-- UI test bench: stubs the KOReader modules used by main.lua and plays full games.
-- Usage (from the plugin folder): luajit tests/test_ui_mock.lua . [language]
-- e.g. "en" (default) or "fr"; with a non-English language, every displayed
-- string must have a translation.
package.path = (arg[1] or ".") .. "/?.lua;" .. package.path
local LANG = arg[2] or "en"
G_reader_settings = { readSetting = function(_, k) if k == "language" then return LANG end end }

local function class()
    local c = {}
    c.__index = c
    function c:extend(o)
        o = o or {}
        o.__index = o
        return setmetatable(o, { __index = self })
    end
    function c:new(o)
        o = o or {}
        setmetatable(o, { __index = self })
        if o.init then o:init() end
        return o
    end
    return c
end

local shown = {}
local function preload(name, value) package.preload[name] = function() return value end end

preload("ffi/blitbuffer", { COLOR_WHITE = 255, COLOR_BLACK = 0, COLOR_GRAY = 170, COLOR_GRAY_D = 221,
    COLOR_LIGHT_GRAY = 204, COLOR_DARK_GRAY = 136, COLOR_GRAY_4 = 68 })
local Button = class()
function Button:setText(t) self.text = t end
function Button:enableDisable(e) self.enabled = e end
local ButtonTable = class()
function ButtonTable:init()
    self.byId = {}
    for _, row in ipairs(self.buttons) do
        for _, b in ipairs(row) do
            assert(type(b.callback) == "function", "button without callback")
            if b.id then self.byId[b.id] = Button:new{ text = b.text, width = 100 } end
        end
    end
end
function ButtonTable:getButtonById(id) return self.byId[id] end
preload("ui/widget/buttontable", ButtonTable)
preload("ui/widget/buttondialog", class())
preload("datastorage", { getSettingsDir = function() return "/tmp" end })
preload("device", { screen = { getWidth = function() return 1072 end, getHeight = function() return 1448 end },
    hasKeys = function() return false end })
