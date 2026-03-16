# Tavily Master Key Migration Design

**Goal:** 将脚本访问 TavilyProxyManager 的凭证语义统一为 `TAVILY_MASTER_KEY`，避免把代理凭证误写成上游 Tavily API Key。

## Context

当前仓库存在三类 Tavily 变量：

- `TAVILY_MASTER_KEY`：代理自身的单个访问令牌
- `TAVILY_API_KEY`：历史上被脚本当作代理访问令牌使用
- `TAVILY_API_KEYS`：多个真实 Tavily 官方 key，用于导入代理后做轮询

其中 `TAVILY_API_KEY` 的名字和真实用途不一致，容易让维护者误以为脚本直接调用的是 Tavily 官方 API。

## Decision

执行一次不保留兼容层的硬切迁移：

- 保留 `TAVILY_MASTER_KEY`，作为所有脚本访问 TavilyProxyManager 的唯一凭证
- 保留 `TAVILY_API_KEYS`，作为导入脚本使用的多个上游 Tavily keys
- 删除 `TAVILY_API_KEY` 作为脚本侧变量

## Scope

需要同步修改：

- `scripts/tavily-search.sh`
- `scripts/web-map.sh`
- `scripts/web-fetch.sh`
- `scripts/import-keys.sh`
- `scripts/setup.sh`
- `.env.example`
- `README.md`
- `docs/architecture.md`
- `docs/plans/2026-03-01-ultimate-search-skill.md`

## Validation

至少验证以下行为：

1. 仅设置 `TAVILY_MASTER_KEY` 时，`tavily-search.sh`、`web-map.sh`、`web-fetch.sh` 会继续执行到发请求阶段。
2. 仅设置旧变量 `TAVILY_API_KEY` 时，上述脚本会报出缺少 `TAVILY_MASTER_KEY`。
3. 仓库文档与环境模板中不再将 `TAVILY_API_KEY` 描述为脚本访问凭证。
