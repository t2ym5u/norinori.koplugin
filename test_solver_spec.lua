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
end)
