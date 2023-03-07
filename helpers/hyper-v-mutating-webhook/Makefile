# Image URL to use all building/pushing image targets
IMG ?= sigwindowstools/hyperv-runtimeclass-mutating-webhook:latest

.PHONY: all
all: build

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: build
build: fmt vet ## Build manager binary.
	go build -o bin/manager main.go webhook.go

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	docker build  -t ${IMG} .

.PHONY: docker-push
docker-push: docker-build ## Push docker image with the manager.
	docker push ${IMG}