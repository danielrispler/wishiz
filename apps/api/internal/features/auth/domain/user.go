package domain

import "time"

type User struct {
	ID                    string
	Email                 string
	FullName              string
	Birthday              time.Time
	Gender                *string
	PreferredCurrencyCode string
	NotificationsEnabled  bool
	ReminderDays          int
	PreferredBrands       []string
	CreatedAt             time.Time
	UpdatedAt             time.Time
}
