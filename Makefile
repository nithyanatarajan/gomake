.PHONY: help
help: ## Prints help (only for targets with comments)
	@grep -E '^[a-zA-Z._-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

APP=application
VERSION?=1.0.0
SRC_PACKAGES=$(shell go list -mod=vendor ./... | grep -v "vendor" | grep -v "swagger")
BUILD?=$(shell git describe --always --dirty 2> /dev/null)
GOLINT:=$(shell command -v golint 2> /dev/null)
APP_EXECUTABLE="./out/$(APP)"
RICHGO=$(shell command -v richgo 2> /dev/null)
GOMETA_LINT=$(shell command -v golangci-lint 2> /dev/null)
GOLANGCI_LINT_VERSION=v1.31.0
GO111MODULE=on
SHELL=bash -o pipefail
BUILD_ARGS="-s -w -X main.version=$(VERSION) -X main.build=$(BUILD)

ifeq ($(GOMETA_LINT),)
	GOMETA_LINT=$(shell command -v $(PWD)/bin/golangci-lint 2> /dev/null)
endif

ifeq ($(RICHGO),)
	GO_BINARY=go
else
	GO_BINARY=richgo
endif

ifeq ($(BUILD),)
	BUILD=dev
endif

all: setup build

ci: setup-golangci-lint build-common

ensure-build-dir:
	mkdir -p out

build-deps: ## Install dependencies
	go get
	go mod tidy
	go mod vendor

update-deps: ## Update dependencies
	go get -u

compile: compile-app ## Compile application

compile-app: ensure-build-dir
	$(GO_BINARY) build -mod=vendor -ldflags $(BUILD_ARGS) -o $(APP_EXECUTABLE) ./main.go

install: ## Install application
	go install -mod=vendor -ldflags $(BUILD_ARGS)

compile-linux: ensure-build-dir ## Compile application for linux
	GOOS=linux GOARCH=amd64 $(GO_BINARY) build -mod=vendor -ldflags $(BUILD_ARGS) -o $(APP_EXECUTABLE) ./main.go

build: fmt build-common ## Build the application

build-common: vet lint-all test compile

compress: compile ## Compress the binary
	upx $(APP_EXECUTABLE)

fmt:
	GOFLAGS="-mod=vendor" $(GO_BINARY) fmt $(SRC_PACKAGES)

vet:
	$(GO_BINARY) vet -mod=vendor $(SRC_PACKAGES)

setup-golangci-lint:
ifeq ($(GOMETA_LINT),)
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s $(GOLANGCI_LINT_VERSION)
endif

setup-richgo:
ifeq ($(RICHGO),)
	GO111MODULE=off $(GO_BINARY) get -u github.com/kyoh86/richgo
endif

setup: setup-richgo setup-golangci-lint ensure-build-dir ## Setup environment

lint: setup-golangci-lint
	$(GOMETA_LINT) run -v

test-all: test test.integration

test: ensure-build-dir ## Run tests
	ENVIRONMENT=test $(GO_BINARY) test -mod=vendor $(SRC_PACKAGES) -race -short -v | grep -viE "start|no test files"

test-cover-html: ensure-build-dir ## Run tests with coverage
	ENVIRONMENT=test $(GO_BINARY) test -mod=vendor $(SRC_PACKAGES) -race -coverprofile ./out/coverage -short -v | grep -viE "start|no test files"
	$(GO_BINARY) tool cover -html=./out/coverage -o ./out/coverage.html

test.integration: ensure-build-dir ## Run integration tests
	ENVIRONMENT=test $(GO_BINARY) test -mod=vendor $(SRC_PACKAGES) -tags=integration -short -v | grep -viE "start|no test files"

dev-docker-build: ## Build application server docker image
	docker build --build-arg BUILD_MODE="dev" -f docker/application/Dockerfile -t application .
	@echo "To run:"
	@echo "$ docker run --rm -it -p 5443:5443 --name application application:latest"

dev-docker-run:  ## Run application server in local docker container
	docker run --rm -it -p 5443:5443 --name application application:latest

generate-doc: ## Generate swagger api doc
	go mod vendor
	GO111MODULE=off swagger generate spec -o swagger.json

generate-test-summary:
	ENVIRONMENT=test $(GO_BINARY) test -mod=vendor $(SRC_PACKAGES) -race -coverprofile ./out/coverage -short -v -json | grep -viE "start|no test files" | tee test-summary.json; \
    sed -i '' -E "s/^(.+\| {)/{/" test-summary.json; \
	passed=`cat test-summary.json | jq | rg '"Action": "pass"' | wc -l`; \
	skipped=`cat test-summary.json | jq | rg '"Action": "skip"' | wc -l`; \
	failed=`cat test-summary.json | jq | rg '"Action": "fail"' | wc -l`; \
	echo "Passed: $$passed | Failed: $$failed | Skipped: $$skipped"
