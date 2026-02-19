---@diagnostic disable: duplicate-set-field
if GetResourceState('nn_departments') == 'missing' then return end
Dispatch = Dispatch or {}

Dispatch.SendAlert = function(data)
    local color = nil
    if data.vehicle then
        local r, g, b = GetVehicleColor(data.vehicle)
        color = {r, g, b}
    end
    local customData = {
        coords = data.coords or vector3(0.0, 0.0, 0.0),
        title = 'Alert '..(data.code or '10-80'),
        message = data.message,
        jobs = data.jobs or {'police'},
        metadata = {
            model = data.vehicle and (GetDisplayNameFromVehicleModel(GetEntityModel(data.vehicle))) or nil,
            color = color,
            plate = data.vehicle and GetVehicleNumberPlateText(data.vehicle) or nil,
            speed = data.vehicle and (GetEntitySpeed(data.vehicle) * 3.6)..' kmh' or nil
        }
    }

    exports['nn_departments']:SendAlert(customData)
end

return Dispatch