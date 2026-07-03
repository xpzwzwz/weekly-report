#!/usr/bin/env bash
# 每周一由 cron 调用：三路联网调研 -> 写 reports/ -> commit -> SSH push
# 手动测试： bash run_weekly.sh
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

REPO="/home/xp/playground/docs/weekly-report"
cd "$REPO" || exit 1
DATE="$(date +%F)"
OUT="reports/${DATE}-weekly.md"
LOG="$REPO/run.log"
MODEL="claude-sonnet-4-6"

echo "===== $(date '+%F %T') START =====" >> "$LOG"

# 先同步远端（避免落后被拒）
GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git pull --rebase --quiet origin main >> "$LOG" 2>&1 || true

read -r -d '' PROMPT <<'EOF'
你是「具身智能 + 大模型」三路进展周报的调研 agent。调研过去 7 天（重点最新）的进展，产出一份可快速扫完的 markdown 周报。

铁律（三路通用）：
- 联网搜索 + 逐条点开一手源核实（arXiv abs 页 / 官方 blog / GitHub / 权威媒体），确认标题+日期真实存在再写。
- 每条标日期；公司/论文自报数字标【自报】；传闻/未核实/仅二手博客单列「⚠️传闻」。
- 绝不编造 arXiv 编号、模型名或公司发布。arXiv 形如 YYMM.xxxxx，排除未来日期的伪造编号。
- 无实质新进展的路/项，如实说「本周无可核实新动态」，别拿旧的或重复的凑。

三路：
第一路 — VLA / 遥操作 / 具身数据：新 VLA/操作策略模型（π/GR00T/Gemini Robotics/OpenVLA 系及开源新品）、世界模型造数、遥操作系统与灵巧手 retarget/力·触觉、新开源机器人数据集与真机 eval benchmark、大厂动态（PI/Figure/1X/NVIDIA/Tesla/Apptronik/Agility/Skild/智元/宇树/银河通用/千寻等）。
第二路 — 多模态大模型：新多模态/VLM 模型发布（Qwen-VL、Gemini、GPT、Claude、国内多模态等）、多模态架构/训练/评测新工作、视觉编码器/长视频/OCR/多模态 agent。
第三路 — 大模型部署 / 推理 infra：vLLM/SGLang/TensorRT-LLM 等推理框架更新、量化（FP8/NVFP4/GGUF/AWQ）、投机解码、KV cache/PagedAttention、服务化与调度、边缘/Jetson（Thor/Orin）部署、性能优化论文与工程实践。

输出：markdown，开头写本周时间范围，三路分节，每节内「✅ 已核实要点（每条带链接+日期）」与「⚠️ 传闻」两栏，每路末尾「本周最值得关注的 2–3 项」。整体简洁、重「新」和「可核实」。
重要：只输出周报 markdown 正文本身，不要任何额外说明/寒暄，不要用 ``` 代码块包裹整篇，不要写文件或执行 git（这些由外部脚本处理）。
EOF

# 无头联网调研，stdout 即周报正文
timeout 1500 claude -p "$PROMPT" --model "$MODEL" --allowedTools WebSearch WebFetch > "$OUT" 2>> "$LOG"
rc=$?

if [ $rc -ne 0 ] || [ ! -s "$OUT" ]; then
  echo "!! claude 失败 rc=$rc 或输出为空，放弃本次" >> "$LOG"
  rm -f "$OUT"
  exit 1
fi

# 头部加元信息
tmp="$(mktemp)"
{ echo "> 生成时间：$(date '+%F %T %Z')（本地 cron 自动）"; echo; cat "$OUT"; } > "$tmp" && mv "$tmp" "$OUT"

# 重建 README 报告列表
{
  echo "# weekly-report"
  echo
  echo "「具身智能 + 大模型」三路进展周报存档 —— 本地 cron 每周一自动生成 + push。"
  echo
  echo "- 第一路 VLA / 遥操作 / 具身数据 · 第二路 多模态大模型 · 第三路 大模型部署 infra"
  echo
  echo "## 报告列表"
  echo
  for f in $(ls -1 reports/*-weekly.md 2>/dev/null | sort -r); do
    d="$(basename "$f" -weekly.md)"
    echo "- [$d]($f)"
  done
} > README.md

git add -A
if git commit -q -m "weekly report ${DATE}"; then
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git push --quiet origin main >> "$LOG" 2>&1 \
    && echo "===== $(date '+%F %T') DONE pushed $OUT =====" >> "$LOG" \
    || echo "!! push 失败（已本地 commit）" >> "$LOG"
else
  echo "!! 无变更可提交" >> "$LOG"
fi
