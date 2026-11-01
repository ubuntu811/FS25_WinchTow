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
    TargetTreeMarker = nil
    WinchHand.hold(20)
    WinchHand.update(WinchHand, 200)
    check("ring: without the marker class (an older game) nothing breaks", WinchHand.marker == nil)
    WinchHand.putAway(20)
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
