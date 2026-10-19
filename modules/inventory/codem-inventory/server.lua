---@diagnostic disable: duplicate-set-field
if GetResourceState('codem-inventory') == 'missing' then return end

Inventory = Inventory or {}
Inventory.Stashes = Inventory.Stashes or {}

local codem = exports['codem-inventory']

---@description This will get the name of the in use resource.
---@return string
Inventory.GetResourceName = function()
    return "codem-inventory"
end

---@description This will add an item, and return true or false based on success
---@param src number
---@param item string
---@param count number
---@param slot number (optional)
---@param metadata table (optional)
---@return boolean
Inventory.AddItem = function(src, item, count, slot, metadata)
    local success = codem:AddItem(src, item, count, slot, metadata)
    if not success then return false end
    TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, {action = "add", item = item, count = count, slot = slot, metadata = metadata})
    return success
end

---@description Internal function to search for items with specific metadata in player inventory
---@param src number
---@param metadata table
---@return boolean, number|nil
local function runMetadataSearch(src, metadata)
    local inv = Framework.GetPlayerInventory(src) or {}
    for _, v in pairs(inv) do
        if v.metadata and v.metadata == metadata then
            return true, v.slot
        end
    end
    return false
end

---This will remove an item, and return true or false based on success
---@param src number
---@param item string
---@param count number
---@param slot number
---@param metadata table
---@return boolean
Inventory.RemoveItem = function(src, item, count, slot, metadata)
    if metadata then
        local found, foundSlot = runMetadataSearch(src, metadata)
        if found then slot = foundSlot end
    end
    local success = codem:RemoveItem(src, item, count, slot)
    if not success then return false end
    TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, {action = "remove", item = item, count = count, slot = slot, metadata = metadata})
    return success
end

---@description This will return a table with the item info, {name, label, stack, weight, description, image}
---@param item string
---@return table
Inventory.GetItemInfo = function(item)
    local itemData = Inventory.Items()
    if not itemData or not itemData[item] then return {} end
    return {
        name = itemData[item].name or "Missing Name",
        label = itemData[item].label or "Missing Label",
        stack = itemData[item].unique or "false",
        weight = itemData[item].weight or "0",
        description = itemData[item].description or "none",
        image = itemData[item].image or Inventory.GetImagePath(item),
    }
end

---@description This will return the entire items table from the inventory.
---@return table 
Inventory.Items = function()
    return codem:GetItemList() or {}
end

---@description This will return the count of the item in the players inventory, if not found will return 0.
---@param src number
---@param item string
---@param metadata table (optional)
---@return number
Inventory.GetItemCount = function(src, item, metadata)
    return codem:GetItemsTotalAmount(src, item) or 0
end

---@description This wil return the players inventory.
---@param src number
---@return table
Inventory.GetPlayerInventory = function(src)
    local identifier = Framework.GetPlayerIdentifier(src)
    local playerItems = codem:GetInventory(identifier, src)
    local repackedTable = {}
    for _, v in pairs(playerItems) do
        table.insert(repackedTable, {
            name = v.name,
            count = v.amount or v.count,
            metadata = v.info or v.metadata or {},
            slot = v.slot,
        })
    end
    return repackedTable
end

---@description Returns the specified slot data as a table.
---@param src number
---@param slot number
---@return table {weight, name, metadata, slot, label, count}
Inventory.GetItemBySlot = function(src, slot)
    local slotData = codem:GetItemBySlot(src, slot)
    if not slotData then return {} end
    return {
        name = slotData.name,
        label = slotData.label or slotData.name,
        weight = slotData.weight,
        slot = slotData.slot,
        count = slotData.amount or slotData.count,
        metadata = slotData.info or slotData.metadata or {},
        stack = slotData.unique or false,
        description = slotData.description
    }
end

---@description This will set the metadata of an item in the inventory.
---@param src number
---@param item string
---@param slot number
---@param metadata table
---@return nil
Inventory.SetMetadata = function(src, item, slot, metadata)
    return codem:SetItemMetadata(src, slot, metadata)
end

---@description This will return a boolean if the player has the item.
---@param src number
---@param item string
---@param requiredCount number (optional)
---@return boolean
Inventory.HasItem = function(src, item, requiredCount)
    return codem:HasItem(src, item, requiredCount or 1)
end

---@description This will clear the specified inventory, will always return true unless a value isnt passed correctly.
---@param id string
---@param _type string unused with ox_inventory
---@return boolean
Inventory.ClearStash = function(id, _type)
    if type(id) ~= "string" then return false end
    if Inventory.Stashes[id] then Inventory.Stashes[id] = nil end
    codem:UpdateStash(id, {})
    return true
end

---@description This will add items to a stash, and return true or false based on success
---@param id string
---@param items table {item, count, metadata}
---@return boolean
Inventory.AddStashItems = function(id, items)
    if type(items) ~= "table" then return false end
    local repack = {}
    for _, v in pairs(items) do
        table.insert(repack, {
            item = v.item,
            amount = v.count or v.amount,
            info = v.metadata or v.info or {},
            unique = v.unique or v.stack or false,
            description = v.description or "none",
            weight = Inventory.GetItemInfo(v.item).weight or 0,
            type = 'item',
            slot = #repack + 1,
        })
    end
    codem:UpdateStash(id, repack)
    return true
end

---@description This will open the specified stash for the src passed.
---@param src number
---@param _type string unused with codem-inventory
---@param id string
---@return nil
Inventory.OpenStash = function(src, _type, id)
    local stash = Inventory.Stashes[id] or {}
    TriggerClientEvent("community_bridge:client:codem-inventory:openStash", src, id, { slots = stash.slots, weight = stash.weight, label = stash.label or id })
end

---@description This will open a players inventory, used for admin purposes and stuff.
---@param src number
---@param target number
Inventory.OpenPlayerInventory = function(src, target)
    assert(src, "OpenPlayerInventory: src is required")
    assert(target, "OpenPlayerInventory: target is required")
    TriggerClientEvent("community_bridge:client:codem-inventory:openPlayerInventory", src, target)
end

---@description This will get the image path for an item, it is an alternate option to GetItemInfo. If a image isnt found will revert to community_bridge logo (useful for menus)
---@param item string
---@return string
Inventory.GetImagePath = function(item)
    item = Inventory.StripPNG(item)
    local file = LoadResourceFile("codem-inventory", string.format("html/itemimages/%s.png", item))
    local imagePath = file and string.format("nui://codem-inventory/html/itemimages/%s.png", item)
    return imagePath or "https://avatars.githubusercontent.com/u/47620135"
end

return Inventory