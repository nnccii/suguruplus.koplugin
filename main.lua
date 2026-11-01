-- Suguru for KOReader.
-- UI adapted from sudoku.koplugin (https://github.com/omer-faruq/sudoku.koplugin, GPL-3.0).
-- Deduction engine ported from sen-ltd/suguru (MIT) - see THIRD_PARTY_NOTICES.md.
-- User-facing strings are in French.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local Core = require("suguru_core")

local Screen = Device.screen
local MAXV = Core.MAX_REGION
local HAS, BIT, WITHOUT = Core.HAS, Core.BIT, Core.WITHOUT

local SIZES = { 5, 6, 7, 8 }
local DEFAULT_SIZE = 6
local DIFFICULTY_ORDER = { "easy", "medium", "hard" }
local DEFAULT_DIFFICULTY = "medium"
local DIFFICULTY_LABELS = { easy = "Facile", medium = "Moyen", hard = "Difficile" }

local RULES_TEXT = [[Suguru

Le but est de remplir toutes les cases avec des chiffres.

1. Les traits épais découpent la grille en zones.
2. Une zone de 2 cases contient 1 et 2. Une zone de 3 cases contient 1, 2 et 3. Et ainsi de suite jusqu'à 5.
3. Deux cases qui se touchent, même par un coin, n'ont jamais le même chiffre.

Les chiffres en gras sont donnés au départ. Il n'y a qu'une solution, et on la trouve sans jamais deviner.]]

-- Colours (with fallbacks in case a shade does not exist in this KOReader version)
local C_WHITE = Blitbuffer.COLOR_WHITE
local C_BLACK = Blitbuffer.COLOR_BLACK
local C_REGION = Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_GRAY_D or Blitbuffer.COLOR_LIGHT_GRAY
local C_SELECT = Blitbuffer.COLOR_GRAY_B or Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_GRAY
local C_THIN = Blitbuffer.COLOR_GRAY_9 or Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY
local C_USER = Blitbuffer.COLOR_GRAY_2 or Blitbuffer.COLOR_DARK_GRAY or C_BLACK
local C_NOTE = Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_DARK_GRAY or C_BLACK
local C_SOLUTION = Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_DARK_GRAY or C_BLACK

local function filled(N, v)
    local t = {}
    for i = 1, N do
        t[i] = v
    end
    return t
end

local function copyFlat(src, N, default)
    local t = {}
    for i = 1, N do
        local v = src and src[i]
        if v == nil then
            v = default
        end
        t[i] = v
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Board (game state)
-- ---------------------------------------------------------------------------
local Board = {}
Board.__index = Board

function Board:new()
    return setmetatable({ undo_stack = {} }, self)
end

function Board:setup(game, difficulty)
    local n = game.n
    local N = n * n
    local topo = Core.buildTopology(n, game.region)
    if not topo then
        return false
    end
    self.n, self.N, self.topo = n, N, topo
    self.region = copyFlat(game.region, N, 1)
    self.puzzle = copyFlat(game.puzzle, N, 0)
    self.solution = copyFlat(game.solution, N, 0)
    self.user = filled(N, 0)
    self.notes = filled(N, 0) -- bitmask of noted digits
    self.wrong = filled(N, false)
    self.selected = 1
    self.difficulty = difficulty or self.difficulty or DEFAULT_DIFFICULTY
    self.reveal = false
    self.hint_cell = nil
    self.undo_stack = {}
    self:recalcConflicts()
    return true
end

function Board:generate(n, difficulty)
    local game = Core.generate(n, difficulty, math.random)
    if not game then
        return false
    end
    return self:setup(game, difficulty)
end

function Board:serialize()
    return {
        version = 1,
        n = self.n,
        region = copyFlat(self.region, self.N),
        puzzle = copyFlat(self.puzzle, self.N),
        solution = copyFlat(self.solution, self.N),
        user = copyFlat(self.user, self.N),
        notes = copyFlat(self.notes, self.N),
        difficulty = self.difficulty,
        selected = self.selected,
        reveal = self.reveal,
    }
end

function Board:load(state)
    if type(state) ~= "table" or state.version ~= 1 or type(state.n) ~= "number" then
        return false
    end
    local n = state.n
    local N = n * n
    for _, key in ipairs({ "region", "puzzle", "solution", "user" }) do
        if type(state[key]) ~= "table" or #state[key] ~= N then
            return false
        end
    end
    if not self:setup({ n = n, region = state.region, puzzle = state.puzzle, solution = state.solution },
        state.difficulty) then
        return false
    end
    if not Core.isValidSolution(self.topo, self.solution) then
        return false
    end
    self.user = copyFlat(state.user, N, 0)
    self.notes = copyFlat(state.notes, N, 0)
    self.selected = math.max(1, math.min(N, tonumber(state.selected) or 1))
    self.reveal = state.reveal and true or false
    self:recalcConflicts()
    return true
end

function Board:rc(i)
    return math.floor((i - 1) / self.n) + 1, (i - 1) % self.n + 1
end

function Board:isGiven(i)
    return self.puzzle[i] ~= 0
end

function Board:value(i)
    local g = self.puzzle[i]
    if g ~= 0 then
        return g
    end
    return self.user[i]
end

function Board:workingGrid()
    local t = {}
    for i = 1, self.N do
        t[i] = self:value(i)
    end
    return t
end

function Board:recalcConflicts()
    self.conflicts = filled(self.N, false)
    for i = 1, self.N do
        local v = self:value(i)
        if v ~= 0 then
            if v > self.topo.rsize[self.region[i]] then
                self.conflicts[i] = true
            end
            for _, j in ipairs(self.topo.peers[i]) do
                if self:value(j) == v then
                    self.conflicts[i] = true
                    self.conflicts[j] = true
                end
            end
        end
    end
end

function Board:pushUndo(entry)
    self.undo_stack[#self.undo_stack + 1] = entry
end

function Board:canUndo()
    return self.undo_stack[1] ~= nil
end

local function editable(self)
    if self.reveal then
        return false, "Masque la solution pour continuer."
    end
    if self:isGiven(self.selected) then
        return false, "Cette case est donnée."
    end
    return true
end

function Board:setValue(v)
    local ok, err = editable(self)
    if not ok then
        return false, err
    end
    local i = self.selected
    local prev_v, prev_notes = self.user[i], self.notes[i]
    local new_v = v or 0
    if prev_v == new_v and prev_notes == 0 then
        return v ~= nil, (v == nil) and "Case déjà vide." or nil
    end
    self:pushUndo{ i = i, value = prev_v, notes = prev_notes }
    self.user[i] = new_v
    self.notes[i] = 0
    self.wrong[i] = false
    self.hint_cell = nil
    self:recalcConflicts()
    return true
end

function Board:toggleNote(v)
    local ok, err = editable(self)
    if not ok then
        return false, err
    end
    local i = self.selected
    if self.user[i] ~= 0 then
        return false, "Efface la case avant d'ajouter des notes."
    end
    local m = self.notes[i]
    self:pushUndo{ i = i, value = self.user[i], notes = m }
    if HAS[m][v] then
        self.notes[i] = WITHOUT[m][v]
    else
        self.notes[i] = m + BIT[v]
    end
    return true
end

function Board:undo()
    local e = table.remove(self.undo_stack)
    if not e then
        return false, "Rien à annuler."
    end
    self.user[e.i] = e.value
    self.notes[e.i] = e.notes
    self.wrong[e.i] = false
    self.selected = e.i
    self.hint_cell = nil
    self:recalcConflicts()
    return true
end

function Board:remaining()
    local r = 0
    for i = 1, self.N do
        if self:value(i) == 0 then
            r = r + 1
        end
    end
    return r
end

function Board:isSolved()
    if self.reveal then
        return false
    end
    for i = 1, self.N do
        if self:value(i) ~= self.solution[i] then
            return false
        end
    end
    return true
end

function Board:markWrong()
    local any = false
    for i = 1, self.N do
        local v = self.user[i]
        self.wrong[i] = (v ~= 0 and v ~= self.solution[i])
        any = any or self.wrong[i]
    end
    return any
end

-- Hint: point at a mistake first, otherwise the next logical deduction.
function Board:hint()
    if self.reveal then
        return nil, "Masque la solution pour continuer."
    end
    for i = 1, self.N do
        local v = self.user[i]
        if v ~= 0 and v ~= self.solution[i] then
            self.wrong[i] = true
            self.selected = i
            return i, "Cette case est fausse : efface-la."
        end
    end
    local cell, digit, rules = Core.nextDeduction(self.topo, self:workingGrid())
    if not cell then
        return nil, "Aucune déduction simple trouvée."
    end
    self.selected = cell
    self.hint_cell = cell
    local how = (rules == "singles")
        and "car c'est le seul chiffre possible dans cette case, ou la seule place pour ce chiffre dans sa zone"
        or "on le trouve en essayant toutes les façons de remplir les zones voisines"
    return cell, T("Indice : un %1 va ici, %2.", digit, how)
end

-- ---------------------------------------------------------------------------
-- Grid widget
-- ---------------------------------------------------------------------------
local BoardWidget = InputContainer:extend{
    board = nil,
}

local function fitFace(name, start, max_w, max_h, min_size)
    local size = start
    while size > min_size do
        local face = Font:getFace(name, size)
        local m = RenderText:sizeUtf8Text(0, max_w, face, "8", true, true)
        if m.x <= max_w and (m.y_bottom - m.y_top) <= max_h then
            return face
        end
        size = size - 1
    end
    return Font:getFace(name, min_size)
end

function BoardWidget:init()
    self.size = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.86)
    self.dimen = Geom:new{ w = self.size, h = self.size }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self:updateFonts()
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.paint_rect end,
            },
        },
    }
