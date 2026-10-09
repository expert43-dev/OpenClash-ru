local file = assert(io.open("luci-app-openclash/root/usr/share/openclash/openclash_version.lua"))
local source = file:read("*a")
file:close()
local code = "local function cdn_list() return {} end\n"
for _, name in ipairs({"repository_for", "raw_url", "build_fetch_urls", "build_feed_urls"}) do
    code = code .. assert(source:match("(local function " .. name .. "%b().-\nend)"), name) .. "\n"
end
code = code .. "return {fetch=build_fetch_urls, feed=build_feed_urls}"
local routes = assert(loadstring(code))()
for _, mod in ipairs({"0", "https://cdn.jsdelivr.net/", "https://fastly.jsdelivr.net/", "https://example.org/"}) do
    for _, path in ipairs({"package/master/version", "package/dev/version", "abc123/master/version"}) do
        assert(routes.fetch(mod, path)[1]:find("expert43%-dev/OpenClash%-ru"))
        assert(routes.feed(mod, path)[1]:find("expert43%-dev/OpenClash%-ru"))
    end
    for _, path in ipairs({"core/master/core_version", "core/dev/core_version", "abc123/master/core_version"}) do
        assert(routes.fetch(mod, path)[1]:find("vernesong/OpenClash"))
        assert(routes.feed(mod, path)[1]:find("vernesong/OpenClash"))
    end
end
print("Plugin update/history routes use fork; core routes use upstream")
