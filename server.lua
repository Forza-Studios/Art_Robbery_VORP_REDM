-- Pays out statue deliveries. The server owns the amount and checks the player is at the delivery point.

local VORPcore = {}
TriggerEvent('getCore', function(core)
    VORPcore = core
end)

local lastPayout = {} -- source -> GetGameTimer() of their last payout
local PAYOUT_COOLDOWN = 2000

RegisterServerEvent('coi_art_rob:server:deliverStatue', function(locationName, deliveryIndex)
    local src = source
    local now = GetGameTimer()
    if lastPayout[src] and now - lastPayout[src] < PAYOUT_COOLDOWN then return end

    local delivery = type(deliveryIndex) == 'number' and Config.Heist.Delivery[deliveryIndex]
    if not delivery then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local d = delivery.coords
    if #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > delivery.radius + 10.0 then return end

    local user = VORPcore.getUser(src)
    if not user then return end
    local character = user.getUsedCharacter
    if not character then return end

    lastPayout[src] = now
    local amount = Config.Heist.Payout
    character.addCurrency(0, amount)
    local message = ('You received $%d for delivering the statue'):format(amount)
    if VORPcore.NotifyRightTip then
        VORPcore.NotifyRightTip(src, message, 5000) -- VORP's default top-right tip
    else
        TriggerClientEvent('vorp:TipRight', src, message, 5000)
    end
    print(('[coi_art_rob] %s was paid $%d for a statue delivery'):format(GetPlayerName(src), amount))
end)

AddEventHandler('playerDropped', function()
    lastPayout[source] = nil
end)
