#!/usr/bin/env bash
# 05_vgpu_driver.sh —— 安装 NVIDIA vGPU host 驱动（Tesla P4 / 535 分支）
#   1) 安装编译依赖（对应当前内核的 headers、dkms、mdevctl）
#   2) 执行 *-vgpu-kvm.run --dkms 安装（DKMS 内核更新自动重编译）
#   3) 加载模块并用 nvidia-smi 验证
#
# 前置（重要）：
#   · host 驱动 .run 需自备，放入 ./drivers/（见 drivers/README.md）。脚本不下载官方驱动。
#   · 必须先完成 04（黑名单 nouveau + IOMMU）并【已重启】。
#   · vGPU 路径下【不要】把 P4 绑到 vfio-pci（否则驱动拿不到卡）。
#
# 环境变量：
#   DRIVER_RUN=路径    指定 .run（默认在 ./drivers/ 找 *vgpu*kvm*.run）
#   DRIVER_DIR=./drivers
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

DRIVER_DIR="${DRIVER_DIR:-${SCRIPT_DIR}/drivers}"
DRIVER_RUN="${DRIVER_RUN:-}"

# ---- 前置环境检查 ----
preflight(){
  # nouveau 必须已卸载（04 黑名单 + 重启）
  if lsmod | grep -q '^nouveau'; then
    die "nouveau 仍在加载！请先执行 04_iommu.sh 并重启后再来"
  fi
  # vfio-pci 不应抢占 NVIDIA 卡（vGPU 路径）
  if lspci -nnk -d 10de: 2>/dev/null | grep -qi 'Kernel driver in use: vfio-pci'; then
    die "P4 当前被 vfio-pci 占用（整卡直通模式）。vGPU 路径请勿绑 vfio-pci，见 04 MODE=vgpu"
  fi
  # 找到 NVIDIA 卡
  if ! lspci -d 10de: 2>/dev/null | grep -qi nvidia; then
    msg_warn "未在 lspci 看到 NVIDIA 设备，请确认 P4 已插好、IOMMU 已开"
  else
    msg_info "检测到 NVIDIA 设备：$(lspci -d 10de: | head -1)"
  fi
}

# ---- 定位驱动文件 ----
locate_driver(){
  if [[ -z "$DRIVER_RUN" ]]; then
    DRIVER_RUN="$(ls -1 "${DRIVER_DIR}"/*vgpu*kvm*.run 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$DRIVER_RUN" && -f "$DRIVER_RUN" ]] || die \
    "未找到 vGPU host 驱动 (.run)。请把 *-vgpu-kvm.run 放入 ${DRIVER_DIR}/ 或用 DRIVER_RUN= 指定（见 drivers/README.md）"
  msg_ok "驱动文件：$DRIVER_RUN"
}

# ---- 安装编译依赖 + 对应内核 headers ----
install_deps(){
  local kv; kv="$(uname -r)"
  msg_info "安装编译依赖与 headers（内核 $kv）"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential dkms mdevctl pkg-config
  if apt-cache show "proxmox-headers-${kv}" >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get -y install "proxmox-headers-${kv}"
  elif apt-cache show "pve-headers-${kv}" >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get -y install "pve-headers-${kv}"
  else
    msg_warn "未找到精确匹配 $kv 的 headers 包，尝试默认 headers 元包"
    DEBIAN_FRONTEND=noninteractive apt-get -y install proxmox-default-headers 2>/dev/null \
      || DEBIAN_FRONTEND=noninteractive apt-get -y install pve-headers
  fi
  msg_ok "依赖安装完成"
}

# ---- 新内核兼容性提示 ----
kernel_compat_note(){
  local kmaj kmin; kmaj="$(uname -r | cut -d. -f1)"; kmin="$(uname -r | cut -d. -f2)"
  if (( kmaj > 6 || (kmaj == 6 && kmin >= 8) )); then
    msg_warn "当前内核 $(uname -r) 较新：535/16.x 驱动可能需内核补丁才能编译。"
    msg_warn "若下方安装因 DKMS 编译报错失败，请把内核版本+驱动版本告诉我，再做针对性 patch。"
  fi
}

# ---- 安装驱动 ----
install_driver(){
  chmod +x "$DRIVER_RUN"
  msg_info "运行驱动安装器（--dkms 静默）..."
  if "$DRIVER_RUN" --dkms -s --no-cc-version-check; then
    msg_ok "驱动安装器执行完成"
  else
    msg_err "驱动安装失败。排查："
    msg_err "  1) 编译日志：/var/log/nvidia-installer.log 与 /var/lib/dkms/nvidia/*/build/make.log"
    msg_err "  2) 多为新内核不兼容，需对应 内核×驱动 的补丁"
    msg_err "  3) 把上述日志关键报错发我，我给精确 patch"
    die "见上方排查"
  fi
}

# ---- 验证 ----
verify(){
  msg_info "加载并验证 NVIDIA 驱动 ..."
  modprobe nvidia 2>/dev/null || true
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
    msg_ok "nvidia-smi 正常，P4 已被 host 驱动接管"
    msg_info "vGPU 能力："
    nvidia-smi vgpu 2>/dev/null || msg_info "（尚无 vGPU 实例，正常；06 再创建 mdev）"
  else
    msg_warn "nvidia-smi 未就绪。可能需重启或加载模块；检查 dmesg | grep -i nvidia"
  fi
}

main(){
  need_root
  need_pve9
  msg_info "===== 05 安装 vGPU host 驱动开始 ====="
  preflight
  locate_driver
  kernel_compat_note
  confirm "将安装编译依赖并执行驱动安装器，继续?" || die "已取消"
  install_deps
  install_driver
  verify
  echo
  msg_ok "===== 05 完成 ====="
  msg_info "下一步：06_vgpu_mdev.sh —— 拉起 vgpu 服务、查询 mdev 类型、为直通做准备"
}
main "$@"
