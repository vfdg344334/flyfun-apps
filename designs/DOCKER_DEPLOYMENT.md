# Docker Deployment Guide

## Overview

This document describes the Docker deployment setup for the Euro AIP application, including the web server and MCP server.

## Architecture

The deployment consists of:
- **Web Server**: FastAPI application serving the web UI and API
  - Runs as non-root user (UID 2000, user `flyfun`)
  - Dockerfile: `web/Dockerfile`
  - Port: 8000 (host) → 8000 (container)
- **MCP Server**: Model Context Protocol server for LLM integration
  - Runs as non-root user (UID 2001, user `flyfun-mcp`)
  - Dockerfile: `mcp_server/Dockerfile`
- **ChromaDB Service**: Vector database for RAG (Retrieval-Augmented Generation)
  - Official ChromaDB image: `chromadb/chroma:latest`
  - Port: 8001 (host) → 8000 (container)
  - Internal service URL: `http://chromadb:8000` (for container-to-container communication)
- **Shared Data**: Mounted volumes for data files, output, cache, and logs

## Directory Structure

```
.
├── web/
│   └── Dockerfile          # Web server container
├── mcp_server/
│   └── Dockerfile          # MCP server container
├── docker-compose.yml      # Orchestration (includes ChromaDB service)
├── .env                    # Environment configuration (create from env.sample)
├── env.sample              # Template for .env
├── .dockerignore           # Files to exclude from builds
├── data/                   # Data files (read-only in containers)
│   ├── airports.db         # Airport database (required)
│   └── rules.json          # Aviation rules JSON (required)
├── out/                    # Output files (writable in containers)
│   ├── ga_meta.sqlite      # GA friendliness database (build artifact)
│   ├── rules_vector_db/    # Local vector DB (if not using ChromaDB service)
│   └── chromadb_data/      # ChromaDB persistent storage (created automatically)
└── logs/                   # Log files (writable in containers)
```

## Quick Start (Brand New Server Setup)

This section provides step-by-step instructions for setting up the application on a brand new server.

### 1. Prerequisites

- Docker and Docker Compose installed
- Git (to clone the repository)
- Required data files (see below)

### 2. Clone Repository and Prepare Directories

```bash
# Clone the repository
git clone <repository-url>
cd flyfun-apps/main

# Create required directories
mkdir -p data out logs

# Set permissions for writable directories
# Option 1: World-writable (simple, less secure - OK for development)
chmod 777 out logs

# Option 2: Specific ownership (more secure - for production)
# sudo chown -R 2000:2000 out logs
# chmod 755 out logs
```

### 3. Prepare Required Data Files

You need these files in the `data/` directory:

#### a) airports.db
- **Location**: `data/airports.db`
- **Source**: Provided with the repository (may be in Git LFS)
- **Size**: ~7.5MB
- **Verification**: `ls -lh data/airports.db`

#### b) rules.json
- **Location**: `data/rules.json`
- **Source**: Generated from Excel files using `tools/xls_to_rules.py` (see below)
- **Verification**: `ls -lh data/rules.json`

### 4. Prepare Optional Data Files

#### a) ga_meta.sqlite (GA Friendliness Database)
- **Location**: `out/ga_meta.sqlite`
- **Source**: Built using `tools/build_ga_friendliness.py` (see below)
- **Note**: This is optional but recommended for GA friendliness features
- **If you have an existing file**: Copy it to `out/ga_meta.sqlite`

#### b) ChromaDB Vector Database
- **Location**: Built automatically in ChromaDB service
- **Source**: Built from `rules.json` using `tools/xls_to_rules.py` (see below)
- **Note**: In Docker, ChromaDB service handles this automatically

### 5. Configure Environment

```bash
# Copy environment template
cp env.sample .env

# Edit .env with your configuration
nano .env  # or use your preferred editor
```

**Required settings in `.env`:**

