config_file_turboacc=`find package/ -follow -type f -path '*/luci-app-turboacc/root/etc/config/turboacc'`
if [ -n "$config_file_turboacc" ]; then
  sed -i "s/option hw_flow '1'/option hw_flow '0'/" $config_file_turboacc
  sed -i "s/option sfe_flow '1'/option sfe_flow '0'/" $config_file_turboacc
  sed -i "s/option sfe_bridge '1'/option sfe_bridge '0'/" $config_file_turboacc
fi
sed -i "/dep.*INCLUDE_.*=n/d" `find package/ -follow -type f -path '*/luci-app-turboacc/Makefile'` 2>/dev/null || true

sed -i "s/option limit_enable '1'/option limit_enable '0'/" `find package/ -follow -type f -path '*/nft-qos/files/nft-qos.config'` 2>/dev/null || true
sed -i "s/option enabled '1'/option enabled '0'/" `find package/ -follow -type f -path '*/vsftpd-alt/files/vsftpd.uci'` 2>/dev/null || true
sed -i "/\/etc\/coremark\.sh/d" `find package/ -follow -type f -path '*/coremark/coremark'` 2>/dev/null || true
sed -i 's/192.168.1.1/192.168.2.1/' package/base-files/files/bin/config_generate
sed -i 's/=1/=0/g' package/kernel/linux/files/sysctl-br-netfilter.conf

sed -i '/DEPENDS+/ s/$/ +wsdd2/' `find package/ -follow -type f -path '*/ksmbd-tools/Makefile'` 2>/dev/null || true

sed -i 's/ +ntfs-3g/ +ntfs3-mount/' `find package/ -follow -type f -path '*/automount/Makefile'` 2>/dev/null || true
sed -i '/skip\=/ a skip=`mount | grep -q /dev/$device; echo $?`' `find package/ -follow -type f -path */automount/files/15-automount` 2>/dev/null || true

sed -i 's/START=95/START=99/' `find package/ -follow -type f -path */ddns-scripts/files/ddns.init` 2>/dev/null || true

# enable r2s oled plugin by default
sed -i "s/enable '0'/enable '1'/" `find package/ -follow -type f -path '*/luci-app-oled/root/etc/config/oled'` 2>/dev/null || true

# set default theme to argon
sed -i '/uci commit luci/i\uci set luci.main.mediaurlbase="/luci-static/argon"' `find package -type f -path '*/default-settings/files/*-default-settings'` 2>/dev/null || true

mkdir -p `find package/ -follow -type d -path '*/pdnsd-alt'`/patches 2>/dev/null || true
mv $GITHUB_WORKSPACE/patches/99-disallow-aaaa.patch `find package/ -follow -type d -path '*/pdnsd-alt'`/patches 2>/dev/null || true

# passwall: adjust dependencies
passwall_makefile=`find package/ -follow -type f -path '*/luci-app-passwall/Makefile'`
if [ -n "$passwall_makefile" ]; then
  line_number_INCLUDE_Xray=$(grep -m1 -n 'Include Xray' $passwall_makefile | cut -d: -f1)
  if [ -n "$line_number_INCLUDE_Xray" ]; then
    line_number_INCLUDE_Xray=$[$line_number_INCLUDE_Xray-1]
    sed -i ${line_number_INCLUDE_Xray}'d' $passwall_makefile
    sed -i ${line_number_INCLUDE_Xray}'d' $passwall_makefile
    sed -i ${line_number_INCLUDE_Xray}'d' $passwall_makefile
  fi
  line_number_INCLUDE_V2ray=$(grep -m1 -n 'Include V2ray' $passwall_makefile | cut -d: -f1)
  if [ -n "$line_number_INCLUDE_V2ray" ]; then
    line_number_INCLUDE_V2ray=$[$line_number_INCLUDE_V2ray-1]
    sed -i ${line_number_INCLUDE_V2ray}'d' $passwall_makefile
    sed -i ${line_number_INCLUDE_V2ray}'d' $passwall_makefile
    sed -i ${line_number_INCLUDE_V2ray}'d' $passwall_makefile
  fi
  sed -i 's/LUCI_DEPENDS:=/LUCI_DEPENDS:=+iptables-mod-iprange +iptables-mod-socket /' $passwall_makefile
fi

