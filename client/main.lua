local QBCore = exports['qb-core']:GetCoreObject()

local CONTROL_FRONTEND_RRIGHT = 54

local ANIM_FLAG_NORMAL = 0
local ANIM_FLAG_UPPER_BODY = 49

local SCANNER_STATE_NONE = "none"
local SCANNER_STATE_SLOW = "slow"
local SCANNER_STATE_MEDIUM = "medium"
local SCANNER_STATE_FAST = "fast"
local SCANNER_STATE_ULTRA = "ultra"

local ProspectingClientState = {
    isProspecting = false,
    pauseProspecting = false,
    didCancelProspecting = false,
    scannerState = SCANNER_STATE_NONE,
    scannerFrametime = 0.0,
    scannerScale = 0.0,
    scannerAudio = true,
    isPickingUp = false,
    circleScale = 0.0,
    circleScaleMultiplier = 1.5,
    renderCircle = false,
    scannerDistance = 0.0,
    closestTargetDifficulty = 1.0,
}

local previousAnim = nil
local targetPool = {}
local maxTargetRange = 200.0
local targets = {}

function EnsureAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(0)
    end
end

function EnsureModel(model)
    if not IsModelInCdimage(model) then
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

function StopAnim(ped)
    if previousAnim then
        StopEntityAnim(ped, previousAnim[2], previousAnim[1], 1)
        previousAnim = nil
    end
end

function PlayAnimFlags(ped, dict, anim, flags)
    StopAnim(ped)
    EnsureAnimDict(dict)
    local len = GetAnimDuration(dict, anim)
    TaskPlayAnim(ped, dict, anim, 1.0, -1.0, len, flags, 1, false, false, false)
    previousAnim = {dict, anim}
end

function PlayAnimUpper(ped, dict, anim)
    PlayAnimFlags(ped, dict, anim, ANIM_FLAG_UPPER_BODY)
end

function PlayAnim(ped, dict, anim)
    PlayAnimFlags(ped, dict, anim, ANIM_FLAG_NORMAL)
end

local entityOffsets = {
    ["prop_metaldetector"] = {
		bone = 18905,
        offset = vector3(0.15, 0.1, 0.0),
        rotation = vector3(270.0, 90.0, 80.0),
	},
    ["prop_tool_shovel"] = {
        bone = 28422,
        offset = vector3(0.0, 0.0, 0.24),
        rotation = vector3(0.0, 0.0, 0.0),
    },
    ["prop_ld_shovel_dirt"] = {
        bone = 28422,
        offset = vector3(0.0, 0.0, 0.24),
        rotation = vector3(0.0, 0.0, 0.0),
    },
}

local attachedEntities = {}
local scannerEntity = nil

function AttachEntity(ped, model)
    if entityOffsets[model] then
        if EnsureModel(model) then
            local pos = GetEntityCoords(PlayerPedId())
            local ent = CreateObjectNoOffset(GetHashKey(model), pos.x, pos.y, pos.z, true, true, false)
            AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, entityOffsets[model].bone), entityOffsets[model].offset.x, entityOffsets[model].offset.y, entityOffsets[model].offset.z, entityOffsets[model].rotation.x, entityOffsets[model].rotation.y, entityOffsets[model].rotation.z, true, true, false, true, 2, true)
            scannerEntity = ent
            table.insert(attachedEntities, ent)
        end
    end
end

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

function DigSequence(cb)
    CleanupModels()

    local ped = PlayerPedId()
    StopEntityAnim(ped, "wood_idle_a", "mini@golfai", 1)
    
    if not ProspectingClientState.isPickingUp then
        ProspectingClientState.isPickingUp = true
        Citizen.Wait(100)

        AttachEntity(ped, "prop_tool_shovel")
        AttachEntity(ped, "prop_ld_shovel_dirt")

        local animDictBurial = 'random@burial'
        RequestAnimDict(animDictBurial)
        while not HasAnimDictLoaded(animDictBurial) do
            Wait(0)
        end

        TaskPlayAnim(ped, animDictBurial, 'a_burial', 1.0, -1.0, -1, 48, 0, false, false, false)

        QBCore.Functions.Progressbar("prospect_digging", "Digging...", math.random(3000, 9000), false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            ClearPedTasks(ped)
            if cb then
                cb()
            end
            CleanupModels()
            RemoveAnimDict('random@burial')
            AttachEntity(ped, "prop_metaldetector")
            ProspectingClientState.isPickingUp = false
        end, function()
            ClearPedTasks(ped)
            CleanupModels()
            RemoveAnimDict('random@burial')
            AttachEntity(ped, "prop_metaldetector")
            ProspectingClientState.isPickingUp = false
            QBCore.Functions.Notify("Digging cancelled.", "error")
        end)
    end
