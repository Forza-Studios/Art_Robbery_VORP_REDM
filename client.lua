local PED_MODEL = Config.PedModel
local PED_COORDS = Config.PedCoords
local POST = vector3(PED_COORDS.x, PED_COORDS.y, PED_COORDS.z)

local NOTICE_DISTANCE = 10.0
local TALK_DISTANCE = 3.0
local FORGET_DISTANCE = 6.0
local WANDER_RADIUS = 3.0
local CHATTER_INTERVAL = 20000
local RESPAWN_DELAY = 60000

local SCENARIOS = {
    'WORLD_HUMAN_STAND_WAITING',
    'WORLD_HUMAN_STAND_IMPATIENT',
    'WORLD_HUMAN_SMOKE',
    'WORLD_HUMAN_WRITE_NOTEBOOK',
}

local LINES = {
    'Evenin\', stranger. Keep your voice down - the walls have ears around here.',
    'You\'re new. Folks say the big paintings in town are worth more than the people who own them...',
    'Not many come this way after dark. Looking for something in particular?',
}

local shopPed

local function say(ped, speech)
    PlayPedAmbientSpeechNative(ped, speech, 'SPEECH_PARAMS_FORCE_NORMAL')
end

local function spawnPed()
    RequestModel(PED_MODEL)
    while not HasModelLoaded(PED_MODEL) do
        Wait(0)
    end

    local ped = CreatePed(PED_MODEL, PED_COORDS.x, PED_COORDS.y, PED_COORDS.z, PED_COORDS.w, false, false, false, false)

    -- RedM peds are invisible until an outfit is applied
    SetRandomOutfitVariation(ped, true)
    SetEntityAsMissionEntity(ped, true, true)

    -- the script drives the reactions, so native auto-reactions stay off
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, true)

    SetModelAsNoLongerNeeded(PED_MODEL)
    return ped
end

local function deletePed()
    if shopPed and DoesEntityExist(shopPed) then
        SetEntityAsMissionEntity(shopPed, true, true)
        DeletePed(shopPed)
    end
    shopPed = nil
end

local function startIdle(ped)
    ClearPedTasks(ped)
    TaskStartScenarioInPlace(ped, GetHashKey(SCENARIOS[math.random(#SCENARIOS)]), -1, true, false, false, false)
end

local function walkTo(ped, coords, heading)
    ClearPedTasks(ped)
    TaskGoStraightToCoord(ped, coords.x, coords.y, coords.z, 1.0, 10000, heading or 0.0, 0.5)
end

CreateThread(function()
    if not IsModelValid(PED_MODEL) then
        print('^1[coi_art_rob] invalid ped model^7')
        return
    end

    while true do
        shopPed = spawnPed()
        local ped = shopPed

        local state = 'idle'        -- idle | wander | talk | handsup | flee | returning
        local stateUntil = 0
        local nextIdleChange = GetGameTimer() + math.random(20000, 40000)
        local lastChatter = 0

        startIdle(ped)

        while DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) do
            local now = GetGameTimer()
            local wait = 500
            local playerPed = PlayerPedId()
            local dist = #(GetEntityCoords(playerPed) - GetEntityCoords(ped))
            local aimed = dist < 20.0 and IsPlayerFreeAimingAtEntity(PlayerId(), ped)
            local shot = dist < 25.0 and IsPedShooting(playerPed)

            if aimed and state ~= 'handsup' then
                -- held at gunpoint
                state, stateUntil = 'handsup', now + 6000
                ClearPedTasks(ped)
                TaskHandsUp(ped, 6000, playerPed, 0, false)
                say(ped, 'GUN_BEG')
            elseif shot and state ~= 'flee' and state ~= 'handsup' then
                -- gunfire nearby
                state, stateUntil = 'flee', now + 12000
                ClearPedTasks(ped)
                TaskSmartFleePed(ped, playerPed, 100.0, 12000, false, false)
                say(ped, 'SCARED')
            elseif state == 'handsup' or state == 'flee' then
                wait = 250
                if now > stateUntil and not aimed then
                    state = 'returning'
                    walkTo(ped, POST, PED_COORDS.w)
                end
            elseif state == 'returning' then
                wait = 250
                if #(GetEntityCoords(ped) - POST) < 1.0 then
                    state = 'idle'
                    startIdle(ped)
                end
            elseif dist < TALK_DISTANCE then
                wait = 100
                if state ~= 'talk' then
                    state = 'talk'
                    lastChatter = now
                    ClearPedTasks(ped)
                    TaskTurnPedToFaceEntity(ped, playerPed, 2000)
                    TaskLookAtEntity(ped, playerPed, -1, 2048, 3, 0)
                    say(ped, 'GREET')
                    TriggerEvent('vorp:TipRight', LINES[math.random(#LINES)], 6000)
                elseif now - lastChatter > CHATTER_INTERVAL then
                    lastChatter = now
                    say(ped, 'GENERIC_WHATEVER')
                    TriggerEvent('vorp:TipRight', LINES[math.random(#LINES)], 6000)
                end
            elseif state == 'talk' then
                if dist > FORGET_DISTANCE then
                    say(ped, 'GOODBYE')
                    TaskClearLookAt(ped)
                    state = 'returning'
                    walkTo(ped, POST, PED_COORDS.w)
                end
            else
                -- idle life: glance at passers-by, change activity now and then
                if dist < NOTICE_DISTANCE then
                    TaskLookAtEntity(ped, playerPed, 3000, 2048, 3, 0)
                end

                if state == 'wander' and now > stateUntil then
                    state = 'returning'
                    walkTo(ped, POST, PED_COORDS.w)
                elseif state == 'idle' and now > nextIdleChange then
                    nextIdleChange = now + math.random(20000, 40000)
                    if math.random() < 0.4 then
                        local a = math.random() * 2.0 * math.pi
                        local r = math.random() * WANDER_RADIUS
                        state, stateUntil = 'wander', now + 10000
                        walkTo(ped, vector3(POST.x + math.cos(a) * r, POST.y + math.sin(a) * r, POST.z))
                    else
                        startIdle(ped)
                    end
                end
            end

            Wait(wait)
        end

        -- killed (or lost): clean up and bring a fresh one back later
        local resource = GetCurrentResourceName()
        Wait(RESPAWN_DELAY)
        if GetResourceState(resource) ~= 'started' then return end
        deletePed()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    deletePed()
end)
