#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK PRODUCTION SERVER TO BUILD 42.20.4 STABLE & RESTORE SNAPSHOT
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

FORCE=false
SPECIFIED_BACKUP=""
BACKUP_DIR="$DATA_PATH/backups"

show_help() {
    cat << EOF
Uso: $(basename "$0") [RUTA_SNAPSHOT] [OPCIONES]

Restaura de forma segura el servidor de producción a la versión estable 42.20.4
y reestablece el mundo, base de datos y configuraciones desde un snapshot preventivo.

Argumentos:
  RUTA_SNAPSHOT         Ruta a un archivo .tar.gz de respaldo específico.
                        Si se omite, detectará el snapshot creado antes del último upgrade.

Opciones:
  -y, --yes             Modo no interactivo / confirmación automática.
  -h, --help            Muestra esta ayuda.

Ejemplo:
  $(basename "$0")
  $(basename "$0") data/backups/snapshot_pre_42_21_20260928_120000.tar.gz -y
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            log_error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$SPECIFIED_BACKUP" ]; then
                SPECIFIED_BACKUP="$1"
            fi
            shift
            ;;
    esac
done

log_header "ROLLBACK A PROJECT ZOMBOID 42.20 (PRODUCCIÓN)"

# 1. Localizar el snapshot adecuado
TARGET_SNAPSHOT=""

if [ -n "$SPECIFIED_BACKUP" ]; then
    if [ ! -f "$SPECIFIED_BACKUP" ]; then
        log_error "El archivo de respaldo especificado no existe: $SPECIFIED_BACKUP"
        exit 1
    fi
    TARGET_SNAPSHOT="$SPECIFIED_BACKUP"
elif [ -f "$BACKUP_DIR/.last_pre_upgrade_snapshot" ]; then
    RECORDED_FILE="$(cat "$BACKUP_DIR/.last_pre_upgrade_snapshot")"
    if [ -f "$RECORDED_FILE" ]; then
        TARGET_SNAPSHOT="$RECORDED_FILE"
        log_info "Snapshot pre-upgrade detectado automáticamente: $(basename "$TARGET_SNAPSHOT")"
    fi
fi

# Si aún no tenemos snapshot, mostrar lista para elegir
if [ -z "$TARGET_SNAPSHOT" ]; then
    log_info "Buscando snapshots disponibles en $BACKUP_DIR..."
    # shellcheck disable=SC2012
    AVAILABLE_BACKUPS=($(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true))
    
    if [ ${#AVAILABLE_BACKUPS[@]} -eq 0 ]; then
        log_error "No se encontraron archivos de respaldo .tar.gz en $BACKUP_DIR."
        exit 1
    fi

    echo -e "${BOLD}Snapshots disponibles:${NC}"
    for i in "${!AVAILABLE_BACKUPS[@]}"; do
        b_file="${AVAILABLE_BACKUPS[$i]}"
        b_size="$(du -h "$b_file" | awk '{print $1}')"
        b_date="$(date -r "$b_file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c '%y' "$b_file" 2>/dev/null | cut -d'.' -f1)"
        echo -e "  [$((i+1))] $(basename "$b_file")  ${CYAN}($b_size - $b_date)${NC}"
    done
    echo ""
    read -rp "Selecciona el número de snapshot a restaurar (1-${#AVAILABLE_BACKUPS[@]}) [o 'q' para cancelar]: " SELECTION

    if [[ "$SELECTION" =~ ^[qQ]$ ]]; then
        log_info "Rollback cancelado por el usuario."
        exit 0
    fi

    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#AVAILABLE_BACKUPS[@]}" ]; then
        log_error "Selección inválida."
        exit 1
    fi

    TARGET_SNAPSHOT="${AVAILABLE_BACKUPS[$((SELECTION-1))]}"
fi

log_info "Snapshot seleccionado: $TARGET_SNAPSHOT"
SNAPSHOT_SIZE="$(du -h "$TARGET_SNAPSHOT" | awk '{print $1}')"

# 2. Confirmación de seguridad
if [ "$FORCE" = false ]; then
    echo -e "\n${YELLOW}⚠️  ADVERTENCIA DE ROLLBACK:${NC}"
    echo -e "  - El servidor cambiará de la rama ${RED}unstable (42.21)${NC} a la rama ${GREEN}estable (42.20.4)${NC}."
    echo -e "  - La partida actual en 42.21 será reemplazada por los datos del snapshot ($SNAPSHOT_SIZE)."
    echo -e "  - Los jugadores deberán desactivar la beta en Steam para poder conectarse."
    echo ""
    read -rp "¿Estás seguro de que deseas proceder con el rollback? (s/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
        log_info "Operación cancelada por el usuario."
        exit 0
    fi
fi

# 3. Detener servidor si está corriendo
if is_container_running; then
    log_info "Deteniendo contenedor $CONTAINER_NAME..."
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD down
    log_success "Servidor detenido."
fi

# 4. Limpiar datos de partida 42.21 incompatible
log_info "Limpiando datos actuales de partida para restaurar snapshot limpio..."
rm -rf "$DATA_PATH/Saves/Multiplayer/${SERVER_NAME}"
rm -rf "$DATA_PATH/db/"*

# 5. Extraer snapshot
log_info "Restaurando archivos desde el snapshot..."
tar -xzf "$TARGET_SNAPSHOT" -C "$DATA_PATH"
log_success "Archivos del snapshot restaurados con éxito."

# 6. Revertir rama a stable en .env
log_info "Restableciendo SERVER_BRANCH a estable en .env..."
if grep -q "^SERVER_BRANCH=" "$PROJECT_ROOT/.env"; then
    sed -i 's/^SERVER_BRANCH=.*/SERVER_BRANCH=/' "$PROJECT_ROOT/.env"
fi

# 7. Aplicar permisos correctos
log_info "Verificando permisos (UID:$PUID, GID:$PGID)..."
chown -R "$PUID:$PGID" "$DATA_PATH" 2>/dev/null || chmod -R 775 "$DATA_PATH" || true
chmod -R 775 "$DATA_PATH" 2>/dev/null || true

# 8. Iniciar el servidor en rama estable
log_info "Iniciando servidor (DepotDownloader descargará/validará 42.20.4)..."
cd "$PROJECT_ROOT"
$DOCKER_COMPOSE_CMD up -d

log_success "¡Rollback completado exitosamente!"
echo ""
echo -e "${GREEN}● El servidor está volviendo a iniciar en la versión estable 42.20.4 con el snapshot intacto.${NC}"
echo -e "${YELLOW}📢 AVISO PARA LOS JUGADORES:${NC}"
echo -e "   Pide a los jugadores que desactiven la beta en Steam:"
echo -e "   Propiedades > Betas > Participación en la beta: ${BOLD}'Ninguna'${NC}."
echo ""
echo -e "Monitorear inicio:"
echo -e "  ${BOLD}docker compose logs -f${NC}"
echo ""

if [ "$FORCE" = false ]; then
    read -rp "¿Deseas seguir los logs en vivo ahora? (S/n): " FOLLOW_LOGS
    if [[ ! "$FOLLOW_LOGS" =~ ^[nN]$ ]]; then
        $DOCKER_COMPOSE_CMD logs -f
    fi
fi
