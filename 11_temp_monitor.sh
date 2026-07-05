#!/usr/bin/env bash
# 11_temp_monitor.sh —— PVE Web UI 显示 CPU/NVMe 温度、频率、功耗、SMART 健康度
#   实际的 Nodes.pm(后端 API) / pvemanagerlib.js(前端面板) patch 由社区脚本完成，
#   本脚本负责：下载缓存、确认后执行、以及卸载还原。
#
# 来源：https://github.com/a904055262/PVE-manager-status（showtempcpufreq.sh）
#   已审查：数据采集全部走本地命令（sensors/smartctl/turbostat），无远程执行；
#   自带按版本号的备份(.bak)与 restore 机制；全自动执行，无交互确认。
#   会给 smartctl/turbostat 加 SUID 位，并重启 pveproxy 使前端生效。
#
# 用法：
#   ./11_temp_monitor.sh           安装/更新（默认）
#   ./11_temp_monitor.sh remod     还原后重新安装（上游版本更新后用这个）
#   ./11_temp_monitor.sh restore   卸载还原，恢复到修改前的 Nodes.pm/pvemanagerlib.js/proxmoxlib.js
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SCRIPT_URL="https://raw.githubusercontent.com/a904055262/PVE-manager-status/main/showtempcpufreq.sh"
CACHE_DIR="/opt/pve-temp-monitor"
CACHE_SCRIPT="${CACHE_DIR}/showtempcpufreq.sh"
ACTION="${1:-install}"

fetch_script(){
  mkdir -p "$CACHE_DIR"
  msg_info "下载/更新监控脚本..."
  wget -q -O "$CACHE_SCRIPT" "$SCRIPT_URL" || die "下载失败，检查网络：$SCRIPT_URL"
  chmod +x "$CACHE_SCRIPT"
  msg_ok "脚本就绪：$CACHE_SCRIPT"
}

main(){
  need_root
  need_pve9
  msg_info "===== 11 温度/频率/SMART 监控（PVE Web UI）====="

  case "$ACTION" in
    restore)
      [[ -f "$CACHE_SCRIPT" ]] || die "未找到已缓存的脚本，无法 restore：$CACHE_SCRIPT"
      msg_warn "将还原 Nodes.pm / pvemanagerlib.js / proxmoxlib.js 到修改前状态"
      confirm "确认还原?" || die "已取消"
      "$CACHE_SCRIPT" restore
      msg_ok "已还原，pveproxy 会自动重启（浏览器控制台短暂断线，刷新即可）"
      ;;
    install|remod)
      msg_warn "将安装 lm-sensors/smartmontools/linux-cpupower，patch PVE 核心文件（Nodes.pm/pvemanagerlib.js）"
      msg_warn "会给 smartctl/turbostat 加 SUID 位，并重启 pveproxy（浏览器控制台短暂断线，刷新即可）"
      msg_info "来源：https://github.com/a904055262/PVE-manager-status（已审查：本地采集，自带备份/还原）"
      confirm "继续?" || die "已取消"
      fetch_script
      if [[ "$ACTION" == "remod" ]]; then
        "$CACHE_SCRIPT" remod
      else
        "$CACHE_SCRIPT"
      fi
      echo
      msg_ok "===== 11 完成 ====="
      msg_info "PVE Web UI → 节点 → 摘要，可看到温度/频率/功耗/SMART"
      msg_info "卸载还原：./11_temp_monitor.sh restore"
      ;;
    *)
      die "未知参数：$ACTION（支持 install|remod|restore）"
      ;;
  esac
}
main "$@"
