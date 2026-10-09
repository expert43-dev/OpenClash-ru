-- Resolve the main route down to the actual selected node, including url-test.
local M = {}
local automatic = { URLTest = true, Fallback = true, Smart = true }
local terminal = { DIRECT = true, REJECT = true, ["REJECT-DROP"] = true, PASS = true }

function M.resolve(proxies, rules, mode)
    if mode == "direct" then return { state = "direct", name = "DIRECT" } end
    if type(proxies) ~= "table" then return { state = "unavailable" } end
    local root
    if mode == "global" then
        root = "GLOBAL"
    else
        -- Prefer the catch-all group; split-routing profiles may end in DIRECT.
        local counts, order = {}, {}
        for _, rule in ipairs(rules or {}) do
            local name = rule.proxy
            if not (rule.extra and rule.extra.disabled) and proxies[name] and
               type(proxies[name].all) == "table" and name ~= "GLOBAL" then
                if rule.type == "Match" then root = name; break end
                if not counts[name] then counts[name] = 0; order[#order + 1] = name end
                counts[name] = counts[name] + 1
            end
        end
        if not root then
            for _, name in ipairs(order) do
                if not root or counts[name] > counts[root] then root = name end
            end
        end
    end
    if not root or not proxies[root] then return { state = "unavailable" } end
    local group = proxies[root]
    local result = { group = root, selected = group.now, chain = {}, choices = {},
                     can_select = group.type == "Selector", automatic = false }
    for _, name in ipairs(group.all or {}) do
        if proxies[name] then
            result.choices[#result.choices + 1] = name
            if automatic[proxies[name].type] and not result.automatic_name then
                result.automatic_name = name
            end
        end
    end
    local name, seen = root, {}
    for _ = 1, 32 do
        if seen[name] or not proxies[name] then result.state = "unavailable"; return result end
        seen[name] = true
        result.chain[#result.chain + 1] = name
        local node = proxies[name]
        if automatic[node.type] then result.automatic = true end
        if node.type == "LoadBalance" then
            result.state = "balanced"; result.name = name; return result
        end
        if type(node.all) ~= "table" then
            result.state = terminal[name] and "direct" or "selected"
            if name == "REJECT" or name == "REJECT-DROP" then result.state = "blocked" end
            result.name, result.protocol = name, node.type
            return result
        end
        if type(node.now) ~= "string" then result.state = "unavailable"; return result end
        name = node.now
    end
    result.state = "unavailable"
    return result
end

function M.allowed(route, name)
    if not route.can_select then return false end
    for _, choice in ipairs(route.choices or {}) do
        if choice == name then return true end
    end
    return false
end

-- Existing TCP/QUIC sessions retain their original outbound after selection.
-- Reset only sessions that actually used this group; DIRECT/LAN stays intact.
function M.connection_ids(connections, group)
    local ids, seen = {}, {}
    for _, connection in ipairs(connections or {}) do
        if type(connection.id) == "string" and not seen[connection.id] then
            for _, name in ipairs(connection.chains or {}) do
                if name == group then
                    ids[#ids + 1] = connection.id
                    seen[connection.id] = true
                    break
                end
            end
        end
    end
    return ids
end

return M
