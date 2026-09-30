#!/usr/bin/env bash
# ==============================================================================
# STAGING SERVER MANAGEMENT CLI
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

show_menu() {
    clear || true
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║       PROJECT ZOMBOID STAGING SERVER CONTROL PANEL           ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Servidor:  ${CYAN}${SERVER_NAME}${NC} | Contenedor: ${CYAN}${CONTAINER_NAME}${NC}"
    echo -e "  Versión:   ${YELLOW}Build 42.21 Unstable (Puerto ${GAME_PORT})${NC}"
    
    if is_container_running; then
        echo -e "  Estado:    ${GREEN}● EN LÍNEA${NC}"
    else
        echo -e "  Estado:    ${RED}○ DETENIDO${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}GESTIÓN DEL SERVIDOR STAGING:${NC}"
    echo -e "    ${BOLD}1)${NC} Iniciar servidor (docker compose up -d)"
    echo -e "    ${BOLD}2)${NC} Detener servidor de forma segura (docker compose down)"
    echo -e "    ${BOLD}3)${NC} Reiniciar servidor (docker compose restart)"
    echo -e "    ${BOLD}4)${NC} Ver logs en vivo (Ctrl+C para salir)"
    echo -e "    ${BOLD}5)${NC} Ver estado, métricas y versión detectada"
    echo ""
    echo -e "  ${BOLD}SINCRONIZACIÓN DESDE PRODUCCIÓN:${NC}"
    echo -e "    ${BOLD}6)${NC} Sincronizar mods y reglas (Mundo nuevo limpio)"
    echo -e "    ${BOLD}7)${NC} Sincronizar mods + clonar partida actual para prueba de migración"
    echo ""
    echo -e "  ${BOLD}CONSOLA / RCON:${NC}"
    echo -e "    ${BOLD}8)${NC} Enviar comando RCON (players, save, etc.)"
    echo ""
    echo -e "    ${BOLD}0)${NC} Salir"
    echo ""
}

run_action() {
    case "$1" in
        start|up|1)
            "$SCRIPT_DIR/up.sh"
            ;;
        stop|down|2)
            "$SCRIPT_DIR/down.sh"
            ;;
        restart|3)
            "$SCRIPT_DIR/restart.sh"
            ;;
        logs|4)
            "$SCRIPT_DIR/logs.sh"
            ;;
        status|5)
            "$SCRIPT_DIR/status.sh"
            ;;
        sync|6)
            "$SCRIPT_DIR/sync_from_prd.sh"
            ;;
        sync-save|7)
            "$SCRIPT_DIR/sync_from_prd.sh" --with-save
            ;;
        rcon|8)
            "$SCRIPT_DIR/rcon.sh"
            ;;
        0|exit|quit|q)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            log_error "Opción no válida: $1"
            ;;
    esac
}

if [ $# -gt 0 ]; then
    run_action "$1"
    exit 0
fi

while true; do
    show_menu
    read -rp "Selecciona una opción [0-8]: " CHOICE
    run_action "$CHOICE"
    echo ""
    read -rp "Presiona [ENTER] para continuar..."
done
