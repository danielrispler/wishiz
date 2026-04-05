package application

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/ports"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
)

var uuidPattern = regexp.MustCompile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

type Service struct {
	repo  ports.Repository
	nowFn func() time.Time
}

func NewService(repo ports.Repository) *Service {
	return &Service{
		repo:  repo,
		nowFn: time.Now,
	}
}

type CreateWishlistInput struct {
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
	IsShared      bool
}

type PatchWishlistInput struct {
	Title         PatchField[string]
	Description   PatchField[string]
	Year          PatchField[int]
	CoverImageURL PatchField[*string]
	IsShared      PatchField[bool]
}

type AddItemInput struct {
	Title      string
	Notes      *string
	PriceLabel *string
	Priority   string
	Status     string
	ImageURL   *string
	ProductURL *string
}

type PatchItemInput struct {
	Title      PatchField[string]
	Notes      PatchField[*string]
	PriceLabel PatchField[*string]
	Priority   PatchField[string]
	Status     PatchField[string]
	ImageURL   PatchField[*string]
	ProductURL PatchField[*string]
}

type AddSharedUserInput struct {
	Name  string
	Email string
	Role  string
}

func (s *Service) userID(ctx context.Context) string {
	user, ok := authctx.UserFromContext(ctx)
	if !ok {
		return ""
	}
	return user.ID
}

func (s *Service) userEmail(ctx context.Context) string {
	user, ok := authctx.UserFromContext(ctx)
	if !ok {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(user.Email))
}

func (s *Service) checkAccess(ctx context.Context, wishlist domain.Wishlist) error {
	uid := s.userID(ctx)
	if wishlist.OwnerID == uid {
		return nil
	}
	uemail := s.userEmail(ctx)
	if wishlist.IsShared && uemail != "" {
		for _, u := range wishlist.SharedUsers {
			if strings.ToLower(u.Email) == uemail {
				return nil
			}
		}
	}
	return WishlistNotFound()
}

func (s *Service) checkOwner(ctx context.Context, wishlist domain.Wishlist) error {
	if wishlist.OwnerID != s.userID(ctx) {
		return WishlistNotFound()
	}
	return nil
}

func (s *Service) List(ctx context.Context) ([]domain.Wishlist, error) {
	wishlists, err := s.repo.List(ctx, s.userID(ctx), s.userEmail(ctx))
	if err != nil {
		return nil, err
	}

	return ensureWishlists(wishlists), nil
}

func (s *Service) GetByID(ctx context.Context, id string) (domain.Wishlist, error) {
	if err := validateUUID("wishlistId", id); err != nil {
		return domain.Wishlist{}, err
	}

	wishlist, err := s.repo.GetByID(ctx, id)
	if errors.Is(err, ports.ErrNotFound) {
		return domain.Wishlist{}, WishlistNotFound()
	}
	if err != nil {
		return domain.Wishlist{}, err
	}

	if err := s.checkAccess(ctx, wishlist); err != nil {
		return domain.Wishlist{}, err
	}

	return ensureWishlist(wishlist), nil
}

func (s *Service) Create(ctx context.Context, input *CreateWishlistInput) (domain.Wishlist, error) {
	if input == nil {
		return domain.Wishlist{}, ValidationError("input", "input is required")
	}

	title, err := requireTitle(input.Title)
	if err != nil {
		return domain.Wishlist{}, err
	}
	err = validateYear(input.Year)
	if err != nil {
		return domain.Wishlist{}, err
	}

	wishlist, err := s.repo.Create(ctx, ports.CreateWishlistParams{
		OwnerID:       s.userID(ctx),
		Title:         title,
		Description:   normalizeText(input.Description),
		Year:          input.Year,
		CoverImageURL: normalizeOptionalString(input.CoverImageURL),
		IsShared:      input.IsShared,
	})
	if err != nil {
		return domain.Wishlist{}, err
	}

	return ensureWishlist(wishlist), nil
}

