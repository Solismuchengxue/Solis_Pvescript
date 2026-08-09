# NVIDIA vGPU 驱动安装指南

[English](vgpu-driver-guide.en.md)

vGPU 全链路涉及三处驱动/授权：**PVE Host**、**飞牛OS(Linux Guest)**、**Win11(Windows Guest)**。
本文档按这三块分别整理，直接跳到对应部分看即可。

驱动本体存放在项目的 `drivers/` 目录（体积大 + 授权限制，不入 git，见 `.gitignore`）。

## 关键约束速查（开始前先看）

| 项 | 约束 |
|----|------|
| host 驱动 vs guest 驱动 | **必须同一 vGPU 分支且版本完全一致**（如都用 535.309.01） |
| 驱动 vs 内核 | R535 与较新 PVE 内核的组合高度敏感；按 `04_iommu.sh` 的兼容内核策略执行，并以实际 DKMS 构建和重启后验证为准 |
| vGPU 类型 | 需要计算能力（CUDA/转码）选 **Q 系列**；vGPU 16.14 的 P4-2Q=`nvidia-64`、P4-4Q=`nvidia-65`，不要把 B 系列当作计算 profile |
| License | 使用有效 entitlement 创建 NVIDIA 官方 CLS/DLS，并从门户或官方 DLS 生成 Client Configuration Token |

## 驱动获取（90 天评估，合法免费）

vGPU 驱动无开源替代，合法免费途径是 NVIDIA 官方 **90 天评估**（不是购买）：

1. NVIDIA 官网 → Data Center → **Virtual GPU (vGPU)** → 申请 **Free Trial / 90-Day Evaluation**。
2. 通过后登录 **NVIDIA Licensing Portal (NLP) / Application Hub** 下载软件包，hypervisor 选 **Linux KVM**。
3. 版本选 **vGPU 16.x（= 535 驱动）**——P4 是 Pascal，下载前对照支持列表确认该版本仍含 P4。
4. 解压软件包，拿到的文件结构：
   ```
   Host_Drivers/NVIDIA-Linux-x86_64-535.xxx.xx-vgpu-kvm.run   → 给 PVE Host 用（见下）
   Guest_Drivers/NVIDIA-Linux-x86_64-535.xxx.xx-grid.run      → 给飞牛OS(Linux) 用
   Guest_Drivers/<版本>_grid_win10_win11_...dch_64bit....exe  → 给 Win11 用
   ```

> 评估申请可能要求组织信息和业务邮箱；审批状态、entitlement 和下载权限以 NVIDIA Licensing Portal 实际显示为准，不要仅依赖通知邮件判断。
> 脚本**不联网下载官方驱动**，请自行准备文件，放入项目的 `drivers/` 目录（可用 `drivers/fetch.sh` 从自建 NAS 拉取）。

---

## PVE Host 侧

**放什么**：`drivers/` 目录存放 NVIDIA vGPU **host** 驱动（注意是 host/KVM 版，不是普通显卡驱动），文件名务必含 `vgpu-kvm`：
```
drivers/NVIDIA-Linux-x86_64-<版本>-vgpu-kvm.run
```

**安装**：`scripts/05_vgpu_driver.sh` 会自动在 `drivers/` 目录查找并安装。

```bash
# 默认自动找 drivers/ 下的 *vgpu*kvm*.run
./scripts/05_vgpu_driver.sh
# 或显式指定
DRIVER_RUN=./drivers/NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run ./scripts/05_vgpu_driver.sh
```

**新增或原位替换 vGPU**：`08_vm_attach.sh` 默认只给没有 vGPU 的 VM 新增一块；若目标 VM 已有 vGPU，脚本会停止，避免误加第二块。原位更换 profile 时必须先关闭目标 VM，并显式设置 `REPLACE_EXISTING=1`：

