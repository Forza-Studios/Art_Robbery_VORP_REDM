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

local activePeds = {}
local activeBlips = {}

-- PLAY_PED_AMBIENT_SPEECH_NATIVE takes a struct buffer on this build (same approach as coi_gunstore).
local SPEECH_PARAM_DEFAULT = 291934926

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

local function spawnPed(model, coords)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    local ped = CreatePed(model, coords.x, coords.y, coords.z, coords.w, false, false, false, false)

    -- RedM peds are invisible until an outfit is applied
    SetRandomOutfitVariation(ped, true)
    SetEntityAsMissionEntity(ped, true, true)

    -- the script drives the reactions, so native auto-reactions stay off
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, true)
    SetEntityInvincible(ped, Config.Invincible)

    SetModelAsNoLongerNeeded(model)
    return ped
end

local function deletePed(ped)
    if ped and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeletePed(ped)
    end
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

local function runPedLogic(locationName, data)
    CreateThread(function()
        local model = data.model
        local coords = data.coords
        local post = vector3(coords.x, coords.y, coords.z)

        while true do
            local ped = spawnPed(model, coords)
            activePeds[locationName] = ped

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
                
                local dist = #(GetEntityCoords(playerPed) - currentCoords)
                local aimed = dist < 20.0 and IsPlayerFreeAimingAtEntity(PlayerId(), ped)
                local shot = dist < 25.0 and IsPedShooting(playerPed)

                -- Always check if the NPC has been moved/pushed away from its post
                if state ~= 'flee' and state ~= 'handsup' and state ~= 'wander' and state ~= 'returning' then
                    if #(currentCoords - post) > Config.ReturnThreshold then
                        state = 'returning'
                        walkTo(ped, post, coords.w)
                    end
                end

                -- Keep the NPC chatting even when no player is nearby.
                if now - lastChatter >= CHATTER_INTERVAL and state ~= 'handsup' and state ~= 'flee' then
                    lastChatter = now
                    speakRandomLine(ped)
                end

                if aimed and state ~= 'handsup' then
                    state, stateUntil = 'handsup', now + 6000
                    ClearPedTasks(ped)
                    TaskHandsUp(ped, 6000, playerPed, 0, false)
                    say(ped, 'SCARED_COMMUNICATE')
                elseif shot and state ~= 'flee' and state ~= 'handsup' then
                    state, stateUntil = 'flee', now + 12000
                    ClearPedTasks(ped)
                    TaskSmartFleePed(ped, playerPed, 100.0, 12000, false, false)
                    say(ped, 'SCARED_COMMUNICATE')
                elseif state == 'handsup' or state == 'flee' then
                    wait = 250
                    if now > stateUntil and not aimed then
                        state = 'returning'
                        walkTo(ped, post, coords.w)
                    end
                elseif state == 'returning' then
                    wait = 250
                    if #(GetEntityCoords(ped) - post) < 1.0 then
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
                        walkTo(ped, post, coords.w)
                    end
                else
                    if dist < NOTICE_DISTANCE then
                        TaskLookAtEntity(ped, playerPed, 3000, 2048, 3, 0)
                    end

                    if state == 'wander' and now > stateUntil then
                        state = 'returning'
                        wanderPoint = nil
                        walkTo(ped, post, coords.w)
                    elseif state == 'wander' and wanderPoint and #(GetEntityCoords(ped) - wanderPoint) < 1.0 then
                        startIdle(ped)
                        wanderPoint = nil
                    elseif state == 'idle' and now > nextIdleChange then
                        nextIdleChange = now + math.random(Config.WanderIntervalMin, Config.WanderIntervalMax)
                        if math.random() < Config.WanderChance then
                            local a = math.random() * 2.0 * math.pi
                            local r = math.random(100, math.floor(WANDER_RADIUS * 100)) / 100
                            wanderPoint = vector3(post.x + math.cos(a) * r, post.y + math.sin(a) * r, post.z)
                            state, stateUntil = 'wander', now + Config.WanderDuration
                            walkTo(ped, wanderPoint)
                        else
                            startIdle(ped)
                        end
                    end
                end

                Wait(wait)
            end

            local resource = GetCurrentResourceName()
            Wait(RESPAWN_DELAY)
            if GetResourceState(resource) ~= 'started' then return end
            deletePed(ped)
            activePeds[locationName] = nil
        end
    end)
end

CreateThread(function()
    for name, data in pairs(Config.Locations) do
        -- Create blip if sprite is defined
        if data.sprite then
            local blip = Citizen.InvokeNative(0x554D5D790A110452, data.sprite, data.coords.x, data.coords.y, data.coords.z)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, name) -- Set blip name
            activeBlips[name] = blip
        end

        if not IsModelValid(data.model) then
            print(string.format('^1[coi_art_rob] invalid ped model for %s^7', name))
        else
            runPedLogic(name, data)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, ped in pairs(activePeds) do
        deletePed(ped)
    end
    for _, blip in pairs(activeBlips) do
        RemoveBlip(blip)
    end
end)
