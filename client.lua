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
local heistPrompt

local function RegisterHeistPrompt()
    local str = CreateVarString(10, 'LITERAL_STRING', Config.Prompt.label)
    heistPrompt = PromptRegisterBegin()
    PromptSetControlAction(heistPrompt, Config.Prompt.control)
    PromptSetText(heistPrompt, str)
    PromptSetStandardMode(heistPrompt, 1) -- Press mode
    
    -- IMPORTANT: Allow prompt to trigger even if not looking at the NPC
    Citizen.InvokeNative(0x560E76D5E2E8E3CB, heistPrompt, true) -- _PROMPT_SET_ATTRIBUTE (Attribute 1: Can be triggered without targeting)
    
    PromptRegisterEnd(heistPrompt)
    PromptSetEnabled(heistPrompt, false)
    PromptSetVisible(heistPrompt, false)
end

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
    
    -- Allow players to interact with the NPC without having to aim/attack first
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- SET_RANDOM_OUTFIT_VARIATION (already called above but ensuring context)
    SetEntityAsMissionEntity(ped, true, true)
    
    -- Crucial: Make the ped interactive for HUD prompts
    Citizen.InvokeNative(0x06843DA7060A02BA, ped, true) -- _SET_PED_CAN_BE_INTERACTED_WITH
    Citizen.InvokeNative(0x50C37353987F1793, ped, true) -- _SET_PED_CAN_BE_TARGETED_BY_PLAYER

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
        local path = data.path
        local spawnCoords = path[1]

        while true do
            local ped = spawnPed(model, spawnCoords)
            activePeds[locationName] = ped

            local state = 'idle'        -- idle | wander | talk | handsup | flee | returning | patrol
            local stateUntil = 0
            local nextIdleChange = GetGameTimer() + math.random(Config.WanderIntervalMin, Config.WanderIntervalMax)
            local lastChatter = 0
            local wanderPoint
            local currentPathIndex = 1

            startIdle(ped)

            while DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) do
                local now = GetGameTimer()
                local wait = 500
                local playerPed = PlayerPedId()
                local currentCoords = GetEntityCoords(ped)
                
                local targetNode = path[currentPathIndex]
                local targetPos = vector3(targetNode.x, targetNode.y, targetNode.z)

                local distToPlayer = #(GetEntityCoords(playerPed) - currentCoords)
                local aimed = distToPlayer < 20.0 and IsPlayerFreeAimingAtEntity(PlayerId(), ped)
                local shot = distToPlayer < 25.0 and IsPedShooting(playerPed)

                -- Prompt handling
                if distToPlayer < Config.Prompt.distance and state ~= 'handsup' and state ~= 'flee' then
                    wait = 0 -- Faster loop when close for responsive prompt
                    
                    PromptSetEnabled(heistPrompt, true)
                    PromptSetVisible(heistPrompt, true)
                    
                    -- Force the prompt to show up in a global group if entity targeting is failing
                    local group = PromptGetGroupIdForTargetEntity(ped)
                    if group and group ~= 0 then
                        PromptSetGroup(heistPrompt, group)
                        Citizen.InvokeNative(0xC5FBA0830A658144, group, CreateVarString(10, 'LITERAL_STRING', data.label or locationName))
                    end

                    if PromptHasStandardModeCompleted(heistPrompt) then
                        TriggerEvent('coi_art_rob:client:startHeist', locationName)
                        if Config.Debug then
                            print(('[coi_art_rob] Art Heist started at %s'):format(locationName))
                        end
                        Wait(1000) -- Prevent double trigger
                    end
                else
                    -- Hide prompt when out of range or in wrong state
                    if heistPrompt then
                        PromptSetEnabled(heistPrompt, false)
                        PromptSetVisible(heistPrompt, false)
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
                        walkTo(ped, targetPos, targetNode.w)
                    end
                elseif state == 'returning' then
                    wait = 250
                    if #(currentCoords - targetPos) < 1.0 then
                        state = 'idle'
                        stateUntil = now + math.random(Config.PathNodeWaitMin, Config.PathNodeWaitMax)
                        startIdle(ped)
                    end
                elseif distToPlayer < TALK_DISTANCE then
                    wait = 100
                    if state ~= 'talk' then
                        state = 'talk'
                        ClearPedTasks(ped)
                        TaskTurnPedToFaceEntity(ped, playerPed, 2000)
                        TaskLookAtEntity(ped, playerPed, -1, 2048, 3, 0)
                    end
                elseif state == 'talk' then
                    if distToPlayer > FORGET_DISTANCE then
                        say(ped, 'GENERIC_GOODBYE')
                        TaskClearLookAt(ped)
                        state = 'returning'
                        walkTo(ped, targetPos, targetNode.w)
                    end
                else
                    if distToPlayer < NOTICE_DISTANCE then
                        TaskLookAtEntity(ped, playerPed, 3000, 2048, 3, 0)
                    end

                    if state == 'wander' and now > stateUntil then
                        state = 'returning'
                        wanderPoint = nil
                        walkTo(ped, targetPos, targetNode.w)
                    elseif state == 'wander' and wanderPoint and #(GetEntityCoords(ped) - wanderPoint) < 1.0 then
                        startIdle(ped)
                        wanderPoint = nil
                    elseif state == 'idle' then
                        -- Handle transitions from idle: either wander or move to next path node
                        if now > stateUntil then
                            if #path > 1 then
                                -- Move to next node in path
                                currentPathIndex = currentPathIndex + 1
                                if currentPathIndex > #path then currentPathIndex = 1 end
                                
                                local nextNode = path[currentPathIndex]
                                state = 'patrol'
                                walkTo(ped, vector3(nextNode.x, nextNode.y, nextNode.z), nextNode.w)
                            elseif now > nextIdleChange then
                                -- Single point: maybe wander
                                nextIdleChange = now + math.random(Config.WanderIntervalMin, Config.WanderIntervalMax)
                                if math.random() < Config.WanderChance then
                                    local a = math.random() * 2.0 * math.pi
                                    local r = math.random(100, math.floor(WANDER_RADIUS * 100)) / 100
                                    wanderPoint = vector3(targetPos.x + math.cos(a) * r, targetPos.y + math.sin(a) * r, targetPos.z)
                                    state, stateUntil = 'wander', now + Config.WanderDuration
                                    walkTo(ped, wanderPoint)
                                else
                                    startIdle(ped)
                                end
                            end
                        end
                    elseif state == 'patrol' then
                        -- Check if we reached the patrol node
                        if #(currentCoords - targetPos) < 1.0 then
                            state = 'idle'
                            stateUntil = now + math.random(Config.PathNodeWaitMin, Config.PathNodeWaitMax)
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
    RegisterHeistPrompt()
    for name, data in pairs(Config.Locations) do
        -- Create blip if sprite is defined (using first point in path)
        if data.sprite then
            local firstPoint = data.path[1]
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, firstPoint.x, firstPoint.y, firstPoint.z, Citizen.ResultAsInteger())
            
            if blip and blip ~= 0 then
                SetBlipSprite(blip, data.sprite, true)
                SetBlipScale(blip, 1.0)
                local varString = VarString(10, 'LITERAL_STRING', data.label or name)
                Citizen.InvokeNative(0x9CB1A1623062F402, blip, varString)
                activeBlips[name] = blip
            end
        end

        if not IsModelValid(data.model) then
            print(string.format('^1[coi_art_rob] invalid ped model for %s^7', name))
        else
            runPedLogic(name, data)
        end
    end
end)

RegisterNetEvent('coi_art_rob:client:startHeist', function(location)
    -- Placeholder for the heist logic
    print('^2[coi_art_rob] Heist started at ' .. location .. '^7')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, ped in pairs(activePeds) do
        deletePed(ped)
    end
    for _, blip in pairs(activeBlips) do
        if blip and type(blip) == 'number' and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    if heistPrompt then
        PromptDelete(heistPrompt)
    end
end)
