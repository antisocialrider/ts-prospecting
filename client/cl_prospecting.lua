-- ===========================================================================
-- Client-Side Prospecting Logic (Metal Detector Scanner)
-- This script handles animations, scanner feedback, and user interaction
-- with prospecting targets.
-- ===========================================================================

-- Global state variables for prospecting
local isProspecting = false
local pauseProspecting = false
local didCancelProspecting = false
local scannerState = "none" -- "none", "slow", "medium", "fast", "ultra"
local scannerFrametime = 0.0
local scannerScale = 0.0
local scannerAudio = true -- Toggle for scanner audio feedback
local isPickingUp = false -- Prevents multiple digging sequences

-- Local variables for scanner visual feedback (marker and audio)
local circleScale = 0.0 -- Used for pulsating marker effect
local circleScaleMultiplier = 1.5 -- Controls speed of marker growth
local renderCircle = false -- Whether to draw the marker
local scannerDistance = 0.0 -- Current distance to closest target
local closestTargetDifficulty = 1.0 -- Difficulty modifier from the closest target

-- ===========================================================================
-- Helper Functions: Animation and Model Management
-- ===========================================================================

--- Ensures an animation dictionary is loaded.
-- @param dict string The name of the animation dictionary.
function EnsureAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(0) -- Yield control, preventing high CPU usage
    end
end

--- Ensures a model is loaded.
-- @param model string The name of the model.
function EnsureModel(model)
    if not IsModelInCdimage(model) then
        -- Model not in game image, perhaps it's a custom stream?
        -- For now, we'll just log an error or assume it will load.
        -- In a real scenario, you might want to handle this more robustly.
        print(string.format("Prospecting: Model %s not found in CD image.", model))
        return false
    end

    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Citizen.Wait(0)
        end
    end
    return true
end

-- Stores the previously played animation to allow for stopping it cleanly.
local previousAnim = nil

--- Stops any currently playing animation on the ped.
-- @param ped integer The ped entity ID.
function StopAnim(ped)
    if previousAnim then
        StopEntityAnim(ped, previousAnim[2], previousAnim[1], true) -- Stop specific anim
        previousAnim = nil
    end
end

--- Plays an animation with specified flags.
-- @param ped integer The ped entity ID.
-- @param dict string The animation dictionary.
-- @param anim string The animation name.
-- @param flags integer Animation flags (e.g., 0 for normal, 49 for upper body).
function PlayAnimFlags(ped, dict, anim, flags)
    StopAnim(ped) -- Stop any previous animations
    EnsureAnimDict(dict)
    local len = GetAnimDuration(dict, anim)
    TaskPlayAnim(ped, dict, anim, 1.0, -1.0, len, flags, 1, 0, 0, 0)
    previousAnim = {dict, anim} -- Store current anim for later stopping
end

--- Plays an animation on the upper body.
-- @param ped integer The ped entity ID.
-- @param dict string The animation dictionary.
-- @param anim string The animation name.
function PlayAnimUpper(ped, dict, anim)
    PlayAnimFlags(ped, dict, anim, 49) -- Flag 49 for upper body animations
end

--- Plays a full-body animation.
-- @param ped integer The ped entity ID.
-- @param dict string The animation dictionary.
-- @param anim string The animation name.
function PlayAnim(ped, dict, anim)
    PlayAnimFlags(ped, dict, anim, 0) -- Flag 0 for full body animations
end

-- Offset data for attaching the metal detector model to the player's ped.
local entityOffsets = {
    ["w_am_metaldetector"] = { -- Assuming you're using this model, or specify another
		bone = 18905, -- Bone index for right hand / weapon attachment
        offset = vector3(0.15, 0.1, 0.0), -- Position offset relative to the bone
        rotation = vector3(270.0, 90.0, 80.0), -- Rotation offset
	},
}

-- Attached entity (the metal detector object)
local attachedEntities = {}
local scannerEntity = nil

