# NanoPi R2S OpenWrt 固件

> Fork 自 [stupidloud/nanopi-openwrt](https://github.com/stupidloud/nanopi-openwrt)，针对 R2S 设备进行了定制化改造。

[刷机工具](https://www.balena.io/etcher/)  
[下载地址](#下载地址)  
[更新说明](#更新说明)  
[使用提示](#使用提示)  
[固件特性](#固件特性)  

### 下载地址：
进入本仓库的 [Releases](../../releases) 页面下载最新固件。  
(img.gz档不需要解压，可以直接使用刷机工具刷入)

### 使用提示：
默认用户名是root, 密码是password，局域网IP为192.168.2.1  
烧制完固件插入tf卡并启动完成，电脑端显示"网络（已连接）"之后，在浏览器输入 http://192.168.2.1 可以直接打开路由器后台。  
如果网络状态一直是未识别（上电超过5分钟），请直接插拔一次电源重启试试。

### 如何构建：
1. Fork 本仓库
2. 进入 Actions 页面，点击左侧 **build** 工作流
3. 点击右侧 **Run workflow**，device 输入 `r2s`，点击运行
4. 等待约 2-4 小时，固件会自动发布到 Releases

如果需要自定义软件包，编辑 `r2s.config.seed` 和 `common.seed` 文件即可。

### 固件特性：
- 基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 源码编译
- slim版固件只有OpenWrt本体，但内置了"本地软件源"，包含大部分常用插件
- 完整版预装 OpenClash、PassWall、AdGuardHome、SmartDNS 等常用插件
- 采用ext4文件系统，刷卡之后可自行使用分区工具对sd卡扩容根分区至最大
- 支持usb无线网卡（RTL8821CU芯片），可以驱动无线网卡运行在5G频段
- 输出完整版、slim版、with-docker版三种镜像

### 更新说明：
见 [CHANGELOG.md](./CHANGELOG.md)

#### 固件源码：
https://github.com/coolsnowwolf/lede