```bash
# API Keys (REQUIRED)
OPENAI_API_KEY=your-openai-api-key-here

# Optional API Keys
GEOAPIFY_API_KEY=your-geoapify-key  # Optional, for geocoding
LANGCHAIN_API_KEY=your-langsmith-key  # Optional, for tracing

# Environment
ENVIRONMENT=production  # or 'development'

# Logging
LOG_LEVEL=INFO

# Aviation Agent
AVIATION_AGENT_ENABLED=1
AVIATION_AGENT_PLANNER_MODEL=gpt-4o-mini
AVIATION_AGENT_FORMATTER_MODEL=gpt-4o-mini

# Note: Paths are automatically set by docker-compose.yml to container paths
# You don't need to set these, but if you do, use container paths:
# AIRPORTS_DB=/app/data/airports.db
# RULES_JSON=/app/data/rules.json
# GA_META_DB=/app/out/ga_meta.sqlite
# VECTOR_DB_URL=http://chromadb:8000  # For Docker (set automatically)
# VECTOR_DB_PATH=/app/out/rules_vector_db  # For local mode (fallback)
```

**Important Notes:**
- The `docker-compose.yml` automatically sets container paths, so you don't need to configure paths in `.env` for Docker
- `VECTOR_DB_URL` is automatically set to `http://chromadb:8000` in Docker
- `WORKING_DIR` is not used in Docker - ignore it

### 6. Build and Start Services

```bash
# Build all images (web-server, mcp-server)
docker-compose build

# Start all services (web-server, mcp-server, chromadb)
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f

# View logs for specific service
docker-compose logs -f web-server
docker-compose logs -f chromadb
```

### 7. Build Vector Database (ChromaDB)

After starting services, you need to build the vector database from `rules.json`:

```bash
# Option 1: Build inside the web-server container (recommended)
docker exec -it flyfun-web-server python tools/xls_to_rules.py \
    --out /app/data/rules.json \
    --build-rag

# Option 2: Build from host (if rules.json is updated)
# First, ensure rules.json exists in data/
docker exec -it flyfun-web-server python tools/xls_to_rules.py \
    --out /app/data/rules.json \
    --vector-db-url http://chromadb:8000 \
    --build-rag
```

**Note**: The vector database is built in the ChromaDB service, not as a local file. The data persists in `out/chromadb_data/` volume.

### 8. Verify Setup

```bash
# Check web server health
curl http://localhost:8000/health

# Check ChromaDB health (from host)
curl http://localhost:8001/api/v1/heartbeat

# Check all services are running
docker-compose ps

# Check logs for errors
docker-compose logs --tail=50
```

### 9. (Optional) Build GA Meta Database

If you have airfield.directory export data:

```bash
# Build ga_meta.sqlite (run on host or in container)
# This requires the build_ga_friendliness.py tool and export data
docker exec -it flyfun-web-server python tools/build_ga_friendliness.py \
    --export /path/to/export.json \
    --output /app/out/ga_meta.sqlite
```

**Note**: The `ga_meta.sqlite` file should be placed in `out/ga_meta.sqlite` on the host, which is mounted into containers.

## Configuration

### Environment Variables

All configuration is done through the `.env` file at the project root. Key variables:

**Important:** Paths in `.env` should use **container paths** when running in Docker (e.g., `/app/data/airports.db`), not host paths. The `docker-compose.yml` automatically overrides paths to use container paths, but it's best to set them correctly in `.env` for clarity.

#### Common
- `ENVIRONMENT`: `development` or `production`
- `AIRPORTS_DB`: Path to airports database (inside container: `/app/data/airports.db`)
- `RULES_JSON`: Path to rules JSON (inside container: `/app/data/rules.json`)
- `LOG_LEVEL`: Logging level (`DEBUG`, `INFO`, `WARNING`, `ERROR`)

#### Web Server
- `WEB_PORT`: Port to expose (default: `8000`)
- `GA_META_DB`: Path to GA meta database (default: `/app/out/ga_meta.sqlite`)
- `GA_META_READONLY`: Whether GA database is read-only (default: `true`)
- `AVIATION_AGENT_ENABLED`: Enable aviation agent (default: `true`)
- `VECTOR_DB_URL`: ChromaDB service URL (default: `http://chromadb:8000` in Docker)
- `VECTOR_DB_PATH`: Local vector DB path (fallback if `VECTOR_DB_URL` not set)
- `EMBEDDING_MODEL`: Embedding model for RAG (default: `all-MiniLM-L6-v2`)

