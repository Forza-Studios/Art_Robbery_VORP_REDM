local PED_MODEL = `cs_valprostitute_02`
local PED_COORDS = vector4(-238.9870, 770.3414, 117.0950, 108.0667)

CreateThread(function()
    if not IsModelValid(PED_MODEL) then
        print('^1[coi_art_rob] invalid ped model^7')
        return
    end

    RequestModel(PED_MODEL)

    while not HasModelLoaded(PED_MODEL) do
        Wait(0)
    end

    local ped = CreatePed(
        PED_MODEL,
        PED_COORDS.x,
        PED_COORDS.y,
        PED_COORDS.z,
        PED_COORDS.w,
        false,
        false,
        false,
        false
    )

    -- RedM peds are invisible until an outfit is applied
    SetRandomOutfitVariation(ped, true)
    SetEntityAsMissionEntity(ped, true, true)

    -- shopkeeper behaviour: stays put, ignores threats, can't be hurt
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_STAND_WAITING'), -1, true, false, false, false)

    SetModelAsNoLongerNeeded(PED_MODEL)
end)
