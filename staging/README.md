# SERVIDOR DE STAGING: PZ-RPM-SERVER-STG (BUILD 42.21 UNSTABLE)

Entorno de pruebas paralelo y completamente aislado para ensayar la actualización a la versión **Build 42.21 Unstable** sin interferir con el servidor de producción (`pz-server`).

---

## 1. CARACTERÍSTICAS DEL ENTORNO

* **Contenedor**: `pz-rpm-server-stg`
* **Rama**: `SERVER_BRANCH=unstable` (descarga automáticamente Build 42.21)
* **Puertos de Red (Host)**:
  * `17261/UDP` -> Juego (Game Loop)
  * `17262/UDP` -> Conexión Directa
  * `27025/TCP` -> Steam Query / RCON
* **Almacenamiento**: `./data` (aislado dentro de la carpeta `staging/`, no toca `../data/`)
* **Límite de RAM**: **6 GB** (`mem_limit: 6g`, Heap inicial 4G / Heap máx 6G)
* **CPUs**: **4 núcleos dedicados** (Hilos `0-3` en P-Cores, 100% aislados de PRD `12-17` y de `pz-panel` `12-19`)

---

## 2. GUÍA RÁPIDA DE USO

Todos los comandos se ejecutan desde la carpeta `staging/`:

```bash
cd /home/perro/pz-server/staging
```

### Paso 1: Sincronizar configuración y mods de Producción
Para traer los 13 mods activos y las reglas de `NobaraZomboid`:

* **Modo A (Recomendado para primera prueba - Mundo Nuevo)**:
  ```bash
  ./scripts/sync_from_prd.sh
  ```
* **Modo B (Prueba de migración de la partida real actual)**:
  ```bash
  ./scripts/sync_from_prd.sh --with-save
  ```

### Paso 2: Iniciar el servidor de Staging
```bash
./scripts/up.sh
# o: docker compose up -d
```
En el primer arranque, DepotDownloader descargará la versión **42.21 Unstable** y los mods de Steam Workshop.

### Paso 3: Monitorear el inicio y versión
```bash
./scripts/logs.sh
# o verificar la versión:
./scripts/status.sh
```

### Paso 4: Detener el servidor
```bash
./scripts/down.sh
# o: docker compose down
```

---

## 3. PANEL INTERACTIVO DE ADMINISTRACIÓN

Para un control visual interactivo de staging:

```bash
./scripts/manage.sh
```

---

## 4. CÓMO CONECTARSE DESDE EL CLIENTE (STEAM)

1. En Steam, clic derecho en **Project Zomboid** -> **Propiedades...** -> **Betas**.
2. Seleccionar: **`unstable - Unstable Build 42`**.
3. Dejar que Steam actualice el juego e iniciar Project Zomboid.
4. En el menú principal, ir a **Unirse / Join** -> pestaña **Favoritos**.
5. Agregar el servidor de staging:
   * **IP**: Tu IP local o `127.0.0.1`
   * **Puerto**: **`17261`** (¡Atención: no usar 16261!)
   * **Contraseña del servidor**: *(la definida en .env si tiene)*
   * **Nombre de cuenta / Contraseña**: Tu usuario de prueba
6. ¡Listo para testear compatibilidad de mods y gameplay!
