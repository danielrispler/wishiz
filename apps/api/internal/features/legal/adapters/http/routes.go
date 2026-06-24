// Package legalhttp serves the public, static compliance pages (Privacy Policy
// and Support) required by the Apple App Store and Google Play. They are mounted
// as base routes (every SERVICE_ROLE), so they are reachable wherever the api
// service answers.
package legalhttp

import (
	"html/template"
	"net/http"
)

// Options carries the values rendered into the static legal pages.
type Options struct {
	// SupportEmail is the contact address shown on the support page and in the
	// privacy policy (for data access / deletion requests).
	SupportEmail string
}

// RegisterRoutes mounts GET /privacy and GET /support on the given mux.
func RegisterRoutes(mux *http.ServeMux, options Options) {
	privacy := template.Must(template.New("privacy").Parse(privacyPage))
	support := template.Must(template.New("support").Parse(supportPage))

	data := pageData{
		SupportEmail:    options.SupportEmail,
		SupportEmailURL: template.URL("mailto:" + options.SupportEmail),
	}

	mux.HandleFunc("GET /privacy", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = privacy.Execute(w, data)
	})

	mux.HandleFunc("GET /support", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = support.Execute(w, data)
	})
}

type pageData struct {
	SupportEmail    string
	SupportEmailURL template.URL
}

const pageStyles = `
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; background: #faf4ff; color: #1f2937; line-height: 1.6; }
    main { max-width: 720px; margin: 0 auto; padding: 48px 24px 80px; }
    .card { background: #ffffff; border-radius: 24px; padding: 40px; box-shadow: 0 24px 70px rgba(70, 71, 211, 0.10); }
    .brand { font-weight: 800; letter-spacing: -0.02em; background: linear-gradient(90deg, #4647d3, #9396ff); -webkit-background-clip: text; background-clip: text; color: transparent; }
    h1 { font-size: 32px; margin: 0 0 4px; letter-spacing: -0.02em; }
    h2 { font-size: 20px; margin: 32px 0 8px; }
    p, li { font-size: 16px; }
    a { color: #4647d3; }
    .updated { color: #6b7280; font-size: 14px; margin-top: 0; }
    .email-button { display: inline-block; margin-top: 8px; padding: 14px 22px; border-radius: 999px; background: linear-gradient(90deg, #4647d3, #9396ff); color: #ffffff; text-decoration: none; font-weight: 600; }
    footer { text-align: center; color: #9ca3af; font-size: 13px; margin-top: 32px; }
`

const privacyPage = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Wishiz — Privacy Policy</title>
  <style>` + pageStyles + `</style>
</head>
<body>
  <main>
    <section class="card">
      <h1><span class="brand">Wishiz</span> Privacy Policy</h1>
      <p class="updated">Last updated: June 2026</p>

      <p>Wishiz ("we", "us") is an editorial-style wishlist manager. This policy explains what
      information we collect, why, and the choices you have. We do not sell your personal data,
      and we do not use third-party advertising or tracking.</p>

      <h2>Information we collect</h2>
      <ul>
        <li><strong>Account information</strong> you provide at sign-up: email address, password
        (stored only as a salted hash — never in plain text), full name, date of birth, and an
        optional gender.</li>
        <li><strong>Preferences</strong> such as your preferred currency and notification settings.</li>
        <li><strong>Your content</strong>: the wishlists you create, the product links you import,
        items you save, images you upload, and the people you share a list with.</li>
        <li><strong>Basic technical data</strong> needed to operate the service, such as request logs.</li>
      </ul>

      <h2>How we use your information</h2>
      <ul>
        <li>To create and secure your account and keep you signed in.</li>
        <li>To build, store, and sync your wishlists across your devices.</li>
        <li>To fetch product details (name, price, image) from the public product links you import.</li>
        <li>To share lists with collaborators you explicitly invite.</li>
        <li>To send the notifications and reminders you have enabled.</li>
      </ul>

      <h2>Sharing and service providers</h2>
      <p>We do not sell your data and we do not share it for advertising. We use trusted
      infrastructure providers strictly to run the service — including Google Cloud Platform
      (application hosting, database, and image storage). When you import a product link, our
      servers fetch that publicly accessible page to extract its details; this may involve a
      scraping provider acting only as a technical relay and receiving no personal account data.</p>

      <h2>Data retention</h2>
      <p>We keep your account and content for as long as your account is active. Expired sessions
      and unaccepted invitations are purged automatically.</p>

      <h2>Your rights and choices</h2>
      <p>You can access, correct, export, or delete your personal data and request account deletion
      at any time by emailing <a href="{{.SupportEmailURL}}">{{.SupportEmail}}</a>. We will action
      verified requests promptly.</p>

      <h2>Children</h2>
      <p>Wishiz is not directed to children under 13, and we do not knowingly collect their data.</p>

      <h2>Changes</h2>
      <p>We may update this policy; material changes will be reflected by the "Last updated" date above.</p>

      <h2>Contact</h2>
      <p>Questions about this policy? Email <a href="{{.SupportEmailURL}}">{{.SupportEmail}}</a>.</p>
    </section>
    <footer>© 2026 Daniel Rispler · Wishiz</footer>
  </main>
</body>
</html>`

const supportPage = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Wishiz — Support</title>
  <style>` + pageStyles + `</style>
</head>
<body>
  <main>
    <section class="card">
      <h1><span class="brand">Wishiz</span> Support</h1>
      <p class="updated">We're here to help</p>

      <p>Need a hand with Wishiz — your editorial wishlist manager? Whether it's a question about
      importing a product, sharing a list, your account, or a bug you've spotted, we'd love to hear
      from you.</p>

      <h2>Contact us</h2>
      <p>Email us directly and we'll get back to you as soon as we can, typically within 2 business days.</p>
      <p><a class="email-button" href="{{.SupportEmailURL}}">Email {{.SupportEmail}}</a></p>
      <p>Or write to us at <a href="{{.SupportEmailURL}}">{{.SupportEmail}}</a>.</p>

      <h2>Common topics</h2>
      <ul>
        <li>Importing products from a link</li>
        <li>Creating and sharing wishlists</li>
        <li>Account, sign-in, and password help</li>
        <li>Deleting your account or data</li>
      </ul>

      <p>For details on how we handle your data, see our <a href="/privacy">Privacy Policy</a>.</p>
    </section>
    <footer>© 2026 Daniel Rispler · Wishiz</footer>
  </main>
</body>
</html>`
