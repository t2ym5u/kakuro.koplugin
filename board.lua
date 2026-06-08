local UndoStack = require("undo_stack")
local _         = require("gettext")

-- ---------------------------------------------------------------------------
-- Generator: build a valid Kakuro board from a template + backtracking
-- ---------------------------------------------------------------------------

-- Templates: layout[r][c]: 0=black, 1=white, 2=clue-slot
-- The generator sanitises each template at runtime, removing white cells that
-- lack a valid clue position or belong to a run of length < 2.

-- Template design principles:
--  * Every column of whites has a 2-cell immediately above the topmost white.
--  * Every row-run of whites has a 2-cell immediately to the left of the first white.
--  * Every run has length >= 2.
--  * The runtime sanitiser handles any remaining edge cases.

local TEMPLATES = {
    -- Easy: two independent 2-column groups (C2-C3 and C5-C6), 4 rows each
    -- Clue cells in column 1 and 4 provide across clues; row 1 provides down clues.
    easy = {
        n_rows = 6, n_cols = 7,
        layout = {
            {0, 2, 2, 0, 2, 2, 0},  -- down-clue row
            {2, 1, 1, 2, 1, 1, 0},  -- across run [c2,c3], [c5,c6]
            {2, 1, 1, 2, 1, 1, 0},
            {2, 1, 1, 2, 1, 1, 0},
            {2, 1, 1, 2, 1, 1, 0},
            {0, 2, 2, 0, 2, 2, 0},  -- footer (no whites)
        },
    },
    -- Medium: 3-column group plus 2-column group, 4 rows
    medium = {
        n_rows = 7, n_cols = 8,
        layout = {
            {0, 2, 2, 2, 0, 2, 2, 0},
            {2, 1, 1, 1, 2, 1, 1, 0},
            {2, 1, 1, 1, 2, 1, 1, 0},
            {2, 1, 1, 1, 2, 1, 1, 0},
            {2, 1, 1, 1, 2, 1, 1, 0},
            {2, 1, 1, 1, 2, 1, 1, 0},
            {0, 2, 2, 2, 0, 2, 2, 0},
        },
    },
    -- Hard: one 4-column group and one 3-column group, 5 rows each
    hard = {
        n_rows = 7, n_cols = 9,
        layout = {
            {0, 2, 2, 2, 2, 0, 2, 2, 2},
            {2, 1, 1, 1, 1, 2, 1, 1, 1},
            {2, 1, 1, 1, 1, 2, 1, 1, 1},
            {2, 1, 1, 1, 1, 2, 1, 1, 1},
            {2, 1, 1, 1, 1, 2, 1, 1, 1},
            {2, 1, 1, 1, 1, 2, 1, 1, 1},
            {0, 2, 2, 2, 2, 0, 2, 2, 2},
        },
    },
}

