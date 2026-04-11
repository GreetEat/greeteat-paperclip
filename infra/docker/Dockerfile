# syntax=docker/dockerfile:1.7
# =============================================================================
# Paperclip container image for the GreetEat GCP deployment.
# =============================================================================
# Built by .github/workflows/build-image.yml from a pinned upstream Paperclip
# release tag (PAPERCLIP_VERSION build arg). Pushed to Artifact Registry as:
#   us-central1-docker.pkg.dev/paperclip-492823/paperclip/paperclip:<tag>
#
# The image MUST contain ZERO secret material at any layer. All secrets are
# resolved at runtime by Cloud Run from Secret Manager via the task spec's
# `secrets` field — never baked in.
#
# NOTE: This is a first-cut Dockerfile based on Paperclip's documented
# Node + pnpm + Drizzle stack. The build/start commands assume Paperclip's
# package.json exposes `pnpm build` and `pnpm start` (or equivalent). The
# first CI build will reveal any necessary adjustments — refine in a PR
# rather than guessing here.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: build — clone Paperclip at the pinned tag and produce a built tree
# -----------------------------------------------------------------------------
FROM node:20-bookworm-slim AS build

ARG PAPERCLIP_VERSION
ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git

# Build prerequisites: git for cloning, build-essential for any native
# Node modules that need compilation, ca-certificates for HTTPS git.
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      ca-certificates \
      python3 \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

# Enable pnpm via corepack (Paperclip's developer guide uses pnpm)
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /build

# Refuse to build without an explicit version pin
RUN test -n "${PAPERCLIP_VERSION}" || \
    (echo "ERROR: PAPERCLIP_VERSION build arg is required" >&2 && exit 1)

# Clone Paperclip at the pinned tag (depth=1 for speed; we don't need history)
RUN git clone --depth 1 --branch "${PAPERCLIP_VERSION}" "${PAPERCLIP_REPO}" .

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build Paperclip (TypeScript -> dist + Vite -> ui/dist)
RUN pnpm build

# Prune dev dependencies after build to shrink the runtime layer
RUN pnpm prune --prod

# -----------------------------------------------------------------------------
# Stage 2: runtime — minimal image, non-root user, no build tools
# -----------------------------------------------------------------------------
FROM node:20-bookworm-slim AS runtime

# Runtime essentials only
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd --system --gid 1001 paperclip && \
    useradd  --system --uid 1001 --gid paperclip --create-home --home-dir /home/paperclip paperclip

# Enable pnpm in the runtime stage too — entrypoint uses `pnpm start`
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Copy the built Paperclip tree from the build stage
COPY --from=build --chown=paperclip:paperclip /build /app

# Entrypoint script (validates env, runs migrations, exec's the server)
COPY --chown=paperclip:paperclip infra/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER paperclip
ENV NODE_ENV=production \
    PAPERCLIP_HOME=/home/paperclip/.paperclip

# Cloud Run injects PORT (default 8080); Paperclip's PORT env var honors
# it directly. We additionally set HOST=0.0.0.0 in the Cloud Run service
# env so Paperclip binds to the right interface.
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
