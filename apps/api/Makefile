.PHONY: test lint

GOLANGCI_LINT_BIN := $(shell go env GOPATH)/bin/golangci-lint

$(GOLANGCI_LINT_BIN):
	go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.11.4

test:
	go test ./...

lint: $(GOLANGCI_LINT_BIN)
	$(GOLANGCI_LINT_BIN) run ./...
