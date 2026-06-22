module github.com/danielrispler/wishiz/apps/api

go 1.24.1

require (
	github.com/PuerkitoBio/goquery v1.10.3
	github.com/aws/aws-sdk-go-v2 v1.39.3
	github.com/aws/aws-sdk-go-v2/credentials v1.18.17
	github.com/aws/aws-sdk-go-v2/service/s3 v1.88.5
	github.com/bogdanfinn/fhttp v0.6.8
	// tls-client (built on bogdanfinn/utls + fhttp) powers the anti-bot static
	// fetcher's FULL Chrome fingerprint (JA3/JA4 + HTTP/2). It DELIBERATELY
	// coexists with refraction-networking/utls below (the sitemap worker's
	// TLS-only transport) — two utls forks on purpose; do NOT "consolidate" them.
	github.com/bogdanfinn/tls-client v1.15.1
	github.com/chromedp/cdproto v0.0.0-20241022234722-4d5d5faf59fb
	github.com/chromedp/chromedp v0.11.2
	github.com/jackc/pgx/v5 v5.7.2
	golang.org/x/crypto v0.46.0
)

require (
	github.com/bdandy/go-errors v1.2.2 // indirect
	github.com/bdandy/go-socks4 v1.2.3 // indirect
	github.com/bogdanfinn/quic-go-utls v1.0.9-utls // indirect
	github.com/bogdanfinn/utls v1.7.7-barnius // indirect
	github.com/bogdanfinn/websocket v1.5.5-barnius // indirect
	github.com/quic-go/qpack v0.6.0 // indirect
	github.com/tam7t/hpkp v0.0.0-20160821193359-2b70b4024ed5 // indirect
)

require (
	github.com/andybalholm/brotli v1.2.0
	github.com/andybalholm/cascadia v1.3.3 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.7.2 // indirect
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.4.10 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.7.10 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.4.10 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.13.2 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.9.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.13.10 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.19.10 // indirect
	github.com/aws/smithy-go v1.23.1 // indirect
	github.com/chromedp/sysutil v1.1.0 // indirect
	github.com/gobwas/httphead v0.1.0 // indirect
	github.com/gobwas/pool v0.2.1 // indirect
	github.com/gobwas/ws v1.4.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	github.com/josharian/intern v1.0.0 // indirect
	github.com/klauspost/compress v1.18.2 // indirect
	github.com/mailru/easyjson v0.7.7 // indirect
	// Sitemap-worker TLS transport (httpx.NewUTLSTransport). Coexists on purpose
	// with bogdanfinn/utls (via tls-client above); do NOT consolidate the two.
	github.com/refraction-networking/utls v1.8.2
	golang.org/x/net v0.48.0 // indirect
	golang.org/x/sync v0.19.0 // indirect
	golang.org/x/sys v0.39.0 // indirect
	golang.org/x/text v0.32.0
)
