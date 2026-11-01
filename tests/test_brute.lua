-- Cross-check: the plugin's solver and deduction rules vs. a naive exhaustive search
-- that shares no code with them.
-- Usage (from the plugin folder): luajit tests/test_brute.lua .
package.path = (arg[1] or ".") .. "/?.lua;" .. package.path
local Core = require("suguru_core")
math.randomseed(os.time())

local fails = 0
local function check(c, m) if not c then fails = fails + 1 print("FAIL: " .. m) end end

-- Enumerates solutions cell by cell, checking the rules directly.
-- Returns the solutions found (up to limit).
local function bruteSolutions(T, givens, limit)
    local g = Core.copyArray(givens, T.N)
    local sols = {}
    local function ok(i, v)
        if v > T.rsize[T.region[i]] then return false end
        for _, j in ipairs(T.peers[i]) do
            if g[j] == v then return false end
        end
        return true
    end
    for i = 1, T.N do
        if g[i] ~= 0 then
            local v = g[i]
            g[i] = 0
            if not ok(i, v) then return sols end
            g[i] = v
        end
    end
    local function rec(i)
        if #sols >= limit then return end
        if i > T.N then sols[#sols + 1] = Core.copyArray(g, T.N) return end
        if g[i] ~= 0 then return rec(i + 1) end
        for v = 1, T.rsize[T.region[i]] do
            if ok(i, v) then
                g[i] = v
                rec(i + 1)
                g[i] = 0
            end
        end
    end
    rec(1)
    return sols
end

local function emptyGrid(N)
    local e = {}
    for i = 1, N do e[i] = 0 end
    return e
end

-- Known impossible case: 2x2 split into two 2-cell regions
do
    local T = Core.buildTopology(2, { 1, 1, 2, 2 })
    check(Core.solve(T, emptyGrid(4), 2) == 0, "2x2 two 2-cell regions impossible (solver)")
    check(#bruteSolutions(T, emptyGrid(4), 2) == 0, "2x2 two 2-cell regions impossible (brute)")
end

-- Solution counts: solver vs. brute force, on random layouts and partial grids
local compared, agreeing = 0, 0
for _ = 1, 400 do
    local n = math.random(4, 5)
    local T = Core.buildTopology(n, Core.randomPartition(n, math.random))
    local cnt, sol = Core.solve(T, emptyGrid(T.N), 1, math.random)
    if cnt == 1 then
        local givens = {}
        local keep = math.random(0, T.N)
        for i = 1, T.N do givens[i] = (math.random(T.N) <= keep) and sol[i] or 0 end
        local a, b = Core.solve(T, givens, 3), #bruteSolutions(T, givens, 3)
        compared = compared + 1
        if a == b then agreeing = agreeing + 1
        else check(false, ("mismatch n=%d solver=%d brute=%d"):format(n, a, b)) end
    end
    local a, b = Core.solve(T, emptyGrid(T.N), 3), #bruteSolutions(T, emptyGrid(T.N), 3)
    compared = compared + 1
    if a == b then agreeing = agreeing + 1
    else check(false, ("mismatch (empty) n=%d solver=%d brute=%d"):format(n, a, b)) end
end
print(("solution counts compared: %d, agreeing: %d"):format(compared, agreeing))

-- Soundness of both rule sets: on partial grids drawn from a solution, every deduced
-- digit must match EVERY solution (all enumerated).
do
    local placedChecks, bad = 0, 0
    for _ = 1, 150 do
        local n = math.random(4, 6)
        local region, sol = Core.generateSolution(n, math.random, 4000)
        if region then
            local T = Core.buildTopology(n, region)
            local givens = {}
            local keep = math.random(0, T.N)
            for i = 1, T.N do givens[i] = (math.random(T.N) <= keep) and sol[i] or 0 end
            local sols = bruteSolutions(T, givens, 50)
            if #sols < 50 then
                for _, rules in ipairs({ "singles", "witness" }) do
                    local _, vals = Core.logicSolve(T, givens, rules)
                    for i = 1, T.N do
                        if givens[i] == 0 and vals[i] ~= 0 then
                            placedChecks = placedChecks + 1
                            for _, s in ipairs(sols) do
                                if s[i] ~= vals[i] then
                                    bad = bad + 1
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    check(bad == 0, "wrong deductions: " .. bad)
    print(("deductions checked: %d, wrong: %d"):format(placedChecks, bad))
end

print(fails == 0 and "VALIDATION PASSED" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
