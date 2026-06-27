# Windows 11 KMS 激活（自建 KMS 服务器）

在飞牛 OS 上用 Docker 跑 `teddysun/kms`，给同网段的 Win11 VM 做 KMS 激活。

> ⚠️ **说明**：KMS 设计用于企业批量授权。自建 KMS 激活属于灰色做法，激活每 **180 天**到期（只要能连到 KMS 服务器会自动续期）。正经长期使用建议购买正版 key，homelab/测试场景下可用本方案。
>
> ⚠️ **关于镜像版本**：KMS 客户端身份由安装的 **GVLK** 决定，与 ISO 是零售版还是 Volume 版**无关**。消费版（如 `Win11_25H2_Pro_Chinese_Simplified_x64.iso`）装好 Win11 Pro 后，执行 `slmgr /ipk <Pro GVLK>` 即切换为 KMS 客户端，可正常激活。
>
> ⚠️ **安装时不要输入产品密钥**，选「我没有产品密钥」，装完进桌面后再走下方 `slmgr` 三连，否则零售/数字许可证可能与 KMS 冲突。

## 1. 飞牛容器部署 KMS 服务器

**Web UI 方式**（飞牛 → Docker → 容器）：

| 项 | 值 |
|----|-----|
| 镜像 | `teddysun/kms` |
| 端口映射 | `1688:1688` |
| 重启策略 | 总是重启（always） |

**命令行方式**（飞牛终端）：

```bash
docker run -d --restart=always -p 1688:1688 --name kms teddysun/kms
```

部署后 KMS 地址为 `<飞牛IP>:1688`，下文以 `192.168.0.50:1688` 为例。

## 2. Windows 11 激活

以**管理员身份**打开 PowerShell 或 CMD，依次执行：

```cmd
slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
slmgr /skms 192.168.0.50:1688
slmgr /ato
```

| 命令 | 含义 |
|------|------|
| `/ipk` | 安装 Win11 Pro 的 KMS 客户端 key（GVLK，微软公开发布，非盗版 key） |
| `/skms` | 指向自建 KMS 服务器 |
| `/ato` | 立即向服务器激活 |

## 3. 验证

```cmd
slmgr /xpr
```

显示「已激活，到期日期 xxxx」即成功。KMS 激活有效期 180 天，联网可自动续期。

## 附：常见 Win11 GVLK（KMS 客户端 key）

| 版本 | GVLK |
|------|------|
| Win11 Pro | `W269N-WFGWX-YVC9B-4J6C9-T83GX` |
| Win11 Pro for Workstations | `NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J` |
| Win11 Enterprise | `NPPR9-FWDCX-D2C8J-H872K-2YT43` |
| Win11 Education | `NW6C2-QMPVW-D7KKK-3GKT6-VCFB2` |
| Win11 Home | `TX9XD-98N7V-6WMQ6-BB6BV-PV683` |

> 完整 GVLK 列表见微软官方文档：<https://learn.microsoft.com/windows-server/get-started/kms-client-activation-keys>

## 常见问题

- **`/ato` 报错 0xC004F074**：Win11 连不到 KMS 服务器。检查飞牛容器是否运行、`1688` 端口是否放行、VM 与飞牛是否同网段互通。
- **`/ipk` 报错 0xC004F050（无效产品密钥）**：GVLK 与当前 Windows 版本不匹配。确认装的是 Pro 就用 Pro 的 GVLK，别用错版本。
- **激活掉了**：超过 180 天未联网续期。重新 `slmgr /ato` 即可。
- **想换激活方式**：`slmgr /upk` 卸载当前 key 后重新操作。
