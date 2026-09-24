# TODO: VENTANA DE MANTENIMIENTO - REINICIO AUTOMÁTICO SEGURO

Este documento contiene los pasos deterministas para que **un agente o administrador** active la verificación RCON y programe el reinicio diario inteligente del servidor Project Zomboid (`NobaraZomboid`), previniendo desincronizaciones de red y el bug de duplicación de entidades ("Zombie Mitosis").

---

## ⚠️ REGLA CRÍTICA
> **MUTATION AT REST ONLY**: El archivo `NobaraZomboid.ini` **NUNCA** debe editarse con el contenedor en ejecución. Al apagarse, el proceso Java de Project Zomboid vuelca su memoria RAM a disco, borrando cualquier cambio manual que no se haya hecho con el servidor detenido.

---

## 📋 CHECKLIST PASO A PASO

### [X] Paso 1: Verificar jugadores activos y detener el servidor
1. Comprobar si hay conexiones activas antes de proceder:
   ```bash
   cd /home/perro/pz-server
   # Revisar últimas conexiones en el log de usuarios
   tail -n 15 $(ls -t data/Logs/*_user.txt data/Logs/logs_*/*_user.txt 2>/dev/null | head -n 1) 2>/dev/null || true
   ```
2. Bajar el contenedor de forma limpia (para que vuelque memoria y cierre bases de datos):
   ```bash
   docker compose down
   ```

---

### [X] Paso 2: Configurar RCON en `NobaraZomboid.ini` (Servidor Detenido)
Con el contenedor apagado, asignar la contraseña RCON.

* **Opción A (Automática / No interactiva para Agentes)**:
  ```bash
  sed -i 's/^RCONPassword=.*/RCONPassword=CambiaEstaContrasena123!/' data/Server/NobaraZomboid.ini
  ```
* **Opción B (Manual para Humanos)**:
  Abrir `data/Server/NobaraZomboid.ini`, ir a la línea 167 y escribir:
  ```ini
  RCONPassword=CambiaEstaContrasena123!
  ```
* **Comprobación**:
  ```bash
  grep "^RCONPassword=" data/Server/NobaraZomboid.ini
  # Salida esperada: RCONPassword=CambiaEstaContrasena123!
  ```

---

### [X] Paso 3: Iniciar el servidor
Iniciar el contenedor con Docker Compose:
```bash
docker compose up -d
```

---

### [X] Paso 4: Validar la inicialización y el puerto RCON
1. Monitorear hasta que el servidor termine de bootear:
   ```bash
   docker compose logs --tail=20 -f pz-server | grep -m 1 -E "SERVER STARTED|Server is open for connection"
   ```
   *(Confirmado: *** SERVER STARTED ****).*

2. Probar la conexión RCON directamente dentro del contenedor:
   ```bash
   docker exec pz-server rcon-cli -a 127.0.0.1:27015 -p "CambiaEstaContrasena123!" "players"
   ```
   **Resultado esperado**:
   `Players connected (0):` (o la lista de jugadores conectados). Confirmado con éxito.

---

### [X] Paso 5: Prueba de ejecución del script (`scripts/safe_restart.sh`)
Ejecutar el script para comprobar el flujo completo de validación y log:
```bash
./scripts/safe_restart.sh
```
*Confirmado*: Ciclo ejecutado exitosamente en 11 segundos con servidor sincronizado.

Comprobar el archivo de log generado:
```bash
cat data/Logs/daily_restart.log
```
Finalizado con: `[EXITO] Servidor reiniciado correctamente y mundo sincronizado.` (Auditado con éxito).

---

### [X] Paso 6: Programar la tarea en Cron (05:00 AM diario en ROOT)
Configurar la ejecución automática diaria en el usuario `root` (solicitud explícita):

* **Comprobación**:
  ```bash
  docker run --rm -v /var/spool/cron:/var/spool/cron alpine cat /var/spool/cron/root
  # Salida: 0 5 * * * /home/perro/pz-server/scripts/safe_restart.sh > /dev/null 2>&1
  ```

---

## 📂 ARCHIVOS Y RUTAS CLAVE
* **Script de reinicio**: [`scripts/safe_restart.sh`](file:///home/perro/pz-server/scripts/safe_restart.sh)
* **Librería de utilidades**: [`scripts/common.sh`](file:///home/perro/pz-server/scripts/common.sh)
* **Variables de entorno**: [`.env`](file:///home/perro/pz-server/.env) (`RCON_PASSWORD=CambiaEstaContrasena123!`)
* **Configuración del servidor**: [`data/Server/NobaraZomboid.ini`](file:///home/perro/pz-server/data/Server/NobaraZomboid.ini)
* **Log de auditoría diaria**: `data/Logs/daily_restart.log`
