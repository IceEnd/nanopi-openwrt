---
name: R2S OpenWrt 镜像重建方案
overview: 对 fork 的 nanopi-openwrt 仓库进行单设备（R2S）定制化改造：修复工作流运行条件和过时依赖，移除对原作者私有缓存的依赖，保留所有原有软件包并对失效仓库做最小化剔除，最终通过 GitHub Actions 产出完整版 + slim 版 R2S 镜像并自动发布到 Release。
todos:
  - id: fix-workflow-core
    content: "改造 `.github/workflows/lo-test.yml`：删除 owner 判断、升级所有 Actions 到 v4、移除 btrfs+stupidloud 缓存逻辑、改为直接 git clone lede 源码、删除 tmate/telegram/save-cache 步骤、添加 `permissions: contents: write`"
    status: completed
  - id: fix-artifact-passing
    content: 改造 `generate_firmware` 和 `generate_slim_firmware` job：用 `actions/upload-artifact@v4` + `download-artifact@v4` 替代原从 stupidloud release 下载 ImageBuilder 的逻辑，确认 `svenstaro/upload-release-action` 配置正确
    status: completed
    dependencies:
      - fix-workflow-core
  - id: simplify-dispatch
    content: 精简或删除 `.github/workflows/dispatch.yml`（仅保留 r2s 或直接移除，改用 workflow_dispatch 手动触发 lo-test.yml）
    status: completed
    dependencies:
      - fix-workflow-core
  - id: verify-third-party-repos
    content: 使用 [subagent:code-explorer] 验证 `scripts/merge_packages.sh` 中所有第三方仓库的存活状态和默认分支，输出失效仓库清单
    status: completed
  - id: trim-merge-packages
    content: 修改 `scripts/merge_packages.sh`：为 merge_package 函数增加失败容错，根据验证结果移除失效仓库（如 stupidloud/helloworld），同步调整 r2s.config.seed / common.seed / extra_packages.seed 中对应包条目
    status: completed
    dependencies:
      - verify-third-party-repos
  - id: trim-patches
    content: 裁剪 `scripts/patches.sh`：删除 R1S / R1S-H3 / R6S / R6C 设备分支，保留 R2S 相关的 cpufreq、BLAKE2S、pwm-fan、u-boot、r8152-vendor、默认 IP、Argon 主题、OLED 启用等配置
    status: completed
  - id: update-readme-autoupdate
    content: 更新 `README.md` 说明 Fork 后的使用方法，可选修改 `scripts/autoupdate-bash.sh` 把仓库路径从 `stupidloud/nanopi-openwrt` 改为当前 Fork 仓库
    status: completed
    dependencies:
      - fix-artifact-passing
  - id: trigger-first-build
    content: 在 GitHub Actions 手动触发首次 R2S 构建，根据失败日志迭代剔除失效插件直到完整产出 R2S 固件和 slim 镜像并发布到 Releases
    status: completed
    dependencies:
      - fix-artifact-passing
      - simplify-dispatch
      - trim-merge-packages
      - trim-patches
---

## 产品概述

将这个长期未更新的 nanopi-openwrt 仓库进行改造，使其能够在 Fork 的仓库中通过 GitHub Actions 成功编译出**最新可用的 NanoPi R2S OpenWrt 固件**，并自动发布到当前仓库的 Releases 页面。

## 核心功能

- **单设备聚焦**：构建目标精简为仅 R2S，移除其他设备的构建逻辑
- **Actions 工作流可用性修复**：
- 移除硬编码的 `repository_owner=='stupidloud'` 判断，使 Fork 后能正常触发
- 升级所有已 deprecated 的 Actions（checkout/upload-artifact 等）到 v4
- 移除对原作者私有缓存仓库（stupidloud/sshactions）的所有依赖
- 修复 Release 发布的权限配置
- **源码与软件包最新化**：
- 每次构建从 `coolsnowwolf/lede` master 拉取最新源码
- Feeds、第三方插件、LuCI 均拉取最新版本
- 保留原仓库完整插件清单（OpenClash、PassWall、AdGuardHome、阿里云盘 WebDAV、OLED、Argon 主题等）
- **双版本输出**：
- 完整固件镜像（fat 版本，预装所有插件）
- 瘦身镜像（slim，通过 ImageBuilder 生成，包含本地软件源供后续按需安装）
- 均上传为 Artifact 并自动发布到当前仓库 Releases（tag 格式 `YYYY-MM-DD`）
- **R2S 硬件特性保留**：
- 默认主题 Argon、默认 IP 192.168.2.1
- OLED 屏幕插件默认启用
- CPU 超频配置（816MHz ~ 1512MHz）
- PWM 风扇控制补丁
- 网卡驱动优化（r8152 → r8152-vendor）
- **失效包处理策略**：采用增量剔除方式，首次失败后根据日志逐个移除 `merge_packages.sh` 中已失效的仓库和 `config.seed` 中对应的软件包条目

