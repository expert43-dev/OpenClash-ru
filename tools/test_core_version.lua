local f=assert(io.open("luci-app-openclash/luasrc/controller/openclash.lua"))
local src=f:read("*a");f:close()
local definition=assert(src:match("(local function coremetacv%b().-\nend)"))
local running,api,cache,stat=true,{version="v1.19.32"},nil,{ino=1,size=10,mtime=20}
local launches=0
local env={
    require=function(name) assert(name=="nixio.fs");return {stat=function() return stat end} end,
    fs={readfile=function() return "cache" end,writefile=function(_,value) cache=value end},
    json={parse=function(data) if data=="api" then return api else return cache end end,stringify=function(data) return data end},
    SYS={exec=function(cmd) assert(cmd:find("curl",1,true) and not cmd:find(" -v",1,true));launches=launches+1;return "api" end},
    UTIL={shellquote=function(v) return "'"..v.."'" end},
    meta_core_path="/core",is_running=function() return running end,cn_port=function() return "9090" end,dase=function() return "secret" end
}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(definition.."\nreturn coremetacv"));setfenv(chunk,env)
local version=chunk()
assert(version()=="v1.19.32" and launches==1)
running=false
assert(version()=="v1.19.32" and launches==1)
stat.mtime=21
assert(version()=="0" and launches==1)
running=true;api=nil
assert(version()=="0")
stat=nil
assert(version()=="0")
print("Core version uses running API and binary-specific cache; polling never executes another packed core")
