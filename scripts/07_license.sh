#!/usr/bin/env bash
# 07_license.sh —— NVIDIA vGPU 官方 License 配置指引
#
# 本脚本不创建 License 服务，只输出 NVIDIA 官方 CLS/DLS 的配置入口、
# Guest Token 放置位置和验证命令。许可证及 Client Configuration Token
# 必须来自 NVIDIA Licensing Portal 中的有效 entitlement。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main(){
  need_root
  need_pve9

  msg_info "===== 07 NVIDIA vGPU 官方 License 配置指引 ====="
  cat <<'EOF'

1. 登录 NVIDIA Licensing Portal：
   https://ui.licensing.nvidia.com/

2. 使用有效 entitlement 创建以下任一官方服务实例：
   - Cloud License Service（CLS，NVIDIA 托管）
   - Delegated License Service（DLS，官方虚拟设备）

3. 在门户或官方 DLS 中生成 Client Configuration Token。

4. 将 Token 放入 Guest：

   [Linux Guest]
     /etc/nvidia/ClientConfigToken/
     chmod 744 /etc/nvidia/ClientConfigToken/*.tok
     systemctl restart nvidia-gridd
     nvidia-smi -q | grep -i -A3 license

   [Windows Guest]
     C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\
     然后重启 NVIDIA Display Container LS 服务或重启系统。

5. 官方文档：
   https://docs.nvidia.com/license-system/latest/
   https://docs.nvidia.com/vgpu/latest/grid-licensing-user-guide/

本项目不提供第三方 License 服务，也不生成或分发授权 Token。
EOF

  msg_ok "===== 07 指引完成 ====="
  msg_info "下一步：08_vm_attach.sh 把 vGPU 挂给 VM"
}

main "$@"
