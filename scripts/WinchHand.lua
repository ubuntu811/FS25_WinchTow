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
WinchHand.LATCH_ROPE_MAX_M = 150      -- a latch of a pinned pole is hooked to lay a wire to another latch: you walk there, so the rope may be this long
WinchHand.STUCK_S = 2                 -- pulling this long without moving is reported once
WinchHand.CARRY = true                -- a trailer's tongue is lifted and carried (below); false: every vehicle is pulled the old way
WinchHand.POLE = true                 -- a joint that is no tongue (a tractor's hitch, a joint on the main body) is held at the end of a stiff pole: below; false: pulled the old way (the 1.2 m stop and the brake on and off)
WinchHand.POLE_M = 2                  -- the pole's length: the joint is held this far (horizontally) from you, pulled in when it is further, pushed back when it is nearer (the tractor does not end up in your face)
WinchHand.POLE_GAIN = 12              -- 1/s: speed wanted per metre the joint is off the pole's length (a steel rod, not a rubber band: 3 times the carry's)
WinchHand.NUDGE = true                -- the steering nudge: a pulled tractor does not steer, its axles drag sideways and it swings round at you. A couple (two opposite forces, no net push) at the joint and at the far end of its body turns it
WinchHand.NUDGE_MS2 = 1               -- ... along the pole: force = mass * this at full strength (an error of NUDGE_FULL_RAD), in proportion below
WinchHand.NUDGE_FULL_RAD = 0.5
WinchHand.NUDGE_MIN_ARM_M = 0.3       -- (a joint this close to its body's origin has no lever)
WinchHand.LOGS = true                 -- a felled tree or a log on the ground can be hooked too (below): it is dragged behind you on a rope; false: joints only
WinchHand.LOG_REACH_M = 2.5           -- a dragged log is pulled in when it is further from you than this (horizontally), and left alone when nearer (a rope goes slack, it does not push)
WinchHand.LOG_LIFT_SHARE = 0.35       -- the pull also lifts this share of a dragged log's weight at the grip: its front rides over the ground (a real winch lifts the end it drags)
WinchHand.LOG_ACCEL_MS2 = 6           -- the most a dragged log is accelerated at: more than a vehicle's pull, the ground rubs on it all the way
WinchHand.TRAFFIC_SEES_LOGS = true    -- while a log is hooked it is also on the collision group that traffic brakes for (DYNAMIC_OBJECT), so cars stop for it instead of driving into it; restored on let-go
WinchHand.RING_MIN_M = 0.45           -- the ring (and strap) keeps at least this much log on both sides: looking near a cut end slides it along the trunk (the game's own marker uses 0.15)
WinchHand.RING_SLIDE_M = 1.0          -- ... by at most this far
WinchHand.BRING_CLOSER_M = 8          -- a fitting joint farther away than this is not what you are bringing the hooked one to: the click lets go (the hold is kept only for 3 to 8 m, 'bring it closer')
WinchHand.ATTACH_REACH_M = 3          -- a hooked wagon's eye is attached to a tractor's hitch only when it is this close to it (the game then pulls it in); further away the click says to bring it closer
WinchHand.HOOK = true                 -- a hooked log gets the game's own strap and hook round the trunk (ForestryHook, what the winch puts on a tree); false: the rope ends at the grip point
WinchHand.HOOK_FILE = "$data/shared/forestry/treeHook01.xml"
WinchHand.POLE_DIAMETER = 0.03        -- the pole is drawn as the cable at this thickness (the horse's tow bar is the same)
WinchHand.CARRY_M = 0.8               -- the carried eye trails you by this much (horizontally), on the line to where it is
WinchHand.EYE_TO_FEET_M = 1.75        -- the player's camera above the floor under the feet (standing)
WinchHand.FEET_NEAR_M = 6             -- the floor under your feet counts for the tongue's height only when you are this close to it (horizontally)
WinchHand.EYE_HEIGHT_M = 0.81         -- the height above the ground the tongue's eye is carried at: the height of a tractor's attacher joint (measured), every trailer is made to hang on it
WinchHand.LIFT_MS = 1.0               -- the tongue is lifted at this speed at most ...
WinchHand.LIFT_ACCEL_MS2 = 4          -- ... getting there this smoothly ...
WinchHand.LIFT_GAIN = 4               -- ... 1/s: speed wanted per metre the eye is below its height
WinchHand.WRONG_END_M = 0.5            -- the joint to hitch to is not taken when a joint of the wrong kind of the same vehicle is this much nearer (it lies the other way round)
WinchHand.LIFT_DONE_M = 0.05          -- lifted when the eye is this close to its height
WinchHand.LIFT_MAX_S = 3              -- and not tried longer than this (a hinge at its stop does not get further)
WinchHand.LIFT_MAX_SHARE = 0.25       -- only a joint on a body this small a share of the vehicle is lifted (a tongue of 60 kg of 660); a plate on the main body would tilt the whole machine
WinchHand.TONGUE_VIEW = true            -- the tongue's eye is held at the end of the bar in the direction you look (a handle in front of you), not along the line to wherever it lies
WinchHand.VIEW_TAU_S = 0.15            -- ... the force wants the speed it is short of within this time ...
WinchHand.VIEW_STIFF = true             -- the eye's horizontal speed is driven (like its vertical one), not pushed by a force: no swing sideways
WinchHand.VIEW_STIFF_TAU_S = 0.06      -- ... it gets to the wanted speed within about this long
WinchHand.GRAB = true                  -- the hand GRABS the eye: its offset from you is kept, not aimed with the view (a step aside steers the front axle, a step forward moves the trailer); false: the eye is held along your view
WinchHand.VIEW_LATCH = true             -- the aim is latched while you stand and turn your head only a little (fine moves: a few cm of a wagon in a hall) ...
WinchHand.LATCH_DEG = 25               -- ... it follows again when you turn further than this from the latched direction ...
WinchHand.LATCH_MOVING_MS = 0.25       -- ... or walk faster than this
WinchHand.VIEW_SMOOTH_S = 0.2          -- ... the aim (where you look) is smoothed over this long ...
WinchHand.VIEW_YAW_DAMP = 3            -- ... and the tongue's turning speed is damped (1/s: the swing dies out in about a second)
WinchHand.VIEW_ACCEL_MS2 = 6           -- ... at most this hard
WinchHand.TONGUE_POLE_M = 1.0           -- the tongue's bar is this long (a tractor's pole is POLE_M; the horse's hitch is its own): the eye is held this far from you
WinchHand.TONGUE_POLE_LONG_M = 2.0     -- ... and this long while you LOOK AT a tractor's hitch to attach it to (you stand off the tractor: the face does not hit it); in between, the bar grows and shrinks at BAR_SPEED_MS
WinchHand.BAR_SPEED_MS = 1.5
WinchHand.TONGUE_POLE = true          -- a lifted tongue is held on the stiff pole (drawn as the steel bar, 2 m from you, pushes and pulls) instead of the invisible 0.8 m carry
WinchHand.PUSH = true                 -- the carried eye is held at CARRY_M from you both ways (a rod, not a rope): walking into it pushes it on, a wagon can be backed up by hand
WinchHand.PUSH_GAIN = 12              -- 1/s: speed wanted per metre the eye is nearer than CARRY_M (the pole's stiffness): the grip holds the distance both ways
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

-- logs: whether the tool in the hand can hook a log (the leash and the hand winch can; the horse's harness tool only borrows the ring for its joints and passes false)
function WinchHand.hold(node, logs)
    WinchHand.hand = node
    WinchHand.logsOk = logs ~= false
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
    if WinchTow ~= nil and WinchTow.setSupport ~= nil and target.vehicle ~= nil and not target.vehicle.isLog then
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

-- A hooked log gets a grip node linked to it, at the point looked at; deleted on let-go.
-- The log's collision group with the bit traffic stops for (and back). Only the group changes, the mask is left alone. Returns what to restore, or nil.
function WinchHand.setTrafficVisible(shape, on, original)
    if not WinchHand.TRAFFIC_SEES_LOGS or CollisionFlag == nil or CollisionFlag.DYNAMIC_OBJECT == nil or getCollisionFilter == nil then
        return nil
    end
    local function set(group, mask)
        if setCollisionFilterGroup ~= nil then
            setCollisionFilterGroup(shape, group)
        elseif setCollisionFilter ~= nil then
            setCollisionFilter(shape, group, mask)
        else
            error("no collision filter setter")
        end
    end
    local ok, result = pcall(function()
        if on then
            local group, mask = getCollisionFilter(shape)
            if group == nil or bit32.band(group, CollisionFlag.DYNAMIC_OBJECT) ~= 0 then
                return nil
            end
            set(bit32.bor(group, CollisionFlag.DYNAMIC_OBJECT), mask)
            return { group = group, mask = mask }
        elseif original ~= nil then
            set(original.group, original.mask)
        end
    end)
    return ok and result or nil
end

function WinchHand.dropGrip(target)
    if target ~= nil and target.trafficOriginal ~= nil then
        if target.component ~= nil and (entityExists == nil or entityExists(target.component)) then
            WinchHand.setTrafficVisible(target.component, false, target.trafficOriginal)
        end
        target.trafficOriginal = nil
    end
    if target ~= nil and target.hook ~= nil then
        pcall(target.hook.delete, target.hook)
        target.hook, target.ropeNode = nil, nil
    end
    if target ~= nil and target.ownsNode and target.node ~= nil and (entityExists == nil or entityExists(target.node)) then
        pcall(delete, target.node)
    end
end

-- The free log in view (DYNAMIC body), or nil and why. Standing (STATIC) and belted (KINEMATIC) trees are refused.
function WinchHand.onLogRaycast(self, hitObjectId, x, y, z, distance, _, _, _, _, shapeId)
    if hitObjectId ~= nil and hitObjectId ~= 0 and self.logHit == nil and getHasClassId(hitObjectId, ClassIds.SHAPE) and getSplitType(hitObjectId) ~= 0 then
        self.logHit = { shape = hitObjectId, x = x, y = y, z = z, body = shapeId }
    end
    return false
end

-- The game's strap and hook round the trunk at (x, y, z), turned towards the hand; nil when the engine pieces are missing or it fails (the rope then ends at the grip).
function WinchHand.makeHook(shape, x, y, z)
    if not WinchHand.HOOK or ForestryHook == nil or XMLFile == nil or g_i3DManager == nil or Utils == nil or WinchHand.hand == nil then
        return nil
    end
    local hook = nil
    local ok = pcall(function()
        hook = ForestryHook.new(nil, getRootNode())
        hook.xmlFilename = Utils.getFilename(WinchHand.HOOK_FILE, nil)
        hook.hookXMLFile = XMLFile.load("hookXMLFile", hook.xmlFilename)
        hook.i3dFilename = Utils.getFilename(hook.hookXMLFile:getString("forestryHook.filename", "$data/shared/forestry/treeHook01.i3d"), nil)
        local node, requestId, reason = g_i3DManager:loadSharedI3DFile(hook.i3dFilename, false, false)
        hook.sharedLoadRequestId = requestId
        hook:onI3DLoaded(node, reason)
        if hook.hookId == nil or hook:mountToTree(shape, x, y, z, 4) == nil then
            error("hook not made")
        end
        hook:setTargetNode(WinchHand.hand, true)
    end)
    if not ok then
        if hook ~= nil then
            pcall(hook.delete, hook)
        end
        return nil
    end
    return hook
end

function WinchHand.pickLog()
    local player = g_localPlayer
    if not WinchHand.LOGS or player == nil or not player.isControlled or raycastClosest == nil or CollisionFlag == nil or CollisionFlag.TREE == nil then
        return nil
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    WinchHand.logHit = nil
    raycastClosest(ox, oy, oz, dx, dy, dz, WinchHand.PICK_RANGE_M, "onLogRaycast", WinchHand, CollisionFlag.TREE)
    local hit = WinchHand.logHit
    WinchHand.logHit = nil
    if hit == nil then
        return nil
    end
    local body = getRigidBodyType(hit.shape)
    if body == RigidBodyType.STATIC then
        return nil, "that tree still stands: fell it first"
    elseif body ~= RigidBodyType.DYNAMIC then
        return nil, "that log is belted to a vehicle or carried: unbelt it first"
    end
    -- the ring goes round the trunk, as the game's winch draws it: centre, axis and radius of the trunk at the hit. Near a cut end it is slid along the trunk until RING_MIN_M of log is left on both sides.
    local ring = nil
    if SplitShapeUtil ~= nil and SplitShapeUtil.getTreeOffsetPosition ~= nil then
        local function ringAt(x, y, z, minLength)
            local ok, cx, cy, cz, ux, uy, uz, radius = pcall(SplitShapeUtil.getTreeOffsetPosition, hit.shape, x, y, z, 4, minLength)
            if ok and cx ~= nil then
                return { cx, cy, cz, ux, uy, uz, radius }
            end
        end
        ring = ringAt(hit.x, hit.y, hit.z, WinchHand.RING_MIN_M)
        if ring == nil then
            local ax, ay, az = localDirectionToWorld(hit.shape, 0, 1, 0)
            for step = 1, math.floor(WinchHand.RING_SLIDE_M / 0.1 + 0.5) do
                for _, sign in ipairs({ 1, -1 }) do
                    local d = step * 0.1 * sign
                    ring = ringAt(hit.x + ax * d, hit.y + ay * d, hit.z + az * d, WinchHand.RING_MIN_M)
                    if ring ~= nil then
                        hit.x, hit.y, hit.z = hit.x + ax * d, hit.y + ay * d, hit.z + az * d
                        break
                    end
                end
                if ring ~= nil then
                    break
                end
            end
        end
        ring = ring or ringAt(hit.x, hit.y, hit.z, 0.15)
    end
    local stand = { isLog = true, isDeleted = false, components = { { node = hit.shape } }, getName = function() return "a log" end }
    return { kind = "log", vehicle = stand, node = hit.shape, component = hit.shape, x = hit.x, y = hit.y, z = hit.z, ring = ring }
end

-- Makes the grip of a picked log (pickLog): a node on the log at the point looked at, the traffic group, the game's strap and hook. Returns the target, or nil and why. Used by the hook (toggle) and by a horse
-- tool that ties the log to the harness itself (the hold is not taken: WinchHand.target stays what it is).
function WinchHand.hookLog(log)
    local ok, grip = pcall(function()
        local node = createTransformGroup("winchLogGrip")
        link(log.node, node)
        setWorldTranslation(node, log.x, log.y, log.z)
        return node
    end)
    if not ok then
        return nil, grip
    end
    log.node, log.ownsNode = grip, true
    log.trafficOriginal = WinchHand.setTrafficVisible(log.component, true)
    log.hook = WinchHand.makeHook(log.component, log.x, log.y, log.z)
    log.ropeNode = log.hook ~= nil and log.hook:getRopeTarget() or nil
    return log
end

-- What is hooked is handed to somebody else (a horse that pulls it): the hold ends, and the new owner has what the hook set up: a log's grip node, hook and traffic group (it lets them go with dropGrip), a
-- vehicle's lifted support leg and let-off brake (it puts them back with its own release).
function WinchHand.handOver()
    local target = WinchHand.target
    if target == nil then
        return nil
    end
    WinchHand.target, WinchHand.stage = nil, nil
    WinchHand.dropRope()
    WinchHand.setSpeedCap("winchhand", nil)
    return target
end

local function labelOf(vehicle)
    if vehicle.getName ~= nil then
        local ok, name = pcall(vehicle.getName, vehicle)
        if ok and name ~= nil then
            return tostring(name)
        end
    end
    return tostring(vehicle.configFileName or "vehicle")
end
WinchHand.labelOf = labelOf

-- The vehicle you aim at: the one with a joint nearest to the view ray within AIM_RADIUS_M (a piece is aimed at by its body, its eyes are at its ends), `exclude` left out. nil when none.
WinchHand.AIM_RADIUS_M = 2.5
function WinchHand.aimedVehicle(exclude)
    local player = g_localPlayer
    if player == nil or not player.isControlled or WinchTow == nil or WinchTow.jointsOf == nil then
        return nil
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    local best, bestD = nil, WinchHand.AIM_RADIUS_M
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle ~= exclude and not vehicle.isDeleted then
            for _, joint in ipairs(WinchTow.jointsOf(vehicle, true)) do
                if joint.node ~= nil and entityExists(joint.node) then
                    local px, py, pz = getWorldTranslation(joint.node)
                    local vx, vy, vz = px - ox, py - oy, pz - oz
                    local t = vx * dx + vy * dy + vz * dz
                    if t > 0 and t <= WinchHand.PICK_RANGE_M + 4 then
                        local qx, qy, qz = vx - dx * t, vy - dy * t, vz - dz * t
                        local d = math.sqrt(qx * qx + qy * qy + qz * qz)
                        if d < bestD then
                            best, bestD = vehicle, d
                        end
                    end
                end
            end
        end
    end
    return best
end

-- An eye (an input joint) or a hitch of one vehicle is hooked: the joint of ANOTHER vehicle that fits it (a hitch for an eye, an eye for a hitch; the same type, free), the one nearest to the hooked joint within the attach reach: you do not have to aim at it
-- (with the joints of two grates a few centimetres apart nothing could be aimed at). Returns the joint (with x y z), else nil and why. Works from either side: it does not matter which of the two you hooked.
-- A hooked latch and another latch looked at (of another vehicle, within WinchWire.LATCH_MAX_M): the click lays a wire between the two. Returns the other latch (marked latchWire), or nil and why.
function WinchHand.latchCandidate(hooked)
    if hooked.node == nil or not entityExists(hooked.node) or WinchWire == nil then
        return nil
    end
    if WinchWire.isWired(hooked.node) then
        return nil, "that latch has a wire already (Ctrl and a click takes the wires of a piece away)"
    end
    local look = WinchHand.pick(true)
    if look == nil or look.kind ~= "winch latch" or look.vehicle == hooked.vehicle or look.node == hooked.node then
        return nil
    end
    if WinchWire.isWired(look.node) then
        return nil, "that latch has a wire already (Ctrl and a click takes the wires of a piece away)"
    end
    local hx, hy, hz = getWorldTranslation(hooked.node)
    local ox, oy, oz = getWorldTranslation(look.node)
    local d = math.sqrt((hx - ox) ^ 2 + (hy - oy) ^ 2 + (hz - oz) ^ 2)
    if d > WinchWire.LATCH_MAX_M then
        return nil, string.format("the two latches are %.0f m apart (%d m at most)", d, WinchWire.LATCH_MAX_M)
    end
    look.latchWire = true
    return look
end

function WinchHand.attachCandidate()
    local hooked = WinchHand.target
    if hooked ~= nil and hooked.kind == "winch latch" then
        return WinchHand.latchCandidate(hooked)
    end
    if hooked == nil or (hooked.kind ~= "drawbar eye" and hooked.kind ~= "hitch") or hooked.index == nil or hooked.node == nil or WinchTow == nil or WinchTow.jointsOf == nil then
        return nil
    end
    if not entityExists(hooked.node) then
        return nil
    end
    if hooked.kind == "hitch" and hooked.inUse then
        return nil, "that hitch already has something on it"
    end
    if WinchWire ~= nil and WinchWire.isWired(hooked.node) then
        return nil, "that joint has a wire already (Ctrl and a click takes the wires of a piece away)"
    end
    local wantKind = hooked.kind == "hitch" and "drawbar eye" or "hitch"
    local hx, hy, hz = getWorldTranslation(hooked.node)
    local best, bestD, why = nil, 30, nil                    -- (the nearest fitting joint within 30 m; farther than the attach reach it only says to bring it closer)
    local nearestSkip = nil
    local aimVehicle = (WinchWire ~= nil and hooked.vehicle.bridgeLinkPair ~= nil) and WinchHand.aimedVehicle(hooked.vehicle) or nil      -- (bridge pieces are joined to the one you AIM at, never to whichever lies nearest)
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle ~= hooked.vehicle and not vehicle.isDeleted and (vehicle.bridgeLinkPair == nil or hooked.vehicle.bridgeLinkPair == nil or WinchWire == nil or vehicle == aimVehicle) and (WinchTow.rootOf == nil or WinchTow.rootOf(vehicle) ~= WinchTow.rootOf(hooked.vehicle) or (vehicle.bridgeLinkPair ~= nil and hooked.vehicle.bridgeLinkPair ~= nil)) then
            local before, beforeD, wrongD = best, bestD, nil              -- (wrongD: the nearest joint of this vehicle that is NOT of the wanted kind: its end faces the hooked joint)
            for _, joint in ipairs(WinchTow.jointsOf(vehicle, true)) do
                if joint.kind ~= wantKind and joint.node ~= nil and entityExists(joint.node) then
                    local jx, jy, jz = getWorldTranslation(joint.node)
                    local d = math.sqrt((hx - jx) ^ 2 + (hy - jy) ^ 2 + (hz - jz) ^ 2)
                    wrongD = (wrongD == nil or d < wrongD) and d or wrongD
                end
                if joint.kind == wantKind and joint.index ~= nil and joint.node ~= nil and entityExists(joint.node) and joint.component ~= nil and joint.component ~= 0 then
                    local jx, jy, jz = getWorldTranslation(joint.node)
                    local d = math.sqrt((hx - jx) ^ 2 + (hy - jy) ^ 2 + (hz - jz) ^ 2)
                    if d < bestD then
                        local linked = (vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() == hooked.vehicle) or (hooked.vehicle.getAttacherVehicle ~= nil and hooked.vehicle:getAttacherVehicle() == vehicle)
                        local bridge = linked and vehicle.bridgeLinkPair ~= nil and hooked.vehicle.bridgeLinkPair ~= nil     -- (two hitched bridge pieces take a second pair of their own: the Hammer's BridgeLink)
                        local sameTree = WinchTow.rootOf ~= nil and WinchTow.rootOf(vehicle) == WinchTow.rootOf(hooked.vehicle)
                        if sameTree and not linked then
                            why = "those two are hitched into one train already"
                        elseif WinchWire ~= nil and WinchWire.isWired(joint.node) then
                            why = "that " .. wantKind .. " has a wire already"
                        elseif joint.inUse then
                            why = "that " .. wantKind .. " is already hitched"
                        elseif linked and not bridge then
                            why = "these two are already hitched together: the game allows only one joint between two vehicles"
                        elseif bridge then
                            joint.vehicle, joint.x, joint.y, joint.z, joint.bridgeSecond = vehicle, jx, jy, jz, true
                            best, bestD = joint, d
                        elseif joint.jointTypeId ~= hooked.jointTypeId then
                            why = string.format("that %s is a %s joint, this one is a %s one: they do not fit", wantKind, tostring(joint.jointType), tostring(hooked.jointType))
                        elseif wantKind == "drawbar eye" and joint.vehicle == nil and vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil then
                            why = "that vehicle is already hitched to something"
                        else
                            joint.vehicle, joint.x, joint.y, joint.z = vehicle, jx, jy, jz
                            best, bestD = joint, d
                        end
                        if best ~= joint and (nearestSkip == nil or d < nearestSkip.d) then
                            nearestSkip = { d = d, why = why, vehicle = vehicle, index = joint.index }       -- (a nearer joint that was passed over: said in the log, once)
                        end
                    end
                elseif joint.kind == wantKind and joint.node ~= nil and entityExists(joint.node) then
                    local jx, jy, jz = getWorldTranslation(joint.node)
                    local d = math.sqrt((hx - jx) ^ 2 + (hy - jy) ^ 2 + (hz - jz) ^ 2)
                    if nearestSkip == nil or d < nearestSkip.d then
                        nearestSkip = { d = d, why = string.format("its data is incomplete (index %s, component %s)", tostring(joint.index), tostring(joint.component)), vehicle = vehicle, index = joint.index }
                    end
                end
            end
            -- the end of that vehicle that faces the hooked joint has joints of the wrong kind (a piece lying the other way round): not the next best thing at its far end, whatever the distance
            if best ~= before and best.vehicle == vehicle and wrongD ~= nil and wrongD + WinchHand.WRONG_END_M < bestD then
                best, bestD = before, beforeD
                why = string.format("the end of %s that faces it has %ss, not %ss: turn it around (the %ss are at the other end)", labelOf(vehicle), hooked.kind == "hitch" and "hitch" or "eye", wantKind, wantKind)
            end
        end
    end
    if best == nil then
        return nil, why
    end
    if nearestSkip ~= nil and nearestSkip.d < bestD - 0.05 then
        local key = tostring(hooked.node) .. ":" .. tostring(best.node) .. ":" .. tostring(nearestSkip.why)
        if WinchHand.skipLogged ~= key then
            WinchHand.skipLogged = key
            Logging.info("[WinchHand] a nearer %s (joint %s of %s, %.2f m) was passed over for the one %.2f m away: %s", wantKind, tostring(nearestSkip.index), labelOf(nearestSkip.vehicle), nearestSkip.d, bestD, tostring(nearestSkip.why))
        end
    end
    local wireable = WinchWire ~= nil and best.vehicle.bridgeLinkPair ~= nil and hooked.vehicle.bridgeLinkPair ~= nil
    if not wireable and bestD > WinchHand.BRING_CLOSER_M then
        return nil, nil                                                  -- (nothing near to hitch it to: the click lets go, as before)
    end
    local reach = wireable and WinchWire.MAX_M or WinchHand.ATTACH_REACH_M
    if bestD > reach then
        return nil, string.format("bring the %s closer to the %s to %s them (%.1f m away, %.0f m at most)", hooked.kind, best.kind, wireable and "wire" or "hitch", bestD, reach), "far"
    end
    return best
end

-- The click with a joint hooked and a fitting joint of another vehicle within reach: the two are hitched with the game's own attach (the same call the horse's joint uses), from either side. Returns a message, nil when this is none of its
-- business (the click then lets go).
-- The game's own attach of an eye to a hitch (the call of the Q key). hitchSide and eyeSide: {vehicle, index}. Returns true, or nil and why.
function WinchHand.attachPair(hitchSide, eyeSide)
    local tractor, wagon = hitchSide.vehicle, eyeSide.vehicle
    if wagon.isAttachAllowed ~= nil then
        local farm = tractor.getActiveFarm ~= nil and tractor:getActiveFarm() or nil
        local ok, allowed, warning = pcall(wagon.isAttachAllowed, wagon, farm, tractor)
        if ok and allowed == false then
            return nil, "the game does not allow it: " .. tostring(warning)
        end
    end
    if tractor.attachImplementFromInfo == nil then
        return nil, "that vehicle cannot take an implement"
    end
    local info = { attacherVehicle = tractor, attacherVehicleJointDescIndex = hitchSide.index, attachable = wagon, attachableJointDescIndex = eyeSide.index }
    local ok, err = pcall(tractor.attachImplementFromInfo, tractor, info)
    if not ok then
        return nil, "the game could not attach it: " .. tostring(err)
    end
    if wagon.getAttacherVehicle ~= nil and wagon:getAttacherVehicle() ~= tractor then
        return nil, "the game did not hitch them"
    end
    return true
end

-- After the first wire between two bridge pieces: the second pair (the other hitch of the one, the other eye of the other: the pair that lies closest together) gets its wire at once, so one click does both and
-- the left button only has to reel. Returns a message, or nil when there is no free second pair (an end piece has one joint) or it is farther than a wire reaches.
function WinchHand.autoSecondWire(hooked, other)
    if WinchWire == nil or WinchTow == nil or WinchTow.jointsOf == nil then
        return nil
    end
    local hitchSide = hooked.kind == "hitch" and hooked or other
    local eyeSide = hooked.kind == "hitch" and other or hooked
    if hitchSide.kind ~= "hitch" or eyeSide.kind ~= "drawbar eye" then
        return nil
    end
    local best, bestD
    for _, h in ipairs(WinchTow.jointsOf(hitchSide.vehicle) or {}) do
        if h.kind == "hitch" and h.node ~= hitchSide.node and not h.inUse and h.node ~= nil and entityExists(h.node) and not WinchWire.isWired(h.node) then
            for _, e in ipairs(WinchTow.jointsOf(eyeSide.vehicle) or {}) do
                if e.kind == "drawbar eye" and e.node ~= eyeSide.node and e.node ~= nil and entityExists(e.node) and not WinchWire.isWired(e.node) then
                    local hx, hy, hz = getWorldTranslation(h.node)
                    local ex, ey, ez = getWorldTranslation(e.node)
                    local d = math.sqrt((hx - ex) ^ 2 + (hy - ey) ^ 2 + (hz - ez) ^ 2)
                    if bestD == nil or d < bestD then
                        best, bestD = { h = h, e = e }, d
                    end
                end
            end
        end
    end
    if best == nil or bestD > WinchWire.MAX_M then
        return nil
    end
    WinchWire.lay({ vehicle = hitchSide.vehicle, node = best.h.node, kind = "hitch", index = best.h.index }, { vehicle = eyeSide.vehicle, node = best.e.node, kind = "drawbar eye", index = best.e.index }, labelOf)
    return string.format("the second pair got its wire too (%.1f m)", bestD)
end

-- ===== published for FS25_Hammer's guide (WinchHand is on g_currentMission.winchTow): wires between two vehicles' latches, laid without a click =====
-- Is there a latch wire between these two vehicles already?
function WinchHand.hasWireBetween(a, b)
    if WinchWire == nil then
        return false
    end
    for _, w in ipairs(WinchWire.wires) do
        if w.latch and ((w.hitch.vehicle == a and w.eye.vehicle == b) or (w.hitch.vehicle == b and w.eye.vehicle == a)) then
            return true
        end
    end
    return false
end

-- A wire between the free latches of two vehicles that lie closest together, the high ones first (a pole's top latches, not its low one). Returns a message, or nil and why.
WinchHand.LATCH_HIGH_M = 1.0
function WinchHand.layLatchWire(a, b)
    if WinchWire == nil or WinchTow == nil or WinchTow.jointsOf == nil or a == nil or b == nil then
        return nil, "no wires"
    end
    local function latches(v, high)
        local out = {}
        local vy = select(2, getWorldTranslation(v.components[1].node))
        for _, j in ipairs(WinchTow.jointsOf(v, true) or {}) do
            if j.kind == "winch latch" and j.node ~= nil and entityExists(j.node) and not WinchWire.isWired(j.node) then
                local jy = select(2, getWorldTranslation(j.node))
                if not high or jy - vy >= WinchHand.LATCH_HIGH_M then
                    out[#out + 1] = j
                end
            end
        end
        return out
    end
    local la, lb = latches(a, true), latches(b, true)
    if #la == 0 or #lb == 0 then
        la, lb = latches(a, false), latches(b, false)
    end
    local best, bestD
    for _, ja in ipairs(la) do
        for _, jb in ipairs(lb) do
            local ax, ay, az = getWorldTranslation(ja.node)
            local bx, by, bz = getWorldTranslation(jb.node)
            local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
            if bestD == nil or d < bestD then
                best, bestD = { ja, jb }, d
            end
        end
    end
    if best == nil then
        return nil, "no free latch on one of them"
    end
    if bestD > WinchWire.LATCH_MAX_M then
        return nil, string.format("%.0f m apart (%d m at most)", bestD, WinchWire.LATCH_MAX_M)
    end
    return WinchWire.lay({ vehicle = a, node = best[1].node, kind = "winch latch", index = best[1].index }, { vehicle = b, node = best[2].node, kind = "winch latch", index = best[2].index }, labelOf, true)
end

function WinchHand.tryAttach()
    local hooked = WinchHand.target
    local other, why, reason = WinchHand.attachCandidate()
    if other == nil then
        return why, reason == "far"                                      -- (too far: the click keeps the hold, you are bringing it closer; any other reason: the click lets go and says why)
    end
    if other.latchWire then                                              -- two latches: a wire is laid, nothing is joined (the poles, the guide wires of a bridge)
        local message = WinchWire.lay(hooked, other, labelOf, true)
        local target = WinchHand.target
        WinchHand.target, WinchHand.stage = nil, nil
        WinchHand.dropRope()
        WinchHand.setSpeedCap("winchhand", nil)
        if target ~= nil and WinchHand.dropGrip ~= nil then
            WinchHand.dropGrip(target)
        end
        return message, true
    end
    if WinchWire ~= nil and hooked.vehicle.bridgeLinkPair ~= nil and other.vehicle.bridgeLinkPair ~= nil then      -- two bridge pieces: a wire is laid, nothing moves (the winch keys reel it in)
        local message = WinchWire.lay(hooked, other, labelOf)
        local second = WinchHand.autoSecondWire(hooked, other)
        if second ~= nil then
            message = message .. "; " .. second
        end
        WinchHand.target, WinchHand.stage = nil, nil
        WinchHand.dropRope()
        WinchHand.setSpeedCap("winchhand", nil)
        return message, true
    end
    if other.bridgeSecond then
        local ok, answer, problem = pcall(hooked.vehicle.bridgeLinkPair, hooked.vehicle, other.vehicle, hooked.node, other.node)
        if ok and answer == true then
            WinchHand.target, WinchHand.stage = nil, nil
            WinchHand.dropRope()
            WinchHand.setSpeedCap("winchhand", nil)
            return string.format("%s and %s: the second joint is pulled in", labelOf(hooked.vehicle), labelOf(other.vehicle)), true
        end
        return "the second joint did not work: " .. tostring(ok and problem or answer), true
    end
    local hitchSide = hooked.kind == "hitch" and hooked or other
    local eyeSide = hooked.kind == "hitch" and other or hooked
    local tractor, wagon = hitchSide.vehicle, eyeSide.vehicle
    if wagon.isAttachAllowed ~= nil then
        local farm = tractor.getActiveFarm ~= nil and tractor:getActiveFarm() or nil
        local ok, allowed, warning = pcall(wagon.isAttachAllowed, wagon, farm, tractor)
        if ok and allowed == false then
            return "the game does not allow it: " .. tostring(warning), true
        end
    end
    if tractor.attachImplementFromInfo == nil then
        return "that vehicle cannot take an implement", true
    end
    local info = { attacherVehicle = tractor, attacherVehicleJointDescIndex = hitchSide.index, attachable = wagon, attachableJointDescIndex = eyeSide.index }
    local ok, err = pcall(tractor.attachImplementFromInfo, tractor, info)
    if not ok then
        return "the game could not attach it: " .. tostring(err), true
    end
    if wagon.getAttacherVehicle ~= nil and wagon:getAttacherVehicle() ~= tractor then          -- (the game refuses without an error, e.g. a second joint between two vehicles that are already hitched)
        return "the game did not hitch them (they may be hitched together already: one joint between two vehicles at most)", true
    end
    -- the hold ends; the game's attach has the wagon now (its support leg and brake are the attach's business)
    WinchHand.target, WinchHand.stage = nil, nil
    WinchHand.dropRope()
    WinchHand.setSpeedCap("winchhand", nil)
    return string.format("attaching the eye of %s to the hitch of %s: the game pulls it in", labelOf(wagon), labelOf(tractor)), true
end

-- The unhitch key: the vehicle that is hooked (or whose joint you look at) is unhitched from EVERYTHING: from what pulls it and from all that hangs on it (the game's own detach), and the hook is let go. Pins are not touched (the Hammer's).
-- The vehicle whose body the view ray hits (a panel's middle, not one of its joints), nil when it hits none.
function WinchHand.onBodyRaycast(self, hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 and self.bodyHit == nil and g_currentMission ~= nil and g_currentMission.getNodeObject ~= nil then
        local node = hitObjectId
        for _ = 1, 8 do
            local object = g_currentMission:getNodeObject(node)
            if object ~= nil then
                self.bodyHit = object
                break
            end
            node = getParent ~= nil and getParent(node) or 0
            if node == nil or node == 0 then
                break
            end
        end
    end
    return false
end

function WinchHand.aimedBody()
    local player = g_localPlayer
    if raycastClosest == nil or CollisionFlag == nil or CollisionFlag.VEHICLE == nil or bit32 == nil or player == nil or not player.isControlled then
        return nil
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    WinchHand.bodyHit = nil
    pcall(raycastClosest, ox, oy, oz, dx, dy, dz, WinchHand.PICK_RANGE_M, "onBodyRaycast", WinchHand, bit32.bor(CollisionFlag.VEHICLE, CollisionFlag.DYNAMIC_OBJECT or 0))
    local hit = WinchHand.bodyHit
    WinchHand.bodyHit = nil
    return hit
end

-- Ctrl and a click: the vehicle that is hooked, else the one whose BODY you look at (a panel's middle: it comes loose from both neighbours, all four joints, and nothing else), else the one whose joint you look at.
function WinchHand.unhitchAll()
    local hooked = WinchHand.target
    local vehicle = hooked ~= nil and hooked.vehicle or nil
    if vehicle == nil then
        vehicle = WinchHand.aimedBody()
    end
    if vehicle == nil then
        local looked = WinchHand.pick ~= nil and WinchHand.pick(true) or nil
        vehicle = looked ~= nil and looked.vehicle or nil
    end
    if vehicle == nil or vehicle.isDeleted then
        return "look at a vehicle (its body, or a joint) or hook it to unhitch it from everything"
    end
    local count = WinchWire ~= nil and WinchWire.clear(vehicle) or 0
    local parent = vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() or nil
    if parent ~= nil and pcall(parent.detachImplementByObject, parent, vehicle) then
        count = count + 1
    end
    local implements = vehicle.getAttachedImplements ~= nil and vehicle:getAttachedImplements() or {}
    for i = #implements, 1, -1 do
        if implements[i].object ~= nil and pcall(vehicle.detachImplementByObject, vehicle, implements[i].object) then
            count = count + 1
        end
    end
    if hooked ~= nil and hooked.vehicle == vehicle then
        WinchHand.target, WinchHand.stage = nil, nil
        WinchHand.setSpeedCap("winchhand", nil)
        WinchHand.dropRope()
        WinchHand.dropGrip(hooked)
        setBrakeOff(hooked, false)
        setSupportUp(hooked, false)
    end
    if count == 0 then
        return string.format("%s is not hitched to anything", labelOf(vehicle))
    end
    return string.format("%s unhitched from everything (%d)", labelOf(vehicle), count)
end

-- Left Shift and a click on a joint that is hitched: unhitched (the game's own detach). An eye: its vehicle is let go from what pulls it; a hitch: what hangs on it is let go.
function WinchHand.tryDetach(target)
    if target == nil or target.vehicle == nil then
        return nil
    end
    local vehicle = target.vehicle
    if target.kind == "drawbar eye" then
        local tractor = vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() or nil
        if tractor == nil then
            return nil
        end
        pcall(tractor.detachImplementByObject, tractor, vehicle)
        return string.format("unhitched %s from %s", labelOf(vehicle), labelOf(tractor))
    end
    local implement = vehicle.getImplementByJointDescIndex ~= nil and vehicle:getImplementByJointDescIndex(target.index) or nil
    if implement == nil or implement.object == nil then
        return nil
    end
    pcall(vehicle.detachImplementByObject, vehicle, implement.object)
    return string.format("unhitched %s from %s", labelOf(implement.object), labelOf(vehicle))
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
    local ropeEnd = target.ropeNode or target.node
    if rope ~= nil and (rope.rfTarget ~= ropeEnd or rope.linkNode ~= WinchHand.hand) then
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
            r.rfTarget = ropeEnd
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
        rope.tied = pcall(rope.setTargetNode, rope, ropeEnd, true)
    end
    return true
end

function WinchHand.letGo(message)
    local target = WinchHand.target
    WinchHand.target, WinchHand.stage = nil, nil
    WinchHand.dropRope()
    WinchHand.setSpeedCap("winchhand", nil)
    WinchHand.dropGrip(target)
    if target ~= nil then
        setBrakeOff(target, false)
        setSupportUp(target, false)
        if message ~= nil then
            WinchHand.notify(message)
        end
    end
end

local hideMarker                      -- (defined with the marker below)

function WinchHand.putAway(node)
    if WinchHand.hand ~= node then
        return
    end
    WinchHand.hand, WinchHand.gate, WinchHand.hint = nil, nil, nil
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

-- The joints of a vehicle (published for other mods: HorseDynamics finds the joint of a saved hitch again): see WinchTow.jointsOf.
function WinchHand.jointsOf(vehicle, all)
    return WinchTow.jointsOf(vehicle, all)
end

-- The joint nearest to a point (published for other mods: a horse that backs up to a trailer): see WinchTow.nearest.
function WinchHand.nearest(x, z, radius, except)
    if WinchTow == nil or WinchTow.nearest == nil then
        return nil
    end
    return WinchTow.nearest(x, z, radius, except)
end

-- The tool's action: hook onto the joint you look at, or let go. Returns a message.
-- true for a vehicle that has no wheels at all (the bridge grates, the plate): the pull for vehicles lets the wheels do the work, on the ground such a vehicle only rubs
function WinchHand.rollsNot(vehicle)
    if vehicle == nil or vehicle.isLog then
        return false
    end
    local wheels = vehicle.spec_wheels
    return wheels == nil or wheels.wheels == nil or #wheels.wheels == 0
end

-- A frozen or pinned vehicle with wheels is refused (the pull would take its axle off the frame). One without wheels (a bridge grate, the plate) can be hooked: the rope only joins it to something.
function WinchHand.isLocked(target)
    local vehicle = target ~= nil and target.vehicle or nil
    if vehicle == nil or WinchHand.rollsNot(vehicle) then
        return false
    end
    local frame = vehicle.components ~= nil and vehicle.components[1] or nil
    return (frame ~= nil and frame.isStatic == true) or vehicle.hdPinned == true
end

function WinchHand.toggle()
    if Input ~= nil and Input.isKeyPressed ~= nil and Input.KEY_lctrl ~= nil and Input.isKeyPressed(Input.KEY_lctrl) then
        return WinchHand.unhitchAll()                             -- Ctrl and a click: the vehicle (hooked or looked at) is unhitched from everything
    end
    if Input ~= nil and Input.isKeyPressed ~= nil and Input.KEY_lshift ~= nil and Input.isKeyPressed(Input.KEY_lshift) then
        -- Shift and a click: the joint you look at (else the hooked one) is unhitched, and the hook is let go (hooked or not)
        local joint = (WinchHand.pick ~= nil and WinchHand.pick(true)) or WinchHand.target
        local done = joint ~= nil and WinchHand.tryDetach(joint) or nil
        if done ~= nil then
            WinchHand.letGo(nil)                                  -- (the original letGo: no message of its own, the unhitch message is the answer)
            return done
        end
    end
    if WinchHand.target ~= nil then
        local attached, used = WinchHand.tryAttach()
        if attached ~= nil and used then
            return attached
        end
        local why = attached                                              -- (nothing fitted: the click lets go, and says why nothing was hitched)
        local target = WinchHand.target
        WinchHand.target, WinchHand.stage = nil, nil
        WinchHand.setSpeedCap("winchhand", nil)
        WinchHand.dropRope()
        WinchHand.dropGrip(target)
        setBrakeOff(target, false)
        setSupportUp(target, false)
        if target.kind == "log" then
            return "winch let go of the log"
        end
        return string.format("winch let go of the %s of %s%s", target.kind, vehicleName(target.vehicle), why ~= nil and (" (" .. why .. ")") or "")
    end
    local target = WinchHand.pick(true)
    local frame = target ~= nil and target.vehicle ~= nil and target.vehicle.components ~= nil and target.vehicle.components[1] or nil
    if target ~= nil and target.kind == "winch latch" and WinchHand.isLocked(target) then
        -- the latch of a pinned or frozen vehicle (a pole on its bank): nothing is pulled; the rope is the start of a WIRE to the latch you look at and click next
        WinchHand.target, WinchHand.stage, WinchHand.pulledS, WinchHand.stuckReported = target, "wire", 0, false
        return string.format("winch hooked to the winch latch of %s (it is fixed, nothing is pulled): walk to another latch, look at it and click: a wire is laid between them (within %d m)", vehicleName(target.vehicle), WinchHand.LATCH_ROPE_MAX_M)
    end
    if WinchHand.isLocked(target) then
        return string.format("%s is frozen or pinned: let it go first (the hammer), or its axle would be pulled off the frame", vehicleName(target.vehicle))
    end
    if target == nil then
        local log, why = WinchHand.pickLog()
        if log == nil then
            return why or ("look at an attacher joint (a drawbar eye, a hitch) or at a log within " .. WinchHand.PICK_RANGE_M .. " m")
        end
        local hooked, problem = WinchHand.hookLog(log)
        if hooked == nil then
            return "the log could not be hooked: " .. tostring(problem)
        end
        log = hooked
        target = log
    end
    WinchHand.target, WinchHand.pulledS, WinchHand.stuckReported = target, 0, false
    WinchHand.tongueHeld = false
    WinchHand.viewX, WinchHand.viewZ = nil, nil
    WinchHand.reachNow, WinchHand.attachNear = nil, false
    WinchHand.grabX, WinchHand.grabZ = nil, nil
    setSupportUp(target, true)
    -- tongue: lift then carry; log: drag; other joints: pole or old pull
    if target.kind == "log" or WinchHand.rollsNot(target.vehicle) then
        WinchHand.stage = "drag"                                          -- (a log, or a vehicle that has no wheels (a grate, a plate): it is dragged, not rolled: the ground rubs on it, the front is lifted a little)
    else
        WinchHand.stage = WinchHand.CARRY and WinchHand.liftable(target) and "lift" or WinchHand.POLE and "pole" or nil
    end
    WinchHand.liftS, WinchHand.liftV, WinchHand.supportWaitS, WinchHand.lastPx, WinchHand.lastPz, WinchHand.pvx, WinchHand.pvz = 0, 0, 0, nil, nil, 0, 0
    local speed = WinchHand.pullSpeed(WinchHand.pullMass(target.vehicle, target.component))
    if target.kind == "log" then
        return string.format("winch hooked to the log (%.1f t): walk away from it, it is dragged behind you on the rope, as slowly as it is heavy; the same key lets go", WinchHand.pullMass(target.vehicle, target.component))
    end
    return string.format("winch hooked to the %s of %s: walk away from it, it follows you at up to %.0f km/h (the heavier, the slower, and so are you, running too); the same key lets go", target.kind, vehicleName(target.vehicle), speed * 3.6)
end

-- The height of the floor under (x, z): a ray down from just above y (terrain, buildings and static objects: the concrete of a hall lies above the terrain under it, which made a tongue lifted to
-- "terrain + 0.81 m" hang too low, so its support leg went through the floor when it was let go); the terrain's height where nothing is hit.
WinchHand.FLOOR_REACH_M = 4
function WinchHand.floorRaycast(_, hitNode, _, hitY)
    if hitNode ~= nil and hitNode ~= 0 then
        WinchHand.floorHit = hitY
    end
end

function WinchHand.groundY(x, z, y)
    local terrain = 0
    if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
        terrain = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    end
    if y ~= nil and raycastClosest ~= nil and CollisionFlag ~= nil and CollisionFlag.TERRAIN ~= nil and CollisionFlag.STATIC_OBJECT ~= nil and CollisionFlag.BUILDING ~= nil and bit32 ~= nil then
        WinchHand.floorHit = nil
        local mask = bit32.bor(CollisionFlag.TERRAIN, CollisionFlag.STATIC_OBJECT, CollisionFlag.BUILDING)
        pcall(raycastClosest, x, y + 1.0, z, 0, -1, 0, WinchHand.FLOOR_REACH_M, "floorRaycast", WinchHand, mask)
        if WinchHand.floorHit ~= nil then
            return math.max(terrain, WinchHand.floorHit)
        end
    end
    return terrain
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
    local ground = WinchHand.groundY(jx, jz, jy)
    -- you stand on the floor the wagon is on (a hall): the eye is carried at least that far above YOUR feet when you are close to it (the camera is WinchHand.EYE_TO_FEET_M above them)
    if WinchHand.cameraY ~= nil and d < WinchHand.FEET_NEAR_M then
        local feet = WinchHand.cameraY - WinchHand.EYE_TO_FEET_M
        if feet > ground and feet - ground < 1.0 then
            ground = feet
        end
    end
    local goalY = ground + WinchHand.EYE_HEIGHT_M
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
            WinchHand.stage = WinchHand.TONGUE_POLE and "pole" or "carry"
            WinchHand.tongueHeld = true
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
    local pole, drag = WinchHand.stage == "pole", WinchHand.stage == "drag"
    -- the tongue on its bar, held along your view: the eye is wanted at the end of the bar in the direction you LOOK (not wherever it happens to lie), your own speed plus a catch-up. Pushing, pulling and steering are one thing: you walk, it goes where you aim.
    if pole and WinchHand.tongueHeld and WinchHand.TONGUE_VIEW and localDirectionToWorld ~= nil and g_localPlayer ~= nil then
        local camera = g_localPlayer.getCurrentCameraNode ~= nil and g_localPlayer:getCurrentCameraNode() or nil
        if camera ~= nil then
            local dx, _, dz = localDirectionToWorld(camera, 0, 0, -1)
            local len = math.sqrt(dx * dx + dz * dz)
            local steer = true
            if len > 0.3 and WinchHand.viewX ~= nil and WinchHand.VIEW_LATCH then
                -- the aim is LATCHED: a small turn of the head while you stand does not move the handle (a 3 cm move of a wagon is a sub-degree turn at the end of a 2 m bar); the aim follows when you walk or turn beyond LATCH_DEG
                local cosAngle = (dx * WinchHand.viewX + dz * WinchHand.viewZ) / len
                local moving = math.sqrt(WinchHand.pvx * WinchHand.pvx + WinchHand.pvz * WinchHand.pvz) > WinchHand.LATCH_MOVING_MS
                steer = moving or cosAngle < math.cos(math.rad(WinchHand.LATCH_DEG))
            end
            if len > 0.3 and steer then
                -- the aim is smoothed (a quick turn of the head does not whip the handle round)
                local k = math.min(1, seconds / (WinchHand.VIEW_SMOOTH_S + seconds))
                local vx, vz = WinchHand.viewX or dx / len, WinchHand.viewZ or dz / len
                vx, vz = vx + (dx / len - vx) * k, vz + (dz / len - vz) * k
                local vlen = math.sqrt(vx * vx + vz * vz)
                if vlen > 1e-6 then
                    WinchHand.viewX, WinchHand.viewZ = vx / vlen, vz / vlen             -- (looking straight down: the last direction holds)
                end
            end
            local fx, fz = WinchHand.viewX or 1, WinchHand.viewZ or 0
            -- arm's length for moving a trailer by hand, the long bar while you look at a hitch to attach it to
            WinchHand.attachCheckMs = (WinchHand.attachCheckMs or 0) + seconds * 1000
            if WinchHand.attachCheckMs >= 150 then
                WinchHand.attachCheckMs = 0
                WinchHand.attachNear = WinchHand.attachCandidate() ~= nil
            end
            local wantReach = WinchHand.attachNear and WinchHand.TONGUE_POLE_LONG_M or WinchHand.TONGUE_POLE_M
            local nowReach = WinchHand.reachNow or wantReach
            nowReach = nowReach + math.max(-WinchHand.BAR_SPEED_MS * seconds, math.min(WinchHand.BAR_SPEED_MS * seconds, wantReach - nowReach))
            WinchHand.reachNow = nowReach
            local reach = nowReach
            if WinchHand.GRAB then
                -- the hand grabs the eye: the offset between you and the eye is kept (in the world's axes, not turned with your view): a step to the side steers the front axle, a step forward moves the trailer. The offset shrinks to arm's length
                -- when it was grabbed from further away, and grows to the long bar while you look at a hitch to attach to.
                if WinchHand.grabX == nil then
                    WinchHand.grabX, WinchHand.grabZ = jx - px, jz - pz
                end
                local glen = math.sqrt(WinchHand.grabX * WinchHand.grabX + WinchHand.grabZ * WinchHand.grabZ)
                local gx, gz = WinchHand.grabX, WinchHand.grabZ
                if glen < 0.2 then
                    gx, gz, glen = fx, fz, 1
                end
                local newLen = glen + math.max(-WinchHand.BAR_SPEED_MS * seconds, math.min(WinchHand.BAR_SPEED_MS * seconds, wantReach - glen))
                WinchHand.grabX, WinchHand.grabZ = gx / glen * newLen, gz / glen * newLen
                reach = newLen
                fx, fz = gx / glen, gz / glen
            end
            local ex, ez = px + fx * reach - jx, pz + fz * reach - jz
            local wvx, wvz = WinchHand.pvx + WinchHand.POLE_GAIN * ex, WinchHand.pvz + WinchHand.POLE_GAIN * ez
            local want = math.sqrt(wvx * wvx + wvz * wvz)
            if want > pullSpeed then
                wvx, wvz = wvx * pullSpeed / want, wvz * pullSpeed / want
            end
            local vx, _, vz = getLinearVelocity(target.component)
            if WinchHand.VIEW_STIFF then
                -- side to side like up and down: the horizontal speed of the eye is DRIVEN to the wanted one (the vertical was always driven, so it never swung; the force servo left the sideways to the pendulum)
                local k = math.min(1, seconds / WinchHand.VIEW_STIFF_TAU_S)
                vx, vz = vx + (wvx - vx) * k, vz + (wvz - vz) * k
            else
                local ax, az = (wvx - vx) / WinchHand.VIEW_TAU_S, (wvz - vz) / WinchHand.VIEW_TAU_S
                local a = math.sqrt(ax * ax + az * az)
                if a > WinchHand.VIEW_ACCEL_MS2 then
                    ax, az = ax * WinchHand.VIEW_ACCEL_MS2 / a, az * WinchHand.VIEW_ACCEL_MS2 / a
                    a = WinchHand.VIEW_ACCEL_MS2
                end
                if a > 1e-3 then
                    addForce(target.component, ax * mass, 0, az * mass, jx, jy, jz, false)
                end
            end
            if WinchHand.NUDGE then
                WinchHand.steer(target, jx, jy, jz, px, pz, d, mass)
            end
            setLinearVelocity(target.component, vx, clamp(err * WinchHand.LIFT_GAIN, -WinchHand.LIFT_MS, WinchHand.LIFT_MS), vz)
            -- the handle does not swing: the tongue's turning speed (yaw) is damped
            local wx, wy, wz = getAngularVelocity(target.component)
            local keep = math.exp(-WinchHand.VIEW_YAW_DAMP * seconds)
            setAngularVelocity(target.component, wx, wy * keep, wz)
            return
        end
    end
    local reach, gain = pole and (WinchHand.tongueHeld and WinchHand.TONGUE_POLE_M or WinchHand.POLE_M) or drag and WinchHand.LOG_REACH_M or WinchHand.CARRY_M, (pole or drag) and WinchHand.POLE_GAIN or WinchHand.POS_GAIN
    local speed = 0
    if d > reach then
        speed = clamp(math.max(0, away) + gain * (d - reach), 0, pullSpeed)
    elseif pole then
        speed = -clamp(gain * (reach - d), 0, pullSpeed)                      -- (a pole is stiff: it pushes the joint back from you)
    elseif WinchHand.PUSH and WinchHand.stage == "carry" then
        speed = -clamp(WinchHand.PUSH_GAIN * (reach - d) + math.max(0, -away), 0, pullSpeed)     -- (a hand is a rod, not a rope: inside the grip distance the eye is pushed back out to it, at your speed on top when you walk into it)
    end
    local vx, _, vz = getLinearVelocity(target.component)
    local ax, az = (-ux * speed - vx) / WinchHand.PULL_TAU_S, (-uz * speed - vz) / WinchHand.PULL_TAU_S
    local a = math.sqrt(ax * ax + az * az)
    local limit = drag and WinchHand.LOG_ACCEL_MS2 or WinchHand.ACCEL_MS2
    if a > limit then
        ax, az = ax * limit / a, az * limit / a
        a = limit
    end
    if a > 1e-3 then
        addForce(target.component, ax * mass, drag and WinchHand.LOG_LIFT_SHARE * mass * 9.81 or 0, az * mass, jx, jy, jz, false)    -- (tonnes * m/s2 = kN)
    end
    if drag then
        return
    end
    if pole then
        if WinchHand.NUDGE then
            WinchHand.steer(target, jx, jy, jz, px, pz, d, mass)
        end
        if WinchHand.tongueHeld then
            setLinearVelocity(target.component, vx, clamp(err * WinchHand.LIFT_GAIN, -WinchHand.LIFT_MS, WinchHand.LIFT_MS), vz)      -- (a tongue's eye is held at its height on the pole too)
        end
        return                                                               -- (a pole holds the joint's distance only: the machine is not lifted)
    end
    -- pushing: the tongue is a lever on a swivelling axle that wanders about unless it is kept in line with the push (the pole's couple: the body is turned along the line from you to the eye)
    if speed < 0 and WinchHand.NUDGE then
        WinchHand.steer(target, jx, jy, jz, px, pz, d, mass)
    end
    -- the eye is held at its height: the tongue's vertical speed only
    local vy = clamp(err * WinchHand.LIFT_GAIN, -WinchHand.LIFT_MS, WinchHand.LIFT_MS)
    setLinearVelocity(target.component, vx, vy, vz)
end

-- The keys of the hooked vehicle for you on foot (what the horse's hitch does too): a vehicle registers its action events (the tension belts, a trailer's tip key, the keys of a mod) in the VEHICLE input
-- context, which is only active while somebody sits in a vehicle. Its own registration is replayed inside a PLAYER context modification (what a hand tool does), so every specialization that registers its
-- keys "when active for input" registers them for you, and the callbacks stay bound to the vehicle. The game clears them whenever it registers the vehicle's events again (hooked below: made again after it).
WinchHand.INHERIT_KEYS = true
WinchHand.keysFor = nil                  -- the vehicle whose keys the player has now

-- Keys that need a running engine only give "Please start the engine first!" when nothing of the hooked vehicle runs (a flatbed on foot, the plate): they are registered but switched off, for the replay only.
local function hidePoweredKeys(vehicle)
    if vehicle.getIsPowered == nil or vehicle.addPoweredActionEvent == nil then
        return false
    end
    local ok, powered = pcall(vehicle.getIsPowered, vehicle)
    if not ok or powered then
        return false
    end
    local original = vehicle.addPoweredActionEvent
    vehicle.addPoweredActionEvent = function(self, ...)
        local success, id = original(self, ...)
        if id ~= nil and g_inputBinding ~= nil then
            pcall(g_inputBinding.setActionEventActive, g_inputBinding, id, false)
            pcall(g_inputBinding.setActionEventTextVisibility, g_inputBinding, id, false)
        end
        return success, id
    end
    return true
end

function WinchHand.registerKeys(vehicle)
    if not WinchHand.INHERIT_KEYS or g_inputBinding == nil or PlayerInputComponent == nil or SpecializationUtil == nil or vehicle.isDeleted then
        return false
    end
    local hidden = hidePoweredKeys(vehicle)
    local began = false
    local ok, err = pcall(function()
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        began = true
        SpecializationUtil.raiseEvent(vehicle, "onPreRegisterActionEvents", true, true)
        SpecializationUtil.raiseEvent(vehicle, "onRegisterActionEvents", true, true)
        g_inputBinding:endActionEventsModification()
        began = false
    end)
    if hidden then
        vehicle.addPoweredActionEvent = nil          -- (back to the class's own)
    end
    -- the vehicle's own attach / detach keys act on an implement hanging on ITS joints, never on the vehicle itself: hidden (the unhitch key of the tool, U and Q, is the one that works)
    local joints = vehicle.spec_attacherJoints
    if ok and joints ~= nil and joints.actionEvents ~= nil and InputAction ~= nil then
        for _, action in ipairs({ InputAction.ATTACH, InputAction.DETACH }) do
            local event = joints.actionEvents[action]
            if event ~= nil and event.actionEventId ~= nil then
                pcall(g_inputBinding.setActionEventActive, g_inputBinding, event.actionEventId, false)
                pcall(g_inputBinding.setActionEventTextVisibility, g_inputBinding, event.actionEventId, false)
            end
        end
    end
    if not ok then
        if began then
            pcall(g_inputBinding.endActionEventsModification, g_inputBinding)
        end
        if not WinchHand.keysReported then
            WinchHand.keysReported = true
            print("[WinchHand] the keys of the hooked vehicle could not be given to the player: " .. tostring(err))
        end
        return false
    end
    return true
end

-- The engine's own angular damping on the hooked tongue's body (the drawbar of a wagon is a light body on a hinge and swings like a pendulum when it is moved): set while it is held on the bar, the old value put back when it is let go.
WinchHand.TONGUE_ANGULAR_DAMPING = 4
WinchHand.dampedNode, WinchHand.dampedOld = nil, nil
function WinchHand.syncDamping()
    local target = WinchHand.target
    local want = target ~= nil and WinchHand.tongueHeld and target.component or nil
    if want == WinchHand.dampedNode then
        return
    end
    local old = WinchHand.dampedNode
    if old ~= nil and entityExists(old) and WinchHand.dampedOld ~= nil then
        pcall(setAngularDamping, old, WinchHand.dampedOld)
    end
    WinchHand.dampedNode, WinchHand.dampedOld = nil, nil
    if want ~= nil and entityExists(want) and getAngularDamping ~= nil and setAngularDamping ~= nil then
        WinchHand.dampedOld = getAngularDamping(want)
        WinchHand.dampedNode = want
        pcall(setAngularDamping, want, WinchHand.TONGUE_ANGULAR_DAMPING)
    end
end

-- Called every frame: the keys follow the hook (taken when it is let go: the vehicle's events are asked again where the game wants them).
function WinchHand.syncKeys()
    local target = WinchHand.target
    local want = target ~= nil and target.kind ~= "log" and target.vehicle or nil
    if want == WinchHand.keysFor then
        return
    end
    local old = WinchHand.keysFor
    WinchHand.keysFor = want
    if old ~= nil and not old.isDeleted and old.updateActionEvents ~= nil then
        pcall(old.updateActionEvents, old)
    end
    if want ~= nil then
        WinchHand.registerKeys(want)
    end
end

if Vehicle ~= nil and Vehicle.registerActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil and not WinchHand.keysHooked then
    WinchHand.keysHooked = true
    Vehicle.registerActionEvents = Utils.appendedFunction(Vehicle.registerActionEvents, function(self)
        if WinchHand.keysFor ~= nil and WinchHand.keysFor == self then
            WinchHand.registerKeys(self)
        end
    end)
end

-- winchBar [tongue|pole] [metres]: the bar's length while playing (the tongue's of the hand tool, or the pole of a tractor and the rear hook); without a number it only says them.
function WinchHand.consoleBar(_, first, second)
    local which, value = first, tonumber(second)
    if tonumber(first) ~= nil then
        which, value = "tongue", tonumber(first)
    end
    if value ~= nil then
        value = math.max(0.2, math.min(4, value))
        if which == "pole" then
            WinchHand.POLE_M = value
        elseif which == "long" then
            WinchHand.TONGUE_POLE_LONG_M = value
        else
            WinchHand.TONGUE_POLE_M = value
        end
    end
    return string.format("winchBar: tongue %.2f m (%.2f m while you look at a hitch to attach to), pole %.2f m (winchBar [tongue|long|pole] <metres>)", WinchHand.TONGUE_POLE_M, WinchHand.TONGUE_POLE_LONG_M, WinchHand.POLE_M)
end

-- winchDamp [angular damping of the tongue, yaw damping of the aim]: tuning while playing (no number: only says them)
function WinchHand.consoleDamp(_, angular, yaw)
    if tonumber(angular) ~= nil then
        WinchHand.TONGUE_ANGULAR_DAMPING = math.max(0, math.min(50, tonumber(angular)))
        if WinchHand.dampedNode ~= nil and entityExists(WinchHand.dampedNode) then
            pcall(setAngularDamping, WinchHand.dampedNode, WinchHand.TONGUE_ANGULAR_DAMPING)
        end
    end
    if tonumber(yaw) ~= nil then
        WinchHand.VIEW_YAW_DAMP = math.max(0, math.min(50, tonumber(yaw)))
    end
    return string.format("winchDamp: the tongue's body %.1f, the yaw speed %.1f per second (winchDamp <body> [yaw])", WinchHand.TONGUE_ANGULAR_DAMPING, WinchHand.VIEW_YAW_DAMP)
end

-- winchTraffic [on|off]: whether a hooked log is also on the traffic's collision group (off = the hook leaves the log's collision group alone; for finding what stands logs on end)
function WinchHand.consoleTraffic(_, state)
    if state == "on" or state == "off" then
        WinchHand.TRAFFIC_SEES_LOGS = state == "on"
    end
    return string.format("winchTraffic: a hooked log is %s the traffic's group (winchTraffic on|off; applies to the next hook)", WinchHand.TRAFFIC_SEES_LOGS and "ON" or "NOT on")
end

-- winchBody [on|off]: an experiment: the player's own body (without the head) shown in first person, so there are arms and hands to look at. The game hides the whole model in first person (Player:onPerspectiveSwitched).
WinchHand.showBody, WinchHand.bodyMs = false, 0
function WinchHand.applyBody(on)
    local player = g_localPlayer
    local gc = player ~= nil and player.graphicsComponent or nil
    local camera = player ~= nil and player.camera or nil
    if gc == nil or gc.model == nil or camera == nil or not camera.isFirstPerson then
        return
    end
    pcall(gc.setModelVisibility, gc, on, true)
    if on and gc.model.hideHead ~= nil then
        pcall(gc.model.hideHead, gc.model)
    end
end

function WinchHand.updateBody(dt)
    if not WinchHand.showBody then
        return
    end
    WinchHand.bodyMs = WinchHand.bodyMs + (dt or 0)
    if WinchHand.bodyMs >= 500 then                      -- (the game sets the visibility again when you get out of a vehicle and so on)
        WinchHand.bodyMs = 0
        WinchHand.applyBody(true)
    end
end

function WinchHand.consoleBody(_, state)
    if state == "on" or state == "off" then
        WinchHand.showBody = state == "on"
        WinchHand.applyBody(WinchHand.showBody)
    end
    return string.format("winchBody: your body is %s in first person (winchBody on|off; first person only, an experiment)", WinchHand.showBody and "SHOWN" or "hidden")
end

if addConsoleCommand ~= nil and not WinchHand.barRegistered then
    WinchHand.barRegistered = true
    addConsoleCommand("winchBody", "WinchTow: show your body (no head) in first person [on|off]", "consoleBody", WinchHand)
    addConsoleCommand("winchTraffic", "WinchTow: a hooked log on the traffic's collision group [on|off]", "consoleTraffic", WinchHand)
    addConsoleCommand("winchDamp", "WinchTow: damping of the hooked tongue [body damping] [yaw damping]", "consoleDamp", WinchHand)
    addConsoleCommand("winchBar", "WinchTow: the hand winch's bar length [tongue|pole] [metres, 0.2 to 4]", "consoleBar", WinchHand)
end

-- Every frame: pulls the hooked vehicle's joint towards the player.
-- The main button on the wires, for another mod's tool (the leash of FS25_HorseDynamics holds the winch): wiresWantPress(hooked) = this press is not a click, wirePress() / wireRelease() (true = it was a reel, no click to make), wirePressed() = a press is going.
function WinchHand.wiresWantPress(hooked)
    return WinchWire ~= nil and WinchWire.wantsPress(hooked == true)
end
function WinchHand.wirePress()
    if WinchWire ~= nil then
        WinchWire.press()
    end
end
function WinchHand.wireRelease()
    return WinchWire ~= nil and WinchWire.release() or false
end
function WinchHand.wirePressed()
    return WinchWire ~= nil and WinchWire.pressMs ~= nil
end

function WinchHand.update(_, dt)
    -- published for other mods (mod globals are invisible between mods): the leash of FS25_HorseDynamics uses it as an easter egg (hold, putAway, pick, toggle, target)
    if g_currentMission ~= nil and g_currentMission.winchTow ~= WinchHand then
        g_currentMission.winchTow = WinchHand
    end
    WinchHand.updateMarker(dt)
    WinchHand.updateBody(dt)
    WinchHand.syncKeys()
    WinchHand.syncDamping()
    if WinchWire ~= nil then
        WinchWire.update(dt)
    end
    local target = WinchHand.target
    if target == nil then
        return
    end
    local player = g_localPlayer
    if target.vehicle.isDeleted or target.node == nil or not entityExists(target.node) or player == nil or not player.isControlled then
        WinchHand.letGo("winch let go (the vehicle is gone)")
        return
    end
    if target.kind == "log" and (target.component == nil or not entityExists(target.component) or getRigidBodyType(target.component) ~= RigidBodyType.DYNAMIC) then
        WinchHand.letGo("winch let go (the log was cut, belted or is gone)")
        return
    end
    local jx, jy, jz = getWorldTranslation(target.node)
    local px, camY, pz = getWorldTranslation(player:getCurrentCameraNode())
    WinchHand.cameraY = camY
    local ex, ez = px - jx, pz - jz
    local d = math.sqrt(ex * ex + ez * ez)
    local ropeMax = WinchHand.stage == "wire" and WinchHand.LATCH_ROPE_MAX_M or WinchHand.MAX_ROPE_M
    if d > ropeMax then
        WinchHand.letGo(string.format("winch let go: the rope would be %.0f m (more than %d m)", d, ropeMax))
        return
    end
    if WinchHand.stage == "wire" then
        return                                                          -- (a fixed latch: the rope only waits for the click on the other latch)
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
WinchHand.hint = nil                  -- optional function() -> { x, y, z, ux, uy, uz, radius } or nil: a ring to show instead of the pick (a horse tool: where a click would tie the log)
WinchHand.gate = nil                  -- optional function() -> bool: whether the tool's click would hook
WinchHand.marker, WinchHand.markerMs, WinchHand.markerShown, WinchHand.markerRed = nil, 0, false, false
WinchHand.LOCKED_EMISSIVE = { 0.5, 1.0, 6.0 }   -- the refusal ring is the Hammer's blue (what a pinned or frozen vehicle is on the map): the ring's own texture is green, so the tint is strong enough to drown it

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
    -- the hands carry something (a pole, a pallet): no ring on anything, it would say "hook me" to a thing in the hands
    local hands = g_localPlayer ~= nil and g_localPlayer.hands or nil
    if hands ~= nil and hands.spec_hands ~= nil and hands.spec_hands.heldItemNode ~= nil then
        hideMarker()
        WinchHand.markerMs = WinchHand.MARKER_EVERY_MS
        return
    end
    -- with the tool in the hand the ring is on the joint a click would hook (as before); without it, on the joint somebody asked about a moment ago (WinchHand.look: WAILA shows the joint in words, and this ring
    -- says which of the several points behind a tractor it means)
    local toolMode = WinchHand.hand ~= nil and WinchHand.target == nil and (WinchHand.gate == nil or WinchHand.gate())
    local asked = WinchHand.target == nil and WinchHand.lookTarget ~= nil and WinchHand.lookAskedAt ~= nil and (g_time or 0) - WinchHand.lookAskedAt < WinchHand.LOOK_RING_MS
    local hinted = WinchHand.hint ~= nil and WinchHand.hand ~= nil
    local attachMode = WinchHand.hand ~= nil and WinchHand.target ~= nil and (WinchHand.target.kind == "drawbar eye" or WinchHand.target.kind == "hitch" or WinchHand.target.kind == "winch latch")     -- (a hooked hitch gets the ring on the eye a click would take, as a hooked eye does on the hitch)
    if not toolMode and not asked and not hinted and not attachMode then
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
    -- a horse tool's ring (WinchHand.hint: a function that returns { x, y, z, ux, uy, uz, radius } or nil): the place a click would tie the log to
    if marker ~= nil and hinted then
        local ok, ring = pcall(WinchHand.hint)
        if not ok and not WinchHand.hintReported then
            WinchHand.hintReported = true
            print("[WinchHand] the hint ring failed: " .. tostring(ring))
        end
        if ok and ring ~= nil then
            marker:setIsActive(true)
            marker:setPosition(ring[1], ring[2], ring[3], ring[4], ring[5], ring[6], ring[7])
            WinchHand.markerShown = true
            return
        end
    end
    if not toolMode and not asked and not attachMode then
        hideMarker()
        return
    end
    local picked = nil
    if marker ~= nil and attachMode then
        picked = WinchHand.attachCandidate()                                   -- (the ring is on the hitch a click would attach the wagon to)
    elseif marker ~= nil then
        picked = toolMode and (WinchHand.pick(true) or (WinchHand.logsOk ~= false and WinchHand.pickLog() or nil)) or WinchHand.lookTarget
    end
    if picked == nil or picked.node == nil or (entityExists ~= nil and not entityExists(picked.node)) then
        hideMarker()
        return
    end
    if picked.kind == "log" and picked.ring ~= nil then
        local r = picked.ring
        if WinchHand.markerRed and marker.setColor ~= nil then                -- a log is never red (the colour of the last frozen vehicle would stay)
            WinchHand.markerRed = false
            pcall(marker.setColor, marker, 0, 2, 0)
        end
        marker:setIsActive(true)
        marker:setPosition(r[1], r[2], r[3], r[4], r[5], r[6], r[7])
        WinchHand.markerShown = true
        return
    end
    local ux, uy, uz = 0, 1, 0
    if picked.kind ~= "log" then
        ux, uy, uz = localDirectionToWorld(picked.node, 0, 1, 0)
    end
    -- red when the hook would be refused: a frozen (static) or pinned vehicle
    local locked = WinchHand.isLocked(picked)
    if locked ~= WinchHand.markerRed and marker.setColor ~= nil then
        WinchHand.markerRed = locked
        local c = locked and WinchHand.LOCKED_EMISSIVE or { 0, 2, 0 }
        pcall(marker.setColor, marker, c[1], c[2], c[3])
    end
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
    local wanted = target ~= nil and (WinchHand.stage == nil or WinchHand.stage == "pole" or WinchHand.stage == "drag" or WinchHand.stage == "wire" or WinchHand.SHOW_LINE) and WinchHand.hand ~= nil and target.node ~= nil and entityExists(target.node)
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
