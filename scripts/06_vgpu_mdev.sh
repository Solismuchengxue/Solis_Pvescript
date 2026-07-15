#!/usr/bin/env bash
# 06_vgpu_mdev.sh —— vGPU 服务与 mdev 类型管理（Tesla P4）
#   1) 启用 nvidia-vgpud / nvidia-vgpu-mgr 服务，开启持久模式
#   2) 列出 P4 支持的 vGPU 类型（mdev profile）及可用实例数 —— 供 08 挑选
#   3) 查看当前已分配的 vGPU 状态
#
# 说明：P4=Pascal，走经典 mdev_supported_types（无需 sriov-manage）。
#       新版 PVE 在 VM 配置写 hostpciX: <addr>,mdev=nvidia-XX 后，
#       会在【VM 启动时自动创建 mdev、关机自动销毁】，故无需手动持久化 mdev。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- 确保 vGPU 服务运行 + 持久模式 ----
ensure_services(){
  command -v nvidia-smi >/dev/null 2>&1 || die "未检测到 nvidia-smi，请先完成 05 安装驱动"
  local s
  for s in nvidia-vgpud nvidia-vgpu-mgr; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${s}\.service"; then
      systemctl enable --now "$s" 2>/dev/null \
        && msg_ok "服务已启用：$s" \
        || msg_warn "启用 $s 失败，检查 systemctl status $s"
    else
      msg_warn "未找到服务 $s（部分驱动版本服务名不同，可忽略）"
    fi
  done
  # 持久模式：驱动常驻，避免首个 VM 启动慢/掉卡
  nvidia-smi -pm 1 >/dev/null 2>&1 && msg_ok "已开启持久模式 (-pm 1)" || true
}

# ---- 列出 P4 支持的 mdev/vGPU 类型 ----
list_mdev_types(){
  msg_info "==== P4 支持的 vGPU 类型（mdev profile）===="
  local found=0 base pci t tname name avail
  for base in /sys/bus/pci/devices/*/mdev_supported_types; do
    [[ -d "$base" ]] || continue
    found=1
    pci="$(basename "$(dirname "$base")")"
    echo "  设备 ${pci}："
    printf "    %-14s %-20s %s\n" "TYPE" "NAME" "可用实例"
    for t in "$base"/*; do
      [[ -d "$t" ]] || continue
      tname="$(basename "$t")"
      name="$(cat "$t/name" 2>/dev/null || echo '?')"
      avail="$(cat "$t/available_instances" 2>/dev/null || echo '?')"
      printf "    %-14s %-20s %s\n" "$tname" "$name" "$avail"
    done
    echo
  done
  if [[ "$found" == "0" ]]; then
    msg_warn "未发现 mdev_supported_types。可能：驱动未就绪 / IOMMU 未开 / 卡不在 vGPU 模式"
    msg_warn "排查：nvidia-smi ；dmesg | grep -i vgpu ；systemctl status nvidia-vgpud"
  else
    msg_info "P4(8G) 常见：1Q×8(1G) / 2Q×4(2G) / 4Q×2(4G) / 8Q×1(8G)；Q=虚拟工作站"
    msg_info "记下要用的 TYPE（如 nvidia-63），08 挂载时填入"
  fi
}

# ---- 当前 vGPU 状态 ----
show_status(){
  msg_info "==== 当前 vGPU 状态 ===="
  nvidia-smi vgpu 2>/dev/null || msg_info "（暂无运行中的 vGPU 实例，正常）"
  if command -v mdevctl >/dev/null 2>&1; then
    echo; msg_info "mdevctl 列表："
    mdevctl list 2>/dev/null || msg_info "（无持久 mdev 定义）"
  fi
}

# ---- ECC：vGPU 建议关闭以释放完整显存（P4 开 ECC 时显存 8192→约7680M）----
manage_ecc(){
  command -v nvidia-smi >/dev/null 2>&1 || return 0
  local ecc
  ecc="$(nvidia-smi --query-gpu=ecc.mode.current --format=csv,noheader 2>/dev/null | head -1)"
  msg_info "当前 ECC 状态：${ecc:-未知}"
  if echo "${ecc:-}" | grep -qi 'Enabled'; then
    msg_warn "ECC 开启占用约 1/16 显存，vGPU 建议关闭（否则 8Q 等大 profile 切不出来）"
    if [[ "${DISABLE_ECC:-0}" == "1" ]] || confirm "现在关闭 ECC?（nvidia-smi -e 0，需重启生效）"; then
      if nvidia-smi -e 0; then
        msg_ok "已请求关闭 ECC，需【重启】才能真正生效"
        msg_warn "ECC 关闭前查 mdev 类型必然为空（属预期），现在退出，重启后重新运行本脚本"
        exit 0
      else
        msg_warn "关闭 ECC 失败"
      fi
    fi
  fi
}

main(){
  need_root
  need_pve9
  msg_info "===== 06 vGPU 服务/mdev 管理 ====="
  ensure_services
  manage_ecc
  echo
  list_mdev_types
  show_status
  echo
  msg_ok "===== 06 完成 ====="
  msg_info "下一步：07_license.sh 查看官方 CLS/DLS 配置指引；08_vm_attach.sh 把 vGPU 挂给 VM"
}
main "$@"
