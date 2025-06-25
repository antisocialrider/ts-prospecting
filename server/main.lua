local QBCore = exports['qb-core']:GetCoreObject()

function IsPointInPolygon(px, py, polygon)
    local num_vertices = #polygon
    local inside = false
    local i = 1
    local j = num_vertices

    while i <= num_vertices do
        local xi, yi = polygon[i].x, polygon[i].y
        local xj, yj = polygon[j].x, polygon[j].y
        if ((yi > py) ~= (yj > py)) and
           (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then
            inside = not inside
        end

        j = i
        i = i + 1
    end

    return inside
end

local function GetBoundingBox(points)
    local minX, maxX = points[1].x, points[1].x
    local minY, maxY = points[1].y, points[1].y

    for i = 2, #points do
        minX = math.min(minX, points[i].x)
        maxX = math.max(maxX, points[i].x)
        minY = math.min(minY, points[i].y)
        maxY = math.max(maxY, points[i].y)
    end
    return minX, minY, maxX, maxY
end

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

function GenerateNewRandomTargetInArea(area)
    local proposedX, proposedY
    local finalZ
    local isValidPoint = false
    local attempts = 0
    local MAX_ATTEMPTS = 50

    local minX, minY, maxX, maxY = GetBoundingBox(area.points)

    while not isValidPoint and attempts < MAX_ATTEMPTS do
        attempts = attempts + 1
        proposedX = (math.random() * (maxX - minX)) + minX
        proposedY = (math.random() * (maxY - minY)) + minY
        if IsPointInPolygon(proposedX, proposedY, area.points) then
            finalZ = (math.random() * (area.maxZ - area.minZ)) + area.minZ
            isValidPoint = true
        else
            Debugging(string.format("Prospecting: Proposed 2D point (%.2f, %.2f) for area '%s' was outside polygon. Retrying...", proposedX, proposedY, area.name))
        end
    end

    if not isValidPoint then
        Debugging(string.format("Prospecting: Failed to find valid target in area '%s' after %d attempts. Skipping target generation.", area.name, MAX_ATTEMPTS))
        return
    end

    local newPos = vector3(proposedX, proposedY, finalZ)

    local newData = GetRandomWeightedItem(area.item_pool)
    newData.difficulty = area.difficulty or 1.0
    Prospecting.AddTarget(area.name, newPos.x, newPos.y, newPos.z, newData)
end

function EnsureMinimumTargets()
    CreateThread(function()
        while true do
            local currentTargets = exports['ts-prospecting']:GetProspectingTargets()
            local targetsByArea = {}
            for _, area in ipairs(Config.prospecting_areas) do
                targetsByArea[area.name] = 0
            end

            for _, target in ipairs(currentTargets) do
                if target.areaName and targetsByArea[target.areaName] ~= nil then
                    targetsByArea[target.areaName] = targetsByArea[target.areaName] + 1
                else
                    Debugging(string.format("Prospecting: Found target at (%.2f, %.2f, %.2f) without a valid areaName. (Likely an old target)", target.x, target.y, target.z))
                end
            end

            for _, area in ipairs(Config.prospecting_areas) do
                local currentCount = targetsByArea[area.name] or 0
                if currentCount < area.amount then
                    local needed = area.amount - currentCount
                    for i = 1, needed do
                        GenerateNewRandomTargetInArea(area)
                    end
                end
            end
            Citizen.Wait(60 * 1000)
        end
    end)
end

RegisterServerEvent("ts-prospecting:server:activateProspecting")
AddEventHandler("ts-prospecting:server:activateProspecting", function()
    local player = source
    Prospecting.StartProspecting(player)
end)

CreateThread(function()
    Prospecting.SetDifficulty(1.0)

    for _, area in ipairs(Config.prospecting_areas) do
        for n = 1, area.amount do
            GenerateNewRandomTargetInArea(area)
        end
    end

    EnsureMinimumTargets()

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
    end)

    Prospecting.OnStart(function(player)
        TriggerClientEvent('QBCore:Notify', player, "Started prospecting", 'success') 
    end)
    Prospecting.OnStop(function(player, time)
        TriggerClientEvent('QBCore:Notify', player, "Stopped prospecting", 'error') 
    end)
end)

QBCore.Functions.CreateUseableItem('metaldetector', function(source)
    TriggerClientEvent('ts-prospecting:client:checkPlayerInZone', source)
end)