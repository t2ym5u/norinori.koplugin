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
                local status, _, st = Solver.logicSolve(P, 3)
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
            -- ...and logic alone (up to single-cell trials) finds it.
            local status, level, st = Solver.logicSolve(P, 3)
            assert.are.equal("solved", status)
            assert.are.equal(p.level, level)
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

        it("makes unique, logic-solvable 6x6 puzzles at the requested level", function()
            for seed = 1, 12 do
                for _, diff in ipairs({ "easy", "medium" }) do
                    local p = check(6, diff, seed)
                    assert.are.equal(Solver.LEVEL[diff], p.level)
                end
            end
        end)

        it("makes hard puzzles that need a trial (8x8)", function()
            for seed = 1, 4 do
                local p = check(8, "hard", seed)
                assert.are.equal(3, p.level)
            end
        end)

        it("makes unique 8x8 and 10x10 puzzles", function()
            for seed = 1, 4 do
                assert.are.equal(1, check(8, "easy", seed).level)
                assert.are.equal(2, check(8, "medium", seed).level)
            end
            for seed = 1, 2 do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    assert.are.equal(Solver.LEVEL[diff], check(10, diff, seed).level)
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
            for _, diff in ipairs({ "easy", "hard" }) do
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
