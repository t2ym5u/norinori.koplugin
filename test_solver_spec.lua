local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Norinori solver", function()
    local Solver

    setup(function()
        Solver = require("solver")
    end)

    -- Every shading of a small grid, checked by the plain rule checker: the
    -- reference the counter and the logical solver are held to.
    local function bruteSolutions(P)
        local N, sols = P.N, {}
        for m = 0, 2 ^ N - 1 do
            local t, x = {}, m
            for i = 1, N do
                t[i] = (x % 2) == 1
                x = math.floor(x / 2)
            end
            if Solver.isValid(P, t) then sols[#sols + 1] = t end
        end
        return sols
    end

    local function randomRegions(n)
        -- Random connected regions: grow from n random seeds.
        local N, region, frontier = n * n, {}, {}
        local nb = Solver.neighbours(n)
        local ids = 0
        while ids < n do
            local i = math.random(N)
            if not region[i] then
                ids = ids + 1
                region[i] = ids
                frontier[#frontier + 1] = i
            end
        end
        while #frontier > 0 do
            local k = math.random(#frontier)
            local i = frontier[k]
            local open = {}
            for _, j in ipairs(nb[i]) do if not region[j] then open[#open + 1] = j end end
            if #open == 0 then
                table.remove(frontier, k)
            else
                local j = open[math.random(#open)]
                region[j] = region[i]
                frontier[#frontier + 1] = j
            end
        end
        return region
    end

    describe("rule checker and counter", function()
        it("agree with brute force on random 4x4 grids", function()
            math.randomseed(11)
            for _ = 1, 25 do
                local P = Solver.newPuzzle(4, randomRegions(4))
                local brute = bruteSolutions(P)
                local count = Solver.countSolutions(P, 1000, 1e6)
                assert.are.equal(#brute, count)
            end
        end)
    end)

    describe("logical solver", function()
        it("never deduces a value some solution contradicts", function()
            math.randomseed(12)
            for _ = 1, 25 do
                local P = Solver.newPuzzle(4, randomRegions(4))
                local brute = bruteSolutions(P)
                local status, _, st = Solver.logicSolve(P, 2)
                if #brute == 0 then
                    assert.are_not.equal("solved", status)
                else
                    assert.are_not.equal("contra", status)
                    for i = 1, P.N do
                        if st[i] ~= Solver.UNKNOWN then
                            for _, s in ipairs(brute) do
                                assert.are.equal(st[i] == Solver.SHADED, s[i])
                            end
                        end
                    end
                end
            end
        end)
    end)

    describe("generate", function()
        local function check(n, diff, seed)
            math.randomseed(seed)
            local p = Solver.generate(n, diff)
            assert.is_truthy(p, ("no puzzle for %dx%d %s seed %d"):format(n, n, diff, seed))
            local P = Solver.newPuzzle(n, p.region)
            -- The planted solution follows the rules...
            assert.is_true(Solver.isValid(P, p.solution))
            -- ...and is the only one, by exhaustive search...
            local count, exhausted = Solver.countSolutions(P, 2, 1e6)
            assert.is_false(exhausted)
            assert.are.equal(1, count)
            -- ...and logic alone finds it: levels 1-2, never a trial.
            local status, level, st, steps = Solver.logicSolve(P, 2)
            assert.are.equal("solved", status)
            assert.are.equal(p.level, level)
            assert.are.equal(p.t2, steps[2])
            for i = 1, P.N do
                assert.are.equal(p.solution[i] == 1, st[i] == Solver.SHADED)
            end
            -- Regions are connected.
            local nb = Solver.neighbours(n)
            for id = 1, P.nregions do
                local cells = P.cells[id]
                local seen, stack, reached = { [cells[1]] = true }, { cells[1] }, 1
                while #stack > 0 do
                    local i = table.remove(stack)
                    for _, j in ipairs(nb[i]) do
                        if not seen[j] and p.region[j] == id then
                            seen[j] = true
                            reached = reached + 1
                            stack[#stack + 1] = j
                        end
                    end
                end
                assert.are.equal(#cells, reached)
            end
            return p
        end

        -- Easy: level 1 only. Medium: 1..MEDIUM_MAX_T2 region analyses.
        -- Hard: at least HARD_MIN_T2 of them -- more work, never a guess.
        local function inWindow(n, diff, p)
            if diff == "easy" then
                assert.are.equal(1, p.level)
                assert.are.equal(0, p.t2)
            elseif diff == "medium" then
                assert.are.equal(2, p.level)
                assert.is_true(p.t2 >= 1 and p.t2 <= Solver.MEDIUM_MAX_T2[n],
                    ("medium %dx%d t2=%d"):format(n, n, p.t2))
            else
                assert.are.equal(2, p.level)
                assert.is_true(p.t2 >= Solver.HARD_MIN_T2[n],
                    ("hard %dx%d t2=%d"):format(n, n, p.t2))
            end
        end

        it("keeps the levels apart: hard needs more analysis than medium", function()
            for _, n in ipairs({ 6, 8, 10 }) do
                assert.is_true(Solver.HARD_MIN_T2[n] > Solver.MEDIUM_MAX_T2[n])
            end
        end)

        it("makes unique, guess-free puzzles in each level's window (6x6, 8x8)", function()
            for _, n in ipairs({ 6, 8 }) do
                for seed = 1, 10 do
                    for _, diff in ipairs({ "easy", "medium", "hard" }) do
                        inWindow(n, diff, check(n, diff, seed))
                    end
                end
            end
        end)

        it("makes unique, guess-free 10x10 puzzles in each level's window", function()
            for seed = 1, 4 do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    inWindow(10, diff, check(10, diff, seed))
                end
            end
        end)

        -- Generous: the Mac takes at most ~0.35 s under LuaJIT; busted's
        -- plain Lua is a few times slower.
        it("stays within a time bound at the largest size", function()
            for seed = 1, 3 do
                for _, diff in ipairs({ "easy", "hard" }) do
                    math.randomseed(100 + seed)
                    local t0 = os.clock()
                    assert.is_truthy(Solver.generate(10, diff))
                    assert.is_true(os.clock() - t0 < 5)
                end
            end
        end)

        it("easy puzzles fall to level 1 alone", function()
            math.randomseed(5)
            local p = Solver.generate(8, "easy")
            local status = Solver.logicSolve(Solver.newPuzzle(8, p.region), 1)
            assert.are.equal("solved", status)
        end)

        -- The Daily Challenge builds today's grid from a fixed seed on every
        -- device: the generator must depend on math.random alone (no clock,
        -- no time budget), and reporting progress must not change a thing.
        it("builds the same puzzle from the same seed, progress reported or not", function()
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                math.randomseed(77)
                local plain = Solver.generate(8, diff)
                math.randomseed(77)
                local again = Solver.generate(8, diff)
                local calls, last, monotone = 0, -1, true
                math.randomseed(77)
                local reported = Solver.generate(8, diff, { progress = function(f)
                    calls = calls + 1
                    if f < last or f < 0 or f > 1 then monotone = false end
                    last = f
                end })
                for _, p in ipairs({ again, reported }) do
                    assert.are.same(plain.region, p.region)
                    assert.are.same(plain.solution, p.solution)
                    assert.are.equal(plain.level, p.level)
                    assert.are.equal(plain.t2, p.t2)
                end
                -- Called as the work goes on, never backwards, ending at 1.
                assert.is_true(calls >= 2)
                assert.is_true(monotone)
                assert.are.equal(1, last)
            end
        end)

        it("builds different puzzles from different seeds", function()
            math.randomseed(1)
            local a = Solver.generate(8, "medium")
            math.randomseed(2)
            local b = Solver.generate(8, "medium")
            assert.are_not.same(a.region, b.region)
        end)
    end)
end)
