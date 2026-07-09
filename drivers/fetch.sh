#!/usr/bin/env bash
# drivers/fetch.sh —— 从自建 NAS(WebDAV/HTTP) 拉取 vGPU host 驱动到 drivers/ 顶层
#
# 背景：驱动体积大且涉及 NVIDIA 授权，不入 git(见 .gitignore)。
#       本脚本只记录“怎么拉”，驱动本体走你自己的 NAS。
#       IP / 账号 / 密码都不写死：地址、账号运行时输入或用环境变量预设，
#       密码始终由 curl 交互提示，不落盘、不进命令历史。
#
# 用法：
#   ./drivers/fetch.sh                         # 交互输入地址/账号，回车后敲密码
#   NAS_URL=http://x.x.x.x:5005/drivers ./drivers/fetch.sh   # 预设地址
#
# 环境变量(均可选)：
#   NAS_URL       存放驱动的 WebDAV/HTTP 目录，如 http://192.168.x.x:5005/drivers
#   WEBDAV_USER   账号(留空=匿名，不加认证)
#   DRIVER_FILE   host 驱动文件名(默认见下)
#   SRC_SUBDIR    源端子目录(默认 Host_Drivers；若 NAS 上平铺存放，设为空 SRC_SUBDIR=)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRIVER_FILE="${DRIVER_FILE:-NVIDIA-Linux-x86_64-535.309.01-vgpu-kvm.run}"
SRC_SUBDIR="${SRC_SUBDIR-Host_Drivers}"   # 用 - 而非 :- ，允许显式置空

# 地址：环境变量优先，否则交互输入
NAS_URL="${NAS_URL:-}"
[[ -z "$NAS_URL" ]] && read -r -p "NAS WebDAV 目录 (如 http://192.168.x.x:5005/drivers): " NAS_URL
[[ -n "$NAS_URL" ]] || { echo "未提供 NAS_URL，退出" >&2; exit 1; }

# 账号：环境变量优先，否则交互输入(匿名直接回车)
WEBDAV_USER="${WEBDAV_USER:-}"
[[ -z "$WEBDAV_USER" ]] && read -r -p "账号 (匿名直接回车): " WEBDAV_USER

# 组装源 URL
src="${NAS_URL%/}/"
[[ -n "$SRC_SUBDIR" ]] && src="${src}${SRC_SUBDIR%/}/"
src="${src}${DRIVER_FILE}"
dst="${SCRIPT_DIR}/${DRIVER_FILE}"

# 有账号才加 -u；密码由 curl 交互提示(不写进命令行)
auth=()
[[ -n "$WEBDAV_USER" ]] && auth=(-u "$WEBDAV_USER")

echo "拉取: $src"
echo "保存: $dst"
curl "${auth[@]}" -fL -o "$dst" "$src"
echo
ls -lh "$dst"
echo "✔ 完成。驱动已放在 drivers/ 顶层，05_vgpu_driver.sh 可自动识别。"
