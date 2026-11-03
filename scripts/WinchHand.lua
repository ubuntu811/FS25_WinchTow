--[[
    WinchHand.lua -- the hand winch's work. The tool's action hooks onto the attacher joint of the vehicle you look at (WinchTow.pick, the same joints the winch rope can take), or lets it go.
    A hooked vehicle creeps towards you at up to 2 km/h while you stand further from its joint than STOP_M, and stops when you stand near it: walk to where you want it. It is a force on the joint's
    body towards you (a speed controller with a limit of ACCEL_MS2), so the vehicle steers round on its own wheels like something pulled.
    A vehicle nobody sits in has its brake pedal down (Wheels:addToPhysics and Drivable:onLeaveVehicle call vehicle:brake(1): wheel brake force plus the auto-hold force at standstill, 12 t did not move
    under 22 kN): while it is pulled the brake is let off (vehicle:brake(0)), when you stand near it, or let go, it is put back, so it stops where it is.
    The rope is let go when the tool is put away, when it gets longer than MAX_ROPE_M, or when the vehicle is gone. The rope is the game's own steel cable (ForestryRope) from your hand to the joint (a green debug line when the engine pieces are missing).
    CARRY (a joint on a body of its own that is a small share of the vehicle: a trailer's tongue): no rope line and no stop radius. The hook is a staged affair, the way a horse's hitch does it: the support leg goes up,
    the tongue is lifted on its hinge to the height of a tractor's joint (EYE_HEIGHT_M) while the wagon is held where it is, then the eye is CARRIED: it trails you at CARRY_M behind, pulled with a force that
    wants the speed you walk away from it at plus a catch-up for the way it is behind, and that also brakes it when you stop (no brake on and off at a distance: that flapped when you stood about near it).
    POLE (anything else: a tractor, a joint on the main body): the same controller, but the joint is held POLE_M (2 m) from you on a stiff pole (drawn as a steel cable, 3 cm thick): pulled in when further away,
    pushed back when nearer, the gain 3 times the carry's, the machine is not lifted. POLE = false is the old pull above (1.2 m stop, brake on and off).
]]
WinchHand = {}
WinchHand.PULL_SPEED_MS = 2 / 3.6     -- 2 km/h: the speed a heavy vehicle (HEAVY_T and more) is pulled at
WinchHand.FAST_SPEED_MS = 3.5         -- the speed a light vehicle (LIGHT_T and less) is pulled at: about a brisk walk (the game's walk speed is 4 m/s)
WinchHand.LIGHT_T, WinchHand.HEAVY_T = 1.2, 10      -- tonnes: between the two the speed falls in a straight line (a little wagon is no effort, a loaded trailer is a crawl)
WinchHand.ACCEL_MS2 = 3              -- the most the pull accelerates the vehicle (force = mass * this, so a heavier vehicle is pulled harder)
WinchHand.PICK_RANGE_M = 6
WinchHand.STOP_M = 1.2                -- the joint is not pulled closer to you than this (horizontally)
WinchHand.MAX_ROPE_M = 15
WinchHand.STUCK_S = 2                 -- pulling this long without moving is reported once
WinchHand.CARRY = true                -- a trailer's tongue is lifted and carried (below); false: every vehicle is pulled the old way
WinchHand.POLE = true                 -- a joint that is no tongue (a tractor's hitch, a joint on the main body) is held at the end of a stiff pole: below; false: pulled the old way (the 1.2 m stop and the brake on and off)
WinchHand.POLE_M = 2                  -- the pole's length: the joint is held this far (horizontally) from you, pulled in when it is further, pushed back when it is nearer (the tractor does not end up in your face)
WinchHand.POLE_GAIN = 12              -- 1/s: speed wanted per metre the joint is off the pole's length (a steel rod, not a rubber band: 3 times the carry's)
WinchHand.NUDGE = true                -- the steering nudge: a pulled tractor does not steer, its axles drag sideways and it swings round at you. A couple (two opposite forces, no net push) at the joint and at the far end of its body turns it
WinchHand.NUDGE_MS2 = 1               -- ... along the pole: force = mass * this at full strength (an error of NUDGE_FULL_RAD), in proportion below
WinchHand.NUDGE_FULL_RAD = 0.5
WinchHand.NUDGE_MIN_ARM_M = 0.3       -- (a joint this close to its body's origin has no lever)
WinchHand.POLE_DIAMETER = 0.03        -- the pole is drawn as the cable at this thickness (the horse's tow bar is the same)
WinchHand.CARRY_M = 0.8               -- the carried eye trails you by this much (horizontally), on the line to where it is
WinchHand.EYE_HEIGHT_M = 0.81         -- the height above the ground the tongue's eye is carried at: the height of a tractor's attacher joint (measured), every trailer is made to hang on it
WinchHand.LIFT_MS = 1.0               -- the tongue is lifted at this speed at most ...
WinchHand.LIFT_ACCEL_MS2 = 4          -- ... getting there this smoothly ...
WinchHand.LIFT_GAIN = 4               -- ... 1/s: speed wanted per metre the eye is below its height
WinchHand.LIFT_DONE_M = 0.05          -- lifted when the eye is this close to its height
WinchHand.LIFT_MAX_S = 3              -- and not tried longer than this (a hinge at its stop does not get further)
WinchHand.LIFT_MAX_SHARE = 0.25       -- only a joint on a body this small a share of the vehicle is lifted (a tongue of 60 kg of 660); a plate on the main body would tilt the whole machine
WinchHand.POS_GAIN = 4                -- 1/s: speed wanted per metre the carried eye is further from you than CARRY_M
WinchHand.PULL_TAU_S = 0.3            -- the force wants the speed it is short of within this time (at most ACCEL_MS2)
WinchHand.VELOCITY_FILTER_S = 0.15    -- your speed (from your position: it moves in steps) is smoothed over this long
WinchHand.SHOW_LINE = false           -- the debug line from the hand to the joint (the old pull draws it always)

WinchHand.ROPE = true                 -- the line from the hand to the joint is the game's own steel cable (ForestryRope, what the winch draws); false: the green debug line
WinchHand.ROPE_FILE, WinchHand.ROPE_NODE, WinchHand.ROPE_DIAMETER, WinchHand.ROPE_UV = "$data/shared/forestry/ropes.i3d", "4", 0.015, 4
WinchHand.hand = nil                  -- the node of the tool while it is in the hand
WinchHand.target = nil                -- { vehicle, node, component, kind } while hooked
WinchHand.pulledS, WinchHand.stuckReported = 0, false

function WinchHand.notify(text)
    print("[WinchHand] " .. text)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_INFO ~= nil then
        pcall(g_currentMission.addIngameNotification, g_currentMission, FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
end

function WinchHand.hold(node)
    WinchHand.hand = node
end

-- The speed a vehicle of this mass (tonnes) is pulled at, m/s.
function WinchHand.pullSpeed(mass)
    if mass <= WinchHand.LIGHT_T then
        return WinchHand.FAST_SPEED_MS
    elseif mass >= WinchHand.HEAVY_T then
        return WinchHand.PULL_SPEED_MS
    end
    local t = (mass - WinchHand.LIGHT_T) / (WinchHand.HEAVY_T - WinchHand.LIGHT_T)
    return WinchHand.FAST_SPEED_MS + (WinchHand.PULL_SPEED_MS - WinchHand.FAST_SPEED_MS) * t
end

-- The player's speed caps, by source (the hand winch, a horse that pulls: published for other mods): the walk state's speed is cut to the lowest of them. The hand tool's walk and run multipliers do not do
-- it: walking is lerp(0, 4, walk * multiplier), but running is lerp(4, 7, run * multiplier): its floor is the whole walk speed, so a runner is never slower than 4 m/s whatever the multiplier is.
WinchHand.speedCaps = {}
function WinchHand.setSpeedCap(source, cap)
    WinchHand.speedCaps[source] = cap
end

function WinchHand.speedCap()
    local least = nil
    for _, cap in pairs(WinchHand.speedCaps) do
        least = least ~= nil and math.min(least, cap) or cap
    end
    return least
end

-- Brake pedal of the hooked vehicle: off while it is pulled (true), down otherwise (false). Only a call when it changes (Wheels:brake ignores the same value, so the brake lights do not flicker).
-- The support leg (WinchTow.setSupport): up while hooked, down when let go.
local function setSupportUp(target, up)
    if WinchTow ~= nil and WinchTow.setSupport ~= nil and target.vehicle ~= nil then
        pcall(WinchTow.setSupport, target.vehicle, up)
    end
end

local function setBrakeOff(target, off)
    local vehicle = target.vehicle
    if vehicle ~= nil and vehicle.brake ~= nil and not vehicle.isDeleted then
        pcall(vehicle.brake, vehicle, off and 0 or 1)
    end
end

-- published for other mods with the rest (g_currentMission.winchTow): what a puller that is not the player (a horse in its harness) does to the vehicle it pulls
WinchHand.setBrakeOff, WinchHand.setSupportUp = setBrakeOff, setSupportUp

-- The mass the pull has to move: the whole vehicle, not the body the joint sits on (a trailer's drawbar is often a body of its own: 60 kg of a 660 kg wagon, pulled with a force for 60 kg, it barely
-- moved). Tonnes. Published for the horse's hitch.
function WinchHand.pullMass(vehicle, component)
    if vehicle ~= nil and vehicle.getTotalMass ~= nil then
        local ok, mass = pcall(vehicle.getTotalMass, vehicle, true)
        if ok and mass ~= nil and mass > 0 then
            return mass
        end
    end
    return getMass(component)
end

-- Lets go of the hooked vehicle: the brake goes back on (unless the vehicle is gone), and the reason is said.
-- The cable from the hand to the joint: a ForestryRope linked to the tool's node, pointing at the joint node (the engine stretches it every frame), made when it is first wanted.
function WinchHand.dropRope()
    local rope = WinchHand.rope
    WinchHand.rope = nil
    if rope ~= nil then
        pcall(rope.delete, rope)
    end
end

local function ropeUpdate(rope, dt)                  -- (the game's update fails every frame when a node it points at was deleted with its vehicle)
    if rope.referenceFrame == nil or not entityExists(rope.referenceFrame) or rope.targetNode == nil or not entityExists(rope.targetNode) then
        return
    end
    return ForestryRope.update(rope, dt)
end

-- true when the cable is there (made, or on its way: the shape loads asynchronously); false when the engine pieces are missing (the debug line is drawn then)
function WinchHand.showRope(target)
    if not WinchHand.ROPE or ForestryRope == nil or ForestryRope.new == nil or g_i3DManager == nil or Utils == nil or Utils.getFilename == nil then
        return false
    end
    local rope = WinchHand.rope
    if rope ~= nil and (rope.rfTarget ~= target.node or rope.linkNode ~= WinchHand.hand) then
        WinchHand.dropRope()
        rope = nil
    end
    if rope == nil then
        local ok, made = pcall(function()
            local r = ForestryRope.new(nil, WinchHand.hand)
            r.i3dFilename, r.i3dRopePath = Utils.getFilename(WinchHand.ROPE_FILE, nil), WinchHand.ROPE_NODE
            r.diameter, r.uvScale = WinchHand.stage == "pole" and WinchHand.POLE_DIAMETER or WinchHand.ROPE_DIAMETER, WinchHand.ROPE_UV
            r.emissiveColor, r.invalidEmissiveColor = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
            r.update = ropeUpdate
            r.rfTarget = target.node
            r.sharedLoadRequestId = g_i3DManager:loadSharedI3DFileAsync(r.i3dFilename, false, false, r.onI3DLoaded, r, r)
            return r
        end)
        if not ok then
            print("[WinchHand] the cable could not be made: " .. tostring(made))
            WinchHand.ROPE = false
            return false
        end
        WinchHand.rope = made
        rope = made
    end
    if rope.referenceFrame ~= nil and not rope.tied then
        rope.tied = pcall(rope.setTargetNode, rope, target.node, true)
    end
    return true
end

function WinchHand.letGo(message)
    local target = WinchHand.target
    WinchHand.target, WinchHand.stage = nil, nil
    WinchHand.dropRope()
    WinchHand.setSpeedCap("winchhand", nil)
    if target ~= nil then
        setBrakeOff(target, false)
        setSupportUp(target, false)
        WinchHand.notify(message)
    end
end

local hideMarker                      -- (defined with the marker below)

function WinchHand.putAway(node)
    if WinchHand.hand ~= node then
        return
    end
    WinchHand.hand, WinchHand.gate = nil, nil
    hideMarker()
    WinchHand.letGo("winch let go (the tool was put away)")
end

local function vehicleName(vehicle)
    if vehicle.getName ~= nil then
        local ok, name = pcall(vehicle.getName, vehicle)
        if ok and name ~= nil then
            return tostring(name)
        end
    end
    return tostring(vehicle.configFileName or "vehicle")
end

-- The joint in front of the player's view, or nil.
-- The joint you look at. all (WinchHand's own use, and WAILA's readout): every joint, also a vehicle's linkage joint that the horse's hitch and the winch rope leave out; a plain call is the filtered pick the
-- horse uses.
function WinchHand.pick(all)
    local player = g_localPlayer
    if player == nil or not player.isControlled or WinchTow == nil then
        return nil
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    return WinchTow.pick({}, ox, oy, oz, dx, dy, dz, WinchHand.PICK_RANGE_M, nil, all)
end

-- The joint you look at, in words (published for other mods: WAILA shows it): nil when none is in sight. The pick is asked at most five times a second, the answer is kept in between.
-- look() is one short row (the kind and the game's name of the type), lookLines() the full description (a list of lines).
WinchHand.LOOK_RING_MS = 600          -- the green ring stays on a joint that was asked about (WAILA) this long: it is shown while somebody keeps asking, with no tool in the hand
function WinchHand.refreshLook()
    local now = g_time or 0
    WinchHand.lookAskedAt = now
    if WinchHand.lookAt == nil or now - WinchHand.lookAt >= 200 or now < WinchHand.lookAt then
        WinchHand.lookAt = now
        local target = WinchHand.pick(true)
        WinchHand.lookTarget = target
        WinchHand.lookText = target ~= nil and WinchTow.describe(target) or nil
        WinchHand.lookList = target ~= nil and WinchTow.describe(target, true) or nil
    end
end

function WinchHand.look()
    WinchHand.refreshLook()
    return WinchHand.lookText
end

function WinchHand.lookLines()
    WinchHand.refreshLook()
    return WinchHand.lookList
end

-- The joint nearest to a point (published for other mods: a horse that backs up to a trailer): see WinchTow.nearest.
function WinchHand.nearest(x, z, radius, except)
    if WinchTow == nil or WinchTow.nearest == nil then
        return nil
    end
    return WinchTow.nearest(x, z, radius, except)
end

-- The tool's action: hook onto the joint you look at, or let go. Returns a message.
function WinchHand.toggle()
    if WinchHand.target ~= nil then
        local target = WinchHand.target
        WinchHand.target, WinchHand.stage = nil, nil
        WinchHand.setSpeedCap("winchhand", nil)
        setBrakeOff(target, false)
        setSupportUp(target, false)
        return string.format("winch let go of the %s of %s", target.kind, vehicleName(target.vehicle))
    end
    local target = WinchHand.pick(true)
    if target == nil then
        return "look at an attacher joint (a drawbar eye, a hitch) within " .. WinchHand.PICK_RANGE_M .. " m"
    end
    WinchHand.target, WinchHand.pulledS, WinchHand.stuckReported = target, 0, false
    setSupportUp(target, true)
    -- a tongue is lifted first, then carried (updateCarry); the other joints are pulled the old way
    WinchHand.stage = WinchHand.CARRY and WinchHand.liftable(target) and "lift" or WinchHand.POLE and "pole" or nil
    WinchHand.liftS, WinchHand.liftV, WinchHand.supportWaitS, WinchHand.lastPx, WinchHand.lastPz, WinchHand.pvx, WinchHand.pvz = 0, 0, 0, nil, nil, 0, 0
    local speed = WinchHand.pullSpeed(WinchHand.pullMass(target.vehicle, target.component))
    return string.format("winch hooked to the %s of %s: walk away from it, it follows you at up to %.0f km/h (the heavier, the slower, and so are you, running too); the same key lets go", target.kind, vehicleName(target.vehicle), speed * 3.6)
end

function WinchHand.groundY(x, z)
    if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
        return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    end
    return 0
end

-- Is this joint a tongue: on a body of its own that is a small share of the vehicle (LIFT_MAX_SHARE), not a machine's own hitch ("hitch": its body is right behind the plate).
function WinchHand.liftable(target)
    if target.kind == "hitch" or target.component == nil then
        return false
    end
    -- the share among the vehicle's OWN bodies, not of the mass the game counts (belted logs add to that, which made the whole trailer's frame look like a small tongue and lifted its nose)
    local own = 0
    for _, component in ipairs(target.vehicle ~= nil and target.vehicle.components or {}) do
        if component.node ~= nil then
            own = own + getMass(component.node)
        end
    end
    if own <= 0 then
        own = WinchHand.pullMass(target.vehicle, target.component)
    end
    return getMass(target.component) <= WinchHand.LIFT_MAX_SHARE * own
end

-- The vehicle stands: the brake is on, every body of it is held at no horizontal speed and no turn, and the tongue (the joint's body) is driven up at liftV when that is given. Nothing is let to roll
-- off a slope while the tongue is lifted (a wagon whose brake was let off for the lift rolled two horse lengths away).
function WinchHand.holdStill(target, liftV)
    setBrakeOff(target, false)
    for _, component in ipairs(target.vehicle.components or { { node = target.component } }) do
        local node = component.node
        if node ~= nil and (entityExists == nil or entityExists(node)) then
            local _, vy, _ = getLinearVelocity(node)
            if node == target.component and liftV ~= nil then
                vy = liftV
            end
            setLinearVelocity(node, 0, vy, 0)
            setAngularVelocity(node, 0, 0, 0)
        end
    end
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- A hooked tongue, every frame (jx, jy, jz: the eye; px, pz: you; d: the way between, horizontally; seconds: the frame). Step one, "lift": the support animation is waited for (up to 3 s: on some trailers it is the
-- tongue's hinge), then the tongue is DRIVEN up to EYE_HEIGHT_M at a speed that ramps up on its own (not on what the physics reports: it takes the speed a step off every frame) with the wagon held (holdStill).
-- Step two, "carry": the brake is off for good, the eye is pulled with a force towards the speed it should have, which is your own speed away from it (smoothed) plus POS_GAIN per metre it is further than CARRY_M,
-- at most the pull speed, and nothing at all when it is nearer: the force then brakes it (the speed wanted is none). The eye is kept at its height meanwhile.
-- The steering nudge of the pole: the machine's body should lie along the pole, its joint towards you. a = from the body's origin to the joint, t = from the joint to you; the angle between them is turned
-- out by a couple: +F across a at the joint, -F at the far end of the body (the origin as far behind as the joint is ahead): no net force, so it only turns, the way the pulling force swings it anyway.
function WinchHand.steer(target, jx, jy, jz, px, pz, d, mass)
    local cx, cy, cz = getWorldTranslation(target.component)
    local ax, az = jx - cx, jz - cz
    local arm = math.sqrt(ax * ax + az * az)
    if arm < WinchHand.NUDGE_MIN_ARM_M or d < 1e-3 then
        return
    end
    ax, az = ax / arm, az / arm
    local tx, tz = (px - jx) / d, (pz - jz) / d
    local cross = ax * tz - az * tx                                          -- (sin of the angle from a to t, + turning towards t is the way of n)
    local dot = ax * tx + az * tz
    local angle = math.atan2(cross, dot)
    local strength = clamp(math.abs(angle) / WinchHand.NUDGE_FULL_RAD, 0, 1)
    if strength < 1e-3 then
        return
    end
    local nx, nz = -az, ax                                                   -- (across a, to its left)
    local sign = angle >= 0 and 1 or -1
    local f = mass * WinchHand.NUDGE_MS2 * strength * sign
    addForce(target.component, nx * f, 0, nz * f, jx, jy, jz, false)
    addForce(target.component, -nx * f, 0, -nz * f, cx - ax * arm, jy, cz - az * arm, false)
end

function WinchHand.updateCarry(target, jx, jy, jz, px, pz, d, mass, pullSpeed, seconds)
    local goalY = WinchHand.groundY(jx, jz) + WinchHand.EYE_HEIGHT_M
    local err = goalY - jy
    if WinchHand.stage == "lift" then
        local attachable = target.vehicle.spec_attachable
        if attachable ~= nil and target.vehicle.getIsAnimationPlaying ~= nil and WinchHand.supportWaitS < 3 then
            for _, support in ipairs(attachable.supportAnimations or {}) do
                if support.animationName ~= nil and target.vehicle:getIsAnimationPlaying(support.animationName) then
                    WinchHand.supportWaitS = WinchHand.supportWaitS + seconds
                    WinchHand.holdStill(target, nil)
                    return
                end
            end
        end
        WinchHand.liftS = WinchHand.liftS + seconds
        local want = clamp(err * WinchHand.LIFT_GAIN, -WinchHand.LIFT_MS, WinchHand.LIFT_MS)
        local step = WinchHand.LIFT_ACCEL_MS2 * seconds
        WinchHand.liftV = WinchHand.liftV + clamp(want - WinchHand.liftV, -step, step)
        WinchHand.holdStill(target, WinchHand.liftV)
        if math.abs(err) < WinchHand.LIFT_DONE_M or WinchHand.liftS > WinchHand.LIFT_MAX_S then
            WinchHand.stage = "carry"
            print(string.format("[WinchHand] the tongue is up (%.2f m short, %.1f s): the eye is carried now", err, WinchHand.liftS))
        end
        return
    end
    -- your speed, smoothed (the capsule moves in steps)
    if WinchHand.lastPx ~= nil then
        local alpha = seconds / (WinchHand.VELOCITY_FILTER_S + seconds)
        WinchHand.pvx = WinchHand.pvx + ((px - WinchHand.lastPx) / seconds - WinchHand.pvx) * alpha
        WinchHand.pvz = WinchHand.pvz + ((pz - WinchHand.lastPz) / seconds - WinchHand.pvz) * alpha
    end
    WinchHand.lastPx, WinchHand.lastPz = px, pz
    setBrakeOff(target, true)
    local ux, uz = 1, 0                                                      -- (from you to the eye)
    if d > 1e-3 then
        ux, uz = (jx - px) / d, (jz - pz) / d
    end
    local away = -(WinchHand.pvx * ux + WinchHand.pvz * uz)                  -- (your speed away from the eye)
    local pole = WinchHand.stage == "pole"
    local reach, gain = pole and WinchHand.POLE_M or WinchHand.CARRY_M, pole and WinchHand.POLE_GAIN or WinchHand.POS_GAIN
    local speed = 0
    if d > reach then
        speed = clamp(math.max(0, away) + gain * (d - reach), 0, pullSpeed)
    elseif pole then
        speed = -clamp(gain * (reach - d), 0, pullSpeed)                      -- (a pole is stiff: it pushes the joint back from you)
    end
    local vx, _, vz = getLinearVelocity(target.component)
    local ax, az = (-ux * speed - vx) / WinchHand.PULL_TAU_S, (-uz * speed - vz) / WinchHand.PULL_TAU_S
    local a = math.sqrt(ax * ax + az * az)
    if a > WinchHand.ACCEL_MS2 then
        ax, az = ax * WinchHand.ACCEL_MS2 / a, az * WinchHand.ACCEL_MS2 / a
        a = WinchHand.ACCEL_MS2
    end
    if a > 1e-3 then
        addForce(target.component, ax * mass, 0, az * mass, jx, jy, jz, false)    -- (tonnes * m/s2 = kN)
    end
    if pole then
        if WinchHand.NUDGE then
            WinchHand.steer(target, jx, jy, jz, px, pz, d, mass)
        end
        return                                                               -- (a pole holds the joint's distance only: the machine is not lifted)
    end
    -- the eye is held at its height: the tongue's vertical speed only
    local vy = clamp(err * WinchHand.LIFT_GAIN, -WinchHand.LIFT_MS, WinchHand.LIFT_MS)
    setLinearVelocity(target.component, vx, vy, vz)
end

-- Every frame: pulls the hooked vehicle's joint towards the player.
function WinchHand.update(_, dt)
    -- published for other mods (mod globals are invisible between mods): the leash of FS25_HorseDynamics uses it as an easter egg (hold, putAway, pick, toggle, target)
    if g_currentMission ~= nil and g_currentMission.winchTow ~= WinchHand then
        g_currentMission.winchTow = WinchHand
    end
    WinchHand.updateMarker(dt)
    local target = WinchHand.target
    if target == nil then
        return
    end
    local player = g_localPlayer
    if target.vehicle.isDeleted or target.node == nil or not entityExists(target.node) or player == nil or not player.isControlled then
        WinchHand.letGo("winch let go (the vehicle is gone)")
        return
    end
    local jx, jy, jz = getWorldTranslation(target.node)
    local px, _, pz = getWorldTranslation(player:getCurrentCameraNode())
    local ex, ez = px - jx, pz - jz
    local d = math.sqrt(ex * ex + ez * ez)
    if d > WinchHand.MAX_ROPE_M then
        WinchHand.letGo(string.format("winch let go: the rope would be %.0f m (more than %d m)", d, WinchHand.MAX_ROPE_M))
        return
    end
    -- the pull speed depends on what is pulled, and the player walks and runs no faster than that (the speed cap on the walk state)
    local mass = WinchHand.pullMass(target.vehicle, target.component)
    local pullSpeed = WinchHand.pullSpeed(mass)
    WinchHand.setSpeedCap("winchhand", pullSpeed)
    if WinchHand.stage ~= nil then
        WinchHand.updateCarry(target, jx, jy, jz, px, pz, d, mass, pullSpeed, math.max((dt or 16) / 1000, 0.001))
        return
    end
    if d <= WinchHand.STOP_M then
        WinchHand.pulledS = 0
        setBrakeOff(target, false)                                          -- (it stops where it is)
        return
    end
    setBrakeOff(target, true)
    local dirX, dirZ = ex / d, ez / d
    local vx, _, vz = getLinearVelocity(target.component)
    local along = vx * dirX + vz * dirZ
    local accel = math.min(WinchHand.ACCEL_MS2, math.max(0, (pullSpeed - along) / 0.3))
    if accel > 0 then
        local force = mass * accel                                          -- (tonnes * m/s2 = kN)
        addForce(target.component, dirX * force, 0, dirZ * force, jx, jy, jz, false)
    end
    -- a vehicle that is pulled and does not move: its brake holds it (or something is in the way): said once
    if along < 0.03 then
        WinchHand.pulledS = WinchHand.pulledS + (dt or 0) / 1000
        if WinchHand.pulledS >= WinchHand.STUCK_S and not WinchHand.stuckReported then
            WinchHand.stuckReported = true
            print(string.format("[WinchHand] pulling for %d s and the vehicle does not move (%.2f m/s towards you, %.1f t, force %.1f kN): something holds it: its wheels are stuck, or it is blocked", WinchHand.STUCK_S, along, mass, mass * accel))
        end
    else
        WinchHand.pulledS, WinchHand.stuckReported = 0, false
    end
end

-- The green ring round the joint the tool would hook (the winch's own TargetTreeMarker: the same ring and glow). Shown while the tool is in the hand, nothing is hooked, and the gate (set by the owner of
-- the tool: the leash only hooks when no horse is in reach) agrees. The pick is looked up ten times a second, not every frame.
WinchHand.MARKER_RADIUS_M = 0.18
WinchHand.MARKER_EVERY_MS = 100
WinchHand.gate = nil                  -- optional function() -> bool: whether the tool's click would hook
WinchHand.marker, WinchHand.markerMs, WinchHand.markerShown = nil, 0, false

local function ensureMarker()
    if WinchHand.marker ~= nil or TargetTreeMarker == nil or getRootNode == nil or g_i3DManager == nil then
        return WinchHand.marker
    end
    local ok, marker = pcall(TargetTreeMarker.new, nil, getRootNode())
    if not ok or marker == nil then
        return nil
    end
    marker.filename = "data/shared/forestry/targetTreeMarker.i3d"
    marker.width, marker.offset, marker.color = 0.05, 0.01, { 0, 2, 0 }
    local loaded, requestId = pcall(g_i3DManager.loadSharedI3DFileAsync, g_i3DManager, marker.filename, false, false, marker.onI3DLoaded, marker, marker)
    if not loaded then
        return nil
    end
    marker.sharedLoadRequestId = requestId
    WinchHand.marker = marker
    return marker
end

hideMarker = function()
    if WinchHand.markerShown and WinchHand.marker ~= nil then
        WinchHand.marker:setIsActive(false)
    end
    WinchHand.markerShown = false
end

function WinchHand.updateMarker(dt)
    -- with the tool in the hand the ring is on the joint a click would hook (as before); without it, on the joint somebody asked about a moment ago (WinchHand.look: WAILA shows the joint in words, and this ring
    -- says which of the several points behind a tractor it means)
    local toolMode = WinchHand.hand ~= nil and WinchHand.target == nil and (WinchHand.gate == nil or WinchHand.gate())
    local asked = WinchHand.target == nil and WinchHand.lookTarget ~= nil and WinchHand.lookAskedAt ~= nil and (g_time or 0) - WinchHand.lookAskedAt < WinchHand.LOOK_RING_MS
    if not toolMode and not asked then
        hideMarker()
        WinchHand.markerMs = WinchHand.MARKER_EVERY_MS
        return
    end
    WinchHand.markerMs = WinchHand.markerMs + (dt or 0)
    if WinchHand.markerMs < WinchHand.MARKER_EVERY_MS then
        return
    end
    WinchHand.markerMs = 0
    local marker = ensureMarker()
    local picked = nil
    if marker ~= nil then
        picked = toolMode and WinchHand.pick(true) or WinchHand.lookTarget
    end
    if picked == nil or picked.node == nil or (entityExists ~= nil and not entityExists(picked.node)) then
        hideMarker()
        return
    end
    local ux, uy, uz = localDirectionToWorld(picked.node, 0, 1, 0)
    marker:setIsActive(true)
    marker:setPosition(picked.x, picked.y, picked.z, ux, uy, uz, WinchHand.MARKER_RADIUS_M)
    WinchHand.markerShown = true
end

function WinchHand.deleteMarker()
    if WinchHand.marker ~= nil then
        pcall(WinchHand.marker.delete, WinchHand.marker)
        WinchHand.marker, WinchHand.markerShown = nil, false
    end
end

WinchHand.delete = WinchHand.deleteMarker     -- (mod event listener: the mission is going)

-- The rope, as a debug line from the hand to the joint (a model of a rope comes later).
function WinchHand.draw()
    local target = WinchHand.target
    local wanted = target ~= nil and (WinchHand.stage == nil or WinchHand.stage == "pole" or WinchHand.SHOW_LINE) and WinchHand.hand ~= nil and target.node ~= nil and entityExists(target.node)
    if not wanted then
        WinchHand.dropRope()
        return
    end
    if not WinchHand.showRope(target) and drawDebugLine ~= nil then
        local hx, hy, hz = getWorldTranslation(WinchHand.hand)
        local jx, jy, jz = getWorldTranslation(target.node)
        pcall(drawDebugLine, hx, hy, hz, 0.2, 1, 0.2, jx, jy, jz, 0.2, 1, 0.2)
    end
end

-- the cap itself: the walk state's desired speed is cut to the lowest cap (walking and running alike)
if PlayerStateWalk ~= nil and PlayerStateWalk.calculateDesiredSpeed ~= nil and Utils ~= nil and not WinchHand.walkHooked then
    WinchHand.walkHooked = true
    PlayerStateWalk.calculateDesiredSpeed = Utils.overwrittenFunction(PlayerStateWalk.calculateDesiredSpeed, function(self, superFunc, ...)
        local speed = superFunc(self, ...)
        local cap = WinchHand.speedCap()
        if cap ~= nil and speed > cap then
            return cap
        end
        return speed
    end)
end

if addModEventListener ~= nil then
    addModEventListener(WinchHand)
end
