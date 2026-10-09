local route = dofile("luci-app-openclash/luasrc/openclash_active_proxy.lua")
local p = {
    GLOBAL = {type="Selector", now="DIRECT", all={"DIRECT", "Main"}},
    DIRECT = {type="Direct"}, REJECT = {type="Reject"},
    Main = {type="Selector", now="Auto", all={"Auto", "Node A", "Node B", "DIRECT"}},
    Auto = {type="URLTest", now="Node B", all={"Node A", "Node B"}},
    Video = {type="Selector", now="Node A", all={"Node A", "Main"}},
    ["Node A"] = {type="Vless"}, ["Node B"] = {type="WireGuard"}
}
local rules = {{type="Domain", proxy="Video"}, {type="Domain", proxy="Main"},
    {type="RuleSet", proxy="Main"}, {type="Match", proxy="DIRECT"}}
local r = route.resolve(p, rules, "rule")
assert(r.group == "Main" and r.name == "Node B" and r.automatic)
assert(r.selected == "Auto" and r.automatic_name == "Auto" and #r.chain == 3)
assert(route.allowed(r, "Node A") and not route.allowed(r, "not-in-config"))
assert(route.resolve(p, rules, "global").name == "DIRECT")
assert(route.resolve(p, rules, "direct").can_select == nil)
p.Main.now = "Node A"
r = route.resolve(p, rules, "rule")
assert(r.name == "Node A" and not r.automatic)
assert(route.resolve(p, {{type="Match", proxy="Video"}}, "rule").group == "Video")
p.Auto.now = "Main"; p.Main.now = "Auto"
assert(route.resolve(p, rules, "rule").state == "unavailable")
p.Main.now = "Missing"
assert(route.resolve(p, rules, "rule").state == "unavailable")
p.Main.type = "LoadBalance"
r = route.resolve(p, rules, "rule")
assert(r.state == "balanced" and not r.can_select)
assert(route.resolve(nil, nil, "rule").state == "unavailable")
assert(route.resolve(p, {{type="Match", proxy="Main", extra={disabled=true}}}, "rule").state == "unavailable")
print("Active VPN route: nested auto/manual selection, direct/global, split routes, cycles and unavailable nodes passed")
