-- run: lua tests/winchwire_test.lua   (fake engine: wires laid between bridge pieces, reeled in, joined)
local nodes, forces = {}, {}
function entityExists(n) return nodes[n] ~= nil end
function getWorldTranslation(n) return nodes[n][1], nodes[n][2], nodes[n][3] end
local lin = { 0, 0, 0 }
function getLinearVelocity() return lin[1], lin[2], lin[3] end
local angv = { 0, 0, 0 }
function getAngularVelocity() return angv[1], angv[2], angv[3] end
function setAngularVelocity(_, x, y, z) angv = { x, y, z } end
function addForce(node, fx, fy, fz) forces[#forces + 1] = { node, fx, fy, fz } end
Logging = { info = function() end }
g_inputBinding = { setActionEventActive = function(_, id, on) end }
local attached, linked, notes = {}, {}, {}
WinchHand = { ROPE = false, hand = 1, pullMass = function() return 0.5 end, notify = function(t) notes[#notes + 1] = t end, labelOf = function(v) return v.name end,
              attachPair = function(h, e) attached[#attached + 1] = { h, e }; return true end }
dofile("scripts/WinchWire.lua")
local pass, fail = 0, 0
local function check(name, cond) if cond then pass = pass + 1 else fail = fail + 1; print("FAIL " .. name) end end
nodes[1], nodes[2] = { 0, 0, 0 }, { 2, 0, 0 }              -- piece A's hitches
nodes[11], nodes[12] = { 0, 0, 3 }, { 2, 0, 3 }            -- piece B's eyes, 3 m away
nodes[50], nodes[60] = { 1, 0, 0 }, { 1, 0, 3 }
local function bridgeLinkPair(self, other, a, b) linked[#linked + 1] = { a, b }; return true end
local A = { name = "A", components = { { node = 50 } }, bridgeLinkPair = bridgeLinkPair }
local B = { name = "B", components = { { node = 60 } }, bridgeLinkPair = bridgeLinkPair }
local msg = WinchWire.lay({ vehicle = A, node = 1, kind = "hitch", index = 1 }, { vehicle = B, node = 11, kind = "drawbar eye", index = 1 }, WinchHand.labelOf)
check("a wire is laid, nothing moves", #WinchWire.wires == 1 and #forces == 0 and msg:find("1 of 2") ~= nil)
check("the joints of a wire are marked", WinchWire.isWired(1) and WinchWire.isWired(11) and not WinchWire.isWired(2))
WinchWire.lay({ vehicle = B, node = 12, kind = "drawbar eye", index = 2 }, { vehicle = A, node = 2, kind = "hitch", index = 2 }, WinchHand.labelOf)
check("the second wire is the other way round: hitch side and eye side are sorted out", WinchWire.wires[2].hitch.node == 2 and WinchWire.wires[2].eye.node == 12)
WinchWire.update(16)
check("no key: no force", #forces == 0)
WinchWire.press()
WinchWire.update(100)
check("a press shorter than HOLD_MS does not reel", #forces == 0)
check("it is a click when let go early", WinchWire.release() == false and WinchWire.pressMs == nil)
WinchWire.press()
WinchWire.update(200); WinchWire.update(200)
check("held past HOLD_MS: reeling, four forces", #forces == 4 and WinchWire.release() == true)
forces = {}
WinchWire.update(16)
check("button up: no force again", #forces == 0)
check("press is wanted only with wires, nothing hooked", WinchWire.wantsPress(false) == true and WinchWire.wantsPress(true) == false)
WinchWire.setReelInput(1)
WinchWire.update(16)
check("K: both pieces are pulled, four forces (two wires, two pieces each)", #forces == 4)
local toward = true
for _, f in ipairs(forces) do if (f[1] == 50 and f[4] <= 0) or (f[1] == 60 and f[4] >= 0) then toward = false end end
check("each piece is pulled towards the other", toward)
check("a little lift (friction)", forces[1][3] > 0)
local single = math.abs(forces[1][4])
forces = {}
A.getTotalMass = function(_, onlyThis) return onlyThis and 0.5 or 4 end            -- 3.5 t of grates hang on A
WinchWire.update(16)
local chained = 0
for _, f in ipairs(forces) do if f[1] == 50 then chained = math.max(chained, math.abs(f[4])) end end
check("a chain hanging on the piece is pulled with its weight (8x, within the cap of 12x)", single > 0 and chained > single * 6 and chained < single * 9)
A.getTotalMass = function(_, onlyThis) return onlyThis and 0.5 or 400 end
forces = {}
WinchWire.update(16)
local capped = 0
for _, f in ipairs(forces) do if f[1] == 50 then capped = math.max(capped, math.abs(f[4])) end end
check("the pull is capped at CHAIN_CAP times the piece's own mass", capped < single * 13)
A.getTotalMass = nil
-- the ratchet: reeled in, then let go: a wire cannot be pulled back out
WinchWire.setReelInput(0)
forces = {}
WinchWire.update(16)
check("let go at the same length: no force", #forces == 0)
nodes[11], nodes[12] = { 0, 0, 3.5 }, { 2, 0, 3.5 }
WinchWire.update(16)
check("pulled out 50 cm: both pieces are pulled back, four forces", #forces == 4)
local back = true
for _, f in ipairs(forces) do if (f[1] == 50 and f[4] <= 0) or (f[1] == 60 and f[4] >= 0) then back = false end end
check("each towards the other", back)
nodes[11], nodes[12] = { 0, 0, 3 }, { 2, 0, 3 }
WinchWire.setReelInput(1)
-- a pinned piece does not get a force
forces = {}
A.hdPinned = true
WinchWire.update(16)
check("pinned: only the loose piece is pulled", #forces == 2 and forces[1][1] == 60)
A.hdPinned = nil
-- not done while a wire is long, done when all are short
nodes[11], nodes[12] = { 0, 0, 0.04 }, { 2, 0, 0.5 }
WinchWire.update(16)
check("one wire still long: not joined", #attached == 0 and #WinchWire.wires == 2)
nodes[12] = { 2, 0, 0.03 }
WinchWire.update(16)
check("all wires short: first by the game's attach, the second by BridgeLink", #attached == 1 and attached[1][1].node == 1 and #linked == 1 and linked[1][1] == 2 and linked[1][2] == 12)
check("the wires are gone, it says so", #WinchWire.wires == 0 and notes[#notes]:find("joined") ~= nil)
-- hitched already: only BridgeLink
attached, linked = {}, {}
B.getAttacherVehicle = function() return A end
WinchWire.lay({ vehicle = A, node = 2, kind = "hitch", index = 2 }, { vehicle = B, node = 12, kind = "drawbar eye", index = 2 }, WinchHand.labelOf)
nodes[12] = { 2, 0, 0.0 }
WinchWire.update(16)
check("already hitched: the wire goes to BridgeLink only", #attached == 0 and #linked == 1)
-- clear
WinchWire.lay({ vehicle = A, node = 1, kind = "hitch", index = 1 }, { vehicle = B, node = 11, kind = "drawbar eye", index = 1 }, WinchHand.labelOf)
nodes[11] = { 0, 0, 5 }
check("Ctrl and a click: the wires of a piece go", WinchWire.clear(A) == 1 and #WinchWire.wires == 0)
-- a deleted piece takes its wire
WinchWire.lay({ vehicle = A, node = 1, kind = "hitch", index = 1 }, { vehicle = B, node = 11, kind = "drawbar eye", index = 1 }, WinchHand.labelOf)
B.isDeleted = true
WinchWire.update(16)
check("a deleted piece: the wire goes", #WinchWire.wires == 0)
-- two wires of different length between the same pieces: the shorter one is reeled gently, so both run out together
B.isDeleted = nil; WinchWire.wires = {}; forces = {}
nodes[11], nodes[12] = { 0, 0, 4 }, { 2, 0, 1 }
WinchWire.lay({ vehicle = A, node = 1, kind = "hitch", index = 1 }, { vehicle = B, node = 11, kind = "drawbar eye", index = 1 }, WinchHand.labelOf)
WinchWire.lay({ vehicle = A, node = 2, kind = "hitch", index = 2 }, { vehicle = B, node = 12, kind = "drawbar eye", index = 2 }, WinchHand.labelOf)
WinchWire.setReelInput(1)
WinchWire.update(16)
local longF, shortF
for _, f in ipairs(forces) do
    if f[1] == 50 then
        local mag = math.abs(f[4])
        if longF == nil then longF = mag else shortF = mag end
    end
end
check("the short wire (1 m) pulls with a quarter of the long one's force (4 m)", longF ~= nil and shortF ~= nil and math.abs(shortF / longF - 0.25) < 0.05)

-- a latch wire (two poles): laid, long, joins nothing even when the ends are together
WinchWire.clear(nil)
attached, linked, notes = {}, {}, {}
nodes[70], nodes[71] = { 0, 1.9, 0 }, { 66, 1.9, 4 }       -- two latches 66 m apart
nodes[72], nodes[73] = { 0, 0, 0 }, { 66, 0, 4 }
local P1 = { name = "pole 1", components = { { node = 72 } } }
local P2 = { name = "pole 2", components = { { node = 73 } } }
local lmsg = WinchWire.lay({ vehicle = P1, node = 70, kind = "winch latch", index = 1 }, { vehicle = P2, node = 71, kind = "winch latch", index = 1 }, WinchHand.labelOf, true)
check("a latch wire between two poles 66 m apart is laid", #WinchWire.wires == 1 and WinchWire.wires[1].latch == true and lmsg:find("walk it", 1, true) ~= nil and WinchWire.LATCH_MAX_M >= 66)
nodes[71] = { 0.05, 1.9, 0 }                              -- the ends together (under SNAP_M): a bridge wire would be joined now
WinchWire.update(16)
check("a latch wire joins nothing, whatever the distance", #attached == 0 and #linked == 0 and #WinchWire.wires == 1)
WinchWire.clear(nil)

-- the swing: a piece on a reeled wire that moves sideways is slowed across the wire, and its spin dies down
WinchWire.clear(nil)
forces = {}
nodes[1], nodes[11], nodes[50], nodes[60] = { 0, 0, 0 }, { 0, 0, 3 }, { 0, 0, 0 }, { 0, 0, 3 }
WinchWire.lay({ vehicle = A, node = 1, kind = "hitch", index = 1 }, { vehicle = B, node = 11, kind = "drawbar eye", index = 1 }, WinchHand.labelOf)
WinchWire.wires[1].maxLen = 3
lin, angv = { 2, 0, 0 }, { 0, 3, 0 }                        -- sideways (the wire runs along z) at 2 m/s, turning at 3 rad/s
WinchWire.update(16)
local swingF
for _, f in ipairs(forces) do if f[1] == 50 and math.abs(f[2]) > 0 then swingF = f end end
check("a swinging piece on a reeled wire gets a force against its sideways speed", swingF ~= nil and swingF[2] < 0 and math.abs(swingF[4]) < 1e-9)
check("... and its spin is damped (the test's one fake body serves both pieces: twice)", angv[2] < 3 and angv[2] > 2.5)
lin, angv = { 0, 0, 1 }, { 0, 0, 0 }                         -- along the wire only
forces = {}
WinchWire.update(16)
local along = false
for _, f in ipairs(forces) do if f[1] == 50 and (math.abs(f[2]) > 1e-9 or math.abs(f[4]) > 1e-9) and f[2] ~= nil and f[1] == 50 and math.abs(f[2]) > 1e-9 then along = true end end
check("speed along the wire is not damped sideways", not along)
lin = { 0, 0, 0 }
WinchWire.clear(nil)

-- saved latch wires are laid again when both vehicles exist
WinchWire.clear(nil)
local vehs = {}
local function sv(id, node) return { name = id, getUniqueId = function() return id end, isDeleted = false, components = { { node = node } }, spec_attacherJoints = { attacherJoints = { [1] = { jointTransform = node + 100 } } } } end
nodes[80], nodes[180], nodes[81], nodes[181] = { 0, 0, 0 }, { 0, 1.9, 0 }, { 30, 0, 0 }, { 30, 1.9, 0 }
vehs["idA"], vehs["idB"] = sv("idA", 80), sv("idB", 81)
g_currentMission = { vehicleSystem = { getVehicleByUniqueId = function(_, id) return vehs[id] end } }
WinchWire.pending, WinchWire.pendingMs = { { a = "idA", ai = 1, b = "idB", bi = 1 } }, 0
WinchWire.update(16)
check("a saved latch wire is laid again when both vehicles are there", #WinchWire.wires == 1 and WinchWire.wires[1].latch == true and #WinchWire.pending == 0)
WinchWire.pending = { { a = "idA", ai = 1, b = "idB", bi = 1 } }
WinchWire.update(16)
check("... and not twice between the same two latches", #WinchWire.wires == 1)
WinchWire.clear(nil)
WinchWire.pending, WinchWire.pendingMs = { { a = "idA", ai = 1, b = "idGone", bi = 1 } }, 0
WinchWire.update(16)
check("a wire whose vehicle is not there yet waits", #WinchWire.wires == 0 and #WinchWire.pending == 1)
WinchWire.update(70000)
check("... and is given up after a minute", WinchWire.pending == nil)
print(string.format("winchwire_test: %d/%d passed", pass, pass + fail))
os.exit(fail == 0 and 0 or 1)
