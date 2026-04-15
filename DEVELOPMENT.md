# Development Guide

This document explains how the system-agent-installer-k3s image is built in CI and how to build it locally for development and testing.

## Project Overview

This repository builds a minimal Docker image that packages:
- K3s binary (the Kubernetes distribution)
- K3s install script
- SHA256 checksums for verification
- A runtime script (`run.sh`) that handles installation on target hosts

The final image is built `FROM scratch`, containing only these essential files.

## Architecture

### Key Files

| File | Purpose |
|------|---------|
| `scripts/version` | Determines the K3s version/tag to build; sets VERSION, URI_VERSION, IMAGE variables |
| `scripts/download` | Downloads K3s binary + installer script from GitHub releases (or private PRIME_RIBS server) |
| `scripts/publish-manifest` | Creates a multi-architecture Docker manifest for both linux/amd64 and linux/arm64 |
| `package/Dockerfile` | The product Dockerfile; builds the final scratch image with artifacts |
| `package/run.sh` | Runtime entrypoint; copies K3s binary to host and runs the installer |
| `Makefile` | Provides `push-image` and `publish-manifest` targets for CI; contains platform detection |

### CI Build Process

The repository uses **GitHub Actions** for all CI/CD:

#### Release Workflow (`.github/workflows/release.yaml`)

Triggered when a GitHub release is published:

1. **Per-architecture build** (matrix: amd64, arm64):
   - Checkout code
   - Set `ARCH`, `OS`, `GIT_TAG` environment variables
   - Run `scripts/download` to fetch K3s artifacts into `artifacts/` directory
   - Load credentials from Vault (Docker Hub, Prime registries)
   - Run `make push-image` to build and push to:
     - Docker Hub (`rancher/system-agent-installer-k3s:TAG-linux-ARCH`)
     - Rancher Prime Staging registry
     - Rancher Prime Production registry (non-RC releases only)

2. **Multi-architecture manifest** (runs after per-arch builds):
   - Source `scripts/version` to determine the IMAGE tag
   - Run `make publish-manifest` to create a multi-arch manifest linking both per-arch images
   - Manifest is pushed to all three registries

#### Pull Request CI (`.github/workflows/ci-on-pull-request.yaml`)

Triggered on every pull request:

1. **Per-architecture validation** (matrix: amd64, arm64):
   - Checkout code
   - Set `ARCH`, `OS` environment variables
   - Run `scripts/download` to fetch K3s artifacts
   - Set up QEMU and Docker Buildx for cross-platform builds
   - Run `docker/build-push-action` with `--load` to build locally (no push to registry)
   - Inspect the built image

#### Automated Version Detection (`.github/workflows/watch-k3s-releases.yml`)

Runs every 2 hours (or manually) to detect new K3s releases and automatically create GitHub releases, which triggers the Release workflow above.

## Local Development: Building Images

### Prerequisites

- Docker with Buildx support (`docker buildx` available)
- `bash`, `curl`, `jq` installed
- Git (for version detection fallback)

### Determine the K3s Version

The `scripts/version` script determines what version to build. It uses this priority order:

1. **Environment variable `TAG`** (e.g., `TAG=v1.30.0+k3s1`)
2. **GitHub Actions environment** (via `GITHUB_TAG`, `GITHUB_REF_NAME`)
3. **Query GitHub API** for the latest K3s release
4. **Fallback** to `FALLBACK_VERSION` (defined in `scripts/version`)

### Option 1: Build for Your Local Machine

Build a single-arch image that matches your machine's architecture (amd64 or arm64) and load it into your local Docker daemon:

```bash
# Step 1: Download K3s artifacts
TAG=v1.30.0+k3s1 ./scripts/download

# Step 2: Build locally with docker buildx
TAG=v1.30.0+k3s1 docker buildx build \
  --platform linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/') \
  --build-arg TAG=v1.30.0+k3s1 \
  --tag rancher/system-agent-installer-k3s:v1.30.0-k3s1 \
  --load \
  --file ./package/Dockerfile \
  .

# Step 3: Inspect the built image
docker inspect rancher/system-agent-installer-k3s:v1.30.0-k3s1
```

### Option 2: Build for a Specific Architecture

Build for a specific architecture using QEMU:

```bash
# Download artifacts for the target architecture
TAG=v1.30.0+k3s1 ARCH=arm64 ./scripts/download

# Build for arm64 (even if you're on amd64)
TAG=v1.30.0+k3s1 docker buildx build \
  --platform linux/arm64 \
  --build-arg TAG=v1.30.0+k3s1 \
  --tag rancher/system-agent-installer-k3s:v1.30.0-k3s1-linux-arm64 \
  --load \
  --file ./package/Dockerfile \
  .
```

### Option 3: Build Multi-arch Image (Same as CI)

Build for both amd64 and arm64, then create a manifest (requires `docker buildx` and appropriate Docker credentials if pushing):

