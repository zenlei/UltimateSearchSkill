# UltimateSearchSkill

为 [OpenClaw](https://openclaw.ai/) / [Pi](https://github.com/badlogic/pi-mono/) agent 打造的双引擎网络搜索 Skill。

```
用户提问 → Agent (SKILL.md 指导)
                ├─ grok-search.sh  → grok2api (多Token聚合) → Grok 联网搜索
                ├─ tavily-search.sh → TavilyProxyManager (多Key聚合) → Tavily 搜索
                ├─ web-fetch.sh    → TavilyProxyManager → Tavily Extract (网页抓取)
                ├─ web-map.sh      → TavilyProxyManager → Tavily Map (站点映射)
                └─ dual-search.sh  → 并行调用以上，交叉验证
```

## 特性

- **双引擎搜索**：Grok（AI 联网搜索）+ Tavily（结构化搜索），互补协作
- **多账户聚合**：通过 grok2api 和 TavilyProxyManager 聚合多个账号，自动负载均衡
- **零 MCP 依赖**：纯 Shell 脚本 + Skill 指令，agent 通过 Bash 原生调用，无需 MCP/mcporter
- **安全加固**：端口绑定 127.0.0.1，API 认证，SSH 隧道访问管理面板
- **搜索方法论**：内置 GrokSearch MCP 的搜索规划框架和证据标准

## 快速开始

### 前置条件

- Docker + Docker Compose
- curl、jq
- Grok 账号 Token（至少 1 个）
- Tavily API Key（免费 1000 次/月，注册：https://www.tavily.com/）

### 安装

```bash
git clone https://github.com/你的用户名/UltimateSearchSkill.git
cd UltimateSearchSkill

# 一键部署
./scripts/setup.sh
```

### 配置

1. **编辑 .env**：修改密码和 API Key
2. **添加 Grok Token**：通过 SSH 隧道访问 grok2api 管理面板
   ```bash
   ssh -L 8100:127.0.0.1:8100 你的服务器
   # 浏览器打开 http://localhost:8100/admin
   ```
3. **添加 Tavily Key**：通过 SSH 隧道访问 TavilyProxyManager
   ```bash
   ssh -L 8200:127.0.0.1:8200 你的服务器
   # 浏览器打开 http://localhost:8200
   ```

### 使用

```bash
# 加载环境变量
source .env

# Grok AI 搜索
grok-search.sh --query "FastAPI 最新特性"

# Tavily 搜索
tavily-search.sh --query "Python web frameworks comparison" --depth advanced

# 双引擎搜索
dual-search.sh --query "Rust vs Go 2026"

# 抓取网页内容
web-fetch.sh --url "https://docs.python.org/3/whatsnew/3.13.html"

# 站点映射
web-map.sh --url "https://docs.tavily.com" --depth 2
```

### 注册为 Skill

```bash
# 在 OpenClaw/Pi 中注册
ln -s $(pwd)/SKILL.md ~/.openclaw/skills/ultimate-search/SKILL.md

# 将脚本加入 PATH
echo "export PATH=\"$(pwd)/scripts:\$PATH\"" >> ~/.bashrc
source ~/.bashrc
```

## 架构说明

详见 [docs/architecture.md](docs/architecture.md)。

## 安全说明

- 所有端口绑定到 `127.0.0.1`，外部无法直接访问
- grok2api 必须配置 API Key（默认无认证）
- TavilyProxyManager 使用随机生成的 Master Key
- 远程管理通过 SSH 隧道访问
- 详见 [安全加固指南](docs/architecture.md#安全加固)

## 致谢

- [GrokSearch MCP](https://github.com/GuDaStudio/GrokSearch) — 搜索方法论和提示词的灵感来源
- [grok2api](https://github.com/chenyme/grok2api) — Grok Token 聚合服务
- [TavilyProxyManager](https://github.com/xuncv/TavilyProxyManager) — Tavily Key 聚合服务

## License

MIT
