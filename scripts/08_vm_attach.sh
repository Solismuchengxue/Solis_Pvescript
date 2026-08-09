#!/usr/bin/env bash
# 08_vm_attach.sh —— 给指定 VM 新增或原位替换 vGPU(mdev)
#   qm set <VMID> -hostpci<IDX> <PCI地址>,mdev=<nvidia-XX>
#   PVE 会在 VM 启动时自动创建 mdev 实例、关机自动销毁。
#
# 用法：
#   ./scripts/08_vm_attach.sh <VMID> [nvidia-XX]      # 位置参数
#   VMID=101 MDEV_TYPE=nvidia-65 ./scripts/08_vm_attach.sh
#   REPLACE_EXISTING=1 VMID=101 MDEV_TYPE=nvidia-65 ./scripts/08_vm_attach.sh
#   直接运行则进入交互式。
#
# 环境变量：
#   HOSTPCI_INDEX=0    指定起始索引（默认0），若该索引被占用则自动递增。
#   REPLACE_EXISTING=1 原位替换目标 VM 唯一的既有 vGPU；要求 VM 已停止。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VMID="${1:-${VMID:-}}"
MDEV_TYPE="${2:-${MDEV_TYPE:-}}"
HOSTPCI_INDEX="${HOSTPCI_INDEX:-0}"
REPLACE_EXISTING="${REPLACE_EXISTING:-0}"
ACTION="attach"
EXISTING_HOSTPCI_VALUE=""
OLD_MDEV_TYPE=""
MDEV_NAME=""

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

normalize_hostpci(){
  tr ',' '\n' | sed '/^$/d' | sort | paste -sd, -
}

