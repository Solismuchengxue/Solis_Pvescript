#!/usr/bin/env bash
# 02_storage.sh —— 系统盘存储调整（扩容四连）
#   删除默认 local-lvm，把其空间并入 local(root)，单盘空间统一可用：
#     pvesm remove local-lvm
#     lvremove -f pve/data
#     lvextend -l +100%FREE -r pve/root
#     pvesm set local --content ...
#
# ⚠️ 破坏性：会销毁 local-lvm(pve/data) 上的数据。
#    请在【全新安装、尚无重要 VM/CT】时执行。
#
# 注：第二块 NVMe 与 USB 移动硬盘本脚本暂不处理（按需另加）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

VG="${VG:-pve}"
LOCAL_CONTENT="${LOCAL_CONTENT:-backup,iso,vztmpl,images,rootdir,snippets}"

show_state(){
  msg_info "LVM 逻辑卷："
  lvs -o lv_name,vg_name,lv_size,data_percent "$VG" 2>/dev/null || true
  echo
  msg_info "PVE 存储："
  pvesm status 2>/dev/null || true
}

merge_locallvm_into_root(){
  # 1. 删除 PVE 存储定义 local-lvm
  if pvesm status 2>/dev/null | awk '{print $1}' | grep -qx 'local-lvm'; then
    msg_warn "即将删除存储 local-lvm，其上 VM/CT 磁盘将不可用！"
    confirm "确认删除 local-lvm 存储定义?" || die "已取消"
    pvesm remove local-lvm
    msg_ok "已移除存储定义 local-lvm"
  else
    msg_info "local-lvm 存储定义不存在，跳过"
  fi

  # 2. 删除 thin 池 LV：pve/data
  if lvs "${VG}/data" >/dev/null 2>&1; then
    msg_warn "即将删除逻辑卷 ${VG}/data（thin 池），其中数据将被销毁！"
    confirm "确认 lvremove ${VG}/data?" || die "已取消"
    lvremove -f "${VG}/data"
    msg_ok "已删除 ${VG}/data"
  else
    msg_info "${VG}/data 不存在，跳过（可能已删）"
  fi

  # 3. root 扩容吃满 VG 剩余空间（含文件系统在线扩容 -r）
  local free_ext
  free_ext="$(vgs --noheadings -o vg_free_count "$VG" 2>/dev/null | tr -d ' ')"
  if [[ "${free_ext:-0}" =~ ^[0-9]+$ ]] && (( free_ext > 0 )); then
    msg_info "扩容 ${VG}/root（+100%FREE）"
    lvextend -l +100%FREE -r "${VG}/root"
    msg_ok "已扩容 ${VG}/root"
  else
    msg_info "VG ${VG} 无空闲空间，root 无需扩容（可能已扩过）"
  fi

  # 4. local 放开内容类型（可存镜像/根文件系统/备份/ISO/模板/snippets）
  msg_info "设置 local 存储 content：$LOCAL_CONTENT"
  pvesm set local --content "$LOCAL_CONTENT"
  msg_ok "已更新 local content"
}

main(){
  need_root
  need_pve9
  msg_info "===== 02 系统盘存储调整开始 ====="
  msg_warn "适用于【全新安装、尚无重要 VM/CT】；会销毁 local-lvm 数据"
  echo;  show_state;  echo
  confirm "继续：删 local-lvm → 删 ${VG}/data → 扩容 ${VG}/root → 放开 local content?" || die "已取消"
  merge_locallvm_into_root
  echo
  msg_ok "===== 02 完成，结果如下 ====="
  show_state
  msg_info "第二块 NVMe / USB 移动硬盘本次未处理，需要时再加存储模块"
}
main "$@"
