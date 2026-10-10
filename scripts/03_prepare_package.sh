#!/bin/bash -e

# ============================================================================================================
# 自定义DIY⬇⬇⬇
# ============================================================================================================
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# TTYD
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init
#sed -i '/${interface:+-i \$interface}/s/^/# /' feeds/packages/utils/ttyd/files/ttyd.init

# samba4 default config
sed -i 's/invalid users = root/#invalid users = root/g' feeds/packages/net/samba4/files/smb.conf.template

# clash_meta：下载失败时必须报错，避免把 0 字节的假内核打进固件
mkdir -p files/etc/openclash/core
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
if wget -qO "$TMPDIR/clash_meta.tar.gz" "$CLASH_META_URL" && tar tzf "$TMPDIR/clash_meta.tar.gz" >/dev/null 2>&1; then
  tar xOvzf "$TMPDIR/clash_meta.tar.gz" > files/etc/openclash/core/clash_meta
  chmod +x files/etc/openclash/core/clash_meta
  echo "clash_meta 下载成功: $(du -h files/etc/openclash/core/clash_meta | cut -f1)"
  if [ ! -s files/etc/openclash/core/clash_meta ]; then
    echo "错误：clash_meta 内容为空，中止构建"; exit 1
  fi
else
  echo "错误：clash_meta 下载或解压失败，中止构建"; exit 1
fi
rm -f "$TMPDIR/clash_meta.tar.gz"

# clash_config：订阅配置。下载失败不阻断构建，但需明确告警
mkdir -p files/etc/config
if wget -qO files/etc/config/openclash "https://raw.githubusercontent.com/Kwonelee/Kwonelee/refs/heads/main/rule/openclash" && [ -s files/etc/config/openclash ]; then
  echo "clash 配置下载成功: $(du -h files/etc/config/openclash | cut -f1)"
else
  echo "警告：clash 配置下载失败，固件不含默认订阅（不影响编译）"
fi

# 集成无线驱动
mkdir -p package/base-files/files/lib/firmware/brcm
cp -a $GITHUB_WORKSPACE/configfiles/firmware/brcm/* package/base-files/files/lib/firmware/brcm/

# 处理Rust报错
#sed -i 's/ci-llvm=true/ci-llvm=false/g' feeds/packages/lang/rust/Makefile
rm -rf feeds/packages/lang/rust && git clone https://github.com/xiangfeidexiaohuo/extra-others && mv extra-others/rust feeds/packages/lang/

# golang 1.26
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# node - prebuilt
rm -rf feeds/packages/lang/node
git clone https://github.com/sbwml/feeds_packages_lang_node feeds/packages/lang/node -b packages-24.10

# zerotier
rm -rf feeds/packages/net/zerotier
git clone https://github.com/sbwml/feeds_packages_net_zerotier feeds/packages/net/zerotier

# 移除要替换的包
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf feeds/third_party/luci-app-LingTiGameAcc
rm -rf feeds/luci/applications/luci-app-filebrowser
rm -rf feeds/third_party/luci-app-zerotier

# Git稀疏克隆，只克隆指定目录到本地
# 上游仓库目录结构调整时不应中断整个构建：克隆失败或目录缺失时跳过并给出提示
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  local repodir
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  if ! git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl; then
    echo "警告：克隆 $repourl 失败，跳过：$*"
    rm -rf "$repodir"
    return 0
  fi
  cd $repodir || return 0
  if ! git sparse-checkout set "$@"; then
    echo "警告：$repourl 中不存在目录 $*，跳过"
    cd .. && rm -rf "$repodir"
    return 0
  fi
  mkdir -p ../package/new
  for d in "$@"; do
    [ -e "$d" ] || { echo "警告：$repourl 缺少 $d，跳过"; continue; }
    rm -rf "../package/new/$d"
    mv -f "$d" ../package/new
  done
  cd .. && rm -rf "$repodir"
}

# 常见插件
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash

# luci-app-lucky 上游已重构为 JS 视图（luci-app-lucky/htdocs/luci-static/resources/view/lucky/），
# 不再有 luasrc/view/lucky/lucky_status.htm，故不再覆盖旧版 Lua 状态页。
# 如需旧版样式，请改用 v3 分支：git_sparse_clone v3 https://github.com/gdy666/luci-app-lucky luci-app-lucky lucky
git_sparse_clone main https://github.com/gdy666/luci-app-lucky luci-app-lucky lucky

git_sparse_clone main https://github.com/sbwml/luci-app-openlist2 luci-app-openlist2 openlist2
git_sparse_clone main https://github.com/sbwml/openwrt_pkgs luci-app-zerotier
git_sparse_clone main https://github.com/Kwonelee/openwrt-packages luci-app-ramfree filebrowser luci-app-filebrowser-go
FB_VERSION="$(curl -s https://github.com/filebrowser/filebrowser/tags | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | sed 's/^v//')"
if [ -f package/new/filebrowser/Makefile ] && [ -n "$FB_VERSION" ]; then
  sed -i "s/2.54.0/$FB_VERSION/g" package/new/filebrowser/Makefile
fi
#git clone --depth=1 -b master https://github.com/w9315273/luci-app-adguardhome package/new/luci-app-adguardhome
