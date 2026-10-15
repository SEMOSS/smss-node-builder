FROM public.ecr.aws/docker/library/node:24-alpine3.24

# Keep npm/npx for uploaded app scripts, and install pnpm directly for the
# non-root builder. npm 11.21.0 still bundles two flagged dependency versions,
# so replace those modules using a separately locked installation.
COPY npm-security/package.json npm-security/package-lock.json /tmp/npm-security/
COPY scripts/verify-toolchain.mjs /tmp/verify-toolchain.mjs
RUN corepack disable \
    && npm install --global --ignore-scripts npm@11.21.0 pnpm@11.28.5 \
    && npm ci --prefix /tmp/npm-security --ignore-scripts --no-audit --no-fund \
    && rm -rf /usr/local/lib/node_modules/npm/node_modules/brace-expansion \
        /usr/local/lib/node_modules/npm/node_modules/http-cache-semantics \
        /usr/local/lib/node_modules/npm/node_modules/balanced-match \
    && cp -a /tmp/npm-security/node_modules/brace-expansion \
        /tmp/npm-security/node_modules/http-cache-semantics \
        /tmp/npm-security/node_modules/balanced-match \
        /usr/local/lib/node_modules/npm/node_modules/ \
    && node /tmp/verify-toolchain.mjs \
    && npm cache clean --force \
    && rm -rf /tmp/npm-security /tmp/verify-toolchain.mjs \
        /usr/local/lib/node_modules/corepack /usr/local/bin/corepack \
        /root/.cache/node/corepack

# Uploaded projects must use the image's patched CLI, even if they pin an older pnpm.
ENV PNPM_CONFIG_DANGEROUSLY_ALLOW_ALL_BUILDS=true \
    PNPM_CONFIG_MINIMUM_RELEASE_AGE=0 \
    PNPM_CONFIG_PM_ON_FAIL=ignore

# Install required system utilities
RUN apk upgrade --no-cache \
    && apk add --no-cache zip unzip bash \
        'openssl>=3.5.9-r0' 'libssl3>=3.5.9-r0' 'libcrypto3>=3.5.9-r0'

WORKDIR /app

# Install dependencies first (layer caching)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Copy application source
COPY server.js ./

# Create required runtime directories
RUN mkdir -p /tmp/builds /tmp/uploads

# Create non-root user and set ownership
RUN addgroup -S builder && adduser -S builder -G builder \
    && chown -R builder:builder /tmp/builds /tmp/uploads /app

USER builder

EXPOSE 3000

CMD ["node", "server.js"]
