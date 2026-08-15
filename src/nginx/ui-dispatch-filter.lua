-- SPDX-License-Identifier: GPL-3.0-only
-- Single response-body dispatcher for the GL admin SPA.

if ngx.var.uri ~= "/gl_home.html" then
    return
end

local MAX_HEAD_BYTES = 262144
local TS_FIX_FILTER = "/usr/share/ts-fix/ts-fix-body-filter.lua"
local TS_FIX_ASSET = "/ts-fix/ts-fix.js"
local TS_CERT_ASSET = "/ts-cert/ts-cert.js"
local TS_CERT_TAG = '<script defer src="/ts-cert/ts-cert.js?v={{VERSION}}"></script>'

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local ctx = ngx.ctx.ts_cert_dispatch
if not ctx then
    ctx = { chunks = {}, bytes = 0, finished = false, pass = false }
    ngx.ctx.ts_cert_dispatch = ctx
end

if ctx.finished or ctx.pass then
    return
end

local chunk = ngx.arg[1] or ""
local eof = ngx.arg[2]
ctx.chunks[#ctx.chunks + 1] = chunk
ctx.bytes = ctx.bytes + #chunk
ngx.arg[1] = nil

local combined = table.concat(ctx.chunks)
local has_head_end = combined:find("</head>", 1, true) ~= nil

if not has_head_end and not eof and ctx.bytes <= MAX_HEAD_BYTES then
    return
end

ctx.chunks = nil
if not has_head_end then
    ngx.arg[1] = combined
    ctx.pass = true
    ngx.log(ngx.WARN, "ts-cert: admin SPA head terminator not found; injection skipped")
    return
end

ngx.arg[1] = combined

local has_ts_fix = file_exists(TS_FIX_FILTER)
if has_ts_fix then
    local ok, err = pcall(dofile, TS_FIX_FILTER)
    if not ok then
        ngx.log(ngx.WARN, "ts-cert: optional ts-fix body filter failed: ", tostring(err))
    end
end

combined = ngx.arg[1] or ""
if has_ts_fix and not combined:find(TS_FIX_ASSET, 1, true) then
    ngx.log(ngx.WARN, "ts-cert: ts-fix filter did not inject its expected asset; adapter may be incompatible")
end

if not combined:find(TS_CERT_ASSET, 1, true) then
    combined = combined:gsub("</head>", TS_CERT_TAG .. "</head>", 1)
end

ngx.arg[1] = combined
ctx.finished = true
