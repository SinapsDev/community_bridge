--- ox_lib compatibility wrapper for zone creation and management.
--- Provides a small API around lib.zones (box, sphere, poly) to create/destroy
--- and lookup zones with automatic id generation and resource ownership.
---
--- Example:
--- local id = cZones.Create("box", { coords = vec3(0,0,0), size = vec3(2,2,2), onEnter = function(z) ... end })
--- cZones.Destroy(id)
---
---@module cZones
---@class ZoneData
---@field id string Unique id for the zone (generated)
---@field invoking string Resource that created the zone
---@field coords vector3? Center coordinates (box/sphere)
---@field points vector2[]? Array of points for poly zones
---@field radius number? Radius for sphere zones
---@field size table? Size table or vec3 for box zones
---@field zone any Internal zone handle returned by lib.zones
---@field debug boolean? Debug flag passed to lib.zones
---@field onEnter fun(data:ZoneData)? Callback invoked on enter (receives ZoneData)
---@field onExit fun(data:ZoneData)? Callback invoked on exit (receives ZoneData)
---@alias ZoneType "box"|"sphere"|"poly"

---@diagnostic disable: duplicate-set-field
local resourceName = "ox_lib"
if GetResourceState(resourceName) == 'missing' then return end
if not lib then Require('init.lua', 'ox_lib') end
Ids = Ids or Require('lib/utility/shared/ids.lua')

cZones = {} --conflict with ox
cZones.All = {}

--- Create a zone of the specified type.
--- Supported types: "box", "sphere", "poly"
---@param type ZoneType
---@param data ZoneData
---@return string|nil id Returns the generated zone id on success, or nil on failure
function cZones.Create(type, data)
    assert(type, "Requires zone type ('box', 'sphere', or 'poly')")
    assert(data, "Requires data table")
    data.id = Ids.CreateUniqueId(cZones.All)
    data.invoking = GetInvokingResource() or "unknown"

    local onEnter = data.onEnter or data.OnEnter
    local onExit = data.onExit or data.OnExit
    local zone = nil
    if type == "box" then
        assert(data.coords, "Requires .coords as vector3 in data")
        local width = data.size?.x or data.length or 1.0
        local height = data.size?.y or data.width or 1.0
        local z = data.size?.z or data.height or 1.0
        zone = lib.zones.box({
            coords = data.coords,
            size = vec3(width, height, z),
            rotation = data.heading or data.rotation or 0.0,
            debug = data.debug or false,
            onEnter = function(point)
                if onEnter then
                    onEnter(data)
                end
            end,
            onExit = function(point)
                if onExit then
                    onExit(data)
                end
            end,
        })
        data.zone = zone
        cZones.All[data.id] = data
        return data.id
    elseif type == "sphere" then
        assert(data.coords, "Requires .coords as vector3 in data")
        data.radius = data.radius or data.size?.x or 1
        lib.zones.sphere(data)
        local zone = lib.zones.sphere({
            coords = data.coords,
            radius = data.radius,
            debug = data.debug or false,
            onEnter = function(point)
                data.zone = data.zone or point
                if onEnter then
                    onEnter(data)
                end
            end,
            onExit = function(point)
                data.zone = data.zone or point
                if onExit then
                    onExit(data)
                end
            end,
        })
        data.zone = zone
        cZones.All[data.id] = data
        return data.id
    elseif type == "poly" then
        assert(data.points, "Requires an array of vector2 in .points")
        assert(#data.points > 2, "Requires at least three points in .points")
        local zSize = data.minZ or data.size?.z or data.height or data.thickness or 2

        local polyZone = lib.zones.poly({
            points = data.points,
            thickness = zSize,
            debug = data.debug or false,
            onEnter = function(point)
                data.zone = data.zone or point
                if onEnter then
                    onEnter(data)
                end
            end,
            onExit = function(point)
                data.zone = data.zone or point
                if onExit then
                    onExit(data)
                end
            end,
        })
        data.zone = polyZone
        cZones.All[data.id] = data
        return data.id
    end
    return nil
end

--- Destroy a zone by id.
---@param id string
---@return boolean success True if destroyed, false otherwise
function cZones.Destroy(id)
    if not id then return false end
    local zone = cZones.All[id].zone
    if not zone then return false end
    zone:remove()
    cZones.All[id] = nil
    return true
end

--- Destroy all zones created by a specific resource.
---@param resource string Name of the invoking resource
---@return boolean success True if operation completed (no guarantee zones existed)
function cZones.DestroyByResource(resource)
    if not resource then return false end
    for id, zone in pairs(cZones.All or {}) do
        if zone.invoking == resource then
            zone.zone:remove()
        end
    end
    return true
end

--- Retrieve zone data by id.
---@param id string
---@return ZoneData|nil
function cZones.Get(id)
    if not id then return nil end
    return cZones.All[id]
end

--- Event handler: clean up zones when a resource stops.
--- This is registered to the "onResourceStop" event and delegates to DestroyByResource.
RegisterNetEvent("onResourceStop", function(resource)
    cZones.DestroyByResource(resource)
end)
