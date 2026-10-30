-- ---------------------------------------------------------------------------
-- solver.lua — Norinori rules engine: logical solver (graded), solution
-- counter and generator. Pure Lua, no KOReader dependency, so the specs can
-- drive it headless.
--
-- Rules: every outlined region holds exactly two shaded cells, and every
-- shaded cell has exactly one shaded orthogonal neighbour -- the shaded cells
-- form dominoes that never touch each other side-on (a domino may straddle
-- two regions, giving one cell to each).
--
-- Cells are addressed by a flat index i = (r - 1) * n + c. A solving state is
-- a flat array of UNKNOWN / SHADED / EMPTY.
-- ---------------------------------------------------------------------------

local Solver = {}

local UNKNOWN, SHADED, EMPTY = 0, 1, 2
Solver.UNKNOWN, Solver.SHADED, Solver.EMPTY = UNKNOWN, SHADED, EMPTY

-- Difficulty is the hardest technique the logical solver needs:
--   1 = counting and domino rules (a region with two shaded cells is full, a
--       lone shaded cell with one open neighbour extends into it, ...), plus
--       case analysis on a region with at most three ways left to finish --
--       a glance more than an analysis;
--   2 = region case analysis on any region: try every way it can still take
--       its shaded cells, keep what all the surviving ways agree on;
--   3 = single-cell trial: "if this cell were shaded, the level-1 rules
--       would break", one step deep.
-- Anything that needs more than that is never handed out as a puzzle.
Solver.LEVEL = { easy = 1, medium = 2, hard = 3 }

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function copy(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    return c
end

-- ---------------------------------------------------------------------------
-- Puzzle geometry
-- ---------------------------------------------------------------------------

local nb_cache = {}

local function neighbours(n)
    if nb_cache[n] then return nb_cache[n] end
    local nb = {}
    for r = 1, n do
        for c = 1, n do
            local list = {}
            if r > 1 then list[#list + 1] = (r - 2) * n + c end
            if r < n then list[#list + 1] = r * n + c end
            if c > 1 then list[#list + 1] = (r - 1) * n + c - 1 end
            if c < n then list[#list + 1] = (r - 1) * n + c + 1 end
            nb[(r - 1) * n + c] = list
        end
    end
    nb_cache[n] = nb
    return nb
end
Solver.neighbours = neighbours

-- region: flat array of region ids, 1..R with no gaps.
function Solver.newPuzzle(n, region)
    local cells, nregions = {}, 0
    for i = 1, n * n do
        local id = region[i]
        if id > nregions then nregions = id end
        cells[id] = cells[id] or {}
        cells[id][#cells[id] + 1] = i
    end
    -- queue / inq / rdirty / wbuf: propagate's scratch space (see there).
    local inq = {}
    for i = 1, n * n do inq[i] = false end
    return { n = n, N = n * n, region = region, cells = cells,
             nregions = nregions, nb = neighbours(n),
             queue = {}, inq = inq, rdirty = {}, wbuf = {} }
end

-- ---------------------------------------------------------------------------
-- Level 1: basic propagation. Applies the counting and domino rules until
-- nothing changes. Returns false on a contradiction. Sound: every value it
-- writes holds in every solution consistent with the input state.
-- ---------------------------------------------------------------------------

-- The worklist is a ring over P's own scratch arrays (a cell is queued at
-- most once, so N slots are enough): this is the counter's inner loop, and
-- fresh tables per call used to be most of its cost. A region is re-counted
-- only when a cell of it changed since its last count (`rdirty`).
local function propagate(P, st, seeds)
    local nb, cells, region, N = P.nb, P.cells, P.region, P.N
    -- Worklist of cells whose surroundings changed: a cell's rules read only
    -- its own neighbours and its region, so a change at x re-examines x, its
    -- neighbours and its region. Without seeds, every cell starts dirty.
    local queue, inq, rdirty = P.queue, P.inq, P.rdirty
    local head, tail, size = 1, 0, 0
    for id = 1, P.nregions do rdirty[id] = true end
    if seeds then
        for k = 1, #seeds do
            local i = seeds[k]
            if not inq[i] then inq[i] = true; tail = tail + 1; queue[tail] = i; size = size + 1 end
            local ni = nb[i]
            for m = 1, #ni do
                local j = ni[m]
                if not inq[j] then inq[j] = true; tail = tail + 1; queue[tail] = j; size = size + 1 end
            end
        end
    else
        for i = 1, N do inq[i] = true; queue[i] = i end
        tail, size = N, N
    end
    local ok = true
    -- Cells written while examining one cell go to `wbuf`; they and their
    -- neighbours are queued once that cell is done.
    local wbuf, nw = P.wbuf, 0
    while size > 0 do
        local i = queue[head]
        head = head % N + 1
        size = size - 1
        inq[i] = false

        -- Region count: two shaded fills it, too few cells left forces them.
        local id = region[i]
        if rdirty[id] then
            rdirty[id] = false
            local list = cells[id]
            local s, u = 0, 0
            for k = 1, #list do
                local v = st[list[k]]
                if v == SHADED then s = s + 1 elseif v == UNKNOWN then u = u + 1 end
            end
            if s > 2 or s + u < 2 then ok = false; break end
            if u > 0 and (s == 2 or s + u == 2) then
                -- Filled in full: nothing left for a re-count to find, so
                -- the region stays clean.
                local fill = (s == 2) and EMPTY or SHADED
                for k = 1, #list do
                    local x = list[k]
                    if st[x] == UNKNOWN then st[x] = fill; nw = nw + 1; wbuf[nw] = x end
                end
            end
        end

        local v = st[i]
        local ni = nb[i]
        if v == SHADED then
            local sn, un, last = 0, 0, nil
            for k = 1, #ni do
                local w = st[ni[k]]
                if w == SHADED then sn = sn + 1
                elseif w == UNKNOWN then un = un + 1; last = ni[k] end
            end
            if sn >= 2 then ok = false; break end
            if sn == 1 then
                -- A finished domino: nothing else may touch it.
                for k = 1, #ni do
                    local x = ni[k]
                    if st[x] == UNKNOWN then
                        st[x] = EMPTY; rdirty[region[x]] = true; nw = nw + 1; wbuf[nw] = x
                    end
                end
            elseif un == 0 then
                ok = false; break
            elseif un == 1 then
                -- A lone shaded cell with one way out takes it.
                st[last] = SHADED; rdirty[region[last]] = true; nw = nw + 1; wbuf[nw] = last
            end
        elseif v == UNKNOWN then
            -- Shading this cell would weld two shaded cells into a blob of
            -- three, or leave it with no possible partner.
            local sn, open = 0, 0
            for k = 1, #ni do
                local w = st[ni[k]]
                if w == SHADED then sn = sn + 1
                elseif w == UNKNOWN then open = open + 1 end
            end
            if sn >= 2 or (sn == 0 and open == 0) then
                st[i] = EMPTY; rdirty[id] = true; nw = nw + 1; wbuf[nw] = i
            end
        end

        for w = 1, nw do
            local x = wbuf[w]
            if not inq[x] then
                inq[x] = true; tail = tail % N + 1; queue[tail] = x; size = size + 1
            end
            local nx = nb[x]
            for m = 1, #nx do
                local j = nx[m]
                if not inq[j] then
                    inq[j] = true; tail = tail % N + 1; queue[tail] = j; size = size + 1
                end
            end
        end
        nw = 0
    end
    -- Leave the scratch clean for the next call (a contradiction can stop
    -- with cells still queued).
    while size > 0 do
        inq[queue[head]] = false
        head = head % N + 1
        size = size - 1
    end
    return ok
end
Solver.propagate = propagate

local function isComplete(st)
    for i = 1, #st do
        if st[i] == UNKNOWN then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Level 2: region case analysis. For one region still short of shaded cells,
-- try each way to finish it (choose the missing cell(s) among its unknowns,
-- the rest empty), propagate, and keep every cell on which all surviving
-- cases agree. Returns "contra", true (progress) plus the cells it set, or
-- false. `st` must be a propagation fixpoint (every caller propagates first),
-- so each case only needs to propagate from the cells it wrote.
-- ---------------------------------------------------------------------------

local function regionStep(P, st, max_ways)
    local N = P.N
    for id = 1, P.nregions do
        local list = P.cells[id]
        local s, unk = 0, {}
        for k = 1, #list do
            local v = st[list[k]]
            if v == SHADED then s = s + 1 elseif v == UNKNOWN then unk[#unk + 1] = list[k] end
        end
        local need = 2 - s
        local ways = need == 1 and #unk or #unk * (#unk - 1) / 2
        if need > 0 and #unk > need and ways <= max_ways then
            -- agree: the first surviving case, then the cells every later
            -- one agrees with (the rest reset to UNKNOWN). Once nothing is
            -- left to agree on, the region can only fail to progress.
            local agree, left = nil, 0
            local function try(a, b)
                if agree and left == 0 then return end
                local t = copy(st)
                for k = 1, #unk do t[unk[k]] = EMPTY end
                t[a] = SHADED
                if b then t[b] = SHADED end
                if not propagate(P, t, unk) then return end
                if not agree then
                    agree = t
                    for i = 1, N do
                        if st[i] == UNKNOWN and t[i] ~= UNKNOWN then left = left + 1 end
                    end
                else
                    for i = 1, N do
                        local v = agree[i]
                        if v ~= UNKNOWN and st[i] == UNKNOWN and t[i] ~= v then
                            agree[i] = UNKNOWN
                            left = left - 1
                        end
                    end
                end
            end
            if need == 1 then
                for x = 1, #unk do try(unk[x]) end
            else
                for x = 1, #unk - 1 do
                    for y = x + 1, #unk do try(unk[x], unk[y]) end
                end
            end
            if not agree then return "contra" end
            if left > 0 then
                local changed = {}
                for i = 1, N do
                    if st[i] == UNKNOWN and agree[i] ~= UNKNOWN then
                        st[i] = agree[i]
                        changed[#changed + 1] = i
                    end
                end
                return true, changed
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Level 3: single-cell trial with the level-1 closure.
-- ---------------------------------------------------------------------------

-- A region with this few ways left to finish is a glance, not an analysis:
-- level 1 reads it off.
local SMALL_CASES = 3

-- Basic propagation plus the glance-sized case analyses, to a fixpoint.
-- `seeds`: the cells written since st was last a propagation fixpoint (nil:
-- propagate from scratch).
local function closure(P, st, max_ways, seeds)
    while true do
        if not propagate(P, st, seeds) then return false end
        local r, changed = regionStep(P, st, max_ways)
        if r == "contra" then return false end
        if not r then return true end
        seeds = changed
    end
end

-- st is a fixpoint of closure(SMALL_CASES) here, so a trial propagates from
-- the one cell it wrote.
local function trialStep(P, st)
    for i = 1, P.N do
        if st[i] == UNKNOWN then
            local t = copy(st)
            t[i] = SHADED
            if not closure(P, t, SMALL_CASES, { i }) then st[i] = EMPTY; return true, { i } end
            t = copy(st)
            t[i] = EMPTY
            if not closure(P, t, SMALL_CASES, { i }) then st[i] = SHADED; return true, { i } end
        end
    end
    return false
end

-- Solve by logic alone, cheapest technique first, going back to level 1
-- after every deduction. Returns status ("solved" / "stuck" / "contra"), the
-- highest level that was needed, the final state, and how many deductions
-- each level above 1 made ({ [2] = .., [3] = .. }).
function Solver.logicSolve(P, max_level, st)
    st = st and copy(st) or {}
    if #st == 0 then for i = 1, P.N do st[i] = UNKNOWN end end
    local used, steps = 1, { 0, 0, 0 }
    -- After the first pass, propagation restarts from the cells the last
    -- deduction wrote: the state was a fixpoint before them.
    local seeds
    while true do
        if not propagate(P, st, seeds) then return "contra", used, st, steps end
        if isComplete(st) then return "solved", used, st, steps end
        local r
        r, seeds = regionStep(P, st, SMALL_CASES)
        if r == "contra" then return "contra", used, st, steps end
        local progress = r
        if not progress and max_level >= 2 then
            r, seeds = regionStep(P, st, math.huge)
            if r == "contra" then return "contra", used, st, steps end
            if r then
                progress = true
                steps[2] = steps[2] + 1
                if used < 2 then used = 2 end
            end
        end
        if not progress and max_level >= 3 then
            r, seeds = trialStep(P, st)
            if r then
                progress = true
                steps[3] = steps[3] + 1
                used = 3
            end
        end
        if not progress then return "stuck", used, st, steps end
    end
end

-- ---------------------------------------------------------------------------
-- Solution counter: propagation + branching. Counts up to `limit` solutions,
-- giving up after `budget` nodes, from `start` (a partial state) or from
-- scratch. Returns count, exhausted, solutions.
-- ---------------------------------------------------------------------------

function Solver.countSolutions(P, limit, budget, start)
    limit  = limit or 2
    budget = budget or 20000
    local count, nodes, exhausted = 0, 0, false
    local sols = {}

    local function pick(st)
        -- The unknown cell of the region with the fewest unknowns: its
        -- branches are the most constrained.
        local best, best_u = nil, math.huge
        for id = 1, P.nregions do
            local list = P.cells[id]
            local u, first = 0, nil
            for k = 1, #list do
                if st[list[k]] == UNKNOWN then
                    u = u + 1
                    first = first or list[k]
                end
            end
            if u > 0 and u < best_u then best, best_u = first, u end
        end
        return best
    end

    local function dfs(st, seed)
        if count >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > budget then exhausted = true; return end
        if not propagate(P, st, seed) then return end
        local i = pick(st)
        if not i then
            count = count + 1
            sols[#sols + 1] = st
            return
        end
        -- The second branch takes over st itself: nothing reads it after.
        local a = copy(st); a[i] = SHADED; dfs(a, { i })
        st[i] = EMPTY; dfs(st, { i })
    end

    local st = start and copy(start) or {}
    if not start then for i = 1, P.N do st[i] = UNKNOWN end end
    dfs(st)
    return count, exhausted, sols
end

-- ---------------------------------------------------------------------------
-- Rule check on a finished shading (flat array of booleans or 1/0).
-- ---------------------------------------------------------------------------

function Solver.isValid(P, shaded)
    local function on(i) return shaded[i] == true or shaded[i] == 1 end
    local per = {}
    for i = 1, P.N do
        if on(i) then
            local id = P.region[i]
            per[id] = (per[id] or 0) + 1
            local sn = 0
            for _, j in ipairs(P.nb[i]) do
                if on(j) then sn = sn + 1 end
            end
            if sn ~= 1 then return false end
        end
    end
    for id = 1, P.nregions do
        if per[id] ~= 2 then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Generator
--
-- Solution first: scatter dominoes that never touch side-on, give every
-- shaded cell a proto-region grown over the empty cells, then pair adjacent
-- protos into regions of exactly two shaded cells. The planted shading is
-- valid by construction. Uniqueness is then forced by local surgery: while
-- the counter finds a second solution, move a cell that the rival shades (and
-- the planted solution leaves empty) into a neighbouring region. That breaks
-- the rival's count in two regions and leaves the planted solution intact,
-- since empty cells carry no count.
-- ---------------------------------------------------------------------------

-- Packs dominoes that never touch side-on, densely: plain random placement
-- stalls near a third of the grid, which leaves wide open regions where a
-- domino can sit in many places. Each step serves the free cell with the
-- fewest possible partners first (corners and edges, then gaps), the classic
-- greedy for dense packings, with random tie-breaks.
local function plantDominoes(n, nb, target)
    local N = n * n
    local sol = {}
    for i = 1, N do sol[i] = 0 end
    local function free(i, partner)
        if sol[i] ~= 0 then return false end
        for _, j in ipairs(nb[i]) do
            if j ~= partner and sol[j] ~= 0 then return false end
        end
        return true
    end
    local function partners(i)
        local list = {}
        if not free(i) then return list end
        for _, j in ipairs(nb[i]) do
            if free(j) and free(i, j) and free(j, i) then list[#list + 1] = j end
        end
        return list
    end
    local placed = 0
    while placed < target do
        local best, best_k, ties = nil, math.huge, 0
        for i = 1, N do
            local k = #partners(i)
            if k > 0 then
                if k < best_k then
                    best, best_k, ties = i, k, 1
                elseif k == best_k then
                    ties = ties + 1
                    if math.random(ties) == 1 then best = i end
                end
            end
        end
        if not best then break end
        local opts = partners(best)
        local j = opts[math.random(#opts)]
        sol[best], sol[j] = 1, 1
        placed = placed + 1
    end
    return sol, placed
end

-- Grow one proto-region per shaded cell over the empty cells, then pair the
-- protos. Returns the flat region array, or nil if the pairing failed.
local function buildRegions(n, nb, sol)
    local N = n * n
    local owner, protos = {}, {}
    for i = 1, N do
        if sol[i] == 1 then
            protos[#protos + 1] = i
            owner[i] = #protos
        end
    end
    -- Always grow the smallest proto that still can (random tie-break):
    -- uniform random growth leaves a few sprawling regions, and a big region
    -- is exactly where a domino can slide to a second position.
    local size, open = {}, {}
    for p = 1, #protos do size[p] = 1; open[p] = { protos[p] } end
    while true do
        local best, best_size, ties = nil, math.huge, 0
        for p = 1, #protos do
            if #open[p] > 0 then
                if size[p] < best_size then
                    best, best_size, ties = p, size[p], 1
                elseif size[p] == best_size then
                    ties = ties + 1
                    if math.random(ties) == 1 then best = p end
                end
            end
        end
        if not best then break end
        local fr = open[best]
        local grown = false
        while #fr > 0 and not grown do
            local fi = math.random(#fr)
            local i = fr[fi]
            local opts = {}
            for _, j in ipairs(nb[i]) do
                if not owner[j] and sol[j] == 0 then opts[#opts + 1] = j end
            end
            if #opts == 0 then
                fr[fi] = fr[#fr]
                fr[#fr] = nil
            else
                local j = opts[math.random(#opts)]
                owner[j] = best
                size[best] = size[best] + 1
                fr[#fr + 1] = j
                grown = true
            end
        end
    end

    -- Proto adjacency.
    local adj = {}
    for p = 1, #protos do adj[p] = {} end
    for i = 1, N do
        for _, j in ipairs(nb[i]) do
            local a, b = owner[i], owner[j]
            if a ~= b then adj[a][b] = true end
        end
    end

    -- Greedy matching, always serving the proto with the fewest unmatched
    -- neighbours first (random tie-break). A perfect matching always exists
    -- -- each domino's two halves are adjacent -- and this heuristic finds a
    -- different one almost every time; when it paints itself into a corner
    -- it simply starts over.
    local function match()
        local mate = {}
        local remaining = #protos
        while remaining > 0 do
            local best, best_deg, ties = nil, math.huge, 0
            for p = 1, #protos do
                if not mate[p] then
                    local d = 0
                    for q in pairs(adj[p]) do if not mate[q] then d = d + 1 end end
                    if d < best_deg then
                        best, best_deg, ties = p, d, 1
                    elseif d == best_deg then
                        ties = ties + 1
                        if math.random(ties) == 1 then best = p end
                    end
                end
            end
            if best_deg == 0 then return nil end
            local opts = {}
            for q in pairs(adj[best]) do if not mate[q] then opts[#opts + 1] = q end end
            table.sort(opts)
            local q = opts[math.random(#opts)]
            mate[best], mate[q] = q, best
            remaining = remaining - 2
        end
        return mate
    end
    local mate
    for _ = 1, 8 do
        mate = match()
        if mate then break end
    end
    if not mate then return nil end

    local rid, next_id = {}, 0
    local region = {}
    for i = 1, N do
        local p = owner[i]
        if not rid[p] then
            next_id = next_id + 1
            rid[p], rid[mate[p]] = next_id, next_id
        end
        region[i] = rid[p]
    end
    return region
end

-- ---------------------------------------------------------------------------
-- Region surgery. A move takes a cell the planted solution leaves empty out
-- of its region and gives it to a neighbouring one. Empty cells carry no
-- count, so the planted solution stays valid whatever moves are made. If the
-- cell was holding part of its region on (a corridor to a dead end), that
-- cut-off part -- empty cells only, the region's two shaded cells being on
-- the main side -- goes along with it, so no region is ever split.
-- ---------------------------------------------------------------------------

-- Returns the cells that would move with x and the candidate target
-- regions, or nil if x cannot move (its removal would separate the region's
-- two shaded cells, or no other region touches the moving group).
local seen_mark, seen_stamp, plan_stack = {}, 0, {}

local function planMove(n, nb, sol, region, x)
    if sol[x] ~= 0 then return nil end
    local id, N = region[x], n * n
    local anchor
    for i = 1, N do
        if region[i] == id and sol[i] == 1 then anchor = i; break end
    end
    -- Flood the region from a shaded cell, x removed. seen_mark[i] ==
    -- seen_stamp means reached: one array for every call, no clearing.
    seen_stamp = seen_stamp + 1
    local stamp, seen, stack = seen_stamp, seen_mark, plan_stack
    seen[anchor], seen[x] = stamp, stamp
    stack[1] = anchor
    local top = 1
    while top > 0 do
        local i = stack[top]
        top = top - 1
        local ni = nb[i]
        for k = 1, #ni do
            local j = ni[k]
            if seen[j] ~= stamp and region[j] == id then
                seen[j] = stamp
                top = top + 1
                stack[top] = j
            end
        end
    end
    local group = { x }
    for i = 1, N do
        if region[i] == id and seen[i] ~= stamp then
            if sol[i] == 1 then return nil end
            group[#group + 1] = i
        end
    end
    local targets, have = {}, {}
    for k = 1, #group do
        local ng = nb[group[k]]
        for m = 1, #ng do
            local t = region[ng[m]]
            if t ~= id and not have[t] then
                have[t] = true
                targets[#targets + 1] = t
            end
        end
    end
    if #targets == 0 then return nil end
    return group, targets
end

-- Moves the first movable cell of `cells` (tried in the given order).
-- Returns an undo function, or nil if none could move.
local function moveOneOf(n, nb, sol, region, cells)
    for _, x in ipairs(cells) do
        local group, targets = planMove(n, nb, sol, region, x)
        if group then
            local t, old = targets[math.random(#targets)], region[x]
            for _, g in ipairs(group) do region[g] = t end
            return function()
                for _, g in ipairs(group) do region[g] = old end
            end
        end
    end
    return nil
end

local function emptyCells(sol, extra)
    local list = {}
    for i = 1, #sol do
        if sol[i] == 0 and (not extra or extra(i)) then list[#list + 1] = i end
    end
    return shuffle(list)
end

-- Progress report: generate() points `progress` at the caller's callback
-- for its duration, and every layout measured (one solution count or one
-- grading) is a unit of work. How many units a puzzle takes is not known in
-- advance, so the fraction reported approaches 1 without reaching it: half
-- way after PROGRESS_HALF units (10x10 averages 30-50 units, 6x6 hard ~260
-- much cheaper ones). It only reads a counter -- never the clock, never
-- math.random -- so reporting cannot change the puzzle (the Daily Challenge
-- needs every device to build the same grid from the same seed).
local PROGRESS_HALF = 100
local progress, work = nil, 0

local function tick()
    if progress then
        work = work + 1
        progress(1 - 0.5 ^ (work / PROGRESS_HALF))
    end
end

-- Hill climb toward uniqueness. The measure is the number of solutions,
-- counted up to CAP; the counter starts from whatever the level-1 solver
-- settles, so its search stays small. Each step moves a cell
-- that a rival solution shades and the planted solution leaves empty: that
-- breaks the rival's count in two regions. The move is kept unless it let
-- more solutions in than it removed (with a little slack, to get off
-- plateaus).
local ACCEPT_WORSE = 0.1

-- Counter node budget per measure, and the solution cap. Measured on 10x10:
-- a bigger budget mostly buys slower failures, a run that exhausts it just
-- reads as "many solutions".
local BUDGET = 1000
local CAP = 8

-- Returns the measure (solutions counted up to CAP, from the state level 1
-- reaches; 1 = unique), plus one rival solution if there is one, and that
-- level-1 state.
local function measure(n, region, sol, budget)
    tick()
    local P = Solver.newPuzzle(n, region)
    local st = {}
    for i = 1, P.N do st[i] = UNKNOWN end
    if not closure(P, st, SMALL_CASES) then return nil end
    local count, exhausted, sols = Solver.countSolutions(P, CAP, budget, st)
    if exhausted then count = CAP + 1 end
    local rivals = {}
    for _, s in ipairs(sols) do
        for i = 1, #sol do
            if (s[i] == SHADED) ~= (sol[i] == 1) then rivals[#rivals + 1] = s; break end
        end
    end
    return count, rivals[1] and rivals[math.random(#rivals)], st
end

local function makeUnique(n, nb, sol, region, max_moves, budget)
    local cur, alt, st = measure(n, region, sol, budget)
    if not cur then return false end
    for _ = 1, max_moves do
        if cur == 1 then return true end
        local undo = moveOneOf(n, nb, sol, region, emptyCells(sol, function(i)
            if alt then return alt[i] == SHADED end
            return st[i] == UNKNOWN
        end))
        -- Every cell that would break the rival is pinned: reshape
        -- anywhere instead and let the next round look again.
        undo = undo or moveOneOf(n, nb, sol, region, emptyCells(sol))
        if not undo then return false end
        local nc, nalt, nst = measure(n, region, sol, budget)
        if nc and (nc <= cur or math.random() < ACCEPT_WORSE) then
            cur, alt, st = nc, nalt, nst
        else
            undo()
        end
    end
    return cur == 1
end

local function countOpen(st)
    local open = 0
    for i = 1, #st do
        if st[i] == UNKNOWN then open = open + 1 end
    end
    return open
end

-- How far the puzzle is from the wanted level, 0 = on target, nil = not
-- acceptable at all (no longer unique, or beyond the level-3 solver). Only
-- the techniques up to the wanted level are run, so the measure stays cheap:
-- for easy and medium, the cells left open when those techniques stall give
-- the climb a slope to follow. For hard, a puzzle levels 1-2 still solve is
-- closer the more cells level 1 alone leaves open: without that slope the
-- climb was a blind walk, and a 6x6 often ran out of restarts before
-- stumbling on one that needs a trial.
local function distance(n, region, want, budget)
    tick()
    local P = Solver.newPuzzle(n, region)
    local status, level, st, open1
    if want == 3 then
        status, _, st = Solver.logicSolve(P, 1)
        if status == "contra" then return nil end
        open1 = countOpen(st)
        -- Level 2 picks up where level 1 stalled: same outcome as a fresh
        -- run, without redoing level 1.
        status, level, st = Solver.logicSolve(P, 2, st)
    else
        status, level, st = Solver.logicSolve(P, want)
    end
    if status == "contra" then return nil end
    if status == "solved" then
        if want == 3 then return 1 + 1 / (1 + open1) end
        return level == want and 0 or 1
    end
    -- The techniques stall: is the solution still unique at all?
    local count, exhausted = Solver.countSolutions(P, 2, budget, st)
    if count ~= 1 or exhausted then return nil end
    if want < 3 then return 2 + countOpen(st) end
    -- Hard: levels 1-2 stall; it must still be solvable with trials.
    status = Solver.logicSolve(P, 3, st)
    return status == "solved" and 0 or nil
end

-- Reshape a unique puzzle toward the wanted difficulty: random moves, kept
-- when the puzzle stays acceptable and got no further from the target.
local function climb(n, nb, sol, region, want, moves, budget)
    local d = distance(n, region, want, budget)
    for _ = 1, moves do
        if d == 0 then break end
        local undo = moveOneOf(n, nb, sol, region, emptyCells(sol))
        if not undo then break end
        local nd = distance(n, region, want, budget)
        if nd and (not d or nd <= d) then d = nd else undo() end
    end
    return d
end

local PLANT_TRIES = 4

local function generateBest(n, difficulty, opts)
    local want = Solver.LEVEL[difficulty] or 1
    local nb = neighbours(n)
    -- Restarts are cheap on small grids and hard puzzles are rare there (a
    -- 6x6 seldom needs a trial), so they get more. A cap, not a schedule:
    -- a 6x6 hard takes 7 on average (38 at most in 100 seeds), a 10x10
    -- under 2.
    local max_attempts = opts.max_attempts or math.floor(4000 / (n * n))
    local best, best_d
    for _ = 1, max_attempts do
        -- Best of a few plantings: the denser the dominoes, the smaller the
        -- regions and the likelier the surgery reaches uniqueness (on 10x10,
        -- 21 dominoes made it one time in five, 23 three times in four). Planting
        -- is cheap next to a failed surgery.
        local sol, placed = plantDominoes(n, nb, n * n)
        for _ = 2, PLANT_TRIES do
            local s2, p2 = plantDominoes(n, nb, n * n)
            if p2 > placed then sol, placed = s2, p2 end
        end
        local region = placed >= 2 and buildRegions(n, nb, sol)
        if region and makeUnique(n, nb, sol, region, 2 * n, BUDGET) then
            -- Hard climbs longer: with a slope to follow (see distance),
            -- 8n moves beat both 2n (more restarts) and 16n or more (time
            -- lost on layouts that never get there).
            local d = climb(n, nb, sol, region, want, want == 3 and 8 * n or 10 * n, BUDGET)
            if d and (not best or d < best_d) then
                best, best_d = { n = n, region = region, solution = sol }, d
            end
            if d == 0 then break end
        end
    end
    if best then
        local status, level = Solver.logicSolve(Solver.newPuzzle(n, best.region), 3)
        best.level, best.difficulty = status == "solved" and level or 3, difficulty
    end
    return best
end

-- Returns { n, region = flat, solution = flat 1/0, level, difficulty }, or
-- nil if every attempt failed (callers fall back). `opts.max_attempts`
-- bounds the restarts; the closest unique puzzle found is used if none hits
-- the requested level exactly. `opts.progress(fraction)`, if given, is
-- called as the work goes on (see tick), and with 1 at the end. Every budget
-- is counted in moves or search nodes, never in time: the puzzle is a pure
-- function of the math.random sequence.
function Solver.generate(n, difficulty, opts)
    opts = opts or {}
    progress, work = opts.progress, 0
    local best = generateBest(n, difficulty, opts)
    local report = progress
    progress = nil
    if report then report(1) end
    return best
end

return Solver
