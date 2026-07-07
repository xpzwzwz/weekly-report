#!/usr/bin/env bash
# 每周一由 cron 调用：三路联网调研 -> 写 reports/ -> commit -> SSH push
# 手动测试： bash run_weekly.sh
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

# 本地代理（国内访问 Anthropic 必需）——cron 冷启动不继承交互态的代理变量，必须显式设置
export http_proxy="http://127.0.0.1:7897"
export https_proxy="http://127.0.0.1:7897"
export all_proxy="socks5h://127.0.0.1:7897"

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
你是「具身智能 + 大模型」五路进展周报的调研 agent。调研过去 7 天（重点最新）的进展，产出一份可快速扫完的 markdown 周报。

铁律（五路通用）：
- 联网搜索 + 逐条点开一手源核实（arXiv abs 页 / 官方 blog / GitHub / 权威媒体），确认标题+日期真实存在再写。
- 每条标日期；公司/论文自报数字标【自报】；传闻/未核实/仅二手博客单列「⚠️传闻」。
- 绝不编造 arXiv 编号、模型名或公司发布。arXiv 形如 YYMM.xxxxx，排除未来日期的伪造编号。
- 无实质新进展的路/项，如实说「本周无可核实新动态」，别拿旧的或重复的凑。
- 覆盖通用大模型（不限具身/多模态域）。每路最多列 5–6 条最值得的已核实要点，保持精简。

五路（注意边界，别互相重复）：
第一路 — VLA / 遥操作 / 具身数据：新 VLA/操作策略模型（π/GR00T/Gemini Robotics/OpenVLA 系及开源新品）、世界模型造数、遥操作系统与灵巧手 retarget/力·触觉、新开源机器人数据集与真机 eval benchmark、大厂动态（PI/Figure/1X/NVIDIA/Tesla/Apptronik/Agility/Skild/智元/宇树/银河通用/千寻等）。
第二路 — 多模态大模型：新多模态/VLM 模型发布（Qwen-VL、Gemini、GPT、Claude、国内多模态等）、多模态架构/训练/评测新工作、视觉编码器/长视频/OCR/多模态 agent。
第三路 — 部署 / 推理 infra（系统级，不改模型权重）：推理框架更新（vLLM/SGLang/TensorRT-LLM 等）、调度与连续批处理、KV cache/PagedAttention、投机解码、算子/内核、服务化与分布式推理、边缘/Jetson(Thor/Orin)部署。注意：模型压缩/量化归第四路，本路不重复。
第四路 — 轻量化 / 模型压缩（模型级，改模型权重）：量化（FP8/NVFP4/INT4/GGUF/AWQ/GPTQ 等）、剪枝、知识蒸馏、低秩分解、稀疏化（2:4 等）、KV cache 量化、小模型/高效架构。含相关论文与开源实现。
第五路 — 训练进展（怎么训；"又发了个新模型"归第一/二路，本路不重复）：① 训练方法：后训练/RL（RLHF/DPO/GRPO/RLVR 等）、优化器（Muon 等）、长上下文训练、数据合成与配比、scaling law、MoE 训练技巧；② 训练系统：分布式并行（FSDP/Megatron/DeepSpeed/3D 并行）、显存优化（ZeRO/激活重算/offload）、通信优化、训练框架。

输出：markdown，开头写本周时间范围，五路分节，每节内「✅ 已核实要点（每条带链接+日期）」与「⚠️ 传闻」两栏，每路末尾「本周最值得关注的 2–3 项」。整体简洁、重「新」和「可核实」。
重要：只输出周报 markdown 正文本身，不要任何额外说明/寒暄，不要用 ``` 代码块包裹整篇，不要写文件或执行 git（这些由外部脚本处理）。
EOF

# 代理可用性检查（cron 时刻代理若没起，claude 会 403 认证失败）
if ! timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7897' 2>/dev/null; then
  echo "!! 警告：代理 127.0.0.1:7897 不可达，claude 大概率认证失败（检查 Clash/代理是否开机自启）" >> "$LOG"
fi

# 无头联网调研，stdout 即周报正文
timeout 2100 claude -p "$PROMPT" --model "$MODEL" --allowedTools WebSearch WebFetch > "$OUT" 2>> "$LOG"
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