func (s *Service) Patch(ctx context.Context, id string, input *PatchWishlistInput) (domain.Wishlist, error) {
	if input == nil {
		return domain.Wishlist{}, ValidationError("input", "input is required")
	}

	current, err := s.GetByID(ctx, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	if ownerErr := s.checkOwner(ctx, current); ownerErr != nil {
		return domain.Wishlist{}, ownerErr
	}

	params := ports.UpdateWishlistParams{
		ID:            current.ID,
		Title:         current.Title,
		Description:   current.Description,
		Year:          current.Year,
		CoverImageURL: cloneString(current.CoverImageURL),
		IsShared:      current.IsShared,
	}

	if input.Title.Set {
		params.Title, err = requireTitle(input.Title.Value)
		if err != nil {
			return domain.Wishlist{}, err
		}
	}
	if input.Description.Set {
		params.Description = normalizeText(input.Description.Value)
	}
	if input.Year.Set {
		if validationErr := validateYear(input.Year.Value); validationErr != nil {
			return domain.Wishlist{}, validationErr
		}
		params.Year = input.Year.Value
	}
	if input.CoverImageURL.Set {
		params.CoverImageURL = normalizeOptionalString(input.CoverImageURL.Value)
	}
	if input.IsShared.Set {
		params.IsShared = input.IsShared.Value
	}

	if _, err := s.repo.Update(ctx, params); errors.Is(err, ports.ErrNotFound) {
		return domain.Wishlist{}, WishlistNotFound()
	} else if err != nil {
		return domain.Wishlist{}, err
	}

	return s.GetByID(ctx, id)
}

func (s *Service) Delete(ctx context.Context, id string) error {
	if err := validateUUID("wishlistId", id); err != nil {
		return err
	}

	current, err := s.GetByID(ctx, id)
	if err != nil {
		return err
	}
	if ownerErr := s.checkOwner(ctx, current); ownerErr != nil {
		return ownerErr
	}

	err = s.repo.Delete(ctx, id)
	if errors.Is(err, ports.ErrNotFound) {
		return WishlistNotFound()
	}
	return err
}

func (s *Service) Archive(ctx context.Context, id string) (domain.Wishlist, error) {
	if err := validateUUID("wishlistId", id); err != nil {
		return domain.Wishlist{}, err
	}

	current, err := s.GetByID(ctx, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	if ownerErr := s.checkOwner(ctx, current); ownerErr != nil {
		return domain.Wishlist{}, ownerErr
	}

	if _, err := s.repo.Archive(ctx, id); errors.Is(err, ports.ErrNotFound) {
		return domain.Wishlist{}, WishlistNotFound()
	} else if err != nil {
		return domain.Wishlist{}, err
	}

	return s.GetByID(ctx, id)
}

func (s *Service) Restore(ctx context.Context, id string) (domain.Wishlist, error) {
	if err := validateUUID("wishlistId", id); err != nil {
		return domain.Wishlist{}, err
	}

	current, err := s.GetByID(ctx, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	if ownerErr := s.checkOwner(ctx, current); ownerErr != nil {
		return domain.Wishlist{}, ownerErr
	}

	if _, err := s.repo.Restore(ctx, id); errors.Is(err, ports.ErrNotFound) {
		return domain.Wishlist{}, WishlistNotFound()
	} else if err != nil {
		return domain.Wishlist{}, err
	}

	return s.GetByID(ctx, id)
}

func (s *Service) AddItem(ctx context.Context, wishlistID string, input *AddItemInput) (domain.WishlistItem, error) {
	if input == nil {
		return domain.WishlistItem{}, ValidationError("input", "input is required")
	}

	current, err := s.GetByID(ctx, wishlistID)
	if err != nil {
		return domain.WishlistItem{}, err
	}
	if ownerErr := s.checkOwner(ctx, current); ownerErr != nil {
		return domain.WishlistItem{}, ownerErr
	}

	title, err := requireTitle(input.Title)
	if err != nil {
		return domain.WishlistItem{}, err
	}
	priority, err := validatePriority(input.Priority)
	if err != nil {
		return domain.WishlistItem{}, err
	}
	status, err := validateStatus(input.Status)
	if err != nil {
		return domain.WishlistItem{}, err
	}

	item, err := s.repo.AddItem(ctx, ports.AddItemParams{
		WishlistID:  wishlistID,
		Title:       title,
		Notes:       normalizeOptionalString(input.Notes),
		PriceLabel:  normalizeOptionalString(input.PriceLabel),
		Priority:    priority,
		Status:      status,
		ImageURL:    normalizeOptionalString(input.ImageURL),
		ProductURL:  normalizeOptionalString(input.ProductURL),
		PurchasedAt: purchasedAtForStatus(status, s.nowFn()),
	})
	if errors.Is(err, ports.ErrNotFound) {
		return domain.WishlistItem{}, WishlistNotFound()
	}
	if err != nil {
		return domain.WishlistItem{}, err
	}

	return item, nil
}

func (s *Service) PatchItem(ctx context.Context, wishlistID, itemID string, input *PatchItemInput) (domain.WishlistItem, error) {
	if input == nil {
		return domain.WishlistItem{}, ValidationError("input", "input is required")
	}

	wishlist, err := s.GetByID(ctx, wishlistID)
	if err != nil {
		return domain.WishlistItem{}, err
	}
	if ownerErr := s.checkOwner(ctx, wishlist); ownerErr != nil {
		return domain.WishlistItem{}, ownerErr
	}
	err = validateUUID("itemId", itemID)
	if err != nil {
		return domain.WishlistItem{}, err
	}

	current, ok := findItem(wishlist.Items, itemID)
	if !ok {
		return domain.WishlistItem{}, ItemNotFound()
	}

	params := ports.UpdateItemParams{
		WishlistID:  wishlistID,
		ItemID:      itemID,
		Title:       current.Title,
		Rank:        current.Rank,
		Notes:       cloneString(current.Notes),
		PriceLabel:  cloneString(current.PriceLabel),
		Priority:    current.Priority,
		Status:      current.Status,
		ImageURL:    cloneString(current.ImageURL),
		ProductURL:  cloneString(current.ProductURL),
		PurchasedAt: cloneTime(current.PurchasedAt),
	}

	if input.Title.Set {
		params.Title, err = requireTitle(input.Title.Value)
		if err != nil {
			return domain.WishlistItem{}, err
		}
	}
	if input.Notes.Set {
		params.Notes = normalizeOptionalString(input.Notes.Value)
	}
	if input.PriceLabel.Set {
		params.PriceLabel = normalizeOptionalString(input.PriceLabel.Value)
	}
	if input.Priority.Set {
		params.Priority, err = validatePriority(input.Priority.Value)
		if err != nil {
			return domain.WishlistItem{}, err
		}
	}
	if input.Status.Set {
		params.Status, err = validateStatus(input.Status.Value)
		if err != nil {
			return domain.WishlistItem{}, err
		}
	}
	if input.ImageURL.Set {
		params.ImageURL = normalizeOptionalString(input.ImageURL.Value)
	}
	if input.ProductURL.Set {
		params.ProductURL = normalizeOptionalString(input.ProductURL.Value)
	}

	params.PurchasedAt = cloneTime(current.PurchasedAt)
	if params.Status == domain.ItemStatusPurchased {
		if current.Status != domain.ItemStatusPurchased {
			params.PurchasedAt = purchasedAtForStatus(params.Status, s.nowFn())
		}
	} else {
		params.PurchasedAt = nil
	}

	item, err := s.repo.UpdateItem(ctx, params)
	if errors.Is(err, ports.ErrNotFound) {
		return domain.WishlistItem{}, ItemNotFound()
	}
	if err != nil {
		return domain.WishlistItem{}, err
	}

	return item, nil
}

func (s *Service) DeleteItem(ctx context.Context, wishlistID, itemID string) error {
	wishlist, err := s.GetByID(ctx, wishlistID)
	if err != nil {
		return err
	}
	if ownerErr := s.checkOwner(ctx, wishlist); ownerErr != nil {
		return ownerErr
	}
	err = validateUUID("itemId", itemID)
	if err != nil {
		return err
	}
	if _, ok := findItem(wishlist.Items, itemID); !ok {
		return ItemNotFound()
	}

	err = s.repo.DeleteItem(ctx, wishlistID, itemID)
	if errors.Is(err, ports.ErrNotFound) {
		return ItemNotFound()
	}
	return err
}

func (s *Service) ReorderItems(ctx context.Context, wishlistID string, orderedItemIDs []string) (domain.Wishlist, error) {
	wishlist, err := s.GetByID(ctx, wishlistID)
	if err != nil {
		return domain.Wishlist{}, err
	}
	if ownerErr := s.checkOwner(ctx, wishlist); ownerErr != nil {
		return domain.Wishlist{}, ownerErr
	}

	existing := make(map[string]domain.WishlistItem, len(wishlist.Items))
	for _, item := range wishlist.Items {
		existing[item.ID] = item
	}

	finalOrder := make([]string, 0, len(wishlist.Items))
	seen := make(map[string]struct{}, len(wishlist.Items))

	for _, itemID := range orderedItemIDs {
		if _, ok := existing[itemID]; !ok {
			continue
		}
		if _, ok := seen[itemID]; ok {
			continue
		}

		seen[itemID] = struct{}{}
		finalOrder = append(finalOrder, itemID)
	}

	for _, item := range wishlist.Items {
		if _, ok := seen[item.ID]; ok {
			continue
		}

		finalOrder = append(finalOrder, item.ID)
	}

	if len(finalOrder) == 0 {
		return wishlist, nil
	}

	if err := s.repo.ReorderItems(ctx, wishlistID, finalOrder); errors.Is(err, ports.ErrNotFound) {
		return domain.Wishlist{}, WishlistNotFound()
	} else if err != nil {
		return domain.Wishlist{}, err
	}

	return s.GetByID(ctx, wishlistID)
}

func (s *Service) AddSharedUser(ctx context.Context, wishlistID string, input *AddSharedUserInput) error {
	if input == nil {
		return ValidationError("input", "input is required")
	}

	wishlist, err := s.GetByID(ctx, wishlistID)
	if err != nil {
		return err
	}
	if ownerErr := s.checkOwner(ctx, wishlist); ownerErr != nil {
		return ownerErr
	}

	name := normalizeText(input.Name)
	if name == "" {
		return ValidationError("name", "name is required")
	}
	email := strings.ToLower(normalizeText(input.Email))
	if email == "" {
		return ValidationError("email", "email is required")
	}

	for _, u := range wishlist.SharedUsers {
		if u.Email == email {
			return nil // Already shared
		}
	}

	err = s.repo.AddSharedUser(ctx, wishlistID, domain.SharedUser{
		Name:  name,
		Email: email,
		Role:  input.Role,
	})
	if errors.Is(err, ports.ErrNotFound) {
		return WishlistNotFound()
	}
	return err
}

func (s *Service) RemoveSharedUser(ctx context.Context, wishlistID, userID string) error {
	wishlist, err := s.GetByID(ctx, wishlistID)
	if err != nil {
		return err
	}
	if ownerErr := s.checkOwner(ctx, wishlist); ownerErr != nil {
		return ownerErr
	}
	if validationErr := validateUUID("userId", userID); validationErr != nil {
		return validationErr
	}

	err = s.repo.RemoveSharedUser(ctx, wishlistID, userID)
	if errors.Is(err, ports.ErrNotFound) {
		return nil // idempotent
	}
	return err
}

func ensureWishlists(wishlists []domain.Wishlist) []domain.Wishlist {
	if wishlists == nil {
		return []domain.Wishlist{}
	}

	for index := range wishlists {
		wishlists[index] = ensureWishlist(wishlists[index])
	}

	return wishlists
}

func ensureWishlist(wishlist domain.Wishlist) domain.Wishlist {
	if wishlist.SharedUsers == nil {
		wishlist.SharedUsers = []domain.SharedUser{}
	}
	if wishlist.Items == nil {
		wishlist.Items = []domain.WishlistItem{}
	}

	return wishlist
}

func requireTitle(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", ValidationError("title", "title is required")
	}

	return trimmed, nil
}

func normalizeText(value string) string {
	return strings.TrimSpace(value)
}

func normalizeOptionalString(value *string) *string {
	if value == nil {
		return nil
	}

	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}

	return &trimmed
}

func validateYear(year int) error {
	if year < 2000 || year > 2100 {
		return ValidationError("year", "year must be between 2000 and 2100")
	}

	return nil
}

func validatePriority(priority string) (string, error) {
	switch strings.TrimSpace(priority) {
	case "", domain.ItemPriorityMedium:
		return domain.ItemPriorityMedium, nil
	case domain.ItemPriorityLow, domain.ItemPriorityHigh:
		return strings.TrimSpace(priority), nil
	default:
		return "", ValidationError("priority", "priority must be one of Low, Medium, or High")
	}
}

func validateStatus(status string) (string, error) {
	switch strings.TrimSpace(status) {
	case "", domain.ItemStatusSaved:
		return domain.ItemStatusSaved, nil
	case domain.ItemStatusConsidering, domain.ItemStatusPurchased:
		return strings.TrimSpace(status), nil
	default:
		return "", ValidationError("status", "status must be one of Saved, Considering, or Purchased")
	}
}

func validateUUID(field string, value string) error {
	if !uuidPattern.MatchString(value) {
		return ValidationError(field, field+" must be a valid UUID")
	}

	return nil
}

func findItem(items []domain.WishlistItem, itemID string) (domain.WishlistItem, bool) {
	for _, item := range items {
		if item.ID == itemID {
			return item, true
		}
	}

	return domain.WishlistItem{}, false
}

func purchasedAtForStatus(status string, now time.Time) *time.Time {
	if status != domain.ItemStatusPurchased {
		return nil
	}

	return &now
}

func cloneString(value *string) *string {
	if value == nil {
		return nil
	}

	copyValue := *value
	return &copyValue
}

func cloneTime(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}

	copyValue := *value
	return &copyValue
}
