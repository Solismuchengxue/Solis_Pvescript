#!/usr/bin/env bash
# 09_fnos_vm.sh —— 创建飞牛OS (FnOS) VM
#   系统盘：local-lvm 虚拟磁盘（默认 40G）
#   存储盘：nvme1n1 裸设备直通 —— 数据格式由飞牛管理，拔盘可在任意机器读取
#   网络  ：vmbr0（SLAAC 自动获取 IPv4 + IPv6）
#
# 前置：飞牛 ISO 已放入 /var/lib/vz/template/iso/
#   下载：https://www.fnnas.com/download?key=fnos （选 ISO 格式）
#   上传：PVE Web UI → local → ISO Images → Upload
#        或：wget -P /var/lib/vz/template/iso/ <直链>
#
# 环境变量：
#   VMID=100               VM ID（默认 100）
#   VM_CORES=2             CPU 核数
#   VM_MEM=4096            内存 MB
#   SYS_DISK_GB=40         系统盘大小 GB（在 local-lvm）
#   STORAGE=local-lvm      PVE 存储池
#   STORAGE_DEV=/dev/nvme1n1   裸设备直通的存储盘
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

VMID="${VMID:-100}"
VM_NAME="${VM_NAME:-fnos}"
VM_CORES="${VM_CORES:-2}"
VM_MEM="${VM_MEM:-4096}"
SYS_DISK_GB="${SYS_DISK_GB:-40}"
STORAGE="${STORAGE:-local-lvm}"
STORAGE_DEV="${STORAGE_DEV:-/dev/nvme1n1}"
ISO_DIR="/var/lib/vz/template/iso"

# ---- 查找飞牛 ISO ----
find_iso(){
  local iso
  iso="$(ls -1 "${ISO_DIR}"/[Ff][Nn][Oo][Ss]*.iso 2>/dev/null | head -1 || true)"
  [[ -n "$iso" ]] || die "未找到飞牛OS ISO，请先下载放入 ${ISO_DIR}/
  下载：https://www.fnnas.com/download?key=fnos（选 ISO 格式）
  上传：PVE Web UI → local → ISO Images → Upload
  或：  wget -P ${ISO_DIR} <飞牛直链URL>"
  echo "$iso"
}

# ---- 检查 VMID 未占用 ----
check_vmid(){
  if qm status "$VMID" >/dev/null 2>&1; then
    die "VMID ${VMID} 已被占用，请用 VMID=<其他ID> 重新执行，或先 qm destroy ${VMID}"
  fi
}

# ---- 检查存储盘可用 ----
check_storage_dev(){
  [[ -b "$STORAGE_DEV" ]] || die "存储盘 ${STORAGE_DEV} 不存在，请用 lsblk 确认设备名"
  if grep -qs "^${STORAGE_DEV}" /proc/mounts; then
    die "${STORAGE_DEV} 当前已挂载，不能直通"
  fi
  local size; size="$(lsblk -dn -o SIZE "$STORAGE_DEV" 2>/dev/null || echo '未知')"
  msg_warn "存储盘 ${STORAGE_DEV}（${size}）将以裸设备直通给 VM"
  msg_warn "飞牛OS 会在此盘建存储池，请确认盘内数据已备份"
}

# ---- 创建 VM ----
create_vm(){
  local iso="$1"
  local iso_ref="local:iso/$(basename "$iso")"

  msg_info "创建 VM ${VMID}（${VM_NAME}）：${VM_CORES}核 / ${VM_MEM}MB / 系统盘 ${SYS_DISK_GB}G"

  qm create "$VMID" \
    --name    "$VM_NAME" \
    --machine q35 \
    --bios    ovmf \
    --cpu     host \
    --cores   "$VM_CORES" \
    --memory  "$VM_MEM" \
    --net0    "virtio,bridge=vmbr0,firewall=0" \
    --scsihw  virtio-scsi-pci \
    --ostype  l26

  qm set "$VMID" \
    --efidisk0 "${STORAGE}:0,efitype=4m,pre-enrolled-keys=0" \
    --scsi0    "${STORAGE}:${SYS_DISK_GB},discard=on,ssd=1" \
    --scsi1    "${STORAGE_DEV},format=raw,backup=0" \
    --ide2     "${iso_ref},media=cdrom" \
    --boot     "order=ide2;scsi0" \
    --onboot   1

  msg_ok "VM ${VMID} 创建完成"
}

main(){
  need_root
  need_pve9
  msg_info "===== 09 创建飞牛OS VM ====="
  msg_info "VMID=${VMID}  存储池=${STORAGE}  系统盘=${SYS_DISK_GB}G  存储盘=${STORAGE_DEV}"

  local iso; iso="$(find_iso)"
  msg_ok "找到 ISO：${iso}"
  check_vmid
  check_storage_dev

  confirm "创建 VM ${VMID}，直通 ${STORAGE_DEV} 作存储盘，继续?" || die "已取消"
  create_vm "$iso"

  local dev_size; dev_size="$(lsblk -dn -o SIZE "$STORAGE_DEV" 2>/dev/null || echo '?')"
  echo
  msg_ok "===== 09 完成 ====="
  msg_info "启动与安装步骤："
  msg_info "  1. PVE Web UI → VM ${VMID} → 启动 → Console"
  msg_info "  2. 飞牛安装向导：系统盘选 scsi0（${SYS_DISK_GB}G）"
  msg_warn "     存储盘 scsi1（${dev_size}）安装时不要动，飞牛启动后在存储管理里再挂"
  msg_info "  3. 安装完毕关机 → 硬件 → CD-ROM → 移除 ISO → 再开机"
  msg_info "  4. 浏览器访问 http://<飞牛IP>:5666 完成初始化向导"
}
main "$@"
