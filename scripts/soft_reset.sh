#!/usr/bin/env bash
# ==============================================================================
# SOFT RESET (REGENERAR LOOT Y ZOMBIS SIN PERDER PERSONAJES NI VEHÍCULOS)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "SOFT RESET DEL MUNDO ($SERVER_NAME)"

SAVE_DIR="$DATA_PATH/Saves/Multiplayer/$SERVER_NAME"

if [ ! -d "$SAVE_DIR" ]; then
    log_error "No se encontró el directorio de la partida: $SAVE_DIR"
    exit 1
fi

echo -e "${YELLOW}⚠️  ADVERTENCIA: El Soft Reset eliminará los archivos de chunks y población de zombis.${NC}"
echo -e "Esto provocará:"
echo -e "  ✅ Regeneración del loot en contenedores del mapa."
echo -e "  ✅ Reaparición y redistribución de zombis."
echo -e "  🛡️  Se conservan: Personajes (${BOLD}players.db${NC}), Cuentas (${BOLD}whitelist${NC}) y Vehículos (${BOLD}vehicles.db${NC})."
echo -e "  ⚠️  Los objetos dejados en el suelo y construcciones no guardadas en edificios reconocidos podrían resetearse."
echo ""

if is_container_running; then
    log_warn "El servidor está encendido. Es obligatorio detenerlo antes de realizar el Soft Reset."
    read -rp "¿Deseas detener el servidor ahora? (s/N): " CONFIRM_STOP
    if [[ ! "$CONFIRM_STOP" =~ ^[sSyY]$ ]]; then
        log_error "Operación cancelada."
        exit 1
    fi
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD down
    log_success "Servidor detenido."
fi

read -rp "¿Confirmas realizar el Soft Reset en la partida '$SERVER_NAME'? (s/N): " CONFIRM_RESET
if [[ ! "$CONFIRM_RESET" =~ ^[sSyY]$ ]]; then
    log_info "Operación cancelada."
    exit 0
fi

# 1. Crear backup preventivo
log_info "Creando backup previo de seguridad..."
"$SCRIPT_DIR/backup.sh" --stop

# 2. Borrar chunkdata y zpop
log_info "Eliminando datos de chunks y spawns de zombis..."
if [ -d "$SAVE_DIR/chunkdata" ]; then
    rm -rf "$SAVE_DIR/chunkdata"/*
    log_info "Carpeta chunkdata limpiada."
fi

if [ -d "$SAVE_DIR/zpop" ]; then
    rm -rf "$SAVE_DIR/zpop"/*
    log_info "Carpeta zpop limpiada."
fi

log_success "¡Soft Reset completado con éxito!"
echo "Al arrancar el servidor se generarán chunks frescos con nuevo loot."
