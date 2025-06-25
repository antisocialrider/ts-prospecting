local QBCore = exports['qb-core']:GetCoreObject()
local PROSPECTING_STATUS = {}
local PROSPECTING_TARGETS = {}
local PROSPECTING_DIFFICULTIES = {}
local updateTimer = nil

function Debugging(data)
    if Config.Debugging then
        print(data)
    end
end

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

function GetBoundingBox(points)
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

function InsertProspectingTarget(resource, areaName, x, y, z, data)
    local targetDifficulty = data.difficulty or 1.0
    table.insert(PROSPECTING_TARGETS, {resource = resource, areaName = areaName, data = data, x = x, y = y, z = z, difficulty = targetDifficulty})
    QueueUpdate()
end

function InsertProspectingTargets(resource, targets_list)
    for _, target in next, targets_list do
        InsertProspectingTarget(resource, target.x, target.y, target.z, target.data)
    end
end

function RemoveProspectingTarget(index)
    local new_targets = {}
    for n, target in next, PROSPECTING_TARGETS do
        if n ~= index then
            table.insert(new_targets, target)
        end
    end
    PROSPECTING_TARGETS = new_targets
    QueueUpdate()
end

function FindMatchingPickup(x, y, z)
    for index, target in next, PROSPECTING_TARGETS do
        if math.floor(target.x) == math.floor(x) and math.floor(target.y) == math.floor(y) and math.floor(target.z) == math.floor(z) then
            return index
        end
    end
    return nil
end

function GetAreaConfig(areaName)
    for _, area in ipairs(Config.prospecting_areas) do
        if area.name == areaName then
            return area
        end
    end
    return nil
end

function QueueUpdate()
    if not updateTimer then
        updateTimer = SetTimeout(100, TriggerUpdate)
    end
end

function TriggerUpdate()
    local targets = {}
    for _, target in next, PROSPECTING_TARGETS do
        local difficulty = target.difficulty or PROSPECTING_DIFFICULTIES[target.resource] or 1.0
        local areaConfig = GetAreaConfig(target.areaName)
        table.insert(targets, {
            x = target.x,
            y = target.y,
            z = target.z,
            difficulty = difficulty,
            areaName = target.areaName,
            minZ = areaConfig and areaConfig.minZ or target.z,
            maxZ = areaConfig and areaConfig.maxZ or target.z,
        })
    end
    TriggerClientEvent("ts-prospecting:client:setTargetPool", -1, targets)
    updateTimer = nil
end

function HandleProspectingPickup(player, index, x, y, z)
    local target = PROSPECTING_TARGETS[index]
    if target then
        local dx, dy, dz = target.x, target.y, target.z
        local resource, data = target.resource, target.data
        if math.floor(dx) == math.floor(x) and math.floor(dy) == math.floor(y) and math.floor(dz) == math.floor(z) then
            RemoveProspectingTarget(index)
            TriggerEvent("ts-prospecting:server:onCollected", player, resource, data, x, y, z)
        else
            local newMatch = FindMatchingPickup(x, y, z)
            if newMatch then
                HandleProspectingPickup(player, newMatch, x, y, z)
            else
                Debugging(string.format("Prospecting: Player %s tried to collect non-existent target at %s, %s, %s", player, x, y, z))
            end
        end
    else
        Debugging(string.format("Prospecting: Player %s tried to collect invalid target index %s", player, index))
    end
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
    InsertProspectingTarget(GetCurrentResourceName(), area.name, newPos.x, newPos.y, newPos.z, newData)
end

function EnsureMinimumTargets()
    CreateThread(function()
        while true do
            local targetsByArea = {}
            for _, area in ipairs(Config.prospecting_areas) do
                targetsByArea[area.name] = 0
            end

            for _, target in ipairs(PROSPECTING_TARGETS) do
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
    if not PROSPECTING_STATUS[source] then
        TriggerClientEvent("ts-prospecting:client:forceStart", source)
    end
end)

RegisterServerEvent("ts-prospecting:server:userStoppedProspecting")
AddEventHandler("ts-prospecting:server:userStoppedProspecting", function()
    local player = source
    if PROSPECTING_STATUS[player] then
        local time = GetGameTimer() - PROSPECTING_STATUS[player]
        PROSPECTING_STATUS[player] = nil
        TriggerEvent("ts-prospecting:server:onStop", player, time)
    end
end)

RegisterServerEvent("ts-prospecting:server:userStartedProspecting")
AddEventHandler("ts-prospecting:server:userStartedProspecting", function()
    local player = source
    if not PROSPECTING_STATUS[player] then
        PROSPECTING_STATUS[player] = GetGameTimer()
        TriggerEvent("ts-prospecting:server:onStart", player)
    end
end)

RegisterServerEvent("ts-prospecting:server:userCollectedNode")
AddEventHandler("ts-prospecting:server:userCollectedNode", function(index, x, y, z)
    local player = source
    if PROSPECTING_STATUS[player] then
        HandleProspectingPickup(player, index, x, y, z)
    end
end)

RegisterServerEvent("ts-prospecting:server:userRequestsLocations")
AddEventHandler("ts-prospecting:server:userRequestsLocations", function()
    local targets = {}
    for _, target in next, PROSPECTING_TARGETS do
        local difficulty = target.difficulty or PROSPECTING_DIFFICULTIES[target.resource] or 1.0
        local areaConfig = GetAreaConfig(target.areaName)
        table.insert(targets, {
            x = target.x,
            y = target.y,
            z = target.z,
            difficulty = difficulty,
            areaName = target.areaName,
            minZ = areaConfig and areaConfig.minZ or target.z,
            maxZ = areaConfig and areaConfig.maxZ or target.z,
        })
    end
    TriggerClientEvent("ts-prospecting:client:setTargetPool", source, targets)
end)

QBCore.Functions.CreateUseableItem('metaldetector', function(source)
    TriggerClientEvent('ts-prospecting:client:checkPlayerInZone', source)
end)

CreateThread(function()
    PROSPECTING_DIFFICULTIES[GetCurrentResourceName()] = 1.0
    for _, area in ipairs(Config.prospecting_areas) do
        for n = 1, area.amount do
            GenerateNewRandomTargetInArea(area)
        end
    end
    EnsureMinimumTargets()
    AddEventHandler("ts-prospecting:server:onCollected", function(player, resource, data, x, y, z)
        if resource == GetCurrentResourceName() then
            local src = player
            local Player = QBCore.Functions.GetPlayer(src)
            local amount = math.random(1,5)
            local itemLabel = QBCore.Shared.Items[data.item] and QBCore.Shared.Items[data.item].label or data.item

            if data.valuable then
                TriggerClientEvent('QBCore:Notify', src, "You found " .. amount .. "x " .. itemLabel .. " (Valuable)!", 'success')
                Player.Functions.AddItem(data.item, amount)
                TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[data.item], 'add')
            else
                TriggerClientEvent('QBCore:Notify', src, "You found " .. amount .. "x " .. itemLabel .. "!", 'success')
                TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[data.item], 'add')
                Player.Functions.AddItem(data.item, amount)
            end
        end
    end)

    AddEventHandler("ts-prospecting:server:onStart", function(player)
        TriggerClientEvent('QBCore:Notify', player, "Started prospecting", 'success')
    end)

    AddEventHandler("ts-prospecting:server:onStop", function(player, time)
        TriggerClientEvent('QBCore:Notify', player, "Stopped prospecting", 'error')
    end)
end)