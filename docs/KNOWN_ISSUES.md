# KNOWN ISSUES & LOG ERROR TRIAGE SPECIFICATION

This document provides structured diagnostic definitions, classification, and deterministic runbooks for known log patterns and engine quirks in Project Zomboid Dedicated Servers (Build 41 / Build 42 Unstable) under Docker.

---

## 1. LOG TAXONOMY & ERROR MATRIX

| Signature Regex | Component | Severity | Class | Action Required |
| :--- | :--- | :--- | :--- | :--- |
| `handleMannequinZone.*missing properties` | Lua (Vanilla Map) | `LOW` | `BUILD42_VANILLA_BUG` | **Ignore** (Upstream base game data omission) |
| `Basements\.mergeRoomsOntoMetaCell.*duplicate RoomDef` | Basement Engine | `LOW` | `BUILD42_COLLISION` | **Monitor** (Procedural basement room index collision) |
| `IsoMetaGrid\.load.*invalid room metaID` | Metagrid Cache | `MEDIUM` | `METAGRID_MISMATCH` | **Evaluate** (Metadata mismatch in `map_meta.bin` after update) |
| `SteamNetworkingUtils.*before SteamAPI_Init` | Steamworks / RakNet | `NONE` | `COSMETIC_RACE` | **Ignore** (Non-blocking socket init race) |
| `NoSuchFileException:.*\/mods` | Java DebugFileWatcher | `LOW` | `ENV_PROVISIONING` | **Fix** (Create `data/mods` host directory) |
| `No UPnP-enabled Internet gateway found` | UPnP NAT Engine | `LOW` | `NETWORK_TIMEOUT` | **Fix** (Set `UPnP=false` in INI to save ~12s boot delay) |

---

## 2. DETAILED ERROR SPECIFICATIONS & ROOT CAUSES

### 2.1 Mannequin Zone Missing Properties
- **Log Pattern**:
  ```text
  [ERROR] ERROR: Lua f:0 st:... at Lua(Vanilla).handleMannequinZone > ERROR: Mannequin zone missing properties in media/maps/Muldraugh, KY/objects.lua coords: X, Y, Z
  ```
- **Root Cause**: In Build 42, clothing outfits on mannequins are populated via `objects.lua`. Certain vanilla coordinate entries lack the outfit definition table.
- **Impact**: Non-fatal. The engine skips dressing the mannequin at that tile and proceeds with normal world generation.
- **Deterministic Action**: **NOOP / IGNORE**. Do not delete save data or modify base game files.

---

### 2.2 Duplicate Basement Room Definitions
- **Log Pattern**:
  ```text
  [ERROR] ERROR: General f:0 st:... at Basements.mergeRoomsOntoMetaCell > duplicate RoomDef.metaID for room at X,Y,Z
  ```
- **Root Cause**: Procedural basements or overlapping building definitions claim an identical `metaID` during metacell room merging.
- **Impact**: Non-fatal. The engine keeps the primary room definition and overwrites the duplicate slot.
- **Deterministic Action**: If players report no crashes at those coordinates, take no action. If crashes occur at that chunk, execute the **Chunk Reset Runbook** (Section 3.2).

---

### 2.3 Invalid Room metaID in `map_meta.bin`
- **Log Pattern**:
  ```text
  [ERROR] ERROR: General f:0 st:... at IsoMetaGrid.load > invalid room metaID #<ID> in cell <CX,CY> while reading map_meta.bin
  ```
- **Root Cause**: `data/Saves/Multiplayer/<SERVER_NAME>/map_meta.bin` caches room IDs for simulated world states. When updating game builds or changing map mods, the room indices in the save file mismatch the current map catalog.
- **Impact**: Non-fatal in >95% of cases. The engine ignores the outdated room identifier and falls back to unzoned space.
- **Deterministic Action**:
  - If server boots and players can enter cell `<CX,CY>`: **IGNORE**.
  - If server crashes on player approach to cell `<CX,CY>`: Execute **Metagrid Regeneration Runbook** (Section 3.1).

