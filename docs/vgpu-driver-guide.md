# NVIDIA vGPU 驱动安装指南

vGPU 全链路涉及三处驱动/授权：**PVE Host**、**飞牛OS(Linux Guest)**、**Win11(Windows Guest)**。
本文档按这三块分别整理，直接跳到对应部分看即可。

驱动本体存放在项目的 `drivers/` 目录（体积大 + 授权限制，不入 git，见 `.gitignore`）。

## 关键约束速查（开始前先看）

| 项 | 约束 |
|----|------|
| host 驱动 vs guest 驱动 | **必须同一 vGPU 分支且版本完全一致**（如都用 535.309.01） |
| 驱动 vs 内核 | 535 在 6.8+ 内核多半需打补丁；故 `04_iommu.sh` 已 pin 内核到兼容版本 |
| vGPU 类型 | 需要计算能力（CUDA/转码）选 **Q 系列**（如 `nvidia-64`），不要 B 系列（`nvidia-157`，vApps 用，无计算） |
| License | guest 满速需 License → 见 `07_dls.sh`（自建 DLS），guest 需能访问 host 的 **443 端口** |

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

> ⚠️ 评估申请表通常要填**组织名 + 业务邮箱**，个人 Gmail 可能需审核或被拒——这是实际门槛。
> ⚠️ **审核邮件不必等**：官方说 24~48 工作小时会发邮件，实测两周都没收到。提交申请后**直接用同一个企业邮箱去门户登录**，entitlement 往往已经生效，不用干等邮件。
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

---

## 飞牛OS（Linux Guest）侧

适用于任何 Debian 系 Linux guest（飞牛OS 基于 Debian 12）。前置：guest 已挂载 vGPU（`08_vm_attach.sh`），且拿到与 host **同版本**的 guest 驱动（如 `NVIDIA-Linux-x86_64-535.309.01-grid.run`）。

### 1. 传驱动到飞牛

两种方式：

- **WebDAV**：走 `drivers/fetch.sh`，不用关心飞牛底层路径，脚本自动处理。
- **SSH 直连飞牛**：飞牛存储池的真实文件系统路径格式是 `/vol{存储池编号}/{用户ID}/`，例如：
  - 存储空间1 → `/vol1/1000/`（1000 = 飞牛默认管理员用户 UID）
  - 存储空间2 → `/vol2/1000/`
  - 约定驱动统一放 `/vol1/1000/drivers/`，SSH 登录飞牛后到这个路径下取 `.run` 安装。

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
nvidia-smi   # 应显示 GPU 信息（如 GRID P4-2Q）及驱动版本
```

### 3. 配置 License

`07_dls.sh` 跑完会打印完整配置指引（含下面这步），也可手动照做：

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

> ⚠️ **`gridd.conf` 这步不能省。** 缺失时 `nvidia-gridd` 不知道该请求哪种授权，guest 拿到的可能是不含计算能力的低档授权，表现为 `nvidia-smi --query-gpu=compute_mode` 显示 **`Prohibited`**（禁止创建 CUDA 上下文），飞牛相册/影视的"GPU 加速转码"等功能会报"启用GPU失败"。`FeatureType=2` = 请求图形+计算授权，配上 Q 系列 vGPU 类型即可正常使用。
>
> `compute_mode` 在 vGPU 环境下由 host 侧 profile 类型 + license 授权版本决定，**guest 内无法用 `nvidia-smi -c` 直接修改**，改 `gridd.conf` 重新申领 token 才是正确路径。

---

## Win11（Windows Guest）侧

前置：guest 已挂载 vGPU（`08_vm_attach.sh`），且拿到与 host **同版本**的 guest 驱动（如 `539.72_grid_win10_win11_server2019_server2022_dch_64bit_international.exe`，535.309.01 对应的 Windows 包）。

> ⚠️ **驱动没装、没验证能看到 GPU 之前，不要把 Win11 的显示适配器改成 `none`。** 这时候关掉 VirtIO/std 显示，vGPU 还出不了图，会导致连控制台都进不去。等驱动装好、确认能看到 P4 之后再考虑要不要关。

### 1. 传驱动到 Win11

启动 VM：
```bash
qm start <VMID>
```

飞牛已有 WebDAV，最简单是在 Win11 里直接用浏览器下载：
```
http://<飞牛IP>:5005/drivers/Guest_Drivers/539.72_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
```
（WebDAV 若需账密，浏览器会弹窗要求输入）

### 2. 安装驱动

双击运行，标准 NVIDIA 安装向导走完，**重启**。

重启后确认能看到 GPU：设备管理器 → 显示适配器，应能看到多出一个 NVIDIA 设备（此时可能还没 License，属正常）。

### 3. 配置 License

1. Win11 里打开浏览器，访问：
   ```
   https://<DLS_IP>:443/-/client-token
   ```
   下载 `.tok` 文件，放到：
   ```
   C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\
   ```
2. `services.msc` 找到 **NVIDIA Display Container LS**，重启该服务（或直接重启系统）。
3. 验证：打开 **NVIDIA Control Panel** 看右下角授权状态，或系统托盘的 **NVIDIA Container** 通知会弹出授权详情。

> ✅ **实测：Windows guest 不需要 Linux 那样的 `gridd.conf`/`FeatureType` 配置**，只要 token 放对位置、重启服务，就能直接拿到正确档位的授权（验证结果：`NVIDIA RTX Virtual Workstation`，与 host 请求的 vWS 档位一致）。这点上 Windows 比 Linux guest 省一步。
