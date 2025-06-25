local QBCore = exports['qb-core']:GetCoreObject()

-- Helper function to get a random item from a given item pool with weights
function GetRandomWeightedItem(item_pool)
    local totalWeight = 0
    for _, itemData in ipairs(item_pool) do
        totalWeight = totalWeight + (itemData.weight or 1) -- Default weight to 1 if not specified
    end

    local randomNumber = math.random(totalWeight)
    local cumulativeWeight = 0
    for _, itemData in ipairs(item_pool) do
        cumulativeWeight = cumulativeWeight + (itemData.weight or 1)
        if randomNumber <= cumulativeWeight then
            return {item = itemData.item, valuable = itemData.valuable}
        end
    end
    return nil -- Should not happen if item_pool is not empty
end

-- Helper function to get a random point within a circular radius
local function GetRandomPointInRadius(center, radius)
    local angle = math.random() * 2 * math.pi
    local distance = math.sqrt(math.random()) * radius
    local x = center.x + distance * math.cos(angle)
    local y = center.y + distance * math.sin(angle)
    -- Keep the Z coordinate from the center, or adjust as needed for terrain
    return vector3(x, y, center.z)
end

-- Make a random location and item from one of the defined areas
function GenerateNewRandomTarget()
    -- Select a random prospecting area from the config
    local randomArea = Config.prospecting_areas[math.random(#Config.prospecting_areas)]
    
    local newPos = GetRandomPointInRadius(randomArea.base, randomArea.size)
    local newData = GetRandomWeightedItem(randomArea.item_pool)
    
    -- Add the area's difficulty to the target data for client-side use
    newData.difficulty = randomArea.difficulty or 1.0 -- Default to 1.0 if not specified
    
    -- Prospecting.AddTarget(x, y, z, data) expects data to be a table,
    -- which now includes item, valuable, and difficulty.
    Prospecting.AddTarget(newPos.x, newPos.y, newPos.z, newData)
end

RegisterServerEvent("ts-prospecting:activateProspecting")
AddEventHandler("ts-prospecting:activateProspecting", function()
    local player = source
    Prospecting.StartProspecting(player)
end)


CreateThread(function()
    -- Set global default difficulty if needed, but area-specific difficulties will override this.
    Prospecting.SetDifficulty(1.0) 

    -- Generate a set number of random targets initially for all areas
    for n = 0, 10 do -- Generate 10 random targets initially
        GenerateNewRandomTarget()
    end

    -- The player collected something
    Prospecting.SetHandler(function(player, data, x, y, z)
        local src = player
        local Player = QBCore.Functions.GetPlayer(src)
        local amount = math.random(1,5)
        -- Check if the item is valuable, which is a part of the data we pass when creating it!
        if data.valuable then
            TriggerClientEvent('QBCore:Notify', src, "You found " .. data.item .. "!", 'success')   
            Player.Functions.AddItem(data.item, amount)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[data.item], 'add')
        else
            TriggerClientEvent('QBCore:Notify', src, "You found " .. data.item .. "!", 'success')   
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[data.item], 'add')
            Player.Functions.AddItem(data.item, amount)
        end
        -- Generate a new random target to replace the collected one
        GenerateNewRandomTarget()
    end)
   

    -- The player started prospecting
    Prospecting.OnStart(function(player)
        TriggerClientEvent('QBCore:Notify', player, "Started prospecting", 'success') 
    end)
    -- The player stopped prospecting
    -- time in milliseconds
    Prospecting.OnStop(function(player, time)
        TriggerClientEvent('QBCore:Notify', player, "Stopped prospecting", 'error') 
    end)
end)


QBCore.Functions.CreateUseableItem('metaldetector', function(source)
    local pos = GetEntityCoords(GetPlayerPed(source))
    local inAnyZone = false
    for _, area in ipairs(Config.prospecting_areas) do
        local dist = #(pos - area.base)
        if dist < area.size then
            inAnyZone = true
            break
        end
    end

    if inAnyZone then
        TriggerClientEvent('ts-prospecting:usedetector', source)
    else
        TriggerClientEvent('QBCore:Notify', source, "You are not in a prospecting zone!", 'error')
    end
end)