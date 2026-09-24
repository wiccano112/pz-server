#!/usr/bin/env bash
# ==============================================================================
# PROJECT ZOMBOID SERVER BACKUP SCRIPT
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

BACKUP_DIR="${DATA_PATH}/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DEFAULT_FILENAME="backup_${SERVER_NAME}_${TIMESTAMP}.tar.gz"
CUSTOM_OUTPUT=""
COPY_TO_DIR=""
STOP_SERVER=false
KEEP_COUNT=0

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [OPCIONES]

Crea una copia de seguridad segura de la configuración, base de datos y partidas del servidor.

Opciones:
  -s, --stop            Detiene el servidor (docker compose stop) antes de respaldar para máxima consistencia
  -o, --output FILE     Nombre o ruta personalizada para el archivo .tar.gz
  -d, --dir DIR         Respaldar a un directorio en lugar de un archivo comprimido .tar.gz
  -k, --keep NUM        Conservar sólo los últimos NUM backups en el directorio de respaldos
  -h, --help            Muestra esta ayuda

Ejemplos:
  $(basename "$0")                     # Crea data/backups/backup_${SERVER_NAME}_<timestamp>.tar.gz
  $(basename "$0") --stop              # Apaga el server, hace backup y lo vuelve a encender
  $(basename "$0") --keep 5            # Crea backup y conserva los últimos 5 archivos
  $(basename "$0") -d /mnt/external    # Respalda como estructura de carpetas en /mnt/external
EOF
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--stop|--safe)
            STOP_SERVER=true
            shift
            ;;
        -o|--output)
            CUSTOM_OUTPUT="$2"
            shift 2
            ;;
        -d|--dir)
            COPY_TO_DIR="$2"
            shift 2
            ;;
        -k|--keep)
            KEEP_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

mkdir -p "$BACKUP_DIR"

log_header "RESPALDO DEL SERVIDOR ($SERVER_NAME)"

WAS_RUNNING=false
if is_container_running; then
    WAS_RUNNING=true
fi

# Si se solicitó detener el servidor
if [ "$STOP_SERVER" = true ] && [ "$WAS_RUNNING" = true ]; then
    log_info "Deteniendo el servidor para garantizar consistencia del mundo y base de datos..."
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD stop "$CONTAINER_NAME"
    log_success "Servidor detenido temporalmente."
elif [ "$WAS_RUNNING" = true ]; then
    log_warn "El servidor está en ejecución. Se realizará un snapshot en caliente."
    log_info "(Tip: Usa --stop para apagar el contenedor durante el backup y evitar datos en memoria sin guardar)."
fi

# Preparar elementos a respaldar
cd "$DATA_PATH"
TARGETS=()
[ -d "Saves" ] && TARGETS+=("Saves")
[ -d "Server" ] && TARGETS+=("Server")
[ -d "db" ] && TARGETS+=("db")
[ -f "options.ini" ] && TARGETS+=("options.ini")
[ -d "mods" ] && TARGETS+=("mods")

if [ ${#TARGETS[@]} -eq 0 ]; then
    log_error "No se encontraron carpetas críticas (Saves, Server, db) en $DATA_PATH."
    exit 1
fi

log_info "Elementos a incluir: ${TARGETS[*]}"

if [ -n "$COPY_TO_DIR" ]; then
    # Modo copia a directorio
    DEST_DIR="$COPY_TO_DIR/backup_${SERVER_NAME}_${TIMESTAMP}"
    mkdir -p "$DEST_DIR"
    log_info "Copiando archivos a $DEST_DIR..."
    for item in "${TARGETS[@]}"; do
        cp -a "$item" "$DEST_DIR/"
    done
    log_success "Respaldo copiado exitosamente en: $DEST_DIR"
else
    # Modo archivo tar.gz
    if [ -n "$CUSTOM_OUTPUT" ]; then
        DEST_FILE="$CUSTOM_OUTPUT"
    else
        DEST_FILE="$BACKUP_DIR/$DEFAULT_FILENAME"
    fi

    log_info "Generando archivo comprimido en $DEST_FILE..."
    tar -czf "$DEST_FILE" "${TARGETS[@]}"
    
    FILE_SIZE="$(du -h "$DEST_FILE" | awk '{print $1}')"
    log_success "Respaldo generado con éxito: $DEST_FILE ($FILE_SIZE)"
fi

# Reiniciar el servidor si fue detenido por este script
if [ "$STOP_SERVER" = true ] && [ "$WAS_RUNNING" = true ]; then
    log_info "Reiniciando el contenedor del servidor..."
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD start "$CONTAINER_NAME"
    log_success "Servidor reiniciado y operativo."
fi

# Purgar backups antiguos si se configuró --keep
if [ "$KEEP_COUNT" -gt 0 ]; then
    log_info "Verificando rotación de respaldos (conservando últimos $KEEP_COUNT)..."
    # shellcheck disable=SC2012
    TOTAL_BACKUPS=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | wc -l || echo 0)
    if [ "$TOTAL_BACKUPS" -gt "$KEEP_COUNT" ]; then
        TO_DELETE=$((TOTAL_BACKUPS - KEEP_COUNT))
        # shellcheck disable=SC2012
        ls -1t "$BACKUP_DIR"/backup_*.tar.gz | tail -n "$TO_DELETE" | while read -r old_backup; do
            log_info "Eliminando respaldo antiguo: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
        log_success "Rotación completada. Se mantienen $KEEP_COUNT respaldos."
    else
        log_info "Total de respaldos ($TOTAL_BACKUPS) dentro del límite permitido ($KEEP_COUNT)."
    fi
fi
