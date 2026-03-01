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

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

双引擎聚合搜索 — 并行调用 Grok AI 搜索和 Tavily 结构化搜索，合并结果

选项:
  --query "查询内容"           必需，搜索查询内容
  --tavily-depth basic|advanced  可选，Tavily 搜索深度（默认: basic）
  --help                       显示此帮助信息

示例:
  $(basename "$0") --query "FastAPI vs Flask comparison"
  $(basename "$0") --query "最新 AI 新闻" --tavily-depth advanced
EOF
  exit 0
}

error_exit() {
  echo "{\"error\": \"$1\"}"
  exit 1
}

QUERY=""
TAVILY_DEPTH="basic"

if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      QUERY="$2"
      shift 2
      ;;
    --tavily-depth)
      TAVILY_DEPTH="$2"
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

[[ -z "$QUERY" ]] && error_exit "缺少必需参数 --query"

# 创建临时文件
GROK_TMP=$(mktemp)
TAVILY_TMP=$(mktemp)

# 确保退出时清理临时文件
cleanup() {
  rm -f "$GROK_TMP" "$TAVILY_TMP"
}
trap cleanup EXIT

# 并行调用两个搜索引擎
"$SCRIPT_DIR/grok-search.sh" --query "$QUERY" > "$GROK_TMP" 2>&1 &
GROK_PID=$!

"$SCRIPT_DIR/tavily-search.sh" --query "$QUERY" --depth "$TAVILY_DEPTH" > "$TAVILY_TMP" 2>&1 &
TAVILY_PID=$!

# 等待两个进程完成
GROK_EXIT=0
TAVILY_EXIT=0
wait "$GROK_PID" || GROK_EXIT=$?
wait "$TAVILY_PID" || TAVILY_EXIT=$?

# 读取结果
GROK_RESULT=$(cat "$GROK_TMP")
TAVILY_RESULT=$(cat "$TAVILY_TMP")

# 验证 JSON 有效性，无效则包装为错误
if ! echo "$GROK_RESULT" | jq empty 2>/dev/null; then
  GROK_RESULT="{\"error\": \"Grok 搜索失败: $(echo "$GROK_RESULT" | head -1 | sed 's/"/\\"/g')\"}"
fi

if ! echo "$TAVILY_RESULT" | jq empty 2>/dev/null; then
  TAVILY_RESULT="{\"error\": \"Tavily 搜索失败: $(echo "$TAVILY_RESULT" | head -1 | sed 's/"/\\"/g')\"}"
fi

# 合并结果
jq -n \
  --argjson grok "$GROK_RESULT" \
  --argjson tavily "$TAVILY_RESULT" \
  '{
    grok: $grok,
    tavily: $tavily
  }'
