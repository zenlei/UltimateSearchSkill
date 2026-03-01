# UltimateSearchSkill 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 构建一个完整的 Pi/OpenClaw 搜索 Skill，整合 grok2api（多 Grok Token 聚合）+ TavilyProxyManager（多 Tavily Key 聚合），提供双引擎搜索能力。

**Architecture:** 三层架构 —— SKILL.md 提供搜索方法论和规划框架；Shell 脚本封装 API 调用供 agent 通过 Bash 使用；Docker Compose 部署 grok2api + TavilyProxyManager 作为基础设施。搜索策略和提示词来自 GrokSearch MCP 项目的精华提炼。

**Tech Stack:** Shell (bash/curl/jq)、Docker Compose、grok2api (Python/FastAPI)、TavilyProxyManager (Go)

---

## 项目结构

```
UltimateSearchSkill/
├── README.md                       # 项目说明 + 快速上手指南
├── SKILL.md                        # Pi/OpenClaw Skill 核心定义
├── docker-compose.yml              # 一键部署 grok2api + TavilyProxyManager
├── .env.example                    # 环境变量模板
├── scripts/
│   ├── setup.sh                    # 安装部署脚本（检测环境、拉取镜像、启动服务）
│   ├── grok-search.sh              # Grok AI 智能搜索（调用 grok2api）
│   ├── tavily-search.sh            # Tavily 搜索（调用 TavilyProxyManager）
│   ├── web-fetch.sh                # 网页内容抓取（Tavily Extract）
│   ├── web-map.sh                  # 站点映射（Tavily Map）
│   └── dual-search.sh              # 双引擎聚合搜索（并行 Grok + Tavily）
└── docs/
    ├── plans/                      # 实施计划
    └── architecture.md             # 架构说明文档
```

## 组件交互关系

```
Agent (Pi/OpenClaw)
  │
  ├─ SKILL.md 指导搜索策略
  │    ├─ 判断搜索复杂度（简单/中等/复杂）
  │    ├─ 选择合适工具（grok-search / tavily-search / dual-search / web-fetch / web-map）
  │    └─ 交叉验证规则
  │
  └─ Bash 调用脚本
       ├─ grok-search.sh → grok2api (:8100) → Grok Web (x.ai)
       │   特点：AI 驱动搜索，Grok 自带联网，返回综合分析
       │
       ├─ tavily-search.sh → TavilyProxyManager (:8200) → Tavily API
       │   特点：结构化搜索结果，评分排序，支持时间过滤
       │
       ├─ web-fetch.sh → TavilyProxyManager (:8200) → Tavily Extract
       │   特点：提取 URL 内容，返回 Markdown，突破反爬
       │
       ├─ web-map.sh → TavilyProxyManager (:8200) → Tavily Map
       │   特点：发现网站结构，获取 URL 列表
       │
       └─ dual-search.sh → 并行调用 grok-search + tavily-search
           特点：双引擎结果合并，交叉验证
```

## 与 grok2api 的集成方式

**项目地址：** https://github.com/chenyme/grok2api
**部署方式：** Docker Compose
**核心能力：**
- 多 Grok Token 聚合（号池），自动负载均衡
- OpenAI 兼容 API (`/v1/chat/completions`)
- 流/非流式对话
- Token 自动刷新，失败自动切换
- 管理面板 (`/admin`)

**与 Skill 的对接：**
- `grok-search.sh` 调用 `http://localhost:8100/v1/chat/completions`
- 使用 GrokSearch MCP 中的 `search_prompt` 作为 system prompt
- Grok 模型自带实时联网搜索能力，通过 chat 接口触发
- 返回 AI 综合分析结果，由脚本解析提取

## 与 TavilyProxyManager 的集成方式

**项目地址：** https://github.com/xuncv/TavilyProxyManager
**部署方式：** Docker Compose
**核心能力：**
- 多 Tavily Key 聚合，优先使用余额最高的 Key
- 透明代理，API 完全兼容 Tavily 官方格式
- 自动故障切换（401/429/432/433 自动换 Key）
- Master Key 鉴权
- 管理面板 (Web UI)

**与 Skill 的对接：**
- `tavily-search.sh` 调用 `http://localhost:8200/search`
- `web-fetch.sh` 调用 `http://localhost:8200/extract`
- `web-map.sh` 调用 `http://localhost:8200/map`
- 统一使用 Master Key 鉴权

