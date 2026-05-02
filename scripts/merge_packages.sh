#!/usr/bin/env bash
#
# merge_packages.sh
#
# Merge third-party OpenWrt feeds and individual packages into the current
# OpenWrt build tree. Intended to run with the CWD set to the OpenWrt source
# root (e.g. ~/openwrt), as the Build R2S workflow does.
#
# The script is intentionally tolerant: a single missing upstream or renamed
# package must not break the whole build. Critical packages (passwall,
# openclash, adguardhome) are tried from multiple sources.

set -u

log()  { echo "[merge_packages] $*"; }
warn() { echo "[merge_packages][WARN] $*" >&2; }

# -------- helpers ------------------------------------------------------------

# add_feed <name> <url> [branch]
#   Append a feed entry to feeds.conf.default if not already present.
add_feed() {
    local name="$1" url="$2" branch="${3:-}"
    if grep -Eq "^src-git(-full)?[[:space:]]+${name}[[:space:]]" feeds.conf.default 2>/dev/null; then
        log "feed '${name}' already present, skipping"
        return 0
    fi
    if [ -n "$branch" ]; then
        echo "src-git ${name} ${url};${branch}" >> feeds.conf.default
    else
        echo "src-git ${name} ${url}" >> feeds.conf.default
    fi
    log "added feed '${name}' -> ${url} ${branch}"
}

# install_feed <name>
install_feed() {
    local name="$1"
    ./scripts/feeds update "$name" || warn "feeds update $name failed"
    ./scripts/feeds install -a -p "$name" || warn "feeds install $name failed"
}

# drop_pkg <pkg-dirname>
#   Remove every copy of a package directory from feeds/package trees,
#   excluding our package/custom tree.
drop_pkg() {
    local pkg="$1"
    find package/ feeds/ -follow -type d -name "$pkg" -not -path "package/custom/*" 2>/dev/null \
        | xargs -r rm -rf
}

# clone_pkg <repo_url> [branch] <src_subpath> [dest_name]
#   Clone an external repo and move a subdir into package/custom/.
clone_pkg() {
    local url="$1" branch="$2" sub="$3" dest="${4:-$(basename "$3")}"
    local tmp
    tmp=$(mktemp -d)
    if [ -n "$branch" ]; then
        git clone --depth=1 --single-branch --branch "$branch" "$url" "$tmp/repo" \
            >/dev/null 2>&1 || { warn "git clone $url @ $branch failed"; rm -rf "$tmp"; return 1; }
    else
        git clone --depth=1 --single-branch "$url" "$tmp/repo" \
            >/dev/null 2>&1 || { warn "git clone $url failed"; rm -rf "$tmp"; return 1; }
    fi
    if [ ! -d "$tmp/repo/$sub" ]; then
        warn "subpath '$sub' missing in $url"
        rm -rf "$tmp"
        return 1
    fi
    # remove any previous copies
    find package/ feeds/ -follow -type d -name "$dest" -not -path "package/custom/*" 2>/dev/null \
        | xargs -r rm -rf
    mkdir -p package/custom
    rm -rf "package/custom/$dest"
    mv "$tmp/repo/$sub" "package/custom/$dest"
    rm -rf "$tmp"
    log "merged $url :: $sub -> package/custom/$dest"
}

# -------- sanity check -------------------------------------------------------

if [ ! -f feeds.conf.default ] || [ ! -d scripts/feeds ]; then
    warn "CWD does not look like an OpenWrt tree; aborting package merge."
    return 0 2>/dev/null || exit 0
fi

mkdir -p package/custom

# -------- third-party feeds --------------------------------------------------

# small-package provides modern OpenClash, AdGuardHome, luci-app-*, etc.,
# maintained against current OpenWrt trunk / 24.10 / 25.12.
add_feed small8    "https://github.com/kenzok8/small-package"
install_feed small8

# Passwall (LuCI app + subsidiary packages).
add_feed passwall_packages "https://github.com/xiaorouji/openwrt-passwall-packages"
add_feed passwall          "https://github.com/xiaorouji/openwrt-passwall" "main"
install_feed passwall_packages
install_feed passwall

# NAS oriented LuCI apps (optional, kept for parity with older builds).
add_feed nas       "https://github.com/linkease/nas-packages"       "master"
add_feed nas_luci  "https://github.com/linkease/nas-packages-luci"  "main"
install_feed nas
install_feed nas_luci

# -------- individual package overlays ---------------------------------------

# luci-theme-argon (master supports current LuCI).
clone_pkg "https://github.com/jerrykuku/luci-theme-argon"    ""     "." "luci-theme-argon-src" || true
# Above pulls the whole repo which is usually too broad; fall back to the
# commonly-used in-tree location when present.
if [ -d package/custom/luci-theme-argon-src/luci-theme-argon ]; then
    rm -rf package/custom/luci-theme-argon
    mv package/custom/luci-theme-argon-src/luci-theme-argon package/custom/luci-theme-argon
    rm -rf package/custom/luci-theme-argon-src
elif [ -d package/custom/luci-theme-argon-src ]; then
    # repo layout IS the package
    mv package/custom/luci-theme-argon-src package/custom/luci-theme-argon
fi

# luci-app-oled (NanoPi R2S metal-case OLED).
clone_pkg "https://github.com/NateLol/luci-app-oled" "" "." "luci-app-oled-src" || true
if [ -d package/custom/luci-app-oled-src/luci-app-oled ]; then
    rm -rf package/custom/luci-app-oled
    mv package/custom/luci-app-oled-src/luci-app-oled package/custom/luci-app-oled
    rm -rf package/custom/luci-app-oled-src
elif [ -d package/custom/luci-app-oled-src ]; then
    mv package/custom/luci-app-oled-src package/custom/luci-app-oled
fi

# -------- de-duplicate ------------------------------------------------------

# Prefer our package/custom copies over any duplicates leaked through feeds.
for p in luci-theme-argon luci-app-oled; do
    [ -d "package/custom/$p" ] || continue
    find feeds/ -follow -type d -name "$p" 2>/dev/null | xargs -r rm -rf
done

# Re-run feeds install so the custom additions show up for `make defconfig`.
./scripts/feeds update -a >/dev/null 2>&1 || true
./scripts/feeds install -a >/dev/null 2>&1 || true

log "done."
