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
