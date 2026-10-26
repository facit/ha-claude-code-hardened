ARG BUILD_FROM
FROM ${BUILD_FROM}

# Labels
LABEL maintainer="Robson Felix"
LABEL org.opencontainers.image.title="Claude Code for Home Assistant"
LABEL org.opencontainers.image.description="Claude Code CLI with web terminal and HA integration"
LABEL org.opencontainers.image.source="https://github.com/robsonfelix/robsonfelix-hass-addons"
LABEL org.opencontainers.image.licenses="MIT"

# Environment setup
ENV \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

# Install system dependencies (ttyd installed separately as static binary)
RUN apk add --no-cache \
    bash \
    curl \
    git \
    github-cli \
    jq \
    nodejs \
    npm \
    openssh-client \
    libstdc++ \
    ncurses \
    vim \
    nano \
    tmux \
    coreutils \
    findutils \
    grep \
    sed \
    gawk \
    ca-certificates \
    openssl \
    ripgrep \
    p7zip \
    socat \
    nginx \
    && update-ca-certificates

# Install ttyd static binary (avoids libwebsockets issues), checked against the
# SHA256SUMS published with the 1.7.7 release
ARG BUILD_ARCH
RUN case "${BUILD_ARCH}" in \
        amd64) TTYD_ARCH="x86_64"; TTYD_SHA256="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55" ;; \
        aarch64) TTYD_ARCH="aarch64"; TTYD_SHA256="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165" ;; \
        armv7|armhf) TTYD_ARCH="armhf"; TTYD_SHA256="8240c8438b68d3b10b0e1a4e7c914d70fca6a7606b516f40bf40adfa1044d801" ;; \
        i386) TTYD_ARCH="i686"; TTYD_SHA256="93e112e19c9c0dcc717e98bdba0f43fc50f0c74ae1ba5b572772c507654ed19c" ;; \
        *) echo "Unsupported arch ${BUILD_ARCH}"; exit 1 ;; \
    esac && \
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
        "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" -o /usr/bin/ttyd && \
    echo "${TTYD_SHA256}  /usr/bin/ttyd" | sha256sum -c - && \
    chmod +x /usr/bin/ttyd

# Install Claude Code.
# 2.1.113 replaced the JS entrypoint with a Bun-compiled native binary, whose
# JavaScriptCore requires AVX. Hosts that lack it - notably VMs exposing the
# generic kvm64 CPU model - cannot run 2.1.113+ (it deadlocks or dies with
# SIGILL). Fix that at the hypervisor (Proxmox CPU type "host"), not here.
# No version is hardcoded: take latest when it runs, otherwise the newest
# release that passes a smoke test, so the add-on still builds on such hosts.
COPY install-claude.sh /usr/local/bin/install-claude.sh
RUN chmod +x /usr/local/bin/install-claude.sh && /usr/local/bin/install-claude.sh

# Install hass-mcp for Home Assistant integration and pymodbus for Modbus operations.
# Pinned: hass-mcp runs with the Supervisor token in its environment.
RUN pip3 install --no-cache-dir --break-system-packages \
    hass-mcp==0.6.1 pymodbus==3.16.1 pyserial==3.5

# Install mbpoll (Modbus command line tool) from source
RUN apk add --no-cache --virtual .build-deps \
    build-base \
    cmake \
    libmodbus-dev \
    && git clone --branch v1.5.4 --depth 1 https://github.com/epsilonrt/mbpoll.git /tmp/mbpoll \
    && cd /tmp/mbpoll \
    && test "$(git rev-parse HEAD)" = d541211d0e2451888de11c82fb1604c3d6285b1a \
    && mkdir build && cd build \
    && cmake .. \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/mbpoll \
    && apk del .build-deps \
    && apk add --no-cache libmodbus

# Pre-cache Playwright MCP server (npx cache avoids /usr/local/bin/mcp conflict with hass-mcp)
ENV NPM_CONFIG_CACHE=/root/.npm
RUN npx @playwright/mcp@0.0.83 --version || true

# Install Home Assistant CLI (ha command)
# Pinned and retried: a transient DNS failure used to abort the whole build
# (curl exit 6). Upstream publishes only amd64 and aarch64, so other arches skip
# the CLI with a warning instead of failing the build on a 404. Upstream
# publishes no checksums; these were recorded from the 5.2.0 release assets.
ARG HA_CLI_VERSION=5.2.0
RUN case "${BUILD_ARCH}" in \
        amd64|aarch64) \
            case "${BUILD_ARCH}" in \
                amd64) HA_SHA256="701be67aee9f1e092254097a40d006b450d1578641a262258b182237987e7479" ;; \
                aarch64) HA_SHA256="af8c03ccddb65d223d7b7dab1570197b8a2ff8fc7139c1db054d08a91a4f8073" ;; \
            esac && \
            curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
                "https://github.com/home-assistant/cli/releases/download/${HA_CLI_VERSION}/ha_${BUILD_ARCH}" \
                -o /usr/local/bin/ha && \
            echo "${HA_SHA256}  /usr/local/bin/ha" | sha256sum -c - && \
            chmod +x /usr/local/bin/ha ;; \
        *) \
            echo "[WARN] Home Assistant CLI is not published for ${BUILD_ARCH}; the 'ha' command will be unavailable" ;; \
    esac

# Create necessary directories (NOT /root/.claude - will be symlinked at runtime)
RUN mkdir -p \
    /homeassistant \
    /root/.config \
    /root/.local/bin

# Shell and tmux config.
# These were heredocs (RUN cat > file << 'EOF'), which require BuildKit and a
# `# syntax=docker/dockerfile:1.4` directive. Builders without heredoc support
# parsed the body as Dockerfile instructions ("unknown instruction: set").
# COPY works on every builder and needs no syntax image.
COPY rootfs/root/.tmux.conf /root/.tmux.conf
COPY rootfs/root/.bashrc /root/.bashrc

# Add-on instructions for Claude, loaded as the managed CLAUDE.md so the user's
# own ~/.claude/CLAUDE.md is never overwritten. nginx fronts the terminal.
COPY rootfs/etc/claude-code/CLAUDE.md /etc/claude-code/CLAUDE.md
COPY rootfs/etc/nginx/claudecode.conf /etc/nginx/claudecode.conf
COPY rootfs/usr/local/bin/claudecode-start.sh /usr/local/bin/claudecode-start.sh
RUN chmod +x /usr/local/bin/claudecode-start.sh

# Ensure .bashrc is sourced for login shells too
RUN echo 'source ~/.bashrc' > /root/.profile

# Set up PATH
ENV PATH="/root/.local/bin:${PATH}"

# Set working directory
WORKDIR /homeassistant

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://127.0.0.1:7681/ || exit 1

ENTRYPOINT []
CMD ["/usr/local/bin/claudecode-start.sh"]
