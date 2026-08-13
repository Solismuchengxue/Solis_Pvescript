#!/usr/bin/env bash
# 00_base.sh —— PVE 9.x 安装后基础配置
#   - APT 源替换为国内镜像（deb822 格式，Debian 13 Trixie 底）
#   - 禁用企业源、去订阅弹窗（升级后自动重打补丁）
#   - 时区 / NTP 国内源 / 基础工具包
# 目标平台：Proxmox VE 9.x（Debian 13 Trixie）
#
# 常用环境变量：
#   MIRROR=ustc|tuna     镜像站（默认 ustc）
#   DO_UPGRADE=1         同时执行 apt full-upgrade（默认 0）
#   ASSUME_YES=1         无人值守，跳过所有确认
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ===== 可调参数 =====
MIRROR="${MIRROR:-ustc}"
SUITE="${SUITE:-trixie}"                 # Debian 13 代号
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
DO_UPGRADE="${DO_UPGRADE:-0}"
EXTRA_PKGS="${EXTRA_PKGS:-vim curl wget git htop tmux ca-certificates gnupg lsb-release}"

case "$MIRROR" in
  ustc) DEB_URL="https://mirrors.ustc.edu.cn/debian"
        SEC_URL="https://mirrors.ustc.edu.cn/debian-security"
        PVE_URL="https://mirrors.ustc.edu.cn/proxmox/debian/pve" ;;
  tuna) DEB_URL="https://mirrors.tuna.tsinghua.edu.cn/debian"
        SEC_URL="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
        PVE_URL="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve" ;;
  *) die "未知 MIRROR=$MIRROR（支持 ustc|tuna）" ;;
esac

# ---- 1. APT 源（deb822 格式）----
setup_sources(){
  msg_info "配置 APT 源（deb822，镜像=$MIRROR，suite=$SUITE）"
  local d=/etc/apt/sources.list.d f

  # 1a. 禁用企业源（pve + ceph）：改名 .disabled（apt 只读 .sources 后缀，改名即忽略）
  #     不往 deb822 里追加 Enabled: false —— 追加易带空行 → 残缺 stanza → apt 报 Malformed
  for f in "$d/pve-enterprise.sources" "$d/ceph.sources"; do
    [[ -f "$f" ]] || continue
    mv "$f" "$f.disabled"
    msg_ok "已禁用企业源：$(basename "$f") → .disabled"
  done

  # 1b. Debian 本体源
  backup_once "$d/debian.sources"
  cat > "$d/debian.sources" <<EOF
Types: deb
URIs: ${DEB_URL}
Suites: ${SUITE} ${SUITE}-updates ${SUITE}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${SEC_URL}
Suites: ${SUITE}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  msg_ok "已写入 debian.sources"

  # 1c. PVE no-subscription 源
  cat > "$d/pve-no-subscription.sources" <<EOF
Types: deb
URIs: ${PVE_URL}
Suites: ${SUITE}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  msg_ok "已写入 pve-no-subscription.sources"

  # 1d. 旧式 /etc/apt/sources.list 若残留 deb 行，注释掉避免与 deb822 冲突
  if [[ -f /etc/apt/sources.list ]] && grep -qE '^[[:space:]]*deb ' /etc/apt/sources.list; then
    backup_once /etc/apt/sources.list
    sed -i -E 's/^([[:space:]]*deb )/# \1/' /etc/apt/sources.list
    msg_ok "已注释旧 /etc/apt/sources.list 的 deb 行"
  fi
}

# ---- 2. 去订阅弹窗 ----
remove_subscription_nag(){
  local js=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
  [[ -f "$js" ]] || { msg_warn "未找到 proxmoxlib.js，跳过去弹窗"; return 0; }
  backup_once "$js"
  # 让“订阅状态判断”恒为 false（视为有效订阅），弹窗不再出现
  sed -i "s/data.status.toLowerCase() !== 'active'/false/g" "$js" || true
  # apt 升级覆盖后自动重打补丁
  cat > /etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ $? -eq 1 ]; then { echo 'Patching subscription nag...'; sed -i 's/data.status.toLowerCase() !== .active./false/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi"; };
EOF
  msg_ok “已移除订阅弹窗（并设置升级后自动重打）”
}

