UNAME_M = $(shell uname -m)
ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else 
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

TAG ?=
PRIME_RIBS ?=

export DOCKER_BUILDKIT?=1

REPO ?= rancher
IMAGE = $(REPO)/system-agent-installer-k3s:$(TAG)

BUILD_OPTS = \
	--platform=$(TARGET_PLATFORMS) \
	--build-arg TAG=$(TAG) \
	--tag "$(IMAGE)"

.PHONY: push-image
push-image:
	docker buildx build \
		$(BUILD_OPTS) \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--push \
		--file ./package/Dockerfile \
		.

.PHONY: publish-manifest
publish-manifest: ## Create and push the runtime manifest
	IMAGE=$(IMAGE) ./scripts/publish-manifest