---

## Task 1: 创建项目基础文件

**Files:**
- Create: `UltimateSearchSkill/.env.example`
- Create: `UltimateSearchSkill/.gitignore`

**Step 1: 创建 .env.example**

```bash
# === grok2api 配置 ===
GROK2API_PORT=8100
GROK2API_APP_KEY=changeme           # grok2api 管理面板密码
GROK2API_API_KEY=sk-ultimate-search # 调用 grok2api 的 API Key

# === TavilyProxyManager 配置 ===
TAVILY_PROXY_PORT=8200

# === 搜索脚本配置 ===
GROK_API_URL=http://localhost:8100
GROK_API_KEY=sk-ultimate-search
GROK_MODEL=grok-4.1-fast
TAVILY_API_URL=http://localhost:8200
TAVILY_API_KEY=                     # TavilyProxyManager 的 Master Key（首次启动后获取）
```

**Step 2: 创建 .gitignore**

```
.env
data/
logs/
*.log
.DS_Store
```

**Step 3: Commit**

```bash
git add .env.example .gitignore
git commit -m "chore: init project with env template and gitignore"
```

---

## Task 2: 创建 Docker Compose 部署文件

**Files:**
- Create: `UltimateSearchSkill/docker-compose.yml`

**Step 1: 编写 docker-compose.yml**

```yaml
services:
  grok2api:
    image: ghcr.io/chenyme/grok2api:latest
    container_name: ultimate-search-grok2api
    ports:
      - "${GROK2API_PORT:-8100}:8000"
    environment:
      - DATA_DIR=/data
      - LOG_FILE_ENABLED=true
      - LOG_LEVEL=INFO
      - SERVER_STORAGE_TYPE=local
    volumes:
      - ./data/grok2api:/data
    restart: unless-stopped

  tavily-proxy:
    image: ghcr.io/xuncv/tavilyproxymanager:latest
    container_name: ultimate-search-tavily-proxy
    ports:
      - "${TAVILY_PROXY_PORT:-8200}:8080"
    environment:
      - LISTEN_ADDR=:8080
      - DATABASE_PATH=/app/data/proxy.db
      - TAVILY_BASE_URL=https://api.tavily.com
      - UPSTREAM_TIMEOUT=150s
    volumes:
      - ./data/tavily-proxy:/app/data
      - /etc/localtime:/etc/localtime:ro
    restart: unless-stopped
```

**Step 2: 验证 compose 文件语法**

```bash
docker compose config
```
Expected: 输出规范化的 YAML，无报错

**Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose for grok2api + TavilyProxyManager"
```

---

## Task 3: 创建安装部署脚本

**Files:**
- Create: `UltimateSearchSkill/scripts/setup.sh`

**Step 1: 编写 setup.sh**

功能：
1. 检测 Docker 是否安装
2. 检测 jq 是否安装
3. 复制 .env.example → .env（如不存在）
4. 启动 Docker Compose
5. 等待服务就绪
6. 输出 TavilyProxyManager 的 Master Key
7. 将脚本目录加入 PATH 提示

**Step 2: 赋予执行权限**

```bash
chmod +x scripts/setup.sh
```

**Step 3: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: add setup script for one-click deployment"
```

---

## Task 4: 创建 grok-search.sh

**Files:**
- Create: `UltimateSearchSkill/scripts/grok-search.sh`

**Step 1: 编写脚本**

核心逻辑：
1. 读取环境变量 `GROK_API_URL`、`GROK_API_KEY`、`GROK_MODEL`
2. 接收参数：`--query "查询内容"` `--platform "可选平台"` `--stream`
3. 使用 GrokSearch MCP 的 `search_prompt` 作为 system prompt
4. 自动注入当前时间上下文（检测时间相关查询）
5. 调用 grok2api 的 `/v1/chat/completions`
6. 解析响应，提取内容和信源
7. 输出结构化 JSON 结果

**关键参考：** GrokSearch MCP 的 `search_prompt`（来自 utils.py）和时间注入逻辑（来自 providers/grok.py）

**Step 2: 赋予执行权限并测试**

```bash
chmod +x scripts/grok-search.sh
# 测试（需先启动服务）
./scripts/grok-search.sh --query "test"
```

**Step 3: Commit**