-- Get across and down runs from a layout
local function getRuns(layout, n_rows, n_cols, dir)
    local runs = {}
    if dir == "across" then
        for r = 1, n_rows do
            local c = 1
            while c <= n_cols do
                if layout[r][c] == 1 then
                    local cells = {}
                    local sc    = c
                    while c <= n_cols and layout[r][c] == 1 do
                        cells[#cells + 1] = {r = r, c = c}
                        c = c + 1
                    end
                    if #cells >= 2 then
                        runs[#runs + 1] = {cells = cells, clue_r = r, clue_c = sc - 1}
                    end
                else
                    c = c + 1
                end
            end
        end
    else
        for c = 1, n_cols do
            local r = 1
            while r <= n_rows do
                if layout[r][c] == 1 then
                    local cells = {}
                    local sr    = r
                    while r <= n_rows and layout[r][c] == 1 do
                        cells[#cells + 1] = {r = r, c = c}
                        r = r + 1
                    end
                    if #cells >= 2 then
                        runs[#runs + 1] = {cells = cells, clue_r = sr - 1, clue_c = c}
                    end
                else
                    r = r + 1
                end
            end
        end
    end
    return runs
end

-- Min/max achievable sum for a run of length L with digits 1-9, no repeats
local function minSum(len) return len * (len + 1) / 2 end
local function maxSum(len) return len * (19 - len) / 2 end

-- Backtracking solver: fill sol grid (white cells start at -1) satisfying all runs
local function solveGrid(sol, across_runs, down_runs, n_rows, n_cols)
    local cell_across = {}
    local cell_down   = {}
    for r = 1, n_rows do
        cell_across[r] = {}
        cell_down[r]   = {}
    end
    for i, run in ipairs(across_runs) do
        for _, cell in ipairs(run.cells) do cell_across[cell.r][cell.c] = i end
    end
    for i, run in ipairs(down_runs) do
        for _, cell in ipairs(run.cells) do cell_down[cell.r][cell.c] = i end
    end

    local white_cells = {}
    for r = 1, n_rows do
        for c = 1, n_cols do
            if sol[r][c] == -1 then white_cells[#white_cells + 1] = {r = r, c = c} end
        end
    end

    local function curSumRem(run)
        local s, rem = 0, 0
        for _, cell in ipairs(run.cells) do
            local v = sol[cell.r][cell.c]
            if v > 0 then s = s + v elseif v == -1 then rem = rem + 1 end
        end
        return s, rem
    end

    local function used(run)
        local u = {}
        for _, cell in ipairs(run.cells) do
            local v = sol[cell.r][cell.c]
            if v > 0 then u[v] = true end
        end
        return u
    end

    local function bt(idx)
        if idx > #white_cells then return true end
        local r, c = white_cells[idx].r, white_cells[idx].c
        local ai   = cell_across[r][c]
        local di   = cell_down[r][c]
        local arun = ai and across_runs[ai]
        local drun = di and down_runs[di]
        local ua   = arun and used(arun) or {}
        local ud   = drun and used(drun) or {}

        local digits = {1, 2, 3, 4, 5, 6, 7, 8, 9}
        for i = #digits, 2, -1 do
            local j = math.random(i)
            digits[i], digits[j] = digits[j], digits[i]
        end

        for _, d in ipairs(digits) do
            if not ua[d] and not ud[d] then
                sol[r][c] = d
                local ok  = true

                if arun then
                    local s, rem = curSumRem(arun)
                    ok = rem == 0 and s == arun.target or rem > 0 and s < arun.target and arun.target - s >= rem
                end
                if ok and drun then
                    local s, rem = curSumRem(drun)
                    ok = rem == 0 and s == drun.target or rem > 0 and s < drun.target and drun.target - s >= rem
                end

                if ok and bt(idx + 1) then return true end
                sol[r][c] = -1
            end
        end
        return false
    end

    return bt(1)
end

local function generateFromTemplate(tmpl)
    local n_rows = tmpl.n_rows
    local n_cols = tmpl.n_cols
    local layout = tmpl.layout

    -- Make a mutable copy of the layout so we can sanitise it
    local grid = {}
    for r = 1, n_rows do
        grid[r] = {}
        for c = 1, n_cols do grid[r][c] = layout[r][c] end
    end

    -- Pass 1: remove white cells that lack a valid clue cell
    -- A white cell at (r,c) needs:
    --   - the leftmost cell of its row-run to have layout[r][start-1] == 2
    --   - the topmost cell of its col-run  to have layout[start-1][c]  == 2
    -- If not, blacken those white cells.
    local changed = true
    while changed do
        changed = false
        for r = 1, n_rows do
            for c = 1, n_cols do
                if grid[r][c] == 1 then
                    -- Find start of across run
                    local sc = c
                    while sc > 1 and grid[r][sc-1] == 1 do sc = sc - 1 end
                    local across_ok = sc > 1 and grid[r][sc-1] == 2

                    -- Find start of down run
                    local sr = r
                    while sr > 1 and grid[sr-1][c] == 1 do sr = sr - 1 end
                    local down_ok = sr > 1 and grid[sr-1][c] == 2

                    if not across_ok or not down_ok then
                        grid[r][c] = 0
                        changed    = true
                    end
                end
            end
        end
    end

    -- Pass 2: remove runs of length 1 (isolated white cells)
    changed = true
    while changed do
        changed = false
        for r = 1, n_rows do
            for c = 1, n_cols do
                if grid[r][c] == 1 then
                    -- Check across run length
                    local sc = c
                    while sc > 1 and grid[r][sc-1] == 1 do sc = sc - 1 end
                    local ec = c
                    while ec < n_cols and grid[r][ec+1] == 1 do ec = ec + 1 end
                    local across_len = ec - sc + 1

                    local sr = r
                    while sr > 1 and grid[sr-1][c] == 1 do sr = sr - 1 end
                    local er = r
                    while er < n_rows and grid[er+1][c] == 1 do er = er + 1 end
                    local down_len = er - sr + 1

                    if across_len < 2 or down_len < 2 then
                        grid[r][c] = 0
                        changed    = true
                    end
                end
            end
        end
    end

    local across_runs = getRuns(grid, n_rows, n_cols, "across")
    local down_runs   = getRuns(grid, n_rows, n_cols, "down")
    if #across_runs < 2 or #down_runs < 2 then return nil end

    -- Verify every run's clue position is a 2-cell
    for _, run in ipairs(across_runs) do
        if grid[run.clue_r][run.clue_c] ~= 2 then return nil end
    end
    for _, run in ipairs(down_runs) do
        if grid[run.clue_r][run.clue_c] ~= 2 then return nil end
    end

    -- Verify every white cell is in both an across and a down run
    local in_across = {}
    local in_down   = {}
    for r = 1, n_rows do in_across[r] = {}; in_down[r] = {} end
    for _, run in ipairs(across_runs) do
        for _, cell in ipairs(run.cells) do in_across[cell.r][cell.c] = true end
    end
    for _, run in ipairs(down_runs) do
        for _, cell in ipairs(run.cells) do in_down[cell.r][cell.c] = true end
    end
    for r = 1, n_rows do
        for c = 1, n_cols do
            if grid[r][c] == 1 then
                if not in_across[r][c] or not in_down[r][c] then return nil end
            end
        end
    end

    for _, run in ipairs(across_runs) do
        local lo = minSum(#run.cells)
        local hi = maxSum(#run.cells)
        run.target = lo + math.random(0, hi - lo)
    end
    for _, run in ipairs(down_runs) do
        local lo = minSum(#run.cells)
        local hi = maxSum(#run.cells)
        run.target = lo + math.random(0, hi - lo)
    end

    local sol = {}
    for r = 1, n_rows do
        sol[r] = {}
        for c = 1, n_cols do
            sol[r][c] = grid[r][c] == 1 and -1 or 0
        end
    end

    if not solveGrid(sol, across_runs, down_runs, n_rows, n_cols) then return nil end

    for r = 1, n_rows do
        for c = 1, n_cols do
            if sol[r][c] == -1 then sol[r][c] = 0 end
        end
    end

    local acl = {}
    local dcl = {}
    for r = 1, n_rows do
        acl[r] = {}
        dcl[r] = {}
        for c = 1, n_cols do acl[r][c] = 0; dcl[r][c] = 0 end
    end
    for _, run in ipairs(across_runs) do
        local s = 0
        for _, cell in ipairs(run.cells) do s = s + sol[cell.r][cell.c] end
        acl[run.clue_r][run.clue_c] = s
    end
    for _, run in ipairs(down_runs) do
        local s = 0
        for _, cell in ipairs(run.cells) do s = s + sol[cell.r][cell.c] end
        dcl[run.clue_r][run.clue_c] = s
    end

    local cells = {}
    for r = 1, n_rows do
        for c = 1, n_cols do
            local v = grid[r][c]
            if v == 1 then
                cells[#cells + 1] = {r=r, c=c, t="W"}
            elseif v == 2 then
                cells[#cells + 1] = {r=r, c=c, t="C", a=acl[r][c], d=dcl[r][c]}
            else
                cells[#cells + 1] = {r=r, c=c, t="B"}
            end
        end
    end

    return {n_rows = n_rows, n_cols = n_cols, cells = cells, solution = sol}
end

-- ---------------------------------------------------------------------------
-- Emergency fallback puzzle (tiny 5×5, always valid)
-- Layout:
--   B  B  B  B  B
--   B  B  C  C  B
--   B  C  W  W  B
--   B  C  W  W  B
--   B  B  B  B  B
-- Across: R3=[1,2]=3, R4=[3,4]=7
-- Down:   C3=[1,3]=4, C4=[2,4]=6
-- ---------------------------------------------------------------------------
local EMERGENCY_PUZZLE = (function()
    local n   = 5
    local sol = {
        {0,0,0,0,0},
        {0,0,0,0,0},
        {0,0,1,2,0},
        {0,0,3,4,0},
        {0,0,0,0,0},
    }
    local cells = {
        {r=1,c=1,t="B"},{r=1,c=2,t="B"},{r=1,c=3,t="B"},{r=1,c=4,t="B"},{r=1,c=5,t="B"},
        {r=2,c=1,t="B"},{r=2,c=2,t="B"},{r=2,c=3,t="C",a=0,d=4},{r=2,c=4,t="C",a=0,d=6},{r=2,c=5,t="B"},
        {r=3,c=1,t="B"},{r=3,c=2,t="C",a=3,d=0},{r=3,c=3,t="W"},{r=3,c=4,t="W"},{r=3,c=5,t="B"},
        {r=4,c=1,t="B"},{r=4,c=2,t="C",a=7,d=0},{r=4,c=3,t="W"},{r=4,c=4,t="W"},{r=4,c=5,t="B"},
        {r=5,c=1,t="B"},{r=5,c=2,t="B"},{r=5,c=3,t="B"},{r=5,c=4,t="B"},{r=5,c=5,t="B"},
    }
    return {n_rows=n, n_cols=n, cells=cells, solution=sol}
end)()

-- ---------------------------------------------------------------------------
-- KakuroBoard
-- ---------------------------------------------------------------------------

local KakuroBoard = {}
KakuroBoard.__index = KakuroBoard

function KakuroBoard:new(opts)
    opts = opts or {}
    local board = setmetatable({}, self)
    board.n_rows        = 5
    board.n_cols        = 5
    board.grid          = {}
    board.user          = {}
    board.notes         = {}
    board.solution      = {}
    board.wrong_marks   = {}
    board.selected      = nil
    board.undo          = UndoStack:new{ max_size = 200 }
    board.show_solution = false
    board.difficulty    = opts.difficulty or "easy"
    return board
end

function KakuroBoard:_buildFromData(data)
    self.n_rows      = data.n_rows
    self.n_cols      = data.n_cols
    self.grid        = {}
    self.solution    = {}
    self.user        = {}
    self.notes       = {}
    self.wrong_marks = {}

    for r = 1, self.n_rows do
        self.grid[r]        = {}
        self.solution[r]    = {}
        self.user[r]        = {}
        self.notes[r]       = {}
        self.wrong_marks[r] = {}
        for c = 1, self.n_cols do
            self.grid[r][c]        = {type = "black"}
            self.solution[r][c]    = 0
            self.user[r][c]        = 0
            self.notes[r][c]       = {}
            self.wrong_marks[r][c] = false
        end
    end

    for _, cell in ipairs(data.cells) do
        local r, c, t = cell.r, cell.c, cell.t
        if t == "W" then
            self.grid[r][c] = {type = "white"}
        elseif t == "C" then
            self.grid[r][c] = {type = "clue", across = cell.a or 0, down = cell.d or 0}
        else
            self.grid[r][c] = {type = "black"}
        end
    end

    for r = 1, self.n_rows do
        for c = 1, self.n_cols do
            self.solution[r][c] = data.solution[r] and data.solution[r][c] or 0
        end
    end

    self.selected      = nil
    self.show_solution = false
    self.undo          = UndoStack:new{ max_size = 200 }
end

function KakuroBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty or "easy"
    local tmpl = TEMPLATES[self.difficulty] or TEMPLATES.easy
    local data = nil
    for _ = 1, 10 do
        data = generateFromTemplate(tmpl)
        if data then break end
    end
    if not data then
        data = EMERGENCY_PUZZLE
    end
    self:_buildFromData(data)
end

-- ---------------------------------------------------------------------------
-- Cell accessors
-- ---------------------------------------------------------------------------

function KakuroBoard:getCell(r, c)
    if r < 1 or r > self.n_rows or c < 1 or c > self.n_cols then return nil end
    return self.grid[r][c]
end

function KakuroBoard:isWhite(r, c)
    local cell = self:getCell(r, c)
    return cell and cell.type == "white"
end

function KakuroBoard:isClue(r, c)
    local cell = self:getCell(r, c)
    return cell and cell.type == "clue"
end

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------

function KakuroBoard:setSelected(r, c)
    if not self:isWhite(r, c) then
        self.selected = nil
        return
    end
    self.selected = {r = r, c = c}
end

function KakuroBoard:getSelected()
    if not self.selected then return nil, nil end
    return self.selected.r, self.selected.c
end

function KakuroBoard:getSelection()
    return self:getSelected()
end

function KakuroBoard:setSelection(r, c)
    self:setSelected(r, c)
end

-- ---------------------------------------------------------------------------
-- Run info
-- ---------------------------------------------------------------------------

function KakuroBoard:getAcrossRun(r, c)
    if not self:isWhite(r, c) then return nil end
    local sc = c
    while sc > 1 and self:isWhite(r, sc - 1) do sc = sc - 1 end
    local cells = {}
    local cc = sc
    while cc <= self.n_cols and self:isWhite(r, cc) do
        cells[#cells + 1] = {r = r, c = cc}
        cc = cc + 1
    end
    if #cells < 2 then return nil end
    local clue_cell = self:getCell(r, sc - 1)
    local clue = (clue_cell and clue_cell.type == "clue") and clue_cell.across or 0
    return {cells = cells, clue = clue}
end

function KakuroBoard:getDownRun(r, c)
    if not self:isWhite(r, c) then return nil end
    local sr = r
    while sr > 1 and self:isWhite(sr - 1, c) do sr = sr - 1 end
    local cells = {}
    local rr = sr
    while rr <= self.n_rows and self:isWhite(rr, c) do
        cells[#cells + 1] = {r = rr, c = c}
        rr = rr + 1
    end
    if #cells < 2 then return nil end
    local clue_cell = self:getCell(sr - 1, c)
    local clue = (clue_cell and clue_cell.type == "clue") and clue_cell.down or 0
    return {cells = cells, clue = clue}
end

function KakuroBoard:getRunInfo(r, c, dir)
    local run = (dir == "a") and self:getAcrossRun(r, c) or self:getDownRun(r, c)
    if not run then return nil end
    local cur  = 0
    local used = {}
    for _, cell in ipairs(run.cells) do
        local v = self.user[cell.r][cell.c]
        if v and v > 0 then
            cur = cur + v
            used[#used + 1] = v
        end
    end
    return {sum_needed = run.clue, cells = run.cells, current_sum = cur, used_digits = used}
end

-- ---------------------------------------------------------------------------
-- Value / note editing
-- ---------------------------------------------------------------------------

function KakuroBoard:setValue(v)
    if self.show_solution then
        return false, _("Hide solution to keep playing.")
    end
    local r, c = self:getSelected()
    if not r then return false, _("No cell selected.") end
    if not self:isWhite(r, c) then return false, _("Select a white cell.") end
    local prev_value = self.user[r][c]
    local prev_notes = {}
    for k, nv in pairs(self.notes[r][c]) do prev_notes[k] = nv end
    local new_value = v or 0
    if prev_value == new_value then return true end
    self.user[r][c]        = new_value
    self.notes[r][c]       = {}
    self.wrong_marks[r][c] = false
    self.undo:push{type = "value", r = r, c = c, prev_value = prev_value, prev_notes = prev_notes}
    return true
end

function KakuroBoard:toggleNote(d)
    if self.show_solution then
        return false, _("Hide solution to keep playing.")
    end
    local r, c = self:getSelected()
    if not r then return false, _("No cell selected.") end
    if not self:isWhite(r, c) then return false, _("Select a white cell.") end
    if self.user[r][c] ~= 0 then
        return false, _("Clear the cell before adding notes.")
    end
    local prev_notes = {}
    for k, nv in pairs(self.notes[r][c]) do prev_notes[k] = nv end
    if self.notes[r][c][d] then
        self.notes[r][c][d] = nil
    else
        self.notes[r][c][d] = true
    end
    self.undo:push{type = "notes", r = r, c = c, prev_notes = prev_notes}
    return true
end

function KakuroBoard:canUndo()
    return self.undo:canUndo()
end

function KakuroBoard:undo()
    local entry = self.undo:pop()
    if not entry then return false, _("Nothing to undo.") end
    local r, c = entry.r, entry.c
    if entry.type == "value" then
        self.user[r][c]        = entry.prev_value or 0
        self.notes[r][c]       = {}
        for k, v in pairs(entry.prev_notes or {}) do self.notes[r][c][k] = v end
        self.wrong_marks[r][c] = false
        self.selected          = {r = r, c = c}
    elseif entry.type == "notes" then
        self.notes[r][c] = {}
        for k, v in pairs(entry.prev_notes or {}) do self.notes[r][c][k] = v end
        self.selected    = {r = r, c = c}
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

function KakuroBoard:checkConflicts()
    for r = 1, self.n_rows do
        for c = 1, self.n_cols do
            if self:isWhite(r, c) then
                local v = self.user[r][c]
                self.wrong_marks[r][c] = (v ~= 0 and v ~= self.solution[r][c])
            end
        end
    end
end

function KakuroBoard:isSolved()
    if self.show_solution then return false end
    for r = 1, self.n_rows do
        for c = 1, self.n_cols do
            if self:isWhite(r, c) and self.user[r][c] ~= self.solution[r][c] then
                return false
            end
        end
    end
    return true
end

function KakuroBoard:getRemainingCells()
    local count = 0
    for r = 1, self.n_rows do
        for c = 1, self.n_cols do
            if self:isWhite(r, c) and self.user[r][c] == 0 then count = count + 1 end
        end
    end
    return count
end

function KakuroBoard:toggleSolution()
    self.show_solution = not self.show_solution
end

function KakuroBoard:isShowingSolution()
    return self.show_solution
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function KakuroBoard:serialize()
    local grid_data = {}
    for r = 1, self.n_rows do
        for c = 1, self.n_cols do
            local cell = self.grid[r][c]
            if cell.type == "white" then
                grid_data[#grid_data + 1] = {r=r, c=c, t="W"}
            elseif cell.type == "clue" then
                grid_data[#grid_data + 1] = {r=r, c=c, t="C", a=cell.across, d=cell.down}
            else
                grid_data[#grid_data + 1] = {r=r, c=c, t="B"}
            end
        end
    end
    local sol = {}
    local usr = {}
    local nts = {}
    local wrg = {}
    for r = 1, self.n_rows do
        sol[r] = {}
        usr[r] = {}
        nts[r] = {}
        wrg[r] = {}
        for c = 1, self.n_cols do
            sol[r][c] = self.solution[r][c]
            usr[r][c] = self.user[r][c]
            nts[r][c] = {}
            for k, v in pairs(self.notes[r][c]) do nts[r][c][k] = v end
            wrg[r][c] = self.wrong_marks[r][c] or false
        end
    end
    return {
        n_rows        = self.n_rows,
        n_cols        = self.n_cols,
        difficulty    = self.difficulty,
        cells         = grid_data,
        solution      = sol,
        user          = usr,
        notes         = nts,
        wrong_marks   = wrg,
        selected      = self.selected and {r = self.selected.r, c = self.selected.c} or nil,
        show_solution = self.show_solution,
        undo          = self.undo:serialize(),
    }
end

function KakuroBoard:load(data)
    if not data or not data.cells or not data.solution then return false end
    self.difficulty = data.difficulty or "easy"
    self:_buildFromData(data)
    for r = 1, self.n_rows do
        for c = 1, self.n_cols do
            if data.user and data.user[r] then
                self.user[r][c] = data.user[r][c] or 0
            end
            if data.notes and data.notes[r] and data.notes[r][c] then
                for k, v in pairs(data.notes[r][c]) do self.notes[r][c][k] = v end
            end
            if data.wrong_marks and data.wrong_marks[r] then
                self.wrong_marks[r][c] = data.wrong_marks[r][c] or false
            end
        end
    end
    if data.selected then
        self.selected = {r = data.selected.r, c = data.selected.c}
    end
    self.show_solution = data.show_solution or false
    if data.undo then self.undo:load(data.undo) end
    return true
end

return KakuroBoard
