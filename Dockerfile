# syntax=docker/dockerfile:1.4

ARG BUILD_BASE_IMAGE=debian:bookworm
FROM ${BUILD_BASE_IMAGE} AS builder

ARG TARGETARCH
ARG BUILD_NAME=kong
ARG GITHUB_TOKEN

ENV DEBIAN_FRONTEND=noninteractive
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      automake \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      file \
      git \
      gnupg \
      libprotobuf-dev \
      libssl-dev \
      libyaml-dev \
      m4 \
      perl \
      pkg-config \
      procps \
      python3 \
      python3-distutils \
      rustc \
      cargo \
      unzip \
      valgrind \
      xz-utils \
      zlib1g-dev \
      openjdk-17-jre-headless; \
    rm -rf /var/lib/apt/lists/*

# Allow GitHub token based fetches without an interactive gh login
RUN if [ -n "${GITHUB_TOKEN:-}" ]; then \
      git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"; \
      git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"; \
    fi

WORKDIR /src
COPY . .

# Install Bazelisk matching the build architecture
RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    case "$arch" in \
      amd64|x86_64) bazel_arch=amd64 ;; \
      arm64|aarch64) bazel_arch=arm64 ;; \
      *) bazel_arch="$arch" ;; \
    esac; \
    curl -sSL "https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-${bazel_arch}" \
      -o /usr/local/bin/bazel; \
    chmod +x /usr/local/bin/bazel

# Build a release .deb from source; cache Bazel downloads between builds
RUN --mount=type=cache,target=/root/.cache/bazel \
    set -eux; \
    platform_flags=""; \
    if [ "${TARGETARCH:-amd64}" = "arm64" ] || [ "${TARGETARCH:-amd64}" = "aarch64" ]; then \
      platform_flags="--platforms=//:generic-crossbuild-aarch64"; \
    fi; \
    webui_flag="--//:skip_webui=true"; \
    if [ -n "${GITHUB_TOKEN:-}" ]; then \
      webui_flag=""; \
    fi; \
    bazel build //build:kong --verbose_failures --config release \
      --action_env=BUILD_NAME=${BUILD_NAME} \
      --action_env=GITHUB_TOKEN=${GITHUB_TOKEN:-} \
      --action_env=CARGO_NET_GIT_FETCH_WITH_CLI=true \
      ${platform_flags} ${webui_flag}; \
    bazel build //:kong_deb --verbose_failures --config release \
      --action_env=BUILD_NAME=${BUILD_NAME} \
      --action_env=GITHUB_TOKEN=${GITHUB_TOKEN:-} \
      --action_env=CARGO_NET_GIT_FETCH_WITH_CLI=true \
      ${platform_flags} ${webui_flag}; \
    pkg="$(ls bazel-bin/pkg/kong*.deb | head -n1)"; \
    install -Dm644 "$pkg" /tmp/pkg/kong.deb


FROM debian:bookworm-slim

ARG EE_PORTS
ARG KONG_PREFIX=/usr/local/kong

ENV KONG_PREFIX=${KONG_PREFIX}
ENV KONG_DATABASE=off

RUN set -eux; \
    apt-get update; \
    apt-get -y upgrade; \
    apt-get -y autoremove; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libpcre3 \
      libyaml-0-2 \
      perl \
      tzdata; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /tmp/pkg/kong.deb /tmp/kong.deb
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      unzip \
      build-essential \
      /tmp/kong.deb; \
    rm /tmp/kong.deb; \
    rm -rf /var/lib/apt/lists/*; \
#    luarocks install kong-adi-sanction-lists; \
    ln -sf /usr/local/openresty/bin/resty /usr/local/bin/resty; \
    ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit; \
    ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua; \
    ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx; \
    kong version

# Make the third-party plugin available by default
# ENV KONG_PLUGINS=bundled,adi-sanction-lists

COPY build/dockerfiles/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER kong

ENTRYPOINT ["/entrypoint.sh"]

HEALTHCHECK --interval=60s --timeout=10s --retries=10 CMD kong-health

EXPOSE 8000 8443 8001 8444 ${EE_PORTS}

STOPSIGNAL SIGQUIT

CMD ["kong", "docker-start"]
