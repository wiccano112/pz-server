#!/usr/bin/env bash
# ==============================================================================
# RESTART STAGING SERVER
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "REINICIANDO SERVIDOR STAGING"

cd "$STAGING_ROOT"

if is_container_running; then
    docker exec "$CONTAINER_NAME" rcon-cli -c /home/steam/server/rcon.yml save 2>/dev/null || true
    $DOCKER_COMPOSE_CMD restart "$CONTAINER_NAME"
    log_success "Servidor de staging reiniciado."
else
    log_warn "El servidor no estaba en ejecución. Iniciando..."
    $DOCKER_COMPOSE_CMD up -d
    log_success "Servidor de staging iniciado."
fi