#### ChromaDB Service
- `CHROMADB_PORT`: External port mapping (default: `8001`)
- `CHROMADB_AUTH_TOKEN`: Authentication token (optional, default: `test-token`)
- `CHROMADB_DATA_DIR`: Persistent data directory (default: `./out/chromadb_data`)

#### MCP Server
- `AIRPORTS_DB`: Path to airports database (inside container: `/app/data/airports.db`)
- `RULES_JSON`: Path to rules JSON (inside container: `/app/data/rules.json`)
- `LOG_LEVEL`: Logging level (`DEBUG`, `INFO`, `WARNING`, `ERROR`)

#### Security
- `OPENAI_API_KEY`: OpenAI API key (required)

### Volume Mappings

The `docker-compose.yml` maps host directories to container paths:

| Host Directory | Container Path | Purpose | Access |
|---------------|---------------|---------|--------|
| `./data` | `/app/data` | Data files (airports.db, rules.json) | Read-only |
| `./out` | `/app/out` | Output files (ga_meta.sqlite, chromadb_data) | Read-write |
| `./logs` | `/app/logs` | Log files | Read-write |
| `./out/chromadb_data` | `/chroma/chroma` | ChromaDB persistent storage | Read-write |

You can customize these in `.env`:
```bash
DATA_DIR=./data
OUTPUT_DIR=./out
LOGS_DIR=./logs
CHROMADB_DATA_DIR=./out/chromadb_data
```

## Data Files

### Required Files

1. **airports.db**: Airport database (SQLite)
   - Location: `data/airports.db`
   - Size: ~7.5MB (stored in Git LFS)
   - Read-only in containers

2. **rules.json**: Aviation rules metadata
   - Location: `data/rules.json`
   - Read-only in containers

### Output Files

1. **ga_meta.sqlite**: GA friendliness database
   - Location: `out/ga_meta.sqlite` (created by build tools)
   - Read-write in containers (if `GA_META_READONLY=false`)
   - Read-only in production web server (default)

2. **ChromaDB Vector Database**: Rules vector database for RAG
   - **Service Mode (Docker)**: Data stored in `out/chromadb_data/` (ChromaDB service)
   - **Local Mode**: Data stored in `out/rules_vector_db/` (if `VECTOR_DB_URL` not set)
   - **Building**: Use `tools/xls_to_rules.py --build-rag` to build from `rules.json`
   - **Note**: In Docker, ChromaDB service handles persistence automatically

## Building Images

### Web Server

```bash
docker build -f web/Dockerfile -t flyfun-web-server .
```

### MCP Server

```bash
docker build -f mcp_server/Dockerfile -t flyfun-mcp-server .
```

### Both (via docker-compose)

```bash
docker-compose build
```

## Running Services

### Start All Services

```bash
docker-compose up -d
```

### Start Individual Services

```bash
# Web server only
docker-compose up -d web-server

# MCP server only
docker-compose up -d mcp-server
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f web-server
docker-compose logs -f mcp-server
```

### Stop Services

```bash
docker-compose down
```

### Restart Services

```bash
docker-compose restart
```

## Health Checks

The web server includes a health check endpoint:
- URL: `http://localhost:8000/health`
- Returns: `{"status": "healthy", "timestamp": "..."}`

Docker Compose automatically monitors health:
```bash
# Check health status
docker-compose ps
```

## Development

### Local Development with Docker

1. **Mount source code as volume** (for live reload):
   ```yaml
   # Add to docker-compose.yml under web-server volumes:
   - ./web/server:/app/web/server:ro
   - ./shared:/app/shared:ro
   - ./out:/app/out:rw  # For vector DB and ga_meta.sqlite
   ```

2. **Use development environment**:
   ```bash
   ENVIRONMENT=development docker-compose up
   ```

