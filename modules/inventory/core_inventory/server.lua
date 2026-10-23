---@diagnostic disable: duplicate-set-field
if GetResourceState('core_inventory') == 'missing' then return end

Inventory = Inventory or {}
Inventory.Stashes = Inventory.Stashes or {}
Callback = Callback or Require("lib/callback/shared/callback.lua")
local core = exports.core_inventory

---This will get the name of the in use resource.
---@return string
Inventory.GetResourceName = function()
    return "core_inventory"
end

-- core_inventory addresses one item two ways: removeItemExact wants its unique
-- `id` ("itemname-uniqueString"), setMetadata wants its numeric slot. The
-- framework usable-item hooks hand resources the `id` as `slot`
-- (modules/framework/*/server.lua RegisterUsableItem), GetPlayerInventory hands
-- them the numeric slot, so every lookup below accepts either and each export
-- gets the handle it expects.

-- getInventory may return the item list or the whole inventory ({ content = ... }).
local function coreContent(src)
    local inv = core:getInventory(src)
    if type(inv) ~= 'table' then return nil end
    if type(inv.content) == 'table' then return inv.content end
    return inv
end

-- grid items can span several cells: slot, else the first of slots, else a numeric content key
local function slotIndexOf(item, key)
    local slot = tonumber(item.slot)
    if not slot and type(item.slots) == 'table' then slot = tonumber(item.slots[1]) end
    return slot or tonumber(key)
end

local function uniqueIdOf(item, key)
    if item.id ~= nil and item.id ~= '' then return item.id end
    if type(key) == 'string' and not tonumber(key) then return key end
    return nil
end

local function repackItem(item, key)
    local id = uniqueIdOf(item, key)
    return {
        name = item.name,
        count = item.count or item.amount or 0,
        metadata = item.metadata or item.info,
        slot = slotIndexOf(item, key) or id,
        id = id,
    }
end

-- the repacked entry for a slot number or a unique id, nil if the player doesn't hold it
local function findEntry(src, handle)
    if handle == nil then return nil end
    local slot = tonumber(handle)
    for _, v in pairs(Inventory.GetPlayerInventory(src) or {}) do
        if (v.id ~= nil and v.id == handle) or (slot and tonumber(v.slot) == slot) then
            return v
        end
    end
    return nil
end

---This will add an item, and return true or false based on success
---@param src number
---@param item string
---@param count number
---@param slot number
---@param metadata table
---@return boolean
Inventory.AddItem = function(src, item, count, slot, metadata)
    -- docs specify a table returned on success, on failure it returns false.
    -- https://docs.c8re.store/core-inventory/api/server#additem
    local success = core:addItem(src, item, count, metadata)
    if not success then return false end
    TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, {action = "add", item = item, count = count, slot = slot, metadata = metadata})
    return success or false
end

---This will remove an item, and return true or false based on success
---@param src number
---@param item string
---@param count number
---@param slot number
---@param metadata table
---@return boolean
Inventory.RemoveItem = function(src, item, count, slot, metadata)
    if not slot and metadata then
        local inv = Inventory.GetPlayerInventory(src)
        if not inv then return false end
        for _, v in pairs(inv) do
            if v.name == item and v.metadata == metadata then
                slot = v.id or v.slot
                break
            end
        end
    end
    if slot then
        -- removeItemExact takes the item's unique id, never a slot number
        -- https://docs.c8re.store/core-inventory/exports
        local entry = findEntry(src, slot)
        if not entry or not entry.id or (item and entry.name ~= item) then return false end
        TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, {action = "remove", item = item, count = count, slot = slot, metadata = metadata})
        local ok, removed = pcall(function()
            return core:removeItemExact(src, entry.id, count)
        end)
        if not ok then
            print(("^1[community_bridge] core_inventory removeItemExact failed for %s: %s^0"):format(tostring(entry.id), tostring(removed)))
            return false
        end
        return removed ~= false
    end
    TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, {action = "remove", item = item, count = count, slot = slot, metadata = metadata})
    core:removeItem(src, item, count)
    return true
end

---This will return the count of the item in the players inventory, if not found will return 0.
---if metadata is passed it will find the matching items count.
---@param src number
---@param item string
---@param metadata table
---@return number
Inventory.GetItemCount = function(src, item, metadata)
    if metadata then
        local inv = Inventory.GetPlayerInventory(src)
        local deepCount = 0
        if not inv then return 0 end
        for _, v in pairs(inv) do
            if v.name == item and v.metadata == metadata then
                deepCount = deepCount + v.count
            end
        end
        return deepCount
    end
    local count = core:getItemCount(src, item)
    return count or 0
end

---This wil return the players inventory.
---@param src number
---@return table
Inventory.GetPlayerInventory = function(src)
    local content = coreContent(src)
    if not content then
        if Bridge.Framework.GetFrameworkName() == 'qb-core' then
            return Bridge.Framework.GetPlayerInventory(src)
        end
        return {}
    end
    local repackedTable = {}
    local expanded, seen = {}, {}
    -- getItems and getInventory can both list the same stack
    local function add(entry)
        local key = entry.id or entry.slot
        if key ~= nil then
            if seen[key] then return end
            seen[key] = true
        end
        table.insert(repackedTable, entry)
    end
    for key, v in pairs(content) do
        if type(v) == 'table' and v.name then
            local stacks = nil
            if (v.metadata or v.info) and (tonumber(v.count or v.amount) or 0) > 1 then
                -- stacked items carrying metadata are listed one by one through getItems
                if expanded[v.name] then goto continue end
                stacks = core:getItems(src, v.name)
                if type(stacks) == 'table' and next(stacks) then expanded[v.name] = true else stacks = nil end
            end
            if stacks then
                for stackKey, item in pairs(stacks) do
                    if type(item) == 'table' then
                        local entry = repackItem(item, stackKey)
                        entry.name = v.name
                        add(entry)
                    end
                end
            else
                add(repackItem(v, key))
            end
        end
        ::continue::
    end
    return repackedTable
end

---Returns the specified slot data as a table.
---Accepts the numeric slot or the item's unique id (what usable-item callbacks pass as slot).
---format {name, count, metadata, slot, id}
---@param src number
---@param slot number|string
---@return table
Inventory.GetItemBySlot = function(src, slot)
    local v = findEntry(src, slot)
    if not v then return {} end
    return {
        name = v.name,
        count = v.count,
        metadata = v.metadata,
        slot = v.slot,
        id = v.id,
    }
end

---This will set the metadata of an item in the inventory.
---Accepts the numeric slot or the item's unique id; core_inventory's setMetadata takes the slot.
---@param src number
---@param item string
---@param slot number|string
---@param metadata table
---@return boolean
Inventory.SetMetadata = function(src, item, slot, metadata)
    local entry = findEntry(src, slot)
    if not entry or (item and entry.name ~= item) then return false end
    -- https://docs.c8re.store/core-inventory/exports : setMetadata(inventory, slotid, metadata)
    core:setMetadata(src, entry.slot, metadata)
    return true
end

---This will open the specified stash for the src passed.
---@param src number
---@param _type string
---@param id number||string
---@return nil
Inventory.OpenStash = function(src, _type, id)
    _type = _type or "stash"
    local tbl = Inventory.Stashes[id]
    core:openInventory(src, id, _type, tbl.slots or 30, tbl.weight or 50000, true, nil, false)
end

---This will register a stash
---@param id number|string
---@param label string
---@param slots number
---@param weight number
---@param owner string
---@param groups table
---@param coords table
---@return boolean
---@return string|number
Inventory.RegisterStash = function(id, label, slots, weight, owner, groups, coords)
    if Inventory.Stashes[id] then return true, id end
    if not slots then slots = 30 end
    local mathyShit = slots / 2
    Inventory.Stashes[id] = {
        id = id,
        label = label,
        slots = mathyShit,
        weight = mathyShit,
        owner = owner,
        groups = groups,
        coords = coords
    }
    return true, id
end

---@description This will return a boolean if the player has the item.
---@param src number
---@param item string
---@param requiredCount number (optional)
---@return boolean
Inventory.HasItem = function(src, item, requiredCount)
    local count = Inventory.GetItemCount(src, item, nil)
    return count >= (requiredCount or 1)
end

---This is to get if there is available space in the inventory, will return boolean.
---@param src number
---@param item string
---@param count number
---@return boolean
Inventory.CanCarryItem = function(src, item, count)
    return true
end

---This will add items to a trunk, and return true or false based on success
---If a trunk with the identifier does not exist, it will create one with default values.
---@param identifier string
---@param items table
---@return boolean
Inventory.AddTrunkItems = function(identifier, items)
    if type(items) ~= "table" then return false end
    return false, print("AddItemsToTrunk is not implemented in core_inventory, because of this we dont have a way to add items to a trunk.")
end

---This will update the plate to the vehicle inside the inventory. (It will also update with jg-mechanic if using it)
---@param oldplate string
---@param newplate string
---@return boolean
Inventory.UpdatePlate = function(oldplate, newplate)
    -- have no clue if this will work but fingers crossed
    local queries = {
        'UPDATE coreinventories SET name = @newplate WHERE name = @oldplate',
        'UPDATE coreinventories SET name = @newplate WHERE name = @glovebox_oldplate',
        'UPDATE coreinventories SET name = @newplate WHERE name = @trunk_oldplate',
    }
    local values = {
        newplate = newplate,
        oldplate = oldplate,
        glovebox_oldplate = 'glovebox-' .. oldplate,
        trunk_oldplate = 'trunk-' .. oldplate
    }
    MySQL.transaction.await(queries, values)
    if GetResourceState('jg-mechanic') == 'missing' then return true end
    return true, exports["jg-mechanic"]:vehiclePlateUpdated(oldplate, newplate)
end

---This will get the image path for an item, it is an alternate option to GetItemInfo. If a image isnt found will revert to community_bridge logo (useful for menus)
---@param item string
---@return string
Inventory.GetImagePath = function(item)
    item = Inventory.StripPNG(item)
    local file = LoadResourceFile("core_inventory", string.format("html/img/%s.png", item))
    local imagePath = file and string.format("nui://core_inventory/html/img/%s.png", item)
    return imagePath or "https://avatars.githubusercontent.com/u/47620135"
end

---This is used for the esx users, documentation doesnt show a client side available option for the inventory so we use jank callbacks to get this.
Callback.Register('community_bridge:Callback:core_inventory', function(source)
    local items = core:getItemsList()
	return items or {}
end)

---This will return the entire items table from the inventory.
---@return table 
Inventory.Items = function()
    return core:getItemsList()
end

Inventory.OpenPlayerInventory = function(src, target)
    assert(src, "OpenPlayerInventory: src is required")
    assert(target, "OpenPlayerInventory: target is required")
    local identifier = Framework.GetPlayerIdentifier(target)
    if not identifier then return false end
    exports.core_inventory:openInventory(src, 'stash-'.. identifier:gsub(':',''), 'stash', nil, nil, true, nil, false)
end

return Inventory