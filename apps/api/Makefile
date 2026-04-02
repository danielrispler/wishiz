.PHONY: test lint

test:
	docker compose -f ../../docker-compose.yml run --rm api-dev go test ./...

lint:
	docker compose -f ../../docker-compose.yml run --rm api-lint golangci-lint run ./...
