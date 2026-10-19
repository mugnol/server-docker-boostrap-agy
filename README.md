# server-bootstrap (Antigravity Edition)

Declarative, Docker-based bootstrap for fresh DigitalOcean droplets.
When a new server is created, its cloud-init `user-data` installs Docker and
Nginx, configures the host firewall (UFW), builds the `devbox` image from this
repository, and starts a container that:

1. Installs every apt package listed in [`tools.txt`](tools.txt) (image build)
2. Installs **Google Antigravity CLI (`agy`)** and Node.js 20 (image build)
3. Clones every repository listed in [`repos.txt`](repos.txt) into `~/projects` (container start)
4. After a one-time Google OAuth login, runs Antigravity with the task in
   [`agy-task.md`](agy-task.md) so each project gets its dependencies
   installed, tested, and started in production mode
5. Exposes port `3001` from the container and proxies standard HTTP port `80`
   (with WebSockets) via Nginx on the host

Everything lives **inside the container** - the host only runs Docker + Nginx.

## Files

| File                        | Purpose                                                          |
| --------------------------- | ---------------------------------------------------------------- |
| `Dockerfile`                | Image definition: Ubuntu 24.04 + Node 20 + tools.txt + `agy` CLI |
| `entrypoint.sh`             | Container startup: config, repo cloning, agent task, server boot |
| `tools.txt`                 | apt packages to install (one per line, `#` comments)             |
| `repos.txt`                 | GitHub repos to clone, `username/repo` per line                  |
| `agy-task.md`               | Instructions Antigravity (`agy`) executes on demand              |
| `nginx-default.conf`        | Host Nginx reverse proxy (:80 -> 127.0.0.1:3001 with WebSockets) |
| `cloud-config.example.yaml` | Droplet user-data template - copy, fill, paste into DO           |

## Usage

1. Edit `tools.txt` and `repos.txt` to match your setup.
2. Copy [`cloud-config.example.yaml`](cloud-config.example.yaml) to a private
   `cloud-config.yaml`, fill in your SSH public key (and optionally `GH_TOKEN`
   for private repos), and paste it into the droplet's **User Data** field
   when creating a DigitalOcean droplet (Ubuntu 24.04).
3. SSH in after boot and check the infrastructure:

   ```bash
   cloud-init status                  # bootstrap finished?
   docker logs -f devbox              # watch the container setup live
   ```

4. Authenticate the agent once with Google OAuth (no API key needed):

   ```bash
   docker exec -it devbox bash        # enter the devbox
   agy                                # choose Google OAuth, open the printed
                                      # URL on your PC, paste the code back
   ```

   The OAuth session is stored in the `devbox-gemini` volume and survives
   container recreation.

5. Run the bootstrap task (inside the container):

   ```bash
   cd ~/projects
   agy --add-dir ~/projects --dangerously-skip-permissions \
       --model "gemini-3.6-flash" -p "$(cat ~/bootstrap/agy-task.md)"
   ```

   Projects land in `~/projects` (backed by the `devbox-projects` volume) and
   the agent report is written to `~/projects/SETUP-REPORT.md`.

## Local usage

The same image works on any machine with Docker:

```bash
docker build -t devbox .
docker run -it --rm devbox bash
# then: agy  (OAuth login)  and work normally
```

## Security notes

- **No AI secrets anywhere.** Authentication is a one-time Google OAuth login
  inside the container; no API key is stored in the repo, the image, or the
  user-data.
- `agy --dangerously-skip-permissions` runs the agent with NO confirmations.
  Only use it with repositories you trust, on disposable machines.
- Private repositories require a fine-grained GitHub PAT (`GH_TOKEN`, with
  Contents Read+Write if the agent should push). With a public bootstrap
  repo, prefer cloning public repos only.
- The container publishes ports 3001/5173 and Nginx exposes port 80 publicly.
  Do not run anything with real secrets or personal data on these ports
  without adding authentication.
