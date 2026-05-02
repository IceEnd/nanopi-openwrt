---
name: restore-r2s-openwrt-latest-build
overview: 将仓库迁移到官方 OpenWrt 最新稳定版构建 R2S 固件，并更新 GitHub Actions、R2S 配置、第三方包/脚本以尽量保留现有插件能力且不破坏其他机型配置。
todos:
  - id: explore-compatibility
    content: 使用 [subagent:code-explorer] 核对 R2S 构建链路
    status: completed
  - id: create-r2s-workflow
    content: 新增 R2S 官方稳定版 Actions 工作流
    status: completed
    dependencies:
      - explore-compatibility
  - id: update-package-config
    content: 更新 R2S、common、extra 包配置
    status: completed
    dependencies:
      - explore-compatibility
  - id: harden-scripts
    content: 整理 feeds、补丁和文件注入脚本
    status: completed
    dependencies:
      - update-package-config
  - id: update-docs-upgrade
    content: 更新仓库链接、升级脚本和文档
    status: completed
    dependencies:
      - create-r2s-workflow
      - harden-scripts
  - id: validate-release
    content: 验证构建、必需包和发布产物
    status: completed
    dependencies:
      - update-docs-upgrade
---

## User Requirements

- 让长期未更新的固件构建仓库恢复可用，优先支持 NanoPi R2S。
- 固件基于官方最新稳定版，尽量使用较新的内核与软件包。
- 当前只需要保证 R2S 能成功编译，但不要无关改动或破坏其他机型配置。
- 自动生成可下载的固件产物，并发布到仓库版本附件或构建产物中。
- 当前仓库地址为 iceend/nanopi-openwrt。

## Product Overview

该仓库需要重新成为一个面向 R2S 的稳定固件构建项目：用户触发构建后，可获得基于官方稳定版的 R2S 固件镜像、校验文件和构建信息。

## Core Features

- 编译 R2S 官方稳定版固件镜像。
- 尽量保留现有常用插件和软件包。
- 保留科学上网相关能力，包括 Passwall、OpenClash 等。
- 保留 IPv6、SQM、AdGuardHome 等常用增强能力。
- 自动上传固件、校验文件、配置和软件清单。
- 更新仓库说明和在线升级入口，指向 iceend/nanopi-openwrt。

## Tech Stack Selection

- 固件基线：官方 OpenWrt 最新稳定版；当前探测到的稳定版为 OpenWrt 25.12.2，并应在工作流中做成可配置输入，便于后续切换到新的稳定标签或回退到 24.10.x。
- 构建系统：OpenWrt 官方源码构建体系、feeds、seed 配置和 ImageBuilder 产物。
- 自动化平台：GitHub Actions，面向 iceend/nanopi-openwrt 的 R2S 专用构建与发布流程。
- 脚本语言：沿用仓库现有 Bash 脚本风格，但增加兼容性保护和失败诊断。
- 产物发布：上传 R2S 固件镜像、校验文件、.config、manifest、buildinfo；成功后可写入 Release。

## Implementation Approach

本次采用“新增或重构 R2S 专用官方稳定版构建链路”的方式，而不是继续依赖旧的 Lean/ImmortalWrt 缓存链路。现有 `.github/workflows/lo-test.yml` 依赖 `coolsnowwolf/lede`、`stupidloud` 仓库缓存、旧 owner guard 和旧 actions 版本，不适合作为最新官方固件的基础。

核心策略：

1. 以官方 OpenWrt 源码标签为构建基线，默认指向当前官方稳定标签，例如 `v25.12.2`。
2. R2S 工作流独立收敛，优先保证 R2S 构建成功；其他机型 seed 文件暂不做无关改动。
3. 对第三方包做“必需包强校验、可选包宽容降级”：

- 必需：Passwall、OpenClash、AdGuardHome、SQM、IPv6 相关能力。
- 可选：旧版主题、旧版 NAS/下载/代理插件、Lean 专属包等，如果官方稳定版下不可用，应改为模块、移除或文档说明，而不是让构建整体无意义失败。

4. `scripts/patches.sh` 从“假设目标树一定是 Lean/ImmortalWrt”的强 sed 脚本，调整为官方 OpenWrt 兼容的受保护脚本。
5. `scripts/merge_files.sh` 适配现代 OpenWrt firewall4/nftables，不再只依赖旧 `firewall.user`/iptables 行为。
6. 所有仓库链接、Release 下载地址、在线升级脚本从 `stupidloud/nanopi-openwrt` 更新为 `iceend/nanopi-openwrt`。

## Implementation Notes

