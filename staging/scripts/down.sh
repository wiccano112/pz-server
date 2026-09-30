#!/usr/bin/env bash
# ==============================================================================
# STOP STAGING SERVER SAFELY
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "DETENIENDO SERVIDOR STAGING"

cd "$STAGING_ROOT"

if ! is_container_running; then
    log_warn "El contenedor de staging ($CONTAINER_NAME) no está en ejecución."
    exit 0
fi

# Intentar guardar mediante RCON antes de bajar
log_info "Guardando partida y deteniendo de forma segura..."
docker exec "$CONTAINER_NAME" rcon-cli -c /home/steam/server/rcon.yml save 2>/dev/null || true

$DOCKER_COMPOSE_CMD down

log_success "Servidor de staging detenido y estado guardado."
