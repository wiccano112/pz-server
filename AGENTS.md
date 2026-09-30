# AGENT INSTRUCTIONS: PROJECT ZOMBOID DOCKER SERVER

## SYSTEM MANIFEST & TOPOLOGY
- **Runtime**: Docker / Docker Compose
- **Base Image**: `indifferentbroccoli/projectzomboid-server-docker:latest`
- **Environments**:
  - **Production (`pz-server`)**:
    - Server Name Key: `SERVER_NAME` (defined in `.env`, e.g. `NobaraZomboid`)
    - Container Host Volumes: `./data` -> `/project-zomboid-config`
    - CPU Affinity: `cpuset: "12-17"` (6 E-Cores)
    - Network: `16261/UDP` (Game), `16262/UDP` (Direct), `27015/TCP` (RCON/Query)
  - **Staging (`pz-rpm-server-stg`)**:
    - Path: `./staging/`
    - Server Name: `pz-rpm-server-stg`
    - Container Host Volumes: `./staging/data` -> `/project-zomboid-config`
    - CPU Affinity: `cpuset: "0-3"` (4 P-Cores, 100% dedicated, zero overlap with PRD)
    - Memory Limit: `mem_limit: 6g` (Max heap 6G, initial 4G)
    - Network: `17261/UDP` (Game), `17262/UDP` (Direct), `27025/TCP` (RCON/Query)
    - Branch: `SERVER_BRANCH=unstable` (Build 42.21)