# ---- 获取并校验 VMID，决定新增或原位替换 ----
resolve_vmid(){
  local -a existing_mdev_lines=()
  local existing_key existing_pci vm_status
  if [[ -z "$VMID" ]]; then
    read -r -p "请输入目标 VMID： " VMID
  fi
  [[ "$VMID" =~ ^[0-9]+$ ]] || die "VMID 非法：$VMID"
  qm config "$VMID" >/dev/null 2>&1 || die "VM $VMID 不存在"
  [[ "$REPLACE_EXISTING" =~ ^[01]$ ]] || die "REPLACE_EXISTING 只能是 0 或 1"

  mapfile -t existing_mdev_lines < <(qm config "$VMID" | grep -E '^hostpci[0-9]+: .*mdev=' || true)
  if (( ${#existing_mdev_lines[@]} > 0 )); then
    [[ "$REPLACE_EXISTING" == "1" ]] || die \
      "VM $VMID 已有 vGPU；为避免误加第二块，脚本已停止。若要原位更换 profile，请先关闭 VM，再设置 REPLACE_EXISTING=1。"
    (( ${#existing_mdev_lines[@]} == 1 )) || die \
      "VM $VMID 存在 ${#existing_mdev_lines[@]} 个 vGPU；原位替换只支持恰好一个既有 vGPU。"
    vm_status="$(qm status "$VMID" | awk '{print $2}')"
    [[ "$vm_status" == "stopped" ]] || die \
      "原位替换 vGPU 要求 VM $VMID 已停止，当前状态：$vm_status"

    existing_key="${existing_mdev_lines[0]%%:*}"
    HOSTPCI_INDEX="${existing_key#hostpci}"
    EXISTING_HOSTPCI_VALUE="${existing_mdev_lines[0]#*: }"
    existing_pci="${EXISTING_HOSTPCI_VALUE%%,*}"
    OLD_MDEV_TYPE="$(sed -n 's/.*mdev=\([^,]*\).*/\1/p' <<<"$EXISTING_HOSTPCI_VALUE")"
    [[ -n "$OLD_MDEV_TYPE" ]] || die "无法解析 VM $VMID 的既有 vGPU profile"
    [[ -d "/sys/bus/pci/devices/${existing_pci}/mdev_supported_types" ]] || die \
      "既有 vGPU PCI 地址 $existing_pci 不支持 mdev，拒绝替换"
    PCI_ADDR="$existing_pci"
    ACTION="replace"
    msg_info "将原位替换 hostpci${HOSTPCI_INDEX}（当前 ${OLD_MDEV_TYPE}），不会新增第二块 vGPU"
    return
  fi

  [[ "$REPLACE_EXISTING" == "0" ]] || die \
    "VM $VMID 没有既有 vGPU，无法使用 REPLACE_EXISTING=1；请改用默认新增模式。"

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
    read -r -p "请输入要使用的 TYPE（FNOS P4-4Q 为 nvidia-65）： " MDEV_TYPE
  fi
  [[ "$MDEV_TYPE" =~ ^nvidia-[0-9]+$ ]] || die "mdev 类型格式非法：$MDEV_TYPE"
  local f="/sys/bus/pci/devices/${PCI_ADDR}/mdev_supported_types/${MDEV_TYPE}/available_instances"
  [[ -f "$f" ]] || die "类型 $MDEV_TYPE 在 $PCI_ADDR 上不存在（用 06 或本脚本查看可用类型）"
  MDEV_NAME="$(cat "${f%/available_instances}/name" 2>/dev/null || echo '?')"
  if [[ "$ACTION" == "replace" && "$MDEV_TYPE" == "$OLD_MDEV_TYPE" ]]; then
    die "目标类型仍是 $MDEV_TYPE（$MDEV_NAME），无需替换"
  fi
  local avail; avail="$(cat "$f")"
  [[ "$avail" =~ ^[0-9]+$ ]] && (( avail > 0 )) || die \
    "类型 $MDEV_TYPE（$MDEV_NAME）可用实例为 $avail；可能已占满，或同一物理 GPU 上存在不同显存大小的活动 profile。"
  msg_ok "类型 $MDEV_TYPE（$MDEV_NAME）可用实例：$avail"
}

main(){
  need_root
  need_pve9
  msg_info "===== 08 给 VM 挂载 vGPU ====="
  detect_pci
  resolve_vmid
  resolve_mdev
  echo
  if [[ "$ACTION" == "replace" ]]; then
    local new_hostpci_value actual expected_normalized actual_normalized
    new_hostpci_value="$(sed -E "s/(^|,)mdev=[^,]+/\1mdev=${MDEV_TYPE}/" <<<"$EXISTING_HOSTPCI_VALUE")"
    msg_info "将原位替换：hostpci${HOSTPCI_INDEX} ${OLD_MDEV_TYPE} → ${MDEV_TYPE}（${MDEV_NAME}）"
    msg_info "保留配置：${new_hostpci_value}"
    confirm "确认替换既有 vGPU profile?" || die "已取消"
    qm set "$VMID" -hostpci${HOSTPCI_INDEX} "$new_hostpci_value"
    actual="$(qm config "$VMID" | sed -n "s/^hostpci${HOSTPCI_INDEX}: //p")"
    expected_normalized="$(normalize_hostpci <<<"$new_hostpci_value")"
    actual_normalized="$(normalize_hostpci <<<"$actual")"
    if [[ "$actual_normalized" != "$expected_normalized" ]]; then
      msg_err "替换后配置不符合预期：hostpci${HOSTPCI_INDEX}=$actual"
      msg_warn "正在恢复原配置：hostpci${HOSTPCI_INDEX}=$EXISTING_HOSTPCI_VALUE"
      qm set "$VMID" -hostpci${HOSTPCI_INDEX} "$EXISTING_HOSTPCI_VALUE" || \
        msg_err "自动恢复失败，请保持 VM 停止并人工检查 qm config $VMID"
      die "vGPU profile 替换验证失败"
    fi
    msg_ok "已原位替换 VM $VMID 的 vGPU（hostpci${HOSTPCI_INDEX}=${MDEV_TYPE}）"
  else
    msg_info "将执行： qm set $VMID -hostpci${HOSTPCI_INDEX} ${PCI_ADDR},mdev=${MDEV_TYPE}"
    confirm "确认挂载?" || die "已取消"
    qm set "$VMID" -hostpci${HOSTPCI_INDEX} "${PCI_ADDR},mdev=${MDEV_TYPE}"
    msg_ok "已为 VM $VMID 挂载 vGPU（hostpci${HOSTPCI_INDEX}=${MDEV_TYPE}）"
  fi
  echo
  msg_info "后续："
  msg_info "  1) 启动： qm start $VMID"
  msg_info "  2) guest 内安装与 host【同分支】的 vGPU guest 驱动"
  msg_info "  3) 配 License（见 07 输出的 token 指引），nvidia-smi -q | grep -i license 应为 Licensed"
  msg_warn "  Windows guest 建议机型 q35 + OVMF；纯计算/Linux 一般无强制要求"
}
main "$@"
