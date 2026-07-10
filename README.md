# Solis PVE Script

联想 M920x 上的 Proxmox VE 9.x 一键化配置脚本：基础环境 + 网络/IPv6 + 存储 + Tesla P4 vGPU + FnOS/Win11 虚拟机。

## 目标硬件

| 部件 | 规格 |
|------|------|
| 主机 | 联想 M920x 小主机 |
| CPU | i7-8700T（6核12线程，支持 VT-d / IOMMU） |
| 内存 | DDR4 16G×2 = 32G |
| 系统盘 | M.2 NVMe 476.9G（`nvme0n1`，PVE 系统） |
| 数据盘 | M.2 NVMe 931.5G（`nvme1n1`，PCIe 直通给飞牛OS） |
| 网卡 | M.2 A+E key 转 RJ45，Intel **i226-V** 芯片，2.5G（`igc` 驱动） |
| 显卡 | Tesla **P4**（Pascal，8G），已改主动散热 |

## 模块清单

| 脚本 | 功能 | 状态 |
|------|------|------|
| `lib/common.sh` | 公共库：日志 / root 检查 / PVE9 检查 / 确认 / 备份 | ✅ |
| `01_base.sh` | APT 源(deb822)国内镜像、去订阅弹窗、时区、NTP、基础包、中文 locale、温度/SMART 监控 | ✅ |
| `02_storage.sh` | 删 local-lvm、`lvextend` 扩容 root（第二盘/USB 暂留） | ✅ |
| `03_network.sh` | vmbr0 网桥、i226 确认、**IPv6**（主机 SLAAC + VM 同网段直拿公网 v6） | ✅ |
| `04_iommu.sh` | IOMMU 引导参数、黑名单 nouveau、内核版本检测（不兼容自动降级并 pin） | ✅ |
| `05_vgpu_driver.sh` | NVIDIA vGPU host 驱动（535/16.x，自备 .run）+DKMS+验证 | ✅ |
| `06_vgpu_mdev.sh` | 拉起 vgpu 服务、ECC 检测关闭、列出 P4 的 mdev profile | ✅ |
| `07_dls.sh` | fastapi-dls 自建 License 服务器（Docker）+ guest 配置指引 | ✅ |
| `08_vm_attach.sh` | 交互式给 VM 挂 vGPU（自动分配空闲 hostpci 索引，不覆盖已有设备） | ✅ |
| `09_fnos_vm.sh` | 创建飞牛OS VM（系统盘 qcow2 + 数据盘 NVMe PCIe 直通） | ✅ |
| `10_win11_vm.sh` | 创建 Win11 VM（UEFI+TPM2.0+VirtIO，待挂 vGPU） | ✅ |
| `drivers/fetch.sh` | 从自建 NAS(WebDAV) 拉取 host 驱动，IP/账号/密码不入库 | ✅ |
| `setup.sh` | 总入口菜单，逐项调用上述模块 | ✅ |

## 部署进度

> **vGPU 全链路已跑通**：飞牛OS 与 Win11 均已挂载 P4 vGPU(`nvidia-64`/2Q)，guest 驱动装好、License 验证为 `NVIDIA RTX Virtual Workstation`，两台 VM 共享同一张 P4（各占 2GB，卡内还剩 4GB/2 个槽位）。

