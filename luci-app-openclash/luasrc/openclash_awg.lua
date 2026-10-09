-- Validation without network access or changes to the running VPN.
local M = {}

function M.range(value, maximum)
    if value == nil or value == "" then return value end
    local first, last = value:match("^(%d+)%-(%d+)$")
    if not first then first = value:match("^(%d+)$"); last = first end
    first, last = tonumber(first), tonumber(last)
    if first and last and first <= last and last <= maximum then return value end
    return nil
end

function M.key(value)
    if value == nil or value == "" then return value end
    if #value == 44 and value:match("^[A-Za-z0-9+/]+=$") then return value end
    return nil
end

function M.singleline(value)
    if value == nil or not value:match("%c") then return value end
    return nil
end

return M
