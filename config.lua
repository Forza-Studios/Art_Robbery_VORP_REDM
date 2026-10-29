Config = {}

Config.Locations = {
    ['valentine'] = {
        model = `cs_valprostitute_02`,
        path = {
            vector4(-238.9870, 770.3414, 117.0950, 108.0667),  -- the first cord will pick for sprite on map blip position 
            vector4(-247.0715, 766.0087, 118.1284, 126.7618),  --- these are the path nodes which npc will roam around
            vector4(-248.5659, 771.9250, 118.1250, 47.1462),
            vector4(-247.9131, 768.4742, 118.1269, 121.2006),
            vector4(-242.4385, 769.7139, 118.0850, 107.1163),
        },
        sprite = -1954662204,
        label = 'Meet Jessie'
    },
}






Config.Heist = {
    StatueModel = `p_gen_statue02b`, -- Example statue model
    StatueSize = 5, -- Size of the statue prop
    StatueLocations = {
        vector4(-231.0029, 842.0952, 123.2734, 0),
        -- Add more statue locations here
    },
    PickupDistance = 2.5,
    PickupLabel = 'Pick Up Statue',
    -- How the statue sits while carried (attached to the right hand). Tune these in game.
    Carry = {
        bone = 'SKEL_R_Hand',
        offset = vector3(0.15, 0.05, 0.0),
        rotation = vector3(0.0, 90.0, 0.0),
    },
    Delivery = {
        coords = vector4(-245.1085, 846.6229, 123.8764, 116.9145),
        radius = 4.0,                           -- size of both the map circle and the world cylinder
        color = 'BLIP_MODIFIER_MP_COLOR_32',    -- map circle tint
        marker = { r = 255, g = 200, b = 0, a = 120 }, -- world cylinder colour
        label = 'Statue Delivery',
        prompt = 'Deliver Statue',
        route = 'COLOR_YELLOW',                 -- GPS route colour while carrying
    },
    Blip = {
        radius = 100.0,                         -- size of the round area on the map
        color = 'BLIP_MODIFIER_MP_COLOR_2',     -- blip colour modifier name; try MP_COLOR_1..32 to pick another tint
        label = 'Find the Statue'
    }
}





payout = 200






-- Per-model carry placement (attached to the player's hand bone). Falls back to Config.Heist.Carry.
Config.PropsLocationOnHands = {
    ["p_gen_statue02b"] = {
        x = 0.8,
        y = 0.8,
        z = -0.4,
        xRot = 45.0,
        yRot = -45.00,
        zRot = 0.0,
    },
}

Config.EndPrompt = {
    label = 'End Art Heist',
    control = 0xC7B5340A, -- INPUT_FRONTEND_ACCEPT
    distance = 4.0
}





Config.PathNodeWaitMin = 5000  -- Minimum milliseconds to wait at a path node
Config.PathNodeWaitMax = 10000 -- Maximum milliseconds to wait at a path node

Config.Prompt = {
    label = 'Start Art Heist',
    control = 0xC7B5340A, -- INPUT_FRONTEND_ACCEPT (Enter / Numpad Enter)
    distance = 4.0
}

Config.Invincible = true
Config.ReturnThreshold = 1.5

-- Native speech lines. RedM chooses the correct voice for the ped model.
Config.Debug = true
Config.SpeechParam = 'SPEECH_PARAMS_FORCE'
Config.VoiceLines = {
    'GREET_EVENING',
    'GREET_GENERAL_STRANGER',
    'GREET_FLIRTY',
    'HOWS_IT_GOING',
    'CHAT_GOOD_WEATHER',
}

Config.ChatterDistance = 12.0
Config.ChatterInterval = 8000 -- milliseconds; the NPC speaks continuously on this loop

-- Random movement around PedCoords. The NPC always returns to PedCoords afterwards.
Config.WanderRadius = 4.0
Config.WanderChance = 0.65
Config.WanderIntervalMin = 15000 -- milliseconds
Config.WanderIntervalMax = 30000 -- milliseconds
Config.WanderDuration = 12000 -- milliseconds spent walking/animating at the random point