- [x] 脚本 v1~v2 全部完成（`lib` + `01~10` + `setup` + `drivers/fetch.sh`）
- [x] NVIDIA vGPU 90 天评估获批，下载 **vGPU 16.14（535.309.01）Linux KVM** 完整包
- [x] `01~04` 基础配置 + IOMMU + 内核 pin（6.14.4，535 在 7.x/6.15+ 上不兼容，需手动降级）
- [x] `05` host 驱动安装（535.309.01 × 内核 6.14.4，未打补丁直接编译通过）
- [x] `06` vGPU 服务 + ECC 关闭（注意：ECC 关闭后需【重启】才生效，脚本已改为关闭后自动退出避免误判）
- [x] `07` 自建 fastapi-dls License 服务器（Docker，Docker Hub 走国内镜像加速）
- [x] `08` 挂载 vGPU：**飞牛OS + Win11 均已挂**，都用 `nvidia-64`（GRID P4-2Q，P4 的 Pascal 同规格族限制下唯一可行选择）
- [x] `09` 飞牛OS VM：系统盘 + 数据盘（KIOXIA NVMe）PCIe 直通，飞牛数据完全独立于 PVE；guest 驱动 + License(`gridd.conf`+`FeatureType=2`) 已验证 `Licensed`
- [x] `10` Win11 VM：已装机、自建 KMS 激活（[docs/win11-kms-activation.md](docs/win11-kms-activation.md)）；guest 驱动 + License 已验证 `NVIDIA RTX Virtual Workstation`
- [ ] M920x SATA FPC 转接板：原理图/封装设计已完成（本地笔记，未入库），**尚未打样/焊接/上机测试**；FPC 侧线序待万用表实测
- [ ] 存储盘现状：USB 硬盘盒（已关 UASP，稳定），作为 SATA 转接板完工前的过渡方案
- [ ] 存储盘现状：USB 硬盘盒（已关 UASP，稳定），作为 SATA 转接板完工前的过渡方案

## 用法

```bash
# 1. 传到 PVE 主机（任选其一）
git clone <你的仓库地址> Solis_Pvescript
#   或 scp -r Solis_Pvescript root@<PVE_IP>:/root/

# 2. 赋可执行权限（首次 clone 需要；Windows 提交的 .sh 已用 git --chmod=+x 保留执行位）
cd /root/Solis_Pvescript && chmod +x *.sh lib/*.sh drivers/*.sh

# 3. 按顺序执行（建议逐个跑、看输出），或 ./setup.sh 走菜单
./01_base.sh
```

### 常用环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `MIRROR` | `ustc` | 镜像站，可选 `tuna` |
| `DO_UPGRADE` | `0` | `1` 时同时 `apt full-upgrade` |
| `TEMP_MONITOR` | `1` | `01` 是否安装温度/SMART 监控（PVE Web UI 摘要页显示） |
| `ASSUME_YES` | `0` | `1` 时无人值守，跳过所有确认 |

例：`MIRROR=tuna DO_UPGRADE=1 ./01_base.sh`

## 推荐执行顺序（含重启点）

```text
01 基础配置
02 系统盘扩容
03 网络 / IPv6
04 IOMMU / 引导 ───► ⚠️ 重启（内核版本不兼容会自动提示降级到 6.14.4 并 pin）
05 安装 vGPU 驱动（重启后跑）───► 建议再次重启，确认 nvidia-smi 正常
06 vGPU 服务 / ECC 关闭 ───► ⚠️ 若关闭了 ECC，脚本会退出，重启后重跑一遍 06
07 自建 License 服务器
08 给 VM 挂 vGPU ───► qm start；guest 内装同分支驱动 + 配 License
09 / 10 创建飞牛OS / Win11 VM（可在 01~04 之后随时穿插进行，不依赖 vGPU 驱动）
```

- **04 之后必须重启**，IOMMU / nouveau 黑名单 / 内核 pin 才生效。
- **05 装完驱动**建议重启，确认 `nvidia-smi` 正常、`nvidia-vgpud` 已运行。
- **06 若提示关闭了 ECC**：脚本会主动退出并提示重启，避免在 ECC 未真正生效时误判 mdev 检测失败。
- 也可 `./setup.sh` 走菜单逐项执行。
- **09/10 不依赖 GPU 驱动**，可以在等驱动评估邮件期间先把 VM 建好、系统装好。

## vGPU 驱动与 License（关键路径）

vGPU host 驱动是 NVIDIA **专有**软件，无开源替代（nouveau 不支持 mdev 切分）。

### 驱动获取：90 天评估（合法免费）

