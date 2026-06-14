local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local Menu            = require("ui/widget/menu")
local Size            = require("ui/size")
local TextWidget      = require("ui/widget/textwidget")
local TextViewer      = require("ui/widget/textviewer")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local KakuroBoard       = lrequire("board")
local KakuroBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

local DIFFICULTY_ORDER  = { "easy", "medium", "hard" }
local DIFFICULTY_LABELS = {
    easy   = _("Easy"),
    medium = _("Medium"),
    hard   = _("Hard"),
}

-- ---------------------------------------------------------------------------
-- KakuroScreen
-- ---------------------------------------------------------------------------

local GAME_RULES = _([[
Kakuro — Rules

Fill the white cells with digits 1–9 so that each "run" sums to its clue value.

Rules:
• Across runs fill cells going right; down runs fill cells going down.
• Each run's digits must sum exactly to the clue shown in the adjacent black triangle.
• No digit may be repeated within a single run.
• Black cells are walls; clue cells show the across clue (bottom-left triangle) and the down clue (top-right triangle).

Tap a white cell to select it, then tap a digit button to enter a value.
]])

local GAME_RULES_FR = [[
Kakuro — Règles

Remplissez les cases blanches avec des chiffres de 1 à 9 de sorte que chaque "séquence" soit égale à son indice.

Règles :
• Une séquence "horizontale" remplit des cases vers la droite ; une séquence "verticale" remplit des cases vers le bas.
• Les chiffres d'une séquence doivent sommer exactement à la valeur de l'indice dans le triangle noir adjacent.
• Un chiffre ne peut pas être répété au sein d'une même séquence.
• Les cases noires sont des murs ; les cases indices affichent l'indice horizontal (triangle bas-gauche) et l'indice vertical (triangle haut-droit).

Appuyez sur une case blanche pour la sélectionner, puis sur un bouton chiffre pour entrer une valeur.
]]

local function showRules()
    local lang = (G_reader_settings and G_reader_settings:readSetting("language") or "en"):sub(1, 2)
    local text = (lang == "fr") and GAME_RULES_FR or GAME_RULES
    UIManager:show(TextViewer:new{
        title  = _("Rules"),
        text   = text,
        width  = math.floor(DeviceScreen:getWidth() * 0.9),
        height = math.floor(DeviceScreen:getHeight() * 0.9),
    })
end

local KakuroScreen = InputContainer:extend{}

function KakuroScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = DeviceScreen:getWidth(), h = DeviceScreen:getHeight() }
    self.covers_fullscreen = true
    self.vertical_align    = "center"
    self.note_mode         = false

    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end

    self.status_text = TextWidget:new{
        text = _("Tap a white cell, then pick a digit."),
        face = Font:getFace("smallinfofont"),
    }

    local state = self.plugin:loadState()
    self.board  = KakuroBoard:new()
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end

    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function KakuroScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local content_size = self.layout:getSize()
    local offset_x     = x + math.floor((self.dimen.w - content_size.w) / 2)
    local offset_y     = y
    if self.vertical_align == "center" then
        offset_y = offset_y + math.floor((self.dimen.h - content_size.h) / 2)
    end
    self.layout:paintTo(bb, offset_x, offset_y)
end

function KakuroScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function KakuroScreen:buildLayout()
    self.board_widget = KakuroBoardWidget:new{
        board          = self.board,
        onCellSelected = function(r, c)
            self:onCellSelected(r, c)
        end,
    }

    local is_landscape = DeviceScreen:getWidth() > DeviceScreen:getHeight()
    local sw           = DeviceScreen:getWidth()

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size  = self.board_widget.size + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_frame_size - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)
    local keypad_width = is_landscape and button_width or math.floor(sw * 0.75)

    -- Top bar
    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {
            {
                { text = _("New game"),   callback = function() self:onNewGame() end },
                { id = "diff_button",     text = self:getDifficultyButtonText(),
                  callback = function() self:openDifficultyMenu() end },
                { id = "show_result",     text = _("Show result"),
                  callback = function() self:toggleSolution() end },
                { text = _("Rules"),  callback = showRules },
                { text = _("Close"),      callback = function() self:onClose() end },
            },
        },
    }
    self.show_result_button = top_buttons:getButtonById("show_result")
    self.diff_button        = top_buttons:getButtonById("diff_button")

    -- Digit keypad (3×3) + action row
    local keypad_rows = {}
    for row = 0, 2 do
        local row_btns = {}
        for col = 1, 3 do
            local d = row * 3 + col
            row_btns[#row_btns + 1] = {
                id       = "digit_" .. d,
                text     = tostring(d),
                callback = function() self:onDigit(d) end,
            }
        end
        keypad_rows[#keypad_rows + 1] = row_btns
    end
    keypad_rows[#keypad_rows + 1] = {
        { id = "note_button", text = self:getNoteButtonText(),
          callback = function() self:toggleNoteMode() end },
        { text = _("Erase"),  callback = function() self:onErase() end },
        { text = _("Check"),  callback = function() self:onCheck() end },
        { id = "undo_button", text = _("Undo"),
          callback = function() self:onUndo() end },
    }
    local keypad = ButtonTable:new{
        width                 = keypad_width,
        shrink_unneeded_width = true,
        buttons               = keypad_rows,
    }
    self.note_button = keypad:getButtonById("note_button")
    self.undo_button = keypad:getButtonById("undo_button")
    self.digit_buttons = {}
    for d = 1, 9 do
        self.digit_buttons[d] = keypad:getButtonById("digit_" .. d)
    end

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            keypad,
        }
        self.layout = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            keypad,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:_ensureShowButtonState()
    self:updateUndoButton()
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function KakuroScreen:onCellSelected(r, c)
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

