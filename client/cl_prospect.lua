local prospecting = false

RegisterNetEvent("ts-prospecting:usedetector")
AddEventHandler("ts-prospecting:usedetector", function()
    local pos = GetEntityCoords(PlayerPedId())

    -- Make sure the player is within the prospecting zone before they start
    local dist = #(pos - Config.base_location)
    if dist < Config.area_size then
        if not prospecting then
            TriggerServerEvent("ts-prospecting:activateProspecting")
            prospecting = true
        else
            TriggerEvent("ts-prospecting:forceStop")
            prospecting = false
        end
    end
end)
