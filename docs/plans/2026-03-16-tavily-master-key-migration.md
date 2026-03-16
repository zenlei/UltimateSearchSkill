# Tavily Master Key Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Tavily 代理访问凭证从历史命名 `TAVILY_API_KEY` 统一收口到 `TAVILY_MASTER_KEY`。

**Architecture:** 所有脚本对 TavilyProxyManager 的调用统一读取 `TAVILY_MASTER_KEY`。`TAVILY_API_KEYS` 继续作为批量导入到代理的上游 Tavily keys 列表。迁移不保留兼容层。

**Tech Stack:** Bash, curl, jq, Markdown

---

### Task 1: 写失败测试锁定新变量约定

**Files:**
- Create: `tests/tavily_master_key_migration_test.sh`

**Step 1: 写失败测试**

创建 shell 测试，验证：

- 仅设置 `TAVILY_MASTER_KEY` 时，三个脚本不会因为缺变量提前退出
- 仅设置 `TAVILY_API_KEY` 时，三个脚本会提示缺少 `TAVILY_MASTER_KEY`

**Step 2: 运行测试确认失败**

Run: `bash tests/tavily_master_key_migration_test.sh`

Expected: 当前至少 `web-fetch.sh` 和 `web-map.sh` 仍依赖 `TAVILY_API_KEY`，测试失败。

### Task 2: 修改脚本与配置

**Files:**
- Modify: `.env.example`
- Modify: `scripts/tavily-search.sh`
- Modify: `scripts/web-map.sh`
- Modify: `scripts/web-fetch.sh`
- Modify: `scripts/import-keys.sh`
- Modify: `scripts/setup.sh`

**Step 1: 修改脚本变量**

将脚本中所有代理调用凭证改为 `TAVILY_MASTER_KEY`。

**Step 2: 删除旧变量同步**

删除 `import-keys.sh` 中把 `TAVILY_MASTER_KEY` 再写入 `TAVILY_API_KEY` 的逻辑。

**Step 3: 更新环境模板**

从 `.env.example` 删除 `TAVILY_API_KEY=`，保留 `TAVILY_MASTER_KEY=` 和 `TAVILY_API_KEYS=`。

### Task 3: 同步说明文档

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/plans/2026-03-01-ultimate-search-skill.md`

**Step 1: 统一术语**

把脚本访问代理凭证统一写成 `TAVILY_MASTER_KEY`。

**Step 2: 保留多 key 导入术语**

保留 `TAVILY_API_KEYS` 作为多个真实 Tavily keys 的文档说明。

### Task 4: 重新运行验证

**Files:**
- Test: `tests/tavily_master_key_migration_test.sh`

**Step 1: 运行回归测试**

Run: `bash tests/tavily_master_key_migration_test.sh`

Expected: PASS

**Step 2: 运行仓库内全文检查**

Run: `rg -n "TAVILY_API_KEY" .`

Expected: 不再出现将 `TAVILY_API_KEY` 作为脚本访问凭证的代码或文案。
