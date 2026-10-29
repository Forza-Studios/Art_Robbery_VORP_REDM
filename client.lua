local PED_MODEL = Config.PedModel
local PED_COORDS = Config.PedCoords
local POST = vector3(PED_COORDS.x, PED_COORDS.y, PED_COORDS.z)

local NOTICE_DISTANCE = Config.ChatterDistance
local TALK_DISTANCE = 3.0
local FORGET_DISTANCE = 6.0
local WANDER_RADIUS = Config.WanderRadius
local CHATTER_INTERVAL = Config.ChatterInterval
local RESPAWN_DELAY = 60000

local SCENARIOS = {
    'WORLD_HUMAN_STAND_WAITING',
    'WORLD_HUMAN_STAND_IMPATIENT',
    'WORLD_HUMAN_SMOKE',
    'WORLD_HUMAN_WRITE_NOTEBOOK',
}

local shopPed

-- PLAY_PED_AMBIENT_SPEECH_NATIVE takes a struct buffer on this build (same approach as coi_gunstore).
local SPEECH_PARAM_DEFAULT = 291934926

local function buildSpeechBuffer(name, bank, line)
    local ok, buf = pcall(function()
        return string.pack("<j j i4 x4 j i4 x4 i4 x4 i4 x4",
            VarString(10, 'LITERAL_STRING', name, Citizen.ResultAsLong()),
            VarString(10, 'LITERAL_STRING', bank, Citizen.ResultAsLong()),
            line,
            SPEECH_PARAM_DEFAULT,
            0,
            0,
            1)
    end)
    return ok and buf or nil
end

local function say(ped, speech)
    -- Same approach as Redm_Raiways_VORP/client/rob.lua: check the ped can say the line, then play it.
    local can = Citizen.InvokeNative(0x9D6DEC9791A4E501, ped, speech, 0, 1, Citizen.ResultAsInteger())
    if not can or can == 0 then
        return false
    end

    local ok, err = pcall(PlayPedAmbientSpeechNative, ped, speech, Config.SpeechParam)
    if Config.Debug then
        print(('[coi_art_rob] %s -> %s'):format(speech, ok and 'played' or tostring(err)))
    end
    return ok
end

local function speakRandomLine(ped)
    local lines = {}
    for index, line in ipairs(Config.VoiceLines) do
        lines[index] = line
    end

    for index = #lines, 2, -1 do
        local randomIndex = math.random(index)
        lines[index], lines[randomIndex] = lines[randomIndex], lines[index]
    end

    for _, line in ipairs(lines) do
        if say(ped, line) then
            return
        end
    end
end

