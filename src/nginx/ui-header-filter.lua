-- SPDX-License-Identifier: GPL-3.0-only
-- Compose the known gl-tailscale-fix header filter without owning its files.

if ngx.var.uri ~= "/gl_home.html" then
    return
end

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local ts_fix_filter = "/usr/share/ts-fix/ts-fix-header-filter.lua"
if file_exists(ts_fix_filter) then
    local ok, err = pcall(dofile, ts_fix_filter)
    if not ok then
        ngx.log(ngx.WARN, "ts-cert: optional ts-fix header filter failed: ", tostring(err))
    end
end

ngx.header.content_length = nil
ngx.header.etag = nil
