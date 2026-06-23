package main

import (
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/platform/config"
)

// The role predicates decide which slice of the binary runs. They encode the
// scale-to-zero contract: api/scraper services do not start background loops
// (only the all role does), and only scrape-capable roles build the engine.
func TestRolePredicates(t *testing.T) {
	t.Parallel()

	cases := []struct {
		role         string
		needsScrape  bool
		servesAPI    bool
		servesScrape bool
	}{
		{config.RoleAll, true, true, true},
		{config.RoleAPI, false, true, false},
		{config.RoleScraper, true, false, true},
		{config.RoleMigrate, false, false, false},
		{config.RoleWeeklyBatch, true, false, false},
	}

	for _, tc := range cases {
		t.Run(tc.role, func(t *testing.T) {
			t.Parallel()
			if got := roleNeedsScrape(tc.role); got != tc.needsScrape {
				t.Errorf("roleNeedsScrape(%q) = %v, want %v", tc.role, got, tc.needsScrape)
			}
			if got := roleServesAPI(tc.role); got != tc.servesAPI {
				t.Errorf("roleServesAPI(%q) = %v, want %v", tc.role, got, tc.servesAPI)
			}
			if got := roleServesScrape(tc.role); got != tc.servesScrape {
				t.Errorf("roleServesScrape(%q) = %v, want %v", tc.role, got, tc.servesScrape)
			}
		})
	}
}
