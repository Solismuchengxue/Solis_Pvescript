#!/usr/bin/env bash
# 08_vm_attach.sh —— 把 vGPU(mdev) 挂载给指定 VM
#   qm set <VMID> -hostpci<IDX> <PCI地址>,mdev=<nvidia-XX>
#   PVE 会在 VM 启动时自动创建 mdev 实例、关机自动销毁。
#
# 用法：
#   ./08_vm_attach.sh <VMID> [nvidia-XX]      # 位置参数
#   VMID=101 MDEV_TYPE=nvidia-63 ./08_vm_attach.sh
#   直接运行则进入交互式。
#
# 环境变量：
#   HOSTPCI_INDEX=0    指定起始索引（默认0），若该索引被占用则自动递增。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

VMID="${1:-${VMID:-}}"
MDEV_TYPE="${2:-${MDEV_TYPE:-}}"
HOSTPCI_INDEX="${HOSTPCI_INDEX:-0}"

# ---- 探测 P4 的 PCI 地址（完整 BDF）----
detect_pci(){
  PCI_ADDR="$(lspci -D -d 10de: 2>/dev/null | awk 'NR==1{print $1}')"
  [[ -n "${PCI_ADDR:-}" ]] || die "未找到 NVIDIA 设备，确认 P4 已插好、驱动已装（05）"
  [[ -d "/sys/bus/pci/devices/${PCI_ADDR}/mdev_supported_types" ]] \
    || die "$PCI_ADDR 无 mdev_supported_types，请先完成 04/05/06"
  msg_info "P4 PCI 地址：$PCI_ADDR"
}

# ---- 列出可用 mdev 类型 ----
list_types(){
  local t tname name avail
  printf "    %-14s %-20s %s\n" "TYPE" "NAME" "可用"
  for t in "/sys/bus/pci/devices/${PCI_ADDR}/mdev_supported_types"/*; do
    [[ -d "$t" ]] || continue
    tname="$(basename "$t")"
    name="$(cat "$t/name" 2>/dev/null || echo '?')"
    avail="$(cat "$t/available_instances" 2>/dev/null || echo '?')"
    printf "    %-14s %-20s %s\n" "$tname" "$name" "$avail"
  done
}

# ---- 查找空闲的 hostpci 索引 ----
find_free_hostpci(){
  local idx=$1
  local max_idx=9   # PVE 支持 hostpci0~9，可根据需要调整
  while [[ $idx -le $max_idx ]]; do
    if ! qm config "$VMID" | grep -q "^hostpci${idx}:"; then
      echo "$idx"
      return 0
    fi
    ((idx++))
  done
  die "VM $VMID 已占用所有 hostpci0~${max_idx}，无法添加新的 PCI 设备。"
}

# ---- 获取并校验 VMID，并自动分配空闲索引 ----
resolve_vmid(){
  if [[ -z "$VMID" ]]; then
    read -r -p "请输入目标 VMID： " VMID
  fi
  [[ "$VMID" =~ ^[0-9]+$ ]] || die "VMID 非法：$VMID"
  qm config "$VMID" >/dev/null 2>&1 || die "VM $VMID 不存在"

  # 如果用户指定的索引被占用，自动寻找下一个空闲索引
  if qm config "$VMID" | grep -q "^hostpci${HOSTPCI_INDEX}:"; then
    msg_warn "VM $VMID 已存在 hostpci${HOSTPCI_INDEX}，正在自动查找空闲索引..."
    HOSTPCI_INDEX=$(find_free_hostpci $((HOSTPCI_INDEX + 1)))
    msg_info "将使用空闲索引 hostpci${HOSTPCI_INDEX}"
  else
    # 指定的索引空闲，直接使用
    msg_info "将使用 hostpci${HOSTPCI_INDEX}"
  fi
}

# ---- 获取并校验 mdev 类型 ----
resolve_mdev(){
  if [[ -z "$MDEV_TYPE" ]]; then
    msg_info "可用 vGPU 类型："
    list_types
    read -r -p "请输入要使用的 TYPE（如 nvidia-63）： " MDEV_TYPE
  fi
  local f="/sys/bus/pci/devices/${PCI_ADDR}/mdev_supported_types/${MDEV_TYPE}/available_instances"
  [[ -f "$f" ]] || die "类型 $MDEV_TYPE 在 $PCI_ADDR 上不存在（用 06 或本脚本查看可用类型）"
  local avail; avail="$(cat "$f")"
  [[ "$avail" =~ ^[0-9]+$ ]] && (( avail > 0 )) || die "类型 $MDEV_TYPE 可用实例为 $avail（已占满）"
  msg_ok "类型 $MDEV_TYPE 可用实例：$avail"
}

main(){
  need_root
  need_pve9
  msg_info "===== 08 给 VM 挂载 vGPU ====="
  detect_pci
  resolve_vmid
  resolve_mdev
  echo
  msg_info "将执行： qm set $VMID -hostpci${HOSTPCI_INDEX} ${PCI_ADDR},mdev=${MDEV_TYPE}"
  confirm "确认挂载?" || die "已取消"
  qm set "$VMID" -hostpci${HOSTPCI_INDEX} "${PCI_ADDR},mdev=${MDEV_TYPE}"
  msg_ok "已为 VM $VMID 挂载 vGPU（hostpci${HOSTPCI_INDEX}=${MDEV_TYPE}）"
  echo
  msg_info "后续："
  msg_info "  1) 启动： qm start $VMID"
  msg_info "  2) guest 内安装与 host【同分支】的 vGPU guest 驱动"
  msg_info "  3) 配 License（见 07 输出的 token 指引），nvidia-smi -q | grep -i license 应为 Licensed"
  msg_warn "  Windows guest 建议机型 q35 + OVMF；纯计算/Linux 一般无强制要求"
}
main "$@"