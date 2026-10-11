#!/bin/bash -e

# ============================================================================================================
# 移植RK3399示例，其他RK3399可模仿
# ============================================================================================================
# 增加设备
echo -e "\\ndefine Device/tvi_tvi3315a
  DEVICE_VENDOR := Tvi
  DEVICE_MODEL := TVI3315A
  SOC := rk3399
  UBOOT_DEVICE_NAME := tvi3315a-rk3399
endef
TARGET_DEVICES += tvi_tvi3315a" >> target/linux/rockchip/image/armv8.mk

# 不整体覆盖 package/boot/uboot-rockchip/Makefile：
# configfiles 中的副本是 24.10 时期的快照，覆盖会丢掉 25.12 的设备定义与固件版本。
# 改为由 scripts/patch_uboot_variant.py 增量注册 tvi3315a-rk3399 与 panther-x2-rk3566。

# 复制dts与配置文件到package/boot/uboot-rockchip
cp -f $GITHUB_WORKSPACE/configfiles/dts/rk3399/{rk3399.dtsi,rk3399-opp.dtsi,rk3399-tvi3315a.dts} package/boot/uboot-rockchip/src/arch/arm/dts/
cp -f $GITHUB_WORKSPACE/configfiles/uboot-rockchip/rk3399-tvi3315a-u-boot.dtsi package/boot/uboot-rockchip/src/arch/arm/dts/
cp -f $GITHUB_WORKSPACE/configfiles/uboot-rockchip/tvi3315a-rk3399_defconfig package/boot/uboot-rockchip/src/configs/

# 复制dts到files/arch/arm64/boot/dts/rockchip（仅 24.10 的 target 布局存在 files/ 目录）
if [ -d target/linux/rockchip/files/arch/arm64/boot/dts/rockchip ]; then
  cp -f $GITHUB_WORKSPACE/configfiles/dts/rk3399/{rk3399.dtsi,rk3399-opp.dtsi,rk3399-tvi3315a.dts} target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/
fi

# 添加dtb补丁到target/linux/rockchip/patches-$(KVER)
# 内核版本随源码分支变化（24.10 -> 6.6，25.12 -> 6.12），需自动探测
KVER="$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/rockchip/Makefile)"
PATCHDIR="target/linux/rockchip/patches-${KVER}"
echo "内核版本: ${KVER}，补丁目录: ${PATCHDIR}"

# 该补丁把 rk3399-tvi3315a.dtb 注册进内核 dts/rockchip/Makefile。
# 它依赖 target/linux/rockchip/files/ 注入 dts 的老机制，该目录仅 24.10 有；
# 且 tvi_tvi3315a 已不在构建目标中（.config 只启用 panther_x2），补丁对产物无影响。
# 25.12 已移除 files/ 布局，若强行套用，其 hunk 上下文会与前序 13 个已修改同一
# 文件的补丁冲突，导致 target/linux 编译失败。
if [ -d target/linux/rockchip/files/arch/arm64/boot/dts/rockchip ]; then
  cp -f $GITHUB_WORKSPACE/configfiles/patch/800-add-rk3399-tvi3315a-dtb-to-makefile.patch "${PATCHDIR}/"
  echo "已安装 800 补丁（24.10 布局，支持 files/ 注入）"
else
  echo "跳过 800 补丁：无 target/linux/rockchip/files/ 布局（25.12），补丁不适用"
fi

# ============================================================================================================
# 移植RK3566示例，其他RK35xx可模仿
# ============================================================================================================
# legacy.mk 不再整体覆盖：仓库内副本是 24.10 时期的快照，
# 覆盖会丢掉 25.12 新增的设备定义。改为直接在源码树自带的 legacy.mk 上追加 Panther X2。

# 复制dts与配置文件到package/boot/uboot-rockchip
# 仅保留 kernel 侧 dts；station-m2 的 u-boot dtsi/defconfig 属于 24.10 遗留，
# 25.12 已无对应 U-Boot 变体，故不再复制。
cp -f $GITHUB_WORKSPACE/configfiles/dts/rk3568/rk3566-roc-pc.dts package/boot/uboot-rockchip/src/arch/arm/dts/

# 复制dts到target/linux/rockchip/dts/rk3568
cp -f $GITHUB_WORKSPACE/configfiles/dts/rk3568/rk3566-jp-tvbox.dts target/linux/rockchip/dts/rk3568/

# 复制Panther X2 的 DTS 到源码树自带 dts 目录
cp -f $GITHUB_WORKSPACE/configfiles/dts/rk3568/rk3566-panther-x2.dts target/linux/rockchip/dts/rk3568/

# ============================================================================================================
# Panther X2 (RK3566) 支持
# ============================================================================================================
# 添加Panther X2设备定义到legacy.mk
cat >> target/linux/rockchip/image/legacy.mk << 'EOF'

define Device/panther_x2
$(call Device/Legacy/rk3566,$(1))
  DEVICE_VENDOR := Panther
  DEVICE_MODEL := X2
  DEVICE_DTS := rk3568/rk3566-panther-x2
  SUPPORTED_DEVICES += panther,x2
  DEVICE_PACKAGES += kmod-brcmfmac wpad-basic-mbedtls
endef
TARGET_DEVICES += panther_x2
EOF

# ============================================================================================================
# U-Boot 说明
# Panther X2 不再使用自定义 bootloader 变体，改为沿用 Device/Legacy/rk3568 继承来的
# easepi-rk3568（RK3566/RK3568 官方参考板，DDR/PMIC 配置与本板通用，
# ATF rk3568_bl31_v1.44.elf + TPL rk3566_ddr_1056MHz_v1.21.bin 均匹配 RK3566）。
#
# 曾尝试注册 panther-x2-rk3566 变体，但 u-boot 的 DTS 编译基于解压后的 tarball 源码树，
# 仓库内提供的 .dtsi 只是 include（不是板级 .dts），tarball 中并无
# arch/arm/dts/rockchip/rk3566-panther-x2.dts，导致：
#   make[6]: *** No rule to make target
#           'arch/arm/dts/rockchip/rk3566-panther-x2.dtb', needed by 'dtbs'.  Stop.
#
# 此处仅补齐 24.10 分支需要的 tvi3315a-rk3399 变体，并校验设备未指向无效变体。
python3 "$GITHUB_WORKSPACE/scripts/patch_uboot_variant.py"
