#!/usr/bin/env bash
# 会话启动时报告协作状态。
#
# SessionStart hook 的 stdout 会被追加到 Agent 的上下文里，所以这里打印的每一条
# Agent 都一定看得到。两个会话都装了这份 hook，因此双方一开口就知道对方在干什么。

PROJ="${CODEBUDDY_PROJECT_DIR:-.}"
cd "$PROJ" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

echo "===== 协作状态（自动检测）====="
echo "当前分支：$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
echo ""

UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)

if [ -n "$UPSTREAM" ]; then
  git fetch --quiet origin 2>/dev/null
  BEHIND=$(git rev-list --count "HEAD..$UPSTREAM" 2>/dev/null || echo 0)
  AHEAD=$(git rev-list --count "$UPSTREAM..HEAD" 2>/dev/null || echo 0)

  if [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null; then
    echo "注意：远端有 $BEHIND 个新提交，动手前先 git pull 或 git merge。"
    git log --oneline "HEAD..$UPSTREAM" 2>/dev/null | head -10
    echo ""
    echo "对方改动过的文件："
    git diff --stat "HEAD..$UPSTREAM" 2>/dev/null | tail -25
  else
    echo "远端没有新提交，本地是最新的。"
  fi

  if [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "注意：本地有 $AHEAD 个提交还没推，收工前记得 git push。"
    git log --oneline "$UPSTREAM..HEAD" 2>/dev/null | head -10
  fi
else
  echo "当前分支没有设置上游，远端比较跳过。"
fi

echo ""
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "${DIRTY:-0}" -gt 0 ] 2>/dev/null; then
  echo "工作区有 $DIRTY 处未提交改动："
  git status --short 2>/dev/null | head -15
else
  echo "工作区干净。"
fi

echo ""
echo "===== 谁正在改什么（docs/进行中.md）====="
if [ -f docs/进行中.md ]; then
  ROWS=$(grep '^|' docs/进行中.md 2>/dev/null | grep -v '^| *谁 ' | grep -v '^| *---')
  if [ -n "$ROWS" ]; then
    echo "$ROWS"
  else
    echo "（没有人在改）"
  fi
else
  echo "（文件不存在）"
fi

echo ""
echo "===== 动手之前的三件事 ====="
echo "1. git pull，确认已同步到远端最新"
echo "2. 读 docs/进行中.md。要改的文件如果在别人的行里，先问用户"
echo "3. 读 docs/开发纪要.md 第零节 与 docs/工程约定.md 第五节"

exit 0
