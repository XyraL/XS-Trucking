Inventory = { name = nil }

if not IsDuplicityVersion() then return end

do
    local forced = Config.Bridges.inventory
    if forced ~= 'auto' then
        Inventory.name = forced ~= 'none' and forced or nil
    else
        for _, name in ipairs({ 'ox_inventory', 'qs-inventory', 'ps-inventory', 'qb-inventory' }) do
            if GetResourceState(name) == 'started' then
                Inventory.name = name
                break
            end
        end
    end
end

function Inventory.Add(src, item, count)
    if not item or item == '' or (count or 0) <= 0 then return false end

    local ok, result = pcall(function()
        if Inventory.name == 'ox_inventory' then
            return exports.ox_inventory:AddItem(src, item, count)
        elseif Inventory.name == 'qs-inventory' then
            return exports['qs-inventory']:AddItem(src, item, count)
        end

        local player = Framework.GetPlayer(src)
        if not player then return false end
        local added = player.Functions.AddItem(item, count)
        if added and Framework.core then
            TriggerClientEvent('inventory:client:ItemBox', src, Framework.core.Shared.Items[item], 'add', count)
        end
        return added
    end)

    return ok and result and true or false
end
