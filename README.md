# server-bootstrap (Antigravity Edition)

Declarative, Docker-based bootstrap for fresh DigitalOcean droplets.
When a new server is created, its cloud-init `user-data` installs Docker and Nginx,
configures the host firewall (UFW), builds the `devbox` image from this repository, and starts a container that:

1. Installs every apt package listed in [`tools.txt`](tools.txt) (image build)
2. Installs **Google Antigravity CLI (`agy`)** and Node.js 20 (AI coding agent, image build)
3. Clones every repository listed in [`repos.txt`](repos.txt) into `~/projects` (container start)
4. Runs Antigravity unattended with the task in [`agy-task.md`](agy-task.md),
   so each project gets its dependencies installed, tested, and started in production mode
5. Exposes port `3001` from the container and proxies standard HTTP port `80` (with WebSockets) via Nginx on the host

## Files

| File                        | Purpose                                                          |
| --------------------------- | ---------------------------------------------------------------- |
| `Dockerfile`                | Image definition: Ubuntu 24.04 + Node 20 + tools.txt + `agy` CLI |
| `entrypoint.sh`             | Container startup: config, repo cloning, agent task, server boot |
| `tools.txt`                 | apt packages to install (one per line, `#` comments)             |
| `repos.txt`                 | GitHub repos to clone, `username/repo` per line                  |
| `agy-task.md`               | Instructions Antigravity (`agy`) executes on first boot          |
| `nginx-default.conf`        | Host Nginx reverse proxy (:80 -> 127.0.0.1:3001 with WebSockets) |
| `cloud-config.example.yaml` | Droplet user-data template - copy, fill secrets, paste into DO   |

## Usage

1. Edit `tools.txt` and `repos.txt` to match your setup.
2. Copy [`cloud-config.example.yaml`](cloud-config.example.yaml) to a private
   `cloud-config.yaml`, fill in your SSH public key and your `GEMINI_API_KEY`,
   and paste it into the droplet's **User Data** field when creating a
   DigitalOcean droplet (Ubuntu 24.04). **Never commit the filled file.**
3. SSH in after boot and check:

   ```bash
   cloud-init status                  # bootstrap finished?
   docker logs -f devbox              # watch the container setup live
   docker exec -it devbox bash        # enter the devbox, then run: agy