-- ============================================================
--  RScriptz Loader v1
--  Descarga la ultima version del bot desde GitHub cada vez que
--  el cliente inicia. Cero re-envio de archivos al cliente cuando
--  se actualiza el bot -- solo commit al repo y listo.
--
--  INSTALACION:
--    Copia este bloque completo (las 4 lineas de abajo) en el
--    Hotkeys editor del bot (vBot -> Edit -> pegar -> OK).
-- ============================================================
HTTP.get('https://raw.githubusercontent.com/RoqueST02/rscriptz/main/rscriptz.lua', function(script, err)
    if err or not script then return warn("[RScriptz Loader] no puedo bajar: "..tostring(err)) end
    local fn, ferr = loadstring(script); if not fn then return warn("[RScriptz Loader] compilacion: "..tostring(ferr)) end
    local ok, rerr = pcall(fn); if not ok then warn("[RScriptz Loader] ejecucion: "..tostring(rerr)) end
end)
