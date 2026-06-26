#!/usr/bin/env bash
# 07_dls.sh —— 自建 NVIDIA vGPU License 服务器（fastapi-dls）
#   面向自有 Tesla P4：guest 满速需 License，本脚本用 Docker 起一个开源 DLS。
#   1) 安装 docker（如缺）
#   2) 生成实例/网站证书
#   3) docker run 启动 fastapi-dls（自动重启、持久化数据库）
#   4) 输出 guest 端 token 配置指引
#
# 环境变量：
#   DLS_IP=<本机IP>     guest 要能访问的地址（默认自动探测主用 IP）
#   DLS_PORT=443        监听端口
#   LEASE_DAYS=90       授权租约天数
#   DLS_DIR=/opt/fastapi-dls
#   IMAGE=collinwebdesigns/fastapi-dls:latest
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

DLS_PORT="${DLS_PORT:-443}"
LEASE_DAYS="${LEASE_DAYS:-90}"
DLS_DIR="${DLS_DIR:-/opt/fastapi-dls}"
TZ_="${TZ:-Asia/Shanghai}"
IMAGE="${IMAGE:-collinwebdesigns/fastapi-dls:latest}"
DLS_IP="${DLS_IP:-$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]\+\).*/\1/p' | head -1)}"

ensure_docker(){
  if ! command -v docker >/dev/null 2>&1; then
    msg_info "安装 docker.io ..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install docker.io
    systemctl enable --now docker
    msg_ok "docker 安装完成"
  else
    msg_info "docker 已安装"
  fi
  # 配置国内镜像加速（Docker Hub 在中国大陆被墙）
  local cfg=/etc/docker/daemon.json
  if [[ ! -f "$cfg" ]] || ! grep -q 'registry-mirrors' "$cfg" 2>/dev/null; then
    msg_info "配置 Docker 国内镜像加速..."
    mkdir -p /etc/docker
    cat > "$cfg" <<'DOCKEREOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com"
  ]
}
DOCKEREOF
    systemctl restart docker
    msg_ok "Docker 镜像加速已配置（DaoCloud + 腾讯云）"
  fi
}

gen_certs(){
  local c="$DLS_DIR/cert"
  mkdir -p "$c"
  if [[ ! -f "$c/instance.private.pem" ]]; then
    openssl genrsa -out "$c/instance.private.pem" 2048
  fi
  openssl rsa -in "$c/instance.private.pem" -outform PEM -pubout -out "$c/instance.public.pem"
  if [[ ! -f "$c/webserver.crt" ]]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$c/webserver.key" -out "$c/webserver.crt" -subj "/CN=${DLS_IP}"
  fi
  msg_ok "证书就绪：$c"
}

pull_image(){
  # 国内 Docker Hub 不可直连，依次尝试各镜像前缀
  local prefixes=("docker.m.daocloud.io/" "")
  for prefix in "${prefixes[@]}"; do
    local img="${prefix}${IMAGE}"
    msg_info "拉取镜像：$img"
    if docker pull "$img" 2>/dev/null; then
      [[ -z "$prefix" ]] || docker tag "$img" "$IMAGE" 2>/dev/null || true
      msg_ok "镜像拉取成功"
      return 0
    fi
    msg_warn "失败，换下一个源..."
  done
  die "所有镜像源均失败。可在 Windows/Mac 上拉好后传入：
  docker save ${IMAGE} | gzip > fastapi-dls.tar.gz
  scp fastapi-dls.tar.gz root@${DLS_IP}:/tmp/
  docker load < /tmp/fastapi-dls.tar.gz"
}

run_dls(){
  msg_info "启动 fastapi-dls（${DLS_IP}:${DLS_PORT}，租约 ${LEASE_DAYS} 天）"
  docker rm -f fastapi-dls >/dev/null 2>&1 || true
  docker volume create dls-db >/dev/null 2>&1 || true
  docker image inspect "$IMAGE" >/dev/null 2>&1 || pull_image
  docker run -d --name fastapi-dls --restart=always \
    -e TZ="$TZ_" \
    -e DLS_URL="$DLS_IP" \
    -e DLS_PORT="$DLS_PORT" \
    -e LEASE_EXPIRE_DAYS="$LEASE_DAYS" \
    -e DATABASE="sqlite:////app/database/db.sqlite" \
    -p "${DLS_PORT}:443" \
    -v "$DLS_DIR/cert:/app/cert" \
    -v dls-db:/app/database \
    "$IMAGE"
  sleep 2
  docker ps --filter name=fastapi-dls --format '    {{.Names}}  {{.Status}}  {{.Ports}}'
  msg_ok "fastapi-dls 已启动"
}

print_guest_guide(){
  cat <<EOF

${C_OK}==== guest 端 License 配置指引 ====${C_RESET}
服务器地址： https://${DLS_IP}:${DLS_PORT}

[Linux guest]
  curl --insecure -L -X GET https://${DLS_IP}:${DLS_PORT}/-/client-token \\
    -o /etc/nvidia/ClientConfigToken/client_configuration_token_\$(date '+%d-%m-%Y-%H-%M-%S').tok
  systemctl restart nvidia-gridd
  nvidia-smi -q | grep -i license    # 应显示 Licensed

[Windows guest]
  浏览器访问 https://${DLS_IP}:${DLS_PORT}/-/client-token 下载 .tok，放到：
    C:\\Program Files\\NVIDIA Corporation\\vGPU Licensing\\ClientConfigToken\\
  重启服务 NVIDIA Display Container LS，或重启系统。

前提：guest 内已安装与 host【同分支】的 vGPU guest 驱动。
EOF
}

main(){
  need_root
  need_pve9
  [[ -n "$DLS_IP" ]] || die "无法自动探测 IP，请用 DLS_IP=<本机IP> 指定"
  msg_info "===== 07 自建 vGPU License 服务器 ====="
  msg_info "DLS_IP=$DLS_IP  PORT=$DLS_PORT  LEASE=${LEASE_DAYS}d  DIR=$DLS_DIR"
  msg_warn "注：PVE host 上直接跑 docker 非官方推荐，介意可改放 LXC/VM；功能不受影响"
  confirm "继续部署 fastapi-dls?" || die "已取消"
  ensure_docker
  gen_certs
  run_dls
  print_guest_guide
  echo
  msg_ok "===== 07 完成 ====="
  msg_info "下一步：08_vm_attach.sh 把 vGPU 挂给 VM"
}
main "$@"
