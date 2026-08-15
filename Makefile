include $(TOPDIR)/rules.mk

PKG_NAME:=gl-tailscale-cert
PKG_VERSION:=0.1.7
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=SPDL91 and contributors
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/gl-tailscale-cert
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Tailscale HTTPS certificates for GL.iNet web interfaces
  URL:=https://github.com/SPDL91/gl-tailscale-cert
  DEPENDS:=+jsonfilter +uci +openssl-util +ca-bundle
endef

define Package/gl-tailscale-cert/description
 Opt-in certificate discovery, renewal, validated activation, boot repair,
 sysupgrade persistence, GL OUI RPC, and coexistence-safe WebUI integration.
endef

define Build/Compile
endef

define Package/gl-tailscale-cert/install
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/usr/bin
	$(INSTALL_BIN) ./src/init.d/gl-tailscale-cert $(1)/etc/init.d/gl-tailscale-cert
	$(INSTALL_BIN) ./src/scripts/gl-tailscale-cert $(1)/usr/bin/gl-tailscale-cert
	sed -i 's/{{VERSION}}/$(PKG_VERSION)/g' $(1)/usr/bin/gl-tailscale-cert
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./src/hotplug/iface/90-gl-tailscale-cert $(1)/etc/hotplug.d/iface/90-gl-tailscale-cert

	$(INSTALL_DIR) $(1)/usr/lib/oui-httpd/rpc $(1)/usr/libexec/gl-tailscale-cert
	$(INSTALL_DATA) ./src/rpc/ts-cert $(1)/usr/lib/oui-httpd/rpc/ts-cert
	$(INSTALL_BIN) ./src/lifecycle/postinst $(1)/usr/libexec/gl-tailscale-cert/postinst
	$(INSTALL_BIN) ./src/lifecycle/prerm $(1)/usr/libexec/gl-tailscale-cert/prerm

	$(INSTALL_DIR) $(1)/usr/share/gl-tailscale-cert/defaults
	$(INSTALL_DIR) $(1)/usr/share/gl-tailscale-cert/nginx
	$(INSTALL_DIR) $(1)/usr/share/gl-tailscale-cert/www
	$(INSTALL_CONF) ./src/config/ts_cert $(1)/usr/share/gl-tailscale-cert/defaults/ts_cert
	$(INSTALL_DATA) ./src/nginx/ts-cert.conf $(1)/usr/share/gl-tailscale-cert/nginx/ts-cert.conf
	$(INSTALL_DATA) ./src/nginx/ui-header-filter.lua $(1)/usr/share/gl-tailscale-cert/ui-header-filter.lua
	$(INSTALL_DATA) ./src/nginx/ui-dispatch-filter.lua $(1)/usr/share/gl-tailscale-cert/ui-dispatch-filter.lua
	sed -i 's/{{VERSION}}/$(PKG_VERSION)/g' $(1)/usr/share/gl-tailscale-cert/ui-dispatch-filter.lua
	$(INSTALL_DATA) ./src/www/ts-cert.js $(1)/usr/share/gl-tailscale-cert/www/ts-cert.js
	sed -i 's/{{VERSION}}/$(PKG_VERSION)/g' $(1)/usr/share/gl-tailscale-cert/www/ts-cert.js
	gzip -9 -c $(1)/usr/share/gl-tailscale-cert/www/ts-cert.js > $(1)/usr/share/gl-tailscale-cert/www/ts-cert.js.gz

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./src/upgrade/keep.d/gl-tailscale-cert $(1)/lib/upgrade/keep.d/gl-tailscale-cert
endef

define Package/gl-tailscale-cert/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
/usr/libexec/gl-tailscale-cert/postinst
endef

define Package/gl-tailscale-cert/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
/usr/libexec/gl-tailscale-cert/prerm
endef

$(eval $(call BuildPackage,gl-tailscale-cert))
