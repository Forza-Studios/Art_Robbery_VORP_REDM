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

    local delivery = type(deliveryIndex) == 'number' and Config.GetDeliveryPoints()[deliveryIndex]
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

-- Admin preview commands: toggle a map/world view of every statue or delivery location.
local function isAdmin(src)
    if src == 0 or IsPlayerAceAllowed(src, 'command') then return true end
    local user = VORPcore.getUser and VORPcore.getUser(src)
    local character = user and user.getUsedCharacter
    if not character then return false end
    for _, group in ipairs(Config.AdminGroups) do
        if character.group == group then return true end
    end
    return false
end

local function registerPreviewCommand(name, kind)
    RegisterCommand(name, function(src)
        if src == 0 then return end
        if not isAdmin(src) then
            TriggerClientEvent('vorp:TipRight', src, 'You do not have permission to use this command.', 4000)
            return
        end
        TriggerClientEvent('coi_art_rob:client:togglePreview', src, kind)
    end, false)
end

registerPreviewCommand('statue', 'statue')
registerPreviewCommand('statuedeli', 'delivery')
