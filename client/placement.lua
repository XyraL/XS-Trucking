Placement = { active = false }

local CONTROLS = {
    confirm = 191, cancel = 194,
    forward = 32, back = 33, left = 34, right = 35,
    up = 22, down = 36, fast = 21, slow = 19,
    turnLeft = 96, turnRight = 97,
    floor = 73,
}

local SPEED = { normal = 8.0, fast = 26.0, slow = 1.5 }
local RANGE = 80.0
local SHOW_WITHIN = 140.0
local MARGIN = 0.2
local POINT = { min = vector3(-0.6, -0.6, 0.0), max = vector3(0.6, 0.6, 1.0) }

local ghosts = {}
local session = 0
local camera

local function forward(cam)
    local rot = GetCamRot(cam, 2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function didHit(hit)
    return hit == true or hit == 1
end

local function aim(cam, ignore)
    local from = GetCamCoord(cam)
    local to = from + forward(cam) * RANGE

    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, ignore or 0, 4)
    local _, hit, coords = GetShapeTestResult(ray)
    local point = didHit(hit) and coords or to

    local wet, water = GetWaterHeightNoWaves(point.x, point.y, point.z + 50.0)
    if wet and water > point.z then point = vector3(point.x, point.y, water) end
    return point
end

local function floorUnder(point)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(point.x, point.y, point.z + 1.0, point.x, point.y, point.z - 10.0, 1 + 16, 0, 4)
    local _, hit, coords = GetShapeTestResult(ray)
    return didHit(hit) and coords.z or nil
end

