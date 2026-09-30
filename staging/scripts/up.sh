#!/usr/bin/env bash
# ==============================================================================
# START STAGING SERVER
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "INICIANDO SERVIDOR STAGING (42.21 UNSTABLE)"

cd "$STAGING_ROOT"

if [ ! -f "$DATA_PATH/Server/${SERVER_NAME}.ini" ]; then
    log_warn "No se encontró configuración en $DATA_PATH/Server/${SERVER_NAME}.ini."
    log_info "Ejecutando sincronización de configuración inicial desde PRD..."
    "$SCRIPT_DIR/sync_from_prd.sh" -f
fi

log_info "Levantando contenedor $CONTAINER_NAME..."
$DOCKER_COMPOSE_CMD up -d

log_success "Servidor de staging iniciado en segundo plano."
echo -e "  Rama:           ${CYAN}${SERVER_BRANCH}${NC}"
echo -e "  Puerto de juego: ${CYAN}${GAME_PORT}/UDP${NC}"
echo -e "  Puerto directo: ${CYAN}${DIRECT_PORT}/UDP${NC}"
echo -e "  Puerto RCON:    ${CYAN}${RCON_PORT}/TCP${NC}"
echo ""
echo -e "Para monitorear la descarga e inicio ejecuta:"
echo -e "  ${BOLD}./scripts/logs.sh${NC}"
