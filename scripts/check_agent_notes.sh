#!/bin/sh
# Agent Note 格式门禁(规范见 docs/notes/README.md)。
# 校验:路径 {lifecycle}/{class}/yyyy-mm-dd-slug.md、header 块(# Agent Note: / Status:)、
# Status 与目录一致、各 lifecycle 的必需/禁止小节;拒绝 .zh.md / i18n sidecar(仅中文单语)。
set -eu
cd "$(dirname "$0")/.."

FAIL=0
CLASSES="feature bug-fix simplification architecture process testing"

bad() {
    echo "AGENT NOTE FAIL: $1"
    FAIL=1
}

has_section() {
    grep -q "^## $2"'$' "$1"
}

[ -f docs/notes/README.md ] || bad "docs/notes/README.md missing"
[ -d docs/notes ] || { echo "AGENT NOTE FAIL: docs/notes/ 不存在"; exit 1; }

for f in $(find docs/notes -type f | sort); do
    rel=${f#docs/notes/}

    # 单语策略:目录树里只允许 markdown 笔记 + 本 README。
    case "$rel" in
        README.md) continue ;;
        *.zh.md|*.i18n.yaml|*.png|*.json)
            bad "$f: 单语策略——不允许双语副本或 sidecar"
            continue ;;
    esac

    lifecycle=${rel%%/*}
    rest=${rel#*/}
    class=${rest%%/*}
    name=${rest#*/}
    case "$lifecycle" in
        proposed|implemented|rejected) ;;
        *) bad "$f: 顶层目录必须是 proposed/implemented/rejected,实际 '$lifecycle'"; continue ;;
    esac
    class_ok=0
    for c in $CLASSES; do
        if [ "$class" = "$c" ]; then class_ok=1; fi
    done
    if [ "$class_ok" -ne 1 ]; then
        bad "$f: class '$class' 不在封闭集合($CLASSES)"
        continue
    fi
    case "$name" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
        *) bad "$f: 文件名须为 yyyy-mm-dd-主题.md"; continue ;;
    esac

    # header 块:第 1 行标题、第 3 行 Status。
    head1=$(awk 'NR==1' "$f")
    head3=$(awk 'NR==3' "$f")
    case "$head1" in
        "# Agent Note: "*) ;;
        *) bad "$f: 第 1 行必须是 '# Agent Note: <标题>'" ;;
    esac
    case "$head3" in
        "Status: proposed"|\
        "Status: implemented") ;;
        "Status: rejected —"*|"Status: rejected -"*) ;;
        *) bad "$f: 第 3 行 Status 必须是 proposed / implemented / rejected — <理由>"; continue ;;
    esac
    case "$head3" in
        "Status: $lifecycle"*) ;;
        *) bad "$f: Status('$head3')与目录 '$lifecycle' 不一致" ;;
    esac

    # 各 lifecycle 的小节骨架;正文第一个二级标题必须是 Problem。
    first_h2=$(awk '/^## /{print; exit}' "$f")
    if [ "$first_h2" != "## Problem" ]; then
        bad "$f: 正文第一个二级标题必须是 '## Problem',实际 '${first_h2:-<无>}'"
    fi
    if ! has_section "$f" "Problem"; then
        bad "$f: 缺少 '## Problem'"
    fi
    if ! has_section "$f" "Alternatives considered"; then
        bad "$f: 缺少 '## Alternatives considered'(强制)"
    fi
    case "$lifecycle" in
        implemented)
            has_section "$f" "Decision" || bad "$f: implemented 缺少 '## Decision'"
            has_section "$f" "Consequences" || bad "$f: implemented 缺少 '## Consequences'"
            for forbidden in "Proposal" "Plan" "Migration plan" "Acceptance criteria"; do
                if has_section "$f" "$forbidden"; then
                    bad "$f: implemented 不允许提案式小节 '## $forbidden'(写现状,不写计划)"
                fi
            done
            ;;
        proposed)
            has_section "$f" "Proposal" || bad "$f: proposed 缺少 '## Proposal'"
            has_section "$f" "Acceptance criteria" || bad "$f: proposed 缺少 '## Acceptance criteria'"
            has_section "$f" "Risks" || bad "$f: proposed 缺少 '## Risks'"
            ;;
        rejected)
            has_section "$f" "Proposal" || bad "$f: rejected 缺少 '## Proposal'"
            ;;
    esac
done

if [ "$FAIL" -ne 0 ]; then
    echo "make check-docs 失败:Agent Note 格式问题见上;规范见 docs/notes/README.md。"
    exit 1
fi
echo "agent notes ok"
