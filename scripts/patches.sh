#!/usr/bin/env bash
#
# patches.sh
#
# Apply small, safe customisations to an upstream OpenWrt source tree.
# Run with CWD == OpenWrt source root.
#
# Every mutation is guarded so that missing files do not break the build when
# running against different OpenWrt versions or when a given package is not
# selected.

set -u

log()  { echo "[patches] $*"; }
warn() { echo "[patches][WARN] $*" >&2; }

DEVICE="${DEVICE:-r2s}"
REPO_URL="${REPO_URL:-https://github.com/iceend/nanopi-openwrt}"
REPO_LABEL="${REPO_LABEL:-iceend/nanopi-openwrt}"
WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"

# ---- helpers ----------------------------------------------------------------

# sed_if <pattern> <sed-expr> <files...>
#   Apply a sed expression in-place on every file that exists and matches the
#   trigger pattern, silently doing nothing otherwise.
sed_if() {
    local expr="$1"; shift
    for f in "$@"; do
        [ -f "$f" ] || continue
        sed -i "$expr" "$f" || warn "sed '$expr' on $f failed"
    done
}

find_files() {
    # usage: find_files <find-expr...>
    find package/ feeds/ -follow "$@" 2>/dev/null || true
}

# ---- sanity -----------------------------------------------------------------

if [ ! -d package ] || [ ! -d target ] || [ ! -f rules.mk ]; then
    warn "CWD does not look like an OpenWrt tree; skipping patches."
    return 0 2>/dev/null || exit 0
fi

# ---- default LAN IP: 192.168.1.1 -> 192.168.2.1 -----------------------------

if [ -f package/base-files/files/bin/config_generate ]; then
    sed -i 's|192\.168\.1\.1|192.168.2.1|g' package/base-files/files/bin/config_generate
    log "default LAN IP set to 192.168.2.1"
fi

# ---- disable aggressive br-netfilter sysctls --------------------------------

if [ -f package/kernel/linux/files/sysctl-br-netfilter.conf ]; then
    sed -i 's/=1/=0/g' package/kernel/linux/files/sysctl-br-netfilter.conf
fi

# ---- default theme: Argon ---------------------------------------------------

for f in $(find_files -type f -path '*/default-settings/files/*-default-settings'); do
    if ! grep -q 'luci.main.mediaurlbase=.luci-static/argon.' "$f"; then
        sed -i '/uci commit luci/i\uci set luci.main.mediaurlbase="/luci-static/argon"' "$f" \
            || warn "theme inject failed on $f"
    fi
done

# ---- Enable R2S OLED plugin by default, if present --------------------------

for f in $(find_files -type f -path '*/luci-app-oled/root/etc/config/oled'); do
    sed -i "s/enable '0'/enable '1'/" "$f" || true
done

# ---- Inject firmware version / source attribution ---------------------------

strDate="$(TZ=UTC-8 date +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"

for status_page in $(find_files -type f \( \
        -path '*/autocore/files/arm/index.htm' -o \
        -path '*/autocore/files/x86/index.htm' -o \
        -path '*/autocore/files/arm/rpcd_10_system.js' -o \
        -path '*/autocore/files/x86/rpcd_10_system.js' \)); do
    case "$status_page" in
      *.htm)
        line=$(grep -n 'Firmware Version' "$status_page" | head -n1 | cut -d: -f1 || true)
        if [ -n "$line" ]; then
            sed -i '/ver\./d' "$status_page" || true
            sed -i "${line} a <a href=\"${REPO_URL}\" target=\"_blank\">${REPO_LABEL}</a> ${strDate}" "$status_page" || true
        fi
        ;;
      *.js)
        line=$(grep -m1 -n 'var fields' "$status_page" | cut -d: -f1 || true)
        if [ -n "$line" ]; then
            sed -i "${line} i var pfv = document.createElement('placeholder');pfv.innerHTML = '<a href=\"${REPO_URL}\" target=\"_blank\">${REPO_LABEL}</a> ${strDate}';" "$status_page" || true
            l2=$(grep -n 'Firmware Version' "$status_page" | head -n1 | cut -d: -f1 || true)
            if [ -n "$l2" ]; then
                sed -i '/Firmware Version/d' "$status_page" || true
                sed -i "${l2} a _('Firmware Version'), pfv," "$status_page" || true
            fi
        fi
        ;;
    esac
done

# ---- pdnsd-alt: optional AAAA blocking patch --------------------------------

pdnsd_dir="$(find_files -type d -path '*/pdnsd-alt' | head -n1)"
if [ -n "$pdnsd_dir" ] && [ -f "$WORKSPACE/patches/99-disallow-aaaa.patch" ]; then
    mkdir -p "$pdnsd_dir/patches"
    cp "$WORKSPACE/patches/99-disallow-aaaa.patch" "$pdnsd_dir/patches/" 2>/dev/null \
        && log "pdnsd-alt AAAA-block patch staged"
fi

# ---- Passwall Makefile tweaks (guarded) -------------------------------------

pw_mk="$(find_files -type f -path '*/luci-app-passwall/Makefile' | head -n1)"
if [ -n "$pw_mk" ]; then
    if grep -q 'LUCI_DEPENDS' "$pw_mk"; then
        grep -q 'iptables-mod-iprange' "$pw_mk" || \
            sed -i 's|LUCI_DEPENDS:=|LUCI_DEPENDS:=+iptables-mod-iprange +iptables-mod-socket |' "$pw_mk"
    fi
fi

# ---- R2S / RK3328 cpufreq tweak (guarded) -----------------------------------

case "$DEVICE" in
    r2s|r2c|r1p|r1p-lts)
        cpufreq_cfg="$(find_files -type f -path '*/luci-app-cpufreq/root/etc/config/cpufreq' | head -n1)"
        if [ -n "$cpufreq_cfg" ] && ! grep -q "governor0 'schedutil'" "$cpufreq_cfg"; then
            truncate -s-1 "$cpufreq_cfg" 2>/dev/null || true
            {
                echo -e "\toption governor0 'schedutil'"
                echo -e "\toption minfreq0 '816000'"
                echo -e "\toption maxfreq0 '1512000'"
                echo
            } >> "$cpufreq_cfg"
            log "cpufreq schedutil profile applied for $DEVICE"
        fi
        ;;
esac

log "done."
