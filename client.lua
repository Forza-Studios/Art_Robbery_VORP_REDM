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
local heistProps = {}
local heistBlips = {}
local heistPrompt
local endHeistPrompt
local heistStarted = false
local promptTargets = {} -- locationName -> label, for NPCs currently in prompt range
local promptGroup = GetRandomIntInRange(0, 0xffffff)

local function RegisterHeistPrompts()
    -- Start Prompt
    local str = CreateVarString(10, 'LITERAL_STRING', Config.Prompt.label)
    heistPrompt = PromptRegisterBegin()
    PromptSetControlAction(heistPrompt, Config.Prompt.control)
    PromptSetText(heistPrompt, str)
    PromptSetStandardMode(heistPrompt, true)
    PromptSetGroup(heistPrompt, promptGroup)
    PromptRegisterEnd(heistPrompt)
    PromptSetEnabled(heistPrompt, false)
    PromptSetVisible(heistPrompt, false)

    -- End Prompt
    local strEnd = CreateVarString(10, 'LITERAL_STRING', Config.EndPrompt.label)
    endHeistPrompt = PromptRegisterBegin()
    PromptSetControlAction(endHeistPrompt, Config.EndPrompt.control)
    PromptSetText(endHeistPrompt, strEnd)
    PromptSetStandardMode(endHeistPrompt, true)
    PromptSetGroup(endHeistPrompt, promptGroup)
    PromptRegisterEnd(endHeistPrompt)
    PromptSetEnabled(endHeistPrompt, false)
    PromptSetVisible(endHeistPrompt, false)
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

                -- Prompt handling: the per-frame drawing lives in its own thread (see below),
                -- because this loop's wait changes with the NPC state and would make the prompt flicker.
                if distToPlayer < Config.Prompt.distance and state ~= 'handsup' and state ~= 'flee' then
                    promptTargets[locationName] = data.label or locationName
                else
                    promptTargets[locationName] = nil
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

            promptTargets[locationName] = nil
            local resource = GetCurrentResourceName()
            Wait(RESPAWN_DELAY)
            if GetResourceState(resource) ~= 'started' then return end
            deletePed(ped)
            activePeds[locationName] = nil
        end
    end)
end

CreateThread(function()
    RegisterHeistPrompts()
    while true do
        local locationName, label = next(promptTargets)
        if locationName then
            local activePrompt = heistStarted and endHeistPrompt or heistPrompt
            local inactivePrompt = heistStarted and heistPrompt or endHeistPrompt
            local currentLabel = heistStarted and Config.EndPrompt.label or label

            PromptSetEnabled(inactivePrompt, false)
            PromptSetVisible(inactivePrompt, false)

            PromptSetEnabled(activePrompt, true)
            PromptSetVisible(activePrompt, true)
            PromptSetActiveGroupThisFrame(promptGroup, CreateVarString(10, 'LITERAL_STRING', currentLabel))

            if PromptHasStandardModeCompleted(activePrompt, 0) then
                if heistStarted then
                    TriggerEvent('coi_art_rob:client:endHeist')
                else
                    TriggerEvent('coi_art_rob:client:startHeist', locationName)
                end
                Wait(1000) -- Prevent double trigger
            end
            Wait(0)
        else
            PromptSetEnabled(heistPrompt, false)
            PromptSetVisible(heistPrompt, false)
            PromptSetEnabled(endHeistPrompt, false)
            PromptSetVisible(endHeistPrompt, false)
            Wait(250)
        end
    end
end)

CreateThread(function()
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

RegisterNetEvent('coi_art_rob:client:startHeist')
AddEventHandler('coi_art_rob:client:startHeist', function(locationName)
    if heistStarted then return end
    heistStarted = true

    if Config.Debug then
        print(('[coi_art_rob] Art Heist started at %s'):format(locationName))
    end

    -- Clear any existing heist items just in case
    for _, prop in ipairs(heistProps) do DeleteObject(prop) end
    for _, blip in ipairs(heistBlips) do RemoveBlip(blip) end
    heistProps = {}
    heistBlips = {}

    local model = Config.Heist.StatueModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    for i, coords in ipairs(Config.Heist.StatueLocations) do
        -- Spawn Statue Prop
        local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
        SetEntityHeading(prop, coords.w)
        PlaceObjectOnGroundProperly(prop)
        FreezeEntityPosition(prop, true)
        table.insert(heistProps, prop)

        -- Large round area blip (no sprite), tinted with a blip colour modifier
        local blip = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, coords.x, coords.y, coords.z, Config.Heist.Blip.radius)
        if blip and blip ~= 0 then
            Citizen.InvokeNative(0x662D364ABF7265AC, blip, GetHashKey(Config.Heist.Blip.color)) -- BLIP_ADD_MODIFIER
            local str = CreateVarString(10, 'LITERAL_STRING', Config.Heist.Blip.label)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, str) -- SET_BLIP_NAME
            table.insert(heistBlips, blip)
        end
    end

    SetModelAsNoLongerNeeded(model)
    
    TriggerEvent('vorp:TipRight', "The Art Heist has begun! Find the statues marked on your map.", 5000)
end)

RegisterNetEvent('coi_art_rob:client:endHeist')
AddEventHandler('coi_art_rob:client:endHeist', function()
    if not heistStarted then return end
    heistStarted = false

    if Config.Debug then
        print('[coi_art_rob] Art Heist ended')
    end

    for _, prop in ipairs(heistProps) do DeleteObject(prop) end
    for _, blip in ipairs(heistBlips) do RemoveBlip(blip) end
    heistProps = {}
    heistBlips = {}

    TriggerEvent('vorp:TipRight', "The Art Heist has ended.", 5000)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    for _, ped in pairs(activePeds) do
        deletePed(ped)
    end
    
    for _, blip in pairs(activeBlips) do
        if blip and type(blip) == "number" and blip ~= 0 then
            RemoveBlip(blip)
        end
    end

    for _, prop in ipairs(heistProps) do
        DeleteObject(prop)
    end

    for _, blip in ipairs(heistBlips) do
        if blip and type(blip) == "number" and blip ~= 0 then
            RemoveBlip(blip)
        end
    end
    
    if endHeistPrompt then
        PromptDelete(endHeistPrompt)
    end
    
    if heistPrompt then
        PromptDelete(heistPrompt)
    end
end)