```bash
# Build amd64
TAG=v1.30.0+k3s1 ARCH=amd64 ./scripts/download
TAG=v1.30.0+k3s1 docker buildx build \
  --platform linux/amd64 \
  --build-arg TAG=v1.30.0+k3s1 \
  --tag rancher/system-agent-installer-k3s:v1.30.0-k3s1-linux-amd64 \
  --push \  # or --load if building for multiple arches
  --file ./package/Dockerfile \
  .

# Build arm64
TAG=v1.30.0+k3s1 ARCH=arm64 ./scripts/download
TAG=v1.30.0+k3s1 docker buildx build \
  --platform linux/arm64 \
  --build-arg TAG=v1.30.0+k3s1 \
  --tag rancher/system-agent-installer-k3s:v1.30.0-k3s1-linux-arm64 \
  --push \
  --file ./package/Dockerfile \
  .

# Create multi-arch manifest
docker buildx imagetools create \
  --tag rancher/system-agent-installer-k3s:v1.30.0-k3s1 \
  rancher/system-agent-installer-k3s:v1.30.0-k3s1-linux-amd64 \
  rancher/system-agent-installer-k3s:v1.30.0-k3s1-linux-arm64
```

### Option 4: Build Without TAG (Uses Latest K3s)

Let `scripts/version` determine the version automatically:

```bash
# This will query GitHub API for the latest K3s release
./scripts/download

# Then build (VERSION will be set by scripts/version fallback)
TAG="" docker buildx build \
  --platform linux/amd64 \
  --tag rancher/system-agent-installer-k3s:latest \
  --load \
  --file ./package/Dockerfile \
  .
```

### Option 5: Build with Local Artifacts

For faster iteration during development, provide pre-downloaded artifacts:

```bash
# Create local artifacts directory
mkdir -p local

# Download what you need (K3s binary, installer.sh, sha256sum file)
# Then place them in local/

# Build using local artifacts (skips downloads)
TAG=v1.30.0+k3s1 LOCAL_ARTIFACTS=true docker buildx build \
  --platform linux/amd64 \
  --build-arg TAG=v1.30.0+k3s1 \
  --tag rancher/system-agent-installer-k3s:v1.30.0-k3s1 \
  --load \
  --file ./package/Dockerfile \
  .
```

## Understanding the Build

### What `scripts/download` Does

Located at `scripts/download`, this script:

1. Sources `scripts/version` to determine VERSION, URI_VERSION, ARCH, OS
2. Creates `artifacts/` directory
3. Downloads K3s install script from GitHub (k3s-io/k3s repository)
4. Downloads K3s binary matching ARCH from either:
   - Private PRIME_RIBS server (if `PRIME_RIBS` env var is set)
   - GitHub k3s-io/k3s releases (default)
5. Downloads corresponding SHA256 checksums
6. Verifies binary integrity via `sha256sum -c`

Outputs: Files placed in `artifacts/` directory (k3s binary, installer.sh, sha256sum file)

### What `package/Dockerfile` Does

Located at `package/Dockerfile`, this is the product Dockerfile:

```dockerfile
FROM scratch
COPY package/run.sh /run.sh
COPY artifacts/* /
```

Builds a minimal scratch image containing:
- K3s binary
- K3s install script
- SHA256 checksum file
- `run.sh` runtime script

### What `package/run.sh` Does

Located at `package/run.sh`, this is the container entrypoint:

1. Copies K3s binary to `/usr/local/bin/k3s` on the host
2. Sets `INSTALL_K3S_SKIP_DOWNLOAD=true` (binary already in place)
3. Runs the K3s install script with retry logic for etcd learner member issues

## Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `TAG` | K3s version to build (e.g., `v1.30.0+k3s1`) | `v1.30.0+k3s1` |
| `ARCH` | Target architecture (amd64, arm64, arm, s390x) | `arm64` |
| `OS` | Target OS (always linux) | `linux` |
| `REPO` | Docker image repository | `rancher` (default), or `your-registry/your-repo` |
| `PRIME_RIBS` | Private artifact server URL (optional) | `https://artifacts.internal/` |
| `LOCAL_ARTIFACTS` | Use artifacts from `local/` directory instead of downloading | `true` |

## Troubleshooting

### "No rule to make target 'build'"

This is expected after removing Dapper. Use the steps above to build locally instead.

### "Binary verification failed"

The SHA256 checksum for the downloaded K3s binary didn't match. This usually means:
- The binary was corrupted during download
- The wrong binary was downloaded for your ARCH
- Network issues

Try deleting `artifacts/` and re-running `scripts/download`.

### "Recursive variable `TAG' references itself"

This error occurs if `TAG` is unset. Always provide `TAG` explicitly or let `scripts/version` query the GitHub API (which it does automatically if `TAG` is empty).
