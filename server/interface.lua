-- Prospecting interface table
Prospecting = {}
-- Reference to the main ts-prospecting export functions
prospecting = exports['ts-prospecting']
-- Table to keep track of active prospecting status for each player (source ID -> start_time_ms)
local PROSPECTING_STATUS = {}
-- Table to store all active prospecting targets (index -> {resource, data, x, y, z, difficulty})
local PROSPECTING_TARGETS = {}
-- Multiplier for client-side scanner distance checks.
-- A higher modifier means the client needs to be closer to the target to get a strong signal.
-- This can be set by controlling resources, but the target's specific difficulty overrides/multiplies this.
local PROSPECTING_DIFFICULTIES = {}
--- Adds a single prospecting target.
-- Data can be any table and is returned with the node in the handler.
-- @param x number X coordinate.
-- @param y number Y coordinate.
-- @param z number Z coordinate.
-- @param data table Custom data for the target (e.g., {item = "gold", valuable = true, difficulty = 1.2}).
function Prospecting.AddTarget(x, y, z, data)
    prospecting:AddProspectingTarget(x, y, z, data)
end

--- Adds multiple prospecting targets from a list.
-- @param list table A list of target tables, each containing {x, y, z, data}.
function Prospecting.AddTargets(list)
    prospecting:AddProspectingTargets(list)
end

--- Starts the prospecting activity for a given player.
-- @param player integer The source ID of the player.
function Prospecting.StartProspecting(player)
    prospecting:StartProspecting(player)
end

--- Stops the prospecting activity for a given player.
-- @param player integer The source ID of the player.
function Prospecting.StopProspecting(player)
    prospecting:StopProspecting(player)
end

--- Checks if a player is currently prospecting.
-- @param player integer The source ID of the player.
-- @return boolean True if prospecting, false otherwise.
function Prospecting.IsProspecting(player)
    return prospecting:IsProspecting(player)
end

--- Sets a difficulty modifier for the invoking resource.
-- This modifier will be applied to targets added by this resource
-- if no specific difficulty is provided in the target data itself.
-- Does not affect other resources' settings.
-- @param modifier number The difficulty multiplier.
function Prospecting.SetDifficulty(modifier)
    return prospecting:SetDifficulty(modifier)
end

--- Sets a handler function for when a player starts prospecting.
-- @param handler function The function to call, with `player` as a parameter.
function Prospecting.OnStart(handler)
    AddEventHandler("ts-prospecting:onStart", function(player)
        handler(player)
    end)
end

--- Sets a handler function for when a player stops prospecting.
-- @param handler function The function to call, with `player` and `time` (in milliseconds) as parameters.
function Prospecting.OnStop(handler)
    AddEventHandler("ts-prospecting:onStop", function(player, time)
        handler(player, time)
    end)
end

--- Sets a handler function for collected nodes.
-- Parameters are: `player`, `data`, `x`, `y`, `z`.
-- The `data` table will now include `item`, `valuable`, and `difficulty`.
-- @param handler function The function to call when a node is collected.
function Prospecting.SetHandler(handler)
    AddEventHandler("ts-prospecting:onCollected", function(player, resource, data, x, y, z)
        -- Ensure this handler only processes events from the current resource
        if resource == GetCurrentResourceName() then
            handler(player, data, x, y, z)
        end
    end)
end

-- [[ Common Functions ]]
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
--- Updates the list of active prospecting targets for a given player or all players.
-- This sends the target locations and their associated difficulties to the client.
-- @param player_src integer | -1 (player source ID or -1 for all players)
function UpdateProspectingTargets(player_src)
    local targets = {}
    for _, target in next, PROSPECTING_TARGETS do
        -- Use the target's specific difficulty, which is now part of its data,
        -- fallback to the resource's global difficulty if target.difficulty isn't set,
        -- and finally default to 1.0.
        local difficulty = target.difficulty or PROSPECTING_DIFFICULTIES[target.resource] or 1.0
        table.insert(targets, {x = target.x, y = target.y, z = target.z, difficulty = difficulty})
    end
    TriggerClientEvent("ts-prospecting:setTargetPool", player_src, targets)
end