# ---- 3. 时区 ----
setup_timezone(){
  msg_info "设置时区：$TIMEZONE"
  timedatectl set-timezone "$TIMEZONE"
  msg_ok "时区：$(timedatectl show -p Timezone --value)"
}

# ---- 4. NTP 国内源 ----
setup_ntp(){
  if [[ -f /etc/chrony/chrony.conf ]]; then
    backup_once /etc/chrony/chrony.conf
    # 幂等：先删本脚本上次写入的块及原 pool/server 行，再追加
    sed -i '/# >>> pve-setup cn-ntp >>>/,/# <<< pve-setup cn-ntp <<</d' /etc/chrony/chrony.conf
    sed -i -E '/^[[:space:]]*(pool|server)[[:space:]]/d' /etc/chrony/chrony.conf
    cat >> /etc/chrony/chrony.conf <<'EOF'
# >>> pve-setup cn-ntp >>>
server ntp.aliyun.com iburst
server ntp.ntsc.ac.cn iburst
pool cn.pool.ntp.org iburst
# <<< pve-setup cn-ntp <<<
EOF
    systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true
    msg_ok "已配置 chrony 国内 NTP"
  else
    mkdir -p /etc/systemd/timesyncd.conf.d
    cat > /etc/systemd/timesyncd.conf.d/cn.conf <<'EOF'
[Time]
NTP=ntp.aliyun.com ntp.ntsc.ac.cn
FallbackNTP=cn.pool.ntp.org
EOF
    timedatectl set-ntp true 2>/dev/null || true
    systemctl restart systemd-timesyncd 2>/dev/null || true
    msg_ok "已配置 systemd-timesyncd 国内 NTP"
  fi
}

# ---- 5. 系统语言（zh_CN.UTF-8）----
setup_locale(){
  msg_info "配置系统语言：zh_CN.UTF-8"
  # locales 包通常已装；apt cache 在 update_and_pkgs 前可能未刷新，用 || true 兜底
  DEBIAN_FRONTEND=noninteractive apt-get -y install locales 2>/dev/null || true
  # 幂等：去掉注释行的 #；若行不存在则追加
  if grep -q 'zh_CN\.UTF-8' /etc/locale.gen 2>/dev/null; then
    sed -i 's/^#[[:space:]]*\(zh_CN\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  else
    echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen
  fi
  # 保留 en_US.UTF-8 作为 fallback
  sed -i 's/^#[[:space:]]*\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen 2>/dev/null || true
  locale-gen
  update-locale LANG=zh_CN.UTF-8
  msg_ok "系统语言已设置为 zh_CN.UTF-8（重新登录终端后生效）"
}

# ---- 6. 更新 + 基础包 ----
update_and_pkgs(){
  msg_info "apt update ..."
  apt-get update
  if [[ "$DO_UPGRADE" == "1" ]]; then
    msg_info "apt full-upgrade ..."
    DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
  fi
  msg_info "安装基础工具：$EXTRA_PKGS"
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get -y install $EXTRA_PKGS
  msg_ok "基础包安装完成"
}

main(){
  need_root
  need_pve9
  msg_info "===== 00 基础配置开始 ====="
  confirm "将替换 APT 源 / 去订阅弹窗 / 配时区+NTP / 装基础包，继续?" || die "已取消"
  setup_sources
  remove_subscription_nag
  setup_timezone
  setup_ntp
  update_and_pkgs
  setup_locale
  msg_ok "===== 00 基础配置完成 ====="
  msg_warn "升级内核前请先完成 04/05（IOMMU 与 vGPU 驱动）并 pin 内核，避免驱动被新内核搞挂"
  msg_info "重启 pveproxy（浏览器控制台会短暂断线，刷新页面即可）..."
  systemctl --no-block restart pveproxy.service 2>/dev/null || true
}
main "$@"
