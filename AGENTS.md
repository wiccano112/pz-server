# AGENT INSTRUCTIONS: PROJECT ZOMBOID DOCKER SERVER

## SYSTEM MANIFEST & TOPOLOGY
- **Runtime**: Docker / Docker Compose
- **Base Image**: `indifferentbroccoli/projectzomboid-server-docker:latest`
- **Server Name Key**: `SERVER_NAME` (defined in `.env`, controls file prefixes & save game directory names)
- **Container Host Volumes**: `./data` -> `/project-zomboid-config`
- **User Permissions**: `PUID=1000`, `PGID=1000` (configurable via `.env`)
- **Network Interfaces**:
  - `16261/UDP`: Primary game loop & physics sync.
  - `16262/UDP`: Direct client connection handoff.
  - `27015/TCP`: Steam Query protocol & RCON administration.
- **Web Administration Plane**: `pz-panel` located at `../pz-panel` ([GitHub Repo](https://github.com/wiccano112/pz-panel)) (Next.js 16 / React 19).

---

## FILE MAP & PATH IDENTIFIERS

```
pz-server/
├── docker-compose.yml                     # Container orchestration & env configuration
├── .env.example                           # Template for environment variables
├── README.md                              # Human-facing documentation
├── AGENTS.md                              # LLM system prompt & operational spec (this file)
├── docs/                                  # Extended technical specs for LLM execution
│   ├── ARCHITECTURE.md                    # Container topology, steamcmd hooks, networking, web panel
│   ├── OPERATIONS.md                      # Deterministic command recipes & runbooks
│   └── CONFIG_REFERENCE.md                # Schema definitions (.ini, .lua, sqlite databases)
└── data/                                  # Bound to /project-zomboid-config (ignored in git)
    ├── options.ini                        # Graphic/Audio server fallback options
    ├── server-console.txt                 # Runtime stdout/stderr log output
    ├── backups/                           # Automated server archives (.zip)
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

2. **ESCAPE DELIMITERS IN INI LISTS**:
   - `Mods`, `WorkshopItems`, and `Map` directives in `data/Server/<SERVER_NAME>.ini` require escaped semicolon delimiter format: `item1\;item2\;item3`.
   - Semicolons without backslashes (`item1;item2`) will truncate or corrupt parsing in the Java server backend.

3. **WORKSHOP-MOD CORRELATION**:
   - Every workshop item ID added to `WorkshopItems` MUST have its matching Mod identifier in `Mods`.
   - Map mods (e.g. `RavenCreek`) MUST precede vanilla map layers in `Map=MapModName\;Muldraugh, KY`.

4. **PERMISSION INTEGRITY**:
   - All files created/edited in `./data` must be readable/writable by UID 1000 / GID 1000 (`chmod 664 / chown 1000:1000` if mutated outside container).

5. **PZ-PANEL INTEROPERABILITY**:
   - `pz-panel` interacts with Docker directly via host socket/CLI (`docker stats`, `docker inspect`, `docker logs -f`).
   - SQLite access by `pz-panel` is synchronous (`node:sqlite DatabaseSync`). Ensure no locks remain during CLI batch updates.

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

### 1. START / STOP / RESTART
```bash
docker compose up -d              # Start detached
docker compose down               # Graceful shutdown (saves world state)
docker compose restart pz-server  # Quick restart without config rebuild
```

### 2. LOG EXTRACTION & HEALTH CHECK
```bash
docker compose ps                 # Verify container state & uptime
docker compose logs --tail=100 -f # Tail server stdout
grep -E "SERVER STARTED|ERROR|Exception" data/server-console.txt # Audit init status
```

### 3. MOD INJECTION PIPELINE
1. `docker compose down`
2. Parse mod requirements: `WorkshopID` and `ModID`.
3. Append `WorkshopID` to `WorkshopItems` in `data/Server/<SERVER_NAME>.ini` using `\;`.
4. Append `ModID` to `Mods` in `data/Server/<SERVER_NAME>.ini` using `\;`.
5. If mod has a map: Prepend map folder name to `Map` in `data/Server/<SERVER_NAME>.ini`.
6. `docker compose up -d`
7. Audit `data/server-console.txt` for `Workshop item [ID] up to date` and `MOD: [ModID] loaded`.

### 4. WEB PANEL SPAWN (`pz-panel`)
```bash
cd ../pz-panel
pnpm dev                          # Default: http://localhost:3000
```

### 5. WORLD RESET / BACKUP PROTOCOL
- **Create Backup**: `tar -czvf "data/backups/manual_$(date +%Y%m%d_%H%M%S).tar.gz" data/Saves data/Server data/db`
- **Soft Reset (Loot & Zombis)**: Delete `data/Saves/Multiplayer/<SERVER_NAME>/chunkdata/` and `zpop/`.
- **Hard Wipe**: Delete `data/Saves/Multiplayer/<SERVER_NAME>/` and `data/db/<SERVER_NAME>.db`.

---

## SUB-SPECIFICATION INDEX
- `docs/ARCHITECTURE.md`: Low-level container runtime, SteamCMD integration, networking, and web panel integration.
- `docs/OPERATIONS.md`: Deterministic automation runbooks, RCON management, triage workflows.
- `docs/CONFIG_REFERENCE.md`: Complete parameter dictionary for INI, SandboxVars LUA, and SQLite schemas.