preload("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
preload("ui/widget/container/framecontainer", class())
preload("ui/geometry", class())
preload("ui/gesturerange", class())
preload("ui/widget/infomessage", class())
preload("ui/widget/container/inputcontainer", class())
local store = {}
preload("luasettings", { open = function(_, path)
    store[path] = store[path] or {}
    local data = store[path]
    return {
        readSetting = function(_, k) return data[k] end,
        saveSetting = function(_, k, v) data[k] = v end,
        flush = function() end,
    }
end })
local painted = 0
preload("ui/rendertext", {
    sizeUtf8Text = function(_, _, w, face, text)
        local s = face.size or 20
        return { x = math.min(w, s * 0.6 * #text), y_top = -s * 0.7, y_bottom = s * 0.2 }
    end,
    renderUtf8Text = function(_, _, _, _, _, text) assert(type(text) == "string") painted = painted + 1 end,
})
preload("ui/size", { line = { thin = 1, thick = 2 }, padding = { default = 5 }, span = { vertical_large = 10 } })
local TextWidget = class()
function TextWidget:setText(t) assert(type(t) == "string", "status is not a string") self.text = t end
preload("ui/widget/textwidget", TextWidget)
preload("ui/uimanager", {
    show = function(_, w) shown[#shown + 1] = w end,
    close = function() end,
    setDirty = function(_, _, f) if type(f) == "function" then f() end end,
    forceRePaint = function() end,
})
local VerticalGroup = class()
function VerticalGroup:getSize() return { w = 1000, h = 1400 } end
function VerticalGroup:paintTo(bb, x, y)
    for _, child in ipairs(self) do
        if child.paintTo then child:paintTo(bb, x, y) end
        if child[1] and child[1].paintTo then child[1]:paintTo(bb, x, y) end
    end
end
preload("ui/widget/verticalgroup", VerticalGroup)
preload("ui/widget/verticalspan", class())
preload("ui/widget/container/widgetcontainer", class())
preload("ffi/util", { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(k) return tostring(args[tonumber(k)]) end))
end })

local fails = 0
local function check(c, m) if not c then fails = fails + 1 print("FAIL: " .. m) end end

local bbW, bbH = 1072, 1448
local bb = { paintRect = function(_, x, y, w, h, color)
    assert(type(x) == "number" and type(y) == "number" and type(w) == "number" and type(h) == "number", "paintRect args")
    assert(color ~= nil, "nil colour")
    assert(x >= 0 and y >= 0 and x + w <= bbW and y + h <= bbH, ("off screen %d,%d %dx%d"):format(x, y, w, h))
end }

-- Paints the grid widget alone at an offset and checks that nothing leaves its bounds
-- (regression test for border strokes sticking out of the outer frame).
local function checkGridBounds(widget, label)
    local ox, oy = 37, 53
    local W = widget.dimen.w
    local outside = 0
    local clip = { paintRect = function(_, x, y, w, h)
        if x < ox or y < oy or x + w > ox + W or y + h > oy + W then
            outside = outside + 1
        end
    end }
    widget:paintTo(clip, ox, oy)
    check(outside == 0, ("%d rectangles outside the grid (%s)"):format(outside, label))
end

local Suguru = dofile((arg[1] or ".") .. "/main.lua")
local function newPlugin()
    local p = Suguru:new{ ui = { menu = { registerToMainMenu = function() end } } }
    p:init()
    local items = {}
    p:addToMainMenu(items)
    check(items.suguru and items.suguru.sorting_hint == "tools", "entry in the Tools menu")
    return p, items
end

local plugin, items = newPlugin()
items.suguru.callback()
local screen = plugin.screen
check(screen ~= nil, "screen opened")
local board = screen.board
check(board.n == 6 and board.difficulty == "medium", "default game is 6x6 medium")

screen:paintTo(bb, 0, 0)
check(painted > 0, "grid painted")
checkGridBounds(screen.board_widget, "default game")

-- tap on a cell
local rect = screen.board_widget.paint_rect
local cell = rect.w / board.n
screen.board_widget:onTap(nil, { pos = { x = rect.x + cell * 2.5, y = rect.y + cell * 3.5 } })
check(board.selected == 3 * board.n + 3, "selection by tap")
check(screen.board_widget:onTap(nil, { pos = { x = rect.x - 5, y = rect.y } }) == false, "tap outside the grid ignored")

-- play on an empty cell
local empty
for i = 1, board.N do if not board:isGiven(i) then empty = i break end end
board.selected = empty
screen:onDigit(1)
check(board.user[empty] == 1, "digit entry")
screen:onUndo()
check(board.user[empty] == 0, "undo entry")
screen:toggleNoteMode()
screen:onDigit(2) screen:onDigit(4)
check(board.notes[empty] == 2 + 8, "notes 2 and 4")
screen:paintTo(bb, 0, 0)
screen:onDigit(2)
check(board.notes[empty] == 8, "note 2 removed")
screen:toggleNoteMode()
screen:onErase()
check(board.notes[empty] == 0, "erase clears notes")

-- given cell cannot be edited
for i = 1, board.N do if board:isGiven(i) then board.selected = i break end end
local before = board:value(board.selected)
screen:onDigit(5)
check(board:value(board.selected) == before, "given cell protected")

-- visible conflict
board.selected = empty
local vconf = board:value(board.topo.peers[empty][1])
if vconf ~= 0 then
    screen:onDigit(vconf)
    check(board.conflicts[empty], "conflict detected")
    screen:paintTo(bb, 0, 0)
    screen:onErase()
end

-- solve the whole grid by following hints
local guard = 0
while not board:isSolved() and guard < 200 do
    guard = guard + 1
    screen:onHint()
    local i = board.hint_cell
    if not i then break end
    screen:onDigit(board.solution[i])
    screen:paintTo(bb, 0, 0)
end
check(board:isSolved(), "grid solved by hints (" .. guard .. " moves)")
screen:onCheck()

-- deliberate mistake, then Check / Hint
local i2
for i = 1, board.N do if not board:isGiven(i) then i2 = i break end end
board.selected = i2
local wrongv = (board.solution[i2] % board.topo.rsize[board.region[i2]]) + 1
if wrongv ~= board.solution[i2] then
    screen:onDigit(wrongv)
    screen:onCheck()
    check(board.wrong[i2], "mistake marked")
    screen:paintTo(bb, 0, 0)
    screen:onHint()
    check(board.selected == i2, "hint points at the mistake")
    screen:onErase()
end

-- reveal solution
screen:toggleReveal()
check(board.reveal, "solution shown")
screen:paintTo(bb, 0, 0)
screen:onDigit(1)
screen:toggleReveal()
check(not board.reveal, "solution hidden")

-- new games, every size and level
for _, n in ipairs({ 5, 6, 7, 8 }) do
    for _, lv in ipairs({ "easy", "medium", "hard" }) do
        screen:startNewGame(n, lv)
        check(board.n == n and board.difficulty == lv, ("new game %dx%d %s"):format(n, n, lv))
        screen:paintTo(bb, 0, 0)
        checkGridBounds(screen.board_widget, ("%dx%d %s"):format(n, n, lv))
        screen.board_widget:onTap(nil, { pos = { x = rect.x + rect.w - 1, y = rect.y + rect.h - 1 } })
        check(board.selected == n * n, "tap on the last cell " .. n)
    end
end
-- menus
screen:openNewGameMenu()
local dlg = shown[#shown]
check(dlg.buttons and #dlg.buttons[1] == 4, "size menu")
dlg.buttons[1][2].callback()
local dlg2 = shown[#shown]
check(dlg2.buttons and #dlg2.buttons[1] == 3, "difficulty menu")
dlg2.buttons[1][1].callback()
check(board.n == 6 and board.difficulty == "easy", "game started from menus")
screen:showRules()

-- save and resume
for i = 1, board.N do if not board:isGiven(i) then board.selected = i break end end
local sel = board.selected
screen:onDigit(board.solution[sel])
screen:closeScreen()
check(plugin.screen == nil, "screen closed")
local plugin2, items2 = newPlugin()
items2.suguru.callback()
local b2 = plugin2.screen.board
check(b2.n == 6 and b2.user[sel] == board.solution[sel], "game resumed from save")
-- corrupted save -> fresh grid
for _, data in pairs(store) do data.state = { version = 1, n = 6, region = { 1 }, puzzle = {}, solution = {}, user = {} } end
local plugin3, items3 = newPlugin()
items3.suguru.callback()
check(plugin3.screen and plugin3.screen.board.topo ~= nil, "corrupted save ignored")

-- language
local L = require("suguru_i18n")
check(L.lang == LANG, "language detected: " .. tostring(L.lang))
local noteText = plugin3.screen.note_button.text
if LANG == "fr" then
    check(noteText == "Notes : non", "French button text: " .. tostring(noteText))
    local missing = {}
    for s in pairs(L.missing) do missing[#missing + 1] = s end
    check(#missing == 0, "untranslated strings: " .. table.concat(missing, " | "))
elseif LANG == "en" then
    check(noteText == "Notes: off", "English button text: " .. tostring(noteText))
end
check(L("RULES_TEXT") ~= "RULES_TEXT", "rules text resolved")

print(fails == 0 and ("UI TESTS PASSED (" .. LANG .. ")") or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
