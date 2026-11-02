-- plain Lua with a fake engine: the winch rope picks the attacher joints of other vehicles, the hook links to them, vehicle attachments are left out of the savegame
local passed, failed = 0, 0
local realPrint = print
local log = {}
print = function(text) log[#log + 1] = text end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

Utils = {
    appendedFunction = function(old, new) return function(...) local r = old(...); new(...); return r end end,
    overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end,
}
-- the game's winch and hook, as far as this mod touches them
local updates, saved = 0, {}
Winch = {
    TREE_RAYCAST_DISTANCE = 5,
    onPostUpdate = function() updates = updates + 1 end,
    saveToXMLFile = function(self, xmlFile, key) local n = 0; for _, rope in ipairs(self.spec_winch.ropes) do n = n + #rope.attachedTrees end; saved[#saved + 1] = n end,
}
local linked = {}
ForestryHook = { mountToTree = function(self, id, x, y, z) return "tree", 0, 0 end }
ForestryHook.link = function(self, node, ...) linked[#linked + 1] = node end
-- the attach key's handler: calls the winch's attach and attaches (the tree mass check is the rope's maxTreeMass)
local attachCalls, massSeen = 0, nil
WinchAttachTreeActivatable = { onAttachTree = function(self)
    attachCalls = attachCalls + 1
    massSeen = self.rope.maxTreeMass
    if self.rope.maxTreeMass >= (self.mass or 0) then self.rope.attachedTrees[#self.rope.attachedTrees + 1] = { treeId = self.vehicle.spec_winch.treeRaycast.lastValidTree } end
end }
local consoles = {}
addConsoleCommand = function(name, _, method, target) consoles[name] = function(...) return target[method](target, ...) end end

-- the world: the player's camera at (0, 1.7, 0) looking along +x
local CAM = 1
local nodes = { [CAM] = { 0, 1.7, 0 } }
getWorldTranslation = function(n) local p = nodes[n]; return p[1], p[2], p[3] end
entityExists = function(n) return nodes[n] ~= nil end
localDirectionToWorld = function(node, x, y, z) if node == CAM then return 1, 0, 0 end return x, y, z end
g_localPlayer = { isControlled = true, handTool = false, getCurrentCameraNode = function() return CAM end, getIsHoldingHandTool = function(self) return self.handTool end }

local function marker() return { active = false, pos = nil, setIsActive = function(self, a) self.active = a end, setPosition = function(self, ...) self.pos = { ... } end } end
local function newVehicle(name, root, extra)
    local v = { configFileName = name, isDeleted = false }
    function v:getRootVehicle() return root or self end
    function v:getName() return name end
    function v:getParentComponent(node) return (self.components or {})[node] or 0 end
    for k, val in pairs(extra or {}) do v[k] = val end
    return v
end

-- the winch (and the tractor it hangs on: the same group), a tractor, a trailer
local rope = { isAttachModeActive = true, attachMarker = marker(), attachedTrees = {}, colors = {} }
rope.setupRope = { setEmissiveColor = function(self, ...) rope.colors[#rope.colors + 1] = { ... } end }
local carrier = newVehicle("carrierTractor")
local winch = newVehicle("winch", carrier, { isServer = true, spec_winch = { treeRaycast = { hasStarted = false, lastValidTree = nil, startPos = { 0, 1, 0 }, maxDistance = 60, treeTargetPos = { 0, 0, 0 }, treeCenterPos = { 0, 0, 0 }, treeUp = { 0, 1, 0 } }, ropes = { rope } } })
nodes[10] = { 3, 1.6, 0.1 }                       -- the carrier's own hitch: same group, must never be picked
carrier.spec_attacherJoints = { attacherJoints = { { jointTransform = 10, jointComponent = 100 } } }
local tractor = newVehicle("farmTractor", nil, { components = { [20] = 200 } })
nodes[20] = { 3, 1.6, 1.0 }                       -- the tractor's rear hitch, 0.9 m from the ray
tractor.spec_attacherJoints = { attacherJoints = { { jointTransform = 20, jointComponent = 200 } } }
local trailer = newVehicle("flatTrailer", nil, { components = { [30] = 300, [31] = 0 } })
nodes[30] = { 4, 1.5, 0.15 }                      -- the trailer's drawbar eye, 0.15 m from the ray, 4 m away
trailer.spec_attachable = { inputAttacherJoints = { { node = 30 } } }
g_currentMission = { vehicleSystem = { vehicles = { winch, carrier, tractor, trailer } } }

dofile("scripts/WinchTow.lua")
local tr = winch.spec_winch.treeRaycast
check("loaded: the update, the hook and the save are patched", WinchTow.hooked == true and consoles.wtProbe ~= nil)

Winch.onPostUpdate(winch, 16)
check("the vanilla update still runs", updates == 1)
check("in attach mode the drawbar eye 0.15 m from the view ray is picked: its component is the valid target (a physics body: getMass and the physics rope work on it)", tr.lastValidTree == 300)
check("... its position and up direction are the target for the marker, the ring has the marker radius", tr.treeTargetPos[1] == 4 and tr.treeCenterPos[2] == 1.5 and tr.treeUp[2] == 1 and tr.treeRadius == WinchTow.MARKER_RADIUS_M)
check("... the marker (the green ring) is on at the joint and the rope is green", rope.attachMarker.active == true and rope.attachMarker.pos[1] == 4 and rope.attachMarker.pos[7] == WinchTow.MARKER_RADIUS_M and rope.colors[#rope.colors][2] == 1)
check("... the tree raycast is held back (its callback would reset the target every frame)", tr.hasStarted == true)
check("the winch's own group is never a target (its tractor's hitch, 0.1 m from the ray, is skipped)", tr.lastValidTree ~= 100)

-- a nearer joint wins
nodes[30] = { 4, 1.5, 0.3 }
nodes[20] = { 2, 1.7, 0.05 }
Winch.onPostUpdate(winch, 16)
check("of two joints near the ray the one nearest to it is picked", tr.lastValidTree == 200)
-- too far along the view
nodes[20] = { 6, 1.7, 0 }
nodes[30] = { 7, 1.7, 0 }
Winch.onPostUpdate(winch, 16)
check("beyond the raycast distance (5 m) nothing is picked, and what was picked is let go", tr.lastValidTree == nil and tr.hasStarted == false and rope.attachMarker.active == false)
-- out of the rope's reach
nodes[20] = { 3, 1.7, 0 }
tr.maxDistance = 1
Winch.onPostUpdate(winch, 16)
check("a joint the rope cannot reach (further from the winch's rope node than its length) is not a target", tr.lastValidTree == nil)
tr.maxDistance = 60
Winch.onPostUpdate(winch, 16)
check("... and is one within reach", tr.lastValidTree == 200)
-- a tree is targeted: vanilla's
tr.lastValidTree, tr.hasStarted = 555, false
rope.rfTowActive = false
Winch.onPostUpdate(winch, 16)
check("a tree is targeted (vanilla's raycast): nothing is overwritten", tr.lastValidTree == 555 and tr.hasStarted == false)
tr.lastValidTree = nil
-- a joint with no component cannot be picked (no body to pull)
nodes[20] = nil
nodes[30] = { 3, 1.7, 0 }
trailer.spec_attachable.inputAttacherJoints[1].node = 31
nodes[31] = { 3, 1.7, 0 }
Winch.onPostUpdate(winch, 16)
check("a joint whose node has no component of the vehicle is ignored", tr.lastValidTree == nil)
trailer.spec_attachable.inputAttacherJoints[1].node = 30
Winch.onPostUpdate(winch, 16)
check("(the same trailer with a proper node is picked)", tr.lastValidTree == 300)
-- looking away, attach mode off, a hand tool
nodes[30] = { 3, 1.7, 3 }
Winch.onPostUpdate(winch, 16)
check("looking away from every joint lets go", tr.lastValidTree == nil and tr.hasStarted == false and rope.rfTowActive == false)
nodes[30] = { 3, 1.7, 0 }
Winch.onPostUpdate(winch, 16)
rope.isAttachModeActive = false
Winch.onPostUpdate(winch, 16)
check("attach mode off lets go too (the vanilla attach input does that after the attach)", tr.lastValidTree == nil and tr.hasStarted == false and rope.attachMarker.active == false)
rope.isAttachModeActive = true
g_localPlayer.handTool = true
Winch.onPostUpdate(winch, 16)
check("a hand tool in the player's hands: nothing is picked (as for trees)", tr.lastValidTree == nil)
g_localPlayer.handTool = false
WinchTow.ENABLED = false
Winch.onPostUpdate(winch, 16)
check("switched off: nothing", tr.lastValidTree == nil)
WinchTow.ENABLED = true
winch.isServer = false
Winch.onPostUpdate(winch, 16)
check("a client does nothing (single player only)", tr.lastValidTree == nil)
winch.isServer = true

-- the hook
Winch.onPostUpdate(winch, 16)
check("(picked again)", tr.lastValidTree == 300)
local hook = setmetatable({}, { __index = ForestryHook })
local x, y, z = ForestryHook.mountToTree(hook, 300, 3, 1.7, 0)
check("mounting the hook to one of our targets links it to the joint node (a tree would get a belt) and says it worked", linked[#linked] == 30 and x == 3 and y == 1.7 and z == 0 and hook.splitShapeId == nil)
local result = ForestryHook.mountToTree(hook, 12345, 0, 0, 0)
check("mounting to anything else is the game's own", result == "tree" and #linked == 1)
nodes[30] = nil
check("a joint node that is gone falls back to the game's own (and a tree check would fail there)", ForestryHook.mountToTree(hook, 300, 0, 0, 0) == "tree")
nodes[30] = { 3, 1.7, 0 }

-- the attach key: a vehicle weighing more than the rope's tree limit is attached all the same, the limit comes back
local activatable = { vehicle = winch, rope = rope, mass = 30 }
rope.maxTreeMass, rope.maxNumTrees = 8.6, 4
getMass = function() return 30 end
local attachedBefore = #rope.attachedTrees
WinchAttachTreeActivatable.onAttachTree(activatable)
check("the attach key on a joint: the tree mass limit is lifted for the call (a 30 t trailer against 8.6 t), so it attaches, and the limit is back after", massSeen == math.huge and rope.maxTreeMass == 8.6 and #rope.attachedTrees == attachedBefore + 1)
check("... and the log says it, with the weight and the limit", (function() for _, line in ipairs(log) do if line:find("attach key on the", 1, true) and line:find("30.0 t", 1, true) and line:find("8.6 t", 1, true) then return true end end return false end)())
rope.attachedTrees[#rope.attachedTrees] = nil
tr.lastValidTree = 555
massSeen = nil
WinchAttachTreeActivatable.onAttachTree(activatable)
check("a tree is attached by the game's own check (limit untouched)", massSeen == 8.6)
tr.lastValidTree = 300
rope.attachedTrees = {}

-- the support leg: a vehicle held by a rope has its leg pulled up (the game's support animation backwards), let go it goes down again
local played = {}
trailer.spec_attachable.supportAnimations = { { animationName = "supportLeg" } }
trailer.playAnimation = function(self, name, speed, time, noEvent) played[#played + 1] = { name, speed, time, noEvent } end
rope.attachedTrees = { { treeId = 300 } }
Winch.onPostUpdate(winch, 16)
check("a vehicle held by the rope gets its support leg pulled up: the support animation played backwards, without a network event", #played == 1 and played[1][1] == "supportLeg" and played[1][2] == -1 and played[1][3] == nil and played[1][4] == true)
Winch.onPostUpdate(winch, 16)
check("... once, not every frame", #played == 1)
rope.attachedTrees = {}
Winch.onPostUpdate(winch, 16)
check("let go of the rope: the leg goes down again (forwards)", #played == 2 and played[2][2] == 1)
Winch.onPostUpdate(winch, 16)
check("... and that is once too", #played == 2)
trailer.getAttacherVehicle = function() return carrier end
rope.attachedTrees = { { treeId = 300 } }
Winch.onPostUpdate(winch, 16)
check("a vehicle that is attached to another one is left alone (its own attachment has the say over the leg)", #played == 2)
trailer.getAttacherVehicle = nil
rope.attachedTrees = {}
Winch.onPostUpdate(winch, 16)
check("... and when it is let go the leg is not put down (it was never pulled up by the rope)", #played == 2)

-- the savegame
rope.attachedTrees = { { treeId = 777 }, { treeId = 300 }, { treeId = 888 } }
Winch.saveToXMLFile(winch, {}, "k")
check("a vehicle attachment is left out of the savegame (the game cannot restore it from a split shape id), the trees are saved", saved[#saved] == 2)
check("... and is back in the rope afterwards, in its place", #rope.attachedTrees == 3 and rope.attachedTrees[2].treeId == 300 and rope.attachedTrees[1].treeId == 777 and rope.attachedTrees[3].treeId == 888)
local realSave = saved
rope.attachedTrees = { { treeId = 300 } }
Winch.saveToXMLFile(winch, {}, "k")
check("only a vehicle attachment: nothing to save, and it comes back", saved[#saved] == 0 and #rope.attachedTrees == 1)
rope.attachedTrees = {}

-- the probe
nodes[20] = { 2, 1.7, 0.05 }
nodes[30] = { 4, 1.5, 0.15 }
local text = consoles.wtProbe()
check("wtProbe lists the joints in front of you, nearest to the view ray first, with their distance", text:find("farmTractor", 1, true) ~= nil and text:find("flatTrailer", 1, true) ~= nil and text:find("0.05 m off the ray", 1, true) ~= nil
    and text:find("farmTractor", 1, true) < text:find("flatTrailer", 1, true))
trailer.spec_attachable.inputAttacherJoints[1].node = 31
nodes[31] = { 4, 1.5, 0.15 }
check("... and says which joint has no component (cannot be picked)", consoles.wtProbe():find("NO component", 1, true) ~= nil)
-- a linkage joint (implement type) is no tow point: not listed for picking, but the probe says why it is skipped
AttacherJoints = { JOINTTYPE_IMPLEMENT = 1, JOINTTYPE_TRAILER = 2, jointTypeNameToInt = { implement = 1, trailer = 2 } }
tractor.spec_attacherJoints = { attacherJoints = { { jointTransform = 20, jointComponent = 200, jointType = 1 }, { jointTransform = 21, jointComponent = 200, jointType = 2 } } }
nodes[21] = { 3, 0.5, 1.0 }
local joints, all = WinchTow.jointsOf(tractor), WinchTow.jointsOf(tractor, true)
check("an implement-type joint (3 point or front linkage, in the air) is not a tow point: only the trailer-type joint is listed", #joints == 1 and joints[1].node == 21 and joints[1].jointType == "trailer")
check("... the probe lists both and says which one is skipped", #all == 2 and consoles.wtProbe():find("a linkage, not a tow point: skipped", 1, true) ~= nil)
tractor.spec_attacherJoints.attachedImplements = { { jointDescIndex = 1 } }
check("... but an implement joint something is hitched to right now is listed again (it is where the hitched thing is)", #WinchTow.jointsOf(tractor) == 2)
tractor.spec_attacherJoints.attachedImplements = nil
tractor.spec_attacherJoints.attacherJoints = { { jointTransform = 20, jointComponent = 200, jointType = 1 } }
check("... and a vehicle with no tow point at all keeps its linkage joints (whatever the winch allows)", #WinchTow.jointsOf(tractor) == 1 and WinchTow.jointsOf(tractor)[1].skipped == nil)
tractor.spec_attacherJoints.attacherJoints = { { jointTransform = 20, jointComponent = 200, jointType = 1 }, { jointTransform = 21, jointComponent = 200, jointType = 2 } }
WinchTow.TOW_JOINTS_ONLY = false
check("... TOW_JOINTS_ONLY = false lists every joint again", #WinchTow.jointsOf(tractor) == 2)
WinchTow.TOW_JOINTS_ONLY = true
AttacherJoints = nil
nodes[10], nodes[20], nodes[21], nodes[30], nodes[31] = nil, nil, nil, nil, nil
check("nothing in front: it says so", consoles.wtProbe():find("no attacher joint within 15 m", 1, true) ~= nil)

print = realPrint
print(string.format("winchtow_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
