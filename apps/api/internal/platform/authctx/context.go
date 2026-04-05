package authctx

import "context"

type contextKey string

const userKey contextKey = "authenticated-user"

type User struct {
	ID    string
	Email string
}

func WithUser(ctx context.Context, user User) context.Context {
	return context.WithValue(ctx, userKey, user)
}

func UserFromContext(ctx context.Context) (User, bool) {
	user, ok := ctx.Value(userKey).(User)
	return user, ok
}
