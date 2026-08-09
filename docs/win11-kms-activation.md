# Windows 11 激活与组织 KMS 客户端配置

[English](win11-kms-activation.en.md)

本项目不部署、不推荐、也不提供第三方 KMS 模拟服务或公共 KMS 地址。Windows 激活必须以用户实际拥有的许可证和授权范围为准。

## 1. 选择合法激活方式

根据实际授权情况选择其中一种方式：

- **Retail / OEM / 数字许可证**：适合个人设备或长期使用的单台虚拟机。
- **MAK**：适用于组织批量许可中分配的多次激活密钥。
- **组织内部 KMS**：仅适用于拥有 Microsoft Volume Licensing、有效 CSVLK（KMS Host Key）并满足微软激活条件的组织。
- **Evaluation**：适合短期测试环境，按微软评估版本的期限和条款使用。

微软官方说明：KMS Host 必须使用组织通过批量许可获得的 CSVLK 激活；Windows 客户端还必须满足 KMS 激活阈值。参见：

- [KMS activation planning](https://learn.microsoft.com/windows-server/get-started/kms-activation-planning)
- [Create a KMS activation host](https://learn.microsoft.com/windows-server/get-started/kms-create-host)

## 2. Retail、MAK 或数字许可证

如果系统曾被手动指定到某个 KMS Host，先清除该配置，再输入实际拥有的产品密钥：

```cmd
slmgr /ckms
slmgr /ipk <你的合法 Retail 或 MAK 密钥>
slmgr /ato
slmgr /xpr
```

也可以在 Windows 11 中进入：

```text
设置 → 系统 → 激活 → 更改产品密钥
```

## 3. 连接组织内部的官方 KMS

只有在组织管理员已经提供合法 KMS Host 的情况下，才使用下面的客户端配置。`<组织KMS地址>` 必须是组织内部授权部署的服务器，不能替换为来源不明的公共 KMS 地址。

以管理员身份打开 PowerShell 或 CMD：

```cmd
slmgr /ipk <与当前 Windows 版本匹配的官方 GVLK>
slmgr /skms <组织KMS地址>:1688
slmgr /ato
slmgr /xpr
```

GVLK 只是让 Windows 进入 KMS Client 模式，本身不代表许可证，也不能代替组织的批量许可。不同 Windows 版本对应的 GVLK 请查阅微软官方列表：

- [KMS client activation keys](https://learn.microsoft.com/windows-server/get-started/kms-client-activation-keys)

## 4. 检查和排障

```cmd
slmgr /dlv
slmgr /xpr
```

- `0xC004F074`：无法联系 KMS Host，或组织 KMS 尚未满足激活条件；请联系组织管理员。
- `0xC004F050`：输入的产品密钥与当前 Windows 版本不匹配。
- 要恢复 KMS 自动发现：执行 `slmgr /ckms`，清除手动指定的服务器。

> 激活成功不等同于自动获得软件许可。许可证是否有效，取决于产品密钥、购买渠道、设备或用户授权以及相应许可条款。
