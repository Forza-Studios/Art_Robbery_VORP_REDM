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
local statuePending = {} -- prop -> true while it still has to be delivered
local heistPrompt
local endHeistPrompt
local heistStarted = false
local carriedProp
local deliveryBlips = {}
local activeLocation -- key of Config.Locations the running heist belongs to
local deliveredCount = 0
local statueBlips = {} -- prop -> blip, so a statue's map circle goes away once picked up
local pickupGroup = GetRandomIntInRange(0, 0xffffff)
local deliverGroup = GetRandomIntInRange(0, 0xffffff)
local pickupPrompt
local deliverPrompt
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

local deliveryPoints
local function activeDeliveries()
    deliveryPoints = deliveryPoints or Config.GetDeliveryPoints()
    return deliveryPoints
end

local function addAreaBlip(coords, radius, colorName, label)
    local blip = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, coords.x, coords.y, coords.z, radius)
    if blip and blip ~= 0 then
        Citizen.InvokeNative(0x662D364ABF7265AC, blip, GetHashKey(colorName)) -- BLIP_ADD_MODIFIER
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, 'LITERAL_STRING', label)) -- SET_BLIP_NAME
        return blip
    end
end

local function hideStatueBlips()
    for prop, blip in pairs(statueBlips) do
        RemoveBlip(blip)
        statueBlips[prop] = nil
    end
end

local function showStatueBlips()
    local activeBlipCfg = Config.Heist.Blip
    for prop in pairs(statuePending) do
        if DoesEntityExist(prop) and not statueBlips[prop] then
            local blip = addAreaBlip(GetEntityCoords(prop), activeBlipCfg.radius, activeBlipCfg.color, activeBlipCfg.label)
            if blip then statueBlips[prop] = blip end
        end
    end
end

local function hideDeliveryBlip()
    for i, blip in pairs(deliveryBlips) do
        RemoveBlip(blip)
        deliveryBlips[i] = nil
    end
end

local function showDeliveryBlip()
    hideDeliveryBlip()
    for i, d in ipairs(activeDeliveries()) do
        local blip = addAreaBlip(d.coords, d.blipRadius or d.radius, d.color, d.label)
        if blip then deliveryBlips[i] = blip end
    end
end

local function registerPrompt(text, group)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, Config.Prompt.control)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, group)
    PromptRegisterEnd(prompt)
    PromptSetEnabled(prompt, false)
    PromptSetVisible(prompt, false)
    return prompt
end

local function showPrompt(prompt, group, title)
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', title))
    return PromptHasStandardModeCompleted(prompt, 0)
end

local function hidePrompt(prompt)
    PromptSetEnabled(prompt, false)
    PromptSetVisible(prompt, false)
end

local function playCarryAnim(ped)
    local carry = Config.Heist.Carry
    RequestAnimDict(carry.animDict)
    while not HasAnimDictLoaded(carry.animDict) do Wait(0) end
    TaskPlayAnim(ped, carry.animDict, carry.animName, 1.0, 8.0, -1, 25, 0, false, false, false)
end

local function stopCarryAnim(ped)
    local carry = Config.Heist.Carry
    StopAnimTask(ped, carry.animDict, carry.animName, 1.0)
end

local function pickUpStatue(prop)
    local ped = PlayerPedId()
    carriedProp = prop
    FreezeEntityPosition(prop, false)
    SetEntityCollision(prop, false, false)
    local carry = Config.Heist.Carry
    local x, y, z = carry.offset.x, carry.offset.y, carry.offset.z
    local xRot, yRot, zRot = carry.rotation.x, carry.rotation.y, carry.rotation.z
    local model = GetEntityModel(prop)
    for name, placement in pairs(Config.PropsLocationOnHands) do
        if GetHashKey(name) == model then
            x, y, z = placement.x, placement.y, placement.z
            xRot, yRot, zRot = placement.xRot, placement.yRot, placement.zRot
            break
        end
    end
    playCarryAnim(ped)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, carry.bone),
        x, y, z, xRot, yRot, zRot,
        true, true, false, true, 1, true)

    -- while carrying, only the delivery point is shown on the map
    hideStatueBlips()
    showDeliveryBlip()

    TriggerEvent('vorp:TipRight', "Carry the statue to the delivery point.", 5000)
end

local function dropStatue()
    local prop = carriedProp
    carriedProp = nil
    stopCarryAnim(PlayerPedId())
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        SetEntityCollision(prop, true, true)
        PlaceObjectOnGroundProperly(prop)
        FreezeEntityPosition(prop, true)
    end
    hideDeliveryBlip()
    showStatueBlips()
end

local function deliverStatue(deliveryIndex)
    local prop = carriedProp
    carriedProp = nil
    stopCarryAnim(PlayerPedId())
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteObject(prop)
    end
    statuePending[prop] = nil
    hideDeliveryBlip()
    showStatueBlips()
    deliveredCount = deliveredCount + 1
    TriggerServerEvent('coi_art_rob:server:deliverStatue', activeLocation, deliveryIndex)
    if deliveredCount >= #Config.Heist.StatueLocations then
        TriggerEvent('vorp:TipRight', "All statues delivered!", 5000)
    end
