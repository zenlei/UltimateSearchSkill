#!/usr/bin/env bash
set -eo pipefail

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
FIRECRAWL_API_URL="${FIRECRAWL_API_URL:-https://api.firecrawl.dev/v2}"
FIRECRAWL_API_KEY="${FIRECRAWL_API_KEY:-}"
# 兼容批量 Key 配置：如果单个 Key 未设置，取 FIRECRAWL_API_KEYS 的第一个
if [[ -z "$FIRECRAWL_API_KEY" && -n "${FIRECRAWL_API_KEYS:-}" ]]; then
  FIRECRAWL_API_KEY=$(echo "$FIRECRAWL_API_KEYS" | cut -d',' -f1 | xargs)
fi

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

网页内容抓取 — 三级降级：Tavily Extract → FireCrawl Scrape → 返回错误

选项:
  --url "URL"                必需，目标网页 URL（可多次指定）
  --depth basic|advanced     可选，提取深度（默认: basic）
  --format markdown|text     可选，输出格式（默认: markdown）
  --help                     显示此帮助信息

示例:
  $(basename "$0") --url "https://example.com"
  $(basename "$0") --url "https://a.com" --url "https://b.com" --depth advanced
  $(basename "$0") --url "https://example.com" --format text
EOF
  exit 0
}

error_exit() {
  echo "{\"error\": \"$1\"}"
  exit 1
}

URLS=()
DEPTH="basic"
FORMAT="markdown"

if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URLS+=("$2")
      shift 2
      ;;
    --depth)
      DEPTH="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
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

[[ ${#URLS[@]} -eq 0 ]] && error_exit "缺少必需参数 --url"

# ==========================================
# Tavily Extract（第一级）
# ==========================================
tavily_extract() {
  local urls_json="$1"
  [[ -z "$TAVILY_API_URL" || -z "$TAVILY_API_KEY" ]] && return 1

  local request_json
  request_json=$(jq -n \
    --argjson urls "$urls_json" \
    --arg depth "$DEPTH" \
    --arg format "$FORMAT" \
    '{
      urls: $urls,
      extract_depth: $depth,
      format: $format
    }')

  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    --connect-timeout 6 --max-time 30 \
    -X POST "$TAVILY_API_URL/extract" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TAVILY_API_KEY" \
    -d "$request_json")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ne 200 ]]; then
    return 1
  fi

  # 检查是否有实际内容
  local has_content
  has_content=$(echo "$body" | jq '[.results[]? | select(.raw_content != null and .raw_content != "")] | length' 2>/dev/null || echo "0")
  if [[ "$has_content" -eq 0 ]]; then
    return 1
  fi

  echo "$body" | jq '{source: "tavily", results: .results}'
  return 0
}

# ==========================================
# FireCrawl Scrape（第二级降级）
# ==========================================
firecrawl_scrape() {
  local urls_json="$1"
  [[ -z "$FIRECRAWL_API_KEY" ]] && return 1

  local api_url="${FIRECRAWL_API_URL%/}"
  local all_results="[]"

  # FireCrawl scrape 是单 URL 接口，需要逐个调用
  local url_count
  url_count=$(echo "$urls_json" | jq 'length')

  for (( i=0; i<url_count; i++ )); do
    local url
    url=$(echo "$urls_json" | jq -r ".[$i]")

    local request_json
    request_json=$(jq -n \
      --arg url "$url" \
      '{
        url: $url,
        formats: ["markdown"]
      }')

    local response http_code body
    response=$(curl -s -w "\n%{http_code}" \
      --connect-timeout 6 --max-time 60 \
      -X POST "$api_url/scrape" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
      -d "$request_json")

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -eq 200 ]]; then
      local content
      content=$(echo "$body" | jq -r '(.data.markdown // .data.content // "") | ltrimstr(" ") | rtrimstr(" ")' 2>/dev/null || echo "")
      if [[ -n "$content" && "$content" != "null" ]]; then
        all_results=$(echo "$all_results" | jq \
          --arg url "$url" \
          --arg content "$content" \
          '. + [{url: $url, raw_content: $content}]')
      fi
    fi
  done

  local result_count
  result_count=$(echo "$all_results" | jq 'length')
  if [[ "$result_count" -eq 0 ]]; then
    return 1
  fi

  jq -n --argjson results "$all_results" '{source: "firecrawl", results: $results}'
  return 0
}

# ==========================================
# 主流程：三级降级
# ==========================================

# 构建 URL 数组 JSON
URLS_JSON=$(printf '%s\n' "${URLS[@]}" | jq -R . | jq -s .)

# 第一级：Tavily Extract
if result=$(tavily_extract "$URLS_JSON" 2>/dev/null); then
  echo "$result" | jq '.'
  exit 0
fi

# 第二级：FireCrawl Scrape
if result=$(firecrawl_scrape "$URLS_JSON" 2>/dev/null); then
  echo "$result" | jq '.'
  exit 0
fi

# 都失败
error_exit "Tavily Extract 和 FireCrawl Scrape 均失败"
