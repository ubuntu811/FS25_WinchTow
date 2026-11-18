--[[
    WinchCable.lua -- the wires of WinchWire get collision once they have been still for a while: a person can stand on one and walk it (collision group STATIC_OBJECT, mask PLAYER only: it never touches the vehicles it is tied to).
    The collision is built from assets/cableSegment.i3d (tools/make_cable_segment.py): one kinematic root box and one compound child box per metre, placed along the wire and added to physics as ONE body. A wire whose ends move
    (reeling, a piece pushed) loses its collision at once; it is built again when both ends have been still STILL_MS. The wires are not saved yet (WinchWire.wires), so neither is the collision.
]]
WinchCable = {}
WinchCable.ENABLED = true
WinchCable.SEG_M = 4.0             -- the box of the asset is this long (the engine cannot stretch a collision shape: a long cable is a row of them, 17 for 68 m)
WinchCable.MIN_M = 0.5             -- shorter wires have none
WinchCable.CHUNK = 32             -- the engine's compound body takes at most 40 children ("Failed to create compound ... Maximum is 40"): a long cable is several bodies of at most this many boxes
WinchCable.STILL_MS = 1000
WinchCable.MOVE_M = 0.01           -- an end that moved more than this starts the waiting again
WinchCable.dir = g_currentModDirectory
WinchCable.template = nil          -- { node, root, child }: the loaded asset, never in the scene

local function say(format, ...)
    Logging.info("[WinchCable] " .. format, ...)
end

local function loadTemplate()
    local t = WinchCable.template
    if t ~= nil and entityExists(t.root) and entityExists(t.child) then
        return t
    end
    if g_i3DManager == nil or WinchCable.dir == nil then
        return nil
    end
    local ok, node = pcall(g_i3DManager.loadI3DFile, g_i3DManager, WinchCable.dir .. "assets/cableSegment.i3d", false, false)
    if not ok or node == nil or node == 0 then
        say("the asset could not be loaded: %s", tostring(node))
        WinchCable.ENABLED = false
        return nil
    end
    local group = getChildAt(node, 0)
    local root, child = getChild(group, "cableRoot"), getChild(group, "cableChild")
    if root == nil or root == 0 or child == nil or child == 0 then
        say("the asset has no cableRoot / cableChild")
        WinchCable.ENABLED = false
        return nil
    end
    WinchCable.template = { node = node, root = root, child = child }
    return WinchCable.template
end

local function place(node, x, y, z, dx, dy, dz)
    local ux, uy, uz = 0, 1, 0
    if math.abs(dy) > 0.99 then
        ux, uy, uz = 1, 0, 0
    end
    setWorldTranslation(node, x, y, z)
    setWorldDirection(node, dx, dy, dz, ux, uy, uz)
end

-- The collision between two points: returns a list of root nodes (one body per CHUNK boxes), or nil.
function WinchCable.build(ax, ay, az, bx, by, bz)
    local t = loadTemplate()
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if t == nil or length < WinchCable.MIN_M then
        return nil
    end
    dx, dy, dz = dx / length, dy / length, dz / length
    local n = math.max(1, math.ceil(length / WinchCable.SEG_M))
    local step = length / n
    local roots = {}
    local ok, err = pcall(function()
        local first = 1
        while first <= n do
            local last = math.min(n, first + WinchCable.CHUNK - 1)
            local s0 = (first - 0.5) * step
            local r = clone(t.root, true)
            place(r, ax + dx * s0, ay + dy * s0, az + dz * s0, dx, dy, dz)
            for i = first + 1, last do
                local c = clone(t.child, true)
                link(r, c)
                local s1 = (i - 0.5) * step
                place(c, ax + dx * s1, ay + dy * s1, az + dz * s1, dx, dy, dz)
            end
            link(getRootNode(), r)
            addToPhysics(r)
            roots[#roots + 1] = r
            first = last + 1
        end
    end)
    if not ok then
        say("the cable could not be built: %s", tostring(err))
        for _, r in ipairs(roots) do
            if entityExists(r) then pcall(removeFromPhysics, r); delete(r) end
        end
        return nil
    end
    say("cable built: %d box(es) in %d body(ies), %.1f m", n, #roots, length)
    return roots, n
end

function WinchCable.destroy(roots)
    for _, root in ipairs(roots or {}) do
        if root ~= nil and entityExists(root) then
            pcall(removeFromPhysics, root)
            delete(root)
        end
    end
end

-- A wire, every frame it is reeled/watched: ends a (hitch) and b (eye). Cheap while nothing moves: six numbers compared.
function WinchCable.update(wire, dt, ax, ay, az, bx, by, bz)
    if not WinchCable.ENABLED then
        return
    end
    local s = wire.cable
    if s == nil then
        s = { ax = ax, ay = ay, az = az, bx = bx, by = by, bz = bz, still = 0 }
        wire.cable = s
    end
    local m = WinchCable.MOVE_M
    if math.abs(ax - s.ax) > m or math.abs(ay - s.ay) > m or math.abs(az - s.az) > m or math.abs(bx - s.bx) > m or math.abs(by - s.by) > m or math.abs(bz - s.bz) > m then
        if s.roots ~= nil then
            WinchCable.destroy(s.roots)
            s.roots = nil
            say("cable removed: an end moved")
        end
        s.ax, s.ay, s.az, s.bx, s.by, s.bz, s.still = ax, ay, az, bx, by, bz, 0
        return
    end
    s.still = s.still + (dt or 0)
    if s.roots == nil and s.still >= WinchCable.STILL_MS and not s.failed then
        s.roots = WinchCable.build(ax, ay, az, bx, by, bz)
        s.failed = s.roots == nil                    -- (once: a wire that cannot be built is not tried again every frame; it moves, or it is laid again)
    end
end

-- The wire is gone.
function WinchCable.remove(wire)
    local s = wire.cable
    if s ~= nil and s.roots ~= nil then
        WinchCable.destroy(s.roots)
        say("cable removed: the wire is gone")
    end
    wire.cable = nil
end
