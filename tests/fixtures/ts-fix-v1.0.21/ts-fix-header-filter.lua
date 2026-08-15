-- Fixture from RemoteToHome-io/gl-tailscale-fix, main commit
-- d86da698e17ece6b52ba1789ee27b02f7313692f (filter shipped by v1.0.21).
-- Copyright (c) 2026 RemoteToHome Consulting; GPL-3.0-only.
if ngx.var.uri == "/gl_home.html" or ngx.var.uri == "/" then
    ngx.header.content_length = nil
end
