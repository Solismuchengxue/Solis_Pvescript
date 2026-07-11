# shellcheck shell=bash
# common.sh —— 公共函数库，供 scripts/ 下各模块 source
#   用法（各脚本顶部）：
#     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     source "${SCRIPT_DIR}/common.sh"
#   （setup.sh 在项目根目录，用 "${SCRIPT_DIR}/scripts/common.sh"）
#
# 约定：危险/可重复的操作统一走这里的 confirm / backup_once，
#       保证幂等、可重跑、首次原始态被保留为 .orig

# ---- 彩色输出（仅在 tty 下上色）----
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_INFO=$'\e[34m'; C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''
fi

msg_info(){ echo "${C_INFO}[*]${C_RESET} $*"; }
msg_ok()  { echo "${C_OK}[+]${C_RESET} $*"; }
msg_warn(){ echo "${C_WARN}[!]${C_RESET} $*" >&2; }
msg_err() { echo "${C_ERR}[x]${C_RESET} $*" >&2; }
die()     { msg_err "$*"; exit 1; }

# ---- 前置检查 ----
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请用 root 运行本脚本"; }

# 检测是否 PVE 9.x；非 9.x 仅告警不阻断，未安装 PVE 才 die
need_pve9(){
  command -v pveversion >/dev/null 2>&1 || die "未检测到 Proxmox VE（pveversion 不存在）"
  local v; v="$(pveversion 2>/dev/null | sed -n 's#.*pve-manager/\([0-9]\+\).*#\1#p')"
  if [[ "$v" != "9" ]]; then
    msg_warn "当前 PVE 主版本为 ${v:-未知}，本脚本面向 9.x；继续前请自行确认兼容性"
  fi
}

# ---- 交互确认；ASSUME_YES=1 时全部跳过（无人值守）----
confirm(){
  local prompt="${1:-确认继续?}"
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  local ans
  read -r -p "${prompt} [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ---- 备份文件一次到 .orig（保留首次原始态，已存在则不覆盖）----
backup_once(){
  local f="$1"
  [[ -e "$f" ]] || return 0
  [[ -e "${f}.orig" ]] || { cp -a "$f" "${f}.orig"; msg_info "已备份 ${f} -> ${f}.orig"; }
}
