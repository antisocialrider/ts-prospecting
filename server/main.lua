local QBCore = exports['qb-core']:GetCoreObject()

function GetRandomWeightedItem(item_pool)
    local totalWeight = 0
    for _, itemData in ipairs(item_pool) do
        totalWeight = totalWeight + (itemData.weight or 1)
    end

    local randomNumber = math.random(totalWeight)
    local cumulativeWeight = 0
    for _, itemData in ipairs(item_pool) do
        cumulativeWeight = cumulativeWeight + (itemData.weight or 1)
        if randomNumber <= cumulativeWeight then
            return {item = itemData.item, valuable = itemData.valuable}
        end
    end
    return nil
end

local function GetRandomPointInRadius(center, radius)
    local angle = math.random() * 2 * math.pi
    local distance = math.sqrt(math.random()) * radius
    local x = center.x + distance * math.cos(angle)
    local y = center.y + distance * math.sin(angle)
    return vector3(x, y, center.z)
end

function GenerateNewRandomTarget()
    local randomArea = Config.prospecting_areas[math.random(#Config.prospecting_areas)]
    
    local newPos = GetRandomPointInRadius(randomArea.base, randomArea.size)
    local newData = GetRandomWeightedItem(randomArea.item_pool)
    
    newData.difficulty = randomArea.difficulty or 1.0
    
    Prospecting.AddTarget(newPos.x, newPos.y, newPos.z, newData)
end

RegisterServerEvent("ts-prospecting:activateProspecting")
AddEventHandler("ts-prospecting:activateProspecting", function()
    local player = source
    Prospecting.StartProspecting(player)
end)


CreateThread(function()
    Prospecting.SetDifficulty(1.0) 

    for n = 0, 10 do
        GenerateNewRandomTarget()
    end

    Prospecting.SetHandler(function(player, data, x, y, z)
        local src = player
        local Player = QBCore.Functions.GetPlayer(src)
        local amount = math.random(1,5)
        local itemLabel = QBCore.Shared.Items[data.item] and QBCore.Shared.Items[data.item].label or data.item

        if data.valuable then
            TriggerClientEvent('QBCore:Notify', src, "You found " .. amount .. "x " .. itemLabel .. " (Valuable)!", 'success')
            Player.Functions.AddItem(data.item, amount)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[data.item], 'add')
        else
            TriggerClientEvent('QBCore:Notify', src, "You found " .. amount .. "x " .. itemLabel .. "!", 'success')
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[data.item], 'add')
            Player.Functions.AddItem(data.item, amount)
        end
        GenerateNewRandomTarget()
    end)

    Prospecting.OnStart(function(player)
        TriggerClientEvent('QBCore:Notify', player, "Started prospecting", 'success') 
    end)
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