### Debugging

```bash
# Execute command in running container
docker-compose exec web-server bash
docker-compose exec mcp-server bash

# View environment variables
docker-compose exec web-server env

# Check file permissions
docker-compose exec web-server ls -la /app/data
```

## Production Deployment

### Security Considerations

1. **API Keys**: Never commit `.env` file with real API keys
2. **File Permissions**: Ensure data files have correct permissions
3. **Network**: Use Docker networks to isolate services
4. **HTTPS**: Use reverse proxy (nginx/traefik) for HTTPS
5. **Secrets**: Consider using Docker secrets or external secret management

### Reverse Proxy Setup

Example nginx configuration:

```nginx
server {
    listen 80;
    server_name maps.flyfun.aero;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Environment-Specific Configuration

Create separate `.env` files for different environments:

```bash
# Development
cp env.sample .env.dev
# Edit .env.dev

# Production
cp env.sample .env.prod
# Edit .env.prod

# Use specific env file
docker-compose --env-file .env.prod up -d
```

## Troubleshooting

### Container Won't Start

1. **Check logs**:
   ```bash
   docker-compose logs web-server
   ```

2. **Check data files exist**:
   ```bash
   ls -la data/airports.db data/rules.json
   ```

3. **Check file permissions**:
   ```bash
   docker-compose exec web-server ls -la /app/data
   ```

### Database Errors

1. **Read-only database error**:
   - Check `GA_META_READONLY` setting
   - Ensure output directory is writable by UID 2000 (web server)
   - Check file permissions: `ls -la out/`
   - Fix permissions: `chmod 777 out` or `chown -R 2000:2000 out`

2. **ChromaDB connection errors**:
   - Verify ChromaDB service is running: `docker-compose ps chromadb`
   - Check ChromaDB logs: `docker-compose logs chromadb`
   - Verify service URL: Should be `http://chromadb:8000` (not `localhost:8001`)
   - Test connectivity from web-server: `docker exec flyfun-web-server curl http://chromadb:8000/api/v1/heartbeat`
   - Check network: `docker network inspect flyfun-network`

3. **Vector database not found**:
   - Build the vector database: See "Building and Updating Data Files" section
   - Verify `rules.json` exists: `ls -la data/rules.json`
   - Check ChromaDB data directory: `ls -la out/chromadb_data/`

2. **Database not found**:
   - Verify `AIRPORTS_DB` path in `.env`
   - Check volume mount in `docker-compose.yml`
   - Ensure file exists in `data/` directory

3. **Permission denied errors**:
   - Containers run as non-root (UID 2000/2001)
   - Ensure writable volumes (`out`, `logs`) have correct permissions
   - Check container user: `docker-compose exec web-server id`
   - Fix: `chmod 777 out logs` or match UID/GID on host

### Port Conflicts

**Web Server Port:**
If port 8000 is already in use:
```bash
# Change in .env
WEB_PORT=8001

# Or in docker-compose.yml
ports:
  - "8001:8000"
```

**ChromaDB Port:**
If port 8001 is already in use:
```bash
# Change in .env
CHROMADB_PORT=8002

# The internal service URL (chromadb:8000) remains the same
# Only the external port mapping changes
```

**Note**: Internal container-to-container communication uses service names and container ports (e.g., `chromadb:8000`), which are separate from host port mappings. Changing host ports doesn't affect internal communication.

### Build Failures

1. **euro_aip installation fails**:
   - Check internet connection
   - Verify git repository URL in Dockerfile
   - Consider using local copy or submodule

2. **Dependencies fail**:
   ```bash
   # Rebuild without cache
   docker-compose build --no-cache
   ```

## Migration from Non-Docker Setup

### Step 1: Update Environment Loading

The code now uses `shared/env_loader.py` which:
- Supports both `.env` and `{env}.env` files
- Works with Docker (loads from root `.env`)
- Works with local development (loads from component directories)

### Step 2: Consolidate Configuration

Move from multiple `dev.env` files to single root `.env`:
- Old: `web/server/dev.env`, `mcp_server/dev.env`
- New: `.env` at root (used by both services)