## 技术栈

- **CI/CD**：GitHub Actions（ubuntu-latest runner）
- **OpenWrt 源码**：`coolsnowwolf/lede` master 分支
- **编译工具链**：OpenWrt 官方 SDK（gcc / make / feeds 脚本）
- **固件打包**：ImageBuilder（用于生成 slim 版本）
- **目标平台**：rockchip/armv8，device profile `friendlyarm_nanopi-r2s`
- **Release 发布**：`svenstaro/upload-release-action@v2`（最新版）+ `GITHUB_TOKEN`
- **脚本语言**：Bash（继续使用现有 `scripts/*.sh` 体系）

## 实现方式

### 总体策略

采用**最小破坏性改造**：保留现有 `common.seed` / `extra_packages.seed` / `r2s.config.seed` / `files/` / `patches/` 的设计，仅对 **workflow 层** 和 **脚本中的设备分支判断、失效 URL** 做修改。这样未来恢复其他设备支持成本最低。

### 关键技术决策

1. **抛弃"复用编译缓存"模式**

- 原工作流依赖 `stupidloud/sshactions` 私有 Release 存储 btrfs loop 镜像和 ImageBuilder 压缩包，Fork 后完全失效
- 改为：**每次全量编译**（可接受，单次 R2S 编译约 60-90 分钟）
- ImageBuilder 产物通过 `actions/upload-artifact@v4` 在同一 workflow 的 job 之间传递（替代原跨仓库下载）

2. **Workflow 权限显式声明**

- 顶层或 job 层声明 `permissions: contents: write`，确保 `svenstaro/upload-release-action` 能创建 tag 和上传 assets
- 移除所有对 `SEC_TOKEN`、`TELEGRAM_*`、`SSH_*`、`TUNNEL_*` 等 secrets 的硬依赖（改为可选或直接删除相关步骤）

3. **Dispatch 流程简化**

- 废弃 `dispatch.yml` 的多设备 matrix（或精简为仅 r2s）
- `lo-test.yml` 保留 `workflow_dispatch` 可直接手动触发，默认 device=r2s

4. **patches.sh 裁剪**

- 删除 R1S / R1S-H3 / R6S / R6C 分支（~30 行），避免误触发
- 保留 R2S/R2C/R1P 共用的 cpufreq + BLAKE2S 调整
- x86 相关 sed 可保留（无害）或删除

5. **merge_packages.sh 风险处理**

- `stupidloud/helloworld;tmp` 分支极可能已失效，需要降级处理：
    - 若失效则直接删除该行，并在 config.seed 中移除 `luci-app-ssr-plus` 相关条目
    - OpenClash、PassWall 仍活跃，保留
- 增加 `git clone` 失败时的 fallback（`|| true`），避免单个仓库失效导致整个脚本中断

### 性能与可靠性

- **磁盘空间**：GitHub runner 默认 ~14GB 可用，编译 OpenWrt 需 ~20GB，保留现有 `sudo rm -rf /usr/share/dotnet` 等清理步骤；移除 btrfs loop 挂载（不必要，徒增风险）
- **编译并发**：保留 `con=$[nproc/2+3]`（4核×2+3=11，对 runner 合适）
- **失败容忍**：`IGNORE_ERRORS=1` 保留；`make download` 保留 while 循环重试
- **可观测性**：保留 `df -h` / `du -h` 空间诊断输出，失败时通过 Actions 日志排查

## 文件改造清单

```
nanopi-openwrt/
├── .github/workflows/
│   ├── lo-test.yml              # [MODIFY] 核心改造，见下方详述
│   └── dispatch.yml             # [MODIFY] 精简为仅 r2s 或直接删除
├── scripts/
│   ├── merge_packages.sh        # [MODIFY] 移除失效仓库（stupidloud/helloworld 等），增加 fallback
│   ├── patches.sh               # [MODIFY] 删除非 R2S 设备分支（R1S/R1S-H3/R6S/R6C）
│   ├── merge_files.sh           # [KEEP] 不改动
│   └── autoupdate-bash.sh       # [OPTIONAL] 把 stupidloud/nanopi-openwrt 替换为当前仓库路径
├── r2s.config.seed              # [KEEP] 首轮不动，构建失败后按需移除失效包
├── common.seed                  # [KEEP] 同上
├── extra_packages.seed          # [KEEP] 同上
├── files/                       # [KEEP] 默认配置文件
├── patches/99-disallow-aaaa.patch  # [KEEP] pdnsd 补丁
└── README.md                    # [OPTIONAL MODIFY] 更新 Fork 使用说明
```

