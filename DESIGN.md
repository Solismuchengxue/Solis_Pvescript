# 设计边界

[English](DESIGN_EN.md)

状态：正式新路径迁移已完成；public/private 双仓结构已投入使用。

## 项目拓扑

本项目采用“外层容器 + 两个独立 Git 仓库”的结构：

```text
Solis_Pvescript/
├── public/   # 公开仓库 Solismuchengxue/Solis_Pvescript
└── private/  # 私有仓库 Solismuchengxue/Solis_Pvescript-private
```

外层 `Solis_Pvescript/` 只负责容纳两个仓库，不是第三个有效 Git 仓库，也不应在外层初始化 Git、保存项目级 Agent 状态或承载仓库历史。

## 仓库职责

- `public/`：面向用户的合规版本，保存公开脚本、公开文档和不含凭据的驱动获取入口。
- `private/`：完整的个人部署版本，保存仅供本人使用的扩展内容和授权范围内的驱动归档。
- 两个仓库拥有独立的 Git 历史、分支、remote 和工作区状态；二者不是同一仓库的分支或工作树。

## 当前维护不变量

- 项目于2026-11-01停止维护；本设计保留为历史架构，不新增开发或部署工作。

- 正式项目路径为 `F:\60_Infrastructure_and_Operations\Solis_Pvescript`。
- 必须保留外层容器及其下的 `public/`、`private/` 两层结构。
- 不得合并两个仓库，不得在外层重新初始化 Git，不得改写历史或修改 remote。
- 交付、维护和迁移核对必须分别检查两个仓库的 HEAD、当前分支、remote、status 和 worktree。
- public 只接收可公开内容；private 资产、驱动、凭据和现场配置不得因文档同步进入 public。

## 基础设施安全边界

- 文档、迁移或仓库治理不得触发 PVE、FnOS、驱动、虚拟机、容器、部署或硬件操作。
- 公开仓库不得接收私有仓库的驱动二进制、凭据、证书、Token 或私有配置。
- 涉及删除、移动、remote、历史或运行配置的操作，必须取得单独明确授权。

技术架构、模块职责、端到端链路和运行限制见 [`README.md`](README.md)。