### Step 3: Update Paths

Paths in `.env` are container paths:
- Old: `/Users/you/flyfun/data/airports.db`
- New: `/app/data/airports.db` (mapped from host `./data/airports.db`)

### Step 4: Test

```bash
# Build and test
docker-compose build
docker-compose up -d

# Verify services are running
docker-compose ps
curl http://localhost:8000/health
```

## Building and Updating Data Files

### Building rules.json from Excel Files

If you have Excel files with Q/A format:

```bash
# Run inside container or on host
docker exec -it flyfun-web-server python tools/xls_to_rules.py \
    --out /app/data/rules.json \
    --defs /path/to/definitions.xlsx \
    --add GB "/path/to/GB-rules.xlsx" \
    --add FR "/path/to/FR-rules.xlsx" \
    --build-rag
```

This will:
1. Convert Excel files to `rules.json`
2. Build the ChromaDB vector database automatically

### Updating ChromaDB Vector Database

After updating `rules.json`, rebuild the vector database:

```bash
# Rebuild vector database from existing rules.json
docker exec -it flyfun-web-server python tools/xls_to_rules.py \
    --out /app/data/rules.json \
    --build-rag
```

Or use the `--vector-db-url` flag explicitly:

```bash
docker exec -it flyfun-web-server python tools/xls_to_rules.py \
    --out /app/data/rules.json \
    --vector-db-url http://chromadb:8000 \
    --build-rag
```

### Building ga_meta.sqlite

If you have airfield.directory export data:

```bash
# Build from export JSON
docker exec -it flyfun-web-server python tools/build_ga_friendliness.py \
    --export /path/to/airfield-directory-export.json \
    --output /app/out/ga_meta.sqlite

# Or run on host (if you have the export file locally)
python tools/build_ga_friendliness.py \
    --export /path/to/export.json \
    --output out/ga_meta.sqlite
```

**Note**: The `ga_meta.sqlite` file must be placed in `out/ga_meta.sqlite` on the host for containers to access it.

## Testing

See `designs/DOCKER_TESTING_GUIDE.md` for comprehensive testing instructions, including:
- Pre-flight checks
- Build and runtime tests
- Functionality verification
- Troubleshooting guide

**Quick Test:**
```bash
# Build and start
docker-compose build
docker-compose up -d

# Check health
curl http://localhost:8000/health
curl http://localhost:8001/api/v1/heartbeat  # ChromaDB

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

## Complete Setup Checklist for New Server

Use this checklist when setting up on a brand new server:

- [ ] Install Docker and Docker Compose
- [ ] Clone repository
- [ ] Create directories: `data/`, `out/`, `logs/`
- [ ] Set permissions: `chmod 777 out logs` (or use proper ownership)
- [ ] Place `airports.db` in `data/`
- [ ] Create or place `rules.json` in `data/`
- [ ] (Optional) Place `ga_meta.sqlite` in `out/`
- [ ] Copy `env.sample` to `.env`
- [ ] Configure `.env` with API keys (OPENAI_API_KEY required)
- [ ] Build images: `docker-compose build`
- [ ] Start services: `docker-compose up -d`
- [ ] Verify services: `docker-compose ps`
- [ ] Build ChromaDB vector database: `docker exec -it flyfun-web-server python tools/xls_to_rules.py --out /app/data/rules.json --build-rag`
- [ ] Test web server: `curl http://localhost:8000/health`
- [ ] Test ChromaDB: `curl http://localhost:8001/api/v1/heartbeat`
- [ ] Check logs: `docker-compose logs -f`

## Next Steps

- [ ] Set up CI/CD for automated builds
- [ ] Configure monitoring and alerting
- [ ] Set up backup strategy for data files (especially `out/chromadb_data/` and `out/ga_meta.sqlite`)
- [ ] Document production deployment process
- [ ] Add support for multiple environments (staging, production)
- [ ] Configure ChromaDB authentication for production (set `CHROMADB_AUTH_TOKEN`)

