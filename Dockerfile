# server-bootstrap devbox image.
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

# Install Node.js 20 LTS (required for Antigravity CLI & modern web projects)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Pre-create the projects dir with the right owner, so a named volume
# mounted at /home/dev/projects inherits dev:dev instead of root:root
RUN mkdir -p /home/dev/projects && chown dev:dev /home/dev/projects

# Install Google Antigravity CLI (agy) as the dev user
USER dev
WORKDIR /home/dev
RUN mkdir -p /home/dev/.npm-global \
    && npm config set prefix '/home/dev/.npm-global' \
    && (npm install -g @google/antigravity || curl -fsSL https://antigravity.google/install.sh | bash)
ENV PATH="/home/dev/.npm-global/bin:/home/dev/.local/bin:/home/dev/.antigravity/bin:${PATH}"

# Runtime configuration (repos to clone, agent task, startup logic)
COPY --chown=dev:dev repos.txt agy-task.md /home/dev/bootstrap/
COPY --chown=dev:dev entrypoint.sh /home/dev/entrypoint.sh
RUN chmod +x /home/dev/entrypoint.sh

EXPOSE 3001 5173

ENTRYPOINT ["/home/dev/entrypoint.sh"]