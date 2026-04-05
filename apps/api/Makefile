.PHONY: test lint

GOLANGCI_LINT_BIN := $(shell go env GOPATH)/bin/golangci-lint

$(GOLANGCI_LINT_BIN):
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.8

test:
	go test ./...

lint: $(GOLANGCI_LINT_BIN)
	$(GOLANGCI_LINT_BIN) run ./...
