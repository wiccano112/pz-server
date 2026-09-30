#!/usr/bin/env bash
# ==============================================================================
# STAGING SERVER STATUS & METRICS
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "ESTADO DEL SERVIDOR STAGING ($SERVER_NAME)"

echo -e "${BOLD}1. Estado del Contenedor:${NC}"
if is_container_running; then
    echo -e "  Contenedor:  ${GREEN}● EN LÍNEA${NC} ($CONTAINER_NAME)"
    UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" | cut -d'.' -f1)
    echo -e "  Iniciado en: $UPTIME"
else
    echo -e "  Contenedor:  ${RED}○ DETENIDO${NC} ($CONTAINER_NAME)"
fi

echo -e "\n${BOLD}2. Parámetros de Red y Versión:${NC}"
echo -e "  Rama configurada:      ${CYAN}${SERVER_BRANCH}${NC}"
echo -e "  Puerto Juego (Host):   ${CYAN}${GAME_PORT}/UDP${NC} -> 16261"
echo -e "  Puerto Directo (Host): ${CYAN}${DIRECT_PORT}/UDP${NC} -> 16262"
echo -e "  Puerto RCON (Host):    ${CYAN}${RCON_PORT}/TCP${NC} -> 27015"

echo -e "\n${BOLD}3. Versión del Juego detectada en consola:${NC}"
if [ -f "$DATA_PATH/server-console.txt" ]; then
    VERSION_LINE=$(grep -i "version=" "$DATA_PATH/server-console.txt" | tail -n 1 || true)
    if [ -n "$VERSION_LINE" ]; then
        echo -e "  $VERSION_LINE"
    else
        echo -e "  (El log no contiene aún la línea de versión)"
    fi
else
    echo -e "  (No se ha generado data/server-console.txt todavía)"
fi

echo -e "\n${BOLD}4. Mods Configurados en INI:${NC}"
INI_FILE="$DATA_PATH/Server/${SERVER_NAME}.ini"
if [ -f "$INI_FILE" ]; then
    MODS=$(grep -E "^Mods=" "$INI_FILE" | cut -d'=' -f2-)
    WORKSHOP=$(grep -E "^WorkshopItems=" "$INI_FILE" | cut -d'=' -f2-)
    echo -e "  Mods:          ${YELLOW}${MODS}${NC}"
    echo -e "  Workshop IDs:  ${YELLOW}${WORKSHOP}${NC}"
else
    echo -e "  (El archivo $INI_FILE aún no existe. Ejecuta ./scripts/sync_from_prd.sh)"
fi

if is_container_running; then
    echo -e "\n${BOLD}5. Uso de Recursos (Docker Stats):${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" "$CONTAINER_NAME"
fi
echo ""