```bash
git add scripts/grok-search.sh
git commit -m "feat: add grok-search script with AI-powered web search"
```

---

## Task 5: 创建 tavily-search.sh

**Files:**
- Create: `UltimateSearchSkill/scripts/tavily-search.sh`

**Step 1: 编写脚本**

核心逻辑：
1. 读取环境变量 `TAVILY_API_URL`、`TAVILY_API_KEY`
2. 接收参数：`--query "查询内容"` `--depth basic|advanced` `--max-results N` `--topic general|news|finance` `--time-range day|week|month|year` `--include-answer`
3. 调用 TavilyProxyManager 的 `POST /search`
4. 使用 Bearer Token 鉴权
5. 输出结构化 JSON 结果

**API 格式参考：**
```bash
curl -X POST "$TAVILY_API_URL/search" \
  -H "Authorization: Bearer $TAVILY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "...",
    "search_depth": "advanced",
    "max_results": 10,
    "include_answer": true,
    "include_raw_content": "markdown"
  }'
```

**Step 2: 赋予执行权限**

**Step 3: Commit**

```bash
git add scripts/tavily-search.sh
git commit -m "feat: add tavily-search script"
```

---

## Task 6: 创建 web-fetch.sh

**Files:**
- Create: `UltimateSearchSkill/scripts/web-fetch.sh`

**Step 1: 编写脚本**

核心逻辑：
1. 接收参数：`--url "URL"` `--depth basic|advanced` `--format markdown|text`
2. 调用 TavilyProxyManager 的 `POST /extract`
3. 提取 `results[0].raw_content`
4. 输出 Markdown 内容

**API 格式参考：**
```bash
curl -X POST "$TAVILY_API_URL/extract" \
  -H "Authorization: Bearer $TAVILY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "urls": ["https://example.com"],
    "extract_depth": "advanced",
    "format": "markdown"
  }'
```

**Step 2: Commit**

```bash
git add scripts/web-fetch.sh
git commit -m "feat: add web-fetch script for URL content extraction"
```

---

## Task 7: 创建 web-map.sh

**Files:**
- Create: `UltimateSearchSkill/scripts/web-map.sh`

**Step 1: 编写脚本**

核心逻辑：
1. 接收参数：`--url "URL"` `--depth N` `--breadth N` `--limit N` `--instructions "说明"`
2. 调用 TavilyProxyManager 的 `POST /map`
3. 输出站点 URL 列表

**Step 2: Commit**

```bash
git add scripts/web-map.sh
git commit -m "feat: add web-map script for site structure discovery"
```

---

## Task 8: 创建 dual-search.sh

**Files:**
- Create: `UltimateSearchSkill/scripts/dual-search.sh`

**Step 1: 编写脚本**

核心逻辑：
1. 接收参数：`--query "查询内容"`
2. 并行调用 `grok-search.sh` 和 `tavily-search.sh`（使用后台进程 + wait）
3. 合并两个引擎的结果
4. 输出合并后的 JSON：`{ "grok": {...}, "tavily": {...} }`
5. agent 可根据 SKILL.md 指引进行交叉验证

**Step 2: Commit**

```bash
git add scripts/dual-search.sh
git commit -m "feat: add dual-search script for cross-engine aggregation"
```

---

## Task 9: 创建 SKILL.md（核心）

**Files:**
- Create: `UltimateSearchSkill/SKILL.md`

**Step 1: 编写 SKILL.md**

这是整个项目的核心，内容来源：
- GrokSearch MCP 的搜索规划方法论（6 阶段规划）
- GrokSearch MCP 的搜索和证据标准
- 双引擎工具使用指南

**结构大纲：**

