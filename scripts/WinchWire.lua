--[[
    WinchWire.lua -- the wire approach for joining two pieces (the bridge grates of FS25_Hammer; any two vehicles that carry the BridgeLink function bridgeLinkPair).
    1. Hook a joint and click the fitting joint of the other piece: a steel wire is laid between the two, nothing moves. Do it again for the second pair.
    2. The main button held (0.3 s; a short press is the ordinary click) or the winch key (WINCH_CONTROL: K pulls in) reels ALL wires in at once: each loose piece is pulled along its wire(s) with a force, at most MAX_SPEED_MS, lifted a little so the ground does not hold it.
       A pinned or frozen piece stays where it is.
    3. When every wire between the two pieces is shorter than SNAP_M (25 cm: by the winch, by a push, by hand), they are joined: the first wire with the game's own attach (hitch and eye), every further one by the Hammer's second joint (BridgeLink).
    Ctrl and a click (or the unhitch key) on a piece takes its wires away.
]]
WinchWire = {}
WinchWire.wires = {}
WinchWire.LATCH_MAX_M = 120          -- a wire between two latches (poles on two banks) may be this long
WinchWire.MAX_M = 25               -- a wire can be laid between joints this far apart (the pieces start where you dragged them)
WinchWire.ACCEL_MS2 = 8            -- the pull: this many m/s2 times the piece's mass (as the drag of a log or a wheel-less vehicle), softer in the last 40 cm
WinchWire.LIFT_SHARE = 0.35        -- ... plus this share of the weight lifted off the ground (friction)
WinchWire.MAX_SPEED_MS = 0.8
WinchWire.CHAIN_CAP = 12            -- the pull counts what hangs on the piece (the chain of grates), at most this many times the piece's own mass
WinchWire.MIN_SHARE = 0.15                 -- the shorter of two wires between the same pieces is reeled at its length over the longer one's (so both run out together), at least this much of the full speed
WinchWire.SNAP_M = 0.25                -- every wire between two pieces this short (reeled, pushed by hand, whatever): they snap together
WinchWire.SLACK_M = 0.03               -- a reeled-in wire is a rope of its shortest length: it may stretch this much before it holds the pieces back
WinchWire.HOLD_ACCEL_PER_M = 30        -- ... then pulls back with this many m/s2 per metre of stretch ...
WinchWire.SWING_DAMP = 6                -- two chains hanging from two banks swing against each other like pendulums and never meet: while a wire is reeled or reeled in, the sideways speed of its piece is damped ...
WinchWire.SWING_ANG_DAMP = 3            -- ... and so is its spin (per second)
WinchWire.SWING_MAX_ACCEL = 25
WinchWire.HOLD_DAMP = 6                -- ... and this many m/s2 per m/s of the pieces moving apart (no swinging on the wire)
WinchWire.HOLD_MAX_ACCEL = 25
WinchWire.DIAMETER = 0.02
WinchWire.reelInput = 0
WinchWire.HOLD_MS = 300                 -- the main button held this long reels the wires in (a shorter press is the ordinary click)
WinchWire.pressMs = nil                 -- nil: the main button is not down on the wires; else how long it has been
WinchWire.reelEventId, WinchWire.reelEventOn = nil, nil

local function held(vehicle)
    local frame = vehicle.components ~= nil and vehicle.components[1] or nil
    return vehicle.hdPinned == true or (frame ~= nil and frame.isStatic == true)
end

local function ropeUpdate(rope, dt)                  -- (the game's update fails every frame when a node it points at was deleted with its vehicle)
    if rope.referenceFrame == nil or not entityExists(rope.referenceFrame) or rope.targetNode == nil or not entityExists(rope.targetNode) then
        return
    end
    return ForestryRope.update(rope, dt)
end

local function makeRope(fromNode, toNode)
    if WinchHand == nil or not WinchHand.ROPE or ForestryRope == nil or ForestryRope.new == nil or g_i3DManager == nil or Utils == nil or Utils.getFilename == nil then
        return nil
    end
    local ok, rope = pcall(function()
        local r = ForestryRope.new(nil, fromNode)
        r.i3dFilename, r.i3dRopePath = Utils.getFilename(WinchHand.ROPE_FILE, nil), WinchHand.ROPE_NODE
        r.diameter, r.uvScale = WinchWire.DIAMETER, WinchHand.ROPE_UV
        r.emissiveColor, r.invalidEmissiveColor = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
        r.update = ropeUpdate
        r.rfTarget = toNode
        r.sharedLoadRequestId = g_i3DManager:loadSharedI3DFileAsync(r.i3dFilename, false, false, r.onI3DLoaded, r, r)
        return r
    end)
    return ok and rope or nil
end

local function dropRope(wire)
    if WinchCable ~= nil then
        WinchCable.remove(wire)
    end
    if wire.rope ~= nil then
        pcall(wire.rope.delete, wire.rope)
        wire.rope = nil
    end
end

local function alive(wire)
    return not wire.hitch.vehicle.isDeleted and not wire.eye.vehicle.isDeleted and entityExists(wire.hitch.node) and entityExists(wire.eye.node)
end

local function length(wire)
    local ax, ay, az = getWorldTranslation(wire.hitch.node)
    local bx, by, bz = getWorldTranslation(wire.eye.node)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2), ax, ay, az, bx, by, bz
