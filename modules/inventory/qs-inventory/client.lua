---@diagnostic disable: duplicate-set-field
if GetResourceState('qs-inventory') == 'missing' then return end
local quasar = exports["qs-inventory"]

Inventory = Inventory or {}

---@description This will get the name of the in use resource.
---@return string
Inventory.GetResourceName = function()
    return "qs-inventory"
end

---@description Return the item info in oxs format, {name, label, stack, weight, description, image}
---@param item string
---@return table
Inventory.GetItemInfo = function(item)
    local itemsData = quasar:GetItemList()
    if not itemsData then return {} end
    itemsData = itemsData[item]
    if not itemsData then return {} end
    return {
        name = itemsData.name or "Missing Name",
        label = itemsData.label or "Missing Label",
        stack = itemsData.unique or "false",
        weight = itemsData.weight or "0",
        description = itemsData.description or "none",
        image = Inventory.GetImagePath(item),
    }
end

---@description This will return the entire items table from the inventory.
---@return table 
Inventory.Items = function()
    return quasar:GetItemList()
end

---@description Will return boolean if the player has the item.
---@param item string
---@param requiredCount number (optional)
---@return boolean
Inventory.HasItem = function(item, requiredCount)
    return Inventory.GetItemCount(item) >= (requiredCount or 1)
end

---@description This will return th count of the item in the players inventory, if not found will return 0.
---@param item string
---@return number
Inventory.GetItemCount = function(item)
    if type(item) ~= 'string' or item == '' then return 0 end
    return tonumber(quasar:Search(item)) or 0
end

---@description This will get the image path for this item, if not found will return placeholder.
---@param item string
---@return string
Inventory.GetImagePath = function(item)
    item = Inventory.StripPNG(item)
    local file = LoadResourceFile("qs-inventory", string.format("html/images/%s.png", item))
    local imagePath = file and string.format("nui://qs-inventory/html/images/%s.png", item)
    return imagePath or "https://avatars.githubusercontent.com/u/47620135"
end

---@description This will return the players inventory in the format of {name, label, count, slot, metadata}
---@return table
Inventory.GetPlayerInventory = function()
    local items = {}
    local inventory = quasar:getUserInventory()
    for _, v in pairs(inventory) do
        table.insert(items, {
            name = v.name,
            label = v.label,
            count = v.amount or v.count,
            slot = v.slot,
            metadata = v.info or v.metadata or {},
            stack = v.unique or v.stack or false,
            close = v.useable,
            weight = v.weight
        })
    end
    return items
end

return Inventory