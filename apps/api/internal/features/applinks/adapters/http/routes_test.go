package applinkshttp

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAssetLinksRouteReturnsAndroidAssociation(t *testing.T) {
	t.Parallel()

	mux := http.NewServeMux()
	RegisterRoutes(mux, sampleOptions())

	request := httptest.NewRequest(http.MethodGet, "/.well-known/assetlinks.json", http.NoBody)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", recorder.Code)
	}

	var payload []struct {
		Target struct {
			PackageName            string   `json:"package_name"`
			SHA256CertFingerprints []string `json:"sha256_cert_fingerprints"`
		} `json:"target"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode assetlinks response: %v", err)
	}

	if payload[0].Target.PackageName != "com.wishiz" {
		t.Fatalf("unexpected package name: %q", payload[0].Target.PackageName)
	}
	if payload[0].Target.SHA256CertFingerprints[0] != sampleOptions().AndroidSHA256CertFingerprint {
		t.Fatalf("unexpected fingerprint: %q", payload[0].Target.SHA256CertFingerprints[0])
	}
}

func TestAppleAssociationRoutesReturnUniversalLinkMetadata(t *testing.T) {
	t.Parallel()

	for _, path := range []string{
		"/apple-app-site-association",
		"/.well-known/apple-app-site-association",
	} {
		mux := http.NewServeMux()
		RegisterRoutes(mux, sampleOptions())

		request := httptest.NewRequest(http.MethodGet, path, http.NoBody)
		recorder := httptest.NewRecorder()
		mux.ServeHTTP(recorder, request)

		if recorder.Code != http.StatusOK {
			t.Fatalf("expected 200 for %s, got %d", path, recorder.Code)
		}

		var payload struct {
			AppLinks struct {
				Details []struct {
					AppID string   `json:"appID"`
					Paths []string `json:"paths"`
				} `json:"details"`
			} `json:"applinks"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
			t.Fatalf("decode AASA response for %s: %v", path, err)
		}

		if payload.AppLinks.Details[0].AppID != sampleOptions().IOSAppID {
			t.Fatalf("unexpected iOS app id for %s: %q", path, payload.AppLinks.Details[0].AppID)
		}
	}
}

func TestWishlistLandingPageContainsHttpsAndCustomSchemeLinks(t *testing.T) {
	t.Parallel()

	mux := http.NewServeMux()
	RegisterRoutes(mux, sampleOptions())

	request := httptest.NewRequest(http.MethodGet, "/lists/wishlist-42", http.NoBody)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", recorder.Code)
	}

	body := recorder.Body.String()
	if !strings.Contains(body, "https://wishiz-api-pdst26qeja-ey.a.run.app/lists/wishlist-42") {
		t.Fatalf("expected landing page to include https share link, got %s", body)
	}
	if !strings.Contains(body, "wishiz://lists/wishlist-42") {
		t.Fatalf("expected landing page to include custom scheme fallback, got %s", body)
	}
	if !strings.Contains(body, "window.location.replace('wishiz:\\/\\/lists\\/wishlist-42')") {
		t.Fatalf("expected landing page to actively attempt app handoff, got %s", body)
	}
}

func TestWishlistLandingPagePreservesInviteToken(t *testing.T) {
	t.Parallel()

	mux := http.NewServeMux()
	RegisterRoutes(mux, sampleOptions())

	request := httptest.NewRequest(http.MethodGet, "/lists/wishlist-42?token=invite-token", http.NoBody)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", recorder.Code)
	}

	body := recorder.Body.String()
	if !strings.Contains(body, "https://wishiz-api-pdst26qeja-ey.a.run.app/lists/wishlist-42?token=invite-token") {
		t.Fatalf("expected landing page to include tokenized https share link, got %s", body)
	}
	if !strings.Contains(body, "wishiz://lists/wishlist-42?token=invite-token") {
		t.Fatalf("expected landing page to include tokenized custom scheme fallback, got %s", body)
	}
	if !strings.Contains(body, "window.location.replace('wishiz:\\/\\/lists\\/wishlist-42?token=invite-token')") {
		t.Fatalf("expected landing page to actively attempt tokenized app handoff, got %s", body)
	}
}

func sampleOptions() Options {
	return Options{
		ShareBaseURL:                 "https://wishiz-api-pdst26qeja-ey.a.run.app",
		AndroidPackageName:           "com.wishiz",
		AndroidSHA256CertFingerprint: "BC:00:5B:70:76:8D:1A:81:0A:82:21:CE:A1:DA:86:6B:F9:1B:0C:2E:52:A4:BD:38:4F:3D:C2:87:AB:F5:1D:3E",
		IOSAppID:                     "P46VR4C98R.com.wishiz",
	}
}