end

function BoardWidget:updateFonts()
    local n = self.board.n
    if self.font_n == n then
        return
    end
    self.font_n = n
    local cell = self.size / n
    local inner = math.floor(cell * 0.62)
    self.number_face = fitFace("cfont", math.floor(cell * 0.7), inner, inner, 10)
    local mini = math.floor(cell / 3 * 0.8)
    self.note_face = fitFace("smallinfofont", math.floor(cell / 3), mini, mini, 8)
end

function BoardWidget:onTap(_, ges)
    if not (self.board and ges and ges.pos) then
        return false
    end
    local rect = self.paint_rect
    local lx, ly = ges.pos.x - rect.x, ges.pos.y - rect.y
    if lx < 0 or ly < 0 or lx >= rect.w or ly >= rect.h then
        return false
    end
    local n = self.board.n
    local cell = rect.w / n
    local col = math.min(n, math.floor(lx / cell) + 1)
    local row = math.min(n, math.floor(ly / cell) + 1)
    self.board.selected = (row - 1) * n + col
    if self.onSelectionChanged then
        self.onSelectionChanged()
    end
    self:refresh()
    return true
end

function BoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

local function centerText(bb, face, text, cx, cy, w, h, color, bold)
    local m = RenderText:sizeUtf8Text(0, w, face, text, true, bold)
    local baseline = cy + math.floor((h + m.y_top - m.y_bottom) / 2)
    local tx = cx + math.floor((w - m.x) / 2)
    RenderText:renderUtf8Text(bb, tx, baseline, face, text, true, bold, color)
