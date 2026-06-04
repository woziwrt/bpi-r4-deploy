include $(TOPDIR)/rules.mk

PKG_NAME:=modemdata
PKG_VERSION:=20260522
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/modemdata
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Detailed information about the cellular modem
	MAINTAINER:=Cezary Jackiewicz <cezary@eko.one.pl>
	PKGARCH:=all
	DEPENDS:=+@BUSYBOX_DEFAULT_AWK +comgt +jsonfilter +sms-tool
endef

define Build/Compile
endef

define Package/modemdata/install
	$(CP) ./files/* $(1)
endef

$(eval $(call BuildPackage,modemdata))
