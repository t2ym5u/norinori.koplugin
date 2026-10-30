local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local grid_utils = require("grid_utils")
local UndoStack  = require("undo_stack")
local Timer      = require("timer")
local Hint       = require("hint")

-- Loaded by path, not require("solver"): lits ships a solver.lua too, and
-- package.loaded is shared by every plugin.
local Solver = lrequire("solver")

local emptyGrid = grid_utils.emptyGrid

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local SIZES        = { 6, 8, 10 }
local DEFAULT_N    = 6
local DIFFICULTIES = { "easy", "medium", "hard" }

-- Cell mark values
local MARK_EMPTY = 0
local MARK_SHADE = 1
local MARK_DOT   = 2

-- ---------------------------------------------------------------------------
-- NorinoriBoard
-- ---------------------------------------------------------------------------

local NorinoriBoard = {}
NorinoriBoard.__index = NorinoriBoard

-- A fresh board holds no puzzle yet: call generate() or load().
function NorinoriBoard:new(opts)
    opts = opts or {}
    return setmetatable({
        n             = opts.n or DEFAULT_N,
        difficulty    = opts.difficulty or "easy",
        region        = nil,   -- [r][c] region id
        solution      = nil,   -- [r][c] 1 = shaded
        marks         = nil,   -- [r][c] MARK_*
        won           = false,
        show_solution = false,
        selected      = nil,   -- { r, c } the hint is pointing at
        hints_used    = 0,
        undo          = UndoStack:new{ max_size = 500 },
        timer         = Timer:new(),
    }, self)
end

local function toGrid(n, flat)
    local g = emptyGrid(n, n, 0)
    for r = 1, n do
        for c = 1, n do g[r][c] = flat[(r - 1) * n + c] end
    end
    return g
end