---

### 2.4 SteamNetworkingUtils Pre-Init Warning
- **Log Pattern**:
  ```text
  [ERROR] [S_API FAIL] Tried to access Steam interface SteamNetworkingUtils004 before SteamAPI_Init succeeded.
  ```
- **Root Cause**: The Linux native dedicated server binary queries Steam socket utilities prior to the asynchronous callback from `SteamGameServer_Init()`.
- **Impact**: Purely cosmetic. Immediately followed by `SteamUtils initialised successfully`.
- **Deterministic Action**: **NOOP / IGNORE**.

---

### 2.5 Missing `mods` Directory Exception
- **Log Pattern**:
  ```text
  ERROR: General f:0 st:...> DebugFileWatcher.registerDir> Exception thrown
  java.nio.file.NoSuchFileException: /project-zomboid-config/mods
  ```
- **Root Cause**: Java NIO `FileWatcher` registers `/project-zomboid-config/mods` for local mods, but the host volume mount `./data` has no `mods/` subdirectory.
- **Deterministic Action**:
  ```bash
  mkdir -p data/mods
  chmod 775 data/mods
  ```

---

### 2.6 UPnP Timeout in Docker
- **Log Pattern**:
  ```text
  Router detection/configuration starting.
  If the server hangs here, set UPnP=false.
  No UPnP-enabled Internet gateway found...
  ```
- **Root Cause**: Docker containers isolate network namespaces; UPnP multicast discovery fails and delays boot by 10–15 seconds.
- **Deterministic Action**:
  1. `docker compose down`
  2. Set `UPnP=false` in `data/Server/<SERVER_NAME>.ini`
  3. `docker compose up -d`

---

## 3. REMEDIATION RUNBOOKS

### 3.1 Metagrid / Cell Reset Runbook
Use this runbook if corrupted room metadata prevents players from loading into a specific cell:

```bash
# 1. Stop container gracefully
docker compose down

# 2. Backup current save
tar -czvf "data/backups/pre_cell_reset_$(date +%Y%m%d_%H%M%S).tar.gz" data/Saves data/Server

# 3. Remove corrupted metacell cache (e.g. cell 25, 33)
rm -f "data/Saves/Multiplayer/<SERVER_NAME>/metagrid/metacell_25_33.bin"

# 4. (Optional) Force map_meta rebuild on next boot if completely corrupted
# rm -f "data/Saves/Multiplayer/<SERVER_NAME>/map_meta.bin"

# 5. Restart container (world engine will recreate cell metadata on load)
docker compose up -d
```

### 3.2 Specific Chunk Data Reset Runbook
If a specific world coordinate (e.g. `X, Y, Z`) is causing physics crashes:

```bash
# Calculate chunk coordinate: floor(X / 10), floor(Y / 10)
# Chunk coordinates for X=10707, Y=9484 -> chunk_1070_948.bin (or map_1070_948.bin)

docker compose down
find "data/Saves/Multiplayer/<SERVER_NAME>/chunkdata/" -name "*1070*948*" -delete
docker compose up -d
```

---

## 4. COLD-START PROVISIONING CHECKLIST (FRESH DEPLOYMENT)
When deploying a new server from scratch (`git clone`):

1. **Copy Environment**: `cp .env.example .env`
2. **Pre-create Volume Structure**:
   ```bash
   mkdir -p data/mods data/backups data/db data/Server
   chmod -R 775 data
   ```
3. **Start Container for Initial File Generation**:
   ```bash
   docker compose up -d
   ```
4. **Wait for First Initialization**, then:
   ```bash
   docker compose down
   # Set UPnP=false in data/Server/<SERVER_NAME>.ini
   sed -i 's/^UPnP=true/UPnP=false/' data/Server/*.ini 2>/dev/null || true
   docker compose up -d
   ```
