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
TAVILY_MASTER_KEY="${TAVILY_MASTER_KEY:-}"

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

Tavily 结构化搜索 — 使用 Tavily Search API 进行结构化网络搜索

选项:
  --query "查询内容"           必需，搜索查询内容
  --depth basic|advanced       可选，搜索深度（默认: basic）
  --max-results N              可选，最大结果数（默认: 5）
  --topic general|news|finance 可选，搜索主题（默认: general）
  --time-range day|week|month|year  可选，时间范围过滤
  --include-answer             可选，在结果中包含 AI 生成的答案
  --include-raw                可选，包含原始内容
  --help                       显示此帮助信息

示例:
  $(basename "$0") --query "Python web frameworks comparison"
  $(basename "$0") --query "AI news" --topic news --time-range week --include-answer
  $(basename "$0") --query "stock market" --depth advanced --max-results 10
EOF
  exit 0
}

error_exit() {
  echo "{\"error\": \"$1\"}"
  exit 1
}

QUERY=""
DEPTH="basic"
MAX_RESULTS=5
TOPIC="general"
TIME_RANGE=""
INCLUDE_ANSWER=false
INCLUDE_RAW=false

if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      QUERY="$2"
      shift 2
      ;;
    --depth)
      DEPTH="$2"
      shift 2
      ;;
    --max-results)
      MAX_RESULTS="$2"
      shift 2
      ;;
    --topic)
      TOPIC="$2"
      shift 2
      ;;
    --time-range)
      TIME_RANGE="$2"
      shift 2
      ;;
    --include-answer)
      INCLUDE_ANSWER=true
      shift
      ;;
    --include-raw)
      INCLUDE_RAW=true
      shift
      ;;
    --help)
      usage
      ;;
    *)
      error_exit "未知参数: $1"
      ;;
  esac
done

[[ -z "$QUERY" ]] && error_exit "缺少必需参数 --query"
[[ -z "$TAVILY_API_URL" ]] && error_exit "未设置 TAVILY_API_URL"
[[ -z "$TAVILY_MASTER_KEY" ]] && error_exit "未设置 TAVILY_MASTER_KEY"

# 构建请求 JSON
REQUEST_JSON=$(jq -n \
  --arg query "$QUERY" \
  --arg depth "$DEPTH" \
  --argjson max_results "$MAX_RESULTS" \
  --arg topic "$TOPIC" \
  --argjson include_answer "$INCLUDE_ANSWER" \
  --argjson include_raw "$INCLUDE_RAW" \
  '{
    query: $query,
    search_depth: $depth,
    max_results: $max_results,
    topic: $topic,
    include_answer: $include_answer,
    include_raw_content: $include_raw
  }')

# 添加可选的 time_range
if [[ -n "$TIME_RANGE" ]]; then
  REQUEST_JSON=$(echo "$REQUEST_JSON" | jq --arg tr "$TIME_RANGE" '. + {time_range: $tr}')
fi

# 调用 API
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "$TAVILY_API_URL/search" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TAVILY_MASTER_KEY" \
  -d "$REQUEST_JSON")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
  error_exit "API 请求失败 (HTTP $HTTP_CODE): $BODY"
fi

echo "$BODY" | jq '.'