end

RegisterNetEvent("ts-prospecting:client:setTargetPool")
AddEventHandler("ts-prospecting:client:setTargetPool", function(pool)
    targetPool = {}
    for n, data in ipairs(pool) do
        table.insert(targetPool, {vector3(data.x, data.y, data.z), data.difficulty, n})
    end
end)

function GetClosestTarget(pos)
    local closest, index, closestdist, difficulty
    for n, target in next, targets do
        local dist = #(pos.xy - target[1].xy)
        if (not closest) or closestdist > dist then
            closestdist = dist
            index = target[3]
            closest = target
            difficulty = target[2]
        end
    end
    return closest or vector3(0.0, 0.0, 0.0), closestdist, index, difficulty or 1.0
end

function DigTarget(index)
    ProspectingClientState.pauseProspecting = true
    
    local localIndexToRemove = nil
    for i, target in ipairs(targets) do
        if target[3] == index then
            localIndexToRemove = i
            break
        end
    end

    if localIndexToRemove then
        local target = table.remove(targets, localIndexToRemove)
        local pos = target[1]

        DigSequence(function()
            TriggerServerEvent("ts-prospecting:server:userCollectedNode", index, pos.x, pos.y, pos.z)
        end)
    else
        QBCore.Functions.Notify("Error: Target to dig not found locally.", "error")
    end
    
    ProspectingClientState.scannerState = SCANNER_STATE_NONE
end

function StopProspecting()
    if not ProspectingClientState.didCancelProspecting then
        ProspectingClientState.didCancelProspecting = true
        CleanupModels()
        local ped = PlayerPedId()
        StopEntityAnim(ped, "wood_idle_a", "mini@golfai", 1)
        
        ProspectingClientState.circleScale = 0.0
        ProspectingClientState.scannerScale = 0.0
        ProspectingClientState.scannerState = SCANNER_STATE_NONE
        
        ProspectingClientState.isProspecting = false
        TriggerServerEvent("ts-prospecting:server:userStoppedProspecting")
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        CleanupModels()
        StopProspecting()
    end
end)

function StartProspecting()
    if not ProspectingClientState.isProspecting then
        ProspectingThreads()
    end
end

RegisterNetEvent("ts-prospecting:client:forceStart")
AddEventHandler("ts-prospecting:client:forceStart", function()
    StartProspecting()
end)

RegisterNetEvent("ts-prospecting:client:forceStop")
AddEventHandler("ts-prospecting:client:forceStop", function()
    ProspectingClientState.isProspecting = false
end)

CreateThread(function()
    Citizen.Wait(1000)
    TriggerServerEvent("ts-prospecting:server:userRequestsLocations")
end)

