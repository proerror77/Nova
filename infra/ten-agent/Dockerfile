# Alice Voice Service - TEN Agent Based
# Built from official TEN Framework image

# ===== Build Stage =====
FROM ghcr.io/ten-framework/ten_agent_build:0.7.12 AS builder

ARG USE_AGENT=agents/examples/voice-assistant

WORKDIR /app

# Clone TEN Agent repository
RUN git clone --depth 1 https://github.com/TEN-framework/TEN-Agent.git /tmp/ten-agent && \
    cp -r /tmp/ten-agent/ai_agents/* /app/ && \
    rm -rf /tmp/ten-agent

# Copy custom configuration
COPY property.json /app/${USE_AGENT}/tenapp/property.json

# Build the agent
RUN cd /app/${USE_AGENT} && \
    task install && task release

# Build playground frontend (optional - not needed for API-only mode)
WORKDIR /app/playground
RUN NEXT_PUBLIC_EDIT_GRAPH_MODE=false bun run build || true
WORKDIR /app

# ===== Production Stage =====
FROM ubuntu:22.04

ARG USE_AGENT=agents/examples/voice-assistant

# Install runtime dependencies
RUN apt-get clean && apt-get update && apt-get install -y --no-install-recommends \
    libasound2 \
    libgstreamer1.0-dev \
    libunwind-dev \
    libc++1 \
    libssl-dev \
    python3 \
    python3-venv \
    python3-pip \
    python3-dev \
    jq \
    ca-certificates \
    curl \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/* && rm -rf /tmp/*

# Install Node.js 20 (for potential frontend serving)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Install Task runner
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /app

# Copy built artifacts from builder
COPY --from=builder /app/${USE_AGENT}/tenapp/.release/ /app/agents/
COPY --from=builder /app/server/bin/api /app/server/bin/api
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/lib/python3 /usr/lib/python3
COPY --from=builder /usr/local/bin/tman /usr/local/bin/tman

# Copy playground (if built)
COPY --from=builder /app/playground/ /app/playground/

# Copy Docker Taskfile
COPY --from=builder /app/${USE_AGENT}/Taskfile.docker.yml /app/Taskfile.docker.yml

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || curl -f http://localhost:8080/ping || exit 1

# Expose ports
EXPOSE 8080 3000

# Run with Taskfile (production mode)
ENTRYPOINT ["task", "-t", "Taskfile.docker.yml", "run-prod"]
