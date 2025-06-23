-- Prospecting interface table
Prospecting = {}
-- Reference to the main ts-prospecting export functions
prospecting = exports['ts-prospecting']

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
