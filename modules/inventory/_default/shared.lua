---@diagnostic disable: duplicate-set-field

---Item names a HasItem/GetItemCount call asks about, mapped to the count needed.
---Accepts a name, a list of names or { name = count } (ox_target `items` formats). Booleans, nil and '' are no item.
---@param item any
---@param requiredCount number|nil
---@return table|nil
function InventoryItemRequest(item, requiredCount)
    local need = tonumber(requiredCount) or 1
    local request = {}
    if type(item) == 'string' then
        if item ~= '' then request[item] = need end
    elseif type(item) == 'table' then
        for k, v in pairs(item) do
            if type(k) == 'string' and k ~= '' and type(v) == 'number' then
                request[k] = v
            elseif type(v) == 'string' and v ~= '' then
                request[v] = need
            end
        end
    end
    return next(request) and request or nil
end

---Makes Inventory.HasItem / GetItemCount safe for whatever inventory module won:
---the inventory export only ever sees one non-empty item name, lists are checked name by name.
---@param inventory table
function InventoryGuardItemChecks(inventory)
    if not inventory then return end
    local hasItem, getItemCount = inventory.HasItem, inventory.GetItemCount
    local server = IsDuplicityVersion()

    if getItemCount then
        local countOne = server
            and function(name, src, metadata) return getItemCount(src, name, metadata) end
            or function(name) return getItemCount(name) end
        local function count(item, src, metadata)
            local request = InventoryItemRequest(item)
            if not request then return 0 end
            local total = 0
            for name in pairs(request) do
                total = total + (tonumber(countOne(name, src, metadata)) or 0)
            end
            return total
        end
        inventory.GetItemCount = server
            and function(src, item, metadata) return count(item, src, metadata) end
            or function(item) return count(item) end
    end

    if hasItem then
        local hasOne = server
            and function(name, need, src) return hasItem(src, name, need) end
            or function(name, need) return hasItem(name, need) end
        local function has(item, requiredCount, src)
            local request = InventoryItemRequest(item, requiredCount)
            if not request then return false end
            for name, need in pairs(request) do
                if not hasOne(name, need, src) then return false end
            end
            return true
        end
        inventory.HasItem = server
            and function(src, item, requiredCount) return has(item, requiredCount, src) end
            or function(item, requiredCount) return has(item, requiredCount) end
    end
end
