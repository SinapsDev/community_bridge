---@diagnostic disable: duplicate-set-field
Target = Target or {}
Ids = Ids or Require("lib/utility/shared/ids.lua")

-- global so a second load of this file (Require of modules/target/_default/init.lua) keeps the ids already handed out
TargetInteractIds = TargetInteractIds or {}
local InteractIds = TargetInteractIds

local function warnUser()
    print("Currently Only Targeting Is Supported By Community Bridge, You Are Using A Resource That Requires The Target Module To Be Used.")
end

function Target.GetResourceName()
    return "default"
end

function Target.GetCanInteract(id)
    return InteractIds[id]
end

function Target.CreateCanInteract(cb)
    if not cb then return end
    local id = Ids.CreateUniqueId(InteractIds)
    InteractIds[id] = {
        id = id,
        ableToInteract = -1,
        onInteract = cb
    }
    return id
end

-- the result is cached for 1 s per option and per entity, so one player's result never shows on another
function Target.CanInteract(id, entity, ...)
    local interactData = InteractIds[id]
    if not interactData then return false end
    local now = GetGameTimer()
    if interactData.ableToInteract == -1 or interactData.entity ~= entity or now >= interactData.expires then
        local canInteractStatus = interactData.onInteract(entity, ...)
        interactData.ableToInteract = canInteractStatus and 1 or 0
        interactData.entity = entity
        interactData.expires = now + 1000
    end
    return interactData.ableToInteract > 0
end

function Target.FixOptions(options)
    for k, v in pairs(options) do
        local action = v.onSelect or v.action
        local select = function(entityOrData)
            if type(entityOrData) == 'table' then
                return action(entityOrData.entity)
            end
            return action(entityOrData)
        end
        options[k].onSelect = select
        local optionsCanInteract = v.canInteract
        if optionsCanInteract then 
            local id = Target.CreateCanInteract(optionsCanInteract)
            v.canInteract = function(...)
                return Target.CanInteract(id, ...)
            end
        end
    end
    return options
end

function Target.AddGlobalPlayer(options)
    warnUser()
end

function Target.AddGlobalVehicle(options)
    warnUser()
end

function Target.RemoveGlobalVehicle(options)
    warnUser()
end

function Target.AddLocalEntity(entities, _options)
    local fixedOptions = Target.FixOptions(_options)
    if type(entities) == "string" or type(entities) == "number" then
        entities = { entities }
    end
    for _, entity in pairs(entities) do
        local id = Ids.RandomString()
        local title =  Language.Locale("target.title")
        local menuData = { id = id, title = title, options = {} }
        for k, v in pairs(fixedOptions) do
            table.insert(menuData.options, {
                title = title .. " " .. k,
                description = Language.Locale("target.description"),
                onSelect = function(selected, secondary, args)
                    if v.onSelect then
                        v.onSelect(selected, secondary, args)
                    end
                end
            })
        end
        Point.Register(id, entity, 5, nil, function()
            local coords = GetEntityCoords(entity)
            local sleep = 3000
            local test = Language.Locale("target.interact")
            CreateThread(function()
                while DoesEntityExist(entity) do
                    Wait(sleep)
                    local distance = #(coords - GetEntityCoords(PlayerPedId()))
                    if distance < 2 then
                        sleep = 0
                        Utility.Draw3DHelpText(coords, test, 0.35)
                        if IsControlJustPressed(0, 38) then
                            Menu.Open(menuData, false)
                        end
                    else
                        sleep = 1000
                    end
                end
            end)
        end,
        function()
            Point.Remove(id)
        end, function()
            --No need for this in this one
        end)
    end
end

function Target.AddModel(models, options)
    warnUser()
end

function Target.AddBoxZone(name, coords, size, heading, options)
    local fixedOptions = Target.FixOptions(options)
    local id = Ids.RandomString()
    local title =  Bridge.Language.Locale("target.title")
    local menuData = { id = id, title = title, options = {} }
    for k, v in pairs(fixedOptions) do
        table.insert(menuData.options, {
            title = title .. " " .. k,
            description = Bridge.Language.Locale("target.description"),
            onSelect = function(selected, secondary, args)
                if v.onSelect then
                    v.onSelect(selected, secondary, args)
                end
            end
        })
    end
    local inZone = false
    Point.Register(id, coords, 5, nil,
    function()
        local sleep = 3000
        while inZone do
            Wait(sleep)
            local distance = #(coords - GetEntityCoords(PlayerPedId()))
            if distance < 10 then
                sleep = 0
                Utility.Draw3DHelpText(coords, Bridge.Language.Locale("target.interact"), 0.35)
                if IsControlJustPressed(0, 38) then
                    Menu.Open(menuData, false)
                end
            end
        end
    end,
    function()
        inZone = false
        Point.Remove(id)
    end, 
    function()
        --No need for this in this one
    end)
end

function Target.RemoveGlobalPlayer()
    warnUser()
end

function Target.RemoveLocalEntity(entity)
    warnUser()
end

function Target.RemoveModel(model)
    warnUser()
end

function Target.RemoveZone(name)
    warnUser()
end

return Target