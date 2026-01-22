# Unified Makefile for building and deploying webhook images
#
# Build:
#   make docker-build-all      # Build both images
#   make docker-push-all       # Push both images
#
# Prerequisites:
#   make helm-install-cert-manager  # Install cert-manager (required once)
#
# Deploy:
#   make helm-install-hyperv   # Install hyperv webhook
#   make helm-install-hpc      # Install hpc webhook
#   make helm-upgrade-hyperv   # Upgrade hyperv webhook
#   make helm-upgrade-hpc      # Upgrade hpc webhook
#   make helm-template-hyperv  # Preview templates
#
# Config:
#   make config                # Show current REGISTRY and VERSION
#
# Override: make docker-build-all REGISTRY=myregistry.io VERSION=2.0

# Image registry and version (edit here or override on command line)
REGISTRY ?= sigwindowstools
VERSION ?= latest

# Constructed image names
HYPERV_IMG = $(REGISTRY)/hyperv-webhook:$(VERSION)
HPC_IMG = $(REGISTRY)/hpc-webhook:$(VERSION)

# Go version for building images
GOLANG_VERSION ?= 1.24

# Default target - build all images
.PHONY: all
all: docker-build-all

#####################################################################
# Docker image build targets
#####################################################################

# Build both webhook images
.PHONY: docker-build-all
docker-build-all: docker-build-hyperv docker-build-hpc

# Build hyperv webhook image
.PHONY: docker-build-hyperv
docker-build-hyperv:
	@echo "Building hyperv webhook image: $(HYPERV_IMG)"
	docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		-t $(HYPERV_IMG) \
		-f Dockerfile.hyperv \
		.

# Build hpc webhook image
.PHONY: docker-build-hpc
docker-build-hpc:
	@echo "Building hpc webhook image: $(HPC_IMG)"
	docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		-t $(HPC_IMG) \
		-f Dockerfile.hpc \
		.

#####################################################################
# Docker push targets
#####################################################################

# Push both images to registry
.PHONY: docker-push-all
docker-push-all: docker-push-hyperv docker-push-hpc

# Push hyperv webhook image
.PHONY: docker-push-hyperv
docker-push-hyperv: docker-build-hyperv
	@echo "Pushing hyperv webhook image: $(HYPERV_IMG)"
	docker push $(HYPERV_IMG)

# Push hpc webhook image
.PHONY: docker-push-hpc
docker-push-hpc: docker-build-hpc
	@echo "Pushing hpc webhook image: $(HPC_IMG)"
	docker push $(HPC_IMG)

#####################################################################
# Prerequisites
#####################################################################

CERT_MANAGER_VERSION ?= v1.17.2

# Install cert-manager (required before deploying webhooks)
.PHONY: helm-install-cert-manager
helm-install-cert-manager:
	@echo "Installing cert-manager $(CERT_MANAGER_VERSION) via Helm..."
	helm install \
		--repo https://charts.jetstack.io \
		--namespace cert-manager \
		--create-namespace \
		--version $(CERT_MANAGER_VERSION) \
		--set crds.enabled=true \
		--wait \
		cert-manager cert-manager

#####################################################################
# Helm deploy targets
#####################################################################

HELM_COMMON_ARGS = --set deployment.image.registry=$(REGISTRY) --set deployment.image.tag=$(VERSION)

# Deploy hyperv webhook
.PHONY: helm-install-hyperv
helm-install-hyperv:
	helm install hyperv-webhook ./helm -f helm/values-hyperv.yaml $(HELM_COMMON_ARGS) --create-namespace

# Deploy hpc webhook
.PHONY: helm-install-hpc
helm-install-hpc:
	helm install hpc-webhook ./helm -f helm/values-hpc.yaml $(HELM_COMMON_ARGS) --create-namespace

# Upgrade hyperv webhook
.PHONY: helm-upgrade-hyperv
helm-upgrade-hyperv:
	helm upgrade hyperv-webhook ./helm -f helm/values-hyperv.yaml $(HELM_COMMON_ARGS) -n hyperv-webhook

# Upgrade hpc webhook
.PHONY: helm-upgrade-hpc
helm-upgrade-hpc:
	helm upgrade hpc-webhook ./helm -f helm/values-hpc.yaml $(HELM_COMMON_ARGS) -n hpc-webhook

# Template hyperv (dry-run)
.PHONY: helm-template-hyperv
helm-template-hyperv:
	helm template hyperv-webhook ./helm -f helm/values-hyperv.yaml $(HELM_COMMON_ARGS)

# Template hpc (dry-run)
.PHONY: helm-template-hpc
helm-template-hpc:
	helm template hpc-webhook ./helm -f helm/values-hpc.yaml $(HELM_COMMON_ARGS)

#####################################################################
# Utility targets
#####################################################################

# Show current configuration
.PHONY: config
config:
	@echo "REGISTRY: $(REGISTRY)"
	@echo "VERSION:  $(VERSION)"
	@echo "HYPERV_IMG: $(HYPERV_IMG)"
	@echo "HPC_IMG:    $(HPC_IMG)"

# Clean build cache
.PHONY: clean
clean:
	@echo "Cleaning build cache..."
	rm -rf .cache

