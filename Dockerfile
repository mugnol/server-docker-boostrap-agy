# server-bootstrap devbox image (Antigravity Edition).
# Contains: all tools from tools.txt + Node.js 20 + Google Antigravity CLI (agy).
# Projects are cloned and configured at container START (see entrypoint.sh),
# so no secrets or repos are baked into the image.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Create the dev user with passwordless sudo
RUN useradd -m -s /bin/bash dev \
    && apt-get update \
    && apt-get install -y sudo curl ca-certificates gnupg \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && rm -rf /var/lib/apt/lists/*

# Install the tools listed in tools.txt.
# Note: docker.io is skipped here - it only makes sense on the host.
COPY tools.txt /tmp/tools.txt
RUN apt-get update \
    && grep -vE '^\s*(#|$)' /tmp/tools.txt | grep -v '^docker\.io$' | xargs apt-get install -y \
    && rm -rf /var/lib/apt/lists/* /tmp/tools.txt

# Install Node.js 20 LTS (needed by modern web projects; agy itself is a
# native binary and does NOT need Node)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Pre-create the projects, gemini, and ai-memory dirs with the right owner, so named
# volumes mounted there inherit dev:dev instead of root:root
RUN mkdir -p /home/dev/projects /home/dev/.gemini /home/dev/.local/share/ai-memory \
    && chown -R dev:dev /home/dev/projects /home/dev/.gemini /home/dev/.local/share/ai-memory

# User-level npm prefix (lets the agent npm-install without sudo)
USER dev
WORKDIR /home/dev
RUN mkdir -p /home/dev/.npm-global \
    && npm config set prefix '/home/dev/.npm-global'

# Install Google Antigravity CLI (agy) - single native binary, official
# installer only. There is NO npm package for it.
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
ENV PATH="/home/dev/.npm-global/bin:/home/dev/.local/bin:${PATH}"

# Install ai-memory CLI - shared long-term memory for coding agents
RUN curl -fsSL https://github.com/akitaonrails/ai-memory/releases/latest/download/install.sh | sh

# Runtime configuration (repos to clone, agent task, startup logic)
COPY --chown=dev:dev repos.txt agy-task.md /home/dev/bootstrap/
COPY --chown=dev:dev entrypoint.sh /home/dev/entrypoint.sh
RUN chmod +x /home/dev/entrypoint.sh

EXPOSE 3001 5173

ENTRYPOINT ["/home/dev/entrypoint.sh"]