-- ---------------------------------------------------------------------------
-- Digit / note / erase
-- ---------------------------------------------------------------------------

function KakuroScreen:onDigit(d)
    if self.note_mode then
        local ok, err = self.board:toggleNote(d)
        if not ok then self:updateStatus(err) ; return end
        self.board_widget:refresh()
        self:updateStatus()
        self.plugin:saveState(self.board:serialize())
        self:updateUndoButton()
        return
    end
    local ok, err = self.board:setValue(d)
    if not ok then self:updateStatus(err) ; return end
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
    if self.board:isSolved() then
        UIManager:show(InfoMessage:new{ text = _("Congratulations! Puzzle solved!"), timeout = 4 })
    end
end

function KakuroScreen:onErase()
    local ok, err = self.board:setValue(0)
    if not ok then self:updateStatus(err) ; return end
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
end

-- ---------------------------------------------------------------------------
-- Note mode
-- ---------------------------------------------------------------------------

function KakuroScreen:getNoteButtonText()
    return self.note_mode and _("Note: On") or _("Note: Off")
end

function KakuroScreen:toggleNoteMode()
    self.note_mode = not self.note_mode
    self:updateNoteButton()
    self:updateStatus(self.note_mode and _("Note mode enabled.") or _("Note mode disabled."))
end

function KakuroScreen:updateNoteButton()
    if not self.note_button then return end
    self.note_button:setText(self:getNoteButtonText(), self.note_button.width)
end

-- ---------------------------------------------------------------------------
-- Check / undo
-- ---------------------------------------------------------------------------

function KakuroScreen:onCheck()
    self.board:checkConflicts()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    local remaining = self.board:getRemainingCells()
    if self.board:isSolved() then
        self:updateStatus(_("Everything looks good!"))
    elseif remaining == 0 then
        self:updateStatus(_("There are mistakes highlighted."))
    else
        self:updateStatus(_("Keep going!"))
    end
end

function KakuroScreen:onUndo()
    local ok, err = self.board:undo()
    if not ok then self:updateStatus(err) ; return end
    self.board_widget:refresh()
    self:updateStatus(_("Last move undone."))
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
end

function KakuroScreen:updateUndoButton()
    if not self.undo_button then return end
    self.undo_button:enableDisable(self.board:canUndo())
end

-- ---------------------------------------------------------------------------
-- New game / difficulty
-- ---------------------------------------------------------------------------

function KakuroScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:_ensureShowButtonState()
    self:updateUndoButton()
    self:updateStatus(T(_("New %1 game started."), DIFFICULTY_LABELS[diff] or diff))
end

function KakuroScreen:getDifficultyButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

function KakuroScreen:openDifficultyMenu()
    local menu_ref
    local function selectDiff(id)
        if menu_ref then UIManager:close(menu_ref) end
        self.plugin:saveSetting("difficulty", id)
        if self.diff_button then
            self.diff_button:setText(self:getDifficultyButtonText(), self.diff_button.width)
        end
        self:onNewGame()
    end

    local items = {}
    local current = self.plugin:getSetting("difficulty", "easy")
    for _, id in ipairs(DIFFICULTY_ORDER) do
        local did = id
        items[#items + 1] = {
            text     = DIFFICULTY_LABELS[id] or id,
            checked  = (id == current),
            callback = function() return selectDiff(did) end,
        }
    end
    menu_ref = Menu:new{
        title                  = _("Select difficulty"),
        item_table             = items,
        width                  = math.floor(DeviceScreen:getWidth()  * 0.7),
        height                 = math.floor(DeviceScreen:getHeight() * 0.9),
        disable_footer_padding = true,
        show_parent            = self,
    }
    UIManager:show(menu_ref)
end

-- ---------------------------------------------------------------------------
-- Show / hide solution
-- ---------------------------------------------------------------------------

function KakuroScreen:toggleSolution()
    self.board:toggleSolution()
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:_ensureShowButtonState()
    self:updateStatus(self.board:isShowingSolution() and _("Showing the solution.") or nil)
end

function KakuroScreen:_ensureShowButtonState()
    if not self.show_result_button then return end
    local text = self.board:isShowingSolution() and _("Hide result") or _("Show result")
    self.show_result_button:setText(text, self.show_result_button.width)
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function KakuroScreen:updateStatus(message)
    local status
    if message then
        status = message
    elseif self.board:isSolved() then
        status = _("Congratulations! Puzzle solved.")
    elseif self.board:isShowingSolution() then
        status = _("Showing solution. Editing disabled.")
    else
        local remaining = self.board:getRemainingCells()
        local sel_r, sel_c = self.board:getSelected()
        if sel_r then
            local info_a = self.board:getRunInfo(sel_r, sel_c, "a")
            local info_d = self.board:getRunInfo(sel_r, sel_c, "d")
            local parts  = {}
            if info_a and info_a.sum_needed > 0 then
                parts[#parts + 1] = T(_("Across: %1 (have %2)"), info_a.sum_needed, info_a.current_sum)
            end
            if info_d and info_d.sum_needed > 0 then
                parts[#parts + 1] = T(_("Down: %1 (have %2)"), info_d.sum_needed, info_d.current_sum)
            end
            if #parts > 0 then
                status = table.concat(parts, "  ·  ") .. T(_("  ·  Empty: %1"), remaining)
            else
                status = T(_("Empty cells: %1"), remaining)
            end
        else
            status = T(_("Empty cells: %1"), remaining)
        end
        if self.note_mode then
            status = (status or "") .. "\n" .. _("Note mode is ON.")
        end
    end
    self.status_text:setText(status or "")
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Close
-- ---------------------------------------------------------------------------

function KakuroScreen:onClose()
    self.plugin:saveState(self.board:serialize())
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

return KakuroScreen
