# drivers/ —— 放置 NVIDIA vGPU host 驱动

`05_vgpu_driver.sh` 会在本目录查找 host 驱动并安装。

## 放什么

NVIDIA vGPU **host** 驱动（注意是 host/KVM 版，不是普通显卡驱动）：

```
NVIDIA-Linux-x86_64-<版本>-vgpu-kvm.run
```

- **Tesla P4 = Pascal 架构**，建议 **16.x（535.xxx）** 分支。
- 文件名务必含 `vgpu-kvm`（host 端）。guest 端驱动是另一个文件，装进虚拟机里，**且必须与 host 同分支**。

## 从哪获取（90 天评估，合法免费）

vGPU 驱动无开源替代，合法免费途径是 NVIDIA 官方 **90 天评估**（不是购买）：

1. NVIDIA 官网 → Data Center → **Virtual GPU (vGPU)** → 申请 **Free Trial / 90-Day Evaluation**。
2. 通过后登录 **NVIDIA Licensing Portal (NLP) / Application Hub** 下载软件包，hypervisor 选 **Linux KVM**。
3. 版本选 **vGPU 16.x（= 535 驱动）**——P4 是 Pascal，下载前对照支持列表确认该版本仍含 P4。
4. 解压软件包，分别取出：
   - `Host_Drivers/NVIDIA-Linux-x86_64-535.xxx.xx-vgpu-kvm.run` → 放**本目录**，给 `05` 用
   - `Guest_Drivers/...`（Windows `.exe` / Linux `.run`）→ 装进虚拟机

### guest 驱动传到飞牛（FnOS）的两种方式

- **WebDAV**：走 `drivers/fetch.sh`，不用关心飞牛底层路径，脚本自动处理。
- **SSH 直连飞牛**：飞牛存储池的真实文件系统路径格式是 `/vol{存储池编号}/{用户ID}/`，例如：
  - 存储空间1 → `/vol1/1000/`（1000 = 飞牛默认管理员用户 UID）
  - 存储空间2 → `/vol2/1000/`
  - 约定驱动统一放 `/vol1/1000/drivers/`，SSH 登录飞牛后到这个路径下取 `.run`/`.deb` 安装。

> ⚠️ 评估申请表通常要填**组织名 + 业务邮箱**，个人 Gmail 可能需审核或被拒——这是实际门槛。
> 脚本**不联网下载官方驱动**，请自行准备 `.run` 放到这里。

## Guest 驱动安装（Linux，以飞牛OS验证过的流程为例）

适用于任何 Debian 系 Linux guest（飞牛OS 基于 Debian 12）。前置：guest 已挂载 vGPU（`08_vm_attach.sh`），且拿到与 host **同版本**的 guest 驱动（如 `NVIDIA-Linux-x86_64-535.309.01-grid.run`）。

**1. 传驱动到 guest** —— 见上一节"guest 驱动传到飞牛的两种方式"（WebDAV / SSH 到 `/vol1/1000/drivers/`）。

**2. 装编译依赖**
```bash
sudo apt update
sudo apt install -y build-essential dkms linux-headers-$(uname -r) pkg-config
```

**3. 装驱动**
```bash
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

**4. 重启并验证驱动**
```bash
sudo reboot
# 重启后
nvidia-smi   # 应显示 GPU 信息（如 GRID P4-2Q）及驱动版本
```

## License 闭环（无需买授权）

guest 满速需 license。评估期内可用 NVIDIA 评估 license；**评估到期后、或干脆从一开始，就用本仓库 `07_dls.sh` 自建 fastapi-dls 发 token** 给 guest，即可持续 `Licensed`——连 NVIDIA 的 license server 都不用碰。

`07_dls.sh` 跑完会打印对应 guest 的完整配置指引（含下面这步），也可手动照做：

**Linux guest 配置 License：**
```bash
# 1) 告诉 nvidia-gridd 去哪要 license、要什么类型
sudo tee /etc/nvidia/gridd.conf <<'EOF'
ServerAddress=<你的 DLS_IP>
FeatureType=2
EOF

# 2) 下载 client token
sudo mkdir -p /etc/nvidia/ClientConfigToken
sudo curl --insecure https://<DLS_IP>:443/-/client-token \
  -o /etc/nvidia/ClientConfigToken/token_$(date '+%d-%m-%Y-%H-%M-%S').tok

# 3) 重启服务、验证
sudo systemctl restart nvidia-gridd
nvidia-smi -q | grep -i license                     # 应为 Licensed
nvidia-smi --query-gpu=compute_mode --format=csv     # 应为 Default，非 Prohibited
```

> ⚠️ **`gridd.conf` 这步不能省。** 缺失时 `nvidia-gridd` 不知道该请求哪种授权，guest 拿到的可能是不含计算能力的低档授权，表现为 `nvidia-smi --query-gpu=compute_mode` 显示 **`Prohibited`**（禁止创建 CUDA 上下文），飞牛相册/影视的"GPU 加速转码"等功能会报"启用GPU失败"。`FeatureType=2` = 请求图形+计算授权，配上 Q 系列 vGPU 类型（见下）即可正常使用。
>
> `compute_mode` 在 vGPU 环境下由 host 侧 profile 类型 + license 授权版本决定，**guest 内无法用 `nvidia-smi -c` 直接修改**，改 `gridd.conf` 重新申领 token 才是正确路径。

## 版本配套（重要）

| 项 | 约束 |
|----|------|
| host 驱动 vs guest 驱动 | **必须同一 vGPU 分支且版本完全一致**（如都用 535.309.01） |
| 驱动 vs 内核 | 535 在 6.8+ 内核多半需打补丁；故 04 已 pin 内核 |
| vGPU 类型 | 需要计算能力（CUDA/转码）选 **Q 系列**（如 `nvidia-64`），不要 B 系列（`nvidia-157`，vApps 用，无计算） |
| License | guest 满速需 License → 见 `07_dls.sh`（自建 DLS），guest 需能访问 host 的 **443 端口** |

## 用法

```bash
# 默认自动找本目录下的 *vgpu*kvm*.run
./05_vgpu_driver.sh
# 或显式指定
DRIVER_RUN=./drivers/NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run ./05_vgpu_driver.sh
```
