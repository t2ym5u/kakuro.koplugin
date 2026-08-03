local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("KakuroBoard", function()
    local Board

    setup(function()
        -- gettext already mocked in helper.lua
        Board = require("board")
    end)


    local function newBoard(difficulty)
        math.randomseed(42)
        local b = Board:new({ difficulty = difficulty or "easy" })
        b:generate()
        return b
    end

    describe("generate", function()
        it("creates a grid with white, clue, and black cells", function()
            local b = newBoard()
            local has_white, has_clue, has_black = false, false, false
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    local t = b.grid[r][c].type
                    if t == "white" then has_white = true
                    elseif t == "clue"  then has_clue  = true
                    elseif t == "black" then has_black = true
                    end
                end
            end
            assert.is_true(has_white)
            assert.is_true(has_clue)
            assert.is_true(has_black)
        end)

        it("solution values in white cells are 1–9", function()
            local b = newBoard()
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then
                        local v = b.solution[r][c]
                        assert.is_true(v >= 1 and v <= 9,
                            ("white cell [%d][%d] has invalid solution %d"):format(r, c, v))
                    end
                end
            end
        end)

        it("clue cells have non-negative across/down values", function()
            local b = newBoard()
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isClue(r, c) then
                        local cell = b.grid[r][c]
                        assert.is_true(cell.across >= 0)
                        assert.is_true(cell.down   >= 0)
                    end
                end
            end
        end)
    end)

    describe("isWhite / isClue / getCell", function()
        it("getCell returns nil out of bounds", function()
            local b = newBoard()
            assert.is_nil(b:getCell(0, 0))
            assert.is_nil(b:getCell(b.n_rows + 1, 1))
        end)

        it("isWhite and isClue are mutually exclusive", function()
            local b = newBoard()
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    assert.is_false(b:isWhite(r, c) and b:isClue(r, c),
                        ("cell [%d][%d] cannot be both white and clue"):format(r, c))
                end
            end
        end)
    end)

    describe("setSelected / getSelected", function()
        it("selects a white cell", function()
            local b = newBoard()
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then
                        b:setSelected(r, c)
                        local sr, sc = b:getSelected()
                        assert.are.equal(r, sr)
                        assert.are.equal(c, sc)
                        return
                    end
                end
            end
        end)

        it("selecting a non-white cell clears selection", function()
            local b = newBoard()
            -- Select a white cell first
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then b:setSelected(r, c); break end
                end
                break
            end
            -- Now select a black cell
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if not b:isWhite(r, c) and not b:isClue(r, c) then
                        b:setSelected(r, c)
                        local sr, sc = b:getSelected()
                        assert.is_nil(sr)
                        return
                    end
                end
            end
        end)
    end)

    describe("setValue / undo", function()
        local function selectFirstWhite(b)
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then
                        b:setSelected(r, c)
                        return r, c
                    end
                end
            end
        end

        it("setValue writes to the selected white cell", function()
            local b = newBoard()
            local r, c = selectFirstWhite(b)
            local ok = b:setValue(5)
            assert.is_true(ok)
            assert.are.equal(5, b.user[r][c])
        end)

        it("setValue returns false with no selection", function()
            local b = newBoard()
            local ok, err = b:setValue(3)
            assert.is_false(ok)
            assert.is_not_nil(err)
        end)

        it("undo restores the previous value", function()
            local b = newBoard()
            local r, c = selectFirstWhite(b)
            b:setValue(7)
            assert.is_true(b:canUndo())
            Board.undo(b)  -- b.undo field (UndoStack) shadows the :undo() method
            assert.are.equal(0, b.user[r][c])
            assert.is_false(b:canUndo())
        end)
    end)

    describe("isSolved / checkConflicts", function()
        it("isSolved returns false on a fresh board", function()
            local b = newBoard()
            assert.is_false(b:isSolved())
        end)

        it("isSolved returns true when user matches solution", function()
            local b = newBoard()
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then
                        b.user[r][c] = b.solution[r][c]
                    end
                end
            end
            assert.is_true(b:isSolved())
        end)

        it("checkConflicts marks a wrong value", function()
            local b = newBoard()
            local r, c
            for rr = 1, b.n_rows do
                for cc = 1, b.n_cols do
                    if b:isWhite(rr, cc) then
                        r, c = rr, cc
                        b.user[r][c] = (b.solution[r][c] % 9) + 1  -- wrong value
                        if b.user[r][c] == b.solution[r][c] then
                            b.user[r][c] = (b.solution[r][c] % 9) + 1  -- try next
                        end
                        goto done
                    end
                end
            end
            ::done::
            b:checkConflicts()
            -- Only mark if value truly differs
            if b.user[r][c] ~= b.solution[r][c] then
                assert.is_true(b.wrong_marks[r][c])
            end
        end)
    end)

    describe("getRemainingCells", function()
        it("counts unfilled white cells", function()
            local b = newBoard()
            local count = 0
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then count = count + 1 end
                end
            end
            assert.are.equal(count, b:getRemainingCells())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips board state", function()
            local b = newBoard()
            -- Place a value
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then
                        b:setSelected(r, c)
                        b:setValue(3)
                        goto done
                    end
                end
            end
            ::done::
            local data = b:serialize()

            local b2 = Board:new()
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n_rows, b2.n_rows)
            assert.are.equal(b.n_cols, b2.n_cols)
            -- White cell values should match
            for r = 1, b.n_rows do
                for c = 1, b.n_cols do
                    if b:isWhite(r, c) then
                        assert.are.equal(b.user[r][c], b2.user[r][c])
                    end
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
