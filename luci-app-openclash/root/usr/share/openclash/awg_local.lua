-- Only explicitly retained nodes; no secrets in command arguments or logs.
local uci = require("luci.model.uci").cursor()
local json = require("luci.jsonc")
local nodes = {}
uci:foreach("openclash", "servers", function(node)
    if node.awg_local == "1" and node.type == "wireguard" and
        (node.config == arg[1] or node.config == "all") then
        nodes[#nodes + 1] = node
    end
end)
io.write(#nodes == 0 and "[]" or json.stringify(nodes))
