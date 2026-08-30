## AgentOS: Serve agents over API, MCP, and interfaces like Slack

AgentOS is a durable agent runtime that serves agents over API, MCP, and chat interfaces like Slack. Build customer-facing agents and serve them to your users from your product, through AI apps like Claude and ChatGPT, or interfaces like Slack. AgentOS gives you one agent backend for every frontend.

**Three ways to build agents.**

1. **Coding agent.** Point a coding agent at the skills in [`.agents/skills/`](.agents/skills/) and it can create, improve and evaluate your agents for you.
2. **Natural language.** Ask the built-in Platform Builder to build agents for you.
3. **No-code Studio.** Build agents visually using the [AgentOS Studio](https://os.agno.com?utm_source=github&utm_medium=template&utm_campaign=agentos-helm&utm_term=kubernetes).

**Three ways to serve your agents to your users.**

1. **Your product.** Call the AgentOS REST API from your product.
2. **AI apps.** Connect your agents to Claude and ChatGPT using the AgentOS MCP server.
3. **Chat interfaces.** Distribute your agents through Slack, WhatsApp (and more) using AgentOS Interfaces.

**Monitor and govern your agents.**

The [AgentOS Control Plane](https://os.agno.com?utm_source=github&utm_medium=template&utm_campaign=agentos-helm&utm_term=kubernetes) gives you a unified view of your agent platform. Trace every action. Enforce agent- and tool-level permissions.

<img width="3298" height="2412" alt="AgentOS" src="https://github.com/user-attachments/assets/40a53a42-d4d2-402b-8e92-742609207957" />

<p align="center"><em>Everything runs in your cloud, your data lives in your database.</em></p>

## Get Started

Copy this prompt into your favorite coding agent. It sets up the platform and builds your first agent for you:

```text
Help me set up my agent platform and build my first agent.

Clone https://github.com/agno-agi/agentos-helm into a folder called agent-platform, cd in, and run the setup-platform skill (in .agents/skills/).
```

Your coding agent checks Docker, sets up `.env`, boots the platform, verifies the MCP endpoint, connects to the AgentOS UI, then builds your first agent. Prefer to drive yourself? See [Manual Setup](#manual-setup).

## Manual Setup

### Step 1: Run locally

> **Prerequisite:** [Docker](https://www.docker.com/get-started/) installed and running.

```sh
git clone https://github.com/agno-agi/agentos-helm agentos
cd agentos

# Configure credentials
cp example.env .env
# Open .env and set OPENAI_API_KEY

# Run the platform on docker
docker compose up -d --build
```

Confirm your AgentOS is running at [http://localhost:8000/docs](http://localhost:8000/docs).

### Step 2: Connect the AgentOS UI

1. Open [os.agno.com](https://os.agno.com?utm_source=github&utm_medium=template&utm_campaign=agentos-helm&utm_term=kubernetes) and sign in.
2. Click **Connect OS**, enter `http://localhost:8000` as the URL, name it **Local AgentOS**, and connect.

### Step 3: Build your first agent using natural language

1. Click **Chat** under the **Agno** team and tell it what you're working on: "Help me build an agent for my product".
2. Give it the docs URL for your product, or for a product you like — `docs.agno.com`, say.
3. Click the **Refresh** button on the top right. You should now see your new agent in the **Agents** dropdown. Chat with it directly, or just ask Agno to run it for you.

## Make the platform yours

Your cloned repo points at this public template. Create your own GitHub repo and point your platform at it:

```sh
git remote rename origin upstream    # keep the template connected for updates
git remote add origin <your-private-repo-url>
git push -u origin main
```

> **Heads up.** Create the private repo first ([github.com/new](https://github.com/new), or `gh repo create <name> --private`). Keep `upstream` connected, so that `git pull upstream main` brings in template updates in the future.

## Run in production

You can run the platform anywhere that supports containerized images. This template deploys to any Kubernetes cluster — cloud-managed (EKS, GKE, AKS) or your own — with the Helm chart in [`charts/agentos`](charts/agentos) and a single script; the [`/deploy-platform`](.agents/skills/deploy-platform/SKILL.md) coding-agent skill guides you through it.

> **Prerequisites:** [kubectl](https://kubernetes.io/docs/tasks/tools/) pointed at your cluster, [Helm](https://helm.sh/docs/intro/install/) 3+, a container registry the cluster can pull from, and OpenSSL.

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
3. **Granular permissions.** Scopes on the token decide what each caller can do — run agents, read sessions, manage the platform. Admin tokens can do everything; scoped tokens get exactly what their claims grant.

During `./scripts/k8s/up.sh`, the script pauses so you can mint the key before the app starts.

1. Open [os.agno.com](https://os.agno.com?utm_source=github&utm_medium=template&utm_campaign=agentos-helm&utm_term=kubernetes), click **Connect OS** → **Live**, and enter your AgentOS URL (your ingress host — or a tunnel while testing).
2. Name it **Live AgentOS**, flip **Token-Based Authorization (JWT)** on and connect. The UI generates your public key. (Ran into an issue? Go to **Settings** → **OS & Security** → **Token-Based Authorization (JWT)** to get the key from the settings page.)
3. Copy the public key.
4. Paste the full public key into the `up.sh` prompt. The script saves it into your env file for future syncs:

```sh
JWT_VERIFICATION_KEY="-----BEGIN PUBLIC KEY-----
MIIBIjANBgkq...
-----END PUBLIC KEY-----"
```

If you run non-interactively or skip the prompt, you can sync environment variables later with `./scripts/k8s/env-sync.sh`.

### 5. Verify

```sh
kubectl rollout status deployment/agentos -n agentos
kubectl logs deploy/agentos -n agentos -f
```

No ingress yet? Port-forward and open [http://localhost:8000/docs](http://localhost:8000/docs):

```sh
kubectl port-forward svc/agentos 8000:8000 -n agentos
```

### 6. Connect your AgentOS to MCP clients

AgentOS comes with an MCP server at `/mcp` (wired via `mcp=MCPConfig(...)` in [`app/main.py`](app/main.py)), where Agno itself is published as a first-class `agno` tool — clients just call it, no id discovery. There are two ways to connect your AgentOS to MCP clients:

1. **AI Apps like Claude and ChatGPT** connect to your AgentOS over the internet using OAuth. Add `https://<your-agentos-domain>/mcp` as a custom connector in the chat app's connector settings. Leave the form's optional OAuth fields (client ID / client secret) empty. Click **Connect** and, on the consent page, enter the `MCP_CONNECT_SECRET` that `up.sh` generated during deploy (saved in `.env.production`; deployed without `INGRESS_HOST`? set `MCP_CONNECT_SECRET` and a public `AGENTOS_URL` in `.env.production` and run `./scripts/k8s/env-sync.sh`).
2. **Coding agents like Claude Code, Claude Desktop, Codex, and Cursor** connect to your AgentOS via the MCP URL. Register your AgentOS with the MCP clients on your machine:

```sh
uvx agno connect --url https://<your-agentos-domain>
```

After a successful connection, open one of these apps and ask:

```text
can you access my agentos mcp?
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

Changed secrets roll the pod automatically (the deployment carries a secret-checksum annotation). The script syncs the connection and secret keys (including `JWT_JWKS_FILE`); other knobs (`ENABLE_DEPLOY_CHECK`, `EVALS_*`) are chart values — set them via `extraEnv` and `helm upgrade`.

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

Change `authorization=runtime_env != "dev"` to `authorization=False` in [`app/main.py`](app/main.py) and redeploy. Use this only inside a private VPC behind another auth layer. Without it, anyone who reaches your AgentOS URL can access your platform.

## Using the platform

This platform is designed so that coding agents can drive the entire **create → improve → evaluate → maintain** lifecycle for you.

### Create

Open your coding agent of choice (Claude Code, Codex, Cursor) and run:

```
/create-agent
```

It asks a few questions, generates the agent file in `agents/`, registers it in `app/main.py`, adds its description and quick prompts to `app/config.yaml`, restarts the container, and smoke-tests it for you.

### Improve

Improve your agents by running the following skills:

- **`/extend-agent`** — Add a tool, add a capability, refine the instructions, fix a known bug.
- **`/improve-agent`** — Claude simulates scenarios from the agent's `INSTRUCTIONS` and its real usage recorded in the database, runs them against the live container, judges the responses, and edits until they pass.

### Evaluate

Run the eval suite to check for regressions. The evals live in [`evals/cases.py`](evals/cases.py), and run history shows up in the AgentOS UI next to your sessions and traces.

The evals run on the host machine, so set up the venv with `./scripts/venv_setup.sh && source .venv/bin/activate`, then run:

```sh
python -m evals --tag smoke      # fast checks of the self-driving surfaces
python -m evals --tag release    # broader pre-release confidence
python -m evals --name <case>    # one case while iterating
python -m evals -v               # stream the full run with rich panels
```

If a case fails, run **`/eval-and-improve`** — it diagnoses each failure, fixes what's in scope, and loops until green.

### Maintain

Because the repo is managed by coding agents, it moves fast. Run `/review-and-improve` before a release or after a refactor: it sweeps for drift between docs, code, and config, auto-fixes mechanical drift like stale paths and missing env vars, and flags anything bigger.

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
| `ENABLE_DEPLOY_CHECK` | no | `True` | The reference deployment-check cron runs daily by default. This env var owns the schedule's toggle (re-asserted on every boot); the workflow is runnable on demand regardless. |
| `EVALS_TAG` | no | `smoke` | Eval tag run by the run-evals workflow. |
| `EVALS_CASE_TIMEOUT_SECONDS` | no | `90` | Default per-case timeout for run-evals runs; applies only to cases that don't set their own `timeout_seconds`. |
| `EVALS_SUITE_TIMEOUT_SECONDS` | no | derived | Whole-suite timeout for run-evals runs; per-case timeouts are the granular limit. Unset, it is derived from the cases the tag selects. Set it to override. |
| `PARALLEL_API_KEY` | no | none | Authenticates Agno's and the Studio registry's web search tools (Parallel SDK when set; keyless MCP fallback). Also the fast route for ingesting a product's docs — clean markdown per page, JS-rendered pages and PDFs included; without it ingestion still works, page by page, just slower. |
| `SLACK_BOT_TOKEN` / `SLACK_SIGNING_SECRET` | no | none | Both must be set to enable the Slack interface. The bot token also lights up the registry's send-only Slack toolkit for built agents. |
| `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASS` / `DB_DATABASE` | no | matches compose | Postgres connection. |
| `DB_DRIVER` | no | `postgresql+psycopg` | SQLAlchemy driver. |
| `AGNO_DEBUG` | no | `False` | If `True`, Agno emits verbose debug logs. Compose sets this for dev. |
| `WAIT_FOR_DB` | no | `False` | If `True`, the entrypoint blocks on the DB before starting. Compose sets this. |

## Learn more

- [Agno documentation](https://docs.agno.com?utm_source=github&utm_medium=template&utm_campaign=agentos-helm&utm_term=kubernetes)
- [AgentOS introduction](https://docs.agno.com/agent-os/introduction?utm_source=github&utm_medium=template&utm_campaign=agentos-helm&utm_term=kubernetes)
- [Agno on GitHub](https://github.com/agno-agi/agno). Drop a star if this is useful.
