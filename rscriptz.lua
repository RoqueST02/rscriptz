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
    C.ensure("vip.pk.on",          true)
    C.ensure("vip.pk.broadcast",   true)

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
    color: #C83C3C
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
    color: #FFFFFF
    background-color: #326432
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
    color: #FFFFFF
    background-color: #B23A48
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
    color: #FFFFFF
    background-color: #2E5AA0
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
    color: #FFFFFF
    background-color: #6E3AB2
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
    color: #FFFFFF
    background-color: #B2743A
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
    color: #FFFFFF
    background-color: #B2A03A
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
    color: #FFFFFF
    background-color: #3AB2A0
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
    color: #FFFFFF
    background-color: #C83C3C
    focusable: true
]==])
    local pCura = setupUI([==[
Panel
  id: pageCura
  height: 720

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
    height: 20
    width: 60
    !text: tr('ON')

  BotSwitch
    id: hp1mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    width: 60
    !text: tr('POT')

  BotItem
    id: hp1item
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 8

  TextEdit
    id: hp1spell
    anchors.top: hp1on.top
    anchors.bottom: hp1on.bottom
    anchors.left: hp1item.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: hp1txt
    anchors.top: hp1on.bottom
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
    height: 20
    width: 60
    !text: tr('ON')

  BotSwitch
    id: hp2mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    width: 60
    !text: tr('POT')

  BotItem
    id: hp2item
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 8

  TextEdit
    id: hp2spell
    anchors.top: hp2on.top
    anchors.bottom: hp2on.bottom
    anchors.left: hp2item.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: hp2txt
    anchors.top: hp2on.bottom
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
    height: 20
    width: 60
    !text: tr('ON')

  BotSwitch
    id: hp3mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    width: 60
    !text: tr('POT')

  BotItem
    id: hp3item
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 8

  TextEdit
    id: hp3spell
    anchors.top: hp3on.top
    anchors.bottom: hp3on.bottom
    anchors.left: hp3item.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: hp3txt
    anchors.top: hp3on.bottom
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
    height: 20
    width: 60
    !text: tr('ON')

  BotSwitch
    id: mp1mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    width: 60
    !text: tr('POT')

  BotItem
    id: mp1item
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 8

  TextEdit
    id: mp1spell
    anchors.top: mp1on.top
    anchors.bottom: mp1on.bottom
    anchors.left: mp1item.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: mp1txt
    anchors.top: mp1on.bottom
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
    height: 20
    width: 60
    !text: tr('ON')

  BotSwitch
    id: mp2mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    width: 60
    !text: tr('POT')

  BotItem
    id: mp2item
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 8

  TextEdit
    id: mp2spell
    anchors.top: mp2on.top
    anchors.bottom: mp2on.bottom
    anchors.left: mp2item.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: mp2txt
    anchors.top: mp2on.bottom
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
    height: 20
    width: 60
    !text: tr('ON')

  BotSwitch
    id: mp3mode
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    width: 60
    !text: tr('POT')

  BotItem
    id: mp3item
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 8

  TextEdit
    id: mp3spell
    anchors.top: mp3on.top
    anchors.bottom: mp3on.bottom
    anchors.left: mp3item.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4

  Label
    id: mp3txt
    anchors.top: mp3on.bottom
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
  height: 280

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
    !text: tr('Yo soy el LEADER')

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

  BotSwitch
    id: mchFollow
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 22
    !text: tr('MCs siguen mismo piso')

  BotSwitch
    id: mchCross
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 22
    !text: tr('MCs cruzan piso (escaleras)')
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

  Button
    id: reconnect
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: Reconectar al hub
    font: cipsoftFont
    color: #FFFFFF
    background-color: #326432
    height: 22
    margin-top: 8

  Label
    id: status
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: (estado)
    color: #C83C3C
    font: verdana-11px-rounded
    height: 14
    margin-top: 6
]==]);  pcall(function() pHub:hide() end)
    RQ._vipPages = {menu=pMenu, cura=pCura, atk=pAtk, ex=pEx, tgt=pTgt, fol=pFol, mch=pMch, pk=pPk, hub=pHub}

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
                pMenu.netLbl:setColor("#C83C3C")
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
            pcall(function() w.item:setVisible(isPot) end)
            pcall(function() w.spell:setVisible(not isPot) end)
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
                pHub.status:setColor("#C83C3C")
            end
        end)
    end)

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
    macro(300, "RScriptz VIP: Follow", function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.fol.on", false) then return end
        local nom = C.get("vip.fol.leader", ""); if nom == "" then return end
        local ldr = RQ.Game.jugadorPorNombre(nom); if not ldr or not ldr.pos then return end
        local miPos = RQ.Game.pos(); if not miPos or ldr.pos.z ~= miPos.z then return end
        local d = RQ.Game.dist(miPos, ldr.pos)
        local maxD = tonumber(C.get("vip.fol.dist", 2)) or 2
        if d > maxD and RQ.Game.hayCamino(ldr.pos, 20) then RQ.Game.irHacia(ldr.pos, 20) end
    end)
    RQ.Scheduler.every("rq_vip_mchpub", 200, function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.mch.isLeader", false) then return end
        if not RQ.Net.conectado then return end
        local p = RQ.Game.pos(); if not p then return end
        RQ.Net.send("leader_pos", {x=p.x, y=p.y, z=p.z})
    end)
    local lastZ = nil
    RQ.Scheduler.every("rq_vip_mchcross", 200, function()
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if not C.get("vip.mch.isLeader", false) then return end
        if not RQ.Net.conectado then return end
        local p = RQ.Game.pos(); if not p then return end
        if lastZ and lastZ ~= p.z then
            RQ.Net.send("leader_cross", {x=p.x, y=p.y, zOld=lastZ, zNew=p.z})
        end
        lastZ = p.z
    end)
    RQ.Net.on("leader_pos", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.isLeader", false) then return end
        if not C.get("vip.mch.followSame", true) then return end
        if C.get("vip.mch.leader", "") ~= from then return end
        if not data or not data.x then return end
        local mi = RQ.Game.pos(); if not mi or data.z ~= mi.z then return end
        local d = RQ.Game.dist(mi, {x=data.x, y=data.y})
        if d > 3 and RQ.Game.hayCamino({x=data.x, y=data.y, z=data.z}, 30) then
            RQ.Game.irHacia({x=data.x, y=data.y, z=data.z}, 30)
        end
    end)
    RQ.Net.on("leader_cross", function(from, data)
        if RQ.tier ~= "VIP" or not C.get("vip.master", true) then return end
        if C.get("vip.mch.isLeader", false) then return end
        if not C.get("vip.mch.crossFl", true) then return end
        if C.get("vip.mch.leader", "") ~= from then return end
        if not data or not data.x then return end
        local mi = RQ.Game.pos(); if not mi then return end
        if mi.z == data.zOld and RQ.Game.hayCamino({x=data.x, y=data.y, z=data.zOld}, 20) then
            RQ.Game.irHacia({x=data.x, y=data.y, z=data.zOld}, 20)
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

    macro(50, "RScriptz Core", function() RQ.Scheduler.tick() end)
    RQ.Scheduler.every("rq_vip_autoconn", 5000, function()
        if not RQ.Net.conectado then RQ.Net.connect(C.get("net.canal", "rq")) end
    end)
    RQ.Scheduler.every("rq_vip_poll", 100, function() RQ.Net.poll() end)

    pcall(function() broadcastMessage("RScriptz v"..RQ.version.." VIP cargado - "..RQ.Game.name()) end)
    RQ.Logger.info("RScriptz", "listo v"..RQ.version.." modo VIP (menu)")
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
