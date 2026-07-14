# AgentOS: The Agent Platform That Builds Itself

AgentOS is a secure, scalable platform for running agents. Build agents once and make them available everywhere:

1. **AgentOS UI.** Chat with agents, build new ones with Agent Builder, and inspect sessions, traces, memory, and evals from the AgentOS UI at [os.agno.com](https://os.agno.com?utm_source=github&utm_medium=example-repo&utm_campaign=agentos-helm&utm_content=agentos-helm&utm_term=kubernetes).
2. **Coding agents.** Claude Code and Codex build, test, and improve the platform using the skills in [`.agents/skills/`](.agents/skills/).
3. **AI apps.** Claude and ChatGPT can use your agents through the MCP server at `/mcp`.
4. **Chat interfaces.** Chat with your agents from Slack, WhatsApp, Telegram, and Discord.
5. **Your product.** Embed agents directly into your product with the AgentOS REST API: 80+ endpoints for runs, sessions, memory, knowledge, evals, and more.

<img width="3298" height="2412" alt="AgentOS" src="https://github.com/user-attachments/assets/40a53a42-d4d2-402b-8e92-742609207957" />

Built on [Agno](https://docs.agno.com). Everything runs in your cloud, your data lives in your database.

## Built for agents

This codebase comes with:

- **Two platform agents** that help you build and run the platform from your favorite AI apps like Claude and ChatGPT. **Agent Builder** creates agents, teams, and workflows using the AgentOS Studio. **Platform Manager** understands, monitors, and explains the platform: codebase questions, eval history, deployment checks, schedules.
- **Coding-agent skills** let Claude Code, Codex, Cursor, and other coding agents build, test, and improve the platform automatically — see [Using the platform](#using-the-platform).

Trace data, agent code, evals, and system logs are all available to coding agents, so the platform can inspect and improve itself end to end.

## Get Started

The fastest way to get started is using a coding agent. Copy the prompt below into Claude Code, Cursor or Codex and it'll take you from zero to a running platform.

```text
Help me set up AgentOS on this machine. Work step by step. When a step needs me (an API key, a Docker install, a sign-in), stop, tell me exactly what to do, and wait for my input. Never read or print secrets.

1. Clone https://github.com/agno-agi/agentos-helm.git into a folder called agent-platform and cd in. Then read AGENTS.md end to end — it is the source of truth for how this platform works and answers most questions you'll hit along the way.
2. Run `cp example.env .env`, open .env in my favorite editor, and ask me to set the OPENAI_API_KEY.
3. Confirm docker is installed, running and `docker info` succeeds. If Docker is missing, ask me to install Docker Desktop and wait until it's running.
4. Start the platform with `docker compose up -d --build`, then poll http://localhost:8000/docs until it returns 200 (first build takes a few minutes). If it never comes up, read `docker compose logs agentos-api` and fix what you find.
5. Prove it end to end with ./scripts/mcp_check.sh — it should print "MCP OK" and a real agent answer. Show me that answer: it's my platform talking.
6. Walk me through connecting the AgentOS UI: os.agno.com → Connect OS → http://localhost:8000, named "Local AgentOS". That's where I chat with my agents and inspect sessions, memory, and evals.
7. Finish with a short summary of what's running and where, then point me at building: suggest asking Agent Builder (in the UI) to "Build an agent that tracks AI news and writes a daily brief", or running /create-new-agent right here in this session. Mention in one line — without setting anything up — that the README also covers connecting other frontends: coding agents via `uvx agno connect`, and claude.ai / ChatGPT over OAuth once deployed with a public URL.
```

## Manual Setup

### Step 1: Run locally

> **Prerequisite:** [Docker](https://www.docker.com/get-started/) installed and running.

```sh
git clone https://github.com/agno-agi/agentos-helm.git agentos
cd agentos

# Configure credentials
cp example.env .env
# Open .env and set OPENAI_API_KEY

# Run the platform on docker
docker compose up -d --build
```

Confirm your AgentOS is running at [http://localhost:8000/docs](http://localhost:8000/docs).

### Step 2: Connect the AgentOS UI

1. Open [os.agno.com](https://os.agno.com?utm_source=github&utm_medium=example-repo&utm_campaign=agentos-helm&utm_content=agentos-helm&utm_term=kubernetes) and sign in.
2. Click **Connect OS**, enter `http://localhost:8000` as the URL, name it **Local AgentOS**, and connect.

### Step 3: Build your first agent

1. Click **Chat** under the **Agent Builder** agent and try the first prompt: "Build an agent that tracks AI news and writes a daily brief". Go through the agent development process.
2. Once created, click the **Refresh** button on the top right. You should now see the "Daily AI News Brief" agent in the **Agents** dropdown. Click the newly created agent.
3. Ask: "What's new with Anthropic?"

### Step 4: Check platform health

Click **Chat** under **Platform Manager** and ask: "How healthy is the platform?" It answers from the codebase and runtime data — eval history, deployment checks, schedules, and the component you just built.

## Run in production

You can run the platform anywhere that supports containerized images. This template deploys to any Kubernetes cluster — cloud-managed (EKS, GKE, AKS) or your own — with the Helm chart in [`charts/agentos`](charts/agentos) and a single script.

> **Prerequisites:** [kubectl](https://kubernetes.io/docs/tasks/tools/) pointed at your cluster, [Helm](https://helm.sh/docs/intro/install/) 3+, and a container registry the cluster can pull from.

### 1. Set up your production env

Create a new `.env.production` file for production credentials.

```sh
cp .env .env.production          # or cp example.env .env.production
# Edit .env.production with production values
```

Keeping a separate `.env.production` lets us use different values for local and production: different OpenAI keys, production-only credentials, a different Slack workspace.

### 2. The image

The chart defaults to the official [`agnohq/agentos`](https://hub.docker.com/r/agnohq/agentos) image — the reference platform exactly as in this repo (`latest`, plus `agno-<pin>` tags for exact runtimes). **The moment you customize anything** — a new agent, edited instructions — build and push your own and point the chart at it:

```sh
docker build -t <registry>/agentos:v1 .
docker push <registry>/agentos:v1
```

(Testing on a local [kind](https://kind.sigs.k8s.io) cluster instead? `docker build -t agentos:kind . && kind load docker-image agentos:kind` — see [Local dry run on kind](#local-dry-run-on-kind).)

### 3. Deploy

```sh
./scripts/k8s/up.sh                                              # official image
IMAGE_REPOSITORY=<registry>/agentos IMAGE_TAG=v1 ./scripts/k8s/up.sh   # your own build
```

This helm-installs the chart into the `agentos` namespace of your current kubectl context (the script shows the context and asks first): the API deployment — **one replica by design**, the in-process scheduler must not run twice — plus in-cluster Postgres with pgvector and its volume. The script pauses and asks for a JWT verification key for authentication (see next section). To publish it behind your ingress controller, add `INGRESS_HOST=os.example.com` (and optionally `INGRESS_CLASS=nginx`); `AGENTOS_URL` then points at that host, otherwise the scheduler uses the in-cluster service DNS, which works out of the box.

Bringing your own Postgres instead? It must have the [pgvector](https://github.com/pgvector/pgvector) extension available — install with `postgres.enabled=false` and the `externalDatabase.*` values (see [charts/agentos/values.yaml](charts/agentos/values.yaml)).

### 4. Production Auth

Token-Based Authorization is on by default. Without a `JWT_VERIFICATION_KEY` or `JWT_JWKS_FILE`, the app refuses to serve traffic in production. The platform's job is to keep your data private, so the safe default is "refuse to start" without an authentication token.

Token-Based Auth gives you three things:

1. **No public access.** The server rejects requests without a valid token.
2. **Per-request identity.** Middleware parses the token and extracts the `user_id`, `session_id`, and custom claims. Each request is tied to a user and session, giving you auditability and traceability.
3. **Granular permissions.** User tokens can run an agent and view their own sessions. Admin tokens read everyone's sessions and test any agent.

During `./scripts/k8s/up.sh`, the script pauses so you can mint the key before the app starts.

1. Open [os.agno.com](https://os.agno.com?utm_source=github&utm_medium=example-repo&utm_campaign=agentos-helm&utm_content=agentos-helm&utm_term=kubernetes), click **Connect OS** → **Live**, enter your AgentOS URL (your ingress host — or a tunnel while testing), and connect.
2. Name it **Live AgentOS**.
3. Go to **Settings** → **OS & Security**.
4. Turn **Token-Based Authorization (JWT)** on.
5. Copy the public key.
6. Paste the full public key into the `up.sh` prompt. The script saves it into your env file for future syncs:

```sh
JWT_VERIFICATION_KEY="-----BEGIN PUBLIC KEY-----
MIIBIjANBgkq...
-----END PUBLIC KEY-----"
```

> **Heads up.** Live AgentOS Connections are a paid feature. Use `PLATFORM30` to get 1 month off. We are working on a free trial so you don't have to pay to try.

If you run non-interactively or skip the prompt, you can sync environment variables later with `./scripts/k8s/env-sync.sh`.

### 5. Register your production AgentOS to MCP clients

Re-run `uvx agno connect`, this time pointed at your deployed domain, to connect Claude Code, Claude Desktop, Codex, and Cursor to your production platform:

```sh
uvx agno connect --url https://<your-agentos-domain>
```

For **claude.ai and ChatGPT (web)**: add `https://<your-agentos-domain>/mcp` as a custom connector in the chat app's connector settings. Leave the form's optional OAuth fields (client ID / client secret) empty. Click **Connect** and, on the consent page, enter the `MCP_CONNECT_SECRET` that `up.sh` generated during deploy (saved in `.env.production`; deployed without `INGRESS_HOST`? set `MCP_CONNECT_SECRET` and a public `AGENTOS_URL` in `.env.production` and run `./scripts/k8s/env-sync.sh`).

### 6. Verify

```sh
kubectl rollout status deployment/agentos -n agentos
kubectl logs deploy/agentos -n agentos -f
```

No ingress yet? Port-forward and open [http://localhost:8000/docs](http://localhost:8000/docs):

```sh
kubectl port-forward svc/agentos 8000:8000 -n agentos
```

### 7. Redeploy after code changes

Build and push a new tag, then roll the release to it:

```sh
docker build -t <registry>/agentos:v2 . && docker push <registry>/agentos:v2
IMAGE_TAG=v2 ./scripts/k8s/redeploy.sh
```

Immutable tags keep rollbacks one `helm rollback` away. Re-pushing the same tag and running `./scripts/k8s/redeploy.sh` without `IMAGE_TAG` restarts the pods instead — that only picks up the new image if it actually reached the cluster.

### 8. Sync environment variables

To re-sync environment variables, run the following command:

```sh
./scripts/k8s/env-sync.sh
```

Changed secrets roll the pod automatically (the deployment carries a secret-checksum annotation). The script syncs the connection and secret keys (including `JWT_JWKS_FILE`); other knobs (`ENABLE_DEPLOY_CHECK`, `ENABLE_SCHEDULED_EVALS`, `EVALS_*`) are chart values — set them via `extraEnv` and `helm upgrade`.

### 9. Tear down

```sh
./scripts/k8s/down.sh
```

Uninstalls the release and deletes the database volume, **including all data**. The namespace is kept — it may be shared; the script prints the optional delete command.

### Local dry run on kind

The whole template runs on a laptop-local [kind](https://kind.sigs.k8s.io) cluster — the same flow the family E2E uses:

```sh
kind create cluster --name agentos
docker build -t agentos:kind . && kind load docker-image agentos:kind --name agentos
printf 'RUNTIME_ENV=dev\n' > .env.production && grep '^OPENAI_API_KEY=' .env >> .env.production
IMAGE_REPOSITORY=agentos IMAGE_TAG=kind IMAGE_PULL_POLICY=Never ./scripts/k8s/up.sh
kubectl port-forward svc/agentos 8000:8000 -n agentos   # then open http://localhost:8000/docs
./scripts/k8s/down.sh --yes && kind delete cluster --name agentos && rm .env.production
```

`RUNTIME_ENV=dev` disables JWT so nothing needs minting — never sync a dev env file to a real cluster.

### Opting out of JWT (not recommended)

Set `authorization=False` in [`app/main.py`](app/main.py) and redeploy. Use this only inside a private VPC behind another auth layer. Without it, anyone who reaches your AgentOS URL can access your platform.

## Using the platform

This platform is designed so that coding agents can drive the entire **create → improve → evaluate → maintain** lifecycle for you.

### Create

Open your coding agent of choice (Claude Code, Codex, Cursor) and run:

```
/create-new-agent
```

It asks a few questions, generates the agent file in `agents/`, registers it in `app/main.py`, adds its description and quick prompts to `app/config.yaml`, restarts the container, and smoke-tests it live.

### Improve

Improve your agents by running the following skills:

- **`/extend-agent`** — Add a tool, add a capability, refine the instructions, fix a known bug.
- **`/improve-agent`** — Claude simulates scenarios from the agent's `INSTRUCTIONS`, runs them against the live container, judges the responses, and edits until they pass.

### Evaluate

Run the eval suite to check for regressions. The evals live in [`evals/cases.py`](evals/cases.py), and run history shows up at os.agno.com next to your sessions and traces.

The evals run on the host machine, so set up the venv with `./scripts/venv_setup.sh && source .venv/bin/activate`, then:

```sh
python -m evals --tag smoke      # fast checks of the self-driving surfaces
python -m evals --tag release    # broader pre-release confidence
python -m evals --name <case>    # one case while iterating
python -m evals -v               # stream the full run with rich panels
```

If a case fails, run **`/eval-and-improve`** — it diagnoses each failure, fixes what's in scope, and loops until green.

### Maintain

Because the repo is managed by coding agents, it moves fast. Run `/review-and-improve` before a release or after a refactor: it sweeps for drift between docs, code, and config, auto-fixes mechanical drift like stale paths and missing env vars, and flags anything bigger.

## Connect more frontends (optional)

AgentOS comes with an MCP server at `/mcp` (enabled by setting `mcp_server=True` in [`app/main.py`](app/main.py)), so any MCP client can call your agents, teams, and workflows through tools like `run_agent`, `run_team`, and `run_workflow`.

Register your AgentOS with the MCP clients on your machine:

```sh
uvx agno connect
```

It auto-detects Claude Code, Claude Desktop, Codex, and Cursor and registers `http://localhost:8000/mcp`. After a successful connection, open one of these apps and ask:

```text
can you access my agentos mcp?
```

**claude.ai and ChatGPT (web).** Hosted AI apps reach your platform over the internet and need an OAuth login. Deploy to production (above), add `https://<domain>/mcp` as a remote connector, and approve the consent page with your connect secret.

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | yes | none | OpenAI key for models and embeddings. |
| `RUNTIME_ENV` | no | `prd` | `dev` disables JWT. Compose sets this to `dev` for local — never put `dev` in an env file that env-sync.sh pushes to a real cluster, or production serves unauthenticated. |
| `JWT_VERIFICATION_KEY` | prd | none | Public key from os.agno.com. Required when `RUNTIME_ENV=prd`, unless `JWT_JWKS_FILE` is set. |
| `JWT_JWKS_FILE` | prd | none | Path to a JWKS file; alternative to `JWT_VERIFICATION_KEY` for production JWT verification. |
| `AGENTOS_URL` | no | `http://127.0.0.1:8000` | Scheduler base URL. The chart resolves it automatically (explicit value > ingress URL > in-cluster service DNS); set by hand only for a custom domain or tunnel. Also the public origin OAuth metadata derives from when `MCP_CONNECT_SECRET` is set. |
| `MCP_CONNECT_SECRET` | no | none | If set (≥16 chars, e.g. `openssl rand -base64 32`), `/mcp` becomes its own OAuth 2.1 authorization server so claude.ai and ChatGPT (web) can connect; connecting asks for this secret on a consent page. Requires a public `AGENTOS_URL`. `scripts/k8s/up.sh` auto-generates it when the deploy has a public URL (`INGRESS_HOST` or `AGENTOS_URL`). PAT and JWT bearers keep working alongside. |
| `AGENTOS_MCP_SIGNING_KEY` | no | none | Optional high-entropy signing-key material (≥32 chars) for OAuth tokens. Unset, a strong key is generated and persisted in the database. Rotating it invalidates outstanding tokens. |
| `ENABLE_DEPLOY_CHECK` | no | `True` | The reference deployment-check cron runs daily by default. Set `False` to disable; the workflow is runnable on demand regardless. |
| `ENABLE_SCHEDULED_EVALS` | no | `False` | If `True`, schedules the run-evals workflow daily. Off by default because it uses model calls. |
| `EVALS_TAG` | no | `smoke` | Eval tag run by the run-evals workflow. |
| `EVALS_CASE_TIMEOUT_SECONDS` | no | `90` | Default per-case timeout for run-evals runs; applies only to cases that don't set their own `timeout_seconds`. |
| `EVALS_SUITE_TIMEOUT_SECONDS` | no | `900` | Whole-suite timeout for run-evals runs; per-case timeouts are the granular limit. The default bounds the `smoke` tag's worst case (incl. builder-case teardown). |
| `PARALLEL_API_KEY` | no | none | Authenticates the WebSearch Agent's Parallel SDK / MCP connection. |
| `SLACK_BOT_TOKEN` / `SLACK_SIGNING_SECRET` | no | none | Both must be set to enable the Slack interface. |
| `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASS` / `DB_DATABASE` | no | matches compose | Postgres connection. |
| `DB_DRIVER` | no | `postgresql+psycopg` | SQLAlchemy driver. |
| `AGNO_DEBUG` | no | `False` | If `True`, Agno emits verbose debug logs. Compose sets this for dev. |
| `WAIT_FOR_DB` | no | `False` | If `True`, the entrypoint blocks on the DB before starting. Compose sets this. |

## Learn more

- [Agno documentation](https://docs.agno.com?utm_source=github&utm_medium=example-repo&utm_campaign=agentos-helm&utm_content=agentos-helm&utm_term=kubernetes)
- [AgentOS introduction](https://docs.agno.com/agent-os/introduction?utm_source=github&utm_medium=example-repo&utm_campaign=agentos-helm&utm_content=agentos-helm&utm_term=kubernetes)
- [Agno on GitHub](https://github.com/agno-agi/agno). Drop a star if this is useful.
