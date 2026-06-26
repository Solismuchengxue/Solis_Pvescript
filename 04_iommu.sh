#!/usr/bin/env bash
# 04_iommu.sh —— IOMMU / 内核引导参数 / 模块准备（vGPU 路径）
#   1) 开启 Intel IOMMU：intel_iommu=on iommu=pt（自动识别 GRUB 或 systemd-boot）
#   2) 黑名单 nouveau（让 NVIDIA host 驱动接管 P4）
#   3) 加载 vfio 框架模块（mdev 经 vfio 分配给 guest）
#   4) pin 当前内核（vGPU 驱动对内核版本敏感，防 apt 升级搞挂）
#
# ⚠️ vGPU(mdev) 与「整卡直通」互斥：
#     · MODE=vgpu（默认）   —— 黑名单 nouveau，但【不】把 P4 绑到 vfio-pci，
#                              由 05 安装的 NVIDIA host 驱动持有整卡再切分 mdev
#     · MODE=passthrough    —— 额外把 P4 的 PCI ID 绑到 vfio-pci，整卡直通给单个 VM
#
# 环境变量：
#   MODE=vgpu|passthrough   默认 vgpu
#   PIN_KERNEL=1            pin 当前内核（默认 1）
#   DRY_RUN=1               只预览不改动
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

MODE="${MODE:-vgpu}"
PIN_KERNEL="${PIN_KERNEL:-1}"
DRY_RUN="${DRY_RUN:-0}"
CMDLINE_ADD="intel_iommu=on iommu=pt"

[[ "$MODE" == "vgpu" || "$MODE" == "passthrough" ]] || die "MODE 只能是 vgpu 或 passthrough"

# ---- 探测引导方式：proxmox-boot-tool(systemd-boot) 还是 GRUB ----
BOOT_KIND=""   # systemd-boot | grub
PBT_MANAGED=0
detect_bootloader(){
  if command -v proxmox-boot-tool >/dev/null 2>&1 && proxmox-boot-tool status >/dev/null 2>&1; then
    PBT_MANAGED=1
  fi
  if [[ -f /etc/kernel/cmdline ]]; then
    BOOT_KIND="systemd-boot"
  elif [[ -f /etc/default/grub ]]; then
    BOOT_KIND="grub"
  else
    die "无法识别引导方式（既无 /etc/kernel/cmdline 也无 /etc/default/grub）"
  fi
  msg_info "引导方式：${BOOT_KIND}（proxmox-boot-tool 管理=${PBT_MANAGED}）"
}

# ---- 写入内核引导参数（幂等）----
add_kernel_cmdline(){
  if grep -qw "intel_iommu=on" /proc/cmdline 2>/dev/null \
     && { [[ "$BOOT_KIND" == "systemd-boot" ]] && grep -qw "intel_iommu=on" /etc/kernel/cmdline 2>/dev/null \
        || [[ "$BOOT_KIND" == "grub" ]] && grep -q "intel_iommu=on" /etc/default/grub 2>/dev/null; }; then
    msg_info "内核参数已含 intel_iommu，跳过"
    return 0
  fi

  if [[ "$BOOT_KIND" == "systemd-boot" ]]; then
    local f=/etc/kernel/cmdline cur
    cur="$(cat "$f")"
    grep -qw "intel_iommu=on" <<<"$cur" && { msg_info "$f 已含参数，跳过"; return 0; }
    if [[ "$DRY_RUN" == "1" ]]; then
      msg_info "[DRY_RUN] $f 末尾追加：$CMDLINE_ADD"; return 0
    fi
    backup_once "$f"
    printf '%s %s\n' "$cur" "$CMDLINE_ADD" > "$f"
    msg_ok "已更新 $f"
  else
    local f=/etc/default/grub
    grep -q "intel_iommu=on" "$f" && { msg_info "$f 已含参数，跳过"; return 0; }
    if [[ "$DRY_RUN" == "1" ]]; then
      msg_info "[DRY_RUN] 在 $f 的 GRUB_CMDLINE_LINUX_DEFAULT 内追加：$CMDLINE_ADD"; return 0
    fi
    backup_once "$f"
    # 把参数插入引号内末尾
    sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)(\")/\1\2 ${CMDLINE_ADD}\3/" "$f"
    msg_ok "已更新 $f"
  fi
}

