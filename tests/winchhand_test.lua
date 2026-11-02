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
local vehicle = { isDeleted = false, getName = function() return "Old Trailer" end, brake = function(self, pedal) brakeCalls[#brakeCalls + 1] = pedal end }
local picked = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" }
local supportCalls = {}
WinchTow = { pick = function(winch, ox, oy, oz, dx, dy, dz, range) WinchTow.range = range; return WinchTow.result end, result = picked,
    setSupport = function(vehicle, up) supportCalls[#supportCalls + 1] = up and "up" or "down"; return true end }
local listeners = {}
addModEventListener = function(l) listeners[#listeners + 1] = l end
g_currentMission = nil

dofile("scripts/WinchHand.lua")
WinchHand.POLE = false                       -- (the old pull is tested first: the pole has its own block at the end)
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
    WinchHand.putAway(20)
    check("ring: tool put away: no ring, and the gate is forgotten", not m.active and WinchHand.gate == nil)
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

print = realPrint
print(string.format("winchhand_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
