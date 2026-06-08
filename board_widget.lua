local Blitbuffer    = require("ffi/blitbuffer")
local Device        = require("device")
local Font          = require("ui/font")
local GestureRange  = require("ui/gesturerange")
local Geom          = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText    = require("ui/rendertext")
local UIManager     = require("ui/uimanager")

local Screen = Device.screen

local function drawLine(bb, x, y, w, h, color)
    bb:paintRect(x, y, w, h, color or Blitbuffer.COLOR_BLACK)
end

local function drawDiagonalLine(bb, x, y, length, dx, dy, color, thickness)
    color     = color     or Blitbuffer.COLOR_BLACK
    thickness = thickness or 1
    length    = math.max(0, length)
    for step = 0, length do
        local px = math.floor(x + dx * step)
        local py = math.floor(y + dy * step)
        bb:paintRect(px, py, thickness, thickness, color)
    end
end

-- ---------------------------------------------------------------------------
-- KakuroBoardWidget
-- ---------------------------------------------------------------------------

local KakuroBoardWidget = InputContainer:extend{
    board          = nil,
    onCellSelected = nil,
    size_ratio     = 0.82,
}

function KakuroBoardWidget:init()
    local board    = self.board
    local n_rows   = board.n_rows
    local n_cols   = board.n_cols
    self.n_rows    = n_rows
    self.n_cols    = n_cols

    local min_dim  = math.min(Screen:getWidth(), Screen:getHeight())
    local size     = math.floor(min_dim * (self.size_ratio or 0.82))
    self.size      = size
    self.cell_w    = size / n_cols
    self.cell_h    = size / n_rows
    self.dimen     = Geom:new{ w = size, h = size }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = size, h = size }

    -- Main digit font (for white cells)
    local cell_min = math.min(self.cell_w, self.cell_h)
    local num_size = math.max(10, math.floor(cell_min * 0.55))
    do
        local padding = math.max(2, math.floor(cell_min / 9))
        local max_wh  = math.max(1, math.floor(cell_min - 2 * padding))
        while num_size > 10 do
            local face = Font:getFace("cfont", num_size)
            local m    = RenderText:sizeUtf8Text(0, max_wh, face, "8", true, false)
            local h    = m.y_bottom - m.y_top
            if m.x <= max_wh and h <= max_wh then
                num_size = math.max(10, num_size - 2)
                break
            end
            num_size = num_size - 1
        end
    end
    self.number_face    = Font:getFace("cfont", num_size)
    self.number_padding = math.max(2, math.floor(cell_min / 9))

    -- Note font (for candidate marks — 3×3 mini grid inside white cell)
    local mini     = cell_min / 3
    local note_size = math.max(8, math.floor(mini * 0.6))
    do
        local padding = math.max(1, math.floor(mini / 8))
        local max_wh  = math.max(1, math.floor(mini - 2 * padding))
        while note_size > 8 do
            local face = Font:getFace("smallinfofont", note_size)
            local m    = RenderText:sizeUtf8Text(0, max_wh, face, "8", true, false)
            local h    = m.y_bottom - m.y_top
            if m.x <= max_wh and h <= max_wh then
                note_size = math.max(8, note_size - 1)
                break
            end
            note_size = note_size - 1
        end
    end
    self.note_face    = Font:getFace("smallinfofont", note_size)
    self.note_padding = math.max(1, math.floor(mini / 8))

    -- Clue font (for numbers in triangular clue areas)
    local clue_size = math.max(8, math.floor(cell_min * 0.28))
    self.clue_face  = Font:getFace("smallinfofont", clue_size)

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            }
        },
    }
end

function KakuroBoardWidget:getCellFromPoint(x, y)
    local rect    = self.paint_rect
    local local_x = x - rect.x
    local local_y = y - rect.y
    if local_x < 0 or local_y < 0 or local_x > rect.w or local_y > rect.h then
        return nil
    end
    local col = math.min(self.n_cols, math.floor(local_x / self.cell_w) + 1)
    local row = math.min(self.n_rows, math.floor(local_y / self.cell_h) + 1)
    if row < 1 or col < 1 then return nil end
    return row, col
