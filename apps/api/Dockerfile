# syntax=docker/dockerfile:1.7
#
# Local/monolith image (SERVICE_ROLE=all): every route + all in-process
# background loops + boot-migrate, used by docker-compose. The split production
# images are Dockerfile.api (slim) and Dockerfile.scraper (Chromium).

FROM golang:1.25-bookworm AS builder

WORKDIR /src

ARG TARGETOS=linux
ARG TARGETARCH

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/api ./cmd/api

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends chromium ca-certificates fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/api /app/api

EXPOSE 8080

ENV CHROMIUM_PATH=/usr/bin/chromium
ENV SERVICE_ROLE=all

ENTRYPOINT ["/app/api"]
