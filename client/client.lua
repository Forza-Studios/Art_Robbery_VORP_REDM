--[[
    Previous carryable-statue logic (disabled).

local statue = nil
local carried = nil
local pickupPrompt = nil
local putDownPrompt = nil
local pickupText = nil
local putDownText = nil
local nextPromptTime = 0

local pickupGroup = GetRandomIntInRange(0, 0xffffff)
local putDownGroup = GetRandomIntInRange(0, 0xffffff)

local function LoadAnim(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(0)
    end
end

local function LoadModel(model)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
end

local function RegisterPrompts()
    pickupText = CreateVarString(10, "LITERAL_STRING", Config.PickupLabel)
    pickupPrompt = PromptRegisterBegin()
    PromptSetControlAction(pickupPrompt, Config.PromptControl)
    PromptSetText(pickupPrompt, pickupText)
    PromptSetVisible(pickupPrompt, 1)
    PromptSetStandardMode(pickupPrompt, 1)
    PromptSetHoldMode(pickupPrompt, 1)
    PromptSetGroup(pickupPrompt, pickupGroup)
    PromptRegisterEnd(pickupPrompt)

    putDownText = CreateVarString(10, "LITERAL_STRING", Config.PutDownLabel)
    putDownPrompt = PromptRegisterBegin()
    PromptSetControlAction(putDownPrompt, Config.PromptControl)
    PromptSetText(putDownPrompt, putDownText)
    PromptSetVisible(putDownPrompt, 1)
    PromptSetStandardMode(putDownPrompt, 1)
    PromptSetHoldMode(putDownPrompt, 1)
    PromptSetGroup(putDownPrompt, putDownGroup)
    PromptRegisterEnd(putDownPrompt)
end

local function SpawnStatue()
    if statue and DoesEntityExist(statue) then
        return
    end

    local model = Config.Statue.model
    local coords = Config.Statue.coords

    LoadModel(model)
    statue = CreateObject(GetHashKey(model), coords.x, coords.y, coords.z, false, true, false)

    if not statue or statue == 0 then
        return
    end

    SetEntityAsMissionEntity(statue, true, true)
    SetEntityHeading(statue, coords.h)
    FreezeEntityPosition(statue, true)
    SetEntityDynamic(statue, false)
    SetEntityCollision(statue, true, true)
end

local function PickUp()
    if not statue or not DoesEntityExist(statue) then
        return
    end

    local ped = PlayerPedId()
    local model = GetEntityModel(statue)

    LoadAnim(Config.PickupAnim.dict)
    TaskPlayAnim(ped, Config.PickupAnim.dict, Config.PickupAnim.name, 1.0, 8.0, 1.0, 25, 0, false, false, false)
    Wait(2000)

    local coords = GetEntityCoords(ped)
    carried = CreateObject(model, coords.x, coords.y, coords.z, false, true, false)

    if not carried or carried == 0 then
        return
    end

    SetEntityAsMissionEntity(carried, true, true)
    SetEntityVisible(carried, true)
    AttachEntityToEntity(
        carried,
        ped,
        GetPedBoneIndex(ped, Config.CarryBone),
        Config.CarryOffset.x,
        Config.CarryOffset.y,
        Config.CarryOffset.z,
        Config.CarryOffset.xRot,
        Config.CarryOffset.yRot,
        Config.CarryOffset.zRot,
        true,
        true,
        false,
        true,
        1,
        true
    )

    DeleteEntity(statue)
    statue = nil

    LoadAnim(Config.CarryAnim.dict)
    TaskPlayAnim(ped, Config.CarryAnim.dict, Config.CarryAnim.name, 1.0, 8.0, -1, 25, 0, false, false, false)
end

local function PutDown()
    if not carried or not DoesEntityExist(carried) then
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local rad = math.rad(heading)

    DetachEntity(carried, true, true)

    SetEntityCoords(
        carried,
        coords.x + math.sin(rad) * 0.8,
        coords.y + math.cos(rad) * 0.8,
        coords.z,
        false,
        false,
        false,
        false
    )
    SetEntityHeading(carried, heading)
    FreezeEntityPosition(carried, true)
    SetEntityDynamic(carried, false)
    SetEntityCollision(carried, true, true)
    ClearPedTasks(ped)

    statue = carried
    carried = nil
end

CreateThread(function()
    RegisterPrompts()
    SpawnStatue()

    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        if carried and DoesEntityExist(carried) then
            sleep = 0
            PromptSetActiveGroupThisFrame(putDownGroup, putDownText)

            if GetGameTimer() >= nextPromptTime and PromptHasHoldModeCompleted(putDownPrompt) then
                PutDown()
                nextPromptTime = GetGameTimer() + 1000
            end
        else
            if not statue or not DoesEntityExist(statue) then
                SpawnStatue()
            end

            if statue and DoesEntityExist(statue) then
                local dist = #(coords - GetEntityCoords(statue))
                if dist <= Config.PickupDistance then
                    sleep = 0
                    PromptSetActiveGroupThisFrame(pickupGroup, pickupText)

                    if GetGameTimer() >= nextPromptTime and PromptHasHoldModeCompleted(pickupPrompt) then
                        PickUp()
                        nextPromptTime = GetGameTimer() + 1000
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    if statue and DoesEntityExist(statue) then
        DeleteEntity(statue)
    end

    if carried and DoesEntityExist(carried) then
        DeleteEntity(carried)
    end
end)
]]

-- local npc = nil
--
-- local SPAWN_DISTANCE = 100.0
-- local MAX_DRIFT = 5.0
--
-- local function LoadModel(model)
--     if not HasModelLoaded(model) then
--         RequestModel(model, false)
--         while not HasModelLoaded(model) do
--             Wait(0)
--         end
--     end
-- end
--
-- local function RemoveNpc()
--     if npc and DoesEntityExist(npc) then
--         DeleteEntity(npc)
--     end
--     npc = nil
-- end
--
-- --[[
--     Previous chair auto-detection experiment (disabled).
--
-- -- Finds the closest chair prop around the given coords.
-- local function FindChair(coords)
--     local best, bestDist = nil, (Config.Npc.chairSearchRadius or 3.0)
--
--     for _, name in ipairs(Config.Npc.chairModels) do
--         local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, bestDist, GetHashKey(name), false, false, false)
--
--         if obj and obj ~= 0 and DoesEntityExist(obj) then
--             local dist = #(GetEntityCoords(obj) - vector3(coords.x, coords.y, coords.z))
--             if dist <= bestDist then
--                 best, bestDist = obj, dist
--             end
--         end
--     end
--
--     return best
-- end
-- ]]
--
-- local function SpawnNpc()
--     if npc and DoesEntityExist(npc) then
--         return
--     end
--
--     local cfg = Config.Npc
--     local model = GetHashKey(cfg.model)
--     local z = cfg.coords.z + (cfg.zOffset or 0.0)
--
--     LoadModel(model)
--
--     local ped = CreatePed(model, cfg.coords.x, cfg.coords.y, z, cfg.coords.h, false, false, false, false)
--
--     if not ped or ped == 0 then
--         print("[coi_art_rob] CreatePed failed.")
--         return
--     end
--
--     npc = ped
--     repeat Wait(0) until DoesEntityExist(npc)
--
--     SetEntityAsMissionEntity(npc, true, true)
--     SetEntityVisible(npc, true)
--     SetRandomOutfitVariation(npc, true)
--     SetBlockingOfNonTemporaryEvents(npc, true)
--     SetPedKeepTask(npc, true)
--     SetPedCanBeTargetted(npc, false)
--     SetEntityInvincible(npc, true)
--     SetPedFleeAttributes(npc, 0, false)
--
--     -- Lock the ped before starting the scenario so she cannot fall through the
--     -- floor or slide off the chair, then force the permanent sitting scenario.
--     FreezeEntityPosition(npc, true)
--     TaskStartScenarioInPlaceHash(npc, GetHashKey(cfg.scenario), -1, true, 0, 0, false)
--
--     local coords = GetEntityCoords(npc)
--     print(("[coi_art_rob] NPC spawned at %.2f, %.2f, %.2f"):format(coords.x, coords.y, coords.z))
-- end
--
-- CreateThread(function()
--     local cfg = Config.Npc
--     local target = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z)
--
--     while true do
--         Wait(1000)
--
--         local playerCoords = GetEntityCoords(PlayerPedId())
--
--         if #(playerCoords - target) <= SPAWN_DISTANCE then
--             if not npc or not DoesEntityExist(npc) then
--                 SpawnNpc()
--             elseif #(GetEntityCoords(npc) - target) > MAX_DRIFT then
--                 RemoveNpc()
--                 SpawnNpc()
--             end
--         elseif npc and DoesEntityExist(npc) then
--             RemoveNpc()
--         end
--     end
-- end)
--
-- RegisterCommand("npcfind", function()
--     local cfg = Config.Npc
--
--     print(("[coi_art_rob] Config position: %.2f, %.2f, %.2f"):format(cfg.coords.x, cfg.coords.y, cfg.coords.z))
--
--     if not npc or not DoesEntityExist(npc) then
--         print("[coi_art_rob] NPC entity does not exist right now.")
--         return
--     end
--
--     local coords = GetEntityCoords(npc)
--     local playerCoords = GetEntityCoords(PlayerPedId())
--
--     print(("[coi_art_rob] NPC position: %.2f, %.2f, %.2f | distance: %.1f"):format(
--         coords.x,
--         coords.y,
--         coords.z,
--         #(playerCoords - coords)
--     ))
--
--     local heading = GetEntityHeading(npc)
--     local rad = math.rad(heading)
--
--     SetEntityCoords(
--         PlayerPedId(),
--         coords.x + math.sin(rad) * 1.5,
--         coords.y + math.cos(rad) * 1.5,
--         coords.z + 0.2,
--         false,
--         false,
--         false,
--         false
--     )
--     SetEntityHeading(PlayerPedId(), heading + 180.0)
-- end, false)
--
-- AddEventHandler("onResourceStop", function(resource)
--     if resource ~= GetCurrentResourceName() then
--         return
--     end
--
--     RemoveNpc()
-- end)
--