```bash
# 新增一块 P4-4Q
VMID=101 MDEV_TYPE=nvidia-65 ./scripts/08_vm_attach.sh

# 把已停止 VM 的唯一既有 vGPU 原位替换为 P4-4Q
REPLACE_EXISTING=1 VMID=101 MDEV_TYPE=nvidia-65 ./scripts/08_vm_attach.sh
```

替换模式沿用原 `hostpci` 索引、PCI 地址和其他选项，只改 `mdev=`。它要求 VM 已停止且恰好存在一个既有 vGPU。vGPU 16.x 同一物理 GPU 上的 time-sliced vGPU 必须具有相同 framebuffer 大小；若仍有其他大小的活动 profile，目标类型会显示 `available_instances=0`，脚本会在修改前退出。

---

## 飞牛OS（Linux Guest）侧

适用于任何 Debian 系 Linux guest（飞牛OS 基于 Debian 12）。前置：guest 已挂载 vGPU（`08_vm_attach.sh`），且拿到与 host **同版本**的 guest 驱动（如 `NVIDIA-Linux-x86_64-535.309.01-grid.run`）。

### 1. 传驱动到飞牛

可使用以下任一受控传输方式：

- **WebDAV / 浏览器下载**：从本人有权访问的文件服务下载 Guest 驱动；不要在命令、文档或 Git 中写入账号密码。
- **SSH 直连飞牛**：飞牛存储池的真实文件系统路径格式是 `/vol{存储池编号}/{用户ID}/`，例如：
  - 存储空间1 → `/vol1/1000/`（1000 = 飞牛默认管理员用户 UID）
  - 存储空间2 → `/vol2/1000/`
  - 约定驱动统一放 `/vol1/1000/drivers/`，SSH 登录飞牛后到这个路径下取 `.run` 安装。

> `drivers/fetch.sh` 的职责是从私有 NAS 把 **Host 驱动**拉到本地仓库 `drivers/`，不是把 Guest 驱动传入 FnOS。

### 2. 安装驱动

```bash
sudo apt update
sudo apt install -y build-essential dkms linux-headers-$(uname -r) pkg-config

cd /vol1/1000/drivers/
chmod +x NVIDIA-Linux-x86_64-535.309.01-grid.run
sudo ./NVIDIA-Linux-x86_64-535.309.01-grid.run
```

安装过程关键选项：

| 提示 | 选择 | 原因 |
|------|------|------|
| 注册模块到 DKMS？ | **Yes** | 内核升级后驱动自动重建，否则要手动重装 |
| 安装 32-bit 兼容库？ | **No** | 纯 64 位环境用不到 |
| 运行 nvidia-xconfig？ | **No** | 无图形界面（X） |
| 其他提示（如 TLS） | 默认 | 不影响功能 |

重启并验证：
```bash
sudo reboot
# 重启后
nvidia-smi   # 应显示所分配的 GPU（如 GRID P4-4Q）、显存及驱动版本
```

### 3. 配置 License

