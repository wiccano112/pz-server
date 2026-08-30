# OPERATIONS SPECIFICATION: PROJECT ZOMBOID DOCKER SERVER

## 1. DETERMINISTIC LIFECYCLE COMMANDS

```bash
# Provision / Boot Container
docker compose up -d

# Graceful Shutdown (Flushes dirty memory chunks to disk)
docker compose down

# Fast In-Place Restart (Does not re-read docker-compose.yml changes)
docker compose restart pz-server

# Force Rebuild / Hard Recreation
docker compose up -d --force-recreate

# Health Status & Port Inspection
docker compose ps
docker port pz-server
```

---

## 2. MOD LIFECYCLE MANAGEMENT RECIPES

### 2.1 Mod Addition Recipe
1. Acquire Steam Workshop ID (`WORKSHOP_ID`) and internal Mod ID (`MOD_ID`).
2. Verify container state: `docker compose down`.
3. Open `data/Server/<SERVER_NAME>.ini`.
4. Append `\;WORKSHOP_ID` to `WorkshopItems`.
5. Append `\;MOD_ID` to `Mods`.
6. IF mod introduces custom map tiles:
   - Identify map folder name (e.g. `RavenCreek`).
   - Prepend `MapFolder\;` before `Muldraugh, KY` in `Map=` parameter.
   - Example: `Map=RavenCreek\;Muldraugh, KY`
7. Start container: `docker compose up -d`.
8. Validate via console log:
   ```bash
   docker compose logs --tail=200 pz-server | grep -E "(Workshop item|MOD:)"
   ```

### 2.2 Mod Removal Recipe
1. Execute `docker compose down`.
2. Remove corresponding `MOD_ID` from `Mods=` in `data/Server/<SERVER_NAME>.ini`.
3. Remove corresponding `WORKSHOP_ID` from `WorkshopItems=`.
4. If map mod, remove map name from `Map=`.
5. **Warning on WorldDictionary**: Removing item/tile mods from an active world may trigger `WorldDictionary` mismatch warnings. If server fails to boot, check `data/Logs/*_DebugLog-server.txt` for dictionary load failures.
6. Execute `docker compose up -d`.

---

## 3. BACKUP & RESTORATION RUNBOOKS

### 3.1 Hot-Safe Backup Creation
```bash
BACKUP_NAME="backup_manual_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czvf "data/backups/${BACKUP_NAME}" \
    -C data \
    Saves Server db options.ini
echo "Backup created at data/backups/${BACKUP_NAME}"
```

### 3.2 Full Restoration Procedure
```bash
# 1. Stop container
docker compose down

# 2. Clear current corrupted state
rm -rf data/Saves/Multiplayer/<SERVER_NAME>/*
rm -f data/db/<SERVER_NAME>.db

# 3. Extract target backup archive
tar -xzvf data/backups/<TARGET_BACKUP_FILE>.tar.gz -C data/

# 4. Verify file permissions
chown -R 1000:1000 data/
chmod -R 775 data/

# 5. Boot container
docker compose up -d
```

---

## 4. DATABASE & STATE MANIPULATION

### 4.1 Account & Whitelist DB (`data/db/<SERVER_NAME>.db`)
- Engine: SQLite 3
- Schema includes `whitelist` table for user accounts, passwords (SHA-256), and admin roles.
- Inspection:
  ```bash
  sqlite3 data/db/<SERVER_NAME>.db "SELECT username, accesslevel FROM whitelist;"
  ```
- Elevate user to Admin:
  ```bash
  sqlite3 data/db/<SERVER_NAME>.db "UPDATE whitelist SET accesslevel='admin' WHERE username='<TARGET_USER>';"
  ```

### 4.2 Players DB (`data/Saves/Multiplayer/<SERVER_NAME>/players.db`)
- Contains character stats, coordinate records, and serialized blob inventory.
- Reset specific player character (delete character while keeping account):
  ```bash
  sqlite3 data/Saves/Multiplayer/<SERVER_NAME>/players.db "DELETE FROM network_players WHERE name='<TARGET_USERNAME>';"
  ```

### 4.3 Vehicles DB (`data/Saves/Multiplayer/<SERVER_NAME>/vehicles.db`)
- Remove all vehicles (for world cleanup):
  ```bash
  sqlite3 data/Saves/Multiplayer/<SERVER_NAME>/vehicles.db "DELETE FROM vehicles;"
  ```

---

## 5. DIAGNOSTICS & TRIAGE HEURISTICS

### 5.1 Port Binding Failure
- Symptom: `Bind for 0.0.0.0:16261 failed: port is already allocated`
- Action:
  ```bash
  ss -tulpn | grep -E "16261|16262|27015"
  # Identify PID holding the port and terminate or reassign port in docker-compose.yml
  ```

### 5.2 Server Crash on Init (OutOfMemoryError)
- Symptom: `java.lang.OutOfMemoryError: Java heap space`
- Action:
  - Edit `.env` -> Increase `MAX_RAM` from `8G` to `12G` or `16G`.
  - Recreate container: `docker compose up -d --force-recreate`.

### 5.3 Mod Download Loop / SteamCMD Timeout
- Symptom: Server hangs at `Workshop: Downloading item [ID]`
- Action:
  ```bash
  docker compose restart pz-server
  # If persistent, inspect data/Workshop/ for incomplete .acf manifests
  ```

### 5.4 Live Console Interaction (RCON / stdin)
- Stdin attach:
  ```bash
  docker attach pz-server
  # Detach sequence: Press Ctrl+P followed by Ctrl+Q (DO NOT USE Ctrl+C)
  ```
- Send commands directly via docker exec (if RCON tool available) or interactive attach:
  - `save`: Forces world save.
  - `quit`: Triggers safe exit.
  - `servermsg "Message"`: Broadcasts global message.

---

## 6. SATELLITE WEB PANEL OPERATIONAL RUNBOOK (`pz-panel`)

### 6.1 Panel Execution
```bash
cd ../pz-panel
pnpm install                      # Dependency install
pnpm dev                          # Dev server on http://localhost:3000
pnpm build && pnpm start          # Production build & serve
```

### 6.2 Panel Code Quality & Invariants
```bash
cd ../pz-panel
pnpm run lint                     # ESLint checks
pnpm tsc --noEmit                 # Strict TypeScript typechecking
```

### 6.3 Shared Resource Triage (pz-panel <-> pz-server)
- **Database lock on `<SERVER_NAME>.db`**: Ensure `sqlite3` CLI processes are closed. `pz-panel` sets `busy_timeout = 3000`.
- **Docker permission denial**: Node.js user executing `pz-panel` must have access to the local Docker socket (`docker` group membership).
- **Atomic Sandbox Lua writes**: `pz-panel` writes to `<SERVER_NAME>_SandboxVars.lua.tmp` before replacing the target file.
