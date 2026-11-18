-- plain Lua with a fake engine: a wire that has been still gets collision (one root + a child per metre), it loses it when an end moves or the wire is dropped
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Logging = { info = function() end }
g_currentModDirectory = "/mod/"
local alive, nodes, nextId, links, physics, deleted = {}, {}, 100, {}, {}, 0
local function new() nextId = nextId + 1; alive[nextId] = true; return nextId end
entityExists = function(n) return alive[n] == true end
g_i3DManager = { loadI3DFile = function(_, path) assert(path == "/mod/assets/cableSegment.i3d"); return 1 end }
alive[1], alive[2], alive[3], alive[4] = true, true, true, true
getChildAt = function() return 2 end
getChild = function(_, name) return name == "cableRoot" and 3 or 4 end
clone = function() return new() end
link = function(parent, child) links[child] = parent end
getRootNode = function() return 0 end
setWorldTranslation = function(n, x, y, z) nodes[n] = { x, y, z } end
setWorldDirection = function() end
addToPhysics = function(n) physics[n] = true end
removeFromPhysics = function(n) physics[n] = nil end
delete = function(n) alive[n] = nil; deleted = deleted + 1 end
dofile("scripts/WinchCable.lua")

local wire = {}
WinchCable.update(wire, 16, 0, 0, 0, 0, 0, 10)
check("a new wire has no collision yet", wire.cable.roots == nil)
WinchCable.update(wire, 500, 0, 0, 0, 0, 0, 10)
check("still for 0.5 s: none yet", wire.cable.roots == nil)
WinchCable.update(wire, 600, 0, 0, 0, 0, 0, 10)
local root = (wire.cable.roots or {})[1]
check("still for a second: built, and in physics", root ~= nil and physics[root] == true)
local children = 0
for _, p in pairs(links) do if p == root then children = children + 1 end end
check("a 10 m wire: 3 boxes of 4 m (the root plus 2 children)", children == 2)
WinchCable.update(wire, 16, 0, 0, 0, 0.05, 0, 10)
check("an end moved: the collision is gone at once", wire.cable.roots == nil and physics[root] == nil and not alive[root])
WinchCable.update(wire, 1100, 0, 0, 0, 0.05, 0, 10)
check("and built again after the wait", wire.cable.roots ~= nil)
local second = (wire.cable.roots or {})[1]
WinchCable.remove(wire)
check("the wire dropped: the collision goes with it", wire.cable == nil and not alive[second])
local short = {}
WinchCable.update(short, 16, 0, 0, 0, 0, 0, 0.2)
WinchCable.update(short, 1100, 0, 0, 0, 0, 0, 0.2)
check("a wire shorter than 0.5 m has none (and is not retried every frame)", short.cable.roots == nil and short.cable.failed == true)
WinchCable.ENABLED = false
local off = {}
WinchCable.update(off, 5000, 0, 0, 0, 0, 0, 10)
check("switched off: nothing", off.cable == nil)

-- a long cable is several bodies (the engine takes 40 children per compound at most)
WinchCable.ENABLED = true
local longw = {}
WinchCable.update(longw, 16, 0, 0, 0, 0, 0, 69)
WinchCable.update(longw, 1100, 0, 0, 0, 0, 0, 69)
local nb, maxc = #(longw.cable.roots or {}), 0
for _, r in ipairs(longw.cable.roots or {}) do
    local c = 0
    for _, p in pairs(links) do if p == r then c = c + 1 end end
    maxc = math.max(maxc, c + 1)
end
check("a 69 m cable: 18 boxes of 4 m in one body (the compound limit is 40, a body is capped at 32)", nb == 1 and maxc <= 32)
WinchCable.destroy(longw.cable.roots)
print(string.format("wincable_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
