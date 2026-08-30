# ARCHITECTURE SPECIFICATION: PROJECT ZOMBOID DOCKER ENVIRONMENT

## 1. RUNTIME CONTAINER SPECIFICATION
- **Image Source**: `docker.io/indifferentbroccoli/projectzomboid-server-docker:latest`
- **Underlying Engine**: Debian/Ubuntu Linux minimal userland with SteamCMD runtime & 64-bit Java OpenJDK Runtime Environment (JRE).
- **Execution Workflow**:
  1. Entrypoint initializes UID/GID remapping matching `PUID=1000`, `PGID=1000`.
  2. SteamCMD validates base Project Zomboid dedicated server binaries (`AppID 380870`).
  3. SteamCMD queries Workshop item updates defined in `data/Server/<SERVER_NAME>.ini` (`WorkshopItems`).
  4. Java server process launches: `ProjectZomboid64.json` / `zomboid-server` wrapper with `-Xmx` / `-Xms` derived from `MAX_RAM`.
  5. World state loaded from `/project-zomboid-config/Saves/Multiplayer/<SERVER_NAME>/`.
  6. Sockets open on UDP 16261, 16262, TCP 27015.

---

## 2. MEMORY & RESOURCE ALLOCATION
- **Heap Allocation**: Defined by `MAX_RAM` in `.env` / `docker-compose.yml`.
  - Default: `8G` (suitable for 1-10 players with standard mod load).
  - High Capacity (20+ players or heavy map expansions): Set `MAX_RAM=16G` and host must have minimum 18GB physical RAM.
- **Garbage Collection**: JVM G1GC configured in base container launch params.
- **CPU Threading**: Java PZ server utilizes multi-threading for physics/chunks (`ZombieUpdatePacker`, `IsoRegion`, `WorldDictionary`).

---

## 3. NETWORKING & PORT MAPPING

| Host Port | Host Protocol | Container Port | Protocol | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `16261` | UDP | `16261` | UDP | Primary game port: Handshake, UDP sync, client-server tick transmission. |
| `16262` | UDP | `16262` | UDP | Direct connection / Steam networking relay port. |
| `27015` | TCP | `27015` | TCP | Steam Master Server Query protocol & RCON administrative listener. |

### Firewall / NAT Requirements:
- Inbound UDP 16261-16262 MUST be forwarded directly without packet transformation.
- Port collisions on host (e.g. other Steam servers on 27015) require shifting host side port: `- "27016:27015/tcp"`.

---

## 4. PERSISTENCE & STORAGE ARCHITECTURE

```
Host Path: ./data
└── Mounted into Container: /project-zomboid-config

Subdirectory Topology:
├── Server/
│   ├── <SERVER_NAME>.ini              # Static server-level configuration & parameters
│   ├── <SERVER_NAME>_SandboxVars.lua  # Lua table: SandboxVars (World rules)
│   ├── <SERVER_NAME>_spawnpoints.lua  # Lua table: Spawn points coordinates
│   └── <SERVER_NAME>_spawnregions.lua # Lua table: Spawn region mappings
├── Saves/Multiplayer/<SERVER_NAME>/
│   ├── map/                           # Binary map chunk tiles (*.bin)
│   ├── chunkdata/                     # Serialized map item states & container contents
│   ├── isoregiondata/                 # Structural room & interior containment data
│   ├── zpop/                          # Zombie population distribution grid
│   ├── apop/                          # Animal population distribution grid
│   ├── players.db                     # SQLite 3 database: Player character positions & inventories
│   ├── vehicles.db                    # SQLite 3 database: Vehicle spawn positions, parts, engine status
│   └── WorldDictionary.bin            # Registry mapping item/tile names to integer IDs across mods
├── db/
│   └── <SERVER_NAME>.db               # SQLite 3 database: User authentication, passwords (hashed), whitelist
├── Logs/                              # Runtime execution logs, chat logs, user action audits
├── backups/                           # Automatic snapshots triggered on startup/version upgrade
└── server-console.txt                 # Direct capture of latest container stdout/stderr
```

---

## 5. PROCESS LIFECYCLE & SIGNAL HANDLING
- **SIGTERM / SIGINT**: Forwarded to Java process. Triggers auto-save routine (`SaveWorld`) before exit. Timeout is 30s.
- **SIGKILL**: Immediate termination. Causes potential SQLite lock or corrupted `map_t.bin` chunk metadata. Avoid `kill -9`. Always prefer `docker compose down` or `docker compose stop -t 30`.

---

## 6. WEB CONTROL PLANE INTEGRATION (`pz-panel`)

### Topology Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                       HOST MACHINE                          │
│                                                             │
│  ┌───────────────────────┐         ┌─────────────────────┐  │
│  │   pz-panel (Node.js)  │         │  pz-server (Docker) │  │
│  │   Next.js 16 / Port   │         │  IndifferentBroccoli│  │
│  │   3000 (React 19)     │         │  Java Server Engine │  │
│  └──────────┬────────────┘         └──────────┬──────────┘  │
│             │                                 │             │
│   (1) Docker CLI & Logs Stream (SSE)          │             │
│             ├─────────────────────────────────┘             │
│             │                                               │
│   (2) File I/O & SQLite Sync                                │
│             ▼                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │   ./pz-server/data/                                   │  │
│  │   ├── Server/<SERVER_NAME>.ini (Mods / Maps)          │  │
│  │   ├── Server/<SERVER_NAME>_SandboxVars.lua (Lua)      │  │
│  │   └── db/<SERVER_NAME>.db (Whitelist, Bans)           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Integration Points:
1. **Docker Control**: `pz-panel/src/lib/serverUtils.ts` invokes `docker inspect`, `docker stats`, `docker start/stop/restart pz-server`.
2. **Log Streaming**: `pz-panel/src/app/api/logs/route.ts` streams `docker logs -f --tail 100 pz-server` via SSE to the browser.
3. **Sandbox Lua Parser/Writer**: `pz-panel/src/lib/sandboxUtils.ts` parses Lua key-values into typed records and writes back changes using atomic `.tmp` swap.
4. **Player & Whitelist Manager**: `pz-panel/src/lib/playerUtils.ts` opens `data/db/<SERVER_NAME>.db` via `node:sqlite` with `busy_timeout=3000`.
