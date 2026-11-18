-- plain Lua with a fake engine: the hand winch hooks onto a joint, pulls the vehicle towards the player at 2 km/h at most, and lets go
local passed, failed = 0, 0
local realPrint = print
local log = {}
print = function(text) log[#log + 1] = text end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

local nodes = { [1] = { 0, 1.7, 0 }, [10] = { 5, 0.6, 0 }, [20] = { 0, 1.2, 0 } }         -- the camera, the joint (5 m ahead), the hand
getWorldTranslation = function(n) local p = nodes[n]; return p[1], p[2], p[3] end
entityExists = function(n) return nodes[n] ~= nil end
localDirectionToWorld = function() return 1, 0, 0 end
g_localPlayer = { isControlled = true, getCurrentCameraNode = function() return 1 end }
local velocity = { 0, 0, 0 }
local forces = {}
getLinearVelocity = function() return velocity[1], velocity[2], velocity[3] end
getMass = function() return 6 end
addForce = function(node, fx, fy, fz, px, py, pz, isLocal) forces[#forces + 1] = { node, fx, fy, fz, px, py, pz, isLocal } end
local lines = {}
drawDebugLine = function(...) lines[#lines + 1] = { ... } end
local brakeCalls = {}
local vehicle = { isDeleted = false, spec_wheels = { wheels = { {}, {} } }, getName = function() return "Old Trailer" end, brake = function(self, pedal) brakeCalls[#brakeCalls + 1] = pedal end }
local picked = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" }
local supportCalls = {}
WinchTow = { pick = function(winch, ox, oy, oz, dx, dy, dz, range) WinchTow.range = range; return WinchTow.result end, result = picked,
    setSupport = function(vehicle, up) supportCalls[#supportCalls + 1] = up and "up" or "down"; return true end }
local listeners = {}
addModEventListener = function(l) listeners[#listeners + 1] = l end
g_currentMission = nil

dofile("scripts/WinchHand.lua")
WinchHand.POLE = false                       -- (the old pull is tested first: the pole has its own block at the end)
WinchHand.TONGUE_POLE = false                 -- (the carry is tested first: the tongue on the pole has its own check at the end of the carry block)
check("the mod listens to update and draw", listeners[1] == WinchHand)

-- nothing hooked: nothing happens
WinchHand.update(WinchHand, 16)
check("not hooked: no force", #forces == 0)
WinchTow.result = nil
check("looking at nothing: it says what to look at", WinchHand.toggle():find("look at an attacher joint", 1, true) ~= nil and WinchHand.target == nil)
WinchTow.result = picked
check("the action hooks onto the joint in view, within 6 m, and says what to do", WinchHand.toggle():find("hooked to the drawbar eye of Old Trailer", 1, true) ~= nil and WinchHand.target == picked and WinchTow.range == 6)
check("hooking pulls the support leg up", supportCalls[#supportCalls] == "up")

-- the player stands at x 0, the joint is 5 m away: the pull is towards the player, along -x, at the joint, mass * accel
WinchHand.update(WinchHand, 16)
local f = forces[#forces]
check("pulling: the brake is let off (vehicle:brake(0))", brakeCalls[#brakeCalls] == 0)
check("pulling: a force on the joint's body, towards the player (-x), applied at the joint, in world coordinates",
    f ~= nil and f[1] == 100 and f[2] < 0 and f[3] == 0 and math.abs(f[4]) < 1e-9 and f[5] == 5 and f[6] == 0.6 and f[7] == 0 and f[8] == false)
check("... with the most force when the vehicle is standing: 6 t * (its pull speed over 0.3 s, at most the 3 m/s2 limit)", math.abs(-f[2] - 6 * math.min(WinchHand.ACCEL_MS2, WinchHand.pullSpeed(6) / 0.3)) < 1e-9)
velocity = { -WinchHand.pullSpeed(6), 0, 0 }
forces = {}
WinchHand.update(WinchHand, 16)
check("at the pull speed towards the player: no more force (the speed is the limit)", #forces == 0)
velocity = { -3, 0, 0 }
WinchHand.update(WinchHand, 16)
check("faster than the pull speed: no force either (it is not braked, the vehicle's own friction does that)", #forces == 0)
velocity = { 0.5, 0, 0 }
WinchHand.update(WinchHand, 16)
check("moving away from the player: pulled back with the limited force (mass * 3)", forces[#forces] ~= nil and math.abs(-forces[#forces][2] - 6 * 3) < 1e-9)
velocity = { 0, 0, 0 }

-- near the player it stops
nodes[1] = { 4.2, 1.7, 0 }                                                                    -- 0.8 m from the joint
forces = {}
WinchHand.update(WinchHand, 16)
check("the player within 1.2 m of the joint: no pull (the vehicle comes to where you stand)", #forces == 0)
check("... and the brake goes back on, so it stops where it is", brakeCalls[#brakeCalls] == 1)
nodes[1] = { 0, 1.7, 0 }

-- standing still: reported once
forces = {}
for _ = 1, 150 do WinchHand.update(WinchHand, 16) end
local stuck = 0
for _, line in ipairs(log) do if line:find("does not move", 1, true) then stuck = stuck + 1 end end
check("pulled for 2 s and not moving: said once, with the mass and the force", stuck == 1)

-- the rope: a debug line from the hand to the joint
WinchHand.hold(20)
WinchHand.draw()
check("the rope is drawn from the hand to the joint", #lines == 1 and lines[1][1] == 0 and lines[1][2] == 1.2 and lines[1][7] == 5)
WinchHand.putAway(21)
check("(a different tool put away: nothing happens)", WinchHand.target == picked)

-- the rope as the game's own cable (ForestryRope) when the engine pieces are there
do
    local made, deleted, targets = {}, 0, {}
    local savedUtils, savedI3D = Utils, g_i3DManager
    Utils = { getFilename = function(f) return f end }
    g_i3DManager = { loadSharedI3DFileAsync = function() return 7 end }
    ForestryRope = { new = function(vehicle, link)
        local r = { linkNode = link }
        made[#made + 1] = r
        r.delete = function() deleted = deleted + 1 end
        r.setTargetNode = function(self, node) self.targetNode = node; targets[#targets + 1] = node end
        return r
    end, update = function() end }
    nodes[500] = { 0, 0, 0 }
    local before = #lines
    WinchHand.draw()
    check("the cable is a ForestryRope linked to the tool, the debug line is not drawn", #made == 1 and made[1].linkNode == 20 and #lines == before)
    check("... its shape loads asynchronously: not tied until the frame is there", #targets == 0)
    made[1].referenceFrame = 500
    WinchHand.draw()
    WinchHand.draw()
    check("... then pointed at the joint node, once", #targets == 1 and targets[1] == 10 and #made == 1)
    made[1].targetNode = nil
    made[1]:update(0.016)
    check("a rope whose target is gone is not updated (the game's update would fail every frame)", made[1].update ~= ForestryRope.update)
    WinchHand.letGo("test")
    check("letting go deletes the cable", WinchHand.rope == nil and deleted == 1)
    WinchHand.toggle()
    WinchHand.draw()
    check("(hooking again makes a new one)", #made == 2 and WinchHand.rope == made[2])
    WinchHand.ROPE = false
    WinchHand.dropRope()
    WinchHand.draw()
    check("WinchHand.ROPE = false: the debug line again", #lines == before + 1)
    WinchHand.ROPE = true
    ForestryRope, Utils, g_i3DManager = nil, savedUtils, savedI3D
    WinchHand.dropRope()
    nodes[500] = nil
end

-- too far
nodes[1] = { -11, 1.7, 0 }                                                                    -- 16 m from the joint
WinchHand.update(WinchHand, 16)
check("further than 15 m from the joint: the rope lets go, and says so", WinchHand.target == nil and log[#log]:find("let go: the rope would be 16 m", 1, true) ~= nil)
nodes[1] = { 0, 1.7, 0 }

-- let go by the action
WinchHand.toggle()
check("hooked again", WinchHand.target == picked)
check("the same action lets go", WinchHand.toggle():find("let go of the drawbar eye", 1, true) ~= nil and WinchHand.target == nil)
check("... the brake is on when it is let go", brakeCalls[#brakeCalls] == 1)
check("... and the support leg goes down again", supportCalls[#supportCalls] == "down")

-- vehicle gone
WinchHand.toggle()
vehicle.isDeleted = true
WinchHand.update(WinchHand, 16)
brakeCalls = {}
check("(the vehicle is deleted)", true)
check("the vehicle is deleted: the rope lets go", WinchHand.target == nil and log[#log]:find("the vehicle is gone", 1, true) ~= nil)
vehicle.isDeleted = false

-- tool put away
WinchHand.toggle()
WinchHand.putAway(20)
check("the tool put away lets go", WinchHand.target == nil and WinchHand.hand == nil and log[#log]:find("the tool was put away", 1, true) ~= nil)
check("a vehicle without a brake function (not a wheeled one) is hooked and pulled all the same", (function()
    vehicle.brake = nil
    WinchHand.toggle()
    WinchHand.update(WinchHand, 16)
    WinchHand.toggle()
    return WinchHand.target == nil
end)())

-- published for other mods: the leash of FS25_HorseDynamics uses it as an easter egg
g_currentMission = {}
WinchHand.update(WinchHand, 16)
check("the winch publishes itself on g_currentMission.winchTow (mod globals are invisible between mods), with hold, putAway, pick, toggle and target", g_currentMission.winchTow == WinchHand
    and type(WinchHand.hold) == "function" and type(WinchHand.putAway) == "function" and type(WinchHand.pick) == "function" and type(WinchHand.toggle) == "function")
g_currentMission = nil

-- the pull moves the WHOLE vehicle: a drawbar that is a body of its own (60 kg of 660) is pulled with the force for the vehicle's total mass
do
    WinchHand.target, WinchHand.hand = nil, nil
    vehicle.brake = function() end
    vehicle.getTotalMass = function(self, onlyThis) return 12 end
    WinchTow.result = picked
    WinchHand.toggle()
    forces, velocity = {}, { 0, 0, 0 }
    WinchHand.update(WinchHand, 16)
    check("the pull force is the vehicle's total mass (12 t, not the joint body's 6 t) * 1.85 m/s2", forces[1] ~= nil and math.abs(-forces[1][2] - 12 * (2 / 3.6) / 0.3) < 1e-9)
    check("WinchHand.pullMass: the total mass, or the body's mass when the vehicle cannot say", WinchHand.pullMass(vehicle, 100) == 12 and WinchHand.pullMass({}, 100) == 6)
    WinchHand.toggle()
    vehicle.getTotalMass = nil
end

-- the pull speed depends on the mass, and the player's speed is capped with it (a cap on the walk state: it holds for running too)
do
    check("pull speed: a light vehicle (1.2 t and less) is pulled at the fast speed, a heavy one (10 t and more) at 2 km/h, in between a straight line",
        WinchHand.pullSpeed(0.66) == WinchHand.FAST_SPEED_MS and WinchHand.pullSpeed(1.2) == WinchHand.FAST_SPEED_MS and math.abs(WinchHand.pullSpeed(10) - 2 / 3.6) < 1e-9 and math.abs(WinchHand.pullSpeed(50) - 2 / 3.6) < 1e-9
        and math.abs(WinchHand.pullSpeed(5.6) - (WinchHand.FAST_SPEED_MS + (2 / 3.6 - WinchHand.FAST_SPEED_MS) * 0.5)) < 1e-9)
    WinchHand.target, WinchHand.hand = nil, nil
    WinchHand.speedCaps = {}
    vehicle.getTotalMass = function() return 0.66 end
    vehicle.brake = function() end
    WinchTow.result = picked
    WinchHand.hold(20)
    check("hooking a 0.66 t wagon says its speed (13 km/h)", WinchHand.toggle():find("up to 13 km/h", 1, true) ~= nil)
    forces, velocity = {}, { 0, 0, 0 }
    WinchHand.update(WinchHand, 16)
    check("the wagon is pulled towards the fast speed (0.66 t * accel 3, the limit: it is far from 3.5 m/s)", forces[1] ~= nil and math.abs(-forces[1][2] - 0.66 * 3) < 1e-9)
    check("the player's speed is capped at the pull speed (3.5 m/s)", WinchHand.speedCap() == WinchHand.FAST_SPEED_MS)
    vehicle.getTotalMass = function() return 12 end
    WinchHand.update(WinchHand, 16)
    check("a 12 t trailer: the player is capped at 2 km/h", math.abs(WinchHand.speedCap() - 2 / 3.6) < 1e-9)
    WinchHand.toggle()
    check("let go: no cap", WinchHand.speedCap() == nil)
    WinchHand.toggle()
    WinchHand.update(WinchHand, 16)
    check("hooked again: capped", WinchHand.speedCap() ~= nil)
    WinchHand.putAway(20)
    check("the tool put away: no cap", WinchHand.speedCap() == nil)
    -- several sources: the lowest wins, each takes its own off
    WinchHand.setSpeedCap("horsehitch", 1)
    WinchHand.setSpeedCap("winchhand", 3.5)
    check("two caps (a horse that pulls, the hand winch): the lowest counts", WinchHand.speedCap() == 1)
    WinchHand.setSpeedCap("horsehitch", nil)
    check("... and when one is taken off the other stays", WinchHand.speedCap() == 3.5)
    WinchHand.setSpeedCap("winchhand", nil)
    check("... and none is none", WinchHand.speedCap() == nil)
    vehicle.getTotalMass = nil
end

-- the green ring (the winch's own TargetTreeMarker) at the joint the tool would hook
do
    local m = { made = 0, active = false, pos = nil, deleted = false }
    TargetTreeMarker = { new = function(vehicle, link)
        m.made = m.made + 1
        return { onI3DLoaded = function() end, setIsActive = function(self, a) m.active = a end,
            setPosition = function(self, x, y, z, dx, dy, dz, r) m.pos = { x, y, z, r } end, delete = function() m.deleted = true end }
    end }
    getRootNode = function() return 0 end
    g_i3DManager = { loadSharedI3DFileAsync = function() return 7 end }
    WinchHand.hand, WinchHand.target, WinchHand.gate = nil, nil, nil
    picked.x, picked.y, picked.z = 5, 0.6, 0
    WinchTow.result = picked
    WinchHand.update(WinchHand, 200)
    check("ring: nothing in the hand, no ring", not m.active and m.made == 0)
    WinchHand.hold(20)
    WinchHand.update(WinchHand, 200)
    check("ring: tool in the hand, a joint in view: the ring is on it (0.18 m, at the joint)", m.active and m.pos ~= nil and m.pos[1] == 5 and m.pos[2] == 0.6 and m.pos[4] == 0.18)
    m.active = true; m.pos = nil
    WinchTow.result = nil
    WinchHand.update(WinchHand, 50)
    check("ring: looked up ten times a second, not every frame (50 ms later it is still there)", m.active)
    WinchHand.update(WinchHand, 60)
    check("ring: looking away takes it off", not m.active)
    WinchTow.result = picked
    WinchHand.gate = function() return false end
    WinchHand.update(WinchHand, 200)
    check("ring: the gate says a click would not hook (a horse in reach): no ring", not m.active)
    WinchHand.gate = function() return true end
    WinchHand.update(WinchHand, 200)
    check("ring: gate agrees: the ring is back", m.active)
    WinchHand.toggle()
    WinchHand.update(WinchHand, 200)
    check("ring: hooked: the ring goes (the rope is the sign now)", not m.active)
    WinchHand.toggle()
    WinchHand.update(WinchHand, 200)
    check("ring: let go: the ring is back", m.active)
    WinchHand.hint = function() return { 1, 2, 3, 0, 1, 0, 0.1 } end
    WinchTow.result = nil
    WinchHand.update(WinchHand, 200)
    check("ring: a hint (a horse tool) shows its own ring, with nothing in view", m.active and m.pos[1] == 1 and m.pos[2] == 2 and m.pos[4] == 0.1)
    WinchHand.hint = function() return nil end
    WinchHand.update(WinchHand, 200)
    check("ring: a hint with nothing to show falls back to the pick: nothing in view, no ring", not m.active)
    WinchHand.hint = nil
    WinchTow.result = picked
    WinchHand.putAway(20)
    check("ring: tool put away: no ring, and the gate and the hint are forgotten", not m.active and WinchHand.gate == nil and WinchHand.hint == nil)
    WinchHand.deleteMarker()
    check("ring: the marker is deleted with the mission", m.deleted and WinchHand.marker == nil and m.made == 1)
    -- a joint asked about with no tool in the hand (WAILA): the ring is on it while the asking goes on
    WinchTow.describe = function(target, long) return long and { "joint" } or "Eye: test" end
    WinchHand.hand, WinchHand.target, WinchHand.gate = nil, nil, nil
    WinchTow.result = picked
    g_time = 1000
    WinchHand.look()
    WinchHand.update(WinchHand, 200)
    check("ring: no tool, but somebody asks about the joint in sight (look): the ring is on it", m.active and m.pos ~= nil and m.pos[1] == 5 and m.pos[2] == 0.6)
    g_time = 1300
    WinchHand.update(WinchHand, 200)
    check("ring: it stays while the asking was recent (300 ms ago)", m.active)
    g_time = 2200
    WinchHand.update(WinchHand, 200)
    check("ring: nobody asks any more (more than LOOK_RING_MS): it goes", not m.active)
    g_time = 3000
    WinchTow.result = nil
    WinchHand.lookAt = nil
    WinchHand.look()
    WinchHand.update(WinchHand, 200)
    check("ring: asked about, but no joint in sight: no ring", not m.active)
    g_time = nil
    WinchHand.lookTarget, WinchHand.lookAskedAt = nil, nil
    WinchHand.deleteMarker()
    TargetTreeMarker = nil
    WinchHand.hold(20)
    WinchHand.update(WinchHand, 200)
    check("ring: without the marker class (an older game) nothing breaks", WinchHand.marker == nil)
    WinchHand.putAway(20)
end

-- CARRY: a tongue (a joint on a body that is a small share of the vehicle) is lifted with the wagon held still, then carried: no stop radius, no brake on and off, no rope line
do
    local SETLIN, SETANG = {}, {}
    setLinearVelocity = function(n, x, y, z) SETLIN[n] = { x, y, z } end
    setAngularVelocity = function(n, x, y, z) SETANG[n] = { x, y, z } end
    getAngularVelocity = function(n) local a = SETANG[n] or { 0, 1, 0 } return a[1], a[2], a[3] end
    local savedMass = getMass
    getMass = function(n) return n == 100 and 0.06 or 6 end
    nodes[100], nodes[101] = { 5, 0.6, 0 }, { 8, 0.6, 0 }
    WinchHand.target, WinchHand.hand, WinchHand.stage, WinchHand.speedCaps, WinchHand.gate = nil, nil, nil, {}, nil
    vehicle.getTotalMass = function() return 0.66 end
    vehicle.components = { { node = 100 }, { node = 101 } }
    vehicle.brake = function(self, pedal) brakeCalls[#brakeCalls + 1] = pedal end
    brakeCalls, supportCalls, forces, lines = {}, {}, {}, {}
    velocity = { 0, 0, 0 }
    WinchTow.result = picked
    check("a tongue (60 kg of a 660 kg wagon, on a drawbar eye) is liftable", WinchHand.liftable(picked) == true)
    check("a joint on the main body (6 t of 12 t) is not, nor a machine's own hitch", (function()
        vehicle.getTotalMass = function() return 12 end
        getMass = function() return 6 end
        local heavy = WinchHand.liftable(picked)
        getMass = function(n) return n == 100 and 0.06 or 6 end
        vehicle.getTotalMass = function() return 0.66 end
        return heavy == false and WinchHand.liftable({ vehicle = vehicle, node = 10, component = 100, kind = "hitch" }) == false
    end)())
    WinchHand.hold(20)
    check("hooking a tongue: the support leg up, and the first stage is the lift", WinchHand.toggle():find("hooked to the drawbar eye", 1, true) ~= nil and WinchHand.stage == "lift" and supportCalls[#supportCalls] == "up")
    WinchHand.update(WinchHand, 250)
    check("the lift: no force, the brake stays ON, the wagon is held (no horizontal speed, no turn on any of its bodies)",
        #forces == 0 and brakeCalls[#brakeCalls] == 1 and SETLIN[100][1] == 0 and SETLIN[100][3] == 0 and SETLIN[101][1] == 0 and SETLIN[101][3] == 0 and SETANG[100][2] == 0 and SETANG[101][2] == 0)
    check("... and the tongue is driven up at the speed it wants (4 per second over the 0.21 m it is short, not what the physics reports), the other body keeps its own vertical speed",
        math.abs(SETLIN[100][2] - 0.21 * WinchHand.LIFT_GAIN) < 1e-9 and SETLIN[101][2] == 0 and WinchHand.stage == "lift")
    nodes[10] = { 5, 0.81, 0 }
    WinchHand.update(WinchHand, 16)
    check("the eye at its height (0.81 m): the lift is done, the eye is carried now", WinchHand.stage == "carry")
    -- carried: you 5 m from the eye, nothing moving: pulled towards you at the most the force may be
    forces = {}
    WinchHand.update(WinchHand, 16)
    local f = forces[#forces]
    check("carried: the brake is off", brakeCalls[#brakeCalls] == 0)
    check("... a force on the tongue towards you (-x), at the eye, the vehicle's whole mass (0.66 t) times the 3 m/s2 limit", f ~= nil and f[1] == 100 and math.abs(f[2] + 0.66 * WinchHand.ACCEL_MS2) < 1e-9 and math.abs(f[4]) < 1e-9 and f[5] == 5 and f[6] == 0.81)
    check("... and the tongue is kept at its height (no vertical speed wanted at 0.81 m)", SETLIN[100][2] == 0)
    -- the speed wanted is your own away from the eye (smoothed) plus 4 per metre it is further than 0.8 m: tested 0.9 m away at 2.3 m/s
    nodes[1] = { 4.1, 1.7, 0 }
    WinchHand.lastPx, WinchHand.pvx, WinchHand.pvz = 4.1, -2, 0
    velocity = { -2.3, 0, 0 }
    forces = {}
    WinchHand.update(WinchHand, 16)
    local alpha = 0.016 / (WinchHand.VELOCITY_FILTER_S + 0.016)
    local pv = -2 * (1 - alpha)
    local wanted = -pv + WinchHand.POS_GAIN * (0.9 - WinchHand.CARRY_M)
    check("walking away: the speed wanted is yours (smoothed) plus the catch-up, the force is the speed it is short of over 0.3 s", forces[#forces] ~= nil and math.abs(forces[#forces][2] - 0.66 * (-wanted + 2.3) / WinchHand.PULL_TAU_S) < 1e-9)
    -- inside CARRY_M the eye is braked, not pushed: no speed wanted, the force opposes its speed
    nodes[1] = { 4.5, 1.7, 0 }
    WinchHand.lastPx, WinchHand.pvx = 4.5, 0
    velocity = { -1, 0, 0 }
    forces = {}
    brakeCalls = {}
    WinchHand.update(WinchHand, 16)
    check("nearer than 0.8 m: no speed wanted, so the force opposes its speed (+x, the most it may be)", forces[#forces] ~= nil and math.abs(forces[#forces][2] - 0.66 * WinchHand.ACCEL_MS2) < 1e-9)
    check("... and the brake is NOT touched at that distance (it flapped on and off there)", #brakeCalls == 1 and brakeCalls[1] == 0)
    -- walking into the eye: it is pushed on at your speed (away from you, +x here)
    nodes[1] = { 4.5, 1.7, 0 }
    WinchHand.lastPx, WinchHand.pvx, WinchHand.pvz = 4.5, 1.2, 0
    velocity = { 0, 0, 0 }
    forces = {}
    WinchHand.update(WinchHand, 16)
    check("walking into the eye (1.2 m/s): a force pushes it away from you (+x)", forces[#forces] ~= nil and forces[#forces][2] > 0)
    WinchHand.PUSH = false
    forces = {}
    WinchHand.update(WinchHand, 16)
    check("PUSH off: standing at the eye it is only braked (nothing to do at rest)", #forces == 0)
    WinchHand.PUSH = true
    brakeCalls = {}
    nodes[1] = { 0, 1.7, 0 }
    for _ = 1, 20 do
        nodes[1] = { nodes[1][1] + 0.2, 1.7, 0 }
        WinchHand.update(WinchHand, 16)
    end
    local flaps = 0
    for _, pedal in ipairs(brakeCalls) do flaps = flaps + (pedal == 1 and 1 or 0) end
    check("walking up to the eye and past 0.8 m: the brake pedal never goes down on the way", flaps == 0)
    -- the eye too low (0.5 m): driven up, at most 1 m/s
    nodes[10] = { 5, 0.5, 0 }
    nodes[1] = { 0, 1.7, 0 }
    WinchHand.update(WinchHand, 16)
    check("the eye below its height in the carry: driven up at most LIFT_MS (1 m/s)", SETLIN[100][2] == WinchHand.LIFT_MS)
    nodes[10] = { 5, 0.81, 0 }
    -- the rope line is not drawn for a carried eye
    WinchHand.draw()
    check("no rope line for a carried tongue ...", #lines == 0)
    WinchHand.SHOW_LINE = true
    WinchHand.draw()
    check("... unless SHOW_LINE", #lines == 1)
    WinchHand.SHOW_LINE = false
    check("the same action lets go: the brake goes on, the leg goes down, the stage is forgotten", WinchHand.toggle():find("let go of the drawbar eye", 1, true) ~= nil and WinchHand.stage == nil and brakeCalls[#brakeCalls] == 1 and supportCalls[#supportCalls] == "down")
    -- the support animation (the hinge on some trailers) is waited for
    local playing = true
    vehicle.getIsAnimationPlaying = function() return playing end
    vehicle.spec_attachable = { supportAnimations = { { animationName = "leg" } } }
    WinchHand.toggle()
    nodes[10] = { 5, 0.2, 0 }
    SETLIN = {}
    WinchHand.update(WinchHand, 100)
    check("the support animation is playing: the wagon is held, the tongue is not lifted yet", WinchHand.stage == "lift" and SETLIN[100] ~= nil and SETLIN[100][2] == 0 and WinchHand.liftS == 0 and WinchHand.supportWaitS > 0)
    playing = false
    WinchHand.update(WinchHand, 100)
    check("... and when it is done the lift starts", WinchHand.liftS > 0 and SETLIN[100][2] > 0)
    WinchHand.update(WinchHand, 4000)
    check("a hinge that never gets there: after LIFT_MAX_S the carry starts anyway", WinchHand.stage == "carry")
    WinchHand.toggle()
    vehicle.getIsAnimationPlaying, vehicle.spec_attachable = nil, nil
    -- TONGUE_POLE: the lifted tongue is held on the pole (stage pole), its eye kept at its height
    WinchHand.TONGUE_POLE = true
    WinchHand.toggle()
    nodes[10], SETLIN = { 5, 0.2, 0 }, {}
    WinchHand.update(WinchHand, 4000)
    check("TONGUE_POLE: after the lift the tongue is on the pole (drawn as the bar)", WinchHand.stage == "pole" and WinchHand.tongueHeld == true)
    nodes[10], SETLIN = { 5, 0.5, 0 }, {}
    WinchHand.update(WinchHand, 16)
    check("... and its eye is still driven up to its height on the pole", SETLIN[100] ~= nil and SETLIN[100][2] > 0)
    -- held along the view: you look along +x, the bar is 0.5 m, you stand at the origin and the eye is 5 m ahead: it is pulled back to 0.5 m in front of you (-x)
    nodes[1], nodes[10], velocity, forces = { 0, 1.7, 0 }, { 5, 0.81, 0 }, { 0, 0, 0 }, {}
    SETANG[100] = { 0, 1, 0 }
    WinchHand.lastPx, WinchHand.pvx, WinchHand.pvz = 0, 0, 0
    SETLIN[100] = nil
    WinchHand.update(WinchHand, 16)
    check("TONGUE_VIEW: the eye is wanted at the end of the bar in the view direction: far ahead, its speed is driven back (-x)", SETLIN[100] ~= nil and SETLIN[100][1] < 0)
    WinchHand.VIEW_STIFF = false
    nodes[1], nodes[10], velocity, forces = { 0, 1.7, 0 }, { 5, 0.81, 0 }, { 0, 0, 0 }, {}
    WinchHand.lastPx, WinchHand.pvx, WinchHand.pvz = 0, 0, 0
    WinchHand.update(WinchHand, 16)
    check("VIEW_STIFF off: the force servo instead (a force back, -x)", forces[1] ~= nil and forces[1][2] < 0)
    WinchHand.VIEW_STIFF = true
    -- the aim is latched while you stand: a head turn of 10 degrees does not move it, 60 degrees does
    local oldDir = localDirectionToWorld
    WinchHand.viewX, WinchHand.viewZ = 1, 0
    nodes[1], nodes[10], velocity = { 0, 1.7, 0 }, { 5, 0.81, 0 }, { 0, 0, 0 }
    WinchHand.lastPx, WinchHand.pvx, WinchHand.pvz = 0, 0, 0
    localDirectionToWorld = function() return math.cos(math.rad(10)), 0, math.sin(math.rad(10)) end
    WinchHand.update(WinchHand, 16)
    check("LATCH: standing, a 10 degree turn of the head leaves the aim where it was", math.abs(WinchHand.viewX - 1) < 1e-9 and math.abs(WinchHand.viewZ) < 1e-9)
    localDirectionToWorld = function() return math.cos(math.rad(60)), 0, math.sin(math.rad(60)) end
    WinchHand.update(WinchHand, 16)
    check("... a 60 degree turn moves it (towards the new direction)", WinchHand.viewZ > 0.01)
    localDirectionToWorld = oldDir
    check("... and the tongue's yaw speed is damped (1 rad/s becomes less)", SETANG[100] ~= nil and SETANG[100][2] < 1 and SETANG[100][2] > 0)
    WinchHand.toggle()
    WinchHand.TONGUE_POLE = false
    -- the other ways
    WinchHand.CARRY = false
    WinchHand.toggle()
    check("CARRY off: a tongue is pulled the old way", WinchHand.stage == nil)
    WinchHand.toggle()
    WinchHand.CARRY = true
    vehicle.getTotalMass = function() return 12 end
    getMass = function() return 6 end
    WinchHand.toggle()
    -- a trailer whose frame IS the eye's body: belted logs add mass to what the game counts for the vehicle, but it is still no tongue
    vehicle.components = { { node = 100 } }
    getMass = function(n) return 0.66 end
    vehicle.getTotalMass = function() return 20 end
    check("the eye's body is the trailer's only frame: not a tongue, whatever the belted load adds to the vehicle's mass", WinchHand.liftable(picked) == false)
    vehicle.components = nil
    getMass = function() return 6 end
    vehicle.getTotalMass = function() return 12 end
    check("a joint on the main body: pulled the old way (no lift, no carry)", WinchHand.stage == nil)
    WinchHand.toggle()
    -- POLE: the same joint on a stiff 2 m pole: pulled in when further, pushed back when nearer, never lifted
    WinchHand.POLE = true
    WinchHand.toggle()
    check("POLE: a joint that is no tongue is held on a pole (stage pole, no lift)", WinchHand.stage == "pole")
    local mass = WinchHand.pullMass(vehicle, picked.component)
    local pullSpeed = WinchHand.pullSpeed(mass)
    nodes[1], velocity, forces, brakeCalls, SETLIN[100] = { 0, 1.7, 0 }, { 0, 0, 0 }, {}, {}, nil
    WinchHand.update(WinchHand, 16)
    local f = forces[#forces]
    check("5 m away: pulled in towards you, the speed wanted is the pull speed over 0.3 s (the force is limited to mass * ACCEL)", f ~= nil and f[2] < 0 and math.abs(f[2] + math.min(mass * pullSpeed / WinchHand.PULL_TAU_S, mass * WinchHand.ACCEL_MS2)) < 1e-9)
    check("... the brake is off and the machine is not lifted (no vertical speed written)", brakeCalls[#brakeCalls] == 0 and SETLIN[100] == nil)
    nodes[1], forces = { 4, 1.7, 0 }, {}                                           -- 1 m from the joint: inside the pole
    WinchHand.lastPx, WinchHand.pvx = 4, 0
    WinchHand.update(WinchHand, 16)
    f = forces[#forces]
    check("1 m away (inside the 2 m pole): it is pushed back from you (a force away from you, +x), not just braked", f ~= nil and f[2] > 0)
    nodes[1], forces = { 3, 1.7, 0 }, {}                                           -- exactly 2 m
    WinchHand.lastPx, WinchHand.pvx = 3, 0
    WinchHand.update(WinchHand, 16)
    check("at the pole's length: nothing is wanted (no force at rest)", #forces == 0)
    -- the steering nudge: the body (origin 2 m behind the joint, along x) lies across the pole when you stand to the side: a couple turns it along the pole, no net force
    nodes[100] = { 7, 0.6, 0 }
    nodes[1], forces = { 5, 1.7, 3 }, {}                                           -- the pole points along +z from the joint, the body along +x: 90 degrees off
    WinchHand.lastPx, WinchHand.lastPz, WinchHand.pvx, WinchHand.pvz = 5, 3, 0, 0
    WinchHand.update(WinchHand, 16)
    local c1, c2 = forces[#forces - 1], forces[#forces]
    check("steering nudge: two opposite forces on the body, at the joint and at the far end of the body (2 m behind the origin's side)", c1 ~= nil and c2 ~= nil and c1[1] == 100 and math.abs(c1[2] + c2[2]) < 1e-9 and math.abs(c1[4] + c2[4]) < 1e-9 and c1[5] == 5 and c2[5] == 9)
    check("... full strength (mass * NUDGE_MS2) across the body, towards the side you stand on (+z)", math.abs(c1[4] - mass * WinchHand.NUDGE_MS2) < 1e-9 and math.abs(c1[2]) < 1e-9)
    nodes[100] = { 7, 0.6, 0 }
    nodes[1], forces = { 3, 1.7, 0 }, {}                                           -- 2 m along the body's line: lined up already
    WinchHand.lastPx, WinchHand.pvx = 3, 0
    WinchHand.update(WinchHand, 16)
    check("lined up along the pole: no nudge", #forces == 0)
    WinchHand.NUDGE = false
    nodes[1], forces = { 5, 1.7, 3 }, {}
    WinchHand.update(WinchHand, 16)
    check("NUDGE = false: no couple, only the pull", #forces == 1)
    WinchHand.NUDGE = true
    nodes[100] = nil
    local before = #lines
    WinchHand.draw()
    check("the pole is drawn like the old rope (stage pole)", #lines == before + 1)
    WinchHand.toggle()
    WinchHand.POLE = false
    getMass = savedMass
    vehicle.getTotalMass, vehicle.components = nil, nil
    nodes[10], nodes[1], nodes[100], nodes[101] = { 5, 0.6, 0 }, { 0, 1.7, 0 }, nil, nil
    WinchHand.hand = nil
end

-- a log on the ground: hooked at the point looked at, dragged behind the player on a rope
do
    dofile("scripts/WinchHand.lua")
    WinchTow.result = nil
    local body, deleted, linked = "dynamic", {}, {}
    local world = { [200] = { 5, 0.3, 0 } }
    RigidBodyType = { STATIC = 1, DYNAMIC = 2, KINEMATIC = 3 }
    ClassIds = { SHAPE = 1 }
    CollisionFlag = { TREE = 8 }
    getHasClassId = function() return true end
    getSplitType = function() return 4 end
    getRigidBodyType = function() return body == "static" and 1 or body == "dynamic" and 2 or 3 end
    raycastClosest = function(ox, oy, oz, dx, dy, dz, range, callbackName, target, mask)
        raycastMask = mask
        target[callbackName](target, 200, 5, 0.3, 0, 4.5, nil, nil, nil, nil, 200)
    end
    local nextNode = 300
    createTransformGroup = function() nextNode = nextNode + 1; return nextNode end
    link = function(parent, node) linked[#linked + 1] = { parent, node } end
    setWorldTranslation = function(node, x, y, z) nodes[node] = { x, y, z } end
    delete = function(node) deleted[#deleted + 1] = node; nodes[node] = nil end
    nodes[200] = { 5, 0.3, 0 }
    nodes[1] = { 0, 1.7, 0 }
    getMass = function() return 2 end
    forces, velocity = {}, { 0, 0, 0 }

    local noRing = WinchHand.pickLog()
    check("without the game's tree geometry the pick has no ring (the marker falls back to a flat ring)", noRing ~= nil and noRing.ring == nil)
    SplitShapeUtil = { getTreeOffsetPosition = function(shape, x, y, z) return 5, 0.4, 0, 1, 0, 0, 0.3 end }
    local withRing = WinchHand.pickLog()
    check("the ring is the trunk's centre, axis and radius", withRing.ring ~= nil and withRing.ring[1] == 5 and withRing.ring[4] == 1 and withRing.ring[7] == 0.3)
    -- near a cut end: the ring slides along the trunk until 0.45 m of log is left on both sides
    SplitShapeUtil = { getTreeOffsetPosition = function(shape, x, y, z, r, minLength)
        if minLength > 0.2 and x < 5.25 then return nil end                 -- (the cut end is 0.25 m behind the hit: too close)
        return x, y, z, 1, 0, 0, 0.3
    end }
    localDirectionToWorld = function() return 1, 0, 0 end
    local slid = WinchHand.pickLog()
    check("looking near a cut end: the ring slides along the trunk to where 0.45 m is left (here 0.3 m on), and the hook goes there", slid.ring ~= nil and math.abs(slid.ring[1] - 5.3) < 1e-9 and math.abs(slid.x - 5.3) < 1e-9)
    SplitShapeUtil = { getTreeOffsetPosition = function(shape, x, y, z, r, minLength) if minLength > 0.2 then return nil end return x, y, z, 1, 0, 0, 0.3 end }
    local short = WinchHand.pickLog()
    check("a log too short for the margin: the game's own 0.15 m margin at the hit point", short.ring ~= nil and short.ring[1] == 5 and short.x == 5)
    SplitShapeUtil = nil
    local text = WinchHand.toggle()
    local t = WinchHand.target
    check("a joint wins, but with none in view the action hooks the log (a tree raycast)", t ~= nil and t.kind == "log" and raycastMask == 8 and text:find("hooked to the log", 1, true) ~= nil)
    check("the grip is a node of its own, linked to the log, at the point looked at", t.ownsNode and linked[1][1] == 200 and linked[1][2] == t.node and nodes[t.node][1] == 5 and nodes[t.node][2] == 0.3)
    check("a log is dragged ('drag'), no support leg or brake is touched", WinchHand.stage == "drag")
    WinchHand.update(WinchHand, 16)
    local f = forces[#forces]
    check("dragged: a force on the log, towards the player, at the grip, mass * at most LOG_ACCEL", f ~= nil and f[1] == 200 and f[2] < 0 and f[5] == 5 and -f[2] <= 2 * WinchHand.LOG_ACCEL_MS2 + 1e-9)
    check("dragged: the pull also lifts LOG_LIFT_SHARE of the log's weight at the grip", math.abs(f[3] - WinchHand.LOG_LIFT_SHARE * 2 * 9.81) < 1e-9)
    nodes[1] = { 4, 1.7, 0 }                                                  -- 1 m from the grip: inside the reach, the rope is slack
    forces = {}
    velocity = { 0, 0, 0 }
    WinchHand.update(WinchHand, 16)
    check("nearer than the reach: nothing is pushed (a rope does not push)", #forces == 0)
    nodes[1] = { 0, 1.7, 0 }
    body = "kinematic"
    WinchHand.update(WinchHand, 16)
    check("belted onto a trailer meanwhile: let go", WinchHand.target == nil and deleted[1] == t.node)
    body = "dynamic"
    WinchHand.toggle()
    local grip = WinchHand.target.node
    WinchHand.toggle()
    check("the action again lets the log go and deletes the grip node", WinchHand.target == nil and deleted[#deleted] == grip)
    body = "static"
    check("a tree that still stands is not hooked, and it says so", WinchHand.toggle():find("still stands", 1, true) ~= nil and WinchHand.target == nil)
    body = "kinematic"
    check("a belted log is not hooked either", WinchHand.toggle():find("belted", 1, true) ~= nil and WinchHand.target == nil)
    body = "dynamic"
    -- traffic brakes for what is on the DYNAMIC_OBJECT group: a hooked log gets that bit, and loses it again on let-go
    do
        bit32 = bit32 or {
            band = function(a, b) local r, bitv = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + bitv end a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2 end return r end,
            bor = function(a, b) local r, bitv = 0, 1 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + bitv end a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2 end return r end,
        }
        local filter = { 8, 0xFF }                                           -- (TREE group)
        CollisionFlag = { TREE = 8, DYNAMIC_OBJECT = 16 }
        getCollisionFilter = function() return filter[1], filter[2] end
        setCollisionFilterGroup = function(node, group) filter[1] = group end
        WinchHand.toggle()
        check("a hooked log is also on the DYNAMIC_OBJECT group (traffic stops for it), the mask is untouched", filter[1] == 24 and filter[2] == 0xFF and WinchHand.target.trafficOriginal ~= nil)
        WinchHand.toggle()
        check("let go: the original group is back", filter[1] == 8 and WinchHand.target == nil)
        WinchHand.TRAFFIC_SEES_LOGS = false
        WinchHand.toggle()
        check("with the switch off the group is left alone", filter[1] == 8 and WinchHand.target.trafficOriginal == nil)
        WinchHand.toggle()
        WinchHand.TRAFFIC_SEES_LOGS = true
        setCollisionFilterGroup, getCollisionFilter = nil, nil
        WinchHand.toggle()
        check("without the engine call the log is hooked all the same", WinchHand.target ~= nil and WinchHand.target.trafficOriginal == nil)
        WinchHand.toggle()
        CollisionFlag = { TREE = 8 }
    end
    -- a vehicle without wheels is dragged like a log (its pull as a vehicle only lets wheels roll it); one with wheels is not
    do
        check("a vehicle with no wheels at all rolls not", WinchHand.rollsNot({ isDeleted = false }) == true)
        check("... one with an empty wheel list too", WinchHand.rollsNot({ spec_wheels = { wheels = {} } }) == true)
        check("... one with wheels does", WinchHand.rollsNot({ spec_wheels = { wheels = { {}, {} } } }) == false)
        check("... and a log standing in is not one", WinchHand.rollsNot({ isLog = true }) == false)
    end
    -- a wagon's eye hooked and a fitting hitch of a tractor in view: attached with the game's own attach
    do
        WinchHand.hold(20)
        local attachedInfo, allowed, allowedWhy = nil, true, nil
        local tractor = { isDeleted = false, getName = function() return "Tractor" end, getActiveFarm = function() return 1 end, attachImplementFromInfo = function(_, info) attachedInfo = info end }
        local wagon = { isDeleted = false, getName = function() return "Wagon" end, isAttachAllowed = function() return allowed, allowedWhy end }
        local eye = { vehicle = wagon, node = 10, component = 100, kind = "drawbar eye", jointType = "trailer", jointTypeId = 3, index = 2 }
        local hitch = { vehicle = tractor, node = 40, component = 400, kind = "hitch", jointType = "trailer", jointTypeId = 3, index = 1, x = 6, y = 0.8, z = 0 }
        nodes[10], nodes[40] = { 5, 0.6, 0 }, { 6, 0.8, 0 }
        wagon.joints, tractor.joints = { eye }, { hitch }
        local savedMission, savedJointsOf = g_currentMission, WinchTow.jointsOf
        g_currentMission = { vehicleSystem = { vehicles = { tractor, wagon } } }
        WinchTow.jointsOf = function(v) return v.joints or {} end
        WinchTow.result = eye
        WinchHand.toggle()
        check("(the wagon's eye is hooked)", WinchHand.target == eye)
        check("a fitting free hitch of another vehicle within reach is the candidate (the ring goes there), nothing to aim at", WinchHand.attachCandidate() == hitch)
        hitch.jointTypeId, hitch.jointType = 5, "implement"
        local none, why = WinchHand.attachCandidate()
        check("a hitch of another type is none, and says why", none == nil and why:find("do not fit", 1, true) ~= nil)
        -- a joint that does not fit never traps the click: it lets go and says why
        do
            local msg = WinchHand.toggle()
            check("... the click then lets go and says why (no trap)", msg:find("let go", 1, true) ~= nil and msg:find("do not fit", 1, true) ~= nil and WinchHand.target == nil and attachedInfo == nil)
            WinchTow.result = eye
            WinchHand.toggle()
            check("(hooked again)", WinchHand.target == eye)
        end
        hitch.jointTypeId, hitch.jointType = 3, "trailer"
        hitch.inUse = true
        check("a hitch with something on it is none, and says so", select(2, WinchHand.attachCandidate()):find("already hitched", 1, true) ~= nil)
        hitch.inUse = nil
        tractor.joints, wagon.joints = {}, { eye, { vehicle = wagon, node = 10, component = 100, kind = "hitch", jointTypeId = 3, jointType = "trailer", index = 1 } }
        check("a hitch of the wagon itself is none", WinchHand.attachCandidate() == nil)
        tractor.joints = { hitch }
        nodes[40] = { 10.5, 0.8, 0 }
        check("a hitch further than ATTACH_REACH_M from the eye (but not BRING_CLOSER_M): the click says to bring it closer, nothing attached", WinchHand.toggle():find("closer to the hitch", 1, true) ~= nil and attachedInfo == nil and WinchHand.target == eye)
        nodes[40] = { 20, 0.8, 0 }
        do
            local msg = WinchHand.toggle()
            check("a hitch far beyond BRING_CLOSER_M is nothing to hitch to: the click lets go, as before", msg:find("let go", 1, true) ~= nil and msg:find("closer", 1, true) == nil and WinchHand.target == nil and attachedInfo == nil)
            WinchTow.result = eye
            WinchHand.toggle()
            check("(hooked again)", WinchHand.target == eye)
        end
        nodes[40] = { 6, 0.8, 0 }
        allowed, allowedWhy = false, "not yours"
        check("the game says no: the click says so, nothing attached", WinchHand.toggle():find("not yours", 1, true) ~= nil and attachedInfo == nil)
        allowed = true
        -- from the other side: the hitch is hooked and the wagon's eye is the mate (it does not matter which of the two is pulled)
        do
            local hooked0 = WinchHand.target
            WinchHand.target = hitch
            nodes[40] = { 6, 0.8, 0 }
            local m = WinchHand.attachCandidate()
            check("the hitch hooked: the wagon's free eye of the same type is the mate", m == eye)
            WinchHand.target = hooked0
        end
        -- Shift and a click on a hitched joint unhitches it (the game's own detach)
        do
            local detached = {}
            local trac2 = { isDeleted = false, getName = function() return "Tractor2" end, detachImplementByObject = function(_, o) detached[#detached + 1] = o end, getImplementByJointDescIndex = function(_, i) return i == 1 and { object = wagon } or nil end }
            local wag2 = { isDeleted = false, getName = function() return "Wagon2" end, getAttacherVehicle = function() return trac2 end }
            Input = { isKeyPressed = function(k) return k == 304 end, KEY_lshift = 304 }
            local msgEye = WinchHand.tryDetach({ vehicle = wag2, kind = "drawbar eye", index = 1 })
            check("an eye of a hitched wagon: unhitched from what pulls it", msgEye ~= nil and msgEye:find("unhitched", 1, true) ~= nil and detached[1] == wag2)
            local msgHitch = WinchHand.tryDetach({ vehicle = trac2, kind = "hitch", index = 1 })
            check("a hitch with something on it: that is unhitched", msgHitch ~= nil and detached[2] == wagon)
            check("a hitch with nothing on it: nothing to do", WinchHand.tryDetach({ vehicle = trac2, kind = "hitch", index = 2 }) == nil)
            check("an eye of a vehicle that is not hitched: nothing to do", WinchHand.tryDetach({ vehicle = wagon, kind = "drawbar eye", index = 1 }) == nil)
            -- the unhitch key: from everything, what pulls it and what hangs on it
            local keepTarget, keepResult = WinchHand.target, WinchTow.result
            local d3 = {}
            local middle = { isDeleted = false, getName = function() return "Middle" end, getAttacherVehicle = function() return trac2 end,
                             getAttachedImplements = function() return { { object = wag2 }, { object = wagon } } end, detachImplementByObject = function(_, o) d3[#d3 + 1] = o end }
            trac2.detachImplementByObject = function(_, o) d3[#d3 + 1] = o end
            WinchHand.target = nil
            WinchTow.result = { vehicle = middle, kind = "drawbar eye", index = 1 }
            local said = WinchHand.unhitchAll()
            check("the unhitch key on the joint you look at: the piece is unhitched from what pulls it and from everything on it", #d3 == 3 and d3[1] == middle and said:find("unhitched from everything", 1, true) ~= nil)
            local lonely = { isDeleted = false, getName = function() return "Lonely" end }
            WinchTow.result = { vehicle = lonely, kind = "drawbar eye", index = 1 }
            check("a piece that is not hitched to anything says so", WinchHand.unhitchAll():find("not hitched", 1, true) ~= nil)
            WinchTow.result = nil
            check("looking at nothing: it says what to do", WinchHand.unhitchAll():find("look at a vehicle", 1, true) ~= nil)
            -- the body of a piece you look at wins over the joint nearest to the ray
            do
                local bodyPiece = { isDeleted = false, getName = function() return "Panel" end, getAttacherVehicle = function() return trac2 end, getAttachedImplements = function() return {} end }
                local d6 = {}
                trac2.detachImplementByObject = function(_, o) d6[#d6 + 1] = o end
                local savedRay, savedFlag, savedMission, savedBit, savedParent = raycastClosest, CollisionFlag, g_currentMission, bit32, getParent
                CollisionFlag = { VEHICLE = 1, DYNAMIC_OBJECT = 2 }
                bit32 = bit32 or { bor = function(a, b) return a + b end }
                getParent = function() return 0 end
                g_currentMission = { getNodeObject = function(_, n) return n == 777 and bodyPiece or nil end, vehicleSystem = { vehicles = {} } }
                raycastClosest = function(_, _, _, _, _, _, _, cbName, target) target[cbName](target, 777) end
                WinchHand.target = nil
                WinchTow.result = { vehicle = lonely, kind = "drawbar eye", index = 1 }               -- (a joint of ANOTHER piece is nearer to the ray)
                local said2 = WinchHand.unhitchAll()
                check("ctrl on a panel's body: that panel is unhitched, not the piece whose joint is nearest to the ray", said2:find("Panel", 1, true) ~= nil and d6[1] == bodyPiece)
                raycastClosest, CollisionFlag, g_currentMission, bit32, getParent = savedRay, savedFlag, savedMission, savedBit, savedParent
                WinchTow.result = nil
            end
            -- Ctrl and a click does the same
            local d4 = {}
            local mid2 = { isDeleted = false, getName = function() return "Mid2" end, getAttacherVehicle = function() return trac2 end, getAttachedImplements = function() return {} end, detachImplementByObject = function() end }
            trac2.detachImplementByObject = function(_, o) d4[#d4 + 1] = o end
            WinchHand.target = nil
            WinchTow.result = { vehicle = mid2, kind = "drawbar eye", index = 1 }
            Input = { isKeyPressed = function(k) return k == 305 end, KEY_lctrl = 305 }
            local viaClick = WinchHand.toggle()
            Input = nil
            check("Ctrl and a click: the piece is unhitched from everything, nothing is hooked", viaClick:find("unhitched from everything", 1, true) ~= nil and d4[1] == mid2 and WinchHand.target == nil)
            -- Shift and a click with the joint hooked: that joint is unhitched and the hook is let go
            local d5 = {}
            local mid3 = { isDeleted = false, getName = function() return "Mid3" end, getAttacherVehicle = function() return trac2 end }
            trac2.detachImplementByObject = function(_, o) d5[#d5 + 1] = o end
            WinchHand.target = { vehicle = mid3, kind = "drawbar eye", index = 1, node = 10, component = 100 }
            WinchTow.result = WinchHand.target
            Input = { isKeyPressed = function(k) return k == 304 end, KEY_lshift = 304 }
            local viaShift = WinchHand.toggle()
            Input = nil
            check("Shift and a click on the hooked joint: it is unhitched and the hook is let go", viaShift:find("unhitched", 1, true) ~= nil and d5[1] == mid3 and WinchHand.target == nil)
            WinchHand.target, WinchTow.result = keepTarget, keepResult
            Input = nil
        end
        -- two vehicles that are already hitched together offer no second joint
        do
            local hooked0 = WinchHand.target
            wagon.getAttacherVehicle = function() return tractor end
            local none2, why2 = WinchHand.attachCandidate()
            check("already hitched together: no second joint is offered, and it says why", none2 == nil and why2 ~= nil and why2:find("one joint between two vehicles", 1, true) ~= nil)
            local clickMsg = WinchHand.toggle()
            check("... and the click lets go (it never traps you at a bridge)", WinchHand.target == nil and clickMsg:find("let go", 1, true) ~= nil and clickMsg:find("one joint between two vehicles", 1, true) ~= nil)
            WinchTow.result = eye
            WinchHand.toggle()
            wagon.getAttacherVehicle = nil
            WinchHand.target = hooked0
        end
        -- two bridge pieces: the wire goes to the piece you AIM at, not to whichever joint lies nearest; and not to the far end of a piece that lies the other way round
        do
            local savedWire, savedCam = WinchWire, nodes[1]
            WinchWire = { isWired = function() return false end, MAX_M = 12 }
            nodes[1] = { 0, 1.7, 0 }                                        -- the camera; it looks along +x (the test's direction)
            local function piece(name) return { isDeleted = false, getName = function() return name end, bridgeLinkPair = function() end } end
            local start, aimed, near = piece("Start"), piece("Aimed"), piece("Near")
            local startHitch = { vehicle = start, node = 61, component = 610, kind = "hitch", jointType = "trailer", jointTypeId = 3, index = 1 }
            local aimedEye = { vehicle = aimed, node = 62, component = 620, kind = "drawbar eye", jointType = "trailer", jointTypeId = 3, index = 1 }
            local nearEye = { vehicle = near, node = 63, component = 630, kind = "drawbar eye", jointType = "trailer", jointTypeId = 3, index = 1 }
            local aimedHitch = { vehicle = aimed, node = 64, component = 620, kind = "hitch", jointType = "trailer", jointTypeId = 3, index = 2 }
            nodes[61], nodes[62], nodes[63], nodes[64] = { 3, 0, 8 }, { 6, 0, 0.2 }, { 3.2, 0, 6.5 }, { 3.0, 0, 0.2 }
            start.joints, aimed.joints, near.joints = { startHitch }, { aimedEye }, { nearEye }
            local keepMission, keepJointsOf, keepTarget = g_currentMission, WinchTow.jointsOf, WinchHand.target
            g_currentMission = { vehicleSystem = { vehicles = { start, aimed, near } } }
            WinchTow.jointsOf = function(v) return v.joints or {} end
            WinchHand.target = startHitch
            local c = WinchHand.attachCandidate()
            check("the hooked start piece: the wire goes to the piece you aim at (eye on the view ray), not to the nearer one", c == aimedEye)
            nodes[1] = { 0, 1.7, 20 }
            local c2 = WinchHand.attachCandidate()
            check("aiming at neither: no bridge piece is chosen for you", c2 == nil)
            nodes[1] = { 0, 1.7, 0 }
            aimed.joints = { aimedEye, aimedHitch }
            nodes[62], nodes[64] = { 6, 0, 0.2 }, { 5.2, 0, 0.2 }
            aimedHitch.x = nil
            nodes[61] = { 5.0, 0, 3 }
            -- the aimed piece lies the other way round: its hitch is next to the hooked hitch, its eye far away
            nodes[61], nodes[62] = { 5.1, 0, 1.0 }, { 9, 0, 0.2 }
            local c3, why3 = WinchHand.attachCandidate()
            check("a piece lying the other way round (its hitches face the hooked hitch): not its far eye, and it says to turn it", c3 == nil and why3 ~= nil and why3:find("turn it around", 1, true) ~= nil)
            g_currentMission, WinchTow.jointsOf, WinchHand.target = keepMission, keepJointsOf, keepTarget
            WinchWire, nodes[1] = savedWire, savedCam
        end
        local text = WinchHand.toggle()
        check("the click attaches the wagon to the tractor with the game's own call (the info the Q key uses)", attachedInfo ~= nil and attachedInfo.attacherVehicle == tractor and attachedInfo.attacherVehicleJointDescIndex == 1 and attachedInfo.attachable == wagon and attachedInfo.attachableJointDescIndex == 2 and text:find("attaching", 1, true) ~= nil)
        check("... and the hold ends (the game's attach has the wagon), no letting go", WinchHand.target == nil)
        WinchHand.hand = nil
        WinchTow.result = nil
        g_currentMission, WinchTow.jointsOf = savedMission, savedJointsOf
    end
    -- handed to a horse: the hold ends, the grip stays until the new owner lets it go
    do
        body = "dynamic"
        WinchHand.hold(20)
        WinchHand.toggle()
        local t3 = WinchHand.target
        local before = #deleted
        local handed = WinchHand.handOver()
        check("handing the log over ends the hold but keeps the grip node", handed == t3 and WinchHand.target == nil and #deleted == before)
        WinchHand.dropGrip(handed)
        check("the new owner lets the grip go with dropGrip", deleted[#deleted] == t3.node)
        check("nothing hooked: nothing to hand over", WinchHand.handOver() == nil)
        -- a vehicle's joint is handed over too: the support leg and the brake stay as the hook left them (the new owner puts them back)
        WinchHand.hand = 20
        WinchTow.result = picked
        WinchHand.toggle()
        local supportBefore, brakeBefore = #supportCalls, #brakeCalls
        local vehicleHandover = WinchHand.handOver()
        check("a hooked joint is handed over without letting go of it (no support or brake calls)", vehicleHandover == picked and WinchHand.target == nil and #supportCalls == supportBefore and #brakeCalls == brakeBefore)
        WinchTow.result = nil
        WinchHand.hand = nil
    end
    -- the ring on a log is for tools that can hook one: the harness tool passes false
    do
        WinchHand.hold(20, false)
        check("a tool that cannot hook logs (the harness) marks that in hold", WinchHand.hand == 20 and WinchHand.logsOk == false)
        WinchHand.hold(20)
        check("the leash and the hand winch can", WinchHand.logsOk == true)
        WinchHand.hand = nil
    end
    -- the game's strap and hook round the trunk, the rope ends at the hook
    do
        local made, hookDeleted, mounted = {}, 0, {}
        ForestryHook = { new = function(vehicle, link)
            local h = { hookId = nil }
            h.onI3DLoaded = function(self, node) self.hookId = node end
            h.mountToTree = function(self, shape, x, y, z) mounted = { shape, x, y, z }; return 5 end
            h.setTargetNode = function(self, node, dirty) self.target = node end
            h.getRopeTarget = function(self) return 777 end
            h.delete = function(self) hookDeleted = hookDeleted + 1 end
            made[#made + 1] = h
            return h
        end }
        XMLFile = { load = function() return { getString = function(_, _, default) return default end } end }
        g_i3DManager = { loadSharedI3DFile = function() return 55, 1, nil end }
        Utils = { getFilename = function(f) return f end }
        getRootNode = function() return 1 end
        WinchHand.hold(20)
        nodes[777] = { 5, 0.3, 0 }
        WinchHand.toggle()
        local t2 = WinchHand.target
        check("a hooked log gets the game's strap and hook at the point looked at, turned towards the hand", t2.hook == made[1] and mounted[1] == 200 and mounted[2] == 5 and made[1].target == 20)
        check("the rope ends at the hook's rope target, the force stays on the grip", t2.ropeNode == 777 and t2.node ~= 777)
        WinchHand.toggle()
        check("letting go deletes the hook (and its strap)", hookDeleted == 1 and WinchHand.target == nil)
        ForestryHook.new = function() local h = { delete = function() hookDeleted = hookDeleted + 1 end, onI3DLoaded = function() end }; return h end
        WinchHand.toggle()
        check("a hook that cannot be made (nothing loaded): the log is hooked at the grip all the same, no rope node", WinchHand.target ~= nil and WinchHand.target.hook == nil and WinchHand.target.ropeNode == nil and hookDeleted == 2)
        WinchHand.toggle()
        ForestryHook, XMLFile, g_i3DManager, Utils, getRootNode = nil, nil, nil, nil, nil
        WinchHand.hand = nil
    end
    WinchTow.result = picked
    check("with a joint in view the joint is hooked, not the log", WinchHand.toggle():find("drawbar eye", 1, true) ~= nil and WinchHand.target.kind == "drawbar eye")
    WinchHand.toggle()
    WinchTow.result = nil
end

-- the cap itself: the walk state's desired speed is cut to it, walking and running alike (the file is loaded again with the game's class in place)
do
    PlayerStateWalk = { calculateDesiredSpeed = function(self) return self.speed end }
    Utils = { overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end }
    dofile("scripts/WinchHand.lua")
    local walk = { speed = 7 }
    walk.calculateDesiredSpeed = PlayerStateWalk.calculateDesiredSpeed
    check("without a cap the game's speed is left alone (a run at 7 m/s)", walk:calculateDesiredSpeed() == 7)
    WinchHand.setSpeedCap("test", 3.5)
    check("a cap cuts a run (7 m/s) to it, and a walk below it is left alone", walk:calculateDesiredSpeed() == 3.5 and (function() walk.speed = 2; return walk:calculateDesiredSpeed() == 2 end)())
    walk.speed = -1.5
    check("walking backwards (a negative speed) is none of its business", walk:calculateDesiredSpeed() == -1.5)
    WinchHand.setSpeedCap("test", nil)
    walk.speed = 7
    check("the cap off: the run is 7 m/s again", walk:calculateDesiredSpeed() == 7)
    check("the class method was hooked (once: the flag)", WinchHand.walkHooked == true)
end

-- frozen or pinned: refused with wheels, allowed without (a bridge grate)
do
    local wheeled = { hdPinned = true, components = { { isStatic = false } }, spec_wheels = { wheels = { {}, {} } } }
    local grate = { hdPinned = true, components = { { isStatic = true } } }
    local loose = { components = { { isStatic = false } }, spec_wheels = { wheels = { {} } } }
    check("a pinned vehicle with wheels is locked", WinchHand.isLocked({ vehicle = wheeled }) == true)
    check("a pinned or frozen vehicle without wheels is not", WinchHand.isLocked({ vehicle = grate }) == false)
    check("a loose vehicle is not", WinchHand.isLocked({ vehicle = loose }) == false)
    check("a log or nothing is not", WinchHand.isLocked(nil) == false)
end

-- the floor of a hall lies above the terrain: the ground height is the ray's hit, not the terrain
do
    local savedRay, savedFlag, savedBit, savedNode, savedTerrain = raycastClosest, CollisionFlag, bit32, g_terrainNode, getTerrainHeightAtWorldPos
    g_terrainNode, getTerrainHeightAtWorldPos = 1, function() return 10.0 end
    CollisionFlag = { TERRAIN = 1, STATIC_OBJECT = 2, BUILDING = 4 }
    bit32 = { bor = function(a, b, c) return a + b + c end }
    raycastClosest = function(x, y, z, dx, dy, dz, dist, cb, obj, mask) obj[cb](obj, 5, x, 10.4, z, 1.0) end
    check("the ground under the eye is the floor the ray hits (a hall's concrete, 40 cm above the terrain), not the terrain", math.abs(WinchHand.groundY(0, 0, 11.2) - 10.4) < 1e-9)
    raycastClosest = function() end
    check("a ray that hits nothing: the terrain", math.abs(WinchHand.groundY(0, 0, 11.2) - 10.0) < 1e-9)
    check("no height given: the terrain, as before", math.abs(WinchHand.groundY(0, 0) - 10.0) < 1e-9)
    raycastClosest, CollisionFlag, bit32, g_terrainNode, getTerrainHeightAtWorldPos = savedRay, savedFlag, savedBit, savedNode, savedTerrain
end

print = realPrint
print(string.format("winchhand_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
