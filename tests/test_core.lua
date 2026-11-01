-- Core tests: generation, uniqueness, logic solvability, timing.
-- Usage (from the plugin folder): luajit tests/test_core.lua . [runs_per_case]
package.path = (arg[1] or ".") .. "/?.lua;" .. package.path
local Core = require("suguru_core")
math.randomseed(os.time())

local failures = 0
local function check(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

-- 2x2 split into two regions of 2: four mutually touching cells, digits {1,2} -> impossible
do
    local T = Core.buildTopology(2, { 1, 1, 2, 2 })
    check(Core.solve(T, { 0, 0, 0, 0 }, 2) == 0, "2x2 with two 2-cell regions must be impossible")
end
-- 2x2 as a single region of 4: 4! = 24 solutions
do
    local T = Core.buildTopology(2, { 1, 1, 1, 1 })
    check(Core.solve(T, { 0, 0, 0, 0 }, 100) == 24, "2x2 single 4-cell region: 24 solutions")
end
-- Invalid layout (region of 6 cells)
check(Core.buildTopology(3, { 1, 1, 1, 1, 1, 1, 2, 2, 2 }) == nil, "6-cell region rejected")

-- Region size mix produced by the generator
do
    local hist, total = { 0, 0, 0, 0, 0 }, 0
    for _ = 1, 20 do
        local region = Core.generateSolution(8, math.random, 4000)
        if region then
            local T = Core.buildTopology(8, region)
            for id = 1, T.R do
                hist[T.rsize[id]] = hist[T.rsize[id]] + 1
                total = total + 1
            end
        end
    end
    local parts = {}
    for s = 1, 5 do
        parts[#parts + 1] = ("%d:%d%%"):format(s, math.floor(100 * hist[s] / math.max(1, total) + 0.5))
    end
    print("region sizes (8x8) " .. table.concat(parts, " "))
end

local SIZES = { 5, 6, 7, 8 }
local DIFFS = { "easy", "medium", "hard" }
local RUNS = tonumber(arg[2]) or 5
for _, n in ipairs(SIZES) do
    for _, d in ipairs(DIFFS) do
        local tmax, tsum, gsum, needWitness = 0, 0, 0, 0
        for _ = 1, RUNS do
            local t0 = os.clock()
            local g = Core.generate(n, d, math.random)
            local dt = os.clock() - t0
            check(g ~= nil, ("generation %dx%d %s"):format(n, n, d))
            if g then
                local T = Core.buildTopology(n, g.region)
                check(T ~= nil, "valid topology")
                check(Core.isValidSolution(T, g.solution), "valid solution")
                local cnt, sol = Core.solve(T, g.puzzle, 2)
                check(cnt == 1, ("unique solution %dx%d %s (found %d)"):format(n, n, d, cnt))
                for i = 1, T.N do
                    check(sol[i] == g.solution[i], "solver = solution")
                    if g.puzzle[i] ~= 0 then
                        check(g.puzzle[i] == g.solution[i], "clue matches solution")
                    end
                end
                local givens = 0
                for i = 1, T.N do
                    if g.puzzle[i] ~= 0 then givens = givens + 1 end
                end
                gsum = gsum + givens
                local rules = (d == "hard") and "witness" or "singles"
                local done, vals = Core.logicSolve(T, g.puzzle, rules)
                check(done, ("solvable by logic (%s) %dx%d %s"):format(rules, n, n, d))
                if done then
                    for i = 1, T.N do
                        check(vals[i] == g.solution[i], "deduction = solution")
                    end
                end
                if not Core.logicSolve(T, g.puzzle, "singles") then
                    needWitness = needWitness + 1
                end
            end
            tsum = tsum + dt
            if dt > tmax then tmax = dt end
        end
        print(("%dx%d %-6s : avg %.2fs  max %.2fs  avg clues %.1f/%d  witness needed %d/%d"):format(
            n, n, d, tsum / RUNS, tmax, gsum / RUNS, n * n, needWitness, RUNS))
    end
end

-- Sample puzzle
local g = Core.generate(6, "medium", math.random)
print("Sample 6x6 (region:digit, . = empty)")
for r = 1, 6 do
    local line = {}
    for c = 1, 6 do
        local i = (r - 1) * 6 + c
        local v = g.puzzle[i]
        line[#line + 1] = string.format("%2d:%s", g.region[i], v == 0 and "." or tostring(v))
    end
    print(table.concat(line, " "))
end
print(failures == 0 and "ALL TESTS PASSED" or ("FAILURES: " .. failures))
os.exit(failures == 0 and 0 or 1)