end

function KakuroBoardWidget:onTap(_, ges)
    if not (self.board and ges and ges.pos) then return false end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then return false end
    if self.board:isWhite(row, col) then
        self.board:setSelected(row, col)
        if self.onCellSelected then
            self.onCellSelected(row, col)
        end
        self:refresh()
    end
    return true
end

function KakuroBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

function KakuroBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board   = self.board
    local n_rows  = self.n_rows
    local n_cols  = self.n_cols
    local cell_w  = self.cell_w
    local cell_h  = self.cell_h

    -- White background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)

    -- Determine selected cell and its runs for highlight
    local sel_r, sel_c = board:getSelected()
    local run_a_cells  = {}
    local run_d_cells  = {}
    if sel_r then
        local ra = board:getAcrossRun(sel_r, sel_c)
        local rd = board:getDownRun(sel_r, sel_c)
        if ra then
            for _, cell in ipairs(ra.cells) do
                run_a_cells[cell.r .. "," .. cell.c] = true
            end
        end
        if rd then
            for _, cell in ipairs(rd.cells) do
                run_d_cells[cell.r .. "," .. cell.c] = true
            end
        end
    end

    local RUN_TINT    = Blitbuffer.COLOR_GRAY_D
    local SEL_COLOR   = Blitbuffer.COLOR_GRAY
    local WRONG_COLOR = Blitbuffer.COLOR_GRAY

    -- Draw cells
    for r = 1, n_rows do
        for c = 1, n_cols do
            local cx = x + math.floor((c - 1) * cell_w)
            local cy = y + math.floor((r - 1) * cell_h)
            local cw = math.ceil(cell_w)
            local ch = math.ceil(cell_h)
            local cell = board:getCell(r, c)
            local key  = r .. "," .. c

            if cell.type == "black" then
                bb:paintRect(cx, cy, cw, ch, Blitbuffer.COLOR_BLACK)

            elseif cell.type == "clue" then
                -- Black fill
                bb:paintRect(cx, cy, cw, ch, Blitbuffer.COLOR_BLACK)
                -- Diagonal line (top-left to bottom-right) divides: top-right = down, bottom-left = across
                local diag_len = math.floor(math.sqrt(cw * cw + ch * ch))
                local dx = cw / diag_len
                local dy = ch / diag_len
                local thickness = math.max(1, math.floor(math.min(cw, ch) / 18))
                drawDiagonalLine(bb, cx, cy, diag_len, dx, dy, Blitbuffer.COLOR_WHITE, thickness)

                -- Down clue: top-right triangle
                if cell.down and cell.down > 0 then
                    local text = tostring(cell.down)
                    local tri_w = math.floor(cw / 2)
                    local tri_h = math.floor(ch / 2)
                    local m    = RenderText:sizeUtf8Text(0, tri_w, self.clue_face, text, true, false)
                    local tw   = m.x
                    local th   = m.y_bottom - m.y_top
                    local pad  = math.max(1, math.floor(math.min(cw, ch) / 14))
                    local tx   = cx + cw - tw - pad
                    local ty   = cy + pad - m.y_top
                    RenderText:renderUtf8Text(bb, tx, ty, self.clue_face, text, true, false, Blitbuffer.COLOR_WHITE)
                end
                -- Across clue: bottom-left triangle
                if cell.across and cell.across > 0 then
                    local text = tostring(cell.across)
                    local tri_w = math.floor(cw / 2)
                    local pad  = math.max(1, math.floor(math.min(cw, ch) / 14))
                    local m    = RenderText:sizeUtf8Text(0, tri_w, self.clue_face, text, true, false)
                    local th   = m.y_bottom - m.y_top
                    local tx   = cx + pad
                    local ty   = cy + ch - th - pad - m.y_top
                    RenderText:renderUtf8Text(bb, tx, ty, self.clue_face, text, true, false, Blitbuffer.COLOR_WHITE)
                end

            elseif cell.type == "white" then
                -- Background
                if sel_r and sel_r == r and sel_c == c then
                    bb:paintRect(cx, cy, cw, ch, SEL_COLOR)
                elseif run_a_cells[key] or run_d_cells[key] then
                    bb:paintRect(cx, cy, cw, ch, RUN_TINT)
                end
                -- Wrong mark overlay
                if board.wrong_marks[r][c] then
                    bb:paintRect(cx, cy, cw, ch, WRONG_COLOR)
                end

                -- Value or notes
                local disp_value = nil
                local disp_color = Blitbuffer.COLOR_BLACK
                if board:isShowingSolution() then
                    disp_value = board.solution[r][c]
                    disp_color = Blitbuffer.COLOR_GRAY_4
                else
                    local v = board.user[r][c]
                    if v and v > 0 then
                        disp_value = v
                        disp_color = board.wrong_marks[r][c] and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_2
                    end
                end

                if disp_value and disp_value > 0 then
                    local text    = tostring(disp_value)
                    local padding = self.number_padding
                    local inner   = math.max(1, math.floor(math.min(cw, ch) - 2 * padding))
                    local m       = RenderText:sizeUtf8Text(0, inner, self.number_face, text, true, false)
                    local tw      = m.x
                    local th      = m.y_bottom - m.y_top
                    local tx      = cx + padding + math.floor((inner - tw) / 2)
                    local ty      = cy + padding + math.floor((inner - th) / 2) - m.y_top
                    RenderText:renderUtf8Text(bb, tx, ty, self.number_face, text, true, false, disp_color)
                    if board.wrong_marks[r][c] then
                        local pad2      = math.max(1, math.floor(math.min(cw, ch) / 12))
                        local diag_len2 = math.max(0, math.floor(math.min(cw, ch) - pad2 * 2))
                        local thick2    = math.max(2, math.floor(math.min(cw, ch) / 18))
                        drawDiagonalLine(bb, cx + pad2, cy + pad2,             diag_len2, 1,  1, Blitbuffer.COLOR_BLACK, thick2)
                        drawDiagonalLine(bb, cx + pad2, cy + ch - pad2, diag_len2, 1, -1, Blitbuffer.COLOR_BLACK, thick2)
                    end
                else
                    -- Notes (3×3 mini grid)
                    local notes = board.notes[r][c]
                    if notes then
                        local mini_w = cw / 3
                        local mini_h = ch / 3
                        local np     = self.note_padding
                        for d = 1, 9 do
                            if notes[d] then
                                local mc  = (d - 1) % 3
                                local mr  = math.floor((d - 1) / 3)
                                local mx  = cx + mc * mini_w
                                local my  = cy + mr * mini_h
                                local mw  = math.ceil(mini_w)
                                local mh  = math.ceil(mini_h)
                                local txt = tostring(d)
                                local m   = RenderText:sizeUtf8Text(0, mw - 2 * np, self.note_face, txt, true, false)
                                local tw2 = m.x
                                local th2 = m.y_bottom - m.y_top
                                local tx2 = mx + np + math.floor((mw - 2 * np - tw2) / 2)
                                local ty2 = my + np + math.floor((mh - 2 * np - th2) / 2) - m.y_top
                                RenderText:renderUtf8Text(bb, tx2, ty2, self.note_face, txt, true, false, Blitbuffer.COLOR_GRAY_4)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Grid lines
    local border = math.max(2, math.floor(math.min(cell_w, cell_h) / 12))
    local thin   = math.max(1, math.floor(border / 2))

    for ci = 0, n_cols do
        local lx = x + math.floor(ci * cell_w)
        local thick = (ci == 0 or ci == n_cols) and border or thin
        drawLine(bb, lx, y, thick, self.dimen.h, Blitbuffer.COLOR_BLACK)
    end
    for ri = 0, n_rows do
        local ly    = y + math.floor(ri * cell_h)
        local thick = (ri == 0 or ri == n_rows) and border or thin
        drawLine(bb, x, ly, self.dimen.w, thick, Blitbuffer.COLOR_BLACK)
    end
end

return KakuroBoardWidget
