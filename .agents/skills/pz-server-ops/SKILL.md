---
name: pz-server-ops
description: >-
  Operational workflows, runbooks, and automation procedures for the Project Zomboid Dedicated Server under Docker.
  Use when testing or adding mods, running staging environment experiments, upgrading to Build 42.21, or rolling back.
---

# Project Zomboid Server Operations Skill

This skill defines deterministic runbooks and best practices for managing the dual-environment Project Zomboid dedicated server setup (`pz-server` in production and `pz-rpm-server-stg` in staging).

---

## 1. Golden Rules & Invariants

1. **Mutation At Rest Only**: Always shut down the container (`docker compose down`) before modifying `.ini`, `.lua`, or database files via CLI.
2. **Staging-First Testing (Mandatory)**: All changes—especially adding/updating Steam Workshop mods or upgrading game versions/branches—**must be tested in staging first**. Never apply untested mods directly to production.
3. **Delimiter Syntax**: Always use standard semicolons (`item1;item2`) in INI lists (`Mods`, `WorkshopItems`, `Map`). Do NOT escape with backslashes.
4. **Player Audit**: Before shutting down production, always audit active players via RCON (`players`) and broadcast maintenance notices (`servermsg`).

---

## 2. Server Environments Matrix

| Attribute | Production (`pz-server`) | Staging (`pz-rpm-server-stg`) |
| :--- | :--- | :--- |
| **Path** | `/home/perro/pz-server/` | `/home/perro/pz-server/staging/` |
| **Branch** | `stable` (Build 42.20.4) | `SERVER_BRANCH=unstable` (Build 42.21) |
| **Game Port** | `16261/UDP` | `17261/UDP` |
| **Direct Connect** | `16262/UDP` | `17262/UDP` |
| **RCON Port** | `27015/TCP` | `27025/TCP` |
| **CPU Pinning** | `cpuset: "12-17"` (6 E-cores) | `cpuset: "0-3"` (4 P-cores dedicated) |
| **RAM Limit** | 8 GB host allocation | `mem_limit: 6g` (Docker hard limit) |
| **Data Directory** | `./data` | `./staging/data` |

---

## 3. Workflows & Runbooks

### Workflow A: Testing a New Mod (Staging-First)

1. **Synchronize or Prepare Staging**:
   ```bash
   cd /home/perro/pz-server/staging
   ./scripts/sync_from_prd.sh
   ```
2. **Add Mod to Staging INI**:
   - Edit `staging/data/Server/pz-rpm-server-stg.ini` (server must be stopped).
   - Append `WorkshopID` to `WorkshopItems=...;<NEW_WORKSHOP_ID>`.
   - Append `ModID` to `Mods=...;<NEW_MOD_ID>`.
   - If map mod: Prepend map folder name to `Map=<NEW_MAP_NAME>;...`.
3. **Start Staging and Audit Logs**:
   ```bash
   ./scripts/up.sh
   ./scripts/logs.sh
   ```
   - Verify `Workshop item <ID> up to date`.
   - Verify `MOD: <ModID> loaded`.
   - Ensure no fatal Java `Exception` or broken Lua dependencies.
4. **Promote to Production**:
   - Once validated, stop production: `cd /home/perro/pz-server && docker compose down`.
   - Apply the same entries to `data/Server/NobaraZomboid.ini`.
   - Start production: `docker compose up -d`.

---

### Workflow B: Production Upgrade to Build 42.21

1. **Verify on Staging first** (run `cd staging && ./scripts/up.sh`).
2. **Coordinate with Players**:
   - Instruct players to switch Steam branch to:
     `Library > Project Zomboid > Properties > Betas > "unstable - Unstable Build 42"`.
3. **Execute Automated Upgrade**:
   ```bash
   cd /home/perro/pz-server
   ./scripts/upgrade_to_42_21.sh
   # Or via interactive menu: ./scripts/manage.sh (Option 11)
   ```
   - Checks active players and offers in-game broadcast.
   - Saves world state and halts container gracefully.
   - Takes full snapshot into `data/backups/snapshot_pre_42_21_<timestamp>.tar.gz`.
   - Configures `SERVER_BRANCH=unstable` in `.env`.
   - Starts container and streams initial download.

---

### Workflow C: Production Rollback to Build 42.20.4

If Build 42.21 causes game-breaking issues:

1. **Execute Automated Rollback**:
   ```bash
   cd /home/perro/pz-server
   ./scripts/rollback_to_42_20.sh
   # Or via interactive menu: ./scripts/manage.sh (Option 12)
   ```
   - Automatically locates pre-upgrade snapshot.
   - Halts container safely.
   - Purges incompatible 42.21 world files and restores 42.20 snapshot.
   - Reverts `SERVER_BRANCH=` to stable in `.env`.
   - Boots container and validates stable branch binaries.
2. **Notify Players**: Instruct players to set their Steam Beta back to "None".
