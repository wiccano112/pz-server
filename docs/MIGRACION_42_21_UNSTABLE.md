# GUÍA DE MIGRACIÓN: PROJECT ZOMBOID 42.21 UNSTABLE

Este documento detalla el procedimiento paso a paso para actualizar el servidor dedicado y la partida actual desde la versión estable (**42.20.4**) a la versión beta (**42.21 Unstable**), incluyendo el resguardo preventivo (backup) y el plan de rollback en caso de incompatibilidades.

---

## 1. CONSIDERACIONES PREVIAS Y REQUISITOS

> [!WARNING]
> **Compatibilidad de Clientes**:
> Todos los jugadores que se conecten al servidor **deben actualizar su juego a la rama `unstable`** en Steam. Si un cliente está en 42.20.4 e intenta entrar al servidor 42.21, Steam/PZ rechazará la conexión por discrepancia de versión.

> [!IMPORTANT]
> **Compatibilidad de Mods**:
> La partida actual (mundo, construcciones, inventarios de jugadores) es compatible hacia adelante. Sin embargo, al ser una versión *unstable*, algunos mods de la Workshop podrían requerir parches si modifican funciones del motor que cambiaron en 42.21.

---

## 2. PROCEDIMIENTO RÁPIDO AUTOMATIZADO (RECOMENDADO)

Hemos preparado scripts deterministas que ejecutan todas las validaciones de seguridad, backup, cambio de rama y arranque:

### Para Actualizar a 42.21:
```bash
./scripts/upgrade_to_42_21.sh
# O desde el panel interactivo: ./scripts/manage.sh (Opción 11)
```
*(Verifica jugadores conectados, permite emitir aviso in-game, guarda el mundo, crea el snapshot `snapshot_pre_42_21_*.tar.gz`, fija `SERVER_BRANCH=unstable` e inicia el contenedor).*

### Para Rollback a 42.20.4 (si algo falla):
```bash
./scripts/rollback_to_42_20.sh
# O desde el panel interactivo: ./scripts/manage.sh (Opción 12)
```
*(Detiene el servidor, detecta el snapshot previo, limpia los archivos de guardado incompatibles de 42.21, restaura el snapshot, revierte a rama estable y levanta el servidor).*

---

## 3. PROCEDIMIENTO MANUAL PASO A PASO

### Paso 1: Verificar jugadores activos y avisar
Antes de detener el servidor, verificar si hay jugadores conectados:
```bash
docker exec pz-server rcon-cli -c /home/steam/server/rcon.yml players
```

Si hay jugadores, enviarles un mensaje in-game avisando del mantenimiento:
```bash
docker exec pz-server rcon-cli -c /home/steam/server/rcon.yml servermsg "Servidor entrando en mantenimiento para actualizar a 42.21 en 2 minutos."
```

### Paso 2: Guardar partida y apagar el contenedor
Forzar el guardado de chunks y base de datos antes de bajar el servicio:
```bash
# 1. Guardar estado del mundo
docker exec pz-server rcon-cli -c /home/steam/server/rcon.yml save

# 2. Detener contenedor de forma segura (flushes dirty chunks)
docker compose down
```

### Paso 3: Crear Backup Completo Preventivo
Crear un archivo comprimido que contenga todo el estado actual del mundo, configuraciones y base de datos:
```bash
mkdir -p data/backups
BACKUP_NAME="pre_unstable_42_21_$(date +%Y%m%d_%H%M%S).tar.gz"

tar -czvf "data/backups/${BACKUP_NAME}" \
    -C data \
    Saves Server db options.ini

echo "Backup creado exitosamente en: data/backups/${BACKUP_NAME}"
```

### Paso 4: Configurar la rama `unstable`

1. **Editar `.env`**:
   Abrir `.env` y agregar la variable de rama al final de la sección de identificación:
   ```env
   # --- Rama del servidor (vacío = stable / unstable = Build 42 Unstable) ---
   SERVER_BRANCH=unstable
   ```

2. **Editar `docker-compose.yml`**:
   Asegurarse de que `SERVER_BRANCH` se pase al contenedor dentro de la sección `environment:` de `pz-server`:
   ```yaml
       environment:
         - SERVER_NAME=${SERVER_NAME}
         - ADMIN_PASSWORD=${ADMIN_PASSWORD}
         - RCON_PASSWORD=${RCON_PASSWORD}
         - SERVER_BRANCH=${SERVER_BRANCH:-}
         - MAX_RAM=${MAX_RAM}
         - MEMORY_XMX_GB=${MEMORY_XMX_GB:-8}
         - MEMORY_XMS_GB=${MEMORY_XMS_GB:-8}
         - PUID=${PUID}
         - PGID=${PGID}
   ```

### Paso 5: Iniciar el servidor y descargar la actualización
Iniciar el contenedor. El script de inicialización (`init.sh`) detectará `SERVER_BRANCH=unstable` y descargará los archivos de 42.21 mediante DepotDownloader:
```bash
docker compose up -d
```

### Paso 6: Monitorear la inicialización
Verificar la descarga y el arranque en los logs:
```bash
# Ver logs en tiempo real
docker compose logs -f

# O verificar directamente en el archivo de consola una vez iniciado:
grep -i "version=" data/server-console.txt
```
Deberías ver una línea similar a:
`version=42.21.X ...` seguida de `SERVER STARTED` y la carga de los mods y el mapa.

---

## 3. INSTRUCCIONES PARA LOS JUGADORES (CLIENTE STEAM)

Cada persona que vaya a jugar en el servidor debe seguir estos pasos en su PC:

1. Abrir **Steam** e ir a la **Biblioteca**.
2. Hacer clic derecho sobre **Project Zomboid** y seleccionar **Propiedades...**
3. En el menú de la izquierda, hacer clic en **Betas**.
4. En el desplegable **Participación en la beta**, seleccionar:
   👉 **`unstable - Unstable Build 42`** (o `unstable`).
5. Cerrar la ventana. Steam descargará automáticamente la actualización de 42.21.
6. Abrir el juego y conectarse normalmente al servidor.

---

## 4. PLAN DE ROLLBACK (EN CASO DE INCOMPATIBILIDAD O ERROR)

Si la versión 42.21 presenta errores graves o incompatibilidad con mods clave y querés volver a 42.20.4 con la partida intacta:

```bash
# 1. Apagar el servidor
docker compose down

# 2. Restaurar la partida y datos desde el backup
# (Reemplazar <ARCHIVO_BACKUP> con el nombre del tar.gz generado en el Paso 3)
rm -rf data/Saves/Multiplayer/*
rm -rf data/db/*
tar -xzvf data/backups/<ARCHIVO_BACKUP>.tar.gz -C data/

# 3. Volver a la rama estable en .env
# Cambiar SERVER_BRANCH=unstable por SERVER_BRANCH= (o comentar la línea)
sed -i 's/^SERVER_BRANCH=unstable/SERVER_BRANCH=/' .env

# 4. Asegurar permisos correctos
chown -R 1000:1000 data/
chmod -R 775 data/

# 5. Iniciar nuevamente en la rama estable (descargará 42.20.4)
docker compose up -d
```
*(Los jugadores también deberán desmarcar la beta en Steam volviendo a "Ninguna" para volver a 42.20.4)*.
