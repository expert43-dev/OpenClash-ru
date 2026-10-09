-- Parsers shared by the controller and the offline service tests.
local M = {}

function M.valid_ipv4(ip)
    if type(ip) ~= "string" or not ip:match("^%d+%.%d+%.%d+%.%d+$") then return false end
    for part in ip:gmatch("%d+") do
        if tonumber(part) > 255 then return false end
    end
    return true
end

function M.ipgeo(data, parse_json)
    local ok, result = pcall(parse_json, data or "")
    if not ok or type(result) ~= "table" or result.ok ~= true or not M.valid_ipv4(result.ip) then return nil end
    return {ip = result.ip, geo = "", country_code = result.country}
end

function M.mail(data)
    -- Parse JSONP as data; never evaluate code returned by a remote provider.
    local ip = (data or ""):match('"ipAddress"%s*:%s*"([%d%.]+)"')
    if not M.valid_ipv4(ip) then return nil end
    return {ip = ip, geo = ""}
end

return M
