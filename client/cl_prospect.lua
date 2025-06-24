local prospecting = false

RegisterNetEvent("ts-prospecting:usedetector")
AddEventHandler("ts-prospecting:usedetector", function()
    if not prospecting then
        TriggerServerEvent("ts-prospecting:activateProspecting")
        prospecting = true
    else
        TriggerEvent("ts-prospecting:forceStop")
        prospecting = false
    end
end)