end

CreateThread(function()
    pickupPrompt = registerPrompt(Config.Heist.PickupLabel, pickupGroup)
    deliverPrompt = registerPrompt('Deliver Statue', deliverGroup)

    while true do
        local wait = 500
        if heistStarted then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)

            if carriedProp then
                if IsEntityDead(playerPed) then
                    dropStatue()
                else
                    hidePrompt(pickupPrompt)

                    local carry = Config.Heist.Carry
                    if not IsEntityPlayingAnim(playerPed, carry.animDict, carry.animName, 3) then
                        playCarryAnim(playerPed)
                    end

                    local insideIndex, insideDelivery
                    for index, d in ipairs(activeDeliveries()) do
                        local dest = vector3(d.coords.x, d.coords.y, d.coords.z)
                        local dist = #(playerCoords - dest)

                        if dist < 80.0 then
                            wait = 0
                            -- world cylinder matching the map circle (_DRAW_MARKER, type 0x94FDAE17 = cylinder)
                            Citizen.InvokeNative(0x2A32FAA57B937173, 0x94FDAE17, dest.x, dest.y, dest.z - 1.0,
                                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                d.radius * 2.0, d.radius * 2.0, 3.0,
                                d.marker.r, d.marker.g, d.marker.b, d.marker.a,
                                false, false, 2, false, nil, nil, false)
                        end

                        if dist < d.radius then
                            insideIndex, insideDelivery = index, d
                        end
                    end

                    if insideDelivery then
                        wait = 0
                        if showPrompt(deliverPrompt, deliverGroup, insideDelivery.label) then
                            deliverStatue(insideIndex)
                            Wait(1000)
                        end
                    else
                        hidePrompt(deliverPrompt)
                    end
                end
            else
                hidePrompt(deliverPrompt)
                local nearest
                for _, prop in ipairs(heistProps) do
                    if DoesEntityExist(prop) and statuePending[prop] then
                        if #(playerCoords - GetEntityCoords(prop)) < Config.Heist.PickupDistance then
                            nearest = prop
                            break
                        end
                    end
                end

                if nearest then
                    wait = 0
                    if showPrompt(pickupPrompt, pickupGroup, 'Statue') then
                        pickUpStatue(nearest)
                        Wait(1000)
                    end
                else
                    hidePrompt(pickupPrompt)
                end
            end
        elseif pickupPrompt then
            hidePrompt(pickupPrompt)
            hidePrompt(deliverPrompt)
        end
        Wait(wait)
    end
end)

RegisterNetEvent('coi_art_rob:client:startHeist')
AddEventHandler('coi_art_rob:client:startHeist', function(locationName)
    if heistStarted then return end
    heistStarted = true
    activeLocation = locationName
    SendNUIMessage({ action = 'badge', show = true, text = Config.Heist.BadgeText })

    if Config.Debug then
        print(('[coi_art_rob] Art Heist started at %s'):format(locationName))
    end

    -- Clear any existing heist items just in case
    for _, prop in ipairs(heistProps) do DeleteObject(prop) end
    hideStatueBlips()
    hideDeliveryBlip()
    heistProps = {}
    statuePending = {}

    local model = Config.Heist.StatueModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    for i, coords in ipairs(Config.Heist.StatueLocations) do
        -- Spawn Statue Prop
        local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
        SetEntityHeading(prop, coords.w)
        
        -- Apply Statue Size
         if Config.Heist.StatueSize and Config.Heist.StatueSize ~= 1.0 then
             Citizen.InvokeNative(0xD5A1CD1284CB2495, prop, Config.Heist.StatueSize + 0.0) -- SET_ENTITY_SCALE
         end

        PlaceObjectOnGroundProperly(prop)
        FreezeEntityPosition(prop, true)
        table.insert(heistProps, prop)

        statuePending[prop] = true
    end

    showStatueBlips()

    SetModelAsNoLongerNeeded(model)
    
    deliveredCount = 0
    PromptSetText(deliverPrompt, CreateVarString(10, 'LITERAL_STRING', activeDeliveries()[1].prompt))

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
    hideStatueBlips()
    hideDeliveryBlip()
    heistProps = {}
    statuePending = {}
    carriedProp = nil
    activeLocation = nil
    SendNUIMessage({ action = 'badge', show = false })

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

    hideStatueBlips()
    hideDeliveryBlip()

    if pickupPrompt then PromptDelete(pickupPrompt) end
    if deliverPrompt then PromptDelete(deliverPrompt) end

    if endHeistPrompt then
        PromptDelete(endHeistPrompt)
    end
    
    if heistPrompt then
        PromptDelete(heistPrompt)
    end
end)
