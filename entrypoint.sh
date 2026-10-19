#!/bin/bash
# Container entrypoint: runs every time the devbox container starts.
# Expects GEMINI_API_KEY environment variable for unattended Antigravity (agy) runs.
set -euo pipefail

BOOTSTRAP_DIR="$HOME/bootstrap"

# Git identity and push credentials, so the agent can commit and push.
# GIT_USER_NAME / GIT_USER_EMAIL have defaults; GH_TOKEN is optional but
# required for pushing (needs Contents: Read and Write on the repo).
git config --global user.name "${GIT_USER_NAME:-devbox-agent}"
git config --global user.email "${GIT_USER_EMAIL:-devbox@localhost}"
if [ -n "${GH_TOKEN:-}" ]; then
  git config --global credential.helper store
  echo "https://x-access-token:${GH_TOKEN}@github.com" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
fi

# Antigravity CLI headless auth: GEMINI_API_KEY alone has no effect.
# The settings.json below selects the Gemini API provider.
if [ -n "${GEMINI_API_KEY:-}" ]; then
  mkdir -p "$HOME/.gemini/antigravity-cli"
  cat > "$HOME/.gemini/antigravity-cli/settings.json" <<EOF
{
  "modelProvider": "gemini"
}
EOF
else
  echo "WARNING: GEMINI_API_KEY is not set. Unattended agy task will be skipped."
fi

# 1. Clone the projects listed in repos.txt (skips projects already cloned)
#    The sudo chown fixes volumes that were created with root ownership
mkdir -p "$HOME/projects"
sudo chown dev:dev "$HOME/projects" 2>/dev/null || true
while read -r repo || [ -n "$repo" ]; do
  repo=$(echo "$repo" | sed 's/#.*//' | xargs)
  [[ -z "$repo" ]] && continue
  name=$(basename "$repo")
  if [ -d "$HOME/projects/$name/.git" ]; then
    echo "Already cloned, pulling latest changes: $name"
    (cd "$HOME/projects/$name" && git pull --ff-only) || true
    continue
  fi
  if [ -n "${GH_TOKEN:-}" ]; then
    url="https://${GH_TOKEN}@github.com/${repo}.git"
  else
    url="https://github.com/${repo}.git"
  fi
  git clone "$url" "$HOME/projects/$name" || true
done < "$BOOTSTRAP_DIR/repos.txt"

# 2. Optionally let Antigravity (agy) install, test, and start the projects.
#    Set -e RUN_AGY_TASK=false to skip (e.g. when you only want a shell).
#    --add-dir is required: without it, print mode works in a scratch dir.
#    --dangerously-skip-permissions is required for unattended execution.
if [ "${RUN_AGY_TASK:-true}" = "true" ] && [ -f "$BOOTSTRAP_DIR/agy-task.md" ] && [ -n "${GEMINI_API_KEY:-}" ]; then
  echo "Running Antigravity (agy) bootstrap task (log: ~/projects/agy-bootstrap.log)..."
  (cd "$HOME/projects" && agy --add-dir "$HOME/projects" --dangerously-skip-permissions \
    -p "$(cat "$BOOTSTRAP_DIR/agy-task.md")") \
    > "$HOME/projects/agy-bootstrap.log" 2>&1 || true
  echo "Antigravity task finished. See ~/projects/SETUP-REPORT.md"
fi

# 3. Ensure any project with start-production.sh is running (survives container restarts)
for proj_dir in "$HOME/projects"/*/; do
  [ -d "$proj_dir" ] || continue
  if [ -f "${proj_dir}start-production.sh" ]; then
    echo "Starting production service in $proj_dir..."
    (cd "$proj_dir" && chmod +x start-production.sh && ./start-production.sh) || true
  fi
done

# 4. Keep the container alive for interactive use:
#    docker exec -it devbox bash
echo "Devbox is ready."
exec sleep infinity