--- Inserts a new prospecting target into the global list.
-- This function is typically called by other server-side scripts (e.g., sv_locations.lua).
-- @param resource string The name of the resource adding the target.
-- @param x number X coordinate of the target.
-- @param y number Y coordinate of the target.
-- @param z number Z coordinate of the target.
-- @param data table Custom data associated with the target (e.g., item, valuable, difficulty).
function InsertProspectingTarget(resource, x, y, z, data)
    -- Ensure 'data' contains the 'difficulty' field from the area config if it's a generated target.
    -- If it's a manually added target, default difficulty to 1.0.
    local targetDifficulty = data.difficulty or 1.0
    table.insert(PROSPECTING_TARGETS, {
        resource = resource,
        data = data,
        x = x,
        y = y,
        z = z,
        difficulty = targetDifficulty -- Store the specific difficulty for this target
    })
    -- Update targets for all clients immediately so everyone sees the new target
    UpdateProspectingTargets(-1)
end

--- Inserts multiple prospecting targets from a list.
-- @param resource string The name of the resource adding the targets.
-- @param targets_list table A list of tables, each containing {x, y, z, data}.
function InsertProspectingTargets(resource, targets_list)
    for _, target in next, targets_list do
        InsertProspectingTarget(resource, target.x, target.y, target.z, target.data)
    end
    -- UpdateProspectingTargets(-1) is called by InsertProspectingTarget, so no need here.
end

--- Removes a prospecting target by its index.
-- This creates a new table to avoid issues with modifying table during iteration.
-- @param index integer The index of the target to remove from PROSPECTING_TARGETS.
function RemoveProspectingTarget(index)
    local new_targets = {}
    for n, target in next, PROSPECTING_TARGETS do
        if n ~= index then
            table.insert(new_targets, target)
        end
    end
    PROSPECTING_TARGETS = new_targets
    -- Update targets for all clients after removal
    UpdateProspectingTargets(-1)
end

--- Finds a matching pickup target based on approximate coordinates.
-- Used to verify collected targets, especially if client-side indexing might be off.
-- @param x number X coordinate to match.
-- @param y number Y coordinate to match.
-- @param z number Z coordinate to match.
-- @return integer | nil The index of the matching target, or nil if not found.
function FindMatchingPickup(x, y, z)
    for index, target in next, PROSPECTING_TARGETS do
        -- Use math.floor for approximate coordinate matching to account for floating point inaccuracies
        if math.floor(target.x) == math.floor(x) and math.floor(target.y) == math.floor(y) and math.floor(target.z) == math.floor(z) then
            return index
        end
    end
    return nil
end

--- Handles the collection of a prospecting target.
-- This function is called when a client successfully "digs" a target.
-- It verifies the target, removes it, and triggers the `onCollected` event.
-- @param player integer The source ID of the player who collected the target.
-- @param index integer The client-provided index of the target.
-- @param x number X coordinate of the collected target.
-- @param y number Y coordinate of the collected target.
-- @param z number Z coordinate of the collected target.
function HandleProspectingPickup(player, index, x, y, z)
    local target = PROSPECTING_TARGETS[index]
    if target then
        local dx, dy, dz = target.x, target.y, target.z
        local resource, data = target.resource, target.data
        -- Verify coordinates to prevent cheating/mismatch
        if math.floor(dx) == math.floor(x) and math.floor(dy) == math.floor(y) and math.floor(dz) == math.floor(z) then
            RemoveProspectingTarget(index)
            TriggerEvent("ts-prospecting:onCollected", player, resource, data, x, y, z)
        else
            -- If the provided index doesn't match, try to find a matching target by coordinates
            local newMatch = FindMatchingPickup(x, y, z)
            if newMatch then
                HandleProspectingPickup(player, newMatch, x, y, z)
            else
                -- Log or notify if no matching target found (could indicate an issue)
                print(string.format("Prospecting: Player %s tried to collect non-existent target at %s, %s, %s", player, x, y, z))
            end
        end
    else
        -- Log or notify if the target index was invalid
        print(string.format("Prospecting: Player %s tried to collect invalid target index %s", player, index))
    end
end

-- [[ Export Handling (for other resources to interact with this system) ]]