end

function BoardWidget:paintTo(bb, x, y)
    local board = self.board
    if not board then
        return
    end
    self:updateFonts()
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    local n = board.n
    local W = self.dimen.w
    local cell = W / n
    local function cx(c) return x + math.floor((c - 1) * cell) end
    local function cy(r) return y + math.floor((r - 1) * cell) end
    local cw = math.ceil(cell)

    -- Every rectangle is clipped to the grid so that centred border strokes never
    -- stick out past the outer frame.
    local function fill(px, py, w, h, color)
        local x2 = math.min(px + w, x + W)
        local y2 = math.min(py + h, y + W)
        px = math.max(px, x)
        py = math.max(py, y)
        if x2 > px and y2 > py then
            bb:paintRect(px, py, x2 - px, y2 - py, color)
        end
    end

    bb:paintRect(x, y, W, W, C_WHITE)

    -- highlight: the selected cell's region, then the cell itself
    local sel = board.selected
    local rid = board.region[sel]
    for _, j in ipairs(board.topo.cells[rid]) do
        local r, c = board:rc(j)
        fill(cx(c), cy(r), cw, cw, C_REGION)
    end
    do
        local r, c = board:rc(sel)
        fill(cx(c), cy(r), cw, cw, C_SELECT)
    end

    -- thin grid lines
    local thin = math.max(1, Size.line.thin or 1)
    for k = 1, n - 1 do
        local off = math.floor(k * cell)
        fill(x + off, y, thin, W, C_THIN)
        fill(x, y + off, W, thin, C_THIN)
    end

    -- region borders (thick strokes centred on the grid lines)
    local thick = math.max(Size.line.thick or 2, math.floor(cell / 16))
    local half = math.floor(thick / 2)
    for r = 1, n do
        for c = 1, n do
            local i = (r - 1) * n + c
            if c < n and board.region[i] ~= board.region[i + 1] then
                fill(x + math.floor(c * cell) - half, cy(r) - half, thick, cw + thick, C_BLACK)
            end
            if r < n and board.region[i] ~= board.region[i + n] then
                fill(cx(c) - half, y + math.floor(r * cell) - half, cw + thick, thick, C_BLACK)
            end
        end
    end
    -- outer frame, drawn inside the grid bounds
    fill(x, y, W, thick, C_BLACK)
    fill(x, y + W - thick, W, thick, C_BLACK)
    fill(x, y, thick, W, C_BLACK)
    fill(x + W - thick, y, thick, W, C_BLACK)

    -- digits and notes
    local pad = thick
    local inner = cw - 2 * pad
    for i = 1, board.N do
        local r, c = board:rc(i)
        local px, py = cx(c), cy(r)
        local given = board:isGiven(i)
        local v
        if board.reveal then
            v = board.solution[i]
        else
            v = board:value(i)
        end
        if v ~= 0 then
            local color = given and C_BLACK or (board.reveal and C_SOLUTION or C_USER)
            centerText(bb, self.number_face, tostring(v), px + pad, py + pad, inner, inner, color, given)
            if not board.reveal and board.conflicts[i] then
                -- conflict: thick bar under the digit (readable in greyscale)
                local bw = math.floor(inner * 0.6)
                bb:paintRect(px + math.floor((cw - bw) / 2), py + cw - pad - math.max(3, math.floor(cell / 14)),
                    bw, math.max(3, math.floor(cell / 18)), C_BLACK)
            end
            if not board.reveal and board.wrong[i] then
                -- mistake found by Check: filled top-right corner
                local s = math.floor(cell / 5)
                for k = 0, s do
                    bb:paintRect(px + cw - pad - s + k, py + pad, s - k, 1, C_BLACK)
                end
            end
        else
            local m = board.notes[i]
            if m ~= 0 then
                local mw, mh = inner / 3, inner / 2
                for d = 1, MAXV do
                    if HAS[m][d] then
                        local mc = (d - 1) % 3
                        local mr = math.floor((d - 1) / 3)
                        centerText(bb, self.note_face, tostring(d),
                            px + pad + math.floor(mc * mw), py + pad + math.floor(mr * mh),
                            math.floor(mw), math.floor(mh), C_NOTE, false)
                    end
                end
            end
        end
        if board.hint_cell == i then
            -- frame around the hint cell
            local t = math.max(2, math.floor(cell / 20))
            bb:paintRect(px + pad, py + pad, inner, t, C_BLACK)
            bb:paintRect(px + pad, py + cw - pad - t, inner, t, C_BLACK)
            bb:paintRect(px + pad, py + pad, t, inner, C_BLACK)
            bb:paintRect(px + cw - pad - t, py + pad, t, inner, C_BLACK)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Game screen