local function toFlat(n, grid)
    local flat = {}
    for r = 1, n do
        for c = 1, n do flat[#flat + 1] = grid[r][c] end
    end
    return flat
end

-- `progress`: optional function(fraction), called as the generator works
-- (see Solver.generate); the screen drives a progress bar with it.
function NorinoriBoard:generate(progress)
    local p
    -- Solver.generate only gives up after dozens of failed restarts: never
    -- seen in testing, but loop rather than hand out nothing.
    repeat
        p = Solver.generate(self.n, self.difficulty, { progress = progress })
    until p
    self.region     = toGrid(self.n, p.region)
    self.solution   = toGrid(self.n, p.solution)
    self.level      = p.level
    self.marks      = emptyGrid(self.n, self.n, MARK_EMPTY)
    self.won        = false
    self.show_solution = false
    self.selected   = nil
    self.hints_used = 0
    self.undo:clear()
    self.timer:reset()
    self.timer:start()
    self._puzzle    = nil
end

-- The solver's view of the grid (flat region array), built on demand.
function NorinoriBoard:_getPuzzle()
    if not self._puzzle then
        self._puzzle = Solver.newPuzzle(self.n, toFlat(self.n, self.region))
    end
    return self._puzzle
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

function NorinoriBoard:canEdit()
    return not self.won and not self.show_solution
end

function NorinoriBoard:setMark(r, c, mark)
    if not self:canEdit() then return false end
    local cur = self.marks[r][c]
    if cur == mark then return true end
    self.undo:push{ r = r, c = c, old = cur }
    self.marks[r][c] = mark
    self.selected = nil
    self:_checkWin()
    return true
end

-- Tap: empty -> shaded -> dot -> empty.
function NorinoriBoard:cycleCell(r, c)
    local cur = self.marks[r][c]
    local nxt
    if     cur == MARK_EMPTY then nxt = MARK_SHADE
    elseif cur == MARK_SHADE then nxt = MARK_DOT
    else                          nxt = MARK_EMPTY
    end
    return self:setMark(r, c, nxt)
end

-- Wipes every mark, as one undoable step.
function NorinoriBoard:clearAll()
    if not self:canEdit() then return false end
    local old, any = {}, false
    for r = 1, self.n do
        old[r] = {}
        for c = 1, self.n do
            old[r][c] = self.marks[r][c]
            if old[r][c] ~= MARK_EMPTY then any = true end
        end
    end
    if not any then return false end
    self.undo:push{ all = old }
    self.marks = emptyGrid(self.n, self.n, MARK_EMPTY)
    self.selected = nil
    return true
end

function NorinoriBoard:canUndo()
    return self:canEdit() and self.undo:canUndo()
end

function NorinoriBoard:undoMove()
    if not self:canEdit() then return false end
    local entry = self.undo:pop()
    if not entry then return false end
    if entry.all then
        self.marks = entry.all
    else
        self.marks[entry.r][entry.c] = entry.old
    end
    self.selected = nil
    return true
end

function NorinoriBoard:setSelection(r, c)
    self.selected = { r, c }
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- Won when the shaded cells satisfy every rule. The generator proved the
-- solution unique, so that is the same as matching it; dots are notes.
function NorinoriBoard:_checkWin()
    local flat = {}
    for r = 1, self.n do
        for c = 1, self.n do flat[#flat + 1] = self.marks[r][c] == MARK_SHADE end
    end
    self.won = Solver.isValid(self:_getPuzzle(), flat)
    if self.won then
        self.selected = nil
        self.timer:stop()
    end
end

function NorinoriBoard:isSolved()
    return self.won
end

-- Shaded cells that already break a rule: a region holding more than two,
-- a blob of three or more, or a lone cell with no neighbour left to pair with.
function NorinoriBoard:getConflicts()
    local n = self.n
    local conflict = emptyGrid(n, n, false)
    local function shaded(r, c)
        return r >= 1 and r <= n and c >= 1 and c <= n and self.marks[r][c] == MARK_SHADE
    end
    local function open(r, c)
        return r >= 1 and r <= n and c >= 1 and c <= n and self.marks[r][c] ~= MARK_DOT
    end
    local per_region = {}
    for r = 1, n do
        for c = 1, n do
            if shaded(r, c) then
                local id = self.region[r][c]
                per_region[id] = (per_region[id] or 0) + 1
            end
        end
    end
    local DIRS = { {-1,0}, {1,0}, {0,-1}, {0,1} }
    for r = 1, n do
        for c = 1, n do
            if shaded(r, c) then
                if per_region[self.region[r][c]] > 2 then conflict[r][c] = true end
                local sn, possible = 0, 0
                for _, d in ipairs(DIRS) do
                    if shaded(r + d[1], c + d[2]) then sn = sn + 1 end
                    if open(r + d[1], c + d[2]) then possible = possible + 1 end
                end
                if sn >= 2 then
                    conflict[r][c] = true
                    for _, d in ipairs(DIRS) do
                        if shaded(r + d[1], c + d[2]) then conflict[r + d[1]][c + d[2]] = true end
                    end
                end
                if possible == 0 then conflict[r][c] = true end
            end
        end
    end
    return conflict
end

function NorinoriBoard:countShaded()
    local count = 0
    for r = 1, self.n do
        for c = 1, self.n do
            if self.marks[r][c] == MARK_SHADE then count = count + 1 end
        end
    end
    return count
end

-- Two per region.
function NorinoriBoard:totalShaded()
    return 2 * self:_getPuzzle().nregions
end

function NorinoriBoard:toggleSolution()
    self.show_solution = not self.show_solution
    self.selected = nil
end

function NorinoriBoard:isShowingSolution()
    return self.show_solution
end

-- ---------------------------------------------------------------------------
-- Hint
-- ---------------------------------------------------------------------------

-- A dot is a note that the cell stays empty, so only shading decides the
-- puzzle: equals() compares shaded-ness, and a dot on a cell the solution
-- shades is reported (and cleared) as a mistake.
Hint.install(NorinoriBoard, {
    getUser     = function(b, r, c) return b.marks[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] == 1 and MARK_SHADE or MARK_EMPTY end,
    isEmpty     = function(v) return v == MARK_EMPTY end,
    equals      = function(u, s) return (u == MARK_SHADE) == (s == MARK_SHADE) end,
    setCell     = function(b, r, c, v) return b:setMark(r, c, v) end,
    blank       = MARK_EMPTY,
})

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function NorinoriBoard:serialize()
    local n = self.n
    -- game-common up to 1.6.0 stops the clock in Timer:serialize(), which
    -- would freeze it at the first saved move: restart it (a no-op with a
    -- Timer that reads without stopping).
    local timer = self.timer:serialize()
    if timer.was_running then self.timer:start() end
    return {
        n          = n,
        difficulty = self.difficulty,
        level      = self.level,
        region     = toFlat(n, self.region),
        solution   = toFlat(n, self.solution),
        marks      = toFlat(n, self.marks),
        won        = self.won,
        hints_used = self.hints_used,
        timer      = timer,
        undo       = self.undo:serialize(),
    }
end

function NorinoriBoard:load(data)
    if type(data) ~= "table" or type(data.region) ~= "table"
            or type(data.solution) ~= "table" or type(data.marks) ~= "table" then
        return false
    end
    local n = tonumber(data.n)
    if not n or #data.region ~= n * n or #data.solution ~= n * n or #data.marks ~= n * n then
        return false
    end
    self.n          = n
    self.difficulty = data.difficulty or "easy"
    self.level      = data.level
    self.region     = toGrid(n, data.region)
    self.solution   = toGrid(n, data.solution)
    self.marks      = toGrid(n, data.marks)
    self.won        = data.won and true or false
    self.hints_used = tonumber(data.hints_used) or 0
    self.show_solution = false
    self.selected   = nil
    self._puzzle    = nil
    self.undo:load(data.undo)
    self.timer:load(data.timer)
    if self.won then self.timer:stop() end
    return true
end

NorinoriBoard.MARK_EMPTY   = MARK_EMPTY
NorinoriBoard.MARK_SHADE   = MARK_SHADE
NorinoriBoard.MARK_DOT     = MARK_DOT
NorinoriBoard.SIZES        = SIZES
NorinoriBoard.DEFAULT_N    = DEFAULT_N
NorinoriBoard.DIFFICULTIES = DIFFICULTIES
NorinoriBoard.Solver       = Solver

return NorinoriBoard