local npc = nil
local npcPoint = nil
local npcPointIsOurs = false

-- Proximity fallback is only used when Config.Npc.onlyWhilePlayerSeated = false.
local SPAWN_DISTANCE = 20.0
local REMOVE_DISTANCE = 35.0
local MAX_DRIFT = 5.0

local POINT_SCAN_RADIUS = 4.0
local POINT_SCAN_MAX = 10

local function LoadModel(model)
    if not HasModelLoaded(model) then
        RequestModel(model, false)
        while not HasModelLoaded(model) do
            Wait(0)
        end
    end
end

local function HashToString(hash)
    hash = tonumber(hash) or 0

    if hash < 0 then
        hash = hash + 4294967296
    end

    return string.format("0x%08X", hash)
end

-- Reads the scenario points around coords. Each entry is 8 bytes wide and the
-- point handle sits in the low 32 bits. The Lua wrapper does not expose the
-- output array, so the raw buffer is passed through InvokeNative.
local function GetScenarioPoints(coords, radius)
    local buffer = DataView.ArrayBuffer(256 * 4)

    Citizen.InvokeNative(0x345EC3B7EBDE1CB5, coords.x, coords.y, coords.z, radius, buffer:Buffer(), POINT_SCAN_MAX)

    local points = {}

    for i = 1, POINT_SCAN_MAX do
        local point = buffer:GetInt32(8 * i)

        if point ~= 0 then
            points[#points + 1] = point
        end
    end

    return points
end

-- True while the player is sitting on a chair near the configured chair.
-- Stock chairs use scenario points, so the player's active point is the most
-- reliable signal. The IsPedUsingAnyScenario fallback covers custom sit tasks.
local function IsPlayerSeatedNear(cfg)
    local player = PlayerPedId()
    local target = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    local playerCoords = GetEntityCoords(player)
    local distance = #(playerCoords - target)
    local radius = cfg.playerSitRadius or 4.0
    local minDistance = cfg.playerMinDistance or 0.8

    -- Too far away, or sitting on the NPC's own chair.
    if distance < minDistance or distance > radius then
        return false
    end

    local point = GetScenarioPointPedIsUsing(player, true)

    if point and point ~= 0 then
        local pointCoords = GetScenarioPointCoords(point, true)

        if #(pointCoords - target) <= radius then
            return true
        end
    end

    return IsPedUsingAnyScenario(player)
end

-- Stock chairs are normally shipped with a scenario point already baked into
-- the map. Reuse it when it exists instead of placing a second point.
local function FindBakedScenarioPoint(cfg)
    local accepted = {}

    for _, name in ipairs(cfg.bakedScenarios or { cfg.scenario }) do
        accepted[GetHashKey(name)] = true
    end

    local origin = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z + (cfg.zOffset or 0.0))
    local best, bestDistance = nil, (cfg.pointSearchRadius or 2.0)

    for _, point in ipairs(GetScenarioPoints(origin, POINT_SCAN_RADIUS)) do
        if accepted[GetScenarioPointType(point)] then
            local pointCoords = GetScenarioPointCoords(point, true)
            local distance = #(pointCoords - origin)

            if distance <= bestDistance then
                best, bestDistance = point, distance
            end
        end
    end

    return best