--- Attaches a model (like the metal detector) to the player's ped.
-- @param ped integer The ped entity ID.
-- @param model string The model name to attach.
function AttachEntity(ped, model)
    if entityOffsets[model] then
        if EnsureModel(model) then -- Only proceed if model loads successfully
            local pos = GetEntityCoords(PlayerPedId())
            local ent = CreateObjectNoOffset(GetHashKey(model), pos.x, pos.y, pos.z, true, true, false)
            AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, entityOffsets[model].bone), entityOffsets[model].offset.x, entityOffsets[model].offset.y, entityOffsets[model].offset.z, entityOffsets[model].rotation.x, entityOffsets[model].rotation.y, entityOffsets[model].rotation.z, true, true, false, true, 2, true)
            scannerEntity = ent
            table.insert(attachedEntities, ent)
        end
    end
end

--- Cleans up attached models (detaches and deletes them).
function CleanupModels()
    for _, ent in next, attachedEntities do
        if DoesEntityExist(ent) then
            DetachEntity(ent, true, false)
            DeleteEntity(ent)
        end
    end
    attachedEntities = {}
    scannerEntity = nil
end

--- Handles the digging animation sequence with a progress bar.
-- @param cb function Callback function to execute after digging is complete.
function DigSequence(cb)
    CleanupModels() -- Detach scanner before digging animation
    local ped = PlayerPedId()
    StopEntityAnim(ped, "wood_idle_a", "mini@golfai", true) -- Stop prospecting idle anim
    
    -- Prevent multiple digging attempts simultaneously
    if not isPickingUp then
        isPickingUp = true
        Citizen.Wait(100) -- Small wait for state update

        -- Use scenario for digging animation
        TaskStartScenarioInPlace(ped, 'world_human_gardener_plant', 0, false)
        
        -- QBCore Progressbar for digging duration
        QBCore.Functions.Progressbar("prospect_digging", "Digging...", math.random(3000, 9000), false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() -- Done callback
            ClearPedTasks(ped)
            if cb then
                cb() -- Execute the callback (e.g., collect item)
            end
            AttachEntity(ped, "w_am_metaldetector") -- Re-attach scanner after digging
            isPickingUp = false
        end, function() -- Cancel callback
            ClearPedTasks(ped)
            AttachEntity(ped, "w_am_metaldetector") -- Re-attach scanner on cancel
            isPickingUp = false
            QBCore.Functions.Notify("Digging cancelled.", "error")
        end)
    end
end

-- ===========================================================================
-- Target Management and Collection
-- ===========================================================================

-- Target pool updated by server
-- Format: { {x, y, z, difficulty}, ... }
local targetPool = {}

-- Max range for targets to be considered by the client for proximity checks.
-- This limits the number of targets the client has to constantly process.
local maxTargetRange = 200.0

-- Actual targets currently within range that the client processes
-- Format: { {vector3_pos, difficulty_modifier, original_server_index}, ... }
local targets = {}


--- Event handler for updating the client's target pool.
-- Received from the server via `UpdateProspectingTargets`.
-- @param pool table A list of tables, each containing {x, y, z, difficulty}.
RegisterNetEvent("ts-prospecting:setTargetPool")
AddEventHandler("ts-prospecting:setTargetPool", function(pool)
    targetPool = {} -- Clear existing pool
    for n, data in ipairs(pool) do
        -- Store position as vector3 and difficulty. 'n' is the original server index.
        table.insert(targetPool, {vector3(data.x, data.y, data.z), data.difficulty, n})
    end
end)


--- Finds the closest prospecting target to a given position.
-- @param pos vector3 The position to check from.
-- @return table The closest target data ({vector3_pos, difficulty_modifier, original_server_index})
-- @return number The distance to the closest target.
-- @return integer The original server index of the closest target.
-- @return number The difficulty modifier of the closest target.
function getClosestTarget(pos)
    local closest, index, closestdist, difficulty
    for n, target in next, targets do
        local dist = #(pos.xy - target[1].xy) -- Calculate 2D distance
        if (not closest) or closestdist > dist then
            closestdist = dist
            index = target[3] -- Use the original server index
            closest = target
            difficulty = target[2] -- Store the difficulty from the target data
        end
    end
    -- Return 0,0,0 if no targets within range, otherwise closest target details
    return closest or vector3(0.0, 0.0, 0.0), closestdist, index, difficulty or 1.0