-- ---------------------------------------------------------------------------
local GameScreen = InputContainer:extend{}

function GameScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.note_mode = false
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.status_text = TextWidget:new{
        text = "",
        face = Font:getFace("smallinfofont"),
        max_width = math.floor(Screen:getWidth() * 0.94),
    }
    self.board_widget = BoardWidget:new{
        board = self.board,
        onSelectionChanged = function()
            self:updateStatus()
        end,
    }
    self:buildLayout()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function GameScreen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_WHITE)
    local size = self.layout:getSize()
    self.layout:paintTo(bb, x + math.floor((self.dimen.w - size.w) / 2),
        y + math.floor((self.dimen.h - size.h) / 2))
end

function GameScreen:buildLayout()
    local top = ButtonTable:new{
        width = math.floor(Screen:getWidth() * 0.94),
        shrink_unneeded_width = true,
        buttons = {
            {
                { text = "Nouvelle partie", callback = function() self:openNewGameMenu() end },
                { text = "Règles", callback = function() self:showRules() end },
                { id = "reveal", text = "Solution", callback = function() self:toggleReveal() end },
                { text = "Fermer", callback = function() self:closeScreen() end },
            },
        },
    }
    self.reveal_button = top:getButtonById("reveal")

    local digits = {}
    for d = 1, MAXV do
        digits[#digits + 1] = { text = tostring(d), callback = function() self:onDigit(d) end }
    end
    local keypad = ButtonTable:new{
        width = math.floor(Screen:getWidth() * 0.94),
        shrink_unneeded_width = true,
        buttons = {
            digits,
            {
                { id = "note", text = self:noteText(), callback = function() self:toggleNoteMode() end },
                { text = "Effacer", callback = function() self:onErase() end },
                { text = "Indice", callback = function() self:onHint() end },
                { text = "Vérifier", callback = function() self:onCheck() end },
                { id = "undo", text = "Annuler", callback = function() self:onUndo() end },
            },
        },
    }
    self.note_button = keypad:getButtonById("note")
    self.undo_button = keypad:getButtonById("undo")

    self.layout = VerticalGroup:new{
        align = "center",
        top,
        VerticalSpan:new{ width = Size.span.vertical_large },
        FrameContainer:new{
            padding = Size.padding.default,
            margin = 0,
            bordersize = 0,
            self.board_widget,
        },
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        keypad,
    }
    self[1] = self.layout
    self:updateRevealButton()
    self:updateUndoButton()
    self:updateStatus()
end

function GameScreen:noteText()
    return self.note_mode and "Notes : oui" or "Notes : non"
end

function GameScreen:updateNoteButton()
    if self.note_button then
        self.note_button:setText(self:noteText(), self.note_button.width)
    end
end

function GameScreen:updateUndoButton()
    if self.undo_button then
        self.undo_button:enableDisable(self.board:canUndo())
    end
end

function GameScreen:updateRevealButton()
    if self.reveal_button then
        self.reveal_button:setText(self.board.reveal and "Masquer" or "Solution", self.reveal_button.width)
    end
end

function GameScreen:updateStatus(message)
    local b = self.board
    local text = message
    if not text then
        if b.reveal then
            text = "Solution affichée : la saisie est bloquée."
        elseif b:isSolved() then
            text = "Bravo, grille terminée !"
        else
            text = T("%1×%2 %3  ·  cases vides : %4%5", b.n, b.n,
                DIFFICULTY_LABELS[b.difficulty] or "", b:remaining(),
                self.note_mode and "  ·  mode notes" or "")
        end
    end
    self.status_text:setText(text)
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function GameScreen:afterChange(message)
    self.board_widget:refresh()
    self:updateUndoButton()
    self.plugin:saveState()
    self:updateStatus(message)
end

function GameScreen:toggleNoteMode()
    self.note_mode = not self.note_mode
    self:updateNoteButton()
    self:updateStatus()
end

function GameScreen:onDigit(d)
    local ok, err
    if self.note_mode then
        ok, err = self.board:toggleNote(d)
    else
        ok, err = self.board:setValue(d)
    end
    if not ok then
        if err then
            self:updateStatus(err)
        end
        return
    end
    self:afterChange()
    if not self.note_mode and self.board:isSolved() then
        UIManager:show(InfoMessage:new{ text = "Bravo, grille terminée !", timeout = 4 })
    end
end

function GameScreen:onErase()
    local ok, err = self.board:setValue(nil)
    if not ok then
        self:updateStatus(err)
        return
    end
    self:afterChange()
end

function GameScreen:onUndo()
    local ok, err = self.board:undo()
    if not ok then
        self:updateStatus(err)
        return
    end
    self:afterChange("Coup annulé.")
end

function GameScreen:onCheck()
    if self.board.reveal then
        return
    end
    local any = self.board:markWrong()
    if self.board:isSolved() then
        self:afterChange("Tout est juste !")
    elseif any then
        self:afterChange("Les erreurs sont marquées d'un coin noir.")
    else
        self:afterChange("Aucune erreur pour l'instant, continue !")
    end
end

function GameScreen:onHint()
    local _, message = self.board:hint()
    self.board_widget:refresh()
    self:updateStatus()
    UIManager:show(InfoMessage:new{ text = message, timeout = 5 })
end

function GameScreen:toggleReveal()
    self.board.reveal = not self.board.reveal
    self.board.hint_cell = nil
    self:updateRevealButton()
    self:afterChange()
end

function GameScreen:showRules()
    UIManager:show(InfoMessage:new{ text = RULES_TEXT })
end

function GameScreen:openNewGameMenu()
    local dialog
    local size_row = {}
    for _, n in ipairs(SIZES) do
        size_row[#size_row + 1] = {
            text = T("%1×%2", n, n),
            callback = function()
                UIManager:close(dialog)
                self:openDifficultyMenu(n)
            end,
        }
    end
    dialog = ButtonDialog:new{
        title = "Nouvelle partie : taille de la grille",
        title_align = "center",
        buttons = {
            size_row,
            { { text = "Annuler", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function GameScreen:openDifficultyMenu(n)
    local dialog
    local row = {}
    for _, level in ipairs(DIFFICULTY_ORDER) do
        row[#row + 1] = {
            text = DIFFICULTY_LABELS[level],
            callback = function()
                UIManager:close(dialog)
                self:startNewGame(n, level)
            end,
        }
    end
    dialog = ButtonDialog:new{
        title = T("%1×%2 : difficulté", n, n),
        title_align = "center",
        buttons = {
            row,
            { { text = "Annuler", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function GameScreen:startNewGame(n, level)
    local wait = InfoMessage:new{ text = "Génération de la grille…" }
    UIManager:show(wait)
    UIManager:forceRePaint()
    local ok = self.board:generate(n, level)
    UIManager:close(wait)
    if not ok then
        UIManager:show(InfoMessage:new{ text = "Impossible de générer une grille, réessaie." })
        return
    end
    self.plugin:rememberChoice(n, level)
    self.note_mode = false
    self:updateNoteButton()
    self:updateRevealButton()
    self:afterChange(T("Nouvelle grille %1×%2 %3.", n, n, DIFFICULTY_LABELS[level]))
    UIManager:setDirty(nil, "full")
end

function GameScreen:closeScreen()
    self.plugin:saveState()
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function GameScreen:onClose()
    self:closeScreen()
    return true
end

-- ---------------------------------------------------------------------------
-- Plugin
-- ---------------------------------------------------------------------------
local Suguru = WidgetContainer:extend{
    name = "suguru",
    is_doc_only = false,
}

function Suguru:ensureSettings()
    if not self.settings then
        self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/suguru.lua")
    end
end

function Suguru:init()
    self:ensureSettings()
    self.ui.menu:registerToMainMenu(self)
end

function Suguru:addToMainMenu(menu_items)
    menu_items.suguru = {
        text = "Suguru",
        sorting_hint = "tools",
        callback = function()
            self:showGame()
        end,
    }
end

function Suguru:rememberChoice(n, level)
    self:ensureSettings()
    self.settings:saveSetting("last_size", n)
    self.settings:saveSetting("last_difficulty", level)
end

function Suguru:getBoard()
    if not self.board then
        self:ensureSettings()
        math.randomseed(os.time())
        local board = Board:new()
        local called, loaded = pcall(board.load, board, self.settings:readSetting("state"))
        if not (called and loaded) then
            local n = self.settings:readSetting("last_size") or DEFAULT_SIZE
            local level = self.settings:readSetting("last_difficulty") or DEFAULT_DIFFICULTY
            if not board:generate(n, level) then
                return nil
            end
        end
        self.board = board
    end
    return self.board
end

function Suguru:saveState()
    if not self.board then
        return
    end
    self:ensureSettings()
    self.settings:saveSetting("state", self.board:serialize())
    self.settings:flush()
end

function Suguru:showGame()
    if self.screen then
        return
    end
    local board = self:getBoard()
    if not board then
        UIManager:show(InfoMessage:new{ text = "Impossible de générer une grille." })
        return
    end
    self.screen = GameScreen:new{ board = board, plugin = self }
    UIManager:show(self.screen)
end

function Suguru:onScreenClosed()
    self.screen = nil
end

return Suguru
