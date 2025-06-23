Config = Config or {}

Config.Debugging = true

-- Defines all prospecting areas. Each area can have its own characteristics.
Config.prospecting_areas = {
    -- Area 1: General Prospecting Zone
    {
        name = "General Prospecting Grounds", -- A descriptive name for the area
        base = vector3(1580.9, 6592.204, 13.84828), -- Center point of the area
        size = 100.0, -- Radius of the circular prospecting area
        difficulty = 1.0, -- Default client-side scanner difficulty multiplier for this area (1.0 is normal)
        item_pool = { -- Items that can randomly spawn in this area, with their rarity weight
            {item = "lockpick", valuable = false, weight = 50},
            {item = "advancedlockpick", valuable = false, weight = 30},
            {item = "10kgoldchain", valuable = true, weight = 20}, -- More rare
        }
    },
    -- Area 2: High-Value Prospecting Zone
    {
        name = "Rich Mineral Deposit", -- A descriptive name for the area
        base = vector3(1400.0, 6700.0, 20.0), -- Another center point
        size = 75.0, -- Smaller radius
        difficulty = 1.5, -- This area is harder to detect in (scanner signals are more subtle)
        item_pool = { -- Items that can randomly spawn in this area, with adjusted weights
            {item = "advancedlockpick", valuable = false, weight = 40},
            {item = "10kgoldchain", valuable = true, weight = 30},
            {item = "gold_nugget", valuable = true, weight = 25},
            {item = "rare_diamond", valuable = true, weight = 5}, -- Very rare
        }
    },
    -- Add more prospecting areas as needed
}