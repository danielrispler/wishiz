package application

import (
	"context"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/ports"
)

// fakeRepo is a configurable ports.Repository double. Unset hooks return zero
// values / nil so tests only wire the methods they exercise.
type fakeRepo struct {
	createUser       func(context.Context, ports.CreateUserParams) (domain.User, error)
	getUserByID      func(context.Context, string) (domain.User, string, error)
	updateUser       func(context.Context, ports.UpdateUserParams) (domain.User, error)
	createSession    func(context.Context, ports.CreateSessionParams) error
	deleteUser       func(context.Context, string) error
	deleteUserCalled bool
}

func (f *fakeRepo) CreateUser(ctx context.Context, p ports.CreateUserParams) (domain.User, error) {
	if f.createUser == nil {
		return domain.User{ID: "new-id"}, nil
	}
	return f.createUser(ctx, p)
}

func (f *fakeRepo) GetUserByEmail(context.Context, string) (domain.User, string, error) {
	return domain.User{}, "", ports.ErrNotFound
}

func (f *fakeRepo) GetUserByID(ctx context.Context, id string) (domain.User, string, error) {
	if f.getUserByID == nil {
		return domain.User{}, "", ports.ErrNotFound
	}
	return f.getUserByID(ctx, id)
}

func (f *fakeRepo) UpdateUser(ctx context.Context, p ports.UpdateUserParams) (domain.User, error) {
	if f.updateUser == nil {
		return domain.User{ID: p.ID, Email: p.Email, FullName: p.FullName, Birthday: p.Birthday}, nil
	}
	return f.updateUser(ctx, p)
}

func (f *fakeRepo) UpdateUserPreferences(context.Context, string, []string) (domain.User, error) {
	return domain.User{}, nil
}

func (f *fakeRepo) CreateSession(ctx context.Context, p ports.CreateSessionParams) error {
	if f.createSession == nil {
		return nil
	}
	return f.createSession(ctx, p)
}

func (f *fakeRepo) GetUserBySessionTokenHash(context.Context, string) (domain.User, error) {
	return domain.User{}, ports.ErrNotFound
}

func (f *fakeRepo) DeleteSessionByTokenHash(context.Context, string) error { return nil }

func (f *fakeRepo) DeleteUser(ctx context.Context, id string) error {
	f.deleteUserCalled = true
	if f.deleteUser == nil {
		return nil
	}
	return f.deleteUser(ctx, id)
}

// recordingGC records the order of its calls so tests can assert that image keys
// are collected before the user is deleted and objects removed after.
type recordingGC struct {
	events *[]string
}

func (g recordingGC) CollectOwnedImageKeys(context.Context, string) []string {
	*g.events = append(*g.events, "collect")
	return []string{"wishlists/abc.jpg"}
}

func (g recordingGC) DeleteObjects(_ context.Context, keys []string) {
	*g.events = append(*g.events, "delete-objects:"+keys[0])
}

func bcryptHash(t *testing.T, password string) string {
	t.Helper()
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	return string(hash)
}

func TestSignUpAllowsMissingBirthday(t *testing.T) {
	t.Parallel()
	var captured ports.CreateUserParams
	repo := &fakeRepo{
		createUser: func(_ context.Context, p ports.CreateUserParams) (domain.User, error) {
			captured = p
			return domain.User{ID: "new-id", Email: p.Email}, nil
		},
	}
	svc := NewService(repo)

	_, _, err := svc.SignUp(context.Background(), &SignUpInput{
		Email:    "a@b.co",
		Password: "pw123456",
		FullName: "A B",
	})
	if err != nil {
		t.Fatalf("signup without birthday should succeed, got %v", err)
	}
	if captured.Birthday != nil {
		t.Fatalf("expected nil birthday persisted, got %v", captured.Birthday)
	}
}

func TestUpdateCurrentUserAllowsMissingBirthday(t *testing.T) {
	t.Parallel()
	birthday := time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC)
	var captured ports.UpdateUserParams
	repo := &fakeRepo{
		getUserByID: func(_ context.Context, id string) (domain.User, string, error) {
			return domain.User{ID: id, Email: "a@b.co", FullName: "A B", Birthday: &birthday}, "hash", nil
		},
		updateUser: func(_ context.Context, p ports.UpdateUserParams) (domain.User, error) {
			captured = p
			return domain.User{ID: p.ID}, nil
		},
	}
	svc := NewService(repo)

	_, err := svc.UpdateCurrentUser(context.Background(), "user-1", &UpdateCurrentUserInput{
		Email:    "a@b.co",
		FullName: "A B",
		Birthday: nil, // user cleared their birthday
	})
	if err != nil {
		t.Fatalf("update without birthday should succeed, got %v", err)
	}
	if captured.Birthday != nil {
		t.Fatalf("expected nil birthday persisted, got %v", captured.Birthday)
	}
}

