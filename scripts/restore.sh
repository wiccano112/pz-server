#!/usr/bin/env bash
# ==============================================================================
# PROJECT ZOMBOID SERVER RESTORATION SCRIPT
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

SOURCE_PATH="${1:-}"
FORCE="${2:-}"
BACKUP_DIR="${DATA_PATH}/backups"

show_help() {
    cat << EOF
Uso: $(basename "$0") [RUTA_ARCHIVO_O_DIRECTORIO] [OPCIONES]

Restaura la configuración, partidas y base de datos del servidor desde un archivo .tar.gz o un directorio.

Argumentos:
  RUTA_ARCHIVO_O_DIRECTORIO   Ruta a un archivo .tar.gz o carpeta con el respaldo.
                              Si se omite, se mostrará un menú interactivo con los respaldos de data/backups/.

Opciones:
  -y, --yes                   Modo no interactivo / confirmación automática.
  -h, --help                  Muestra esta ayuda.

Ejemplos:
  $(basename "$0")                                             # Selección interactiva
  $(basename "$0") data/backups/backup_NobaraZomboid_20260905.tar.gz
  $(basename "$0") /mnt/respaldos/backup_NobaraZomboid/
EOF
}

if [ "$SOURCE_PATH" = "-h" ] || [ "$SOURCE_PATH" = "--help" ]; then
    show_help
    exit 0
fi

log_header "RESTAURACIÓN DEL SERVIDOR"

# Si no se pasó argumento, buscar respaldos disponibles en data/backups
if [ -z "$SOURCE_PATH" ]; then
    log_info "Buscando respaldos disponibles en $BACKUP_DIR..."
    
    # shellcheck disable=SC2012
    BACKUPS=($(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true))
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        log_error "No se encontraron archivos .tar.gz en $BACKUP_DIR."
        echo "Indica manualmente la ruta al archivo o directorio de respaldo:"
        echo "  $(basename "$0") /ruta/al/respaldo"
        exit 1
    fi

    echo -e "${BOLD}Respaldos encontrados:${NC}"
    for i in "${!BACKUPS[@]}"; do
        b_file="${BACKUPS[$i]}"
        b_size="$(du -h "$b_file" | awk '{print $1}')"
        b_date="$(date -r "$b_file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c '%y' "$b_file" 2>/dev/null | cut -d'.' -f1)"
        echo -e "  [$((i+1))] $(basename "$b_file")  ${CYAN}($b_size - $b_date)${NC}"
    done
    echo ""
    read -rp "Selecciona el número de respaldo a restaurar (1-${#BACKUPS[@]}) [o 'q' para cancelar]: " SELECTION

    if [[ "$SELECTION" =~ ^[qQ]$ ]]; then
        log_info "Operación cancelada por el usuario."
        exit 0
    fi

    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#BACKUPS[@]}" ]; then
        log_error "Selección inválida."
        exit 1
    fi

    SOURCE_PATH="${BACKUPS[$((SELECTION-1))]}"
fi

if [ ! -e "$SOURCE_PATH" ]; then
    log_error "La ruta de respaldo especificada no existe: $SOURCE_PATH"
    exit 1
fi

log_info "Fuente seleccionada: $SOURCE_PATH"

# 1. Verificar si el contenedor está en ejecución
if is_container_running; then
    log_warn "El servidor ($CONTAINER_NAME) está en ejecución."
    log_warn "Regla obligatoria: La restauración sólo debe realizarse con el servidor apagado para evitar corrupción."
    
    if [ "$FORCE" != "-y" ] && [ "$FORCE" != "--yes" ]; then
        read -rp "¿Deseas detener el servidor ahora para continuar? (s/N): " CONFIRM_STOP
        if [[ ! "$CONFIRM_STOP" =~ ^[sSyY]$ ]]; then
            log_error "Restauración cancelada. Debes detener el servidor primero (docker compose down)."
            exit 1
        fi
    fi

    log_info "Deteniendo contenedor $CONTAINER_NAME..."
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD down
    log_success "Servidor detenido correctamente."
fi

# 2. Confirmación previa de seguridad
if [ "$FORCE" != "-y" ] && [ "$FORCE" != "--yes" ]; then
    echo -e "\n${YELLOW}⚠️  ADVERTENCIA: Esta acción sobreescribirá los datos del servidor (Saves, Server, db).${NC}"
    read -rp "¿Estás seguro de continuar con la restauración? (s/N): " CONFIRM_RESTORE
    if [[ ! "$CONFIRM_RESTORE" =~ ^[sSyY]$ ]]; then
        log_info "Restauración cancelada por el usuario."
        exit 0
    fi
fi

# 3. Crear snapshot de seguridad previo del estado actual
PRE_RESTORE_NAME="pre_restore_safety_$(date +%Y%m%d_%H%M%S).tar.gz"
log_info "Creando copia de seguridad de seguridad preventiva en $BACKUP_DIR/$PRE_RESTORE_NAME..."
mkdir -p "$BACKUP_DIR"
(
    cd "$DATA_PATH"
    SAFETY_ITEMS=()
    [ -d "Saves" ] && SAFETY_ITEMS+=("Saves")
    [ -d "Server" ] && SAFETY_ITEMS+=("Server")
    [ -d "db" ] && SAFETY_ITEMS+=("db")
    [ -f "options.ini" ] && SAFETY_ITEMS+=("options.ini")
    if [ ${#SAFETY_ITEMS[@]} -gt 0 ]; then
        tar -czf "$BACKUP_DIR/$PRE_RESTORE_NAME" "${SAFETY_ITEMS[@]}"
        log_success "Snapshot preventivo generado: $PRE_RESTORE_NAME"
    fi
)

# 4. Restaurar archivos
if [ -f "$SOURCE_PATH" ]; then
    # Archivo .tar.gz o .tar
    log_info "Extrayendo archivo de respaldo en $DATA_PATH..."
    tar -xzvf "$SOURCE_PATH" -C "$DATA_PATH"
elif [ -d "$SOURCE_PATH" ]; then
    # Directorio
    log_info "Copiando datos desde el directorio $SOURCE_PATH hacia $DATA_PATH..."
    for folder in Saves Server db options.ini mods; do
        if [ -e "$SOURCE_PATH/$folder" ]; then
            log_info "Restaurando $folder..."
            cp -a "$SOURCE_PATH/$folder" "$DATA_PATH/"
        fi
    done
fi

# 5. Ajustar permisos
log_info "Verificando y aplicando permisos correctos (UID:$PUID, GID:$PGID)..."
if [ "$(id -u)" -eq 0 ]; then
    chown -R "$PUID:$PGID" "$DATA_PATH"
    chmod -R 775 "$DATA_PATH"
else
    # Si no es root, intentar chown o advertir
    chown -R "$PUID:$PGID" "$DATA_PATH" 2>/dev/null || chmod -R 775 "$DATA_PATH" || true
fi
log_success "Permisos aplicados correctamente."

# 6. Resumen y arranque opcional
log_success "¡Restauración completada con éxito!"

if [ "$FORCE" != "-y" ] && [ "$FORCE" != "--yes" ]; then
    read -rp "¿Deseas iniciar el servidor ahora? (S/n): " START_NOW
    if [[ ! "$START_NOW" =~ ^[nN]$ ]]; then
        log_info "Iniciando servidor..."
        cd "$PROJECT_ROOT"
        $DOCKER_COMPOSE_CMD up -d
        log_success "Servidor iniciado en segundo plano. Puedes monitorear los logs con: docker compose logs -f"
    fi
fi