- 构建性能：官方源码全量构建 CPU 和 I/O 开销较大，应启用 `ccache`、缓存 `dl/` 下载目录，并限制并发为 `nproc` 或安全值；失败时再执行 `make V=sc` 便于诊断。
- 可靠性：构建前后检查关键包是否进入最终 `.config` 或 manifest；如果 Passwall、OpenClash、AdGuardHome、SQM 等必需能力缺失，应让工作流失败并输出明确原因。
- 兼容性：OpenWrt 新版本默认 firewall4/nftables，旧 iptables 依赖需要显式确认，必要时加入 `iptables-nft`、nft tproxy 相关依赖或改写注入逻辑。
- 爆炸半径控制：不要删除或重写其他设备 seed；R2S 工作流独立完成后，再决定是否迁移其他机型。
- 安全性：Release 和升级脚本只引用当前仓库，不在日志中输出 secrets，不继续依赖外部私有缓存仓库。
- 仓库状态：不要操作未跟踪目录 `.tmp-passwall-packages/`，除非后续明确需要。

## Architecture Design

构建链路分为四层：

1. 仓库配置层  
`r2s.config.seed`、`common.seed`、`extra_packages.seed` 定义目标设备、内核/根文件系统选项和软件包集合。

2. 包源整合层  
`scripts/merge_packages.sh` 负责加入第三方 feeds 或 clone 自定义包，并对不可用包做显式降级。

3. OpenWrt 定制层  
`scripts/patches.sh` 与 `scripts/merge_files.sh` 负责默认 IP、主题、固件标识、文件覆盖、DNS/防火墙兼容逻辑等。

4. CI 构建发布层  
GitHub Actions 拉取官方 OpenWrt、更新 feeds、合成配置、构建固件、校验必需功能、上传 artifact 和 Release。

## Directory Structure

本次改造聚焦 R2S 构建链路，文件组织如下：

```
/Users/alchemy/Documents/github/nanopi-openwrt/
├── .github/
│   └── workflows/
│       ├── build-r2s.yml        # [NEW] R2S 官方稳定版专用构建工作流。负责拉取官方 OpenWrt、缓存下载与 ccache、执行 feeds/scripts/defconfig/build、上传固件和 Release。需要支持 openwrt_ref、release 开关、debug/verbose 输入。
│       ├── lo-test.yml          # [MODIFY] 旧构建流程说明或降级处理。避免继续误导用户使用 Lean/ImmortalWrt、stupidloud 缓存和旧 owner guard；保留历史参考或明确标记为 legacy。
│       └── dispatch.yml         # [MODIFY] 调整为 R2S 优先入口，避免默认触发所有设备；如保留 repository_dispatch，应与新 R2S 工作流输入保持一致。
├── scripts/
│   ├── merge_packages.sh        # [MODIFY] 重整第三方 feeds/package 集成。保留 Passwall、OpenClash、AdGuardHome 等核心包；移除或保护旧分支、旧主题、Lean 专属包和不可用包。
│   ├── patches.sh               # [MODIFY] 改为官方 OpenWrt 兼容补丁脚本。所有 sed/find/git apply 都需检测文件存在；删除 R2S 无关的旧内核、R1S/R6S、Lean 专属 hack。
│   ├── merge_files.sh           # [MODIFY] 适配官方 OpenWrt 文件覆盖和 firewall4/nftables。避免重复追加旧 iptables 规则，必要时生成 nft include 文件。
│   ├── autoupdate-bash.sh       # [MODIFY] 更新 Release 查询和下载仓库为 iceend/nanopi-openwrt，并适配新的 R2S 产物命名。
│   ├── autoupdate.sh            # [MODIFY] 更新在线升级下载地址、仓库名、校验文件命名和失败提示。
│   └── autoupdate-offline.sh    # [MODIFY] 同步离线升级脚本的仓库地址和产物命名。
├── r2s.config.seed              # [MODIFY] 校准官方 OpenWrt R2S target 与默认包。保留 R2S、rootfs、USB 网卡、Passwall、OpenClash、AdGuardHome、SQM、IPv6 等关键能力。
├── common.seed                  # [MODIFY] 清理共享包集合。将官方稳定版不存在或高风险的旧包降级为模块、移除或转交第三方 feed；保留通用增强能力。
├── extra_packages.seed          # [MODIFY] 更新 slim/可选模块集合，确保包名符合官方稳定版和新 feeds。
├── files/
│   └── etc/
│       └── nftables.d/
│           └── 10-dns-redirect.nft # [NEW] 如仍需 DNS 劫持规则，使用 firewall4/nftables 兼容方式注入，避免只依赖 firewall.user。
├── README.md                    # [MODIFY] 更新仓库地址、构建入口、R2S 使用方式、默认版本、产物说明和在线升级说明。
└── CHANGELOG.md                 # [MODIFY] 记录迁移到官方 OpenWrt 稳定版、R2S 优先恢复构建和已知包兼容调整。
```

## Key Code Structures

不需要新增复杂接口。关键约定应体现在工作流输入与脚本约定中：

- `openwrt_ref`：官方 OpenWrt 标签或分支，默认当前稳定版标签。
- `device`：当前仅保证 `r2s`。
- `release`：是否创建或覆盖 Release。
- `REQUIRED_PACKAGES`：工作流内用于校验必需功能的软件包列表。

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose: 在实施前继续复核工作流、seed、脚本和包源之间的完整构建链路。
- Expected outcome: 输出 R2S 官方稳定版构建所需的精确文件修改点、不可用包清单和替代/降级建议。