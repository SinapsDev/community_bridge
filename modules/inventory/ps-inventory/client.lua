---@diagnostic disable: duplicate-set-field
if GetResourceState('ps-inventory') == 'missing' then return end
local ps = exports['ps-inventory']

Inventory = Inventory or {}

---Return the item info in oxs format, {name, label, stack, weight, description, image}
---@param item string
---@return table
Inventory.GetItemInfo = function(item)
    local itemData = Framework.Shared.Items[item]
    if not itemData then return {} end
    return {
        name = itemData.name,
        label = itemData.label,
        stack = itemData.unique,
        weight = itemData.weight,
        description = itemData.description,
        image = Inventory.GetImagePath(itemData.name)
    }
end

---This will get the name of the in use resource.
---@return string
Inventory.GetResourceName = function()
    return "ps-inventory"
end

---This will return the entire items table from the inventory.
---@return table 
Inventory.Items = function()
    return Framework.Shared.Items
end

---Will return boolean if the player has the item.
---@param item string
---@param requiredCount number (optional)
---@return boolean
Inventory.HasItem = function(item, requiredCount)
    return ps:HasItem(item, requiredCount or 1)
end

---This will get the image path for this item, if not found will return placeholder.
---@param item string
---@return string
Inventory.GetImagePath = function(item)
    item = Inventory.StripPNG(item)
    local file = LoadResourceFile("ps-inventory", string.format("html/images/%s.png", item))
    local imagePath = file and string.format("nui://ps-inventory/html/images/%s.png", item)
    return imagePath or "https://avatars.githubusercontent.com/u/47620135"
end

RegisterNetEvent('community_bridge:client:ps-inventory:openStash', function(id, data)
    if source ~= 65535 then return end
    TriggerEvent('ps-inventory:client:SetCurrentStash', id)
    TriggerServerEvent('ps-inventory:server:OpenInventory', 'stash', id, { maxweight = data.weight, slots = data.slots })
end)

return Inventory