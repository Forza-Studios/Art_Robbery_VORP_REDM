-- Pays out statue deliveries. The server owns the amount and checks the player is at the delivery point.

local VORPcore = {}
TriggerEvent('getCore', function(core)
    VORPcore = core
end)

local lastPayout = {} -- source -> GetGameTimer() of their last payout
local PAYOUT_COOLDOWN = 2000

RegisterServerEvent('coi_art_rob:server:deliverStatue', function()
    local src = source
    local now = GetGameTimer()
    if lastPayout[src] and now - lastPayout[src] < PAYOUT_COOLDOWN then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local d = Config.Heist.Delivery.coords
    if #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > Config.Heist.Delivery.radius + 10.0 then return end

    local user = VORPcore.getUser(src)
    if not user then return end
    local character = user.getUsedCharacter
    if not character then return end

    lastPayout[src] = now
    local amount = Config.Heist.Payout
    character.addCurrency(0, amount)
    TriggerClientEvent('vorp:TipRight', src, ('Statue delivered. You earned $%d'):format(amount), 5000)
    print(('[coi_art_rob] %s was paid $%d for a statue delivery'):format(GetPlayerName(src), amount))
end)

AddEventHandler('playerDropped', function()
    lastPayout[source] = nil
end)
