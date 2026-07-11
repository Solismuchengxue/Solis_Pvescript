#!/usr/bin/env bash
# 03_network.sh —— 网络与 IPv6 配置
#   场景（已与用户确认）：
#     · 上游光猫/路由器已下发 IPv6（LAN 内有 RA）
#     · VM/CT 桥接 vmbr0，与主机同 /64，各自 SLAAC 直拿公网 v6
#   故 host 侧只需三件事：
#     1) vmbr0 启用 SLAAC（inet6 auto），主机自己拿到 v6
#     2) accept_ra=2（即便将来开了 forwarding 也仍收 RA）
#     3) 确保未禁用 IPv6；并检查防火墙是否放行 ICMPv6
#
#   VM/CT 侧零配置：网卡接 vmbr0，guest 内开 SLAAC 即可（二层透传 RA）。
#
# 环境变量：
#   BRIDGE=vmbr0       目标网桥
#   DRY_RUN=1          只打印将做的改动，不落盘、不重载（强烈建议首次先跑）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

BRIDGE="${BRIDGE:-vmbr0}"
DRY_RUN="${DRY_RUN:-0}"
IFACES_FILE=/etc/network/interfaces
SYSCTL_FILE=/etc/sysctl.d/90-pve-ipv6.conf

# ---- 列出物理网卡及驱动/速率，重点标出 i226(igc) ----
detect_nics(){
  msg_info "物理网卡一览（i226 应为 igc 驱动、2500Mb/s）："
  local n name drv speed carrier
  for n in /sys/class/net/*; do
    name="$(basename "$n")"
    [[ -e "$n/device/driver" ]] || continue          # 仅物理口
    drv="$(basename "$(readlink -f "$n/device/driver")")"
    speed="$(cat "$n/speed" 2>/dev/null || echo '?')"
    carrier="$(cat "$n/carrier" 2>/dev/null || echo 0)"
    [[ "$carrier" == "1" ]] && carrier="link-up" || carrier="link-down"
    printf '    %-12s driver=%-8s speed=%sMb/s %s' "$name" "$drv" "$speed" "$carrier"
    [[ "$drv" == "igc" ]] && printf '  <== i226' ; echo
  done
}

# ---- 确认 vmbr0 现状与桥成员 ----
show_bridge(){
  if ! ip link show "$BRIDGE" >/dev/null 2>&1; then
    msg_warn "$BRIDGE 不存在（PVE 安装器一般已建好）；请确认桥名后用 BRIDGE= 指定"
    return 1
  fi
  local ports
  ports="$(ls -1 "/sys/class/net/$BRIDGE/brif" 2>/dev/null | tr '\n' ' ')"
  msg_info "$BRIDGE 桥成员：${ports:-（空）}"
  msg_info "$BRIDGE 当前地址："
  ip -brief addr show "$BRIDGE" || true
}

# ---- 在 interfaces 里为 vmbr0 启用 SLAAC（幂等，marker 块）----
enable_slaac(){
  local block="# >>> pve-setup ipv6 >>>
iface ${BRIDGE} inet6 auto
# <<< pve-setup ipv6 <<<"

  if [[ "$DRY_RUN" == "1" ]]; then
    msg_info "[DRY_RUN] 将向 $IFACES_FILE 追加："
    echo "$block" | sed 's/^/        /'
    return 0
  fi

  backup_once "$IFACES_FILE"
  # 删除上次写入的块，再追加（幂等）
  sed -i '/# >>> pve-setup ipv6 >>>/,/# <<< pve-setup ipv6 <<</d' "$IFACES_FILE"
  # 去掉可能的尾部多余空行后追加
  printf '\n%s\n' "$block" >> "$IFACES_FILE"
  msg_ok "已在 $IFACES_FILE 为 $BRIDGE 启用 inet6 auto（SLAAC）"
}

# ---- sysctl：不禁用 v6 + accept_ra=2 ----
apply_sysctl(){
  # default.* 是关键兜底：开机 systemd-sysctl 应用时 vmbr0 可能尚未创建，
  # conf.<bridge>.* 会写入失败；default.* 让随后创建的 vmbr0 继承到正确值。
  local content="# 由 03_network.sh 写入：桥接场景下主机仍能收 RA 拿 v6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.${BRIDGE}.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.ipv6.conf.${BRIDGE}.accept_ra = 2
net.ipv6.conf.all.autoconf = 1
net.ipv6.conf.default.autoconf = 1
net.ipv6.conf.${BRIDGE}.autoconf = 1"

  if [[ "$DRY_RUN" == "1" ]]; then
    msg_info "[DRY_RUN] 将写入 $SYSCTL_FILE："
    echo "$content" | sed 's/^/        /'
    return 0
  fi
  echo "$content" > "$SYSCTL_FILE"
  sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
  msg_ok "已写入并应用 $SYSCTL_FILE"
}

# ---- 检查 PVE 防火墙是否放行 ICMPv6 ----
check_firewall_icmpv6(){
  command -v pve-firewall >/dev/null 2>&1 || return 0
  if pve-firewall status 2>/dev/null | grep -qi 'enabled'; then
    msg_warn "PVE 防火墙已启用：请确保放行 ICMPv6（NDP/RA/RS/NS/NA），否则 v6 邻居发现会失败"
    msg_warn "  PVE 默认对 NDP 有内建放行；若自定义了严格规则，请手动确认 v6 ICMP 未被拦"
  else
    msg_info "PVE 防火墙未启用，ICMPv6 无需额外放行"
  fi
}

# ---- 重载网络（ifupdown2 热重载，尽量不断网）----
reload_network(){
  if [[ "$DRY_RUN" == "1" ]]; then
    msg_info "[DRY_RUN] 跳过 ifreload"
    return 0
  fi
  if command -v ifreload >/dev/null 2>&1; then
    msg_info "ifreload -a 热重载网络 ..."
    ifreload -a && msg_ok "网络已重载" || msg_warn "ifreload 返回非 0，请检查 $IFACES_FILE"
  else
    msg_warn "未找到 ifreload（ifupdown2）；请手动 systemctl restart networking 或重启"
  fi
}

main(){
  need_root
  need_pve9
  msg_info "===== 03 网络/IPv6 配置开始（DRY_RUN=$DRY_RUN）====="
  detect_nics
  echo
  show_bridge || true
  echo
  msg_warn "本步会修改 $IFACES_FILE 并热重载网络，存在短暂断网/配置失误风险"
  msg_warn "建议：先用 DRY_RUN=1 预览；正式执行时最好能直连键鼠或有控制台兜底"
  confirm "继续为 $BRIDGE 启用 IPv6(SLAAC) 并应用 sysctl?" || die "已取消"
  enable_slaac
  apply_sysctl
  check_firewall_icmpv6
  reload_network
  echo
  msg_ok "===== 03 完成 ====="
  msg_info "验证：ip -6 addr show $BRIDGE  应看到一个非 fe80 开头的公网 v6 地址"
  msg_info "VM/CT 侧：网卡桥接到 $BRIDGE，guest 内开 SLAAC 即自动获取公网 v6"
  msg_info "提示：要稳定对外暴露服务，guest 内建议关闭 privacy/临时地址或配静态 v6，并配 AAAA DDNS"
}
main "$@"
