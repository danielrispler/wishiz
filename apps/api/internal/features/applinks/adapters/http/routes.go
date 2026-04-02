package applinkshttp

import (
	"fmt"
	"html/template"
	"net/http"
	"strings"
)

type Options struct {
	ShareBaseURL                 string
	AndroidPackageName           string
	AndroidSHA256CertFingerprint string
	IOSAppID                     string
}

func RegisterRoutes(mux *http.ServeMux, options Options) {
	mux.HandleFunc("GET /.well-known/assetlinks.json", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(
			w,
			`[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app","package_name":%q,"sha256_cert_fingerprints":[%q]}}]`,
			options.AndroidPackageName,
			options.AndroidSHA256CertFingerprint,
		)
	})

	mux.HandleFunc("GET /apple-app-site-association", func(w http.ResponseWriter, _ *http.Request) {
		writeAppleAppSiteAssociation(w, options)
	})
	mux.HandleFunc("GET /.well-known/apple-app-site-association", func(w http.ResponseWriter, _ *http.Request) {
		writeAppleAppSiteAssociation(w, options)
	})

	mux.HandleFunc("GET /lists/{wishlistID}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")

		wishlistID := r.PathValue("wishlistID")
		shareBaseURL := strings.TrimRight(options.ShareBaseURL, "/")
		appLink := fmt.Sprintf("%s/lists/%s", shareBaseURL, wishlistID)
		customSchemeLink := fmt.Sprintf("wishiz://lists/%s", wishlistID)

		const page = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open in Wishiz</title>
  <meta http-equiv="refresh" content="0; url={{.CustomSchemeLink}}">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #faf7f2; color: #1f2937; }
    main { max-width: 560px; margin: 0 auto; min-height: 100vh; display: grid; place-content: center; padding: 32px; }
    .card { background: white; border-radius: 24px; padding: 32px; box-shadow: 0 20px 60px rgba(15, 23, 42, 0.08); }
    h1 { margin-top: 0; font-size: 32px; }
    p, a { line-height: 1.5; }
    .button { display: inline-block; margin-top: 12px; padding: 12px 18px; border-radius: 999px; background: #111827; color: white; text-decoration: none; }
    .link { word-break: break-all; }
  </style>
</head>
<body>
  <main>
    <section class="card">
      <h1>Open in Wishiz</h1>
      <p>Wishiz should open automatically if the app is installed.</p>
      <a class="button" href="{{.CustomSchemeLink}}">Open the app</a>
      <p>If nothing happens, make sure the app is installed and try the link again.</p>
      <p class="link">{{.ShareLink}}</p>
    </section>
  </main>
</body>
</html>`

		tmpl := template.Must(template.New("wishlist-landing-page").Parse(page))
		_ = tmpl.Execute(w, struct {
			ShareLink        string
			CustomSchemeLink template.URL
		}{
			ShareLink:        appLink,
			CustomSchemeLink: template.URL(customSchemeLink),
		})
	})
}

func writeAppleAppSiteAssociation(w http.ResponseWriter, options Options) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(
		w,
		`{"applinks":{"apps":[],"details":[{"appID":%q,"paths":["/lists/*"]}]}}`,
		options.IOSAppID,
	)
}