local function spawnPed()
    RequestModel(PED_MODEL)
    while not HasModelLoaded(PED_MODEL) do
        Wait(0)
    end

    local ped = CreatePed(PED_MODEL, Config.PedCoords.x, Config.PedCoords.y, Config.PedCoords.z, Config.PedCoords.w, false, false, false, false)

    -- RedM peds are invisible until an outfit is applied
    SetRandomOutfitVariation(ped, true)
    SetEntityAsMissionEntity(ped, true, true)

    -- the script drives the reactions, so native auto-reactions stay off
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, true)
    SetEntityInvincible(ped, Config.Invincible)

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
    -- TaskFollowNavMeshToCoord enables proper pathfinding around obstacles like walls
    TaskFollowNavMeshToCoord(ped, coords.x, coords.y, coords.z, 1.0, -1, 0.5, true, heading or 0.0)
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
        local nextIdleChange = GetGameTimer() + math.random(Config.WanderIntervalMin, Config.WanderIntervalMax)
        local lastChatter = 0
        local wanderPoint

        startIdle(ped)

        while DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) do
            local now = GetGameTimer()
            local wait = 500
            local playerPed = PlayerPedId()
            local currentCoords = GetEntityCoords(ped)
            
            -- Use config values directly so changes take effect if the script is reloaded or if the user expects dynamic updates
            local postCoords = vector3(Config.PedCoords.x, Config.PedCoords.y, Config.PedCoords.z)
            
            local dist = #(GetEntityCoords(playerPed) - currentCoords)
            local aimed = dist < 20.0 and IsPlayerFreeAimingAtEntity(PlayerId(), ped)
            local shot = dist < 25.0 and IsPedShooting(playerPed)

            -- Always check if the NPC has been moved/pushed away from its post
            -- We ignore this if the NPC is currently wandering, fleeing, or reacting to a gun.
            if state ~= 'flee' and state ~= 'handsup' and state ~= 'wander' and state ~= 'returning' then
                if #(currentCoords - postCoords) > Config.ReturnThreshold then
                    state = 'returning'
                    walkTo(ped, postCoords, Config.PedCoords.w)
                end
            end

            -- Keep the NPC chatting even when no player is nearby.
            if now - lastChatter >= CHATTER_INTERVAL and state ~= 'handsup' and state ~= 'flee' then
                lastChatter = now
                speakRandomLine(ped)
            end

            if aimed and state ~= 'handsup' then
                -- held at gunpoint
                state, stateUntil = 'handsup', now + 6000
                ClearPedTasks(ped)
                TaskHandsUp(ped, 6000, playerPed, 0, false)
                say(ped, 'SCARED_COMMUNICATE')
            elseif shot and state ~= 'flee' and state ~= 'handsup' then
                -- gunfire nearby
                state, stateUntil = 'flee', now + 12000
                ClearPedTasks(ped)
                TaskSmartFleePed(ped, playerPed, 100.0, 12000, false, false)
                say(ped, 'SCARED_COMMUNICATE')
            elseif state == 'handsup' or state == 'flee' then
                wait = 250
                if now > stateUntil and not aimed then
                    state = 'returning'
                    walkTo(ped, postCoords, Config.PedCoords.w)
                end
            elseif state == 'returning' then
                wait = 250
                if #(GetEntityCoords(ped) - postCoords) < 1.0 then
                    state = 'idle'
                    startIdle(ped)
                end
            elseif dist < TALK_DISTANCE then
                wait = 100
                if state ~= 'talk' then
                    state = 'talk'
                    ClearPedTasks(ped)
                    TaskTurnPedToFaceEntity(ped, playerPed, 2000)
                    TaskLookAtEntity(ped, playerPed, -1, 2048, 3, 0)
                end
            elseif state == 'talk' then
                if dist > FORGET_DISTANCE then
                    say(ped, 'GENERIC_GOODBYE')
                    TaskClearLookAt(ped)
                    state = 'returning'
                    walkTo(ped, postCoords, Config.PedCoords.w)
                end
            else
                -- idle life: glance at passers-by, change activity now and then
                if dist < NOTICE_DISTANCE then
                    TaskLookAtEntity(ped, playerPed, 3000, 2048, 3, 0)
                end

                if state == 'wander' and now > stateUntil then
                    state = 'returning'
                    wanderPoint = nil
                    walkTo(ped, postCoords, Config.PedCoords.w)
                elseif state == 'wander' and wanderPoint and #(GetEntityCoords(ped) - wanderPoint) < 1.0 then
                    -- The random point was reached: play an idle animation there
                    -- until it is time to return to the original spawn point.
                    startIdle(ped)
                    wanderPoint = nil
                elseif state == 'idle' and now > nextIdleChange then
                    nextIdleChange = now + math.random(Config.WanderIntervalMin, Config.WanderIntervalMax)
                    if math.random() < Config.WanderChance then
                        local a = math.random() * 2.0 * math.pi
                        local r = math.random(100, math.floor(WANDER_RADIUS * 100)) / 100
                        wanderPoint = vector3(postCoords.x + math.cos(a) * r, postCoords.y + math.sin(a) * r, postCoords.z)
                        state, stateUntil = 'wander', now + Config.WanderDuration
                        walkTo(ped, wanderPoint)
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