### lo-test.yml 具体修改点

| 位置 | 动作 |
| --- | --- |
| 顶层 | 新增 `permissions: contents: write` |
| L25 | **删除** `if: github.repository_owner=='stupidloud'` |
| L48/L228/L275 | `actions/checkout@v2` → `actions/checkout@v4` |
| L55 | `curl ... zstd-bin/zstd` → 改为 `sudo apt install -y zstd` |
| L56-L69 | **整段重写**：移除 btrfs loop 挂载 + stupidloud 缓存下载，直接 `git clone -b $BRANCH --depth=1 https://github.com/coolsnowwolf/lede ~/lede` |
| L96-L107 | 删除 tmate debug 步骤（或用 `if: false` 保留代码但禁用） |
| L109-L115 | Clean build cache 步骤保留但简化 |
| L129 | ImageBuilder 输出路径保留；新增 `actions/upload-artifact@v4` 上传 `ib-r2s.tar.xz` 供下游 job 使用 |
| L162 | `actions/upload-artifact@v2` → `@v4` |
| L167-L199 | **整段删除** Save cache state 步骤 |
| L201-L217 | 删除 Telegram 通知 + 失败 tmate debug 步骤 |
| L237, L284 | `curl -L https://github.com/stupidloud/sshactions/...` → 改为 `actions/download-artifact@v4` 从 build_packages job 下载 |
| L255-L263, L317-L325 | `svenstaro/upload-release-action@v2` 保留，确认 `body`/`release_name` 配置合理 |


### dispatch.yml 具体修改点

| 位置 | 动作 |
| --- | --- |
| L28 | `matrix.device: [r1p, r1p-lts, ..., x86]` → `matrix.device: [r2s]` |
| L36 | `secrets.SEC_TOKEN` → `secrets.GITHUB_TOKEN`（但 repository_dispatch 需要 PAT，建议直接删除 dispatch.yml，改用 lo-test.yml 的 workflow_dispatch） |


### merge_packages.sh 具体修改点

| 位置 | 动作 |
| --- | --- |
| L1-L8 | `merge_package` 函数增加 `git clone ... \ | \ | return 0`，单仓库失败不中断整体 |
| L26 | `stupidloud/helloworld;tmp` → 失效则删除，同步移除 ssr-plus 相关 config 条目 |
| 其他行 | 保留，首轮构建失败后依据日志逐行剔除 |


### patches.sh 具体修改点

| 位置 | 动作 |
| --- | --- |
| L98-L113 | 删除 R6S/R6C 分支 |
| L116-L126 | 删除 R1S 分支 |
| L129-L131 | 删除 R1S-H3 分支 |
| 其他行 | 保留 |


## 关键实现备注

- **不引入新模式**：继续沿用 `common.seed` + `$device.config.seed` + `extra_packages.seed` 的三段配置合并逻辑
- **向后兼容**：保留 `build_packages` / `generate_firmware` / `generate_slim_firmware` 三个 job 结构，只替换其内部数据传递方式
- **敏感信息**：不再使用 `SEC_TOKEN`，仅依赖 runner 内置的 `GITHUB_TOKEN`
- **Release tag 冲突**：同一天多次构建会因 `overwrite: true` 直接覆盖，符合日常迭代需求
- **回滚策略**：若 Fork 后仍无法编译，可在 lo-test.yml 手动触发时通过 `branch` 输入切换为特定历史 tag 或其他源码源

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose: 在实施阶段验证 `merge_packages.sh` 中所有第三方仓库当前的存活状态和默认分支名（尤其 `stupidloud/helloworld;tmp`、`ilxp/luci-app-ikoolproxy`、`sundaqiang/openwrt-packages` 等），并确认 `patches.sh` 中基于源码路径的 sed 语句在 `coolsnowwolf/lede` 最新 master 上是否仍适用
- Expected outcome: 输出一份"失效仓库清单 + 替代方案 + 需要调整的 sed 行号"报告，用于指导 `merge_packages.sh` 和对应 config.seed 条目的精准裁剪