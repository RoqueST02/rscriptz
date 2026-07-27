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
local function _rqLoadOTUI(content)
    -- fallback 1: string directo (algunas versiones lo soportan)
    if g_ui and g_ui.importStyleFromString then
        local ok = pcall(g_ui.importStyleFromString, content)
        if ok then return true end
    end
    -- fallback 2: escribir a archivo temporal y usar importStyle
    if g_resources and g_resources.writeFileContents then
        local path = "/rscriptz_runtime.otui"
        local ok, err = pcall(function()
            g_resources.writeFileContents(path, content)
            g_ui.importStyle(path)
        end)
        if ok then return true end
        pcall(function() statusMessage("[RScriptz] OTUI err: "..tostring(err)) end)
    end
    return false
end
local OTUI_STR = [==[
-- ==========================================================
--  RScriptz.otui  --  ventanas profesionales con listas
-- ==========================================================

-- ---------- widgets base ----------
RQTitle < Label
  text-align: center
  font: verdana-11px-rounded
  color: #D4AF37
  background-color: #232323
  height: 20
  margin-top: 6

RQGroupTitle < Label
  text-align: left
  font: verdana-11px-rounded
  color: #D4AF37
  height: 14

RQCheck < CheckBox
  text-wrap: true
  text-auto-resize: true
  margin-top: 4
  font: verdana-11px-rounded

RQFieldLabel < Label
  text-align: left
  font: verdana-11px-rounded
  color: #C8C8C8
  height: 14

RQCenterLabel < Label
  text-align: center
  font: verdana-11px-rounded
  color: #E8E8E8

RQHelp < Label
  text-wrap: true
  text-auto-resize: true
  text-align: center
  font: verdana-11px-rounded
  color: #8A8A8A

RQBigButton < Button
  height: 22
  font: cipsoftFont

-- filas de listas -----------------------------------------
RQSpellEntry < Label
  background-color: alpha
  text-offset: 22 1
  focusable: true
  height: 16
  font: verdana-11px-rounded

  CheckBox
    id: enabled
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 15
    height: 15
    margin-left: 3

  $focus:
    background-color: #00000055

  Button
    id: remove
    !text: tr('x')
    anchors.right: parent.right
    margin-right: 3
    text-offset: 1 0
    width: 15
    height: 15

RQItemEntry < Label
  background-color: alpha
  text-offset: 42 1
  focusable: true
  height: 18
  font: verdana-11px-rounded

  CheckBox
    id: enabled
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 15
    height: 15
    margin-left: 3

  UIItem
    id: preview
    anchors.left: prev.right
    margin-left: 3
    anchors.verticalCenter: parent.verticalCenter
    size: 16 16
    focusable: false

  $focus:
    background-color: #00000055

  Button
    id: remove
    !text: tr('x')
    anchors.right: parent.right
    margin-right: 3
    text-offset: 1 0
    width: 15
    height: 15

RQNameEntry < Label
  background-color: alpha
  text-offset: 6 1
  focusable: true
  height: 16
  font: verdana-11px-rounded

  $focus:
    background-color: #00000055

  Button
    id: remove
    !text: tr('x')
    anchors.right: parent.right
    margin-right: 3
    text-offset: 1 0
    width: 15
    height: 15

-- ==========================================================
--  HEALING WINDOW  (IDs unicos por cada seccion)
-- ==========================================================
RScriptzHealingWindow < MainWindow
  !text: tr('RScriptz - Healing (curaciones)')
  size: 520 640
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Anade tantas reglas como quieras. Se recorren en orden -- pon primero las mas importantes.

  RQFieldLabel
    id: lblVoc
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 8
    text: Vocacion:

  ComboBox
    id: voc
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 10

  -- ============ SPELL HEAL ============
  RQGroupTitle
    id: t1
    anchors.top: voc.bottom
    anchors.left: parent.left
    margin-top: 10
    text: SPELLS DE CURACION

  TextList
    id: spellList
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 90
    padding: 1
    padding-top: 2
    vertical-scrollbar: spellListSb

  VerticalScrollBar
    id: spellListSb
    anchors.top: spellList.top
    anchors.bottom: spellList.bottom
    anchors.right: spellList.right
    step: 14
    pixels-scroll: true

  ComboBox
    id: spellName
    anchors.top: spellList.bottom
    anchors.left: parent.left
    margin-top: 6
    width: 150

  RQFieldLabel
    id: spellHpLbl
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: spellName.right
    margin-left: 8
    text: HP<=

  TextEdit
    id: spellHpBelow
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: spellHpLbl.right
    margin-left: 4
    width: 40

  RQFieldLabel
    id: spellMpLbl
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: spellHpBelow.right
    margin-left: 8
    text: MP>=

  TextEdit
    id: spellMinMp
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: spellMpLbl.right
    margin-left: 4
    width: 40

  Button
    id: spellAdd
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: spellMinMp.right
    margin-left: 6
    text: Anadir
    size: 60 20
    font: cipsoftFont

  Button
    id: spellUp
    anchors.top: spellName.bottom
    anchors.right: parent.horizontalCenter
    margin-top: 6
    margin-right: 4
    text: Subir
    size: 60 20
    font: cipsoftFont

  Button
    id: spellDown
    anchors.top: spellName.bottom
    anchors.left: parent.horizontalCenter
    margin-top: 6
    margin-left: 4
    text: Bajar
    size: 60 20
    font: cipsoftFont

  -- ============ POCIONES HP ============
  RQGroupTitle
    id: t2
    anchors.top: spellUp.bottom
    anchors.left: parent.left
    margin-top: 12
    text: POCIONES DE VIDA

  TextList
    id: hpList
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 90
    padding: 1
    padding-top: 2
    vertical-scrollbar: hpListSb

  VerticalScrollBar
    id: hpListSb
    anchors.top: hpList.top
    anchors.bottom: hpList.bottom
    anchors.right: hpList.right
    step: 14
    pixels-scroll: true

  ComboBox
    id: hpPotName
    anchors.top: hpList.bottom
    anchors.left: parent.left
    margin-top: 6
    width: 170

  RQFieldLabel
    id: hpBelowLbl
    anchors.verticalCenter: hpPotName.verticalCenter
    anchors.left: hpPotName.right
    margin-left: 8
    text: HP<=

  TextEdit
    id: hpBelow
    anchors.verticalCenter: hpPotName.verticalCenter
    anchors.left: hpBelowLbl.right
    margin-left: 4
    width: 40

  Button
    id: hpAdd
    anchors.verticalCenter: hpPotName.verticalCenter
    anchors.left: hpBelow.right
    margin-left: 6
    text: Anadir
    size: 60 20
    font: cipsoftFont

  Button
    id: hpUp
    anchors.top: hpPotName.bottom
    anchors.right: parent.horizontalCenter
    margin-top: 6
    margin-right: 4
    text: Subir
    size: 60 20
    font: cipsoftFont

  Button
    id: hpDown
    anchors.top: hpPotName.bottom
    anchors.left: parent.horizontalCenter
    margin-top: 6
    margin-left: 4
    text: Bajar
    size: 60 20
    font: cipsoftFont

  -- ============ POCIONES MP ============
  RQGroupTitle
    id: t3
    anchors.top: hpUp.bottom
    anchors.left: parent.left
    margin-top: 12
    text: POCIONES DE MANA

  TextList
    id: mpList
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 90
    padding: 1
    padding-top: 2
    vertical-scrollbar: mpListSb

  VerticalScrollBar
    id: mpListSb
    anchors.top: mpList.top
    anchors.bottom: mpList.bottom
    anchors.right: mpList.right
    step: 14
    pixels-scroll: true

  ComboBox
    id: mpPotName
    anchors.top: mpList.bottom
    anchors.left: parent.left
    margin-top: 6
    width: 170

  RQFieldLabel
    id: mpBelowLbl
    anchors.verticalCenter: mpPotName.verticalCenter
    anchors.left: mpPotName.right
    margin-left: 8
    text: MP<=

  TextEdit
    id: mpBelow
    anchors.verticalCenter: mpPotName.verticalCenter
    anchors.left: mpBelowLbl.right
    margin-left: 4
    width: 40

  Button
    id: mpAdd
    anchors.verticalCenter: mpPotName.verticalCenter
    anchors.left: mpBelow.right
    margin-left: 6
    text: Anadir
    size: 60 20
    font: cipsoftFont

  Button
    id: mpUp
    anchors.top: mpPotName.bottom
    anchors.right: parent.horizontalCenter
    margin-top: 6
    margin-right: 4
    text: Subir
    size: 60 20
    font: cipsoftFont

  Button
    id: mpDown
    anchors.top: mpPotName.bottom
    anchors.left: parent.horizontalCenter
    margin-top: 6
    margin-left: 4
    text: Bajar
    size: 60 20
    font: cipsoftFont

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  SPELLS ATAQUE WINDOW
-- ==========================================================
RScriptzSpellsWindow < MainWindow
  !text: tr('RScriptz - Spells de ataque')
  size: 520 420
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Anade tantos spells de ataque como quieras. Se lanza el primero que cumple sus condiciones.

  RQFieldLabel
    id: lblVoc
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 8
    text: Vocacion:

  ComboBox
    id: voc
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 10

  RQGroupTitle
    id: t1
    anchors.top: voc.bottom
    anchors.left: parent.left
    margin-top: 10
    text: LISTA DE SPELLS DE ATAQUE

  TextList
    id: list
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 150
    padding: 1
    padding-top: 2
    vertical-scrollbar: listSb

  VerticalScrollBar
    id: listSb
    anchors.top: list.top
    anchors.bottom: list.bottom
    anchors.right: list.right
    step: 14
    pixels-scroll: true

  ComboBox
    id: spellName
    anchors.top: list.bottom
    anchors.left: parent.left
    margin-top: 6
    width: 150

  RQFieldLabel
    id: lblCd
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: spellName.right
    margin-left: 8
    text: cada ms

  TextEdit
    id: cd
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: lblCd.right
    margin-left: 4
    width: 55

  RQFieldLabel
    id: lblMana
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: cd.right
    margin-left: 8
    text: MP>=

  TextEdit
    id: minMana
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: lblMana.right
    margin-left: 4
    width: 40

  Button
    id: add
    anchors.verticalCenter: spellName.verticalCenter
    anchors.left: minMana.right
    margin-left: 6
    text: Anadir
    size: 60 20
    font: cipsoftFont

  Button
    id: moveUp
    anchors.top: spellName.bottom
    anchors.right: parent.horizontalCenter
    margin-top: 10
    margin-right: 4
    text: Subir
    size: 60 20
    font: cipsoftFont

  Button
    id: moveDown
    anchors.top: spellName.bottom
    anchors.left: parent.horizontalCenter
    margin-top: 10
    margin-left: 4
    text: Bajar
    size: 60 20
    font: cipsoftFont

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  RUNES WINDOW
-- ==========================================================
RScriptzRunesWindow < MainWindow
  !text: tr('RScriptz - Runes')
  size: 540 430
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Elige runes de la lista. El item ID se pone solo. Anade varias reglas.

  RQGroupTitle
    id: t1
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: LISTA DE RUNES

  TextList
    id: list
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 150
    padding: 1
    padding-top: 2
    vertical-scrollbar: listSb

  VerticalScrollBar
    id: listSb
    anchors.top: list.top
    anchors.bottom: list.bottom
    anchors.right: list.right
    step: 14
    pixels-scroll: true

  ComboBox
    id: runeName
    anchors.top: list.bottom
    anchors.left: parent.left
    margin-top: 8
    width: 170

  BotItem
    id: preview
    anchors.verticalCenter: runeName.verticalCenter
    anchors.left: runeName.right
    margin-left: 6

  RQFieldLabel
    id: lblCd
    anchors.verticalCenter: runeName.verticalCenter
    anchors.left: preview.right
    margin-left: 8
    text: cada ms

  TextEdit
    id: cd
    anchors.verticalCenter: runeName.verticalCenter
    anchors.left: lblCd.right
    margin-left: 4
    width: 55

  RQFieldLabel
    id: lblHp
    anchors.verticalCenter: runeName.verticalCenter
    anchors.left: cd.right
    margin-left: 8
    text: HPtgt>=

  TextEdit
    id: minHp
    anchors.verticalCenter: runeName.verticalCenter
    anchors.left: lblHp.right
    margin-left: 4
    width: 40

  Button
    id: add
    anchors.verticalCenter: runeName.verticalCenter
    anchors.left: minHp.right
    margin-left: 6
    text: Anadir
    size: 60 20
    font: cipsoftFont

  RQCheck
    id: onlyMonsters
    anchors.top: runeName.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Solo contra monstruos (aplica a toda la lista)

  Button
    id: moveUp
    anchors.top: onlyMonsters.bottom
    anchors.right: parent.horizontalCenter
    margin-top: 6
    margin-right: 4
    text: Subir
    size: 60 20
    font: cipsoftFont

  Button
    id: moveDown
    anchors.top: onlyMonsters.bottom
    anchors.left: parent.horizontalCenter
    margin-top: 6
    margin-left: 4
    text: Bajar
    size: 60 20
    font: cipsoftFont

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  TARGET WINDOW
-- ==========================================================
RScriptzTargetWindow < MainWindow
  !text: tr('RScriptz - Auto Target')
  size: 380 240
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Ataca al monstruo mas cercano dentro del rango si no tienes target.

  RQCenterLabel
    id: rangeText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 12
    text: Rango maximo: 5 tiles

  HorizontalScrollBar
    id: range
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    minimum: 1
    maximum: 10
    step: 1
    height: 16

  RQCheck
    id: keepTarget
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: No cambiar de target hasta que muera

  RQCheck
    id: preferLeader
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Preferir el target del leader (MC Hunt)

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  FOLLOW WINDOW
-- ==========================================================
RScriptzFollowWindow < MainWindow
  !text: tr('RScriptz - Follow')
  size: 380 220
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Sigue a un jugador con findPath (verifica ruta antes de mover).

  RQFieldLabel
    id: lblLeader
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 12
    text: Nombre del leader (exacto):

  TextEdit
    id: leader
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3

  RQCenterLabel
    id: distText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 10
    text: Distancia maxima al leader: 2 tiles

  HorizontalScrollBar
    id: maxDist
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    minimum: 1
    maximum: 8
    step: 1
    height: 16

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  MC HUNT WINDOW
-- ==========================================================
RScriptzMCHuntWindow < MainWindow
  !text: tr('RScriptz - MC Hunt')
  size: 400 340
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: MC Hunt sincroniza posicion y cruces de piso entre leader y MCs por el hub.

  RQCheck
    id: isLeader
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: YO SOY EL LEADER (activar en un solo personaje)

  RQFieldLabel
    id: lblLeader
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Nombre del leader (los MCs escriben aqui):

  TextEdit
    id: leaderName
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3

  RQCenterLabel
    id: pubText
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 10
    text: Frecuencia de publicacion: 500 ms

  HorizontalScrollBar
    id: pubMs
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    minimum: 200
    maximum: 2000
    step: 50
    height: 16

  RQCheck
    id: followOnSameFloor
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 8
    text: MCs siguen al leader tambien en el mismo piso

  RQCheck
    id: crossFloors
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: MCs cruzan piso automatico (escaleras/alcantarilla)

  RQCheck
    id: shareTarget
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: MCs atacan el mismo target que el leader

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  ANTI-PK WINDOW
-- ==========================================================
RScriptzAntiPKWindow < MainWindow
  !text: tr('RScriptz - Anti-PK')
  size: 400 400
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Alerta cuando aparece un player desconocido. Puede avisar a los otros MCs.

  RQCheck
    id: broadcast
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Avisar tambien a los otros MCs por el hub

  RQCheck
    id: playSound
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Sonido de alerta

  RQGroupTitle
    id: t1
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: LISTA DE AMIGOS (no dispara alerta)

  TextList
    id: list
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 130
    padding: 1
    padding-top: 2
    vertical-scrollbar: listSb

  VerticalScrollBar
    id: listSb
    anchors.top: list.top
    anchors.bottom: list.bottom
    anchors.right: list.right
    step: 14
    pixels-scroll: true

  TextEdit
    id: nameInput
    anchors.top: list.bottom
    anchors.left: parent.left
    margin-top: 6
    width: 240

  Button
    id: add
    anchors.verticalCenter: nameInput.verticalCenter
    anchors.left: nameInput.right
    margin-left: 6
    text: Anadir amigo
    size: 90 20
    font: cipsoftFont

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

-- ==========================================================
--  HUB WINDOW
-- ==========================================================
RScriptzHubWindow < MainWindow
  !text: tr('RScriptz - Conexion HUB')
  size: 380 300
  @onEscape: self:hide()

  RQHelp
    id: help
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: El hub (RQ_Hub.py) conecta todos los MCs. Deben usar el mismo canal.

  RQFieldLabel
    id: lblChannel
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 12
    text: Canal (todos los MCs igual):

  TextEdit
    id: channel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3

  RQFieldLabel
    id: lblUrl
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 8
    text: URL del hub:

  TextEdit
    id: url
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3

  RQBigButton
    id: reconnect
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 10
    text: Reconectar al hub

  RQCenterLabel
    id: status
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    text: (estado)

  HorizontalSeparator
    id: sep
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    !text: tr('Cerrar')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-right: 5

]==]
local _rqOtuiOk = _rqLoadOTUI(OTUI_STR)
if not _rqOtuiOk then
    pcall(function() statusMessage("[RScriptz] OTUI no cargo -- ventanas no funcionaran") end)
