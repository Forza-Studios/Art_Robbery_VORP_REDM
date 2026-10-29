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

local npc = nil

local SPAWN_DISTANCE = 100.0
local MAX_DRIFT = 5.0

local function LoadModel(model)
    if not HasModelLoaded(model) then
        RequestModel(model, false)
        while not HasModelLoaded(model) do
            Wait(0)
        end
    end
end

local function RemoveNpc()
    if npc and DoesEntityExist(npc) then
        DeleteEntity(npc)
    end
    npc = nil
end

--[[
    Previous chair auto-detection experiment (disabled).

-- Finds the closest chair prop around the given coords.
local function FindChair(coords)
    local best, bestDist = nil, (Config.Npc.chairSearchRadius or 3.0)

    for _, name in ipairs(Config.Npc.chairModels) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, bestDist, GetHashKey(name), false, false, false)

        if obj and obj ~= 0 and DoesEntityExist(obj) then
            local dist = #(GetEntityCoords(obj) - vector3(coords.x, coords.y, coords.z))
            if dist <= bestDist then
                best, bestDist = obj, dist
            end
        end
    end

    return best
end
]]

local function SpawnNpc()
    if npc and DoesEntityExist(npc) then
        return
    end

    local cfg = Config.Npc
    local model = GetHashKey(cfg.model)
    local z = cfg.coords.z + (cfg.zOffset or 0.0)

    LoadModel(model)

    local ped = CreatePed(model, cfg.coords.x, cfg.coords.y, z, cfg.coords.h, false, false, false, false)

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

    -- Lock the ped before starting the scenario so she cannot fall through the
    -- floor or slide off the chair, then force the permanent sitting scenario.
    FreezeEntityPosition(npc, true)
    TaskStartScenarioInPlaceHash(npc, GetHashKey(cfg.scenario), -1, true, 0, 0, false)

    local coords = GetEntityCoords(npc)
    print(("[coi_art_rob] NPC spawned at %.2f, %.2f, %.2f"):format(coords.x, coords.y, coords.z))
end

CreateThread(function()
    local cfg = Config.Npc
    local target = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z)

    while true do
        Wait(1000)

        local playerCoords = GetEntityCoords(PlayerPedId())

        if #(playerCoords - target) <= SPAWN_DISTANCE then
            if not npc or not DoesEntityExist(npc) then
                SpawnNpc()
            elseif #(GetEntityCoords(npc) - target) > MAX_DRIFT then
                RemoveNpc()
                SpawnNpc()
            end
        elseif npc and DoesEntityExist(npc) then
            RemoveNpc()
        end
    end
end)

RegisterCommand("npcfind", function()
    local cfg = Config.Npc

    print(("[coi_art_rob] Config position: %.2f, %.2f, %.2f"):format(cfg.coords.x, cfg.coords.y, cfg.coords.z))

    if not npc or not DoesEntityExist(npc) then
        print("[coi_art_rob] NPC entity does not exist right now.")
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
