#!/usr/bin/env bash
# ==============================================================================
# SYNC CONFIG & MODS FROM PRODUCTION TO STAGING
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

WITH_SAVE=false
FORCE=false

show_help() {
    cat << EOF
Uso: $(basename "$0") [OPCIONES]

Sincroniza la configuración de mods, variables sandbox y opciones desde el servidor
de producción (PRD) al servidor de staging (STG).

Opciones:
  -s, --with-save       Copia también el mundo actual y base de datos de PRD para probar
                        la migración de la partida guardada en Build 42.21.
  -f, --force           No pedir confirmaciones interactivas.
  -h, --help            Muestra esta ayuda.

Ejemplos:
  $(basename "$0")                 # Sincroniza mods y reglas (mundo nuevo de prueba)
  $(basename "$0") --with-save     # Sincroniza mods + copia la partida real actual
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--with-save)
            WITH_SAVE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
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

log_header "SINCRONIZACIÓN DE PRODUCCIÓN A STAGING"

if is_container_running; then
    log_warn "El contenedor de staging ($CONTAINER_NAME) está en ejecución."
    if [ "$FORCE" = false ]; then
        read -rp "¿Deseas detener el contenedor de staging para sincronizar de forma segura? (s/N): " CONFIRM_STOP
        if [[ ! "$CONFIRM_STOP" =~ ^[sSyY]$ ]]; then
            log_error "Operación cancelada. Detén el contenedor de staging antes de sincronizar."
            exit 1
        fi
    fi
    log_info "Deteniendo contenedor de staging..."
    cd "$STAGING_ROOT"
    $DOCKER_COMPOSE_CMD down
fi

# Detectar servidor PRD
PRD_SERVER_NAME="NobaraZomboid"
if [ -f "$PRD_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    PRD_SERVER_NAME=$(grep -E "^SERVER_NAME=" "$PRD_ROOT/.env" | cut -d'=' -f2 | tr -d ' "' || echo "NobaraZomboid")
fi

PRD_INI="$PRD_DATA_PATH/Server/${PRD_SERVER_NAME}.ini"
PRD_SANDBOX="$PRD_DATA_PATH/Server/${PRD_SERVER_NAME}_SandboxVars.lua"
PRD_SPAWNREG="$PRD_DATA_PATH/Server/${PRD_SERVER_NAME}_spawnregions.lua"
PRD_SPAWNPTS="$PRD_DATA_PATH/Server/${PRD_SERVER_NAME}_spawnpoints.lua"
PRD_OPTIONS="$PRD_DATA_PATH/options.ini"

if [ ! -f "$PRD_INI" ]; then
    log_error "No se encontró el archivo INI de producción en: $PRD_INI"
    exit 1
fi

log_info "Servidor de producción detectado: $PRD_SERVER_NAME"
log_info "Servidor de destino (Staging): $SERVER_NAME"

# Crear estructura de carpetas en staging
mkdir -p "$DATA_PATH/Server" "$DATA_PATH/backups" "$DATA_PATH/db" "$DATA_PATH/mods"

# 1. Copiar y adaptar archivo INI
log_info "Copiando archivo de configuración INI y mods..."
cp "$PRD_INI" "$DATA_PATH/Server/${SERVER_NAME}.ini"
sed -i "s/^DefaultPort=.*/DefaultPort=${GAME_PORT}/" "$DATA_PATH/Server/${SERVER_NAME}.ini"
sed -i "s/^UDPPort=.*/UDPPort=${DIRECT_PORT}/" "$DATA_PATH/Server/${SERVER_NAME}.ini"
sed -i "s/^RCONPort=.*/RCONPort=${RCON_PORT}/" "$DATA_PATH/Server/${SERVER_NAME}.ini"

# 2. Copiar SandboxVars
if [ -f "$PRD_SANDBOX" ]; then
    log_info "Copiando SandboxVars.lua..."
    cp "$PRD_SANDBOX" "$DATA_PATH/Server/${SERVER_NAME}_SandboxVars.lua"
fi

# 3. Copiar Spawn regions y spawn points
if [ -f "$PRD_SPAWNREG" ]; then
    log_info "Copiando spawnregions.lua..."
    cp "$PRD_SPAWNREG" "$DATA_PATH/Server/${SERVER_NAME}_spawnregions.lua"
fi

if [ -f "$PRD_SPAWNPTS" ]; then
    log_info "Copiando spawnpoints.lua..."
    cp "$PRD_SPAWNPTS" "$DATA_PATH/Server/${SERVER_NAME}_spawnpoints.lua"
fi

# 4. Copiar options.ini
if [ -f "$PRD_OPTIONS" ]; then
    log_info "Copiando options.ini..."
    cp "$PRD_OPTIONS" "$DATA_PATH/options.ini"
fi

# 5. Si se solicitó la partida guardada
if [ "$WITH_SAVE" = true ]; then
    log_info "Copiando partida guardada (Saves) de PRD a Staging..."
    PRD_SAVE_DIR="$PRD_DATA_PATH/Saves/Multiplayer/${PRD_SERVER_NAME}"
    STG_SAVE_DIR="$DATA_PATH/Saves/Multiplayer/${SERVER_NAME}"
    
    if [ -d "$PRD_SAVE_DIR" ]; then
        mkdir -p "$STG_SAVE_DIR"
        rm -rf "${STG_SAVE_DIR:?}"/*
        cp -r "$PRD_SAVE_DIR"/* "$STG_SAVE_DIR/"
        log_success "Partida del mundo clonada en: $STG_SAVE_DIR"
    else
        log_warn "No se encontró directorio de partida en $PRD_SAVE_DIR."
    fi

    # Copiar base de datos SQLite de usuarios/whitelist
    PRD_DB="$PRD_DATA_PATH/db/${PRD_SERVER_NAME}.db"
    STG_DB="$DATA_PATH/db/${SERVER_NAME}.db"
    if [ -f "$PRD_DB" ]; then
        log_info "Copiando base de datos SQLite (${PRD_SERVER_NAME}.db -> ${SERVER_NAME}.db)..."
        cp "$PRD_DB" "$STG_DB"
        log_success "Base de datos clonada en: $STG_DB"
    fi
else
    log_info "Modo partida limpia (Fresh): No se clonó el savegame existente."
    log_info "(Usa --with-save si deseas probar la migración de tu partida real actual)."
fi

# 6. Permisos correctos
log_info "Ajustando permisos a UID:$PUID, GID:$PGID..."
chown -R "$PUID:$PGID" "$DATA_PATH" 2>/dev/null || chmod -R 775 "$DATA_PATH" || true
chmod -R 775 "$DATA_PATH" 2>/dev/null || true

# Resumen de mods sincronizados
MODS_COUNT=$(grep -E "^Mods=" "$DATA_PATH/Server/${SERVER_NAME}.ini" | awk -F';' '{print NF}')
WORKSHOP_COUNT=$(grep -E "^WorkshopItems=" "$DATA_PATH/Server/${SERVER_NAME}.ini" | awk -F';' '{print NF}')

echo ""
log_success "¡Sincronización completada exitosamente!"
echo -e "  Mods configurados:     ${CYAN}${MODS_COUNT}${NC}"
echo -e "  WorkshopItems:         ${CYAN}${WORKSHOP_COUNT}${NC}"
echo -e "  Mundo preparado en:    ${CYAN}${DATA_PATH}${NC}"
echo ""
echo -e "Para iniciar el servidor de staging en la versión 42.21:"
echo -e "  ${BOLD}./scripts/up.sh${NC}  o  ${BOLD}docker compose up -d${NC}"
