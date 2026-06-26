# drivers/ —— 放置 NVIDIA vGPU host 驱动

`05_vgpu_driver.sh` 会在本目录查找 host 驱动并安装。

## 放什么

NVIDIA vGPU **host** 驱动（注意是 host/KVM 版，不是普通显卡驱动）：

```
NVIDIA-Linux-x86_64-<版本>-vgpu-kvm.run
```

- **Tesla P4 = Pascal 架构**，建议 **16.x（535.xxx）** 分支。
- 文件名务必含 `vgpu-kvm`（host 端）。guest 端驱动是另一个文件，装进虚拟机里，**且必须与 host 同分支**。

## 从哪获取

- NVIDIA Licensing Portal（需 NVIDIA Enterprise / vGPU 软件授权账号）。
- 或你自有的合法授权渠道。

> 脚本**不会**联网下载官方驱动（涉及授权）。请自行准备 `.run` 文件放到这里。

## 版本配套（重要）

| 项 | 约束 |
|----|------|
| host 驱动 vs guest 驱动 | **必须同一 vGPU 分支**（如都用 16.x/535） |
| 驱动 vs 内核 | 535 在 6.8+ 内核多半需打补丁；故 04 已 pin 内核 |
| License | guest 满速需 License → 见 `07_dls.sh`（自建 DLS） |

## 用法

```bash
# 默认自动找本目录下的 *vgpu*kvm*.run
./05_vgpu_driver.sh
# 或显式指定
DRIVER_RUN=./drivers/NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run ./05_vgpu_driver.sh
```
