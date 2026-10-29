--[[
    Previous carryable-statue logic (disabled).

Config = {}

-- Statue model and spawn position.
Config.Statue = {
    model = "p_gen_statue02b",
    coords = { x = 2690.8564, y = -1183.2087, z = 52.9590, h = 73.0674 },
}

-- Attachment offset while the statue is carried.
Config.CarryOffset = {
    x = 0.8,
    y = 0.8,
    z = -0.4,
    xRot = 45.0,
    yRot = -45.0,
    zRot = 0.0,
}

Config.PickupDistance = 5.0
Config.PromptControl = 0x760A9C6F -- G

Config.CarryBone = 53675

Config.PickupAnim = {
    dict = "mech_carry_ped@enters@idle",
    name = "0_close_lf",
}

Config.CarryAnim = {
    dict = "mech_pickup@camerabag@carried",
    name = "grip_lt_arm",
}

Config.PickupLabel = "Pick Up"
Config.PutDownLabel = "Put Down"
]]

Config = {}

-- NPC sitting on the chair and drinking.
Config.Npc = {
    -- Female story ped. Swap for any female model from the local ped list
    -- (for example "a_f_m_valtownfolk_01") if you prefer a generic townsperson.
    model = "rcsp_beauandpenelope1_females_01",
    -- Chair X, Y, Z and heading. The heading is the direction the chair faces.
    -- This is the chair opposite the player; it is the only location setting.
    coords = { x = -244.0550, y = 772.1157, z = 116.5846, h = 199.8500 },
    scenario = "PROP_HUMAN_SEAT_CHAIR_DRINKING",

    -- Only show the NPC while the player is sitting near the opposite chair.
    -- Set this to false to fall back to the old "spawn when you are nearby" mode.
    onlyWhilePlayerSeated = true,
    -- How close the player's seat must be to the configured chair (metres).
    playerSitRadius = 4.0,
    -- Ignore the configured chair itself, so sitting on the NPC's chair does not
    -- make her try to sit in the same seat.
    playerMinDistance = 0.8,
    -- Grace period after the player stands up before the NPC leaves.
    leaveDelay = 5000,

    -- Spawn just behind the chair and let the ped walk onto the scenario point,
    -- instead of dropping her directly into the seat.
    spawnOffset = 1.2,

    -- Baked scenario-point search around the configured chair.
    pointSearchRadius = 2.0,
    pointScanRadius = 6.0,
    bakedScenarios = {
        "PROP_HUMAN_SEAT_CHAIR_DRINKING",
        "PROP_HUMAN_SEAT_CHAIR",
        "PROP_HUMAN_SEAT_CHAIR_TABLE_DRINKING",
    },

    -- Only used when the script has to create a scenario point. Baked map
    -- points keep their own Z.
    -- Use 0.0 if she sinks into the floor, or about -0.8 if she floats above the seat.
    zOffset = -0.5,
}
