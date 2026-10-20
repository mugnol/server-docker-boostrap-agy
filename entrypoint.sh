#!/bin/bash
# Container entrypoint: runs every time the devbox container starts.
# Auth model: one-time Google OAuth login inside the container (see README).
# Optional fallback: if GEMINI_API_KEY is set, API key mode is configured
# automatically for fully unattended runs.
set -euo pipefail

BOOTSTRAP_DIR="$HOME/bootstrap"

# Git identity and push credentials, so the agent can commit and push.
# GIT_USER_NAME / GIT_USER_EMAIL have defaults; GH_TOKEN / GITHUB_TOKEN is optional
# but required for cloning private repos and pushing to git.
git config --global user.name "${GIT_USER_NAME:-devbox-agent}"
git config --global user.email "${GIT_USER_EMAIL:-devbox@localhost}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -n "${GH_TOKEN:-}" ]; then
  git config --global credential.helper store
  AUTH_USER="${GIT_USER_NAME:-x-access-token}"
  echo "https://${AUTH_USER}:${GH_TOKEN}@github.com" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
fi

# Antigravity (agy) configuration: default to Flash model and always-proceed permissions.
AGY_CONFIG_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS_FILE="$AGY_CONFIG_DIR/settings.json"
DEFAULT_MODEL="${AGY_MODEL:-Gemini 3.8 Flash (Medium)}"

mkdir -p "$AGY_CONFIG_DIR"

if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" <<EOF
{
  "model": "$DEFAULT_MODEL",
  "toolPermission": "always-proceed"
}
EOF
else
  if command -v jq >/dev/null 2>&1; then
    tmp_settings=$(mktemp)
    jq --arg model "$DEFAULT_MODEL" '.model = $model | .toolPermission = "always-proceed"' "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"
  fi
fi

# Optional API key mode (fallback for fully unattended runs).
# GEMINI_API_KEY alone has no effect: agy also needs modelProvider=gemini.
if [ -n "${GEMINI_API_KEY:-}" ]; then
  if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS_FILE" ]; then
    tmp_settings=$(mktemp)
    jq '.modelProvider = "gemini"' "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"
  fi
fi

# 1. Clone the projects listed in repos.txt (skips projects already cloned)
#    The sudo chown fixes named volumes that were created with root ownership
mkdir -p "$HOME/projects" "$HOME/.local/share/ai-memory"
sudo chown -R dev:dev "$HOME/projects" "$HOME/.gemini" "$HOME/.local/share/ai-memory" 2>/dev/null || true

# 2. Configure and start ai-memory (shared long-term memory for coding agents)
if command -v ai-memory >/dev/null 2>&1; then
  echo "Setting up ai-memory for antigravity-cli..."
  ai-memory setup --yes --no-service --agent antigravity-cli || true

  if ! pgrep -f "ai-memory serve" >/dev/null; then
    echo "Starting ai-memory server..."
    nohup ai-memory serve --transport http --enable-web > "$HOME/.local/share/ai-memory/ai-memory.log" 2>&1 &
    for _ in $(seq 1 10); do
      if curl -s http://127.0.0.1:49374/healthz >/dev/null; then
        echo "ai-memory server is healthy."
        break
      fi
      sleep 0.5
    done
  fi
fi

while read -r repo || [ -n "$repo" ]; do
  repo=$(echo "$repo" | sed 's/#.*//' | xargs)
  [[ -z "$repo" ]] && continue
  name=$(basename "$repo")
  if [ -d "$HOME/projects/$name/.git" ]; then
    echo "Already cloned, pulling latest changes: $name"
    (cd "$HOME/projects/$name" && git pull --ff-only) || true
    continue
  fi
  url="https://github.com/${repo}.git"
  if ! git clone "$url" "$HOME/projects/$name"; then
    if [ -n "${GH_TOKEN:-}" ]; then
      echo "Retrying clone with embedded token for $name..."
      git clone "https://${GH_TOKEN}@github.com/${repo}.git" "$HOME/projects/$name" || true
    fi
  fi
done < "$BOOTSTRAP_DIR/repos.txt"

# 2. Optionally let Antigravity (agy) install, test, and start the projects.
#    Requires auth: either GEMINI_API_KEY set, or a previous OAuth login
#    (stored in the devbox-gemini volume). RUN_AGY_TASK defaults to false
#    because a fresh container has no credentials yet - log in once, then
#    either run the task manually or restart with RUN_AGY_TASK=true.
#    --add-dir is required: without it, print mode works in a scratch dir.
#    --dangerously-skip-permissions is required for unattended execution.
#    AGY_MODEL: free API keys have NO quota for Pro models (error 429
#    "limit: 0"). Flash models (e.g. gemini-3.8-flash-medium) work on free tier.
if [ "${RUN_AGY_TASK:-false}" = "true" ] && [ -f "$BOOTSTRAP_DIR/agy-task.md" ]; then
  echo "Running Antigravity (agy) bootstrap task (log: ~/projects/agy-bootstrap.log)..."
  (cd "$HOME/projects" && agy --add-dir "$HOME/projects" --dangerously-skip-permissions \
    --model "${AGY_CLI_MODEL:-gemini-3.8-flash-medium}" \
    -p "$(cat "$BOOTSTRAP_DIR/agy-task.md")") \
    > "$HOME/projects/agy-bootstrap.log" 2>&1 || true
  echo "Antigravity task finished. See ~/projects/SETUP-REPORT.md"
  if command -v ai-memory >/dev/null 2>&1; then
    ai-memory finalize-session --agent antigravity-cli 2>/dev/null || true
  fi
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
