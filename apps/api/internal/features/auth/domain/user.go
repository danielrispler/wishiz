package domain

import (
	"fmt"
	"time"
)

type Preference string

const (
	PreferenceFashion     Preference = "fashion"
	PreferenceBeauty      Preference = "beauty"
	PreferenceHome        Preference = "home"
	PreferenceAccessories Preference = "accessories"
	PreferenceGifts       Preference = "gifts"
	PreferenceTravel      Preference = "travel"
)

func ParsePreference(s string) (Preference, error) {
	switch Preference(s) {
	case PreferenceFashion, PreferenceBeauty, PreferenceHome,
		PreferenceAccessories, PreferenceGifts, PreferenceTravel:
		return Preference(s), nil
	default:
		return "", fmt.Errorf("unknown preference: %q", s)
	}
}

type User struct {
	ID                    string
	Email                 string
	FullName              string
	Birthday              time.Time
	PreferredCurrencyCode string
	NotificationsEnabled  bool
	ReminderDays          int
	OnboardingCategories  []Preference
	PreferredBrands       []string
	CreatedAt             time.Time
	UpdatedAt             time.Time
}
