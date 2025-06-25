Config = Config or {}

Config.Debugging = false

Config.prospecting_areas = {
    {
        name = "General Prospecting Grounds",
        base = vector3(1580.9, 6592.204, 13.84828),
        size = 50.0,
        amount = 10,
        difficulty = 1.0,
        item_pool = {
            {item = "lockpick", valuable = false, weight = 50},
            {item = "advancedlockpick", valuable = false, weight = 30},
            {item = "10kgoldchain", valuable = true, weight = 20},
        }
    },
    {
        name = "Rich Mineral Deposit",
        base = vector3(1400.0, 6700.0, 20.0),
        size = 100.0,
        amount = 10,
        difficulty = 1.5,
        item_pool = {
            {item = "advancedlockpick", valuable = false, weight = 40},
            {item = "10kgoldchain", valuable = true, weight = 30},
            {item = "gold_nugget", valuable = true, weight = 25},
            {item = "rare_diamond", valuable = true, weight = 5},
        }
    },
}