end

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
                rqSetupFullBot()
                pcall(function() whiteInfoMessage("[RScriptz] Modo VIP activado (key "..key..")") end)
            else
                pcall(function() displayErrorBox("RScriptz VIP", "Key rechazada: "..(reason or "?")) end)
            end
        end)
    end)
end

local function showTierSelector()
    -- Usa displayGeneralBox nativo de OTClient -- garantizado que funciona,
    -- no depende de anchors ni constantes de la version del cliente.
    displayGeneralBox(
        "RScriptz v"..RQ.version,
        "Bienvenido a RScriptz.\n\nElegi que version queres correr:\n\n"..
        "FREE  -- Healing (spells + pociones) + Follow basico\n"..
        "VIP   -- Todo (Spells, Runes, Target, MC Hunt, Anti-PK, Hub)",
        {
            {text = "VIP", callback = function()
                _askForKey()
            end},
            {text = "FREE", callback = function()
                storage.rscriptz_tier = "FREE"
                RQ.tier = "FREE"
                rqSetupFreeBot()
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
    vocations = {"Knight", "Paladin", "Druid", "Sorcerer"},
    healSpells = {
        Knight   = {"exura ico", "exura gran ico", "exura san"},
        Paladin  = {"exura", "exura gran", "exura san"},
        Druid    = {"exura", "exura gran", "exura vita", "exura gran mas res"},
        Sorcerer = {"exura", "exura gran", "exura vita"},
    },
    attackSpells = {
        Knight   = {"exori", "exori gran", "exori hur", "exori ico", "exori min", "exori mas"},
        Paladin  = {"exori san", "exori mort", "exori con", "exori gran con", "exevo con hur", "divine missile"},
        Druid    = {"exori frigo", "exori tera", "exori gran frigo", "exori gran tera", "exori mas"},
        Sorcerer = {"exori vis", "exori flam", "exori mort", "exori gran vis", "exori gran flam", "exori mas"},
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
    local base = ((vocId or 0) - 1) % 4 + 1
    if base == 1 then return "Sorcerer" end
    if base == 2 then return "Druid" end
    if base == 3 then return "Paladin" end
    if base == 4 then return "Knight" end
    return "Knight"
end

-- ==========================================================
--  SETUP FREE  (Healing + Follow solamente, resto bloqueado)
-- ==========================================================
rqSetupFreeBot = function()
    setDefaultTab("RQ")
    local ui = setupUI([[
Panel
  height: 152

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
    text: Version limitada: Healing + Follow
    font: verdana-11px-rounded
    color: #8A8A8A
    background-color: #1A1A1A
    height: 16

  BotSwitch
    id: swHeal
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 6
    height: 20
    !text: tr('HEALING (spells + pociones)')

  BotSwitch
    id: swFollow
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 20
    !text: tr('FOLLOW basico')

  Label
    id: locked
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: (Spells, Runes, Target, MC Hunt, Anti-PK: solo VIP)
    font: verdana-11px-rounded
    color: #C83C3C
    height: 16
    margin-top: 6

  Button
    id: upgradeBtn
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: [ UPGRADE A VIP ]
    color: #FFFFFF
    background-color: #B28B00
    font: cipsoftFont
    height: 24
    margin-top: 4
]])

    -- defaults minimos
    local C = RQ.Config
    C.ensure("heal.spells", {{enabled=true, spell="exura", hpBelow=90, minMp=5}})
    C.ensure("heal.hpPots", {{enabled=true, itemId=266, hpBelow=60}})
    C.ensure("heal.mpPots", {{enabled=true, itemId=268, mpBelow=30}})
    C.ensure("heal.on", true)
    C.ensure("follow.on", false)
    C.ensure("follow.leader", "")
    C.ensure("follow.maxDist", 2)

    ui.swHeal:setOn(C.get("heal.on", true))
    ui.swHeal.onClick = function(w)
        local n = not C.get("heal.on", true); C.set("heal.on", n); w:setOn(n)
    end
    ui.swFollow:setOn(C.get("follow.on", false))
    ui.swFollow.onClick = function(w)
        local n = not C.get("follow.on", false); C.set("follow.on", n); w:setOn(n)
    end

    ui.upgradeBtn.onClick = function()
        storage.rscriptz_tier = nil
        pcall(function() displayInfoBox("RScriptz",
            "Reinicia el cliente para ingresar tu key VIP.\n"..
            "Contacta al vendedor si aun no tenes key.") end)
    end

    -- macros FREE
    macro(200, "RScriptz FREE: Healing spells", function()
        if not C.get("heal.on", true) then return end
        local hp = RQ.Game.hp(); local mp = RQ.Game.mana()
        for _, r in ipairs(C.list("heal.spells")) do
            if r.enabled and hp <= (r.hpBelow or 0) and mp >= (r.minMp or 0) then
                cast(r.spell, 900); return
            end
        end
    end)
    macro(200, "RScriptz FREE: Healing HP pots", function()
        if not C.get("heal.on", true) then return end
        local hp = RQ.Game.hp()
        for _, r in ipairs(C.list("heal.hpPots")) do
            if r.enabled and hp <= (r.hpBelow or 0) then
                useOnYourself(tonumber(r.itemId) or 266); return
            end
        end
    end)
    macro(200, "RScriptz FREE: Healing MP pots", function()
        if not C.get("heal.on", true) then return end
        local mp = RQ.Game.mana()
        for _, r in ipairs(C.list("heal.mpPots")) do
            if r.enabled and mp <= (r.mpBelow or 0) then
                useOnYourself(tonumber(r.itemId) or 268); return
            end
        end
    end)
    macro(300, "RScriptz FREE: Follow", function()
        if not C.get("follow.on", false) then return end
        local nom = C.get("follow.leader", ""); if nom == "" then return end
        local ldr = RQ.Game.jugadorPorNombre(nom); if not ldr or not ldr.pos then return end
        local miPos = RQ.Game.pos(); if not miPos then return end
        if ldr.pos.z ~= miPos.z then return end
        local d = RQ.Game.dist(miPos, ldr.pos)
        if d > C.get("follow.maxDist", 2) then
            if RQ.Game.hayCamino(ldr.pos, 20) then RQ.Game.irHacia(ldr.pos, 20) end
        end
    end)
    macro(50, "RScriptz Core", function() RQ.Scheduler.tick() end)

    RQ.Logger.info("RScriptz", "listo v"..RQ.version.." modo FREE")
end

-- ==========================================================
--  SETUP FULL  (VIP: todo el bot)
-- ==========================================================
rqSetupFullBot = function()
    -- ==========================================================
    --  DEFAULTS
    -- ==========================================================
    local C = RQ.Config
    C.ensure("net.canal", "rq")
    C.ensure("net.url", "http://127.0.0.1:9876")
    C.ensure("master.on", true)

    -- healing: LISTAS de reglas
    C.ensure("heal.voc", vocIdToName(RQ.Game.voc()))
    C.ensure("heal.spells", {
        {enabled=true, spell="exura",     hpBelow=90, minMp=5},
        {enabled=true, spell="exura gran", hpBelow=70, minMp=15},
    })
    C.ensure("heal.hpPots", {
        {enabled=true, itemId=266, hpBelow=60},
        {enabled=true, itemId=239, hpBelow=30},
    })
    C.ensure("heal.mpPots", {
        {enabled=true, itemId=268, mpBelow=30},
    })
    -- master del healing = si hay al menos una regla enabled
    C.ensure("heal.on", true)

    -- spells ataque: LISTA de reglas
    C.ensure("spells.on", false)
    C.ensure("spells.voc", vocIdToName(RQ.Game.voc()))
    C.ensure("spells.rules", {
        {enabled=true, spell="exori", cd=2000, minMana=60},
    })

    -- runes: LISTA de reglas
    C.ensure("runes.on", false)
    C.ensure("runes.onlyMons", true)
    C.ensure("runes.rules", {
        {enabled=true, name="Sudden Death (SD)", itemId=3155, cd=1000, minHp=30},
    })

    -- target
    C.ensure("target.on", false)
    C.ensure("target.range", 5)
    C.ensure("target.keep", true)
    C.ensure("target.followLdr", false)

    -- follow
    C.ensure("follow.on", false)
    C.ensure("follow.leader", "")
    C.ensure("follow.maxDist", 2)

    -- mchunt
    C.ensure("mchunt.isLeader", false)
    C.ensure("mchunt.leader", "")
    C.ensure("mchunt.pubMs", 500)
    C.ensure("mchunt.followSame", true)
    C.ensure("mchunt.crossFl", true)
    C.ensure("mchunt.shareTgt", false)

    -- antipk
    C.ensure("antipk.on", true)
    C.ensure("antipk.broadcast", true)
    C.ensure("antipk.sound", true)
    C.ensure("antipk.friends", {})   -- lista de nombres {"Pepe", "Juan"}

    RQ.Net.setUrl(C.get("net.url", "http://127.0.0.1:9876"))

    -- ==========================================================
    --  PANEL PRINCIPAL EN LA PESTANA "RQ"
    -- ==========================================================
    setDefaultTab("RQ")

    local panelName = "rscriptz_main"
    local ui = setupUI([[
    Panel
      height: 288

      Label
        id: brand
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        text-align: center
        text: RScriptz v0.5
        font: verdana-11px-rounded
        color: #D4AF37
        background-color: #232323
        height: 20

      Label
        id: netLbl
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        text-align: center
        text: Net: iniciando...
        font: verdana-11px-rounded
        color: #C83C3C
        background-color: #1A1A1A
        height: 18

      BotSwitch
        id: master
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        !text: tr('MASTER ON/OFF (todo el bot)')

      Panel
        id: rowHub
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 6
        height: 20
        Button
          id: btn
          anchors.fill: parent
          text: HUB (conexion)
          color: #FFFFFF
          background-color: #326432
          font: cipsoftFont

      Panel
        id: rowHeal
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('HEALING')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #B23A48
          font: cipsoftFont

      Panel
        id: rowSpells
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('SPELLS')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #2E5AA0
          font: cipsoftFont

      Panel
        id: rowRunes
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('RUNES')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #6E3AB2
          font: cipsoftFont

      Panel
        id: rowTarget
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('TARGET')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #B2743A
          font: cipsoftFont

      Panel
        id: rowFollow
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('FOLLOW')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #B2A03A
          font: cipsoftFont

      Panel
        id: rowMcHunt
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('MC HUNT')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #3AB2A0
          font: cipsoftFont

      Panel
        id: rowAntiPk
        anchors.top: prev.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        margin-top: 4
        height: 20
        BotSwitch
          id: sw
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: 96
          !text: tr('ANTI-PK')
        Button
          id: btn
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: prev.right
          anchors.right: parent.right
          margin-left: 4
          text: Configurar
          color: #FFFFFF
          background-color: #C83C3C
          font: cipsoftFont
    ]])
    ui:setId(panelName)

    -- estado visual del panel
    ui.master:setOn(C.get("master.on", true))
    ui.master.onClick = function(w)
        local nuevo = not C.get("master.on", true); C.set("master.on", nuevo); w:setOn(nuevo)
    end

    local function bindRowSwitch(row, key)
        row.sw:setOn(C.get(key, false))
        row.sw.onClick = function(w)
            local nuevo = not C.get(key, false); C.set(key, nuevo); w:setOn(nuevo)
        end
    end
    bindRowSwitch(ui.rowHeal,   "heal.on")
    bindRowSwitch(ui.rowSpells, "spells.on")
    bindRowSwitch(ui.rowRunes,  "runes.on")
    bindRowSwitch(ui.rowTarget, "target.on")
    bindRowSwitch(ui.rowFollow, "follow.on")
    bindRowSwitch(ui.rowAntiPk, "antipk.on")
    ui.rowMcHunt.sw:setOn(C.get("mchunt.isLeader", false))
    ui.rowMcHunt.sw.onClick = function(w)
        local nuevo = not C.get("mchunt.isLeader", false)
        C.set("mchunt.isLeader", nuevo); w:setOn(nuevo)
        RQ.Logger.info("MCHunt", nuevo and "AHORA soy LEADER" or "YA NO soy leader")
    end

    RQ.Scheduler.every("rq_net_label", 1000, function()
        if not ui.netLbl then return end
        if RQ.Net.conectado then
            pcall(function()
                ui.netLbl:setText("Net OK | "..RQ.Net.canal.." | tx="..RQ.Net.tx.." rx="..RQ.Net.rx)
                ui.netLbl:setColor("#32DC64")
            end)
        else
            pcall(function()
                ui.netLbl:setText("Net OFF | ¿RQ_Hub.py corriendo?")
                ui.netLbl:setColor("#C83C3C")
            end)
        end
    end)

    -- ==========================================================
    --  HELPERS COMUNES DE LISTAS
    -- ==========================================================
    local function fillCombo(combo, opts, currentValue)
        combo:clearOptions()
        for _, o in ipairs(opts) do combo:addOption(o) end
        if currentValue then pcall(function() combo:setCurrentOption(currentValue) end) end
    end
    local function fillComboItems(combo, lista, currentName)
        combo:clearOptions()
        for _, e in ipairs(lista) do combo:addOption(e.name) end
        if currentName then pcall(function() combo:setCurrentOption(currentName) end) end
    end

    -- helper para listas: agrega una entry visual en un TextList
    -- entry es una tabla con {enabled, ...} de config
    -- fmt(entry) devuelve el texto que se muestra
    -- onRemove(entry) borra la entry de la lista de config
    local function addListRow(textList, entry, fmt, onRemove, entryClass)
        local row = g_ui.createWidget(entryClass or "RQSpellEntry", textList)
        row.enabled:setChecked(entry.enabled ~= false)
        row.enabled.onClick = function(w)
            entry.enabled = not entry.enabled
            row.enabled:setChecked(entry.enabled)
        end
        row.remove.onClick = function()
            onRemove(entry); row:destroy()
        end
        row:setText(fmt(entry))
        return row
    end

    local rootWidget = g_ui.getRootWidget()

    -- helper: aisla cada ventana. Si UNA falla al cablearse, las demas siguen
    -- funcionando y el error se loguea, no se rompe el script entero.
    local function protect(name, fn)
        local ok, err = pcall(fn)
        if not ok then
            RQ.Logger.error("UI", name..": "..tostring(err))
        end
    end

    -- ==========================================================
    --  HUB WINDOW
    -- ==========================================================
    local hubWin
    if rootWidget then protect("HubWindow", function()
        hubWin = UI.createWindow('RScriptzHubWindow', rootWidget); hubWin:hide()
        hubWin.closeButton.onClick = function() hubWin:hide() end
        hubWin.channel:setText(C.get("net.canal", "rq"))
        hubWin.url:setText(C.get("net.url", "http://127.0.0.1:9876"))
        hubWin.channel.onTextChange = function(_, t) if t and t~="" then C.set("net.canal", t) end end
        hubWin.url.onTextChange     = function(_, t) if t and t~="" then C.set("net.url", t); RQ.Net.setUrl(t) end end
        hubWin.reconnect.onClick = function()
            RQ.Net.setUrl(C.get("net.url", "http://127.0.0.1:9876"))
            RQ.Net.connect(C.get("net.canal", "rq"))
        end
        RQ.Scheduler.every("rq_hub_status", 800, function()
            if not hubWin or not hubWin:isVisible() then return end
            pcall(function()
                if RQ.Net.conectado then
                    hubWin.status:setText("Net OK | canal "..RQ.Net.canal.." | tx="..RQ.Net.tx.." rx="..RQ.Net.rx)
                    hubWin.status:setColor("#32DC64")
                else
                    hubWin.status:setText("Net OFF -- ¿RQ_Hub.py corriendo?")
                    hubWin.status:setColor("#C83C3C")
                end
            end)
        end)
    end) end
    ui.rowHub.btn.onClick = function() if hubWin then hubWin:show(); hubWin:raise(); hubWin:focus() end end

    -- ==========================================================
    --  HEALING WINDOW
    -- ==========================================================
    local healWin
    if rootWidget then protect("HealingWindow", function()
        healWin = UI.createWindow('RScriptzHealingWindow', rootWidget); healWin:hide()
        healWin.closeButton.onClick = function() healWin:hide() end

        -- vocacion + spell combo dinamico
        fillCombo(healWin.voc, RQ.Catalog.vocations, C.get("heal.voc"))
        local function refreshHealSpellCombo(voc)
            fillCombo(healWin.spellName, RQ.Catalog.healSpells[voc] or {})
        end
        refreshHealSpellCombo(C.get("heal.voc"))
        healWin.voc.onOptionChange = function(w)
            local o = w:getCurrentOption(); local t = o and o.text or nil
            if t then C.set("heal.voc", t); refreshHealSpellCombo(t) end
        end

        -- ---------- SECCION SPELLS ----------
        local fmtSpell = function(e) return string.format("HP<=%d MP>=%d : %s", e.hpBelow or 0, e.minMp or 0, e.spell or "?") end
        local function refreshSpells()
            healWin.spellList:destroyChildren()
            local lst = C.list("heal.spells")
            for _, entry in ipairs(lst) do
                addListRow(healWin.spellList, entry, fmtSpell,
                    function(e)
                        for i, x in ipairs(lst) do if x == e then table.remove(lst, i); return end end
                    end)
            end
        end
        refreshSpells()
        healWin.spellHpBelow:setText("70")
        healWin.spellMinMp:setText("15")
        healWin.spellAdd.onClick = function()
            local sName = healWin.spellName:getCurrentOption()
            sName = sName and sName.text or nil
            local hp = tonumber(healWin.spellHpBelow:getText())
            local mp = tonumber(healWin.spellMinMp:getText())
            if not sName or not hp or not mp then RQ.Logger.warn("Heal", "faltan campos"); return end
            table.insert(C.list("heal.spells"), {enabled=true, spell=sName, hpBelow=hp, minMp=mp})
            refreshSpells()
        end
        healWin.spellUp.onClick = function()
            local sel = healWin.spellList:getFocusedChild(); if not sel then return end
            local i = healWin.spellList:getChildIndex(sel); if i < 2 then return end
            local lst = C.list("heal.spells"); lst[i], lst[i-1] = lst[i-1], lst[i]
            healWin.spellList:moveChildToIndex(sel, i-1)
        end
        healWin.spellDown.onClick = function()
            local sel = healWin.spellList:getFocusedChild(); if not sel then return end
            local i = healWin.spellList:getChildIndex(sel)
            if i >= healWin.spellList:getChildCount() then return end
            local lst = C.list("heal.spells"); lst[i], lst[i+1] = lst[i+1], lst[i]
            healWin.spellList:moveChildToIndex(sel, i+1)
        end

        -- ---------- SECCION HP POTS ----------
        fillComboItems(healWin.hpPotName, RQ.Catalog.hpPots)
        local fmtPotHp = function(e)
            local nm = findNameById(RQ.Catalog.hpPots, e.itemId) or ("id "..tostring(e.itemId))
            return string.format("HP<=%d : %s", e.hpBelow or 0, nm)
        end
        local function refreshHpPots()
            healWin.hpList:destroyChildren()
            local lst = C.list("heal.hpPots")
            for _, entry in ipairs(lst) do
                local row = addListRow(healWin.hpList, entry, fmtPotHp,
                    function(e)
                        for i, x in ipairs(lst) do if x == e then table.remove(lst, i); return end end
                    end, "RQItemEntry")
                pcall(function() row.preview:setItemId(entry.itemId or 0) end)
            end
        end
        refreshHpPots()
        healWin.hpBelow:setText("60")
        healWin.hpAdd.onClick = function()
            local opt = healWin.hpPotName:getCurrentOption()
            local nm = opt and opt.text or nil
            local hp = tonumber(healWin.hpBelow:getText())
            if not nm or not hp then RQ.Logger.warn("Heal", "faltan campos"); return end
            local id = findIdByName(RQ.Catalog.hpPots, nm) or 266
            table.insert(C.list("heal.hpPots"), {enabled=true, itemId=id, hpBelow=hp})
            refreshHpPots()
        end
        healWin.hpUp.onClick = function()
            local sel = healWin.hpList:getFocusedChild(); if not sel then return end
            local i = healWin.hpList:getChildIndex(sel); if i < 2 then return end
            local lst = C.list("heal.hpPots"); lst[i], lst[i-1] = lst[i-1], lst[i]
            healWin.hpList:moveChildToIndex(sel, i-1)
        end
        healWin.hpDown.onClick = function()
            local sel = healWin.hpList:getFocusedChild(); if not sel then return end
            local i = healWin.hpList:getChildIndex(sel)
            if i >= healWin.hpList:getChildCount() then return end
            local lst = C.list("heal.hpPots"); lst[i], lst[i+1] = lst[i+1], lst[i]
            healWin.hpList:moveChildToIndex(sel, i+1)
        end

        -- ---------- SECCION MP POTS ----------
        fillComboItems(healWin.mpPotName, RQ.Catalog.mpPots)
        local fmtPotMp = function(e)
            local nm = findNameById(RQ.Catalog.mpPots, e.itemId) or ("id "..tostring(e.itemId))
            return string.format("MP<=%d : %s", e.mpBelow or 0, nm)
        end
        local function refreshMpPots()
            healWin.mpList:destroyChildren()
            local lst = C.list("heal.mpPots")
            for _, entry in ipairs(lst) do
                local row = addListRow(healWin.mpList, entry, fmtPotMp,
                    function(e)
                        for i, x in ipairs(lst) do if x == e then table.remove(lst, i); return end end
                    end, "RQItemEntry")
                pcall(function() row.preview:setItemId(entry.itemId or 0) end)
            end
        end
        refreshMpPots()
        healWin.mpBelow:setText("40")
        healWin.mpAdd.onClick = function()
            local opt = healWin.mpPotName:getCurrentOption()
            local nm = opt and opt.text or nil
            local mp = tonumber(healWin.mpBelow:getText())
            if not nm or not mp then RQ.Logger.warn("Heal", "faltan campos"); return end
            local id = findIdByName(RQ.Catalog.mpPots, nm) or 268
            table.insert(C.list("heal.mpPots"), {enabled=true, itemId=id, mpBelow=mp})
            refreshMpPots()
        end
        healWin.mpUp.onClick = function()
            local sel = healWin.mpList:getFocusedChild(); if not sel then return end
            local i = healWin.mpList:getChildIndex(sel); if i < 2 then return end
            local lst = C.list("heal.mpPots"); lst[i], lst[i-1] = lst[i-1], lst[i]
            healWin.mpList:moveChildToIndex(sel, i-1)
        end
        healWin.mpDown.onClick = function()
            local sel = healWin.mpList:getFocusedChild(); if not sel then return end
            local i = healWin.mpList:getChildIndex(sel)
            if i >= healWin.mpList:getChildCount() then return end
            local lst = C.list("heal.mpPots"); lst[i], lst[i+1] = lst[i+1], lst[i]
            healWin.mpList:moveChildToIndex(sel, i+1)
        end
    end) end
    ui.rowHeal.btn.onClick = function() if healWin then healWin:show(); healWin:raise(); healWin:focus() end end

    -- ==========================================================
    --  SPELLS WINDOW
    -- ==========================================================
    local spellsWin
    if rootWidget then protect("SpellsWindow", function()
        spellsWin = UI.createWindow('RScriptzSpellsWindow', rootWidget); spellsWin:hide()
        spellsWin.closeButton.onClick = function() spellsWin:hide() end
        fillCombo(spellsWin.voc, RQ.Catalog.vocations, C.get("spells.voc"))
        local function refreshCombo(voc)
            fillCombo(spellsWin.spellName, RQ.Catalog.attackSpells[voc] or {})
        end
        refreshCombo(C.get("spells.voc"))
        spellsWin.voc.onOptionChange = function(w)
            local o = w:getCurrentOption(); local t = o and o.text or nil
            if t then C.set("spells.voc", t); refreshCombo(t) end
        end
        local fmt = function(e) return string.format("cada %dms MP>=%d : %s", e.cd or 0, e.minMana or 0, e.spell or "?") end
        local function refresh()
            spellsWin.list:destroyChildren()
            local lst = C.list("spells.rules")
            for _, entry in ipairs(lst) do
                addListRow(spellsWin.list, entry, fmt,
                    function(e) for i, x in ipairs(lst) do if x == e then table.remove(lst, i); return end end end)
            end
        end
        refresh()
        spellsWin.cd:setText("2000"); spellsWin.minMana:setText("60")
        spellsWin.add.onClick = function()
            local o = spellsWin.spellName:getCurrentOption(); local nm = o and o.text or nil
            local cd = tonumber(spellsWin.cd:getText()); local mn = tonumber(spellsWin.minMana:getText())
            if not nm or not cd or not mn then RQ.Logger.warn("Spells", "faltan campos"); return end
            table.insert(C.list("spells.rules"), {enabled=true, spell=nm, cd=cd, minMana=mn})
            refresh()
        end
        spellsWin.moveUp.onClick = function()
            local sel = spellsWin.list:getFocusedChild(); if not sel then return end
            local i = spellsWin.list:getChildIndex(sel); if i < 2 then return end
            local lst = C.list("spells.rules"); lst[i], lst[i-1] = lst[i-1], lst[i]
            spellsWin.list:moveChildToIndex(sel, i-1)
        end
        spellsWin.moveDown.onClick = function()
            local sel = spellsWin.list:getFocusedChild(); if not sel then return end
            local i = spellsWin.list:getChildIndex(sel)
            if i >= spellsWin.list:getChildCount() then return end
            local lst = C.list("spells.rules"); lst[i], lst[i+1] = lst[i+1], lst[i]
            spellsWin.list:moveChildToIndex(sel, i+1)
        end
    end) end
    ui.rowSpells.btn.onClick = function() if spellsWin then spellsWin:show(); spellsWin:raise(); spellsWin:focus() end end

    -- ==========================================================
    --  RUNES WINDOW
    -- ==========================================================
    local runesWin
    if rootWidget then
        runesWin = UI.createWindow('RScriptzRunesWindow', rootWidget); runesWin:hide()
        runesWin.closeButton.onClick = function() runesWin:hide() end
        fillComboItems(runesWin.runeName, RQ.Catalog.runes)
        -- preview del combo
        runesWin.runeName.onOptionChange = function(w)
            local o = w:getCurrentOption(); local nm = o and o.text or nil
            if nm then
                local id = findIdByName(RQ.Catalog.runes, nm)
                if id then runesWin.preview:setItemId(id) end
            end
        end
        pcall(function()
            local first = RQ.Catalog.runes[1]
            if first then runesWin.preview:setItemId(first.id) end
        end)
        runesWin.onlyMonsters:setChecked(C.get("runes.onlyMons", true))
        runesWin.onlyMonsters.onCheckChange = function(_, v) C.set("runes.onlyMons", v) end

        local fmt = function(e) return string.format("cada %dms HPtgt>=%d : %s", e.cd or 0, e.minHp or 0, e.name or "?") end
        local function refresh()
            runesWin.list:destroyChildren()
            local lst = C.list("runes.rules")
            for _, entry in ipairs(lst) do
                local row = addListRow(runesWin.list, entry, fmt,
                    function(e) for i, x in ipairs(lst) do if x == e then table.remove(lst, i); return end end end,
                    "RQItemEntry")
                pcall(function() row.preview:setItemId(entry.itemId or 0) end)
            end
        end
        refresh()
        runesWin.cd:setText("1000"); runesWin.minHp:setText("30")
        runesWin.add.onClick = function()
            local o = runesWin.runeName:getCurrentOption(); local nm = o and o.text or nil
            local cd = tonumber(runesWin.cd:getText()); local hp = tonumber(runesWin.minHp:getText())
            if not nm or not cd or not hp then RQ.Logger.warn("Runes", "faltan campos"); return end
            local id = findIdByName(RQ.Catalog.runes, nm)
            if not id then RQ.Logger.warn("Runes", "rune no valida"); return end
            table.insert(C.list("runes.rules"), {enabled=true, name=nm, itemId=id, cd=cd, minHp=hp})
            refresh()
        end
        runesWin.moveUp.onClick = function()
            local sel = runesWin.list:getFocusedChild(); if not sel then return end
            local i = runesWin.list:getChildIndex(sel); if i < 2 then return end
            local lst = C.list("runes.rules"); lst[i], lst[i-1] = lst[i-1], lst[i]
            runesWin.list:moveChildToIndex(sel, i-1)
        end
        runesWin.moveDown.onClick = function()
            local sel = runesWin.list:getFocusedChild(); if not sel then return end
            local i = runesWin.list:getChildIndex(sel)
            if i >= runesWin.list:getChildCount() then return end
            local lst = C.list("runes.rules"); lst[i], lst[i+1] = lst[i+1], lst[i]
            runesWin.list:moveChildToIndex(sel, i+1)
        end
    end
    ui.rowRunes.btn.onClick = function() if runesWin then runesWin:show(); runesWin:raise(); runesWin:focus() end end

    -- ==========================================================
    --  TARGET WINDOW
    -- ==========================================================
    local targetWin
    if rootWidget then
        targetWin = UI.createWindow('RScriptzTargetWindow', rootWidget); targetWin:hide()
        targetWin.closeButton.onClick = function() targetWin:hide() end
        local function updRng()
            targetWin.rangeText:setText("Rango maximo: "..C.get("target.range", 5).." tiles")
        end
        targetWin.range:setValue(C.get("target.range", 5)); updRng()
        targetWin.range.onValueChange = function(_, v) C.set("target.range", v); updRng() end
        targetWin.keepTarget:setChecked(C.get("target.keep", true))
        targetWin.keepTarget.onCheckChange = function(_, v) C.set("target.keep", v) end
        targetWin.preferLeader:setChecked(C.get("target.followLdr", false))
        targetWin.preferLeader.onCheckChange = function(_, v) C.set("target.followLdr", v) end
    end
    ui.rowTarget.btn.onClick = function() if targetWin then targetWin:show(); targetWin:raise(); targetWin:focus() end end

    -- ==========================================================
    --  FOLLOW WINDOW
    -- ==========================================================
    local followWin
    if rootWidget then
        followWin = UI.createWindow('RScriptzFollowWindow', rootWidget); followWin:hide()
        followWin.closeButton.onClick = function() followWin:hide() end
        followWin.leader:setText(C.get("follow.leader", ""))
        followWin.leader.onTextChange = function(_, t) C.set("follow.leader", t or "") end
        local function updDist()
            followWin.distText:setText("Distancia maxima al leader: "..C.get("follow.maxDist", 2).." tiles")
        end
        followWin.maxDist:setValue(C.get("follow.maxDist", 2)); updDist()
        followWin.maxDist.onValueChange = function(_, v) C.set("follow.maxDist", v); updDist() end
    end
    ui.rowFollow.btn.onClick = function() if followWin then followWin:show(); followWin:raise(); followWin:focus() end end

    -- ==========================================================
    --  MC HUNT WINDOW
    -- ==========================================================
    local mchWin
    if rootWidget then
        mchWin = UI.createWindow('RScriptzMCHuntWindow', rootWidget); mchWin:hide()
        mchWin.closeButton.onClick = function() mchWin:hide() end
        mchWin.isLeader:setChecked(C.get("mchunt.isLeader", false))
        mchWin.isLeader.onCheckChange = function(_, v)
            C.set("mchunt.isLeader", v); ui.rowMcHunt.sw:setOn(v)
        end
        mchWin.leaderName:setText(C.get("mchunt.leader", ""))
        mchWin.leaderName.onTextChange = function(_, t) C.set("mchunt.leader", t or "") end
        local function updPub()
            mchWin.pubText:setText("Frecuencia de publicacion: "..C.get("mchunt.pubMs", 500).." ms")
        end
        mchWin.pubMs:setValue(C.get("mchunt.pubMs", 500)); updPub()
        mchWin.pubMs.onValueChange = function(_, v) C.set("mchunt.pubMs", v); updPub() end
        mchWin.followOnSameFloor:setChecked(C.get("mchunt.followSame", true))
        mchWin.followOnSameFloor.onCheckChange = function(_, v) C.set("mchunt.followSame", v) end
        mchWin.crossFloors:setChecked(C.get("mchunt.crossFl", true))
        mchWin.crossFloors.onCheckChange = function(_, v) C.set("mchunt.crossFl", v) end
        mchWin.shareTarget:setChecked(C.get("mchunt.shareTgt", false))
        mchWin.shareTarget.onCheckChange = function(_, v) C.set("mchunt.shareTgt", v) end
    end
    ui.rowMcHunt.btn.onClick = function() if mchWin then mchWin:show(); mchWin:raise(); mchWin:focus() end end

    -- ==========================================================
    --  ANTI-PK WINDOW
    -- ==========================================================
    local pkWin
    if rootWidget then
        pkWin = UI.createWindow('RScriptzAntiPKWindow', rootWidget); pkWin:hide()
        pkWin.closeButton.onClick = function() pkWin:hide() end
        pkWin.broadcast:setChecked(C.get("antipk.broadcast", true))
        pkWin.broadcast.onCheckChange = function(_, v) C.set("antipk.broadcast", v) end
        pkWin.playSound:setChecked(C.get("antipk.sound", true))
        pkWin.playSound.onCheckChange = function(_, v) C.set("antipk.sound", v) end

        local function refresh()
            pkWin.list:destroyChildren()
            local lst = C.list("antipk.friends")
            for _, entry in ipairs(lst) do
                local row = g_ui.createWidget("RQNameEntry", pkWin.list)
                row:setText(entry.name or "?")
                row.remove.onClick = function()
                    for i, x in ipairs(lst) do if x == entry then table.remove(lst, i); break end end
                    row:destroy()
                end
            end
        end
        refresh()
        pkWin.add.onClick = function()
            local nm = pkWin.nameInput:getText()
            if not nm or nm == "" then return end
            nm = nm:gsub("^%s+",""):gsub("%s+$","")
            table.insert(C.list("antipk.friends"), {name=nm})
            pkWin.nameInput:setText("")
            refresh()
        end
    end
    ui.rowAntiPk.btn.onClick = function() if pkWin then pkWin:show(); pkWin:raise(); pkWin:focus() end end

    -- ==========================================================
    --  MOTORES (macros)
    -- ==========================================================

    -- HEALING: recorrer lista de spells
    macro(200, "RScriptz: Healing spells", function()
        if not C.get("master.on", true) then return end
        if not C.get("heal.on", true) then return end
        local hp = RQ.Game.hp(); local mp = RQ.Game.mana()
        for _, r in ipairs(C.list("heal.spells")) do
            if r.enabled and hp <= (r.hpBelow or 0) and mp >= (r.minMp or 0) then
                cast(r.spell, 900); return
            end
        end
    end)

    -- HEALING: pociones HP
    macro(200, "RScriptz: Healing HP pots", function()
        if not C.get("master.on", true) then return end
        if not C.get("heal.on", true) then return end
        local hp = RQ.Game.hp()
        for _, r in ipairs(C.list("heal.hpPots")) do
            if r.enabled and hp <= (r.hpBelow or 0) then
                useOnYourself(tonumber(r.itemId) or 266); return
            end
        end
    end)

    -- HEALING: pociones MP
    macro(200, "RScriptz: Healing MP pots", function()
        if not C.get("master.on", true) then return end
        if not C.get("heal.on", true) then return end
        local mp = RQ.Game.mana()
        for _, r in ipairs(C.list("heal.mpPots")) do
            if r.enabled and mp <= (r.mpBelow or 0) then
                useOnYourself(tonumber(r.itemId) or 268); return
            end
        end
    end)

    -- SPELLS ATAQUE: recorrer lista, con cooldown por regla
    local lastSpellCast = {}
    macro(200, "RScriptz: Attack spells", function()
        if not C.get("master.on", true) then return end
        if not C.get("spells.on", false) then return end
        if not getAttackingCreature() then return end
        local mp = RQ.Game.mana()
        local nowMs = g_clock.millis()
        for i, r in ipairs(C.list("spells.rules")) do
            if r.enabled and mp >= (r.minMana or 0) then
                local key = "s"..i.."_"..(r.spell or "")
                local last = lastSpellCast[key] or 0
                if nowMs - last >= (r.cd or 2000) then
                    say(r.spell); lastSpellCast[key] = nowMs; return
                end
            end
        end
    end)

    -- RUNES: recorrer lista, cooldown por regla
    local lastRuneUse = {}
    macro(200, "RScriptz: Runes", function()
        if not C.get("master.on", true) then return end
        if not C.get("runes.on", false) then return end
        local tgt = getAttackingCreature(); if not tgt then return end
        if C.get("runes.onlyMons", true) and tgt:isPlayer() then return end
        local hpT = tgt:getHealthPercent()
        local nowMs = g_clock.millis()
        for i, r in ipairs(C.list("runes.rules")) do
            if r.enabled and hpT >= (r.minHp or 0) then
                local key = "r"..i.."_"..(r.itemId or 0)
                local last = lastRuneUse[key] or 0
                if nowMs - last >= (r.cd or 1000) then
                    useWith(tonumber(r.itemId) or 3155, tgt); lastRuneUse[key] = nowMs; return
                end
            end
        end
    end)

    -- TARGET AUTO
    macro(500, "RScriptz: Auto Target", function()
        if not C.get("master.on", true) then return end
        if not C.get("target.on", false) then return end
        local cur = getAttackingCreature()
        if cur and C.get("target.keep", true) then return end
        local miPos = RQ.Game.pos(); if not miPos then return end
        local maxR = C.get("target.range", 5)
        local mejor, mejorD = nil, 999
        for _, c in ipairs(RQ.Game.creatures()) do
            if c.isMonster and c.pos and c.pos.z == miPos.z then
                local d = RQ.Game.dist(miPos, c.pos)
                if d <= maxR and d < mejorD then mejorD = d; mejor = c end
            end
        end
        if mejor and mejor.ref then pcall(function() attack(mejor.ref) end) end
    end)

    -- FOLLOW
    macro(300, "RScriptz: Follow", function()
        if not C.get("master.on", true) then return end
        if not C.get("follow.on", false) then return end
        local nom = C.get("follow.leader", ""); if nom == "" then return end
        local ldr = RQ.Game.jugadorPorNombre(nom); if not ldr or not ldr.pos then return end
        local miPos = RQ.Game.pos(); if not miPos then return end
        if ldr.pos.z ~= miPos.z then return end
        local d = RQ.Game.dist(miPos, ldr.pos)
        if d > C.get("follow.maxDist", 2) then
            if RQ.Game.hayCamino(ldr.pos, 20) then RQ.Game.irHacia(ldr.pos, 20) end
        end
    end)

    -- MC HUNT: publicar leader_pos
    RQ.Scheduler.every("rq_mch_pub", 500, function()
        if not C.get("master.on", true) then return end
        if not C.get("mchunt.isLeader", false) then return end
        if not RQ.Net.conectado then return end
        local p = RQ.Game.pos(); if not p then return end
        RQ.Net.send("leader_pos", {x=p.x, y=p.y, z=p.z})
    end)

    -- MC HUNT: cambio de piso
    local ultimoZ = nil
    RQ.Scheduler.every("rq_mch_cross", 200, function()
        if not C.get("master.on", true) then return end
        if not C.get("mchunt.isLeader", false) then return end
        if not RQ.Net.conectado then return end
        local p = RQ.Game.pos(); if not p then return end
        if ultimoZ and ultimoZ ~= p.z then
            RQ.Net.send("leader_cross", {x=p.x, y=p.y, zOld=ultimoZ, zNew=p.z})
            RQ.Logger.info("MCHunt", "publique cruce "..ultimoZ.."->"..p.z)
        end
        ultimoZ = p.z
    end)

    RQ.Scheduler.every("rq_mch_pub_freq", 2000, function()
        RQ.Scheduler.setInterval("rq_mch_pub", C.get("mchunt.pubMs", 500))
    end)

    RQ.Net.on("leader_pos", function(from, data)
        if not C.get("master.on", true) then return end
        if C.get("mchunt.isLeader", false) then return end
        if not C.get("mchunt.followSame", true) then return end
        if C.get("mchunt.leader", "") ~= from then return end
        if not data or not data.x then return end
        local miPos = RQ.Game.pos(); if not miPos then return end
        if data.z == miPos.z then
            local d = RQ.Game.dist(miPos, {x=data.x, y=data.y})
            if d > 3 and RQ.Game.hayCamino({x=data.x, y=data.y, z=data.z}, 30) then
                RQ.Game.irHacia({x=data.x, y=data.y, z=data.z}, 30)
            end
        end
    end)

    RQ.Net.on("leader_cross", function(from, data)
        if not C.get("master.on", true) then return end
        if C.get("mchunt.isLeader", false) then return end
        if not C.get("mchunt.crossFl", true) then return end
        if C.get("mchunt.leader", "") ~= from then return end
        if not data or not data.x then return end
        RQ.Logger.info("MCHunt", "leader "..from.." cruzo "..tostring(data.zOld).."->"..tostring(data.zNew))
        local miPos = RQ.Game.pos(); if not miPos then return end
        if miPos.z == data.zOld and RQ.Game.hayCamino({x=data.x, y=data.y, z=data.zOld}, 20) then
            RQ.Game.irHacia({x=data.x, y=data.y, z=data.zOld}, 20)
            local key = "rq_mch_use_"..tostring(data.x).."_"..tostring(data.y)
            RQ.Scheduler.every(key, 400, function()
                local ahora = RQ.Game.pos(); if not ahora then return end
                if ahora.x == data.x and ahora.y == data.y then
                    pcall(function()
                        local tile = g_map.getTile({x=data.x, y=data.y, z=ahora.z})
                        if tile then use(tile) end
                    end)
                    RQ.Scheduler.remove(key)
                end
            end)
        end
    end)

    -- ANTI-PK
    local pksVistos = {}
    local function esAmigo(nom)
        for _, f in ipairs(C.list("antipk.friends")) do
            if f.name == nom then return true end
        end
        return false
    end

    RQ.Scheduler.every("rq_antipk", 1000, function()
        if not C.get("master.on", true) then return end
        if not C.get("antipk.on", true) then return end
        local yo = RQ.Game.name()
        local mchLdr = C.get("mchunt.leader", "")
        for _, c in ipairs(RQ.Game.creatures()) do
            if c.isPlayer and c.name ~= yo and c.name ~= mchLdr and not esAmigo(c.name) then
                if not pksVistos[c.name] then
                    pksVistos[c.name] = os.time()
                    RQ.Logger.warn("AntiPK", "ALERTA: "..c.name.." aparecio")
                    if C.get("antipk.sound", true) then
                        pcall(function() g_sounds:getChannel(1):play("/sounds/notification.ogg") end)
                    end
                    if C.get("antipk.broadcast", true) and RQ.Net.conectado then
                        RQ.Net.send("antipk_alert", {who=c.name})
                    end
                end
            end
        end
        for nom, ts in pairs(pksVistos) do
            if os.time() - ts > 30 then pksVistos[nom] = nil end
        end
    end)

    RQ.Net.on("antipk_alert", function(from, data)
        if not C.get("master.on", true) then return end
        RQ.Logger.warn("AntiPK", "aviso de "..tostring(from)..": "..tostring(data.who))
    end)

    -- ==========================================================
    --  ARRANQUE
    -- ==========================================================
    macro(50, "RScriptz Core (no apagar)", function() RQ.Scheduler.tick() end)

    RQ.Scheduler.every("rq_net_autoconnect", 5000, function()
        if not RQ.Net.conectado then RQ.Net.connect(C.get("net.canal", "rq")) end
    end)

    RQ.Scheduler.every("rq_net_poll", 300, function() RQ.Net.poll() end)

    pcall(function()
        broadcastMessage("RScriptz v"..RQ.version.." CARGADO - "..RQ.Game.name())
    end)
    RQ.Logger.info("RScriptz", "listo v"..RQ.version.." - pestana RQ")

end

-- ==========================================================
--  ARRANQUE: si ya hay tier guardado revalidar y correr, sino selector
-- ==========================================================
local savedTier = storage.rscriptz_tier
local savedKey  = storage.rscriptz_key
if savedTier == "VIP" and savedKey then
    -- revalidacion silenciosa
    local charName = ""
    pcall(function() charName = player:getName() end)
    validateLicense(savedKey, charName, function(ok, reason)
        if ok then
            RQ.tier = "VIP"
            rqSetupFullBot()
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
    rqSetupFreeBot()
else
    showTierSelector()
end