- **User Permissions**: `PUID=1000`, `PGID=1000` (configurable via `.env`)
- **Web Administration Plane**: `pz-panel` located at `../pz-panel` ([GitHub Repo](https://github.com/wiccano112/pz-panel)) (Next.js 16 / React 19).

---

## FILE MAP & PATH IDENTIFIERS

```
pz-server/
├── docker-compose.yml                     # Production container orchestration
├── .env.example                           # Template for production environment variables
├── .env                                   # Production environment variables
├── README.md                              # Human-facing documentation
├── AGENTS.md                              # LLM system prompt & operational spec (this file)
├── docs/                                  # Extended technical specs for LLM execution
│   ├── ARCHITECTURE.md                    # Container topology, steamcmd hooks, networking, web panel
│   ├── OPERATIONS.md                      # Deterministic command recipes & runbooks
│   ├── CONFIG_REFERENCE.md                # Schema definitions (.ini, .lua, sqlite databases)
│   ├── KNOWN_ISSUES.md                    # Error triage matrix and engine quirks
│   ├── CPU_TUNING_AND_COOP_GAMING.md      # CPU pinning profiles (Intel P-cores vs E-cores)
│   └── MIGRACION_42_21_UNSTABLE.md        # Step-by-step 42.21 upgrade & rollback guide
├── scripts/                               # Production operational scripts
│   ├── common.sh                          # Shared utilities and environment loader
│   ├── manage.sh                          # Interactive control panel (Options 1-12)
│   ├── backup.sh                          # Full safe server backup script
│   ├── restore.sh                         # Server restoration script
│   ├── upgrade_to_42_21.sh                # Deterministic PRD upgrade script (backup + unstable)
│   ├── rollback_to_42_20.sh               # Deterministic PRD rollback script (restore + stable)
│   ├── safe_restart.sh                    # Graceful restart with RCON warning
│   └── status.sh                          # Live status & metrics monitor
├── staging/                               # Staging Environment (100% isolated)
│   ├── docker-compose.yml                 # Staging container orchestration (pz-rpm-server-stg)
│   ├── .env / .env.example                # Staging environment variables (ports 17261/17262/27025)
│   ├── README.md                          # Staging guide & player connection specs
│   ├── scripts/                           # Staging automation scripts
│   │   ├── sync_from_prd.sh               # Syncs mods/config from PRD (--with-save optional)
│   │   ├── up.sh / down.sh / restart.sh   # Staging lifecycle controls
│   │   ├── logs.sh / status.sh / rcon.sh  # Staging telemetry & console
│   │   └── manage.sh                      # Staging interactive CLI panel
│   └── data/                              # Bound to staging container (ignored in git)
└── data/                                  # Bound to production container (ignored in git)
    ├── options.ini                        # Graphic/Audio server fallback options
    ├── server-console.txt                 # Runtime stdout/stderr log output
    ├── backups/                           # Automated server archives (.zip / .tar.gz)
    ├── db/<SERVER_NAME>.db                # SQLite user authentication & whitelist DB
    ├── Logs/                              # Timestamped session logs & chat transcripts
    ├── Saves/Multiplayer/<SERVER_NAME>/   # World state, chunkdata, map, players.db, vehicles.db
    └── Server/                            # Core server configuration files
        ├── <SERVER_NAME>.ini              # Server properties, mods, ports, networking
        ├── <SERVER_NAME>_SandboxVars.lua  # Game mechanics, loot, zombie traits, climate
        ├── <SERVER_NAME>_spawnpoints.lua  # Vector spawn coordinates
        └── <SERVER_NAME>_spawnregions.lua # Regional spawn definitions

External / Satellite Systems:
└── pz-panel/                              # Web administration panel (Next.js 16 App Router)
    ├── src/lib/serverUtils.ts             # Direct Docker CLI caller + INI parser/writer
    ├── src/lib/playerUtils.ts             # Direct SQLite caller (<SERVER_NAME>.db) + Log streamer
    └── src/lib/sandboxUtils.ts            # Atomic Lua serializer (<SERVER_NAME>_SandboxVars.lua)
```

---

## CRITICAL INVARIANTS & AGENT RULES

1. **MUTATION AT REST ONLY**:
   - MUST execute `docker compose down` before editing `data/Server/*.ini`, `data/Server/*.lua`, or any file in `data/Saves/Multiplayer/<SERVER_NAME>/` via CLI.
   - Modifying world/config state during container execution causes silent overwrite on server exit or memory corruption.
   - Note: `pz-panel` executes atomic file writes (`.tmp` -> rename) for sandbox vars and interacts with SQLite using `PRAGMA busy_timeout = 3000`.

2. **DELIMITERS IN INI LISTS**:
   - `Mods`, `WorkshopItems`, and `Map` directives in `data/Server/<SERVER_NAME>.ini` use standard semicolon delimiters: `item1;item2;item3`.
   - Do NOT escape semicolons with backslashes (`item1\;item2`), as the Java engine treats `\` as part of the ID, breaking workshop downloads and mod loading.

3. **WORKSHOP-MOD CORRELATION**:
   - Every workshop item ID added to `WorkshopItems` MUST have its matching Mod identifier in `Mods`.
   - Map mods (e.g. `RavenCreek`) MUST precede vanilla map layers in `Map=MapModName;Muldraugh, KY`.

4. **PERMISSION INTEGRITY**:
   - All files created/edited in `./data` must be readable/writable by UID 1000 / GID 1000 (`chmod 664 / chown 1000:1000` if mutated outside container).

5. **PZ-PANEL INTEROPERABILITY**:
   - `pz-panel` interacts with Docker directly via host socket/CLI (`docker stats`, `docker inspect`, `docker logs -f`).
   - SQLite access by `pz-panel` is synchronous (`node:sqlite DatabaseSync`). Ensure no locks remain during CLI batch updates.

6. **PLAYER CONNECTION AUDIT**:
   - MUST verify if players are connected (via RCON or `docker compose logs`) before executing `docker compose down`.
   - If players are active, explicitly ask the USER for confirmation or ask them to announce a restart warning in-game before bringing the server down to avoid abrupt disconnections.

7. **STAGING-FIRST VALIDATION (MANDATORY)**:
   - Any major structural modification—including **adding or updating Workshop mods**, changing map definitions, or **upgrading the game engine/branch (e.g. Build 42.21)**—**MUST FIRST BE TESTED IN THE STAGING ENVIRONMENT (`./staging`)**.
   - NEVER inject new mods or version bumps directly into production without verifying in staging that:
     1. The mod downloads cleanly via Steam Workshop.
     2. The server initializes without fatal Lua exceptions or mod ID collisions.
     3. The world loads and test clients can connect without mismatch errors.
   - Once validated in staging, promote the change to production using the production scripts or safe shutdown pipeline.

---

## RUNTIME STATE MACHINE

```
[IDLE/STOPPED] ──(docker compose up -d)──> [CONTAINER_START]
                                                  │
                                          [STEAMCMD_UPDATE] (Downloads PZ + Workshop Items)
                                                  │
                                          [SERVER_INITIALIZE] (Parses .ini, .lua, SQLite)
                                                  │
                                          [LISTENING: 16261/16262/27015]
                                                  │
[RUNNING] ──────(docker compose down)────> [SIGTERM -> WORLD_FLUSH -> GRACEFUL_HALT]
```

---

## FAST EXECUTION DIRECTIVES

### 1. START / STOP / RESTART (PRODUCCIÓN)
```bash
docker compose up -d              # Start detached
docker compose down               # Graceful shutdown (saves world state)
docker compose restart pz-server  # Quick restart without config rebuild
./scripts/manage.sh               # Interactive control panel (Options 1-12)
```

### 2. STAGING LIFECYCLE & TESTING (`staging/`)
```bash
cd staging
./scripts/sync_from_prd.sh        # Sync mods and configs from PRD (or --with-save to test savegame)
./scripts/up.sh                   # Start staging container (pz-rpm-server-stg on port 17261)
./scripts/logs.sh                 # Monitor download & boot logs
./scripts/status.sh               # Verify detected version, RAM/CPU and loaded mods
./scripts/down.sh                 # Graceful shutdown of staging
```

### 3. MOD INJECTION PIPELINE (STAGING-FIRST)
1. **Test in Staging first**:
   - `cd staging && ./scripts/down.sh`
   - Append `WorkshopID` to `WorkshopItems` in `staging/data/Server/pz-rpm-server-stg.ini` using `;`.
   - Append `ModID` to `Mods` in `staging/data/Server/pz-rpm-server-stg.ini` using `;`.
   - If map mod: Prepend map folder name to `Map` in `staging/data/Server/pz-rpm-server-stg.ini`.
   - `./scripts/up.sh` and `./scripts/logs.sh` to confirm `MOD: [ModID] loaded`.
2. **Promote to Production (after successful staging test)**:
   - Audit connected players (`docker exec pz-server rcon-cli ... players`).
   - `docker compose down`
   - Apply same `WorkshopItems` and `Mods` entries to `data/Server/<SERVER_NAME>.ini` using `;`.
   - `docker compose up -d`
   - Audit `data/server-console.txt` for clean init.

### 4. PRODUCTION ENGINE UPGRADE & ROLLBACK (BUILD 42.21)
```bash
# Automated Upgrade with pre-flight checks and snapshot:
./scripts/upgrade_to_42_21.sh     # Or ./scripts/manage.sh (Option 11)

# Automated Rollback to 42.20.4 and snapshot restore:
./scripts/rollback_to_42_20.sh    # Or ./scripts/manage.sh (Option 12)
```

### 5. WEB PANEL SPAWN (`pz-panel`)
```bash
cd ../pz-panel
pnpm dev                          # Default: http://localhost:3000
```

### 6. WORLD RESET / BACKUP PROTOCOL
- **Create Backup**: `./scripts/backup.sh --stop` (or `tar -czvf "data/backups/manual_$(date +%Y%m%d_%H%M%S).tar.gz" data/Saves data/Server data/db`)
- **Soft Reset (Loot & Zombis)**: Delete `data/Saves/Multiplayer/<SERVER_NAME>/chunkdata/` and `zpop/`.
- **Hard Wipe**: Delete `data/Saves/Multiplayer/<SERVER_NAME>/` and `data/db/<SERVER_NAME>.db`.

---

## SUB-SPECIFICATION INDEX
- `docs/ARCHITECTURE.md`: Low-level container runtime, SteamCMD integration, networking, and web panel integration.
- `docs/OPERATIONS.md`: Deterministic automation runbooks, RCON management, triage workflows.
- `docs/CONFIG_REFERENCE.md`: Complete parameter dictionary for INI, SandboxVars LUA, and SQLite schemas.
- `docs/KNOWN_ISSUES.md`: Known errors triage matrix, Build 42 log quirks, and resolution runbooks.
- `docs/CPU_TUNING_AND_COOP_GAMING.md`: CPU pinning profiles for hybrid architectures (P-cores vs E-cores) and Host & Play co-op setup.
- `docs/MIGRACION_42_21_UNSTABLE.md`: Step-by-step migration guide for upgrading to Build 42.21 Unstable.
