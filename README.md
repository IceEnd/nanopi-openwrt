# NanoPi R2S OpenWrt 固件 (iceend fork)

基于官方 OpenWrt 最新稳定版的 NanoPi R2S 固件构建仓库。

- 固件源码: 官方 [openwrt/openwrt](https://github.com/openwrt/openwrt)，默认 `v25.12.2`
- 支持设备: **NanoPi R2S** (其他机型的 seed 暂保留但未列入自动构建矩阵)
- 构建方式: GitHub Actions (`.github/workflows/build-r2s.yml`)
- 刷机工具推荐: [balenaEtcher](https://www.balena.io/etcher/)

## 下载

在 [Releases](https://github.com/iceend/nanopi-openwrt/releases) 页面下载最新的 `r2s-YYYY-MM-DD.img.gz`。`img.gz` 无需解压即可使用刷机工具写入 TF 卡。

## 默认信息

- 默认 LAN IP: `192.168.2.1`
- 默认用户名: `root`，密码: `password`（首次登录请立即修改）
- 默认主题: Argon

## 自行构建

1. Fork 本仓库到你自己的账号。
2. 打开 Actions → **Build R2S** → **Run workflow**，可选参数：
   - `openwrt_ref`: OpenWrt 的 tag 或分支，默认 `v25.12.2`。可填 `openwrt-25.12` 跟随 25.12 分支，或 `master` 跟随主干。
   - `release`: 是否把产物发到 Release（默认 `true`）。
   - `clean_build`: 是否忽略 dl/ccache 做干净编译。
   - `ssh_debug`: 失败时开 tmate 调试通道。
3. 运行成功后产物上传到 Release 和 artifact，含 `r2s-YYYY-MM-DD.img.gz`、`.md5`、`r2s.config`、`r2s.manifest`。

## 自定义固件

- 调整 R2S 默认预装插件/内核模块：编辑 `r2s.config.seed`。
- 调整跨机型的通用软件包：编辑 `common.seed`。
- 调整作为 slim/软件中心可选的模块：编辑 `extra_packages.seed`。
- 接入第三方 feeds/自定义包：编辑 `scripts/merge_packages.sh`。
- 打补丁、改默认 IP/主题/固件标识：编辑 `scripts/patches.sh`。

> `make defconfig` 会自动丢弃当前 OpenWrt 树里不存在的 `CONFIG_PACKAGE_*`，所以 seed 文件里可以保留一份"希望保留但暂时不可用"的包名清单，不会因为某个包临时缺失而中断整次构建。必需能力 (Passwall/OpenClash/AdGuardHome/SQM/IPv6) 会在工作流里显式校验，缺失时会输出 warning。

## 终端内在线升级

完整版固件:

```bash
wget -qO- https://github.com/iceend/nanopi-openwrt/raw/master/scripts/autoupdate-bash.sh | bash
```

slim 版 (如你发布了 slim 产物):

```bash
wget -qO- https://github.com/iceend/nanopi-openwrt/raw/master/scripts/autoupdate-bash.sh | ver=-slim bash
```

## 默认固件特性

- 科学上网: Passwall、OpenClash (通过第三方 feeds 合并)
- 广告拦截 / 分流: AdGuardHome、SmartDNS、mosdns
- 网络增强: SQM、wireguard、frpc、DDNS (Cloudflare/DNSPod/阿里云等)、IPv6 (odhcp6c / ipv6helper)
- 存储 / 分享: Samba4、KSMBD、diskman、filebrowser
- 监控: statistics + collectd、nlbwmon、vnstat2
- USB Wi-Fi 驱动: ath9k-htc、mt76x0u/mt76x2u、rtw88-usb、rtl8xxxu
- 默认 USB 网卡驱动: `kmod-usb-net-rtl8152-vendor`
- 主题: Argon (默认) / Bootstrap / Material

## 脚本一览

- `scripts/merge_packages.sh`: 合并第三方 feeds 与软件包
- `scripts/patches.sh`: 对 OpenWrt 源码做小范围默认值/品牌/补丁调整
- `scripts/merge_files.sh`: 把仓库 `files/` overlay 合并到 OpenWrt 构建树
- `scripts/autoupdate-bash.sh`: R2S 端终端在线升级
- `scripts/autoupdate.sh`: 旧的 zstd-helper 升级流程，已废弃，保留做参考

## 历史 / 旧工作流

`.github/workflows/lo-test.yml` 与 `.github/workflows/dispatch.yml` 是基于 `coolsnowwolf/lede` 的历史流程，依赖上游作者私有缓存仓库，已不可用。保留仅作参考，默认被 `if: github.repository_owner=='stupidloud'` guard 阻止。新流程请统一使用 `.github/workflows/build-r2s.yml`。

## 鸣谢

- 原仓库 [stupidloud/nanopi-openwrt](https://github.com/stupidloud/nanopi-openwrt) 的历史积累
- [openwrt/openwrt](https://github.com/openwrt/openwrt)
- [xiaorouji/openwrt-passwall](https://github.com/xiaorouji/openwrt-passwall)
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash)
- [kenzok8/small-package](https://github.com/kenzok8/small-package)
- [jerrykuku/luci-theme-argon](https://github.com/jerrykuku/luci-theme-argon)
- [NateLol/luci-app-oled](https://github.com/NateLol/luci-app-oled)
