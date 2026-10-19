\# Bootstrap task for Google Antigravity (agy)



You are running unattended on a freshly provisioned Ubuntu container (`devbox`).

The directory `\~/projects` contains repositories cloned from GitHub.



For EACH project in `\~/projects`:



1\. Read the README (and any `package.json` / `requirements.txt` / `go.mod` / `Cargo.toml`)

&#x20;  to identify the stack.

2\. Install its dependencies:

&#x20;  - Node.js: `npm install` (or the package manager the repo uses)

&#x20;  - Python: create a `.venv` and `pip install -r requirements.txt`

&#x20;  - Other stacks: follow the README instructions

3\. If a `.env.example` exists and `.env` does not, copy it to `.env` (ensure `COOKIE\_SECURE=false` and `HOST=0.0.0.0` if applicable for HTTP IP testing).

4\. If the project uses Prisma (`prisma/schema.prisma`), run `npx prisma generate` and `npx prisma db push` (plus any seed command defined in `package.json`).

5\. Run the project's build (`npm run build`) and unit/integration tests (`npm test`) to validate the installation.

&#x20;  If a step fails, try to fix it once; if it still fails, note it and move on.

6\. Start production server (if applicable):

&#x20;  - If the project has a `./start-production.sh` or `./scripts/start-production.sh` script, execute it to start the server in the background.

&#x20;  - CRITICAL: Any background daemon/server MUST be started fully detached (`setsid ... > /tmp/<project>.log 2>\&1 < /dev/null \&`) so open stdout/stderr pipes do not hang this headless subshell.

&#x20;  - Verify the server is responding locally (e.g., `curl -i http://127.0.0.1:3001/api/health`).



Rules:

\- Do NOT commit or push anything to git.

\- Do NOT install anything globally with sudo.

\- Do NOT modify system configuration.



When finished, write a summary report to `\~/projects/SETUP-REPORT.md` listing,

for each project: what was installed, whether build/tests passed, whether the production server is running (with its port and health check status), and any issues that need manual attention.