end

--- Initiates the digging sequence for a target.
-- @param index integer The original server index of the target to dig.
function DigTarget(index)
    pauseProspecting = true -- Pause scanner feedback while digging
    
    -- Find and remove the target locally before telling server
    local localIndexToRemove = nil
    for i, target in ipairs(targets) do
        if target[3] == index then -- Match by original server index
            localIndexToRemove = i
            break
        end
    end

    if localIndexToRemove then
        local target = table.remove(targets, localIndexToRemove) -- Remove from local client list
        local pos = target[1] -- Position of the collected target

        DigSequence(function()
            -- After digging animation, inform the server that the node was collected
            TriggerServerEvent("ts-prospecting:userCollectedNode", index, pos.x, pos.y, pos.z)
        end)
    else
        QBCore.Functions.Notify("Error: Target to dig not found locally.", "error")
    end
    
    scannerState = "none" -- Reset scanner state
    -- pauseProspecting is reset after DigSequence's completion callback
end

--- Stops the prospecting activity and cleans up client-side effects.
function StopProspecting()
    if not didCancelProspecting then
        didCancelProspecting = true
        CleanupModels() -- Detach and delete metal detector model
        local ped = PlayerPedId()
        StopEntityAnim(ped, "wood_idle_a", "mini@golfai", true) -- Stop prospecting idle anim
        
        -- Reset scanner feedback variables
        circleScale = 0.0
        scannerScale = 0.0
        scannerState = "none"
        
        isProspecting = false -- Set global state to stopped
        TriggerServerEvent("ts-prospecting:userStoppedProspecting") -- Inform server
    end
end

--- Event handler for resource stop, ensures cleanup.
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        CleanupModels()
        StopProspecting()
    end
end)

--- Starts the prospecting activity if not already active.
function StartProspecting()
    if not isProspecting then
        ProspectingThreads() -- Begin the prospecting loops
    end
end

--- Force start prospecting (e.g., via server command).
RegisterNetEvent("ts-prospecting:forceStart")
AddEventHandler("ts-prospecting:forceStart", function()
    StartProspecting()
end)

--- Force stop prospecting (e.g., via server command).
RegisterNetEvent("ts-prospecting:forceStop")
AddEventHandler("ts-prospecting:forceStop", function()
    isProspecting = false -- This will break the while loop in ProspectingThreads, triggering StopProspecting
end)

-- Request initial locations from the server on resource start
CreateThread(function()
    Citizen.Wait(1000) -- Small delay to ensure everything is ready
    TriggerServerEvent("ts-prospecting:userRequestsLocations")
end)

-- ===========================================================================
-- Core Prospecting Threads
-- ===========================================================================

