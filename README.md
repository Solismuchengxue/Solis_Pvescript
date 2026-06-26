# Solis PVE Script

联想 M920x 上的 Proxmox VE 9.x 一键化配置脚本：基础环境 + 网络/IPv6 + 存储 + Tesla P4 vGPU。

## 目标硬件

| 部件 | 规格 |
|------|------|
| 主机 | 联想 M920x 小主机 |
| CPU | i7-8700T（支持 VT-d / IOMMU） |
| 内存 | DDR4 16G×2 = 32G |
| 系统盘/数据盘 | M.2 NVMe 1T ×2 |
| 外置 | USB3.0 1T 移动硬盘 |
| 网卡 | M.2 A+E key 转 RJ45，Intel **i226** 芯片，2.5G（占无线网卡位，`igc` 驱动） |
| 显卡 | Tesla **P4**（Pascal），已改主动散热 |

## 模块清单

| 脚本 | 功能 | 状态 |
|------|------|------|
| `lib/common.sh` | 公共库：日志 / root 检查 / PVE9 检查 / 确认 / 备份 | ✅ |
| `01_base.sh` | APT 源(deb822)国内镜像、去订阅弹窗、时区、NTP、基础包 | ✅ |
| `02_storage.sh` | 删 local-lvm、`lvextend` 扩容 root（第二盘/USB 暂留） | ✅ |
| `03_network.sh` | vmbr0 网桥、i226 确认、**IPv6**（主机 SLAAC + VM 同网段直拿公网 v6） | ✅ |
| `04_iommu.sh` | IOMMU 引导参数(GRUB/systemd-boot 自适应)、黑名单 nouveau、内核 pin | ✅ |
| `05_vgpu_driver.sh` | NVIDIA vGPU host 驱动（535 分支，自备 .run）+DKMS+验证 | ✅ |
| `06_vgpu_mdev.sh` | 拉起 vgpu 服务、列出 P4 的 mdev profile、查看状态 | ✅ |
| `07_dls.sh` | fastapi-dls 自建 License 服务器（Docker）+ guest 配置指引 | ✅ |
| `08_vm_attach.sh` | 交互式给 VM 挂 vGPU（含 VMID/类型/实例数校验） | ✅ |
| `setup.sh` | 总入口菜单，逐项调用上述模块 | ✅ |

## 部署进度

> 脚本已全部完成；当前卡在 NVIDIA 驱动获取（外部依赖，等审核）。

- [x] 脚本 v1 全部完成（`lib` + `01~08` + `setup`）
- [x] P4 硬件验证：Win11 + GPU-Z 确认为标准卡、可识别
- [x] NVIDIA vGPU 90 天评估申请已提交（2026-06-26，等审核邮件 24~48 工作小时）
- [ ] 收到邮件 → 下 16.x KVM 包 → host `.run` 放 `drivers/`
- [ ] 部署 `01~04` + 重启（**不依赖驱动，可在等邮件期间先做**）
- [ ] 驱动到手 → `05~08` 跑通 → 多 VM 共享

## 用法

```bash
# 1. 传到 PVE 主机（任选其一）
scp -r Solis_Pvescript root@<PVE_IP>:/root/
#   或 git clone

# 2. 赋可执行权限
cd /root/Solis_Pvescript && chmod +x *.sh

# 3. 按顺序执行（建议逐个跑、看输出）
./01_base.sh
```

### 常用环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `MIRROR` | `ustc` | 镜像站，可选 `tuna` |
| `DO_UPGRADE` | `0` | `1` 时同时 `apt full-upgrade` |
| `ASSUME_YES` | `0` | `1` 时无人值守，跳过所有确认 |

例：`MIRROR=tuna DO_UPGRADE=1 ./01_base.sh`

## 推荐执行顺序（含重启点）

```text
01 基础配置
02 系统盘扩容
03 网络 / IPv6
04 IOMMU / 引导 ───►  ⚠️ 重启
05 安装 vGPU 驱动（重启后跑）───►  建议再次重启，确认 nvidia-smi 正常
06 vGPU 服务 / 查看 mdev 类型
07 自建 License 服务器
08 给 VM 挂 vGPU ───►  qm start；guest 内装同分支驱动 + 配 License
```

- **04 之后必须重启**，IOMMU / nouveau 黑名单 / 内核 pin 才生效。
- **05 装完驱动**建议重启，确认 `nvidia-smi` 正常、`nvidia-vgpud` 已运行。
- 也可 `./setup.sh` 走菜单逐项执行。
- **两阶段部署**：`01~04` 不依赖 GPU 驱动，可在等评估邮件期间先跑通（含 04 后重启）；驱动到手后再从 `05` 开始。

## vGPU 驱动与 License（关键路径）

vGPU host 驱动是 NVIDIA **专有**软件，无开源替代（nouveau 不支持 mdev 切分）。驱动获取与授权是本项目最容易卡的环节。

### 驱动获取：90 天评估（合法免费）

| 项 | 说明 |
|----|------|
| 申请入口 | [NVIDIA vGPU 评估注册](https://enterpriseproductregistration.nvidia.com/?LicType=EVAL&ProductFamily=vGPU) |
| ⚠️ 邮箱门槛 | **必须企业/域名邮箱**；个人邮箱（Gmail/Outlook/QQ）会被拒。可用自有域名邮箱（[腾讯企业邮基础版](https://exmail.qq.com/) 免费，绑自己域名，开通后用 `name@你的域名` 注册） |
| 版本 | 选 **vGPU 16.x（= 535 驱动）**，hypervisor 选 **Linux KVM**（PVE 即 KVM，无 Proxmox 选项） |
| 取件 | host `*-vgpu-kvm.run` → `drivers/`（给 05）；guest 驱动 → 装进 VM |

详细步骤见 [drivers/README.md](drivers/README.md)。

### License：自建 DLS，不被 90 天卡住

- 评估的 **90 天限制的是 license，不是驱动**；驱动一旦下到手就一直能装能用。
- guest 满速所需 license **全程走 `07` 自建的 fastapi-dls**，长期有效，连 NVIDIA license server 都不用碰。
- host 与 guest 驱动**必须同分支**（都 16.x/535）。

### 完整闭环

```text
评估账号 → 下 16.x KVM 包 → host .run(05) → guest 驱动 → 07 自建 DLS 发 token → guest Licensed → 多 VM 共享
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

## 备注

- 面向 **PVE 9.x（Debian 13 Trixie）**，APT 源为 deb822 格式，与 8.x 不通用。
- P4 走 **vGPU(mdev)** 时**不要**绑 `vfio-pci`；`vfio-pci` 仅用于整卡直通给单个 VM，二者互斥。
- P4 是 Pascal，vGPU 驱动建议 **16.x(535) 分支**；host 与 guest 驱动必须同代。
- 本卡为**标准正品 P4**：device `10de:1bb3` / subsystem `10de:11d8`，vBIOS 未魔改。
- P4 出厂 **ECC 默认开启**（显存 7680/8192M）；跑 vGPU 前用 `nvidia-smi -e 0` 关闭并重启，释放完整 8G（`06` 会自动检测询问）。
