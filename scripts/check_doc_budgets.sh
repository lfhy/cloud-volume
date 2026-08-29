#!/bin/sh
# 文档字数预算门禁(规范见 docs/DOC_STANDARDS.md)。
# 清单:每个 glob 一个字符上限(wc -m);glob 至少匹配一个文件,否则清单失配。
# 超限处理顺序:搬走 → 压缩 → 提上限(需在提交说明里给理由)。
set -eu
cd "$(dirname "$0")/.."

FAIL=0

check_glob() {
    pattern=$1
    limit=$2
    matched=0
    for f in $pattern; do
        [ -f "$f" ] || continue
        matched=1
        size=$(wc -m < "$f" | tr -d ' ')
        if [ "$size" -gt "$limit" ]; then
            echo "DOC BUDGET FAIL: $f is $size chars (limit $limit)"
            FAIL=1
        fi
    done
    if [ "$matched" -eq 0 ]; then
        echo "DOC BUDGET FAIL: manifest entry '$pattern' matched no files"
        FAIL=1
    fi
}

check_glob 'AGENTS.md' 14000
check_glob 'docs/AGENT_GUIDE.md' 8000
check_glob 'docs/DOC_STANDARDS.md' 14000
check_glob 'docs/DEVELOPMENT_GUIDE.md' 16000
check_glob 'docs/CODE_MAP.md' 30000
check_glob 'docs/README.md' 6000
check_glob 'docs/features/*.md' 60000

if [ "$FAIL" -ne 0 ]; then
    echo "make check-docs 失败:见上方超限条目;处理顺序与规范见 docs/DOC_STANDARDS.md。"
    exit 1
fi
echo "doc budgets ok"