end

function WinchWire.has()
    return #WinchWire.wires > 0
end

function WinchWire.isWired(node)
    for _, w in ipairs(WinchWire.wires) do
        if w.hitch.node == node or w.eye.node == node then
            return true
        end
    end
    return false
end

local function between(a, b)
    local n = 0
    for _, w in ipairs(WinchWire.wires) do
        if (w.hitch.vehicle == a and w.eye.vehicle == b) or (w.hitch.vehicle == b and w.eye.vehicle == a) then
            n = n + 1
        end
    end
    return n
end

-- hooked: the hooked joint of WinchHand.target (vehicle, node, kind, index); other: the fitting joint (vehicle, node, kind, index). Returns the message.
function WinchWire.lay(hooked, other, label, latches)
    local hitch = hooked.kind == "hitch" and hooked or other
    local eye = hooked.kind == "hitch" and other or hooked
    local wire = { hitch = { vehicle = hitch.vehicle, node = hitch.node, index = hitch.index }, eye = { vehicle = eye.vehicle, node = eye.node, index = eye.index }, latch = latches == true or nil }
    wire.rope = makeRope(hitch.node, eye.node)
    table.insert(WinchWire.wires, wire)
    local d = length(wire)
    if latches then
        return string.format("wire laid between the latch of %s and the latch of %s (%.1f m): a person can walk it once both ends have been still for a second", label(hitch.vehicle), label(eye.vehicle), d)
    end
    return string.format("wire laid between %s and %s (%.1f m, %d of 2): hold the left mouse button to reel in (or K)", label(hitch.vehicle), label(eye.vehicle), d, math.min(between(hitch.vehicle, eye.vehicle), 2))
end

-- Takes the wires of a vehicle away. Returns how many.
function WinchWire.clear(vehicle)
    local n = 0
    for i = #WinchWire.wires, 1, -1 do
        local w = WinchWire.wires[i]
        if vehicle == nil or w.hitch.vehicle == vehicle or w.eye.vehicle == vehicle then
            dropRope(w)
            table.remove(WinchWire.wires, i)
            n = n + 1
        end
    end
    return n
end

