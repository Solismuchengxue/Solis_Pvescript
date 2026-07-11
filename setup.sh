#!/usr/bin/env bash
# setup.sh —— Solis PVE Setup 总入口菜单
#   逐项调用各模块脚本。建议按顺序执行，注意 04 之后需重启。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

menu(){
cat <<EOF

${C_INFO}========= Solis PVE Setup =========${C_RESET}
  1) 基础配置    源/去弹窗/时区/NTP/基础包
  2) 系统盘扩容  删 local-lvm 并入 root
  3) 网络与 IPv6 vmbr0 SLAAC / i226 确认
  4) IOMMU/引导  vGPU 准备 ${C_WARN}*执行后需重启*${C_RESET}
  5) vGPU 驱动   安装 NVIDIA host 驱动(.run)
  6) vGPU 服务   服务/mdev 类型查看
  7) License     自建 DLS(fastapi-dls)
  8) 挂载 vGPU   给 VM 分配 vGPU
  9) 飞牛OS VM   创建 FnOS VM（NVMe PCIe 直通）
 10) Win11 VM    创建 Win11 VM（UEFI+TPM，待挂 vGPU）
  q) 退出
${C_INFO}===================================${C_RESET}
EOF
}

run(){ bash "${SCRIPT_DIR}/scripts/$1"; }

main(){
  need_root
  local c
  while true; do
    menu
    read -r -p "选择> " c
    case "$c" in
      1) run 01_base.sh ;;
      2) run 02_storage.sh ;;
      3) run 03_network.sh ;;
      4) run 04_iommu.sh ;;
      5) run 05_vgpu_driver.sh ;;
      6) run 06_vgpu_mdev.sh ;;
      7) run 07_dls.sh ;;
      8) run 08_vm_attach.sh ;;
      9) run 09_fnos_vm.sh ;;
      10) run 10_win11_vm.sh ;;
      q|Q) exit 0 ;;
      *) msg_warn "无效选择：$c" ;;
    esac
    echo; read -r -p "回车返回菜单..." _ || true
  done
}
main "$@"
