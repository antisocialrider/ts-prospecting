Prospecting = {}
prospecting = exports['ts-prospecting']
local PROSPECTING_STATUS = {}
local PROSPECTING_TARGETS = {}
local PROSPECTING_DIFFICULTIES = {}
local targetsDirty = false
local updateTimer = nil

function Prospecting.AddTarget(x, y, z, data)
    prospecting:AddProspectingTarget(x, y, z, data)
end

function Prospecting.GetProspectingTargets()
    return prospecting:GetProspectingTargets()
end

function Prospecting.AddTargets(list)
    prospecting:AddProspectingTargets(list)
end

function Prospecting.StartProspecting(player)
    prospecting:StartProspecting(player)
end

function Prospecting.StopProspecting(player)
    prospecting:StopProspecting(player)
end

function Prospecting.IsProspecting(player)
    return prospecting:IsProspecting(player)
end

function Prospecting.SetDifficulty(modifier)
    return prospecting:SetDifficulty(modifier)
end

function Prospecting.OnStart(handler)
    AddEventHandler("ts-prospecting:server:onStart", function(player)
        handler(player)
    end)
end

function Prospecting.OnStop(handler)
    AddEventHandler("ts-prospecting:server:onStop", function(player, time)
        handler(player, time)
    end)
end

function Prospecting.SetHandler(handler)
    AddEventHandler("ts-prospecting:server:onCollected", function(player, resource, data, x, y, z)
        if resource == GetCurrentResourceName() then
            handler(player, data, x, y, z)
        end
    end)
end

function OnStart(handler)
    AddEventHandler("ts-onStart", function(player)
        handler(player)
    end)
end

function OnStop(handler)
    AddEventHandler("ts-onStop", function(player, time)
        handler(player, time)
    end)
end

function SetHandler(handler)
    AddEventHandler("ts-onCollected", function(player, resource, data, x, y, z)
        if resource == GetCurrentResourceName() then
            handler(player, data, x, y, z)
        end
    end)
end

local function TriggerUpdate()
    local targets = {}
    for _, target in next, PROSPECTING_TARGETS do
        local difficulty = target.difficulty or PROSPECTING_DIFFICULTIES[target.resource] or 1.0
        table.insert(targets, {x = target.x, y = target.y, z = target.z, difficulty = difficulty})
    end
    TriggerClientEvent("ts-prospecting:client:setTargetPool", -1, targets)
    targetsDirty = false
    updateTimer = nil
end

function QueueUpdate()
    targetsDirty = true
    if not updateTimer then
        updateTimer = SetTimeout(500, TriggerUpdate)
    end
end

function UpdateProspectingTargets(player_src)
    local targets = {}
    for _, target in next, PROSPECTING_TARGETS do
        local difficulty = target.difficulty or PROSPECTING_DIFFICULTIES[target.resource] or 1.0
        table.insert(targets, {x = target.x, y = target.y, z = target.z, difficulty = difficulty})
    end
    TriggerClientEvent("ts-prospecting:client:setTargetPool", player_src, targets)
end

function InsertProspectingTarget(resource, x, y, z, data)
    local targetDifficulty = data.difficulty or 1.0
    table.insert(PROSPECTING_TARGETS, {
        resource = resource,
        data = data,
        x = x,
        y = y,
        z = z,
        difficulty = targetDifficulty
    })
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
                print(string.format("Prospecting: Player %s tried to collect non-existent target at %s, %s, %s", player, x, y, z))
            end
        end
    else
        print(string.format("Prospecting: Player %s tried to collect invalid target index %s", player, index))
    end
end

function AddProspectingTarget(x, y, z, data)
    local resource = GetInvokingResource()
    InsertProspectingTarget(resource, x, y, z, data)
end
AddEventHandler("ts-prospecting:server:AddProspectingTarget", function(x, y, z, data)
    AddProspectingTarget(x, y, z, data)
end)

function AddProspectingTargets(list)
    local resource = GetInvokingResource()
    InsertProspectingTargets(resource, list)
end
AddEventHandler("ts-prospecting:server:AddProspectingTargets", function(list)
    AddProspectingTargets(list)
end)

function StartProspecting(player)
    if not PROSPECTING_STATUS[player] then
        TriggerClientEvent("ts-prospecting:client:forceStart", player)
    end
end
AddEventHandler("ts-prospecting:server:StartProspecting", function(player)
    StartProspecting(player)
end)

function StopProspecting(player)
    if PROSPECTING_STATUS[player] then
        TriggerClientEvent("ts-prospecting:client:forceStop", player)
    end
end
AddEventHandler("ts-prospecting:server:StopProspecting", function(player)
    StopProspecting(player)
end)

function IsProspecting(player)
    return PROSPECTING_STATUS[player] ~= nil
end

function GetProspectingTargets()
    return PROSPECTING_TARGETS
end

function SetDifficulty(modifier)
    local resource = GetInvokingResource()
    PROSPECTING_DIFFICULTIES[resource] = modifier
end

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
    local player = source
    UpdateProspectingTargets(player)
end)