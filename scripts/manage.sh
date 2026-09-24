#!/usr/bin/env bash
# ==============================================================================
# PROJECT ZOMBOID SERVER MANAGEMENT CLI
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

show_menu() {
    clear || true
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║       PROJECT ZOMBOID DEDICATED SERVER CONTROL PANEL         ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Servidor: ${CYAN}${SERVER_NAME}${NC} | Contenedor: ${CYAN}${CONTAINER_NAME}${NC}"
    
    if is_container_running; then
        echo -e "  Estado:   ${GREEN}● EN LÍNEA${NC}"
    else
        echo -e "  Estado:   ${RED}○ DETENIDO${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}GESTIÓN DE CONTENEDOR:${NC}"
    echo -e "    ${BOLD}1)${NC} Iniciar servidor (docker compose up -d)"
    echo -e "    ${BOLD}2)${NC} Detener servidor de forma segura (docker compose down)"
    echo -e "    ${BOLD}3)${NC} Reiniciar servidor (docker compose restart)"
    echo -e "    ${BOLD}4)${NC} Ver logs en vivo (Ctrl+C para salir)"
    echo -e "    ${BOLD}5)${NC} Entrar a consola de administración del juego (RCON / attach)"
    echo ""
    echo -e "  ${BOLD}ESTADO, JUGADORES Y PARTIDAS:${NC}"
    echo -e "    ${BOLD}6)${NC} Ver estado y métricas de rendimiento (CPU/RAM/Puertos)"
    echo -e "    ${BOLD}7)${NC} Listar partidas, cuentas y jugadores conectados"
    echo ""
    echo -e "  ${BOLD}RESPALDOS Y MANTENIMIENTO:${NC}"
    echo -e "    ${BOLD}8)${NC} Crear copia de seguridad (Backup tar.gz)"
    echo -e "    ${BOLD}9)${NC} Restaurar copia de seguridad (Restore)"
    echo -e "   ${BOLD}10)${NC} Soft Reset del mundo (Regenerar loot y zombis)"
    echo ""
    echo -e "    ${BOLD}0)${NC} Salir"
    echo ""
}

run_action() {
    case "$1" in
        start|1)
            cd "$PROJECT_ROOT"
            log_info "Iniciando servidor..."
            $DOCKER_COMPOSE_CMD up -d
            log_success "Servidor iniciado."
            ;;
        stop|2)
            cd "$PROJECT_ROOT"
            log_info "Deteniendo servidor de forma segura (guardando mundo)..."
            $DOCKER_COMPOSE_CMD down
            log_success "Servidor detenido."
            ;;
        restart|3)
            cd "$PROJECT_ROOT"
            log_info "Reiniciando servidor..."
            $DOCKER_COMPOSE_CMD restart "$CONTAINER_NAME"
            log_success "Servidor reiniciado."
            ;;
        logs|4)
            cd "$PROJECT_ROOT"
            $DOCKER_COMPOSE_CMD logs --tail=100 -f "$CONTAINER_NAME"
            ;;
        attach|5)
            if ! is_container_running; then
                log_warn "El servidor no está en ejecución."
                return
            fi
            echo -e "${YELLOW}⚠️  Para salir de la consola sin apagar el server usa: Ctrl+P y luego Ctrl+Q (NO uses Ctrl+C).${NC}"
            read -rp "Presiona [ENTER] para entrar..."
            docker attach "$CONTAINER_NAME"
            ;;
        status|6)
            "$SCRIPT_DIR/status.sh"
            ;;
        players|saves|7)
            "$SCRIPT_DIR/list_players_and_saves.sh"
            ;;
        backup|8)
            "$SCRIPT_DIR/backup.sh"
            ;;
        restore|9)
            "$SCRIPT_DIR/restore.sh"
            ;;
        soft-reset|10)
            "$SCRIPT_DIR/soft_reset.sh"
            ;;
        0|exit|quit|q)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            log_error "Comando o selección no válida: $1"
            echo "Uso: $(basename "$0") [start|stop|restart|logs|attach|status|players|backup|restore|soft-reset]"
            exit 1
            ;;
    esac
}

# Si se pasaron argumentos de línea de comandos, ejecutar directamente
if [ $# -gt 0 ]; then
    run_action "$1"
    exit 0
fi

# Modo interactivo
while true; do
    show_menu
    read -rp "Selecciona una opción [0-10]: " CHOICE
    run_action "$CHOICE"
    echo ""
    read -rp "Presiona [ENTER] para continuar..."
done