function ProspectingThreads()
    if ProspectingClientState.isProspecting then return false end
    
    TriggerServerEvent("ts-prospecting:server:userStartedProspecting")
    ProspectingClientState.isProspecting = true
    ProspectingClientState.didCancelProspecting = false
    ProspectingClientState.pauseProspecting = false

    CreateThread(function()
        AttachEntity(PlayerPedId(), "prop_metaldetector")
        
        while ProspectingClientState.isProspecting do
            Citizen.Wait(5)

            local ped = PlayerPedId()
            local ply = PlayerId()
            local canProspect = true

            if not IsEntityPlayingAnim(ped, "mini@golfai", "wood_idle_a", 3) then
                PlayAnimUpper(ped, "mini@golfai", "wood_idle_a")
            end

            local restrictedMovement = false
            restrictedMovement = restrictedMovement or IsPedFalling(ped)
            restrictedMovement = restrictedMovement or IsPedJumping(ped)
            restrictedMovement = restrictedMovement or IsPedSprinting(ped)
            restrictedMovement = restrictedMovement or IsPedRunning(ped)
            restrictedMovement = restrictedMovement or IsPlayerFreeAiming(ply)
            restrictedMovement = restrictedMovement or IsPedRagdoll(ped)
            restrictedMovement = restrictedMovement or IsPedInAnyVehicle(ped, false)
            restrictedMovement = restrictedMovement or IsPedInCover(ped, false)
            restrictedMovement = restrictedMovement or IsPedInMeleeCombat(ped)
            restrictedMovement = restrictedMovement or IsPedOnAnyBike(ped)
            restrictedMovement = restrictedMovement or IsPedOnFoot(ped) == false

            if restrictedMovement then canProspect = false end
            
            if canProspect and not ProspectingClientState.pauseProspecting then
                local pedCoords = GetEntityCoords(ped)
                local forwardVector = GetEntityForwardVector(ped)
                local pos = pedCoords + (forwardVector * 0.75) - vector3(0.0, 0.0, 0.75) 

                local target, dist, index, targetDifficulty = GetClosestTarget(pos)
                ProspectingClientState.closestTargetDifficulty = targetDifficulty or 1.0

                if index then
                    local effectiveDist = dist * ProspectingClientState.closestTargetDifficulty 

                    if effectiveDist < 3.0 then
                        if IsDisabledControlJustPressed(0, CONTROL_FRONTEND_RRIGHT) then
                            DigTarget(index)
                        end
                        ProspectingClientState.scannerState = SCANNER_STATE_ULTRA
                    else
                        if IsDisabledControlJustPressed(0, CONTROL_FRONTEND_RRIGHT) then
                            QBCore.Functions.Notify("You're too far away from the signal to dig!", "error")
                        end

                        if effectiveDist < 4.0 then
                            ProspectingClientState.scannerFrametime = 0.35
                            ProspectingClientState.scannerScale = 4.50
                            ProspectingClientState.scannerState = SCANNER_STATE_FAST
                        elseif effectiveDist < 5.0 then
                            ProspectingClientState.scannerFrametime = 0.4
                            ProspectingClientState.scannerScale = 3.75
                            ProspectingClientState.scannerState = SCANNER_STATE_FAST
                        elseif effectiveDist < 6.5 then
                            ProspectingClientState.scannerFrametime = 0.425
                            ProspectingClientState.scannerScale = 3.00
                            ProspectingClientState.scannerState = SCANNER_STATE_FAST
                        elseif effectiveDist < 7.5 then
                            ProspectingClientState.scannerFrametime = 0.45
                            ProspectingClientState.scannerScale = 2.50
                            ProspectingClientState.scannerState = SCANNER_STATE_FAST
                        elseif effectiveDist < 10.0 then
                            ProspectingClientState.scannerFrametime = 0.5
                            ProspectingClientState.scannerScale = 1.75
                            ProspectingClientState.scannerState = SCANNER_STATE_FAST
                        elseif effectiveDist < 12.5 then
                            ProspectingClientState.scannerFrametime = 0.75
                            ProspectingClientState.scannerScale = 1.25
                            ProspectingClientState.scannerState = SCANNER_STATE_MEDIUM
                        elseif effectiveDist < 15.0 then
                            ProspectingClientState.scannerFrametime = 1.0
                            ProspectingClientState.scannerScale = 1.00
                            ProspectingClientState.scannerState = SCANNER_STATE_MEDIUM
                        elseif effectiveDist < 20.0 then
                            ProspectingClientState.scannerFrametime = 1.25
                            ProspectingClientState.scannerScale = 0.875
                            ProspectingClientState.scannerState = SCANNER_STATE_MEDIUM
                        elseif effectiveDist < 25.0 then
                            ProspectingClientState.scannerFrametime = 1.5
                            ProspectingClientState.scannerScale = 0.75
                            ProspectingClientState.scannerState = SCANNER_STATE_SLOW
                        elseif effectiveDist < 30.0 then
                            ProspectingClientState.scannerFrametime = 2.0
                            ProspectingClientState.scannerScale = 0.5
                            ProspectingClientState.scannerState = SCANNER_STATE_SLOW
                        else
                            ProspectingClientState.scannerState = SCANNER_STATE_NONE
                        end
                    end
                    ProspectingClientState.scannerDistance = dist
                else
                    ProspectingClientState.scannerState = SCANNER_STATE_NONE
                end
            else
                StopEntityAnim(ped, "wood_idle_a", "mini@golfai", 1)
                ProspectingClientState.scannerState = SCANNER_STATE_NONE
            end

            if not ProspectingClientState.isProspecting then
                CleanupModels()
                StopEntityAnim(ped, "wood_idle_a", "mini@golfai", 1)
                ProspectingClientState.scannerState = SCANNER_STATE_NONE
                break
            end
        end
        StopProspecting()
    end)

    CreateThread(function()
        local framecount = 0
        local frametime = 0.0
        
        while ProspectingClientState.isProspecting do
            Citizen.Wait(1)

            if not ProspectingClientState.pauseProspecting then
                local ped = PlayerPedId()
                local pedCoords = GetEntityCoords(ped)
                local forwardVector = GetEntityForwardVector(ped)
                local pos = pedCoords + (forwardVector * 0.75) - vector3(0.0, 0.0, 0.75) 

                ProspectingClientState.renderCircle = true

                if ProspectingClientState.scannerState == SCANNER_STATE_NONE then
                    ProspectingClientState.renderCircle = false
                    ProspectingClientState.circleScale = 0.0
                elseif ProspectingClientState.scannerState == SCANNER_STATE_ULTRA then
                    ProspectingClientState.renderCircle = false
                    if frametime > 0.125 then
                        frametime = 0.0
                        if ProspectingClientState.scannerAudio then PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", false) end
                        if ProspectingClientState.scannerAudio then PlaySoundFrontend(-1, "BOATS_PLANES_HELIS_BOOM", "MP_LOBBY_SOUNDS", false) end
                    end
                else
                    ProspectingClientState.circleScale = ProspectingClientState.circleScale + (GetFrameTime() * ProspectingClientState.scannerScale * 100.0)
                    if frametime > ProspectingClientState.scannerFrametime then
                        frametime = 0.0
                        if ProspectingClientState.scannerAudio then PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", false) end
                    end

                    local circleR, circleG, circleB = 255, 255, 0
                    local alpha = math.floor(255 - ((ProspectingClientState.circleScale % 100) / 100) * 255)
                    local size = (ProspectingClientState.circleScale % 100) / 100 * 1.5

                    DrawMarker(1, pos.x, pos.y, pos.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 0.1, circleR, circleG, circleB, alpha, false, false, 2, false, 'nil', 'nil', false)
                end

                if ProspectingClientState.circleScale > 100 then
                    ProspectingClientState.circleScale = ProspectingClientState.circleScale % 100
                    if ProspectingClientState.scannerState ~= SCANNER_STATE_ULTRA and ProspectingClientState.scannerAudio then 
                        PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", false) 
                    end
                end

                frametime = frametime + GetFrameTime()
            end
        end
    end)

    CreateThread(function()
        while ProspectingClientState.isProspecting do
            local pedPos = GetEntityCoords(PlayerPedId())
            local newTargets = {}
            for n, targetData in next, targetPool do
                local targetPos = targetData[1]
                if #(pedPos.xy - targetPos.xy) < maxTargetRange then
                    table.insert(newTargets, targetData)
                end
            end
            targets = newTargets
            Citizen.Wait(5000)
        end
    end)
    return true
end

local prospecting = false
RegisterNetEvent("ts-prospecting:client:usedetector")
AddEventHandler("ts-prospecting:client:usedetector", function()
    if not prospecting then
        TriggerServerEvent("ts-prospecting:server:activateProspecting")
        prospecting = true
    else
        TriggerEvent("ts-prospecting:client:forceStop")
        prospecting = false
    end
end)