--- Adds a single prospecting target.
-- This is an export so other resources can add targets.
-- @param x number X coordinate.
-- @param y number Y coordinate.
-- @param z number Z coordinate.
-- @param data table Custom data for the target (e.g., {item = "gold", valuable = true, difficulty = 1.2}).
function AddProspectingTarget(x, y, z, data)
    local resource = GetInvokingResource()
    InsertProspectingTarget(resource, x, y, z, data)
end
-- Register a net event for client-side resources to add targets (though typically done server-side)
AddEventHandler("ts-prospecting:AddProspectingTarget", function(x, y, z, data)
    AddProspectingTarget(x, y, z, data)
end)

--- Adds multiple prospecting targets from a list.
-- This is an export so other resources can add targets in bulk.
-- @param list table A list of target tables.
function AddProspectingTargets(list)
    local resource = GetInvokingResource()
    InsertProspectingTargets(resource, list)
end
-- Register a net event for client-side resources to add targets (typically server-side)
AddEventHandler("ts-prospecting:AddProspectingTargets", function(list)
    AddProspectingTargets(list)
end)

--- Starts the prospecting activity for a given player.
-- @param player integer The source ID of the player.
function StartProspecting(player)
    if not PROSPECTING_STATUS[player] then
        TriggerClientEvent("ts-prospecting:forceStart", player)
    end
end
-- Register a net event for client-side to request starting prospecting
AddEventHandler("ts-prospecting:StartProspecting", function(player)
    StartProspecting(player)
end)

--- Stops the prospecting activity for a given player.
-- @param player integer The source ID of the player.
function StopProspecting(player)
    if PROSPECTING_STATUS[player] then
        TriggerClientEvent("ts-prospecting:forceStop", player)
    end
end
-- Register a net event for client-side to request stopping prospecting
AddEventHandler("ts-prospecting:StopProspecting", function(player)
    StopProspecting(player)
end)

--- Checks if a player is currently prospecting.
-- @param player integer The source ID of the player.
-- @return boolean True if prospecting, false otherwise.
function IsProspecting(player)
    return PROSPECTING_STATUS[player] ~= nil
end

--- Sets a difficulty modifier for the invoking resource.
-- This modifier will be applied to targets added by this resource
-- if no specific difficulty is provided in the target data itself.
-- @param modifier number The difficulty multiplier (e.g., 1.0 for normal, 2.0 for harder).
function SetDifficulty(modifier)
    local resource = GetInvokingResource()
    PROSPECTING_DIFFICULTIES[resource] = modifier
end

-- [[ Client Triggered Events ]]

-- Event handler for when a client explicitly stops prospecting.
RegisterServerEvent("ts-prospecting:userStoppedProspecting")
AddEventHandler("ts-prospecting:userStoppedProspecting", function()
    local player = source
    if PROSPECTING_STATUS[player] then
        local time = GetGameTimer() - PROSPECTING_STATUS[player]
        PROSPECTING_STATUS[player] = nil
        TriggerEvent("ts-prospecting:onStop", player, time) -- Custom handler for stop event
    end
end)

-- Event handler for when a client explicitly starts prospecting.
RegisterServerEvent("ts-prospecting:userStartedProspecting")
AddEventHandler("ts-prospecting:userStartedProspecting", function()
    local player = source
    if not PROSPECTING_STATUS[player] then
        PROSPECTING_STATUS[player] = GetGameTimer() -- Record start time
        TriggerEvent("ts-prospecting:onStart", player) -- Custom handler for start event
    end
end)

-- Event handler for when a client signals they have collected a node.
RegisterServerEvent("ts-prospecting:userCollectedNode")
AddEventHandler("ts-prospecting:userCollectedNode", function(index, x, y, z)
    local player = source
    if PROSPECTING_STATUS[player] then
        HandleProspectingPickup(player, index, x, y, z)
    end
end)

-- Event handler for when a client requests initial location data (on resource start).
RegisterServerEvent("ts-prospecting:userRequestsLocations")
AddEventHandler("ts-prospecting:userRequestsLocations", function()
    local player = source
    UpdateProspectingTargets(player)
end)

