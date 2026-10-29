-- cs_valprostitute_02 NPC Spawner
-- Spawns the NPC at the specified coordinates on resource start.

local NPC = { model = 'cs_valprostitute_02', x = -238.9870, y = 770.3414, z = 117.0950, yaw = 108.0667 }

local function SpawnPed(model, x, y, z, yaw)
    local ped = CreatePed(model, x, y, z, yaw, false, false, false, false)
    repeat Wait(10) until DoesEntityExist(ped)
    return ped
end

CreateThread(function()
    print('[' .. GetCurrentResourceName() .. '] Requesting NPC model: ' .. NPC.model)

    RequestModel(NPC.model)
    while not HasModelLoaded(NPC.model) do
        Wait(100)
    end

    local ped = SpawnPed(NPC.model, NPC.x, NPC.y, NPC.z, NPC.yaw)

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityVisible(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)

    print('[' .. GetCurrentResourceName() .. '] NPC spawned at (' .. string.format('%.2f, %.2f, %.2f') , NPC.x, NPC.y, NPC.z) .. ')')
    SetModelAsNoLongerNeeded(NPC.model)
end)