---@diagnostic disable: duplicate-set-field
local resourceName = "qbx_vehiclekeys"
if GetResourceState(resourceName) == 'missing' then return end

VehicleKey = VehicleKey or {}

local function resolvePlate(vehicle, plate)
    if not plate or plate == '' then
        plate = GetVehicleNumberPlateText(vehicle)
    end
    return tostring(plate):match('^%s*(.-)%s*$')
end

---Gives the player (self) the keys of the specified vehicle.
---@param vehicle number The vehicle entity handle.
---@param plate? string The plate of the vehicle.
---@return nil
VehicleKey.GiveKeys = function(vehicle, plate)
    assert(vehicle, "vehicle is nil")
    assert(DoesEntityExist(vehicle), "vehicle does not exist")
    
    TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", resolvePlate(vehicle, plate))

    -- qbx rolls a random lock on the first entry attempt of a vehicle with no lock state
    if Entity(vehicle).state.doorslockstate == nil and NetworkGetEntityIsNetworked(vehicle) then
        local lockState = GetVehicleDoorLockStatus(vehicle) >= 2 and 2 or 1
        TriggerServerEvent("qb-vehiclekeys:server:setVehLockState", VehToNet(vehicle), lockState)
    end
end

---Removes the keys of the specified vehicle from the player (self).
---@param vehicle number The vehicle entity handle.
---@param plate? string The plate of the vehicle.
---@return nil
VehicleKey.RemoveKeys = function(vehicle, plate)
    assert(vehicle, "vehicle is nil")
    assert(DoesEntityExist(vehicle), "vehicle does not exist")
    
    TriggerEvent("qb-vehiclekeys:client:RemoveKeys", resolvePlate(vehicle, plate))
end

VehicleKey.GetResourceName = function()
    return resourceName
end

return VehicleKey