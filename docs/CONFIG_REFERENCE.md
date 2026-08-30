# CONFIGURATION REFERENCE SPECIFICATION

## 1. ENVIRONMENT VARIABLES (`.env`)

| Variable | Type | Description |
| :--- | :--- | :--- |
| `CONTAINER_NAME` | String | Name of the Docker container (e.g. `pz-server`). |
| `SERVER_NAME` | String | Name prefix for `.ini`, `_SandboxVars.lua`, `_spawnregions.lua` and multiplayer save directory. |
| `ADMIN_PASSWORD` | String | Initial password set for default administrative account `admin`. |
| `MAX_RAM` | String | Maximum heap allocated to JVM (e.g. `4G`, `8G`, `16G`). Sets `-Xmx` parameter. |
| `PUID` | Integer | POSIX User ID for mapped filesystem permissions. |
| `PGID` | Integer | POSIX Group ID for mapped filesystem permissions. |
| `GAME_PORT` | Integer | Main UDP game port (`16261`). |
| `DIRECT_PORT` | Integer | Direct connection UDP port (`16262`). |
| `RCON_PORT` | Integer | Steam Query & RCON TCP port (`27015`). |
| `DATA_PATH` | String | Host path mapped to `/project-zomboid-config` (default: `./data`). |

---

## 2. SERVER PROPERTIES (`data/Server/<SERVER_NAME>.ini`)

### Critical Network & Identity Parameters:
- `Public`: `[true | false]` -> If true, lists server on global Steam server browser.
- `PublicName`: String -> Display name in server list.
- `PublicDescription`: String -> Markdown/text description in server browser.
- `MaxPlayers`: Integer -> Maximum concurrent player slots (default: `32`).
- `Password`: String -> Global server access password (leave blank for open server).
- `DefaultPort`: Integer -> Base UDP port (`16261`).
- `UDPPort`: Integer -> Secondary UDP port (`16262`).
- `RCONPort`: Integer -> Remote console port (`27015`).
- `RCONPassword`: String -> Password for remote RCON access.

### Mod & Map Configuration (Delimiter: `\;`):
- `WorkshopItems`: List -> Semicolon-escaped Steam Workshop IDs.
  - Example: `2196102849\;2503622437\;2896041179\;3077900375`
- `Mods`: List -> Semicolon-escaped internal Mod IDs.
  - Example: `errorMagnifier\;ChuckleberryFinnAlertSystem\;SkillRecoveryJournal\;RavenCreek`
- `Map`: List -> Semicolon-escaped map priority list.
  - Example: `RavenCreek\;Muldraugh, KY`

### Gameplay & Safety Switches:
- `PVP`: `[true | false]` -> Global player-versus-player damage flag.
- `PauseEmpty`: `[true | false]` -> Freezes world simulation time when 0 players are connected.
- `Open`: `[true | false]` -> If false, server requires manual whitelist approval.
- `AllowCoop`: `[true | false]` -> Enables cooperative multiplayer mechanics.
- `SleepAllowed`: `[true | false]` -> Allows player sleep mechanic.
- `SleepNeeded`: `[true | false]` -> Forces sleep requirement for fatigue recovery.
- `BackupsCount`: Integer -> Number of rotating backups retained (`5`).
- `BackupsOnStart`: `[true | false]` -> Triggers automated backup on container boot.

---

## 3. SANDBOX VARIABLES (`data/Server/<SERVER_NAME>_SandboxVars.lua`)

Lua Table Schema: `SandboxVars = { ... }`

### Key Sub-Tables & Fields:
- `ZombieConfig`:
  - `Population`: Integer `[1=Insane, 2=High, 3=Normal, 4=Low, 5=None]`
  - `Speed`: Integer `[1=Sprinters, 2=Fast Shamblers, 3=Shamblers]`
  - `Transmission`: Integer `[1=Blood+Saliva, 2=Saliva Only, 3=Everyone's Infected, 4=None]`
  - `InfectionMortality`: Integer `[1=Instant, 2=0-30 Secs, ..., 7=Never]`
  - `RallyGroupSize`: Integer `[0-1000]` -> Max zombie horde gathering size.
- `Loot`:
  - `CannedFood`, `Literature`, `Medical`, `Weapon`, `Ammo`: Integer `[1=Extremely Rare, 2=Rare, 3=Normal, 4=Common, 5=Abundant]`
- `World`:
  - `DayLength`: Integer `[1=15 min, 2=30 min, 3=1 hour (default), ..., 24=24 hours]`
  - `StartYear`, `StartMonth`, `StartDay`, `StartTime`: World time initialization.
  - `WaterShutModifier`, `ElecShutModifier`: Integer -> Days until utility shutoff `[-1=Instant, 1=0-30 days, 2=0-2 months, etc.]`
  - `ErosionSpeed`: Integer `[1=Very Fast (20 days), 2=Fast (50 days), 3=Normal (100 days), 4=Slow (200 days), 5=Very Slow (500 days)]`

---

## 4. SPAWN REGIONS (`data/Server/<SERVER_NAME>_spawnregions.lua`)

Lua Table Schema:
```lua
function SpawnRegions()
    return {
        { name = "Muldraugh, KY", file = "media/maps/Muldraugh, KY/spawnpoints.lua" },
        { name = "West Point, KY", file = "media/maps/West Point, KY/spawnpoints.lua" },
        { name = "Riverside, KY", file = "media/maps/Riverside, KY/spawnpoints.lua" },
        { name = "Rosewood, KY", file = "media/maps/Rosewood, KY/spawnpoints.lua" },
        -- Custom map additions:
        { name = "Raven Creek", file = "media/maps/RavenCreek/spawnpoints.lua" },
    }
end
```

---

## 5. PZ-PANEL INTEGRATION SCHEMA MAP

| PZ-Panel Route / Utility | Target File / Database in `pz-server` | Mode |
| :--- | :--- | :--- |
| `src/lib/serverUtils.ts` | `data/Server/<SERVER_NAME>.ini` | Read & Write (`WorkshopItems`, `Mods`, `Map`) |
| `src/lib/sandboxUtils.ts` | `data/Server/<SERVER_NAME>_SandboxVars.lua` | Read & Atomic Write (via `.tmp`) |
| `src/lib/playerUtils.ts` | `data/db/<SERVER_NAME>.db` | Read & Write (`whitelist`, `bannedips`, `bannedsteamids`) |
| `src/app/api/logs/route.ts` | `pz-server` Docker container stdout | Stream (`tail -f --tail 100`) |