-- The main button (the tool's click) goes down while wires exist and nothing is hooked: it is a click only if it is let go within HOLD_MS, else it reels.
function WinchWire.wantsPress(hooked)
    if hooked or #WinchWire.wires == 0 or WinchHand == nil or WinchHand.hand == nil then
        return false
    end
    if Input ~= nil and Input.isKeyPressed ~= nil and ((Input.KEY_lctrl ~= nil and Input.isKeyPressed(Input.KEY_lctrl)) or (Input.KEY_lshift ~= nil and Input.isKeyPressed(Input.KEY_lshift))) then
        return false                                              -- (Ctrl / Shift and a click are the unhitch clicks)
    end
    return true
end

function WinchWire.press()
    WinchWire.pressMs = 0
    Logging.info("[WinchWire] main button down on the wires: held %d ms reels them in", WinchWire.HOLD_MS)
end

-- The main button is up: returns true when it had been reeling (no click to make).
function WinchWire.release()
    local was = WinchWire.pressMs
    WinchWire.pressMs = nil
    return was ~= nil and was >= WinchWire.HOLD_MS
end

function WinchWire.setReelInput(value)
    WinchWire.reelInput = value or 0
end

local function setReelActive(on)
    if WinchWire.reelEventId ~= nil and WinchWire.reelEventOn ~= on and g_inputBinding ~= nil then
        WinchWire.reelEventOn = on
        g_inputBinding:setActionEventActive(WinchWire.reelEventId, on)
    end
end

-- The force on one piece, along its wire(s), at the joint.
local function pull(vehicle, x, y, z, dx, dy, dz, wires, factor, share)
    local comp = vehicle.components ~= nil and vehicle.components[1] or nil
    if comp == nil or held(vehicle) then
        return
    end
    local vx, vy, vz = getLinearVelocity(comp.node)
    if vx * dx + vy * dy + vz * dz > WinchWire.MAX_SPEED_MS * share then
        return
    end
    local mass = WinchHand.pullMass(vehicle, comp.node)
    local chain = mass
    local root = vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() or vehicle      -- (a grate hitched to others drags the whole chain: the root carries it all)
    if root.getTotalMass ~= nil then
        local ok, total = pcall(root.getTotalMass, root, false)
        if ok and total ~= nil and total > mass then
            chain = math.min(total, mass * WinchWire.CHAIN_CAP)
        end
    end
    local f = chain * WinchWire.ACCEL_MS2 * factor * share
    addForce(comp.node, dx * f, dy * f + WinchWire.LIFT_SHARE * mass * 9.81 / wires, dz * f, x, y, z, false)
end

-- The sideways damping of a piece on a wire (a viscous drag on the speed across the wire, and on the spin): what the swing of a hanging chain needs to die down. Shared between the wires a piece has.
local function damp(vehicle, dx, dy, dz, wires, dt)
    local comp = vehicle.components ~= nil and vehicle.components[1] or nil
    if comp == nil or held(vehicle) then
        return
    end
    local vx, vy, vz = getLinearVelocity(comp.node)
    local along = vx * dx + vy * dy + vz * dz
    local sx, sy, sz = vx - along * dx, vy - along * dy, vz - along * dz
    local speed = math.sqrt(sx * sx + sy * sy + sz * sz)
    if speed > 0.02 then
        local mass = WinchHand.pullMass(vehicle, comp.node)
        local chain = mass
        local root = vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() or vehicle
        if root.getTotalMass ~= nil then
            local ok, total = pcall(root.getTotalMass, root, false)
            if ok and total ~= nil and total > mass then
                chain = math.min(total, mass * WinchWire.CHAIN_CAP)
            end
        end
        local accel = math.min(WinchWire.SWING_MAX_ACCEL, WinchWire.SWING_DAMP * speed)
        local f = chain * accel / wires / speed
        local cx, cy, cz = getWorldTranslation(comp.node)
        addForce(comp.node, -sx * f, -sy * f, -sz * f, cx, cy, cz, false)
    end
    if getAngularVelocity ~= nil and setAngularVelocity ~= nil and WinchWire.SWING_ANG_DAMP > 0 then
        local ax, ay, az = getAngularVelocity(comp.node)
        local k = math.exp(-WinchWire.SWING_ANG_DAMP * (dt or 16) / 1000 / wires)
        setAngularVelocity(comp.node, ax * k, ay * k, az * k)
    end
end

-- A wire that has been reeled in cannot be pulled back out: beyond its shortest length it pulls both pieces back, spring and damper along the wire (a rope, not a spring: nothing while it is slack).
local function hold(w, d, stretch, ax, ay, az, bx, by, bz)
    local a, b = w.hitch.vehicle, w.eye.vehicle
    local ca = a.components ~= nil and a.components[1] or nil
    local cb = b.components ~= nil and b.components[1] or nil
    if ca == nil or cb == nil or d < 1e-3 then
        return
    end
    local dx, dy, dz = (bx - ax) / d, (by - ay) / d, (bz - az) / d
    local avx, avy, avz = getLinearVelocity(ca.node)
    local bvx, bvy, bvz = getLinearVelocity(cb.node)
    local apart = math.max(0, (bvx - avx) * dx + (bvy - avy) * dy + (bvz - avz) * dz)
    local acc = math.min(WinchWire.HOLD_MAX_ACCEL, WinchWire.HOLD_ACCEL_PER_M * stretch + WinchWire.HOLD_DAMP * apart)
    if not held(a) then
        local m = WinchHand.pullMass(a, ca.node) * acc
        addForce(ca.node, dx * m, dy * m, dz * m, ax, ay, az, false)
    end
    if not held(b) then
        local m = WinchHand.pullMass(b, cb.node) * acc
        addForce(cb.node, -dx * m, -dy * m, -dz * m, bx, by, bz, false)
    end
end

local function wiresOf(vehicle)
    local n = 0
    for _, w in ipairs(WinchWire.wires) do
        if w.hitch.vehicle == vehicle or w.eye.vehicle == vehicle then
            n = n + 1
        end
    end
    return n
end

-- One line a second while reeling: why a piece does (not) move.
local function why(vehicle, d)
    local comp = vehicle.components ~= nil and vehicle.components[1] or nil
    if comp == nil then
        return "no component"
    end
    local vx, vy, vz = getLinearVelocity(comp.node)
    local att = vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() or nil
    local n = vehicle.getAttachedImplements ~= nil and #vehicle:getAttachedImplements() or 0
    return string.format("%s: held=%s pinned=%s static=%s speed=%.2f m/s pullMass=%.0f total=%.0f attachedTo=%s implements=%d wires=%d dist=%.2f", tostring(vehicle.configFileName and vehicle.configFileName:match("([^/]+)%.xml$") or "?"), tostring(held(vehicle)), tostring(vehicle.hdPinned == true), tostring(comp.isStatic == true), math.sqrt(vx * vx + vy * vy + vz * vz), WinchHand.pullMass(vehicle, comp.node), (vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle().getTotalMass ~= nil) and vehicle:getRootVehicle():getTotalMass(false) or -1, att ~= nil and tostring(att.configFileName and att.configFileName:match("([^/]+)%.xml$")) or "nil", n, wiresOf(vehicle), d)
end

-- Two pieces whose wires are all (almost) zero: joined.
local function finish(group, notify, label)
    local first = group[1]
    local hv, ev = first.hitch.vehicle, first.eye.vehicle
    local linked = (ev.getAttacherVehicle ~= nil and ev:getAttacherVehicle() == hv) or (hv.getAttacherVehicle ~= nil and hv:getAttacherVehicle() == ev)
    local rest = {}
    local answer = string.format("%s and %s joined", label(hv), label(ev))
    for i, w in ipairs(group) do
        if i == 1 and not linked then
            local ok, why = WinchHand.attachPair(w.hitch, w.eye)
            if not ok then
                answer = string.format("%s and %s could not be joined: %s", label(hv), label(ev), tostring(why))
            end
        else
            rest[#rest + 1] = w
        end
    end
    for _, w in ipairs(rest) do
        if hv.bridgeLinkPair ~= nil then
            local ok, a, why = pcall(hv.bridgeLinkPair, hv, ev, w.hitch.node, w.eye.node)
            if not ok or a ~= true then
                answer = string.format("the second joint did not work: %s", tostring(ok and why or a))
            end
        end
    end
    for _, w in ipairs(group) do
        for i = #WinchWire.wires, 1, -1 do
            if WinchWire.wires[i] == w then
                dropRope(w)
                table.remove(WinchWire.wires, i)
            end
        end
    end
    notify(answer)
end

-- ===== latch wires are saved =====
-- A wire between two latches (the poles, the anchors) is written to winchWires.xml in the savegame folder whenever the game saves (FSBaseMission.saveSavegame): the two vehicles' unique ids and the numbers of the joints.
-- At a load they are laid again as soon as both vehicles exist (tried for a minute); a pair that is wired already (the Hammer's guide lays the pole wires itself) is not wired twice. Wires between bridge pieces (hitch and eye) are
-- the reeling of a moment and are not saved.
WinchWire.SAVE_FILE = "winchWires.xml"
WinchWire.LOAD_GIVE_UP_MS = 60000
WinchWire.pending, WinchWire.pendingMs = nil, 0

function WinchWire.save()
    local dir = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.savegameDirectory or nil
    if dir == nil or XMLFile == nil then
        return
    end
    local xml = XMLFile.create("winchWiresXML", dir .. "/" .. WinchWire.SAVE_FILE, "winchWires")
    if xml == nil then
        return
    end
    local i = 0
    for _, w in ipairs(WinchWire.wires) do
        local va, vb = w.hitch.vehicle, w.eye.vehicle
        if w.latch and va.getUniqueId ~= nil and vb.getUniqueId ~= nil and va:getUniqueId() ~= nil and vb:getUniqueId() ~= nil and w.hitch.index ~= nil and w.eye.index ~= nil then
            local key = string.format("winchWires.wire(%d)", i)
            xml:setString(key .. "#a", va:getUniqueId())
            xml:setInt(key .. "#ai", w.hitch.index)
            xml:setString(key .. "#b", vb:getUniqueId())
            xml:setInt(key .. "#bi", w.eye.index)
            i = i + 1
        end
    end
    xml:save()
    xml:delete()
end

-- The saved wires, as a list { a, ai, b, bi } (empty without a file).
function WinchWire.readSaved()
    local out = {}
    local dir = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.savegameDirectory or nil
    if dir == nil or XMLFile == nil or fileExists == nil or not fileExists(dir .. "/" .. WinchWire.SAVE_FILE) then
        return out
    end
    local xml = XMLFile.load("winchWiresXML", dir .. "/" .. WinchWire.SAVE_FILE)
    if xml == nil then
        return out
    end
    xml:iterate("winchWires.wire", function(_, key)
        local a, b = xml:getString(key .. "#a"), xml:getString(key .. "#b")
        if a ~= nil and b ~= nil then
            out[#out + 1] = { a = a, ai = xml:getInt(key .. "#ai", 0), b = b, bi = xml:getInt(key .. "#bi", 0) }
        end
    end)
    xml:delete()
    return out
end

function WinchWire.startLoading()
    WinchWire.pending, WinchWire.pendingMs = WinchWire.readSaved(), 0
end

local function latchOf(vehicle, index)
    local joints = vehicle ~= nil and vehicle.spec_attacherJoints ~= nil and vehicle.spec_attacherJoints.attacherJoints or nil
    local j = joints ~= nil and joints[index] or nil
    return j ~= nil and j.jointTransform or nil
end

-- Called every update: lays the saved wires whose two vehicles exist now.
function WinchWire.layPending(dt)
    local list = WinchWire.pending
    if list == nil or #list == 0 then
        return
    end
    WinchWire.pendingMs = WinchWire.pendingMs + (dt or 0)
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for i = #list, 1, -1 do
        local e = list[i]
        local va = system ~= nil and system.getVehicleByUniqueId ~= nil and system:getVehicleByUniqueId(e.a) or nil
        local vb = system ~= nil and system.getVehicleByUniqueId ~= nil and system:getVehicleByUniqueId(e.b) or nil
        if va ~= nil and vb ~= nil and not va.isDeleted and not vb.isDeleted then
            local na, nb = latchOf(va, e.ai), latchOf(vb, e.bi)
            if na ~= nil and nb ~= nil and entityExists(na) and entityExists(nb) then
                if not WinchWire.isWired(na) and not WinchWire.isWired(nb) then
                    local label = (WinchHand ~= nil and WinchHand.labelOf) or function(v) return tostring(v.configFileName or "vehicle") end
                    WinchWire.lay({ vehicle = va, node = na, kind = "winch latch", index = e.ai }, { vehicle = vb, node = nb, kind = "winch latch", index = e.bi }, label, true)
                    Logging.info("[WinchWire] a saved wire between two latches is laid again")
                end
                table.remove(list, i)
            end
        end
    end
    if #list > 0 and WinchWire.pendingMs > WinchWire.LOAD_GIVE_UP_MS then
        Logging.info("[WinchWire] %d saved wire(s) could not be laid again (a vehicle is gone)", #list)
        WinchWire.pending = nil
    end
end

if FSBaseMission ~= nil and FSBaseMission.saveSavegame ~= nil and Utils ~= nil and not WinchWire.saveHooked then
    WinchWire.saveHooked = true
    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, function()
        local ok, err = pcall(WinchWire.save)
        if not ok then
            Logging.warning("[WinchWire] the wires could not be saved: %s", tostring(err))
        end
    end)
end
if g_messageCenter ~= nil and MessageType ~= nil and MessageType.SAVEGAME_LOADED ~= nil and not WinchWire.loadHooked then
    WinchWire.loadHooked = true
    g_messageCenter:subscribe(MessageType.SAVEGAME_LOADED, WinchWire.startLoading, WinchWire)
end

function WinchWire.update(dt)
    WinchWire.layPending(dt)
    local wires = WinchWire.wires
    if #wires == 0 then
        WinchWire.pressMs = nil
        setReelActive(false)
        return
    end
    if WinchWire.pressMs ~= nil then
        WinchWire.pressMs = WinchWire.pressMs + (dt or 0)
    end
    for i = #wires, 1, -1 do
        if not alive(wires[i]) then
            dropRope(wires[i])
            table.remove(wires, i)
        end
    end
    setReelActive(WinchHand ~= nil and WinchHand.hand ~= nil and #wires > 0)
    local reel = (WinchWire.reelInput > 0.5 or (WinchWire.pressMs ~= nil and WinchWire.pressMs >= WinchWire.HOLD_MS)) and WinchHand ~= nil and WinchHand.hand ~= nil
    if reel ~= (WinchWire.reeling == true) then
        WinchWire.reeling = reel
        Logging.info("[WinchWire] %s", reel and "reeling the wires in" or "reeling stopped")
    end
    local lengths, longest = {}, {}
    for _, w in ipairs(wires) do                                       -- (the longest wire of each pair of pieces: the shorter ones are reeled slower, so all arrive together)
        lengths[w] = (length(w))
        local a, b = tostring(w.hitch.vehicle), tostring(w.eye.vehicle)
        local key = a < b and (a .. b) or (b .. a)
        longest[w] = key
        longest[key] = math.max(longest[key] or 0, lengths[w])
    end
    for i, w in ipairs(wires) do
        local rope = w.rope
        if rope ~= nil and rope.referenceFrame ~= nil and not rope.tied then
            rope.tied = pcall(rope.setTargetNode, rope, w.eye.node, true)
        end
        local d, ax, ay, az, bx, by, bz = length(w)
        if WinchCable ~= nil then
            WinchCable.update(w, dt, ax, ay, az, bx, by, bz)
        end
        if w.maxLen ~= nil and d - w.maxLen > WinchWire.SLACK_M then
            hold(w, d, d - w.maxLen - WinchWire.SLACK_M, ax, ay, az, bx, by, bz)
        end
        if (reel or w.maxLen ~= nil) and d > 1e-3 and not w.latch then                           -- (reeled in: the pieces are on the wire, the swing is damped; a latch wire between poles is no business of the damping)
            local ddx, ddy, ddz = (bx - ax) / d, (by - ay) / d, (bz - az) / d
            damp(w.hitch.vehicle, ddx, ddy, ddz, wiresOf(w.hitch.vehicle), dt)
            damp(w.eye.vehicle, ddx, ddy, ddz, wiresOf(w.eye.vehicle), dt)
        end
        if reel and d > 1e-3 then
            if w.maxLen == nil then
                Logging.info("[WinchWire] a wire is reeled in: it holds at %.2f m now (cannot be pulled back out)", d)
            end
            w.maxLen = math.min(w.maxLen or d, d)
            local dx, dy, dz = (bx - ax) / d, (by - ay) / d, (bz - az) / d
            local factor = math.min(1, d / 0.4)
            local share = math.max(WinchWire.MIN_SHARE, math.min(1, d / math.max(longest[longest[w]], 1e-3)))
            WinchWire.diagMs = (WinchWire.diagMs or 0) + (dt or 0)
            if WinchWire.diagMs >= 1000 then
                WinchWire.diagMs = 0
                for _, v in ipairs({ w.hitch.vehicle, w.eye.vehicle }) do
                    local ok, line = pcall(why, v, d)
                    Logging.info("[WinchWire] reel: %s", ok and line or ("diag failed: " .. tostring(line)))
                end
            end
            pull(w.hitch.vehicle, ax, ay, az, dx, dy, dz, wiresOf(w.hitch.vehicle), factor, share)
            pull(w.eye.vehicle, bx, by, bz, -dx, -dy, -dz, wiresOf(w.eye.vehicle), factor, share)
        end
    end
    -- every wire between two pieces short: joined
    local done = {}
    for _, w in ipairs(wires) do
      if not w.latch then                                                   -- (a latch wire joins nothing: it stays a wire)
        local a, b = tostring(w.hitch.vehicle), tostring(w.eye.vehicle)
        local key = a < b and (a .. b) or (b .. a)
        local g = done[key]
        if g == nil then
            g = { ok = true }
            done[key] = g
        end
        g[#g + 1] = w
        if lengths[w] > WinchWire.SNAP_M then
            g.ok = false
        end
      end
    end
    for _, g in pairs(done) do
        if g.ok then
            finish(g, WinchHand.notify, WinchHand.labelOf or function(v) return tostring(v.configFileName or "piece") end)
        end
    end
end
