--[[
    WinchHand.lua -- the hand winch's work. The tool's action hooks onto the attacher joint of the vehicle you look at (WinchTow.pick, the same joints the winch rope can take), or lets it go.
    A hooked vehicle creeps towards you at up to 2 km/h while you stand further from its joint than STOP_M, and stops when you stand near it: walk to where you want it. It is a force on the joint's
    body towards you (a speed controller with a limit of ACCEL_MS2), so the vehicle steers round on its own wheels like something pulled.
    A vehicle nobody sits in has its brake pedal down (Wheels:addToPhysics and Drivable:onLeaveVehicle call vehicle:brake(1): wheel brake force plus the auto-hold force at standstill, 12 t did not move
    under 22 kN): while it is pulled the brake is let off (vehicle:brake(0)), when you stand near it, or let go, it is put back, so it stops where it is.
    The rope is let go when the tool is put away, when it gets longer than MAX_ROPE_M, or when the vehicle is gone. A debug line from your hand to the joint shows the rope for now.
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
function WinchHand.letGo(message)
    local target = WinchHand.target
    WinchHand.target = nil
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
function WinchHand.pick()
    local player = g_localPlayer
    if player == nil or not player.isControlled or WinchTow == nil then
        return nil
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    return WinchTow.pick({}, ox, oy, oz, dx, dy, dz, WinchHand.PICK_RANGE_M, nil)
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
        WinchHand.target = nil
        WinchHand.setSpeedCap("winchhand", nil)
        setBrakeOff(target, false)
        setSupportUp(target, false)
        return string.format("winch let go of the %s of %s", target.kind, vehicleName(target.vehicle))
    end
    local target = WinchHand.pick()
    if target == nil then
        return "look at an attacher joint (a drawbar eye, a hitch) within " .. WinchHand.PICK_RANGE_M .. " m"
    end
    WinchHand.target, WinchHand.pulledS, WinchHand.stuckReported = target, 0, false
    setSupportUp(target, true)
    local speed = WinchHand.pullSpeed(WinchHand.pullMass(target.vehicle, target.component))
    return string.format("winch hooked to the %s of %s: walk away from it, it follows you at up to %.0f km/h (the heavier, the slower, and so are you, running too); the same key lets go", target.kind, vehicleName(target.vehicle), speed * 3.6)
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
    if WinchHand.hand == nil or WinchHand.target ~= nil or (WinchHand.gate ~= nil and not WinchHand.gate()) then
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
    local picked = marker ~= nil and WinchHand.pick() or nil
    if picked == nil then
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
    if target ~= nil and WinchHand.hand ~= nil and target.node ~= nil and entityExists(target.node) and drawDebugLine ~= nil then
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
