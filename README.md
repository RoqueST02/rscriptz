# RScriptz

Bot multi-cuenta para Tibia (vBot 4.8 / Mayas OTC).

## Instalacion (para clientes)

1. Abrir Mayas OTC con el perfil que tenga vBot.
2. Ir a `Main` -> boton `Edit` arriba a la derecha del panel del bot.
3. Se abre "Hotkeys editor". Pegar el contenido de [`RQ_Loader.lua`](RQ_Loader.lua) y darle OK.
4. Reiniciar el cliente.
5. Al arrancar aparecera el selector **FREE / VIP**. Elegir.
   - **FREE**: Healing + Follow basico.
   - **VIP**: Todo (Spells, Runes, Target auto, MC Hunt multi-cuenta, Anti-PK, Hub).
6. Si eliges VIP, pedira una license key. Contactar al vendedor.

## Actualizaciones

Se descargan automaticamente al arrancar el cliente. El comprador no
necesita re-instalar nada -- solo reiniciar Mayas.

## Estructura del repo

- `rscriptz.lua` -- todo el bot en un solo archivo (Lua + OTUI inyectado).
- `RQ_Loader.lua` -- las 4 lineas que el cliente pega en el Hotkeys editor.
- `RQ_Hub.py` -- consola opcional que corre en Python para coordinar
  multiples MCs (solo VIP -- se descarga aparte).

## Para el vendedor (admin)

- **License validation**: por default el bot corre en modo "dev" y acepta
  cualquier key que empiece con `RQ-`. Para produccion, editar la variable
  `LICENSE_CSV_URL` en `rscriptz.lua` con la URL de un Google Sheet publicado
  como CSV con columnas: `license_key,character_name_o_asterisco,expires_YYYY-MM-DD`.
- Para publicar el sheet: File -> Share -> Publish to the web -> tipo CSV.
- Actualizar el bot: editar `rscriptz.lua`, commit, push. Los clientes reciben
  la nueva version al siguiente reinicio.
