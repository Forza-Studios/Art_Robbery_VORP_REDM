Config = {}

-- Statue model and spawn position.
Config.Statue = {
    model = "p_gen_statue02b",
    coords = { x = 2690.8564, y = -1183.2087, z = 51.9590, h = 0 },
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
