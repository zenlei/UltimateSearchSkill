#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载 .env（如果环境变量未设置）
if [[ -f "$SCRIPT_DIR/../.env" ]]; then
  while IFS='=' read -r key value; do
    key="$(echo "$key" | xargs)"
    [[ -z "$key" || "$key" == \#* ]] && continue
    value="$(echo "$value" | xargs | sed -e "s/^['\"]//;s/['\"]$//")"
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$SCRIPT_DIR/../.env"
fi

TAVILY_API_URL="${TAVILY_API_URL:-}"
TAVILY_API_KEY="${TAVILY_API_KEY:-}"

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

站点结构映射 — 使用 Tavily Map API 发现网站 URL 结构

选项:
  --url "URL"              必需，目标站点 URL
  --depth N                可选，爬取深度，范围 1-5（默认: 1）
  --breadth N              可选，每层爬取宽度（默认: 20）
  --limit N                可选，最大 URL 数量（默认: 50）
  --instructions "说明"    可选，爬取指令说明
  --help                   显示此帮助信息

示例:
  $(basename "$0") --url "https://example.com"
  $(basename "$0") --url "https://docs.example.com" --depth 2 --limit 100
  $(basename "$0") --url "https://example.com" --instructions "只抓取文档页面"
EOF
  exit 0
}

error_exit() {
  echo "{\"error\": \"$1\"}"
  exit 1
}

URL=""
DEPTH=1
BREADTH=20
LIMIT=50
INSTRUCTIONS=""

if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="$2"
      shift 2
      ;;
    --depth)
      DEPTH="$2"
      shift 2
      ;;
    --breadth)
      BREADTH="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --instructions)
      INSTRUCTIONS="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      error_exit "未知参数: $1"
      ;;
  esac
done

[[ -z "$URL" ]] && error_exit "缺少必需参数 --url"
[[ -z "$TAVILY_API_URL" ]] && error_exit "未设置 TAVILY_API_URL"
[[ -z "$TAVILY_API_KEY" ]] && error_exit "未设置 TAVILY_API_KEY"

# 验证 depth 范围
if [[ "$DEPTH" -lt 1 || "$DEPTH" -gt 5 ]]; then
  error_exit "--depth 必须在 1-5 范围内"
fi

# 构建请求 JSON
REQUEST_JSON=$(jq -n \
  --arg url "$URL" \
  --argjson depth "$DEPTH" \
  --argjson breadth "$BREADTH" \
  --argjson limit "$LIMIT" \
  '{
    url: $url,
    depth: $depth,
    breadth: $breadth,
    limit: $limit
  }')

# 添加可选的 instructions
if [[ -n "$INSTRUCTIONS" ]]; then
  REQUEST_JSON=$(echo "$REQUEST_JSON" | jq --arg inst "$INSTRUCTIONS" '. + {instructions: $inst}')
fi

# 调用 API
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "$TAVILY_API_URL/map" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TAVILY_API_KEY" \
  -d "$REQUEST_JSON")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
  error_exit "API 请求失败 (HTTP $HTTP_CODE): $BODY"
fi

echo "$BODY" | jq '.'
