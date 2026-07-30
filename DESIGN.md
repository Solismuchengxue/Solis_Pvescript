# 设计边界

状态：迁移目标已批准，迁移尚未执行。

## 项目拓扑

本项目采用“外层容器 + 两个独立 Git 仓库”的结构：

```text
Solis_Pvescript/
├── public/   # 公开仓库 Solismuchengxue/Solis_Pvescript
└── private/  # 私有仓库 Solismuchengxue/Solis_Pvescript-private
```

外层 `Solis_Pvescript/` 只负责容纳两个仓库，不是第三个有效 Git 仓库。源路径中存在的无效外层 `.git` 目录不得被解释为项目仓库；是否迁移、保留或清理它属于单独审批的迁移载荷问题。

## 仓库职责

- `public/`：面向用户的合规版本，保存公开脚本、公开文档和不含凭据的驱动获取入口。
- `private/`：完整的个人部署版本，保存仅供本人使用的扩展内容和授权范围内的驱动归档。
- 两个仓库拥有独立的 Git 历史、分支、remote 和工作区状态；二者不是同一仓库的分支或工作树。

## 迁移不变量

- 正式目标路径为 `F:\70_Infrastructure_and_Operations\Solis_Pvescript`。
- 迁移必须保留外层容器及其下的 `public/`、`private/` 两层结构。
- 不得合并两个仓库，不得在外层重新初始化 Git，不得改写历史或修改 remote。
- 迁移前后应分别核对两个仓库的 HEAD、当前分支、remote、status 和 worktree。
- 空目录、本地维护文件、驱动包、缓存及其他未明确内容是否迁移，必须单独确认。

## 基础设施安全边界

- 迁移治理不得触发 PVE、FnOS、驱动、虚拟机、容器、部署或硬件操作。
- 公开仓库不得接收私有仓库的驱动二进制、凭据、证书、Token 或私有配置。
- 涉及删除、移动、remote、历史或运行配置的操作，必须取得单独明确授权。