```markdown
# UltimateSearch Skill

## 工具清单
- `grok-search.sh` — AI 驱动搜索（Grok 联网搜索）
- `tavily-search.sh` — 结构化搜索（Tavily）
- `web-fetch.sh` — 网页内容抓取（Tavily Extract）
- `web-map.sh` — 站点结构映射（Tavily Map）
- `dual-search.sh` — 双引擎聚合搜索

## 搜索决策流程

### 何时使用哪个工具
- 简单事实查询 → `tavily-search.sh --depth basic`
- 复杂/探索性问题 → `dual-search.sh`（双引擎交叉验证）
- 需要 AI 分析的搜索 → `grok-search.sh`
- 抓取指定 URL 内容 → `web-fetch.sh`
- 探索网站结构 → `web-map.sh`

### 搜索复杂度评估
- Level 1（1-2 次搜索）：单个明确问题
- Level 2（3-5 次搜索）：多角度比较/分析
- Level 3（6+ 次搜索）：深度研究课题

### 搜索规划流程
1. 意图分析：明确核心问题
2. 复杂度评估：确定搜索深度
3. 查询拆解：分解为不重叠的子查询
4. 策略选择：broad_first / narrow_first / targeted
5. 工具映射：为每个子查询选择最佳工具
6. 执行顺序：确定并行/串行执行计划

### 证据标准
- 关键事实需 ≥2 个独立来源支持
- 来源冲突时：展示双方证据，评估可信度
- 经验性结论标注置信度（High/Medium/Low）
- 引用格式：[作者/组织, 年份, URL]
- 严禁编造引用

### 输出规范
- 先给出最可能的答案，再展开分析
- 所有技术术语附简明解释
- 使用标准 Markdown 格式
- 每个结论注明信源
```

**Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: add SKILL.md with search methodology and tool guide"
```

---

## Task 10: 创建 README.md

**Files:**
- Create: `UltimateSearchSkill/README.md`

**Step 1: 编写 README.md**

内容：
- 项目简介（一句话描述 + 架构图）
- 特性列表
- 快速开始（3 步：clone → setup → 使用）
- 前置条件
- 详细安装步骤
- 使用示例
- 配置说明
- 致谢（GrokSearch MCP、grok2api、TavilyProxyManager）
- License (MIT)

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with quick start guide"
```

---

## Task 11: 创建架构文档

**Files:**
- Create: `UltimateSearchSkill/docs/architecture.md`

**Step 1: 编写架构文档**

内容：
- 设计理念（Skill vs MCP 的选择）
- 三层架构详解
- 数据流图
- 与 GrokSearch MCP 的对比
- 扩展指南

**Step 2: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: add architecture documentation"
```

---

## Task 12: 集成测试

**Step 1: 在 OpenClaw 服务器上运行 setup.sh**

```bash
ssh -p 2222 ckckck-ubuntu@192.168.1.2
cd UltimateSearchSkill
./scripts/setup.sh
```

**Step 2: 配置 grok2api Token**

访问 `http://192.168.1.2:8100/admin`，添加 Grok Token。

**Step 3: 配置 TavilyProxyManager Key**

访问 `http://192.168.1.2:8200`，添加 Tavily API Key。

**Step 4: 测试各脚本**

```bash
# 测试 Grok 搜索
./scripts/grok-search.sh --query "FastAPI 最新用法"

# 测试 Tavily 搜索
./scripts/tavily-search.sh --query "FastAPI latest features" --depth advanced

# 测试网页抓取
./scripts/web-fetch.sh --url "https://fastapi.tiangolo.com/"

# 测试站点映射
./scripts/web-map.sh --url "https://fastapi.tiangolo.com/" --depth 1

# 测试双引擎搜索
./scripts/dual-search.sh --query "FastAPI vs Flask 2026 comparison"
```

**Step 5: 将 Skill 注册到 OpenClaw**

```bash
# 将 SKILL.md 链接或复制到 OpenClaw 的 skills 目录
ln -s ~/UltimateSearchSkill/SKILL.md ~/.openclaw/skills/ultimate-search/SKILL.md

# 将脚本目录加入 PATH
echo 'export PATH="$HOME/UltimateSearchSkill/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Step 6: 端到端测试**

在 OpenClaw 中发送消息，验证 agent 能够：
1. 识别需要搜索的请求
2. 选择合适的搜索工具
3. 返回有信源引用的回答

---

## 执行顺序总结

| 阶段 | Task | 说明 | 依赖 |
|------|------|------|------|
| 基础 | Task 1 | 项目初始化 | - |
| 基础 | Task 2 | Docker Compose | Task 1 |
| 基础 | Task 3 | 安装脚本 | Task 2 |
| 核心 | Task 4-8 | 5 个搜索脚本 | Task 1 |
| 核心 | Task 9 | SKILL.md | Task 4-8 |
| 文档 | Task 10-11 | README + 架构文档 | Task 9 |
| 验证 | Task 12 | 集成测试 | All |

**并行可能性：**
- Task 4-8（5 个脚本）可并行开发
- Task 10-11（文档）可并行编写
