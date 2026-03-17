# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DeerFlow 2.0 is an open-source "super agent harness" that orchestrates sub-agents, memory, and sandboxes to execute complex tasks - powered by extensible skills.

**Stack**:
- Backend: Python 3.12, LangGraph + FastAPI, uv
- Frontend: Next.js 16, React 19, TypeScript 5.8, Tailwind CSS 4, pnpm 10.26.2
- Proxy: nginx (unified entry point)

**Architecture**:
```
Browser → Nginx (2026) → Frontend (3000) / Gateway API (8001) / LangGraph Server (2024)
```

## Commands

### Root Directory (Full Application)

```bash
make check        # Verify system requirements (Node.js 22+, pnpm, uv, nginx)
make install      # Install all dependencies (frontend + backend)
make config       # Generate config.yaml from config.example.yaml (first-time setup)
make dev          # Start all services with hot-reload (localhost:2026)
make stop         # Stop all services
make clean        # Stop services and clean up temp files
```

### Docker Development (Recommended)

```bash
make docker-init    # Pull sandbox image (first-time setup)
make docker-start   # Start Docker dev environment (localhost:2026)
make docker-stop    # Stop Docker services
make docker-logs    # View all Docker logs
```

### Backend Directory (`backend/`)

```bash
make install      # Install backend dependencies (uv sync)
make dev          # Run LangGraph server only (port 2024)
make gateway      # Run Gateway API only (port 8001)
make test         # Run all backend tests (uv run pytest)
make lint         # Lint with ruff
make format       # Format with ruff
```

### Frontend Directory (`frontend/`)

```bash
pnpm dev          # Dev server with Turbopack (port 3000)
pnpm build        # Production build (requires BETTER_AUTH_SECRET)
pnpm lint         # ESLint
pnpm typecheck    # TypeScript check
```

## Project Structure

```
deer-flow/
├── Makefile                     # Root commands
├── config.yaml                  # Main configuration (gitignored)
├── config.example.yaml          # Configuration template
├── extensions_config.json       # MCP servers and skills config
├── scripts/                     # Shell scripts for dev/deploy
├── docker/                      # Docker compose and nginx config
├── backend/                     # Python backend
│   ├── Makefile                # Backend commands
│   ├── langgraph.json          # LangGraph entry point
│   ├── packages/harness/       # deerflow-harness package
│   │   └── deerflow/           # Core framework (import: deerflow.*)
│   │       ├── agents/         # Lead agent, middlewares, memory
│   │       ├── sandbox/        # Sandbox execution system
│   │       ├── subagents/      # Subagent delegation
│   │       ├── tools/          # Built-in tools
│   │       ├── mcp/            # MCP integration
│   │       ├── models/         # Model factory
│   │       ├── skills/         # Skills loading
│   │       ├── config/         # Configuration system
│   │       └── client.py       # Embedded Python client
│   ├── app/                    # Application layer (import: app.*)
│   │   ├── gateway/            # FastAPI Gateway API
│   │   └── channels/           # IM integrations (Feishu, Slack, Telegram)
│   └── tests/                  # Test suite
├── frontend/                    # Next.js frontend
│   └── src/
│       ├── app/                # Next.js routes
│       ├── components/         # React components
│       └── core/               # Business logic (threads, api, artifacts)
└── skills/                      # Agent skills
    ├── public/                 # Built-in skills (committed)
    └── custom/                 # Custom skills (gitignored)
```

## Key Architecture Concepts

### Harness / App Split

The backend has a strict dependency boundary:
- **Harness** (`packages/harness/deerflow/`): Publishable framework package. Import prefix: `deerflow.*`
- **App** (`app/`): Application code. Import prefix: `app.*`
- **Rule**: App can import deerflow, but deerflow MUST NOT import app (enforced by `tests/test_harness_boundary.py` in CI)

### Middleware Chain

Middlewares execute in strict order (see `backend/packages/harness/deerflow/agents/lead_agent/agent.py`):
1. ThreadDataMiddleware - Create per-thread directories
2. UploadsMiddleware - Track uploaded files
3. SandboxMiddleware - Acquire sandbox environment
4. DanglingToolCallMiddleware - Handle interrupted tool calls
5. SummarizationMiddleware - Context reduction (optional)
6. TodoListMiddleware - Task tracking (plan mode)
7. TitleMiddleware - Auto-generate thread titles
8. MemoryMiddleware - Queue conversations for memory update
9. ViewImageMiddleware - Vision model support
10. SubagentLimitMiddleware - Limit concurrent subagents
11. ClarificationMiddleware - Handle clarification requests (must be last)

### Sandbox System

- **Virtual paths**: Agent sees `/mnt/user-data/{workspace,uploads,outputs}`, `/mnt/skills`
- **Physical paths**: `backend/.deer-flow/threads/{thread_id}/user-data/...`, `deer-flow/skills/`
- **Providers**: LocalSandboxProvider (dev) or AioSandboxProvider (Docker, production)

### Configuration

**Main config** (`config.yaml` in project root):
- Models: LLM configs with `use` class path, `supports_thinking`, `supports_vision`
- Tools: Tool configs with `use` variable path and `group`
- Sandbox: `sandbox.use` for provider class path
- Memory, summarization, subagents settings

**Extensions config** (`extensions_config.json` in project root):
- `mcpServers`: MCP server configurations
- `skills`: Skill enabled/disabled state

Config values starting with `$` are resolved as environment variables.

## Development Workflow

1. **First-time setup**:
   ```bash
   make config      # Create config.yaml
   # Edit config.yaml to add your model API keys
   make install     # Install dependencies
   ```

2. **Run application**:
   ```bash
   make dev         # Start all services at localhost:2026
   ```

3. **Before committing**:
   ```bash
   # Backend
   cd backend && make lint && make test

   # Frontend
   cd frontend && pnpm lint && pnpm typecheck
   ```

## Important Notes

- `make config` aborts if `config.yaml` already exists (non-idempotent by design)
- `pnpm build` requires `BETTER_AUTH_SECRET` environment variable
- Frontend `pnpm check` is broken; use `pnpm lint` and `pnpm typecheck` separately
- Run `make stop` to clean up processes if `make dev` is interrupted