func TestDeleteAccountHardDeletesAfterPasswordCheck(t *testing.T) {
	t.Parallel()
	var events []string
	repo := &fakeRepo{
		getUserByID: func(_ context.Context, id string) (domain.User, string, error) {
			return domain.User{ID: id}, bcryptHash(t, "correct-horse"), nil
		},
		deleteUser: func(_ context.Context, _ string) error {
			events = append(events, "delete-user")
			return nil
		},
	}
	svc := NewService(repo).WithImageGC(recordingGC{events: &events})

	if err := svc.DeleteAccount(context.Background(), "user-1", "correct-horse"); err != nil {
		t.Fatalf("expected delete to succeed, got %v", err)
	}
	if !repo.deleteUserCalled {
		t.Fatal("expected DeleteUser to be called")
	}
	// Image keys must be collected BEFORE the cascade delete and objects removed
	// AFTER, so a failed delete never orphans live data.
	want := []string{"collect", "delete-user", "delete-objects:wishlists/abc.jpg"}
	if len(events) != len(want) {
		t.Fatalf("unexpected event order %v", events)
	}
	for i := range want {
		if events[i] != want[i] {
			t.Fatalf("event %d = %q, want %q (full: %v)", i, events[i], want[i], events)
		}
	}
}

// signalingGC reports its DeleteObjects keys on a channel so the async-path test
// can wait for the detached goroutine without racing on a shared slice.
type signalingGC struct{ deleted chan []string }

func (g signalingGC) CollectOwnedImageKeys(context.Context, string) []string {
	return []string{"wishlists/async.jpg"}
}

func (g signalingGC) DeleteObjects(_ context.Context, keys []string) {
	g.deleted <- keys
}

func TestDeleteAccountAsyncImageGCDeletesOffRequestPath(t *testing.T) {
	t.Parallel()
	repo := &fakeRepo{
		getUserByID: func(_ context.Context, id string) (domain.User, string, error) {
			return domain.User{ID: id}, bcryptHash(t, "correct-horse"), nil
		},
		deleteUser: func(_ context.Context, _ string) error { return nil },
	}
	gc := signalingGC{deleted: make(chan []string, 1)}
	svc := NewService(repo).WithImageGC(gc).WithImageGCAsync()

	if err := svc.DeleteAccount(context.Background(), "user-1", "correct-horse"); err != nil {
		t.Fatalf("expected delete to succeed, got %v", err)
	}

	// The objects are removed on a detached goroutine after the response returns.
	select {
	case keys := <-gc.deleted:
		if len(keys) != 1 || keys[0] != "wishlists/async.jpg" {
			t.Fatalf("unexpected deleted keys: %v", keys)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("detached DeleteObjects did not run")
	}
}

func TestDeleteAccountRejectsWrongPassword(t *testing.T) {
	t.Parallel()
	repo := &fakeRepo{
		getUserByID: func(_ context.Context, id string) (domain.User, string, error) {
			return domain.User{ID: id}, bcryptHash(t, "correct-horse"), nil
		},
		deleteUser: func(context.Context, string) error {
			t.Fatal("DeleteUser must not be called on wrong password")
			return nil
		},
	}
	svc := NewService(repo)

	err := svc.DeleteAccount(context.Background(), "user-1", "wrong-password")
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeUnauthorized {
		t.Fatalf("expected unauthorized error, got %v", err)
	}
	if repo.deleteUserCalled {
		t.Fatal("DeleteUser was called despite wrong password")
	}
}

func TestDeleteAccountUnknownUserNotFound(t *testing.T) {
	t.Parallel()
	repo := &fakeRepo{
		getUserByID: func(context.Context, string) (domain.User, string, error) {
			return domain.User{}, "", ports.ErrNotFound
		},
	}
	svc := NewService(repo)

	err := svc.DeleteAccount(context.Background(), "ghost", "whatever")
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeNotFound {
		t.Fatalf("expected not_found error, got %v", err)
	}
}

func TestDeleteAccountRequiresPassword(t *testing.T) {
	t.Parallel()
	svc := NewService(&fakeRepo{})

	err := svc.DeleteAccount(context.Background(), "user-1", "  ")
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeValidation {
		t.Fatalf("expected validation error, got %v", err)
	}
}

func TestDeleteAccountWorksWithoutImageGC(t *testing.T) {
	t.Parallel()
	repo := &fakeRepo{
		getUserByID: func(_ context.Context, id string) (domain.User, string, error) {
			return domain.User{ID: id}, bcryptHash(t, "pw"), nil
		},
	}
	svc := NewService(repo) // no WithImageGC

	if err := svc.DeleteAccount(context.Background(), "user-1", "pw"); err != nil {
		t.Fatalf("delete without image GC should succeed, got %v", err)
	}
	if !repo.deleteUserCalled {
		t.Fatal("expected DeleteUser to be called")
	}
}