# ---- 黑名单 nouveau ----
blacklist_nouveau(){
  local f=/etc/modprobe.d/blacklist-nouveau.conf
  if [[ "$DRY_RUN" == "1" ]]; then msg_info "[DRY_RUN] 写入 $f（blacklist nouveau）"; return 0; fi
  cat > "$f" <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
  msg_ok "已黑名单 nouveau"
}

# ---- 加载 vfio 框架模块 ----
enable_vfio_modules(){
  local f=/etc/modules-load.d/vfio.conf
  if [[ "$DRY_RUN" == "1" ]]; then msg_info "[DRY_RUN] 写入 $f（vfio 模块）"; return 0; fi
  cat > "$f" <<'EOF'
vfio
vfio_iommu_type1
vfio_pci
EOF
  msg_ok "已配置 vfio 模块开机加载"
}

# ---- passthrough 模式：把 NVIDIA 卡绑到 vfio-pci ----
bind_vfio_passthrough(){
  local ids
  ids="$(lspci -nn -d 10de: 2>/dev/null | grep -oiP '\[\K10de:[0-9a-f]{4}' | sort -u | paste -sd, -)"
  [[ -n "$ids" ]] || { msg_warn "未探测到 NVIDIA 设备，跳过 vfio-pci 绑定"; return 0; }
  msg_info "passthrough 模式：将 NVIDIA 设备 [$ids] 绑定 vfio-pci"
  if [[ "$DRY_RUN" == "1" ]]; then msg_info "[DRY_RUN] options vfio-pci ids=$ids"; return 0; fi
  echo "options vfio-pci ids=${ids}" > /etc/modprobe.d/vfio-pci.conf
  # 同时黑名单 nvidia，确保 vfio-pci 抢到设备
  cat > /etc/modprobe.d/blacklist-nvidia.conf <<'EOF'
blacklist nvidia
blacklist nvidiafb
blacklist nvidia_drm
EOF
  msg_ok "已写入 vfio-pci 绑定（ids=$ids）"
}

# ---- pin 当前内核 ----
pin_current_kernel(){
  [[ "$PIN_KERNEL" == "1" ]] || { msg_info "PIN_KERNEL!=1，跳过内核 pin"; return 0; }
  command -v proxmox-boot-tool >/dev/null 2>&1 || { msg_warn "无 proxmox-boot-tool，跳过 pin"; return 0; }
  local kv; kv="$(uname -r)"
  if [[ "$DRY_RUN" == "1" ]]; then msg_info "[DRY_RUN] proxmox-boot-tool kernel pin $kv"; return 0; fi
  proxmox-boot-tool kernel pin "$kv" && msg_ok "已 pin 内核 $kv" \
    || msg_warn "pin 内核失败（确认 $kv 在 proxmox-boot-tool kernel list 中）"
}

# ---- 应用：initramfs + 引导刷新 ----
apply_changes(){
  if [[ "$DRY_RUN" == "1" ]]; then msg_info "[DRY_RUN] 跳过 initramfs/引导刷新"; return 0; fi
  msg_info "update-initramfs -u -k all ..."
  update-initramfs -u -k all
  if [[ "$PBT_MANAGED" == "1" ]]; then
    msg_info "proxmox-boot-tool refresh ..."
    proxmox-boot-tool refresh
  fi
  if [[ "$BOOT_KIND" == "grub" ]]; then
    msg_info "update-grub ..."
    update-grub
  fi
  msg_ok "引导配置已刷新"
}

main(){
  need_root
  need_pve9
  msg_info "===== 04 IOMMU/引导准备开始（MODE=$MODE, DRY_RUN=$DRY_RUN）====="
  detect_bootloader
  confirm "将写入内核参数($CMDLINE_ADD)、黑名单 nouveau、配 vfio、pin 内核，继续?" || die "已取消"
  add_kernel_cmdline
  blacklist_nouveau
  enable_vfio_modules
  [[ "$MODE" == "passthrough" ]] && bind_vfio_passthrough
  pin_current_kernel
  apply_changes
  echo
  msg_ok "===== 04 完成，需【重启】生效 ====="
  msg_warn "重启后验证："
  msg_warn "  dmesg | grep -e DMAR -e IOMMU      # 应看到 IOMMU enabled"
  msg_warn "  find /sys/kernel/iommu_groups -type l | wc -l   # 非 0 即 IOMMU 生效"
  msg_warn "  lsmod | grep -i nouveau            # 应为空（已黑名单）"
  [[ "$MODE" == "vgpu" ]] && msg_info "下一步：重启后跑 05 安装 NVIDIA vGPU host 驱动"
}
main "$@"
