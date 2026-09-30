#!/usr/bin/env bash
# ==============================================================================
# EXECUTE RCON COMMAND AGAINST STAGING SERVER
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

if ! is_container_running; then
    log_error "El servidor de staging ($CONTAINER_NAME) no está en ejecución."
    exit 1
fi

CMD="${*:-}"

if [ -z "$CMD" ]; then
    echo -e "${CYAN}Ingresa el comando RCON a ejecutar (ej: players, save, help, checkMods):${NC}"
    read -rp "> " CMD
fi

if [ -n "$CMD" ]; then
    docker exec "$CONTAINER_NAME" rcon-cli -c /home/steam/server/rcon.yml "$CMD"
fi
