#!/usr/bin/env bash
# 10_win11_vm.sh —— 创建 Windows 11 VM（为后续挂 vGPU 准备）
#   UEFI + TPM 2.0 + Secure Boot：满足 Win11 硬性要求
#   磁盘/网卡走 VirtIO：性能最佳，安装时需从 virtio-win ISO 加载驱动
#   显示先用默认 std；驱动装好后用 08_vm_attach.sh 挂 P4 vGPU 再切 none
#
# 前置：两个 ISO 都放入 /var/lib/vz/template/iso/
#   1) Windows 11 ISO —— 消费版/零售版均可（如 Win11_25H2_Pro_*.iso）；
#      KMS 激活靠安装后的 GVLK，与 ISO 渠道无关（见 docs/win11-kms-activation.md）
#   2) virtio-win ISO —— https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
#
# 环境变量：
#   VMID=110               VM ID（默认 110）
#   VM_CORES=4             CPU 核数
#   VM_MEM=8192            内存 MB
#   SYS_DISK_GB=128        系统盘大小 GB
#   STORAGE=local          PVE 存储池
#   WIN_ISO=               Win11 ISO 路径（留空自动探测 *win11* / *Win*11*）
#   VIRTIO_ISO=            virtio-win ISO 路径（留空自动探测 virtio-win*.iso）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VMID="${VMID:-110}"
VM_NAME="${VM_NAME:-win11}"
VM_CORES="${VM_CORES:-4}"
VM_MEM="${VM_MEM:-8192}"
SYS_DISK_GB="${SYS_DISK_GB:-128}"
STORAGE="${STORAGE:-local}"
WIN_ISO="${WIN_ISO:-}"
VIRTIO_ISO="${VIRTIO_ISO:-}"
ISO_DIR="/var/lib/vz/template/iso"

# ---- 查找 Win11 ISO ----
find_win_iso(){
  [[ -n "$WIN_ISO" ]] && { echo "$WIN_ISO"; return 0; }
  local iso
  iso="$(ls -1 "${ISO_DIR}"/*[Ww]in*11*.iso "${ISO_DIR}"/*[Ww]in11*.iso 2>/dev/null | head -1 || true)"
  [[ -n "$iso" ]] || die "未找到 Windows 11 ISO，请放入 ${ISO_DIR}/，或用 WIN_ISO=<路径> 指定"
  echo "$iso"
}

# ---- 查找 virtio-win ISO ----
find_virtio_iso(){
  [[ -n "$VIRTIO_ISO" ]] && { echo "$VIRTIO_ISO"; return 0; }
  local iso
  iso="$(ls -1 "${ISO_DIR}"/virtio-win*.iso 2>/dev/null | head -1 || true)"
  [[ -n "$iso" ]] || die "未找到 virtio-win ISO，请下载放入 ${ISO_DIR}/，或用 VIRTIO_ISO=<路径> 指定
  下载：https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
  echo "$iso"
}

# ---- 检查 VMID 未占用 ----
check_vmid(){
  if qm status "$VMID" >/dev/null 2>&1; then
    die "VMID ${VMID} 已被占用，请用 VMID=<其他ID> 重新执行，或先 qm destroy ${VMID}"
  fi
}

# ---- 创建 VM ----
create_vm(){
  local win_iso="$1" virtio_iso="$2"
  local win_ref="local:iso/$(basename "$win_iso")"
  local virtio_ref="local:iso/$(basename "$virtio_iso")"

  msg_info "创建 VM ${VMID}（${VM_NAME}）：${VM_CORES}核 / ${VM_MEM}MB / 系统盘 ${SYS_DISK_GB}G"

  qm create "$VMID" \
    --name    "$VM_NAME" \
    --machine q35 \
    --bios    ovmf \
    --cpu     host \
    --cores   "$VM_CORES" \
    --sockets 1 \
    --memory  "$VM_MEM" \
    --net0    "virtio,bridge=vmbr0,firewall=0" \
    --scsihw  virtio-scsi-single \
    --ostype  win11 \
    --agent   enabled=1

  qm set "$VMID" \
    --efidisk0  "${STORAGE}:0,efitype=4m,pre-enrolled-keys=1" \
    --tpmstate0 "${STORAGE}:1,version=v2.0" \
    --scsi0     "${STORAGE}:${SYS_DISK_GB},format=qcow2,ssd=1,discard=on,iothread=1" \
    --ide2      "${win_ref},media=cdrom" \
    --ide3      "${virtio_ref},media=cdrom" \
    --onboot    0
  # 启动顺序最后单独设置，覆盖 qm create 自动加入的 net0
  qm set "$VMID" --boot "order=ide2;scsi0"

  msg_ok "VM ${VMID} 创建完成"
}

main(){
  need_root
  need_pve9
  msg_info "===== 10 创建 Windows 11 VM ====="

  local win_iso virtio_iso
  win_iso="$(find_win_iso)";       msg_ok "Win11 ISO：${win_iso}"
  virtio_iso="$(find_virtio_iso)"; msg_ok "VirtIO ISO：${virtio_iso}"
  check_vmid

  msg_info "VMID=${VMID}  存储池=${STORAGE}  系统盘=${SYS_DISK_GB}G  内存=${VM_MEM}MB"
  confirm "创建 VM ${VMID}，继续?" || die "已取消"
  create_vm "$win_iso" "$virtio_iso"

  echo
  msg_ok "===== 10 完成 ====="
  msg_info "安装步骤："
  msg_info "  1. PVE Web UI → VM ${VMID} → 启动 → Console"
  msg_info "  2. 装到「选择安装位置」看不到磁盘 → 点【加载驱动程序】"
  msg_info "     → 浏览 virtio CD → vioscsi\\w11\\amd64 → 装好后磁盘出现"
  msg_info "  3. 走到「让我们为你连接到网络」时（VirtIO 网卡此时无驱动，先跳过联网）："
  msg_info "     按 Shift+F10 调出命令行 → 输入下面命令 → 回车后自动重启："
  echo
  echo "       OOBE\\BYPASSNRO"
  echo
  msg_info "     重启回到网络步骤 → 选「我没有 Internet 连接」→ 继续建本地账户"
  msg_warn "     若 25H2 上 BYPASSNRO 失效，改用：Shift+F10 → start ms-cxh:localonly"
  msg_info "  4. 装完进桌面 → 打开 virtio CD → 运行 virtio-win-guest-tools.exe"
  msg_info "     （一次装齐网卡 / QEMU Agent / Balloon 驱动，装完网络即通）"
  msg_info "  5. 安装完成后移除 ISO 并改启动顺序："
  echo
  echo "    qm set ${VMID} --ide2 none,media=cdrom"
  echo "    qm set ${VMID} --ide3 none,media=cdrom"
  echo "    qm set ${VMID} --boot 'order=scsi0'"
  echo "    qm reboot ${VMID}"
  echo
  msg_info "  6. 激活：见 docs/win11-kms-activation.md（正版授权与组织许可路径）"
  msg_info "  7. vGPU：驱动就绪后用 08_vm_attach.sh 挂 P4，再把显示切为 none"
}
main "$@"
