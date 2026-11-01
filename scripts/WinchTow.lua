--[[
    WinchTow.lua -- the winch rope can be attached to the attacher joints of other vehicles (to pull a tractor out, a trailer by its drawbar eye ...), not only to trees and logs.

    The game (checked in the 28 Oct 2026 archive): in attach mode Winch:onPostUpdate casts the player's view ray with CollisionFlag.TREE, so only trees and logs are ever hit;
    Winch:onWinchTreeRaycastCallback accepts only shapes with getSplitType() ~= 0 and stores the target in spec.treeRaycast (lastValidTree, treeTargetPos, treeCenterPos, treeUp, treeRadius);
    the target marker (the green ring) is placed from those, the attach input calls attachTreeToWinch(lastValidTree, treeTargetPos ...), which hooks onto the tree (ForestryHook:mountToTree)
    and makes the physics rope between the winch and that body (rope.mainRope:create(shape, hookTarget ...)). Nothing in it knows about vehicles.

    So, in the same shape:
      1. DETECT. While a rope is in attach mode and no tree is targeted, the attacher joint (of a vehicle in another group than the winch's) nearest to the view ray, within PICK_RADIUS_M, is injected as the
         valid target: lastValidTree = the vehicle's component node (a physics body, so getMass and the physics rope work on it), the positions of the joint, the ring round the joint. Vanilla then draws the
         marker, makes the rope green and enables the attach prompt. While a vehicle joint is picked the tree raycast is held back (its callback would reset the target every frame).
      2. ATTACH. ForestryHook:mountToTree is wrapped: for one of our targets the hook is linked to the joint node (a tree would get a belt); everything else in attachTreeToWinch (the physics rope, the joint
         limits of the winch, sounds, prompts, the mass limit maxTreeMass) is vanilla.
      3. SAVE. Vehicle attachments cannot be restored from a split shape id, so they are left out of the savegame (Winch:saveToXMLFile): after a reload the rope is simply not attached.
    Single player only: the multiplayer events carry split shape ids.
]]
WinchTow = {}

WinchTow.ENABLED = true
WinchTow.PICK_RADIUS_M = 0.35       -- a joint counts when it is this close to the view ray
WinchTow.MIN_RANGE_M = 0.3
WinchTow.MARKER_RADIUS_M = 0.18     -- the ring round the joint
WinchTow.targets = {}               -- component node -> { vehicle, node, component, kind, x, y, z }

local function say(format, ...)
    print(string.format("[WinchTow] " .. format, ...))
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

local function rootOf(vehicle)
    if vehicle.getRootVehicle ~= nil then
        local ok, root = pcall(vehicle.getRootVehicle, vehicle)
        if ok and root ~= nil then
            return root
        end
    end
    return vehicle
end

-- The attacher joints of a vehicle: { node, component, kind }. The joints a vehicle HAS (where implements go: a tractor's hitch, a winch's own trailer joint) and the ones it CARRIES for being attached
-- (a trailer's drawbar eye, an implement's lower link points).
function WinchTow.jointsOf(vehicle)
    local out = {}
    local function component(node)
        if vehicle.getParentComponent ~= nil then
            local ok, c = pcall(vehicle.getParentComponent, vehicle, node)
            if ok then
                return c
            end
        end
        return nil
    end
    local parent = vehicle.spec_attacherJoints
    for _, joint in ipairs(parent ~= nil and parent.attacherJoints or {}) do
        if joint.jointTransform ~= nil then
            out[#out + 1] = { node = joint.jointTransform, component = joint.jointComponent or component(joint.jointTransform), kind = "hitch" }
        end
    end
    local attachable = vehicle.spec_attachable
    for _, joint in ipairs(attachable ~= nil and attachable.inputAttacherJoints or {}) do
        if joint.node ~= nil then
            out[#out + 1] = { node = joint.node, component = component(joint.node), kind = "drawbar eye" }
        end
    end
    return out
end

-- The joint nearest to the ray (ox, oy, oz) + t * (dx, dy, dz), 0 < t < maxRange, within PICK_RADIUS_M, of a vehicle in another group than `winch`.
-- reach: optional { x, y, z, distance }: the rope can only reach joints that far from that point (the winch's rope node).
function WinchTow.pick(winch, ox, oy, oz, dx, dy, dz, maxRange, reach)
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    local winchRoot = rootOf(winch)
    local best, bestDistance = nil, WinchTow.PICK_RADIUS_M
    for _, vehicle in ipairs(vehicles) do
        if vehicle ~= winch and not vehicle.isDeleted and rootOf(vehicle) ~= winchRoot then
            for _, joint in ipairs(WinchTow.jointsOf(vehicle)) do
                if joint.component ~= nil and joint.component ~= 0 and entityExists(joint.node) then
                    local px, py, pz = getWorldTranslation(joint.node)
                    local vx, vy, vz = px - ox, py - oy, pz - oz
                    local t = vx * dx + vy * dy + vz * dz
                    if t >= WinchTow.MIN_RANGE_M and t <= maxRange then
                        local qx, qy, qz = vx - dx * t, vy - dy * t, vz - dz * t
                        local d = math.sqrt(qx * qx + qy * qy + qz * qz)
                        local inReach = true
                        if reach ~= nil then
                            local rx, ry, rz = px - reach.x, py - reach.y, pz - reach.z
                            inReach = math.sqrt(rx * rx + ry * ry + rz * rz) <= reach.distance
                        end
                        if d < bestDistance and inReach then
                            best, bestDistance = { vehicle = vehicle, node = joint.node, component = joint.component, kind = joint.kind, x = px, y = py, z = pz }, d
                        end
                    end
                end
            end
        end
    end
    return best
end

-- The attacher joint nearest to a point (horizontally), within radius, of a vehicle that is not attached to another vehicle and is not `except`: { vehicle, node, component, kind, x, y, z, distance }, or nil.
-- For a puller that backs up to something (a horse in its harness, FS25_HorseDynamics: the game's attach key shows when this finds a joint behind it).
function WinchTow.nearest(x, z, radius, except)
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    local best, bestDistance = nil, radius
    for _, vehicle in ipairs(vehicles) do
        local attached = vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil
        if vehicle ~= except and not vehicle.isDeleted and not attached then
            for _, joint in ipairs(WinchTow.jointsOf(vehicle)) do
                if joint.component ~= nil and joint.component ~= 0 and entityExists(joint.node) then
                    local px, py, pz = getWorldTranslation(joint.node)
                    local d = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
                    if d < bestDistance then
                        best, bestDistance = { vehicle = vehicle, node = joint.node, component = joint.component, kind = joint.kind, x = px, y = py, z = pz, distance = d }, d
                    end
                end
            end
        end
    end
    return best
end

-- Lets go of what this mod put into the winch's targeting (a picked vehicle joint), and lets the tree raycast run again.
function WinchTow.release(spec, rope)
    local tr = spec.treeRaycast
    if rope.rfTowActive then
        if tr.lastValidTree ~= nil and WinchTow.targets[tr.lastValidTree] ~= nil then
            tr.lastValidTree = nil
        end
        tr.hasStarted = false
        rope.rfTowActive = false
        if rope.attachMarker ~= nil then
            rope.attachMarker:setIsActive(false)
        end
    end
end

function WinchTow.updateRope(winch, spec, rope)
    local tr = spec.treeRaycast
    local player = g_localPlayer
    if player == nil or not player.isControlled or (player.getIsHoldingHandTool ~= nil and player:getIsHoldingHandTool()) then
        WinchTow.release(spec, rope)
        return
    end
    -- a tree is targeted: that is vanilla's, not ours
    if tr.lastValidTree ~= nil and WinchTow.targets[tr.lastValidTree] == nil then
        return
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    local reach = nil
    if tr.startPos ~= nil and tr.maxDistance ~= nil and tr.maxDistance < math.huge then
        reach = { x = tr.startPos[1], y = tr.startPos[2], z = tr.startPos[3], distance = tr.maxDistance }
    end
    local target = WinchTow.pick(winch, ox, oy, oz, dx, dy, dz, (Winch ~= nil and Winch.TREE_RAYCAST_DISTANCE) or 5, reach)
    if target == nil then
        WinchTow.release(spec, rope)
        return
    end
    local ux, uy, uz = localDirectionToWorld(target.node, 0, 1, 0)
    tr.treeTargetPos, tr.treeCenterPos, tr.treeUp = tr.treeTargetPos or { 0, 0, 0 }, tr.treeCenterPos or { 0, 0, 0 }, tr.treeUp or { 0, 1, 0 }
    tr.treeTargetPos[1], tr.treeTargetPos[2], tr.treeTargetPos[3] = target.x, target.y, target.z
    tr.treeCenterPos[1], tr.treeCenterPos[2], tr.treeCenterPos[3] = target.x, target.y, target.z
    tr.treeUp[1], tr.treeUp[2], tr.treeUp[3] = ux, uy, uz
    tr.treeRadius = WinchTow.MARKER_RADIUS_M
    tr.lastValidTree, tr.lastInValidTree = target.component, nil
    tr.hasStarted = true                  -- no tree raycast while a joint is picked: its callback would reset lastValidTree
    if WinchTow.targets[target.component] == nil or WinchTow.targets[target.component].node ~= target.node then
        say("target: the %s of %s", target.kind, vehicleName(target.vehicle))
    end
    WinchTow.targets[target.component] = target
    rope.rfTowActive = true
    if rope.attachMarker ~= nil then
        rope.attachMarker:setIsActive(true)
        rope.attachMarker:setPosition(target.x, target.y, target.z, ux, uy, uz, WinchTow.MARKER_RADIUS_M)
    end
    if rope.setupRope ~= nil and rope.setupRope.setEmissiveColor ~= nil then
        rope.setupRope:setEmissiveColor(0, 1, 0, 1)
    end
end

-- Appended to Winch:onPostUpdate.
-- The support leg of a vehicle (a trailer's peg that holds its drawbar up when it stands unhitched): the game plays the support animation backwards when the vehicle is attached to another vehicle
-- (Attachable:onPostAttach: playAnimation(name, -1, nil, true)) and forwards when it is detached. A rope is no attachment, so this does it for the rope: retracted = true pulls the leg up, false puts it down.
-- A vehicle attached to another one is left alone (that has its own say). Returns whether the vehicle has a support animation.
WinchTow.supportHeld = setmetatable({}, { __mode = "k" })       -- vehicle -> owner (the winch, or a name): whose rope has retracted its leg

function WinchTow.setSupport(vehicle, retracted)
    local attachable = vehicle.spec_attachable
    if attachable == nil or vehicle.playAnimation == nil or vehicle.isDeleted then
        return false
    end
    if vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil then
        return false
    end
    local found = false
    for _, support in ipairs(attachable.supportAnimations or {}) do
        if support.animationName ~= nil then
            pcall(vehicle.playAnimation, vehicle, support.animationName, retracted and -1 or 1, nil, true)
            found = true
        end
    end
    if found then
        say("the support leg of %s goes %s", vehicleName(vehicle), retracted and "up" or "down")
    end
    return found
end

-- Every frame of a winch: the vehicles its ropes hold get their support leg up, the ones it let go get it down again.
function WinchTow.syncSupports(winch, spec)
    local held = {}
    for _, rope in ipairs(spec.ropes or {}) do
        for _, data in ipairs(rope.attachedTrees or {}) do
            local target = WinchTow.targets[data.treeId]
            if target ~= nil and target.vehicle ~= nil then
                held[target.vehicle] = true
            end
        end
    end
    for vehicle in pairs(held) do
        if WinchTow.supportHeld[vehicle] == nil and WinchTow.setSupport(vehicle, true) then
            WinchTow.supportHeld[vehicle] = winch                       -- (only what this pulled up is put down again)
        end
    end
    for vehicle, owner in pairs(WinchTow.supportHeld) do
        if owner == winch and not held[vehicle] then
            WinchTow.supportHeld[vehicle] = nil
            WinchTow.setSupport(vehicle, false)
        end
    end
end

function WinchTow.update(winch)
    if not WinchTow.ENABLED or not winch.isServer then
        return
    end
    local spec = winch.spec_winch
    if spec == nil or spec.treeRaycast == nil then
        return
    end
    for _, rope in ipairs(spec.ropes or {}) do
        if rope.isAttachModeActive then
            WinchTow.updateRope(winch, spec, rope)
        elseif rope.rfTowActive then
            WinchTow.release(spec, rope)
        end
    end
    WinchTow.syncSupports(winch, spec)
end

-- Console wtProbe: the attacher joints near where you look, with their distance from the view ray (what the picker sees).
function WinchTow.probe()
    local player = g_localPlayer
    if player == nil or player.getCurrentCameraNode == nil then
        return "no player"
    end
    local camera = player:getCurrentCameraNode()
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    local lines = {}
    for _, vehicle in ipairs(g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        for _, joint in ipairs(WinchTow.jointsOf(vehicle)) do
            if entityExists(joint.node) then
                local px, py, pz = getWorldTranslation(joint.node)
                local vx, vy, vz = px - ox, py - oy, pz - oz
                local t = vx * dx + vy * dy + vz * dz
                local qx, qy, qz = vx - dx * t, vy - dy * t, vz - dz * t
                local d = math.sqrt(qx * qx + qy * qy + qz * qz)
                if t > 0 and t < 15 then
                    lines[#lines + 1] = { d = d, text = string.format("%s: %s of %s, %.1f m along the view, %.2f m off the ray%s", joint.kind, tostring(joint.node), vehicleName(vehicle), t, d, (joint.component == nil or joint.component == 0) and " (NO component: cannot be picked)" or "") }
                end
            end
        end
    end
    table.sort(lines, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(#lines, 12) do
        out[#out + 1] = lines[i].text
    end
    local text = #out > 0 and table.concat(out, "\n") or "no attacher joint within 15 m in front of you"
    print("[WinchTow] probe (a joint is picked within " .. WinchTow.PICK_RADIUS_M .. " m of the ray, other vehicle group than the winch):\n" .. text)
    return text
end

-- ===== hooks (the game's classes, patched once when this file loads) =====
if Winch ~= nil and Winch.onPostUpdate ~= nil and Utils ~= nil and not WinchTow.hooked then
    WinchTow.hooked = true
    Winch.onPostUpdate = Utils.appendedFunction(Winch.onPostUpdate, function(self, ...)
        local ok, err = pcall(WinchTow.update, self)
        if not ok then
            say("update failed (%s)", tostring(err))
        end
    end)
    if ForestryHook ~= nil and ForestryHook.mountToTree ~= nil then
        ForestryHook.mountToTree = Utils.overwrittenFunction(ForestryHook.mountToTree, function(self, superFunc, splitShapeId, x, y, z, ...)
            local target = WinchTow.targets[splitShapeId]
            if target ~= nil and target.node ~= nil and entityExists(target.node) then
                self:link(target.node, 0, 0, 0, 0, 0, 0)
                self.splitShapeId, self.beltShape = nil, nil
                say("rope attached to the %s of %s", target.kind, vehicleName(target.vehicle))
                return x, y, z
            end
            return superFunc(self, splitShapeId, x, y, z, ...)
        end)
    end
    -- The attach key (B). The game checks the mass of what is attached against the rope's limit for TREES (maxTreeMass: 8.6 or 20 tonnes) and only shows a short warning when it is too heavy: a tractor or a
    -- trailer weighs more than a log, so for a vehicle joint the limit is lifted for that one call (the rope's physics decide whether it can pull it), and the log says what happened.
    if WinchAttachTreeActivatable ~= nil and WinchAttachTreeActivatable.onAttachTree ~= nil then
        WinchAttachTreeActivatable.onAttachTree = Utils.overwrittenFunction(WinchAttachTreeActivatable.onAttachTree, function(self, superFunc, ...)
            local tr = self.vehicle ~= nil and self.vehicle.spec_winch ~= nil and self.vehicle.spec_winch.treeRaycast or nil
            local target = tr ~= nil and tr.lastValidTree ~= nil and WinchTow.targets[tr.lastValidTree] or nil
            if target == nil then
                return superFunc(self, ...)
            end
            local rope = self.rope
            local before = #rope.attachedTrees
            say("attach key on the %s of %s: the vehicle weighs %.1f t, the rope's limit for trees is %.1f t (lifted for a vehicle)", target.kind, vehicleName(target.vehicle),
                getMass ~= nil and getMass(target.component) or 0, rope.maxTreeMass or 0)
            local limit = rope.maxTreeMass
            rope.maxTreeMass = math.huge
            local ok, err = pcall(superFunc, self, ...)
            rope.maxTreeMass = limit
            if not ok then
                say("attaching failed: %s", tostring(err))
            elseif #rope.attachedTrees == before then
                say("attaching did nothing: the game refused it (too many ropes on the winch: %d of %d) or the hook could not mount", before, rope.maxNumTrees or 0)
            end
        end)
    end
    if Winch.saveToXMLFile ~= nil then
        Winch.saveToXMLFile = Utils.overwrittenFunction(Winch.saveToXMLFile, function(self, superFunc, xmlFile, key, usedModNames)
            local parked = {}
            for _, rope in ipairs(self.spec_winch ~= nil and self.spec_winch.ropes or {}) do
                for i = #rope.attachedTrees, 1, -1 do
                    local data = rope.attachedTrees[i]
                    if WinchTow.targets[data.treeId] ~= nil then
                        parked[#parked + 1] = { rope, i, data }
                        table.remove(rope.attachedTrees, i)
                    end
                end
            end
            local ok, err = pcall(superFunc, self, xmlFile, key, usedModNames)
            for k = #parked, 1, -1 do
                table.insert(parked[k][1].attachedTrees, parked[k][2], parked[k][3])
            end
            if not ok then
                error(err, 0)
            end
        end)
    end
    if addConsoleCommand ~= nil then
        addConsoleCommand("wtProbe", "WinchTow: the attacher joints near where you look and their distance from the view ray", "consoleProbe", WinchTow)
    end
    say("loaded: in attach mode the winch rope can pick the attacher joints of other vehicles (ring and prompt as for a tree)")
end

function WinchTow.consoleProbe()
    return WinchTow.probe()
end
