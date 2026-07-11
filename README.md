# Solis PVE Script

Proxmox VE 9.x 一键化配置脚本：基础环境 + 网络/IPv6 + 存储 + vGPU + FnOS/Win11 虚拟机。

## 1.模块清单

| 脚本 | 功能 | 状态 |
|------|------|------|
| `scripts/common.sh` | 公共库：日志 / root 检查 / PVE9 检查 / 确认 / 备份 | ✅ |
| `scripts/01_base.sh` | APT 源(deb822)国内镜像、去订阅弹窗、时区、NTP、基础包、中文 locale、温度/SMART 监控 | ✅ |
| `scripts/02_storage.sh` | 删 local-lvm、`lvextend` 扩容 root（第二盘/USB 暂留） | ✅ |
| `scripts/03_network.sh` | vmbr0 网桥、i226 确认、**IPv6**（主机 SLAAC + VM 同网段直拿公网 v6） | ✅ |
| `scripts/04_iommu.sh` | IOMMU 引导参数、黑名单 nouveau、内核版本检测（不兼容自动降级并 pin） | ✅ |
| `scripts/05_vgpu_driver.sh` | NVIDIA vGPU host 驱动（535/16.x，自备 .run）+DKMS+验证 | ✅ |
| `scripts/06_vgpu_mdev.sh` | 拉起 vgpu 服务、ECC 检测关闭、列出 P4 的 mdev profile | ✅ |
| `scripts/07_dls.sh` | fastapi-dls 自建 License 服务器（Docker）+ guest 配置指引 | ✅ |
| `scripts/08_vm_attach.sh` | 交互式给 VM 挂 vGPU（自动分配空闲 hostpci 索引，不覆盖已有设备） | ✅ |
| `scripts/09_fnos_vm.sh` | 创建飞牛OS VM（系统盘 qcow2 + 数据盘 NVMe PCIe 直通） | ✅ |
| `scripts/10_win11_vm.sh` | 创建 Win11 VM（UEFI+TPM2.0+VirtIO，待挂 vGPU） | ✅ |
| `drivers/fetch.sh` | 从自建 NAS(WebDAV) 拉取 host 驱动，IP/账号/密码不入库 | ✅ |
| `setup.sh` | 总入口菜单，逐项调用上述模块（根目录唯一的 .sh 文件） | ✅ |

## 2.用法

```bash
# 1. 传到 PVE 主机
cd ~ && git clone https://github.com/Solismuchengxue/Solis_Pvescript.git

# 2. 赋可执行权限（首次 clone 需要；Windows 提交的 .sh 已用 git --chmod=+x 保留执行位）
cd ~/Solis_Pvescript && chmod +x setup.sh scripts/*.sh drivers/*.sh

# 3. 执行——菜单驱动(推荐，交互式逐项引导)
./setup.sh

#   或手动逐个跑单个脚本(适合只重跑某一步、调试)
./scripts/01_base.sh
```

### 常用环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `MIRROR` | `ustc` | 镜像站，可选 `tuna` |
| `DO_UPGRADE` | `0` | `1` 时同时 `apt full-upgrade` |
| `TEMP_MONITOR` | `1` | `01` 是否安装温度/SMART 监控（PVE Web UI 摘要页显示） |
| `ASSUME_YES` | `0` | `1` 时无人值守，跳过所有确认 |

例：`MIRROR=tuna DO_UPGRADE=1 ./scripts/01_base.sh`

## 3.推荐执行顺序（含重启点）

无论走 `./setup.sh` 菜单还是手动逐个跑脚本，都按下面顺序，重启点和注意事项同样适用：

```text
01 基础配置
02 系统盘扩容
03 网络 / IPv6
04 IOMMU / 引导 ───► ⚠️ 重启（内核版本不兼容会自动提示降级到 6.14.4 并 pin）
05 安装 vGPU 驱动（重启后跑）───► 建议再次重启，确认 nvidia-smi 正常
06 vGPU 服务 / ECC 关闭 ───► ⚠️ 若关闭了 ECC，脚本会退出，重启后重跑一遍 06
07 自建 License 服务器
08 给 VM 挂 vGPU ───► qm start；guest 内装同分支驱动 + 配 License（详见 docs/vgpu-driver-guide.md）
09 / 10 创建飞牛OS / Win11 VM（可在 01~04 之后随时穿插进行，不依赖 vGPU 驱动）
```

- **04 之后必须重启**，IOMMU / nouveau 黑名单 / 内核 pin 才生效。
- **05 装完驱动**建议重启，确认 `nvidia-smi` 正常、`nvidia-vgpud` 已运行。
- **06 若提示关闭了 ECC**：脚本会主动退出并提示重启，避免在 ECC 未真正生效时误判 mdev 检测失败。
- **09/10 不依赖 GPU 驱动**，可以先把 VM 建好、系统装好。

### 详细步骤参考

- [docs/vgpu-driver-guide.md](docs/vgpu-driver-guide.md) —— vGPU 驱动获取、PVE Host / 飞牛OS(Linux Guest) / Win11(Guest) 三侧的安装与 License 配置完整指南（05/08 的详细展开）
- [docs/win11-kms-activation.md](docs/win11-kms-activation.md) —— 飞牛自建 KMS（`teddysun/kms`）激活 Win11（10 之后的激活步骤）

## 4.备注

- 所有脚本 `set -euo pipefail`，开头做 root 与 PVE 版本检查。
- **幂等**：可重复执行，不产生重复配置。
- **自动备份**：被修改的系统文件首次会备份为 `*.orig`。
- **危险操作确认**：删除存储、改 GRUB 等会先 `confirm`（`ASSUME_YES=1` 跳过）。
- 面向 **PVE 9.x（Debian 13 Trixie）**，APT 源为 deb822 格式，与 8.x 不通用。
- P4 走 **vGPU(mdev)** 时**不要**绑 `vfio-pci`；`vfio-pci` 仅用于整卡直通给单个 VM，二者互斥。
- P4 是 Pascal，vGPU 驱动用 **16.x(535) 分支**；17.x 起已删除 Pascal 支持。
- 内核版本敏感：535 在 **7.x / 6.15+ 内核不兼容**，`04` 会自动检测并提示降级到 `6.14.4-1+deb13u1-pve`。
- P4 出厂 **ECC 默认开启**（显存 7680/8192M）；`06` 会自动检测询问关闭，**关闭后必须重启**才生效。

## 5.已验证硬件

| 部件   | 规格                                                         |
| ------ | ------------------------------------------------------------ |
| 主机   | 联想 M920x 小主机                                            |
| CPU    | i7-8700T（6核12线程，支持 VT-d / IOMMU）                     |
| 内存   | DDR4 16G×2 = 32G                                             |
| 系统盘 | M.2 NVMe 476.9G（`nvme0n1`，PVE 系统）                       |
| 数据盘 | M.2 NVMe 931.5G（`nvme1n1`，PCIe 直通给飞牛OS）              |
| 网卡   | M.2 A+E key 转 RJ45，Intel **i226-V** 芯片，2.5G（`igc` 驱动） |
| 显卡   | Tesla **P4**（Pascal，8G），已改主动散热                     |
