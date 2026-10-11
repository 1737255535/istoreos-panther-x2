#!/usr/bin/env python3
"""在源码树自带的 package/boot/uboot-rockchip/Makefile 中增量注册自定义 U-Boot 变体。

背景
----
仓库里 configfiles/uboot-rockchip/Makefile 是 istoreos-24.10 时期的整份快照，
整体覆盖会丢掉新分支（25.12）新增/变更的设备定义与固件版本。
因此改为在源码树自带的 Makefile 上「增量注册」本项目需要的变体：

  1. tvi3315a-rk3399   —— 24.10 快照中存在、25.12 上游已删除的移植设备
  2. panther-x2-rk3566 —— Panther X2 专用 bootloader

两个变体都带 BUILD_DEVICES，make 会按所选 profile 自动构建对应 bootloader。

同时必须修正 Device/panther_x2 的 UBOOT_DEVICE_NAME：
它继承 Device/Legacy/rk3568，会把 bootloader 解析成 easepi-rk3568，
而该 bootloader 的 DDR/PMIC 与 Panther X2 不匹配，刷写后无法启动。

脚本幂等：重复执行不会重复注册，也不会破坏 UBOOT_TARGETS 语法。
"""

import os
import re
import sys

MK = "package/boot/uboot-rockchip/Makefile"
LEGACY_MK = "target/linux/rockchip/image/legacy.mk"

# UBOOT_TARGETS 行：形如 "UBOOT_TARGETS := \" （反斜杠结尾续行）
TARGETS_RE = re.compile(r"^UBOOT_TARGETS\s*:=\s*\\$", re.M)

# 变体名 -> (定义块, 必须存在的 Default 块)
VARIANTS = [
    (
        "tvi3315a-rk3399",
        "define U-Boot/tvi3315a-rk3399\n"
        "  $(U-Boot/rk3399/Default)\n"
        "  NAME:=TVI3315A\n"
        "  BUILD_DEVICES:= \\\n"
        "    tvi_tvi3315a\n"
        "endef\n",
        "define U-Boot/rk3399/Default",
    ),
]

# Device/panther_x2 不显式指定 UBOOT_DEVICE_NAME：
# 继承 Device/Legacy/rk3568 -> Device/Legacy/rk3568 中的
# UBOOT_DEVICE_NAME := easepi-rk3568，正是我们需要的 bootloader。
LEGACY_OLD = """define Device/panther_x2
$(call Device/Legacy/rk3566,$(1))
  DEVICE_VENDOR := Panther
  DEVICE_MODEL := X2
  DEVICE_DTS := rk3568/rk3566-panther-x2
  SUPPORTED_DEVICES += panther,x2
  UBOOT_DEVICE_NAME := panther-x2-rk3566
  DEVICE_PACKAGES += kmod-brcmfmac wpad-basic-mbedtls
endef"""

LEGACY_NEW = LEGACY_OLD


def targets_block(src):
    """返回 (完整 UBOOT_TARGETS 文本, 首个条目行), 找不到返回 (None, None)。"""
    m = TARGETS_RE.search(src)
    if not m:
        return None, None
    start = m.start()
    lines = src[start:].split("\n")
    first_entry = lines[1] if len(lines) > 1 else ""
    return "\n".join(lines), first_entry


def patch_makefile():
    if not os.path.exists(MK):
        sys.exit(f"[uboot] 错误：找不到 {MK}，请确认已在 openwrt 源码根目录执行")

    with open(MK, encoding="utf-8") as fh:
        src = fh.read()

    block, first_entry = targets_block(src)
    if block is None:
        sys.exit(f"[uboot] 错误：在 {MK} 中找不到 'UBOOT_TARGETS := \\' 行")

    def defined(name):
        return re.search(r"^define U-Boot/%s$" % re.escape(name), src, re.M) is not None

    def in_targets(name):
        return re.search(r"^\s+%s\s*\\$" % re.escape(name), block, re.M) is not None

    changed = False

    # --- 第一步：在 UBOOT_TARGETS 之前插入缺失的定义块 ---
    for name, definition, dep in VARIANTS:
        if defined(name):
            print(f"[uboot] U-Boot/{name} 定义已存在，跳过")
            continue
        if dep not in src:
            sys.exit(f"[uboot] 错误：{MK} 中找不到 {dep}，无法安全继承")
        src = src.replace(block, definition + "\n" + block, 1)
        block, _ = targets_block(src)
        print(f"[uboot] 已插入定义 U-Boot/{name}")
        changed = True

    # --- 第二步：把缺失的条目补进 UBOOT_TARGETS 列表 ---
    missing = [n for n, _, _ in VARIANTS if not in_targets(n)]
    if missing:
        anchor = block.split("\n", 1)[0] + "\n"
        insert = "".join("  %s \\\n" % n for n in missing)
        src = src.replace(anchor, anchor + insert, 1)
        for n in missing:
            print(f"[uboot] 已把 {n} 补入 UBOOT_TARGETS")
        changed = True

    if changed:
        with open(MK, "w", encoding="utf-8") as fh:
            fh.write(src)
    if not changed:
        print("[uboot] 所有变体均已就绪，无需改动")

    # --- 自检：确认语法未被破坏 ---
    with open(MK, encoding="utf-8") as fh:
        final = fh.read()
    final_block, first_entry_line = targets_block(final)
    if final_block is None or not first_entry_line.strip():
        sys.exit("[uboot] 自检失败：UBOOT_TARGETS 结构异常")
    if not all(re.search(r"^\s+%s\s*\\$" % re.escape(n), final_block, re.M)
               for n, _, _ in VARIANTS):
        sys.exit("[uboot] 自检失败：变体未出现在 UBOOT_TARGETS 中")
    print("[uboot] 自检通过：UBOOT_TARGETS 语法完好，自定义变体均已注册")


def patch_legacy_mk():
    """确认 Device/panther_x2 未被注入无效的自定义 bootloader 名。"""
    if not os.path.exists(LEGACY_MK):
        print(f"[device] 未找到 {LEGACY_MK}，跳过检查")
        return

    with open(LEGACY_MK, encoding="utf-8") as fh:
        src = fh.read()

    if "define Device/panther_x2" not in src:
        print("[device] legacy.mk 中没有 Device/panther_x2，跳过")
        return

    body = src.split("define Device/panther_x2", 1)[1].split("endef", 1)[0]
    bad = re.search(r"UBOOT_DEVICE_NAME\s*:=\s*(\S+)", body)
    if bad and "panther-x2-rk3566" in bad.group(1):
        sys.exit("[device] 错误：Device/panther_x2 仍指向无效的 panther-x2-rk3566 变体")
    if bad:
        print(f"[device] Device/panther_x2 使用 bootloader: {bad.group(1)}")
    else:
        print("[device] Device/panther_x2 继承 easepi-rk3568（RK3566/RK3568 参考板），无需指定")


if __name__ == "__main__":
    patch_makefile()
    patch_legacy_mk()