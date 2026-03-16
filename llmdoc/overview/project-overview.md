# 项目概览

UltimateSearchSkill 是一个面向 OpenClaw/Pi 的搜索 Skill，使用 Shell 脚本调用 Grok 与 TavilyProxyManager，提供搜索、抓取和站点映射能力。

## 当前关键约定

- Tavily 运行时脚本统一使用 `TAVILY_MASTER_KEY` 访问 TavilyProxyManager。
- `TAVILY_API_KEYS` 表示多个真实 Tavily 官方 key，仅用于导入到代理后做轮询。
- FireCrawl 仍使用 `FIRECRAWL_API_KEY` 或 `FIRECRAWL_API_KEYS` 作为降级抓取凭证。