end

local function CreateChairScenarioPoint(cfg)
    local point = CreateScenarioPointHash(
        GetHashKey(cfg.scenario),
        cfg.coords.x,
        cfg.coords.y,
        cfg.coords.z + (cfg.zOffset or 0.0),
        cfg.coords.h,
        0,
        0,
        true
    )

    if point and point ~= 0 then
        SetScenarioPointActive(point, true)
    end

    return point
end

local function RemoveNpc()
    if npc and DoesEntityExist(npc) then
        DeleteEntity(npc)
    end
    npc = nil

    if npcPointIsOurs and npcPoint and DoesScenarioPointExist(npcPoint) then
        DeleteScenarioPoint(npcPoint)
    end

    npcPoint = nil
    npcPointIsOurs = false
end

local function SpawnNpc()
    if npc and DoesEntityExist(npc) then
        return
    end

    local cfg = Config.Npc
    local model = GetHashKey(cfg.model)

    -- Spawn behind the chair and let her walk onto the scenario point, exactly
    -- like a stock NPC, instead of dropping her inside the seat.
    local rad = math.rad(cfg.coords.h)
    local offset = cfg.spawnOffset or 1.2
    local spawnX = cfg.coords.x - math.sin(rad) * offset
    local spawnY = cfg.coords.y + math.cos(rad) * offset
    local spawnZ = cfg.coords.z + 0.2

    LoadModel(model)

    local ped = CreatePed(model, spawnX, spawnY, spawnZ, cfg.coords.h + 180.0, false, false, false, false)

    if not ped or ped == 0 then
        print("[coi_art_rob] CreatePed failed.")
        return
    end

    npc = ped
    repeat Wait(0) until DoesEntityExist(npc)

    SetEntityAsMissionEntity(npc, true, true)
    SetEntityVisible(npc, true)
    SetRandomOutfitVariation(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedKeepTask(npc, true)
    SetPedCanBeTargetted(npc, false)
    SetEntityInvincible(npc, true)
    SetPedFleeAttributes(npc, 0, false)

    local point = FindBakedScenarioPoint(cfg)

    if point then
        print(("[coi_art_rob] Using baked scenario point %s (%s)."):format(
            tostring(point),
            HashToString(GetScenarioPointType(point))
        ))
    else
        point = CreateChairScenarioPoint(cfg)
        npcPointIsOurs = point ~= nil and point ~= 0
        print("[coi_art_rob] No baked scenario point found, created one at the chair.")
    end

    if point and point ~= 0 then
        npcPoint = point
        TaskUseScenarioPoint(npc, point, "", -1.0, true, false, 0, false, -1.0, true)
    else
        -- Fallback if the scenario point API fails: old in-place scenario.
        FreezeEntityPosition(npc, true)
        TaskStartScenarioInPlaceHash(npc, GetHashKey(cfg.scenario), -1, true, 0, 0, false)
    end

    -- The scenario point plays the stock enter/sit animation. Freeze only
    -- after it had time to finish so she cannot slide off the chair.
    CreateThread(function()
        Wait(8000)

        if npc ~= ped or not DoesEntityExist(ped) then
            return
        end

        if GetScenarioPointTypePedIsUsing(ped) ~= 0 then
            FreezeEntityPosition(ped, true)
        else
            print("[coi_art_rob] NPC did not start the scenario. Run /npcstate and /npcscen at the chair.")
        end
    end)

    local coords = GetEntityCoords(ped)
    print(("[coi_art_rob] NPC spawned at %.2f, %.2f, %.2f"):format(coords.x, coords.y, coords.z))
end

CreateThread(function()
    local cfg = Config.Npc
    local target = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    local leaveAt = 0

    while true do
        Wait(1000)

        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = #(playerCoords - target)
        local shouldBePresent

        if cfg.onlyWhilePlayerSeated == false then
            -- Old proximity mode, kept as a fallback.
            if distance <= SPAWN_DISTANCE then
                shouldBePresent = true
            elseif distance > REMOVE_DISTANCE then
                shouldBePresent = false
            else
                shouldBePresent = npc ~= nil and DoesEntityExist(npc)
            end
        else
            -- New behaviour: only while the player is seated near the opposite chair.
            shouldBePresent = IsPlayerSeatedNear(cfg)
        end

        if shouldBePresent then
            leaveAt = 0

            if not npc or not DoesEntityExist(npc) then
                SpawnNpc()
            elseif #(GetEntityCoords(npc) - target) > MAX_DRIFT then
                RemoveNpc()
                SpawnNpc()
            end
        elseif npc and DoesEntityExist(npc) then
            if leaveAt == 0 then
                leaveAt = GetGameTimer() + (cfg.leaveDelay or 5000)
            elseif GetGameTimer() >= leaveAt then
                RemoveNpc()
                leaveAt = 0
            end
        end
    end
end)

RegisterCommand("npcscen", function()
    local cfg = Config.Npc
    local radius = cfg.pointScanRadius or 6.0
    local origin = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z + (cfg.zOffset or 0.0))
    local points = GetScenarioPoints(origin, radius)

    print(("[coi_art_rob] %d scenario point(s) within %.1fm of the chair:"):format(#points, radius))

    for _, point in ipairs(points) do
        local pointType = GetScenarioPointType(point)
        local pointCoords = GetScenarioPointCoords(point, true)

        print(("  point=%s type=%s dist=%.2f at %.2f, %.2f, %.2f"):format(
            tostring(point),
            HashToString(pointType),
            #(pointCoords - origin),
            pointCoords.x,
            pointCoords.y,
            pointCoords.z
        ))
    end
end, false)

RegisterCommand("npcstate", function()
    local cfg = Config.Npc
    local player = PlayerPedId()
    local target = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    local coords = GetEntityCoords(player)
    local point = GetScenarioPointPedIsUsing(player, true)

    print(("[coi_art_rob] player %.2f, %.2f, %.2f | dist %.2f"):format(
        coords.x,
        coords.y,
        coords.z,
        #(coords - target)
    ))

    print(("[coi_art_rob] anyScenario=%s point=%s type=%s seatedNear=%s"):format(
        tostring(IsPedUsingAnyScenario(player)),
        tostring(point),
        HashToString(GetScenarioPointTypePedIsUsing(player)),
        tostring(IsPlayerSeatedNear(cfg))
    ))
end, false)

RegisterCommand("npcfind", function()
    local cfg = Config.Npc

    print(("[coi_art_rob] Config position: %.2f, %.2f, %.2f"):format(cfg.coords.x, cfg.coords.y, cfg.coords.z))

    if not npc or not DoesEntityExist(npc) then
        print("[coi_art_rob] NPC is not spawned. Sit on the opposite chair first.")
        return
    end

    local coords = GetEntityCoords(npc)
    local playerCoords = GetEntityCoords(PlayerPedId())

    print(("[coi_art_rob] NPC position: %.2f, %.2f, %.2f | distance: %.1f"):format(
        coords.x,
        coords.y,
        coords.z,
        #(playerCoords - coords)
    ))

    print(("[coi_art_rob] Scenario point: %s | type in use: %s"):format(
        npcPoint and tostring(npcPoint) or "none",
        HashToString(GetScenarioPointTypePedIsUsing(npc))
    ))

    local heading = GetEntityHeading(npc)
    local rad = math.rad(heading)

    SetEntityCoords(
        PlayerPedId(),
        coords.x + math.sin(rad) * 1.5,
        coords.y + math.cos(rad) * 1.5,
        coords.z + 0.2,
        false,
        false,
        false,
        false
    )
    SetEntityHeading(PlayerPedId(), heading + 180.0)
end, false)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    RemoveNpc()
end)
