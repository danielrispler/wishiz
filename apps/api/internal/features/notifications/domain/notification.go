// Package domain holds the notifications feature's core types: the event-driven
// inbox Notification, FCM DeviceToken registrations, and per-list Mute records.
package domain

import "time"

// Notification types. The set is mirrored exactly by the notifications_type_check
// CHECK in 000001_init_wishlists.up.sql; a drift test enforces equality.
const (
	// TypeListMemberJoined: an invite was accepted -> notify the list owner.
	TypeListMemberJoined = "list_member_joined"
	// TypeItemAdded: an item was added to a shared list -> notify owner + members
	// except the actor.
	TypeItemAdded = "item_added"
	// TypeItemPurchased: an item was marked purchased on a shared list -> notify
	// owner + members except the actor. The owner IS notified deliberately —
	// Wishiz lists are collaborative, not surprise-gift lists.
	TypeItemPurchased = "item_purchased"
	// TypeImportSettled: an import job reached a terminal status -> notify the
	// importer only.
	TypeImportSettled = "import_settled"
)

// AllTypes is the single source of truth for the valid notification types in Go.
// The migration's CHECK constraint must mirror this exactly (drift test enforced).
func AllTypes() []string {
	return []string{
		TypeListMemberJoined,
		TypeItemAdded,
		TypeItemPurchased,
		TypeImportSettled,
	}
}

// Device platforms, mirrored by the device_tokens_platform_check CHECK.
const (
	PlatformIOS     = "ios"
	PlatformAndroid = "android"
)

// Notification is one durable inbox row. It is the source of truth for the inbox
// and the unread badge; the FCM push derived from it is best-effort/advisory.
type Notification struct {
	ID          string
	UserID      string
	Type        string
	Title       string
	Body        string
	WishlistID  *string
	ItemID      *string
	ImportJobID *string
	// ReadAt nil means unread (counts toward the badge). A per-list-muted row is
	// inserted with ReadAt = CreatedAt: visible in history, never badges/pushes.
	ReadAt    *time.Time
	CreatedAt time.Time
}

// DeviceToken is one registered FCM device for a user.
type DeviceToken struct {
	ID         string
	UserID     string
	Token      string
	Platform   string
	CreatedAt  time.Time
	LastSeenAt time.Time
}

// Mute records that a user has silenced notifications for one wishlist.
type Mute struct {
	UserID     string
	WishlistID string
	CreatedAt  time.Time
}