# inject the firmware version
strDate=`TZ=UTC-8 date +%Y-%m-%d`
status_pages=`find package/ -follow -type f \( -path '*/autocore/files/arm/index.htm' -o -path '*/autocore/files/x86/index.htm' -o -path '*/autocore/files/arm/rpcd_10_system.js' -o -path '*/autocore/files/x86/rpcd_10_system.js' \)`
for status_page in $status_pages; do
case $status_page in
  *htm)
    line_number_FV=`grep -n 'Firmware Version' $status_page | cut -d: -f 1`
    sed -i '/ver\./d' $status_page
    sed -i $line_number_FV' a <a href="https://github.com/'${GITHUB_REPOSITORY:-iceend/nanopi-openwrt}'" target="_blank">'${GITHUB_REPOSITORY:-iceend/nanopi-openwrt}'</a> '$strDate $status_page
    ;;
  *js)
    line_number_FV=`grep -m1 -n 'var fields' $status_page | cut -d: -f1`
    sed -i $line_number_FV' i var pfv = document.createElement('\''placeholder'\'');pfv.innerHTML = '\''<a href="https://github.com/'${GITHUB_REPOSITORY:-iceend/nanopi-openwrt}'" target="_blank">'${GITHUB_REPOSITORY:-iceend/nanopi-openwrt}'</a> '$strDate"';" $status_page
    line_number_FV=`grep -n 'Firmware Version' $status_page | cut -d : -f 1`
    sed -i '/Firmware Version/d' $status_page
    sed -i $line_number_FV' a _('\''Firmware Version'\''), pfv,' $status_page
    ;;
esac
done

# R2S specific: cpufreq voltage and kernel crypto module
case $DEVICE in
  r2s|r2c|r1p|r1p-lts)
    config_file_cpufreq=`find package/ -follow -type f -path '*/luci-app-cpufreq/root/etc/config/cpufreq'`
    if [ -n "$config_file_cpufreq" ]; then
      truncate -s-1 $config_file_cpufreq
      echo -e "\toption governor0 'schedutil'" >> $config_file_cpufreq
      echo -e "\toption minfreq0 '816000'" >> $config_file_cpufreq
      echo -e "\toption maxfreq0 '1512000'\n" >> $config_file_cpufreq
    fi

    crypto_mk=`find package/kernel/linux/modules -name 'crypto.mk' 2>/dev/null`
    if [ -n "$crypto_mk" ] && grep -q 'CONFIG_CRYPTO_LIB_BLAKE2S' $crypto_mk; then
      line_number_CONFIG_CRYPTO_LIB_BLAKE2S=$[`grep -n 'CONFIG_CRYPTO_LIB_BLAKE2S' $crypto_mk | cut -d: -f 1`+1]
      sed -i $line_number_CONFIG_CRYPTO_LIB_BLAKE2S' s/HIDDEN:=1/DEPENDS:=@(LINUX_5_4||LINUX_5_10)/' $crypto_mk
      sed -i 's/libblake2s.ko@lt5.9/libblake2s.ko/;s/libblake2s-generic.ko@lt5.9/libblake2s-generic.ko/' $crypto_mk
    fi
    ;;
esac

# u-boot rockchip version updates
sed -i 's/rk3399_bl31_v1.35.elf/rk3399_bl31_v1.36.elf/;s/rk3568_ddr_1560MHz_v1.13.bin/rk3568_ddr_1560MHz_v1.18.bin/;s/rk3568_bl31_v1.34.elf/rk3568_bl31_v1.43.elf/' package/boot/uboot-rockchip/Makefile 2>/dev/null || true
sed -i 's/kmod-usb-net-rtl8152/kmod-usb-net-rtl8152-vendor/' target/linux/rockchip/image/armv8.mk 2>/dev/null || true

## ugly fix of the read-only issue
sed -i '3 i sed -i "/^exit.*/i\\/bin\\/mount -o remount,rw /" /etc/rc.local' `find package -type f -path '*/default-settings/files/*-default-settings'` 2>/dev/null || true

sed -i 's/\+1017\,12/+1017\,13/;/ifdef CONFIG_MBO/i+NEED_GAS=y' package/network/services/hostapd/patches/200-multicall.patch 2>/dev/null || true

# add pwm fan control service for rockchip
if wget -q --spider https://github.com/friendlyarm/friendlywrt/commit/cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch 2>/dev/null; then
  wget -q https://github.com/friendlyarm/friendlywrt/commit/cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
  git apply cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch 2>/dev/null || true
  rm -f cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
  sed -i 's/pwmchip1/pwmchip0/' target/linux/rockchip/armv8/base-files/usr/bin/fa-fancontrol.sh target/linux/rockchip/armv8/base-files/usr/bin/fa-fancontrol-direct.sh 2>/dev/null || true
fi