| 项 | 说明 |
|----|------|
| 申请入口 | [NVIDIA vGPU 评估注册](https://enterpriseproductregistration.nvidia.com/?LicType=EVAL&ProductFamily=vGPU) |
| ⚠️ 邮箱门槛 | **必须企业/域名邮箱**；个人邮箱（Gmail/Outlook/QQ）会被拒。可用自有域名邮箱（[腾讯企业邮基础版](https://exmail.qq.com/) 免费） |
| ⚠️ **审核邮件不必等** | 官方说 24~48 工作小时会发邮件，**实测两周都没收到**。提交申请后**直接用同一个企业邮箱去门户登录**，entitlement 往往已经生效，不用干等邮件 |
| 下载 | 门户 [ui.licensing.nvidia.com](https://ui.licensing.nvidia.com) → Software Downloads，筛选 **Platform=Linux KVM（非 Red Hat KVM）**、**Version=16.x** |
| 已验证版本 | **vGPU 16.14（含 535.309.01 host + guest 驱动）**，P4(Pascal) 在 6.14.4 内核上**未打补丁直接 DKMS 编译通过** |
| 取件 | `Host_Drivers/*.run` → `drivers/`（给 05）；`Guest_Drivers/...` → 装进虚拟机 |

驱动本体不入 git（体积大 + 授权限制），走自建 NAS 分发：见 [drivers/fetch.sh](drivers/fetch.sh) 和 [drivers/README.md](drivers/README.md)。

### License：自建 DLS，不被 90 天卡住

- 评估的 **90 天限制的是 license，不是驱动**；驱动一旦下到手就一直能装能用。
- guest 满速所需 license **全程走 `07` 自建的 fastapi-dls**，长期有效，连 NVIDIA license server 都不用碰。
- **Linux guest 必须配置 `/etc/nvidia/gridd.conf`**（`ServerAddress` + `FeatureType=2`），否则可能拿到不含计算能力的授权，表现为 `nvidia-smi --query-gpu=compute_mode` 显示 `Prohibited`。详见 [drivers/README.md](drivers/README.md)。
- host 与 guest 驱动**必须同一版本**（不只是同分支，如都是 535.309.01）。

### 完整闭环（飞牛OS + Win11 均已验证跑通）

```text
NVIDIA 评估账号 → 门户下 16.14 Linux KVM 包 → host .run(05) → guest 驱动 →
07 自建 DLS 发 token → guest 配 gridd.conf → Licensed → GPU 加速可用
```

## ⚠️ 重要：行尾必须是 LF

脚本在 Windows 上编辑、在 PVE(Linux) 上运行。**必须保持 LF 行尾**，否则 bash 报
`$'\r': command not found`。若传输后报该错，在 PVE 上执行一次：

```bash
sed -i 's/\r$//' *.sh lib/*.sh
# 或： apt install -y dos2unix && dos2unix *.sh lib/*.sh
```

## 设计约定

- 所有脚本 `set -euo pipefail`，开头做 root 与 PVE 版本检查。
- **幂等**：可重复执行，不产生重复配置。
- **自动备份**：被修改的系统文件首次会备份为 `*.orig`。
- **危险操作确认**：删除存储、改 GRUB 等会先 `confirm`（`ASSUME_YES=1` 跳过）。
- Windows 提交 `.sh` 文件后需 `git update-index --chmod=+x <文件>` 补执行位（Windows 无执行位概念，git 默认按 644 入库）。

## 备注

- 面向 **PVE 9.x（Debian 13 Trixie）**，APT 源为 deb822 格式，与 8.x 不通用。
- P4 走 **vGPU(mdev)** 时**不要**绑 `vfio-pci`；`vfio-pci` 仅用于整卡直通给单个 VM，二者互斥。
- P4 是 Pascal，vGPU 驱动用 **16.x(535) 分支**；17.x 起已删除 Pascal 支持。
- 内核版本敏感：535 在 **7.x / 6.15+ 内核不兼容**，`04` 会自动检测并提示降级到 `6.14.4-1+deb13u1-pve`。
- P4 出厂 **ECC 默认开启**（显存 7680/8192M）；`06` 会自动检测询问关闭，**关闭后必须重启**才生效。
- 本卡为**标准正品 P4**：device `10de:1bb3` / subsystem `10de:11d8`，vBIOS 未魔改。

## 其他文档

- [docs/win11-kms-activation.md](docs/win11-kms-activation.md) —— 飞牛自建 KMS（`teddysun/kms`）激活 Win11
- [drivers/README.md](drivers/README.md) —— 驱动获取、guest 安装步骤、License 配置排障
