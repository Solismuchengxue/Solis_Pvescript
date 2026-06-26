#!/usr/bin/env bash
# 09_fnos_vm.sh —— 创建飞牛OS (FnOS) VM
#   系统盘：local 虚拟磁盘（默认 40G，qcow2，标记 SSD）
#   存储盘：NVMe PCIe 直通（hostpci0）—— guest 看到真实 NVMe 控制器，
#           数据格式由飞牛管理，拔盘可在任意机器直接读取
#   网络  ：vmbr0（SLAAC 自动获取 IPv4 + IPv6）
#
# 前置：飞牛 ISO 已放入 /var/lib/vz/template/iso/
#   下载：https://www.fnnas.com/download?key=fnos （选 ISO 格式）
#   上传：PVE Web UI → local → ISO Images → Upload
#
# 环境变量：
#   VMID=100                   VM ID（默认 100）
#   VM_CORES=2                 CPU 核数
#   VM_MEM=4096                内存 MB
#   SYS_DISK_GB=40             系统盘大小 GB（存放在 STORAGE）
#   STORAGE=local              PVE 存储池
#   STORAGE_DEV=/dev/nvme1n1   存储盘块设备（自动转为 PCI 地址做直通）
#   PCI_ADDR=                  手动指定 PCI 地址（留空则从 STORAGE_DEV 自动探测）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

VMID="${VMID:-100}"
VM_NAME="${VM_NAME:-fnos}"
VM_CORES="${VM_CORES:-2}"
VM_MEM="${VM_MEM:-4096}"
SYS_DISK_GB="${SYS_DISK_GB:-40}"
STORAGE="${STORAGE:-local}"
STORAGE_DEV="${STORAGE_DEV:-/dev/nvme1n1}"
PCI_ADDR="${PCI_ADDR:-}"
ISO_DIR="/var/lib/vz/template/iso"

# ---- 查找飞牛 ISO ----
find_iso(){
  local iso
  iso="$(ls -1 "${ISO_DIR}"/[Ff][Nn][Oo][Ss]*.iso 2>/dev/null | head -1 || true)"
  [[ -n "$iso" ]] || die "未找到飞牛OS ISO，请先下载放入 ${ISO_DIR}/
  下载：https://www.fnnas.com/download?key=fnos（选 ISO 格式）
  上传：PVE Web UI → local → ISO Images → Upload"
  echo "$iso"
}

# ---- 从块设备名探测 PCI 地址 ----
find_pci_addr(){
  [[ -n "$PCI_ADDR" ]] && { echo "$PCI_ADDR"; return 0; }
  local dev_name="${STORAGE_DEV##/dev/}"
  [[ -b "$STORAGE_DEV" ]] || die "存储盘 ${STORAGE_DEV} 不存在，请用 lsblk 确认"
  local pci
  pci=$(readlink -f "/sys/block/${dev_name}" 2>/dev/null \
        | grep -oP '0000:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | tail -1 || true)
  [[ -n "$pci" ]] || die "无法从 ${STORAGE_DEV} 探测 PCI 地址，请用 PCI_ADDR=xxxx:xx:xx.x 手动指定"
  echo "$pci"
}

# ---- 检查 NVMe 独占 IOMMU 组 ----
check_iommu_group(){
  local pci="$1"
  local dev_path
  dev_path=$(find /sys/kernel/iommu_groups/ -name "$pci" 2>/dev/null | head -1 || true)
  [[ -n "$dev_path" ]] || die "${pci} 未在任何 IOMMU 组中，请确认 04_iommu.sh 已跑且已重启"
  local devices_dir; devices_dir="$(dirname "$dev_path")"
  local count; count=$(ls "$devices_dir/" | wc -l)
  if (( count > 1 )); then
    msg_warn "IOMMU 组内设备列表："; ls "$devices_dir/"
    die "${pci} 与其他设备共享 IOMMU 组（共 ${count} 个），PCIe 直通不安全"
  fi
  msg_ok "${pci} 独占 IOMMU 组，可安全直通"
}

# ---- 检查 VMID 未占用 ----
check_vmid(){
  if qm status "$VMID" >/dev/null 2>&1; then
    die "VMID ${VMID} 已被占用，请用 VMID=<其他ID> 重新执行，或先 qm destroy ${VMID}"
  fi
}

# ---- 创建 VM ----
create_vm(){
  local iso="$1" pci="$2"
  local iso_ref="local:iso/$(basename "$iso")"
  local dev_size; dev_size="$(lsblk -dn -o SIZE "$STORAGE_DEV" 2>/dev/null || echo '?')"

  msg_info "创建 VM ${VMID}（${VM_NAME}）：${VM_CORES}核 / ${VM_MEM}MB / 系统盘 ${SYS_DISK_GB}G"
  msg_info "存储盘 PCIe 直通：${pci}（${STORAGE_DEV} ${dev_size}）"

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
    --scsi0    "${STORAGE}:${SYS_DISK_GB},format=qcow2,ssd=1" \
    --hostpci0 "${pci},pcie=1" \
    --ide2     "${iso_ref},media=cdrom" \
    --boot     "order=ide2;scsi0" \
    --onboot   1

  msg_ok "VM ${VMID} 创建完成"
}

main(){
  need_root
  need_pve9
  msg_info "===== 09 创建飞牛OS VM ====="

  local iso; iso="$(find_iso)"
  msg_ok "找到 ISO：${iso}"

  local pci; pci="$(find_pci_addr)"
  msg_info "存储盘 ${STORAGE_DEV} → PCI ${pci}"
  check_iommu_group "$pci"
  check_vmid

  local dev_size; dev_size="$(lsblk -dn -o SIZE "$STORAGE_DEV" 2>/dev/null || echo '?')"
  msg_info "VMID=${VMID}  存储池=${STORAGE}  系统盘=${SYS_DISK_GB}G  存储盘=${pci}（${dev_size}）"
  msg_warn "存储盘将做 PCIe 直通，飞牛OS 会格式化此盘，请确认数据已备份"

  confirm "创建 VM ${VMID}，继续?" || die "已取消"
  create_vm "$iso" "$pci"

  echo
  msg_ok "===== 09 完成 ====="
  msg_info "启动与安装步骤："
  msg_info "  1. PVE Web UI → VM ${VMID} → 启动 → Console"
  msg_info "  2. 飞牛安装向导：系统盘选 40G SSD（scsi0）"
  msg_warn "     NVMe 存储盘（${dev_size}）安装时不要动，飞牛启动后在存储管理里挂载"
  msg_info "  3. 安装完毕关机 → 硬件 → CD-ROM → 移除 ISO → 再开机"
  msg_info "  4. 浏览器访问 http://<飞牛IP>:5666 完成初始化向导"
}
main "$@"
