#!/usr/bin/env python3
"""Static contract tests for the single-dispatcher/exact-location design.

Runtime injection behaviour is covered end to end against real OpenResty and
the real Lua filter in tests/test-openresty.sh; do not re-model it here.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
DISPATCHER = (ROOT / "src/nginx/ui-dispatch-filter.lua").read_text(encoding="utf-8")
NGINX_CONF = (ROOT / "src/nginx/ts-cert.conf").read_text(encoding="utf-8")
FIXTURE = (ROOT / "tests/fixtures/ts-fix-v1.0.21/ts-fix-body-filter.lua").read_text(encoding="utf-8")


class DispatcherTests(unittest.TestCase):
    def test_exact_location_owns_one_filter_pair(self):
        self.assertEqual(NGINX_CONF.count("location = /gl_home.html"), 1)
        self.assertEqual(NGINX_CONF.count("header_filter_by_lua_file"), 1)
        self.assertEqual(NGINX_CONF.count("body_filter_by_lua_file"), 1)
        exact = re.search(r"location = /gl_home\.html \{(.*?)\n\}", NGINX_CONF, re.S)
        self.assertIsNotNone(exact)
        self.assertIn("ui-dispatch-filter.lua", exact.group(1))

    def test_current_upstream_fixture_matches_adapter_contract(self):
        self.assertIn('ngx.var.uri == "/gl_home.html"', FIXTURE)
        self.assertIn('chunk:find("</head>")', FIXTURE)
        self.assertIn('/ts-fix/ts-fix.js?v=1.0.21', FIXTURE)
        self.assertIn("pcall(dofile, TS_FIX_FILTER)", DISPATCHER)
        self.assertIn("adapter may be incompatible", DISPATCHER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
