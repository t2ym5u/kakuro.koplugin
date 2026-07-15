local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Menu            = require("ui/widget/menu")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase        = require("screen_base")
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

local GAME_RULES_EN = _([[
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

local KakuroScreen = ScreenBase:extend{ note_mode = false }

function KakuroScreen:init()
    local state = self.plugin:loadState()
    self.board  = KakuroBoard:new()
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end
    ScreenBase.init(self)
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

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Kakuro"), function()
        return {
            { text = _("New game"),                  callback = function() self:onNewGame() end },
            { text = self:getDifficultyButtonText(), callback = function() self:openDifficultyMenu() end },
            { text = self.board:isShowingSolution() and _("Hide result") or _("Show result"),
              callback = function() self:toggleSolution() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

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
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            keypad,
        }
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, content, keypad)
    end
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
        self:showMessage(_("Congratulations! Puzzle solved!"), 4)
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

return KakuroScreen
