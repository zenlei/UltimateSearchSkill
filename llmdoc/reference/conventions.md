# 约定

## 凭证命名

- `TAVILY_MASTER_KEY`：TavilyProxyManager 的单个访问令牌，供 `tavily-search.sh`、`web-map.sh`、`web-fetch.sh` 使用。
- `TAVILY_API_KEYS`：多个上游 Tavily key，供 `import-keys.sh` 导入代理。

## 敏感信息排除

- `.env`、`.env.bak`、`data/`、`export_sso.txt` 必须保持在 `.gitignore` 中。
- `import-keys.sh` 在写入 `.env` 时会生成临时备份 `.env.bak`，脚本结束后会删除，但仓库仍需忽略该文件以防中断残留。