--- Main function to start client-side prospecting threads.
function ProspectingThreads()
    if isProspecting then return false end -- Prevent multiple instances
    
    TriggerServerEvent("ts-prospecting:userStartedProspecting") -- Inform server
    isProspecting = true
    didCancelProspecting = false
    pauseProspecting = false

    -- Thread 1: Main Prospecting Logic (Animations, Target Detection, User Input)
    CreateThread(function()
        AttachEntity(PlayerPedId(), "w_am_metaldetector") -- Attach the metal detector model
        
        while isProspecting do
            Citizen.Wait(0) -- Yield control frequently

            local ped = PlayerPedId()
            local ply = PlayerId()
            local canProspect = true -- Flag to determine if prospecting can occur

            -- Keep playing the prospecting idle animation if not already playing
            if not IsEntityPlayingAnim(ped, "mini@golfai", "wood_idle_a", 3) then
                PlayAnimUpper(ped, "mini@golfai", "wood_idle_a")
            end

            -- Actions that halt prospecting animations and scanner feedback
            local restrictedMovement = false
            restrictedMovement = restrictedMovement or IsPedFalling(ped)
            restrictedMovement = restrictedMovement or IsPedJumping(ped)
            restrictedMovement = restrictedMovement or IsPedSprinting(ped)
            restrictedMovement = restrictedMovement or IsPedRunning(ped)
            restrictedMovement = restrictedMovement or IsPlayerFreeAiming(ply)
            restrictedMovement = restrictedMovement or IsPedRagdoll(ped)
            restrictedMovement = restrictedMovement or IsPedInAnyVehicle(ped)
            restrictedMovement = restrictedMovement or IsPedInCover(ped)
            restrictedMovement = restrictedMovement or IsPedInMeleeCombat(ped)
            restrictedMovement = restrictedMovement or IsPedOnBike(ped)
            restrictedMovement = restrictedMovement or IsPedOnFoot(ped) == false -- If not on foot

            if restrictedMovement then canProspect = false end
            
            if canProspect and not pauseProspecting then
                -- Get position for scanner detection (slightly in front of the ped)
                local pedCoords = GetEntityCoords(ped)
                local forwardVector = GetEntityForwardVector(ped)
                -- Offset the detection point to be where the detector would be
                local pos = pedCoords + (forwardVector * 0.75) - vector3(0.0, 0.0, 0.75) 

                local target, dist, index, targetDifficulty = getClosestTarget(pos)
                closestTargetDifficulty = targetDifficulty or 1.0 -- Update global difficulty for renderer

                if index then -- If a target is found
                    -- Apply the target's difficulty to the distance check
                    local effectiveDist = dist * closestTargetDifficulty 

                    if effectiveDist < 3.0 then -- Close enough to dig
                        if IsDisabledControlJustPressed(0, 54) then -- E key for interaction (or context action)
                            DigTarget(index)
                        end
                        scannerState = "ultra" -- Strongest signal
                    else
                        -- Not close enough to dig, but within scanner range
                        if IsDisabledControlJustPressed(0, 54) then
                            QBCore.Functions.Notify("You're too far away from the signal to dig!", "error")
                        end

                        -- Adjust scanner state based on effective distance
                        if effectiveDist < 4.0 then
                            scannerFrametime = 0.35 -- Faster pulse
                            scannerScale = 4.50 -- Larger marker growth
                            scannerState = "fast"
                        elseif effectiveDist < 5.0 then
                            scannerFrametime = 0.4
                            scannerScale = 3.75
                            scannerState = "fast"
                        elseif effectiveDist < 6.5 then
                            scannerFrametime = 0.425
                            scannerScale = 3.00
                            scannerState = "fast"
                        elseif effectiveDist < 7.5 then
                            scannerFrametime = 0.45
                            scannerScale = 2.50
                            scannerState = "fast"
                        elseif effectiveDist < 10.0 then
                            scannerFrametime = 0.5
                            scannerScale = 1.75
                            scannerState = "fast"
                        elseif effectiveDist < 12.5 then
                            scannerFrametime = 0.75
                            scannerScale = 1.25
                            scannerState = "medium"
                        elseif effectiveDist < 15.0 then
                            scannerFrametime = 1.0
                            scannerScale = 1.00
                            scannerState = "medium"
                        elseif effectiveDist < 20.0 then
                            scannerFrametime = 1.25
                            scannerScale = 0.875
                            scannerState = "medium"
                        elseif effectiveDist < 25.0 then
                            scannerFrametime = 1.5
                            scannerScale = 0.75
                            scannerState = "slow"
                        elseif effectiveDist < 30.0 then
                            scannerFrametime = 2.0
                            scannerScale = 0.5
                            scannerState = "slow"
                        else
                            scannerState = "none" -- No signal
                        end
                    end
                    scannerDistance = dist -- Keep actual distance for potential debug/UI
                else
                    scannerState = "none" -- No target in range
                end
            else
                -- Ped is busy or prospecting is paused, reset scanner feedback
                StopEntityAnim(ped, "wood_idle_a", "mini@golfai", true)
                scannerState = "none"
            end

            -- If prospecting was stopped mid-frame, clean up
            if not isProspecting then
                CleanupModels()
                StopEntityAnim(ped, "wood_idle_a", "mini@golfai", true)
                scannerState = "none"
                break -- Exit the loop
            end
        end
        StopProspecting() -- Final cleanup and inform server on loop exit
    end)

    -- Thread 2: Marker Rendering and Audio Feedback
    CreateThread(function()
        local framecount = 0
        local frametime = 0.0 -- Time accumulator for pulse
        
        while isProspecting do
            Citizen.Wait(0) -- Yield control

            if not pauseProspecting then
                local ped = PlayerPedId()
                local pedCoords = GetEntityCoords(ped)
                local forwardVector = GetEntityForwardVector(ped)
                local pos = pedCoords + (forwardVector * 0.75) - vector3(0.0, 0.0, 0.75) 

                renderCircle = true -- Assume we want to render unless explicitly none

                -- Adjust marker and audio based on scanner state
                if scannerState == "none" then
                    renderCircle = false
                    circleScale = 0.0
                elseif scannerState == "ultra" then
                    -- Strongest signal, rapid sound, no marker pulse or very small static one
                    renderCircle = false -- No large marker pulse for "ultra"
                    if frametime > 0.125 then -- Very fast pulse rate for ultra
                        frametime = 0.0
                        if scannerAudio then PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0) end
                        -- Example of a second, more intense sound for ultra
                        if scannerAudio then PlaySoundFrontend(-1, "BOATS_PLANES_HELIS_BOOM", "MP_LOBBY_SOUNDS", 0) end
                    end
                else -- "slow", "medium", "fast" states will have a pulsating marker
                    circleScale = circleScale + (GetFrameTime() * scannerScale * 100.0) -- Scale grows based on frame time and scannerScale
                    if frametime > scannerFrametime then
                        frametime = 0.0
                        if scannerAudio then PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0) end
                    end

                    -- Marker color and alpha
                    local circleR, circleG, circleB = 255, 255, 0 -- Yellowish color
                    local alpha = math.floor(255 - ((circleScale % 100) / 100) * 255) -- Alpha fades out as scale grows
                    local size = (circleScale % 100) / 100 * 1.5 -- Scale from 0 to 1.5

                    -- Draw the marker (Type 1 is a simple cylinder)
                    DrawMarker(1, pos.x, pos.y, pos.z - 0.98, -- Position slightly below ground
                            0.0, 0.0, 0.0, -- Rotation
                            0.0, 0.0, 0.0, -- Rotation
                            size, size, 0.1, -- Scale (x, y, z)
                            circleR, circleG, circleB, alpha, -- Color (R, G, B, A)
                            false, false, 2, false, nil, nil, false)
                end
                
                -- Reset circleScale if it exceeds 100 to loop the pulse
                if circleScale > 100 then
                    circleScale = circleScale % 100
                    -- Play initial sound for new pulse cycle if not ultra
                    if scannerState ~= "ultra" and scannerAudio then 
                        PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", 0) 
                    end
                end

                frametime = frametime + GetFrameTime() -- Accumulate frame time
            end
        end
    end)

    -- Thread 3: Location Updater (Fetches nearby targets from the global pool)
    CreateThread(function()
        while isProspecting do
            local pedPos = GetEntityCoords(PlayerPedId())
            local newTargets = {}
            for n, targetData in next, targetPool do
                -- targetData: {vector3_pos, difficulty_modifier, original_server_index}
                local targetPos = targetData[1]
                if #(pedPos.xy - targetPos.xy) < maxTargetRange then
                    table.insert(newTargets, targetData)
                end
            end
            targets = newTargets -- Update the client's active targets list
            Citizen.Wait(5000) -- Update nearby targets every 5 seconds
        end
    end)
    return true
end