local function makeGhost(model, alpha)
    if not model then return nil end

    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    if not pcall(lib.requestModel, hash, 10000) then return nil end

    local ghost
    if IsModelAVehicle(hash) then
        ghost = CreateVehicle(hash, 0.0, 0.0, 0.0, 0.0, false, false)
        SetVehicleDoorsLocked(ghost, 2)
    else
        ghost = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    end

    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(ghost, true, true)
    SetEntityAlpha(ghost, alpha, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityInvincible(ghost, true)
    return ghost
end

local function cleanup()
    for _, ghost in ipairs(ghosts) do
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
    end
    ghosts = {}
end

local function sizeOf(entity)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    if not min or not max or (max.y - min.y) < 0.2 then return nil end
    return { min = min, max = max }
end

local function footprint(point, size)
    local h = math.rad(point.h or 0.0)
    local right = { x = math.cos(h), y = math.sin(h) }
    local ahead = { x = -math.sin(h), y = math.cos(h) }
    local cx = (size.min.x + size.max.x) / 2
    local cy = (size.min.y + size.max.y) / 2

    return {
        x = point.x + right.x * cx + ahead.x * cy,
        y = point.y + right.y * cx + ahead.y * cy,
        z = point.z,
        axes = { right, ahead },
        half = { (size.max.x - size.min.x) / 2 + MARGIN, (size.max.y - size.min.y) / 2 + MARGIN },
    }
end

local function reach(rect, axis)
    local a, b = rect.axes[1], rect.axes[2]
    return rect.half[1] * math.abs(a.x * axis.x + a.y * axis.y) + rect.half[2] * math.abs(b.x * axis.x + b.y * axis.y)
end

local function overlaps(a, b)
    if math.abs(a.z - b.z) > 3.0 then return false end
    local dx, dy = b.x - a.x, b.y - a.y
    for _, rect in ipairs({ a, b }) do
        for _, axis in ipairs(rect.axes) do
            if math.abs(dx * axis.x + dy * axis.y) > reach(a, axis) + reach(b, axis) then return false end
        end
    end
    return true
end

local function outline(rect, r, g, b)
    local right, ahead = rect.axes[1], rect.axes[2]
    local w, l = rect.half[1], rect.half[2]
    local z = rect.z + 0.06
    local corners = {
        { rect.x + right.x * w + ahead.x * l, rect.y + right.y * w + ahead.y * l },
        { rect.x - right.x * w + ahead.x * l, rect.y - right.y * w + ahead.y * l },
        { rect.x - right.x * w - ahead.x * l, rect.y - right.y * w - ahead.y * l },
        { rect.x + right.x * w - ahead.x * l, rect.y + right.y * w - ahead.y * l },
    }
    for i = 1, 4 do
        local p, q = corners[i], corners[i % 4 + 1]
        DrawLine(p[1], p[2], z, q[1], q[2], z, r, g, b, 235)
    end
end

local function label(x, y, z, text, r, g, b)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(r, g, b, 240)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function prepareOthers(list, token)
    local out = {}

    for _, item in ipairs(type(list) == 'table' and list or {}) do
        local x, y, z = tonumber(item.x), tonumber(item.y), tonumber(item.z)
        if x and y and z then
            local point = { x = x, y = y, z = z, h = tonumber(item.h) or 0.0 }
            local model = type(item.model) == 'string' and item.model ~= '' and item.model or nil
            out[#out + 1] = {
                point = point,
                model = model,
                label = tostring(item.label or ''):upper(),
                rect = footprint(point, POINT),
                top = z + 1.4,
            }
        end
    end

    CreateThread(function()
        for _, other in ipairs(out) do
            if session ~= token then return end
            if other.model then
                local ghost = makeGhost(other.model, 100)
                if ghost then
                    if session ~= token then
                        DeleteEntity(ghost)
                        return
                    end
                    ghosts[#ghosts + 1] = ghost
                    SetEntityCoordsNoOffset(ghost, other.point.x, other.point.y, other.point.z + 0.05, false, false, false)
                    SetEntityHeading(ghost, other.point.h)
                    other.ghost = ghost
                    local size = sizeOf(ghost)
                    if size then
                        other.rect = footprint(other.point, size)
                        other.top = other.point.z + size.max.z + 0.5
                    end
                end
            end
        end
    end)

    return out
end

local function tint(ghost, red)
    if not ghost or not DoesEntityExist(ghost) or not IsEntityAVehicle(ghost) then return end
    if red then
        SetVehicleCustomPrimaryColour(ghost, 220, 38, 38)
        SetVehicleCustomSecondaryColour(ghost, 220, 38, 38)
    else
        ClearVehicleCustomPrimaryColour(ghost)
        ClearVehicleCustomSecondaryColour(ghost)
    end
end

function Placement.Start(options)
    if Placement.active then return nil end
    options = options or {}

    session = session + 1
    local token = session

    local ped = cache.ped
    local origin = options.origin
    local start = origin and vector3(origin.x, origin.y, origin.z) or GetEntityCoords(ped)
    local heading = origin and origin.h or GetEntityHeading(ped)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    camera = cam
    SetCamCoord(cam, start.x, start.y, start.z + 6.0)
    SetCamRot(cam, -35.0, 0.0, GetEntityHeading(ped), 2)
    SetCamFov(cam, 60.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 300, true, true)
    FreezeEntityPosition(ped, true)

    local ghost = makeGhost(options.preview, 170)
    if ghost then ghosts[#ghosts + 1] = ghost end

    local size = ghost and sizeOf(ghost) or POINT
    local others = prepareOthers(options.others, token)
    Placement.active = true

    lib.showTextUI(([[
**%s**
[Enter] Put it here
[WASD] Fly  ·  [Shift] fast  ·  [Alt] slow
[Space] / [Ctrl] Up and down
[Scroll] Turn
[X] Drop to the floor
[Backspace] Cancel
White outlines are your other points.
Red means it would hit one.]]):format(options.label or 'Placing a point'), { position = 'left-center' })

    local result
    local point = start
    local pinned = false
    local red = false
    local armed

    while Placement.active do
        Wait(0)

        DisableAllControlActions(0)
        EnableControlAction(0, CONTROLS.confirm, true)
        EnableControlAction(0, CONTROLS.cancel, true)

        local pos = GetCamCoord(cam)
        local rot = GetCamRot(cam, 2)
        SetCamRot(cam, math.max(-89.0, math.min(89.0, rot.x - GetDisabledControlNormal(0, 2) * 6.0)), 0.0,
            rot.z - GetDisabledControlNormal(0, 1) * 6.0, 2)

        local speed = SPEED.normal
        if IsDisabledControlPressed(0, CONTROLS.fast) then speed = SPEED.fast end
        if IsDisabledControlPressed(0, CONTROLS.slow) then speed = SPEED.slow end
        speed = speed * GetFrameTime()

        local fwd = forward(cam)
        local right = vector3(fwd.y, -fwd.x, 0.0)
        local move = vector3(0.0, 0.0, 0.0)

        if IsDisabledControlPressed(0, CONTROLS.forward) then move = move + fwd end
        if IsDisabledControlPressed(0, CONTROLS.back) then move = move - fwd end
        if IsDisabledControlPressed(0, CONTROLS.right) then move = move + right end
        if IsDisabledControlPressed(0, CONTROLS.left) then move = move - right end
        if IsDisabledControlPressed(0, CONTROLS.up) then move = move + vector3(0.0, 0.0, 1.0) end
        if IsDisabledControlPressed(0, CONTROLS.down) then move = move - vector3(0.0, 0.0, 1.0) end

        if #move > 0.0 then
            pos = pos + move * speed
            SetCamCoord(cam, pos.x, pos.y, pos.z)
            pinned = false
        end

        SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)

        if not pinned then point = aim(cam, ghost) end

        if IsDisabledControlJustPressed(0, CONTROLS.floor) then
            local floor = floorUnder(point)
            if floor then
                point = vector3(point.x, point.y, floor)
                pinned = true
            end
        end

        if IsDisabledControlPressed(0, CONTROLS.turnLeft) then heading = (heading + 2.0) % 360 end
        if IsDisabledControlPressed(0, CONTROLS.turnRight) then heading = (heading - 2.0) % 360 end

        if ghost and DoesEntityExist(ghost) then
            SetEntityCoordsNoOffset(ghost, point.x, point.y, point.z + 0.05, false, false, false)
            SetEntityHeading(ghost, heading)
        else
            DrawMarker(1, point.x, point.y, point.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                1.0, 1.0, 0.6, 56, 217, 255, 120, false, false, 2, false)
            local dir = vector3(-math.sin(math.rad(heading)), math.cos(math.rad(heading)), 0.0)
            DrawLine(point.x, point.y, point.z + 0.1, point.x + dir.x * 2.0, point.y + dir.y * 2.0, point.z + 0.1, 56, 217, 255, 230)
        end

        local here = footprint({ x = point.x, y = point.y, z = point.z, h = heading }, size)
        local clash

        for _, other in ipairs(others) do
            local hit = overlaps(here, other.rect)
            if hit and not clash then clash = other end

            local p = other.point
            if #(pos - vector3(p.x, p.y, p.z)) < SHOW_WITHIN then
                if hit then outline(other.rect, 255, 70, 70) else outline(other.rect, 235, 235, 235) end
                label(p.x, p.y, other.top, other.label, 255, hit and 110 or 255, hit and 110 or 255)
                if not other.ghost then
                    DrawMarker(1, p.x, p.y, p.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.8, 0.8, 0.5, 235, 235, 235, 90, false, false, 2, false)
                end
            end
        end

        if clash then outline(here, 255, 70, 70) else outline(here, 63, 224, 143) end

        if (clash ~= nil) ~= red then
            red = clash ~= nil
            tint(ghost, red)
        end

        if armed and (#(point - armed.point) > 0.05 or math.abs(heading - armed.heading) > 0.5) then armed = nil end

        if clash then
            local top = point.z + (size.max.z or 1.4) + 0.8
            label(point.x, point.y, top, armed and 'PRESS ENTER AGAIN TO PUT IT HERE ANYWAY' or ('TOO CLOSE TO ' .. clash.label), 255, 90, 90)
        end

        if IsDisabledControlJustPressed(0, CONTROLS.confirm) then
            if clash and not armed then
                armed = { point = point, heading = heading }
            else
                result = { x = point.x, y = point.y, z = point.z, h = heading }
                break
            end
        end

        if IsDisabledControlJustPressed(0, CONTROLS.cancel) then break end
    end

    session = session + 1
    cleanup()
    RenderScriptCams(false, true, 300, true, true)
    SetCamActive(cam, false)
    DestroyCam(cam, true)
    camera = nil
    ClearFocus()
    FreezeEntityPosition(ped, false)
    lib.hideTextUI()
    Placement.active = false

    return result
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not Placement.active then return end

    session = session + 1
    cleanup()
    RenderScriptCams(false, false, 0, true, true)
    if camera then DestroyCam(camera, true) end
    ClearFocus()
    FreezeEntityPosition(cache.ped, false)
    lib.hideTextUI()
end)
