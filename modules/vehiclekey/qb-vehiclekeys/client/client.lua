---@diagnostic disable: duplicate-set-field
local resourceName = "qb-vehiclekeys"
if GetResourceState(resourceName) == 'missing' then return end

VehicleKey = VehicleKey or {}

local function acquiresByNetId()
    local version = GetResourceMetadata(resourceName, "version", 0) or ""
    local major, minor = version:match("^(%d+)%.(%d+)")
    major, minor = tonumber(major) or 0, tonumber(minor) or 0
    return major > 1 or (major == 1 and minor >= 6)
end

---Gives the player (self) the keys of the specified vehicle.
---@param vehicle number The vehicle entity handle.
---@param plate? string The plate of the vehicle.
---@return nil
VehicleKey.GiveKeys = function(vehicle, plate)
    assert(vehicle, "vehicle is nil")
    assert(DoesEntityExist(vehicle), "vehicle does not exist")
    
    if not plate then
        plate = GetVehicleNumberPlateText(vehicle)
    end

    -- qb-vehiclekeys 1.6.0 takes the vehicle's network id (and checks the player
    -- stands near it); older versions take the plate.
    if acquiresByNetId() and NetworkGetEntityIsNetworked(vehicle) then
        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", NetworkGetNetworkIdFromEntity(vehicle))
        return
    end
    TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", plate)
end

---Removes the keys of the specified vehicle from the player (self).
---@param vehicle number The vehicle entity handle.
---@param plate? string The plate of the vehicle.
---@return nil
VehicleKey.RemoveKeys = function(vehicle, plate)
    assert(vehicle, "vehicle is nil")
    assert(DoesEntityExist(vehicle), "vehicle does not exist")
    
    if not plate then
        plate = GetVehicleNumberPlateText(vehicle)
    end

    TriggerEvent("qb-vehiclekeys:client:RemoveKeys", plate)
end

VehicleKey.GetResourceName = function()
    return resourceName
end

return VehicleKey