先使用有效 entitlement 在 [NVIDIA Licensing Portal](https://ui.licensing.nvidia.com/) 创建官方 CLS 或 DLS 服务实例，并生成 Client Configuration Token。下面只配置 Guest，不创建 License 服务：

```bash
# 1) 将从 NVIDIA Licensing Portal 或官方 DLS 获取的 Token 复制到默认目录
sudo mkdir -p /etc/nvidia/ClientConfigToken
sudo cp <Client-Configuration-Token路径> /etc/nvidia/ClientConfigToken/
sudo chmod 744 /etc/nvidia/ClientConfigToken/*.tok

# 2) 按当前 NVIDIA Client Licensing 指南配置 /etc/nvidia/gridd.conf
#    FeatureType 应与实际产品授权和 vGPU 类型匹配，不要复用来源不明的配置。

# 3) 重启服务并验证
sudo systemctl restart nvidia-gridd
nvidia-smi -q | grep -i -A3 license
```

> NVIDIA 不同 vGPU 软件版本的 `FeatureType` 和默认行为可能不同，请以对应版本的 [Client Licensing User Guide](https://docs.nvidia.com/vgpu/latest/grid-licensing-user-guide/) 为准。`compute_mode` 在 vGPU 环境下由 profile、驱动和授权共同决定，不能把来源不明的 Token 或配置当作许可证替代品。

### 4. 配置 NVIDIA Container Toolkit（Docker GPU）

NVIDIA Container Toolkit 是安装在 Linux Guest 上的系统软件包和 Docker runtime 集成，不是长期运行的 Docker 容器。推荐使用 NVIDIA 官方 APT 仓库；若发行版或 NAS 应用中心也提供封装版本，应二选一，不要混装。

下面以现场验证过的 `1.19.1-1` 为例。安装前先确认 `nvidia-smi`、License 和 `/dev/nvidia-uvm` 正常，并备份已有 `/etc/docker/daemon.json`：

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor --yes \
      -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL \
  https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

sudo apt-get update
NVIDIA_CONTAINER_TOOLKIT_VERSION=1.19.1-1
sudo apt-get install -y \
  "nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
  "nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
  "libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
  "libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"

if sudo test -f /etc/docker/daemon.json; then
  sudo cp -a /etc/docker/daemon.json \
    "/etc/docker/daemon.json.pre-nvidia-$(date +%Y%m%d-%H%M%S)"
fi
sudo nvidia-ctk runtime configure --runtime=docker
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl restart docker
```

上面的 `nvidia-ctk` 命令只注册 NVIDIA runtime，不把它设为默认；普通容器继续使用 `runc`。验证时应同时检查 runtime、原有容器和临时 CUDA 容器：

```bash
docker info --format 'runtimes={{json .Runtimes}} default={{.DefaultRuntime}}'
docker ps
docker run --rm --gpus all \
  nvidia/cuda:12.2.2-base-ubuntu22.04 nvidia-smi -L
```

容器测试通过只证明 CUDA/NVIDIA runtime 基础链路可用。影视硬件转码还应以真实的非直放转码验证 NVENC；相册智能分类等功能应以实际推理任务和 GPU 使用记录验收。Guest 内核升级后还要再次确认 DKMS、`nvidia-smi`、UVM、Docker runtime 和容器 GPU；必要时为新内核重建 Guest 驱动。

---

## Win11（Windows Guest）侧

前置：guest 已挂载 vGPU（`08_vm_attach.sh`），且拿到与 host **同版本**的 guest 驱动（如 `539.72_grid_win10_win11_server2019_server2022_dch_64bit_international.exe`，535.309.01 对应的 Windows 包）。

> ⚠️ **驱动没装、没验证能看到 GPU 之前，不要把 Win11 的显示适配器改成 `none`。** 这时候关掉 VirtIO/std 显示，vGPU 还出不了图，会导致连控制台都进不去。等驱动装好、确认能看到 P4 之后再考虑要不要关。

### 1. 传驱动到 Win11

启动 VM：
```bash
qm start <VMID>
```

通过本人有权访问的 WebDAV、浏览器下载、SMB 或其他受控文件传输方式，把对应的 Windows Guest 驱动送入 VM。不要在公开文档或命令历史中写入文件服务地址、账号或密码。

### 2. 安装驱动

双击运行，标准 NVIDIA 安装向导走完，**重启**。

重启后确认能看到 GPU：设备管理器 → 显示适配器，应能看到多出一个 NVIDIA 设备（此时可能还没 License，属正常）。

### 3. 配置 License

1. 从 NVIDIA Licensing Portal 或官方 DLS 获取 Client Configuration Token，放到：
   ```
   C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\
   ```
2. `services.msc` 找到 **NVIDIA Display Container LS**，重启该服务（或直接重启系统）。
3. 验证：打开 **NVIDIA Control Panel** 看右下角授权状态，或系统托盘的 **NVIDIA Container** 通知会弹出授权详情。

> Windows vGPU Guest 通常会根据 vGPU 类型选择相应授权；具体行为仍以所安装驱动分支对应的 NVIDIA Client Licensing 文档为准。
