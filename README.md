# iStoreOS for Panther X2 (RK3566)

基于 [iStoreOS-Native-main](https://github.com/xiaomeng9597/iStoreOS-Native-main) 自动编译 iStoreOS 固件，针对 Panther X2 (RK3566) 设备优化。

## 功能特性

- 自动每日编译最新 iStoreOS 固件
- 基于已验证可编译通过的 iStoreOS-Native-main 版本
- 集成 OpenClash、Lucky、Zerotier 等插件
- 支持 Docker、SMB、NFS 等服务
- 自动发布到 GitHub Releases

## 默认配置

- 管理地址: 192.168.100.1
- 用户名: root
- 密码: password
- 单网口设备，默认网口为 LAN（旁路由模式）

## 使用方法

1. Fork 本仓库
2. 在 Settings -> Secrets 中添加 `ACCESS_TOKEN`（GitHub Personal Access Token）
3. 在 Actions 页面启用 workflow
4. 等待自动编译完成，固件将发布到 Releases

## 手动编译

1. 点击 Actions -> Build iStoreOS for Panther X2 (RK3566)
2. 点击 "Run workflow"
3. 等待编译完成

## 目录结构

```
.
├── .github/workflows/
│   └── build-istoreos-6.x.yml    # GitHub Actions 工作流
├── armv8/
│   ├── .config                   # OpenWrt 编译配置
│   └── feeds.conf                # Feed 源
├── configfiles/
│   ├── dts/rk3568/              # 设备树文件（含 Panther X2）
│   ├── firmware/brcm/           # WiFi 固件
│   ├── uboot-rockchip/          # U-Boot 配置
│   └── ...
├── scripts/
│   ├── 01_get_ready.sh          # 准备脚本
│   ├── 02_add_device.sh         # 添加设备支持
│   └── 03_prepare_package.sh    # 准备软件包
└── depends/
    └── ubuntu-22.04             # 编译依赖
```

## 自定义

### 添加软件包

编辑 `scripts/03_prepare_package.sh` 或 `armv8/.config`。

### 修改 feeds

编辑 `armv8/feeds.conf` 添加自定义 feed 源。

### 修改固件版本信息

编辑 `scripts/01_get_ready.sh` 中的 `author` 变量。

## 致谢

- [iStoreOS](https://github.com/istoreos/istoreos)
- [OpenWrt](https://openwrt.org)
- [iStoreOS-Native-main](https://github.com/xiaomeng9597/iStoreOS-Native-main)
