#!/usr/bin/env bash
# 每周一由 cron 调用：五路联网调研 -> 写 reports/ -> commit -> SSH push
# 手动测试： bash run_weekly.sh
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

# 本地代理（国内访问 Anthropic 必需）——cron 冷启动不继承交互态的代理变量，必须显式设置
export http_proxy="http://127.0.0.1:7897"
export https_proxy="http://127.0.0.1:7897"
export all_proxy="socks5h://127.0.0.1:7897"

# git 也走 SOCKS 代理隧道：国内 github SSH 直连 22/443 端口间歇性被封，隧道走代理最稳
# （clone/api 一直走代理成功）。指定 github 专用 key。
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -i /home/xp/.ssh/id_ed25519_github_xpzwzwz -o IdentitiesOnly=yes -o ProxyCommand='nc -X 5 -x 127.0.0.1:7897 %h %p'"

REPO="/home/xp/playground/docs/weekly-report"
cd "$REPO" || exit 1
DATE="$(date +%F)"
OUT="reports/${DATE}-weekly.md"
LOG="$REPO/run.log"
MODEL="claude-sonnet-4-6"

echo "===== $(date '+%F %T') START =====" >> "$LOG"

# 先同步远端（避免落后被拒；走上面配置的代理隧道 GIT_SSH_COMMAND）
git pull --rebase --quiet origin main >> "$LOG" 2>&1 || true

read -r -d '' PROMPT <<'EOF'
你是「具身智能 + 大模型」五路进展周报的调研 agent。调研过去 7 天（重点最新）的进展，产出一份可快速扫完的 markdown 周报。

铁律（五路通用）：
- 联网搜索 + 逐条点开一手源核实（arXiv abs 页 / 官方 blog / GitHub / 权威媒体），确认标题+日期真实存在再写。
- 每条标日期；公司/论文自报数字标【自报】；传闻/未核实/仅二手博客单列「⚠️传闻」。
- 绝不编造 arXiv 编号、模型名或公司发布。arXiv 形如 YYMM.xxxxx，排除未来日期的伪造编号。
- 无实质新进展的路/项，如实说「本周无可核实新动态」，别拿旧的或重复的凑。
- 覆盖通用大模型（不限具身/多模态域）。每路最多列 5–6 条最值得的已核实要点，保持精简。

强制检索方法（不能只靠普通网页搜索）：
1. 先确定明确的起止日期，并按五路分别建立候选池。arXiv 必须按 submittedDate 查询整个时间窗口的 v1 首次提交，不能用搜索引擎是否已收录来判断“本周无动态”。
2. 每路使用宽关键词组合扫候选：VLA 同时覆盖 world model/teleoperation/tactile/retargeting/dataset/benchmark；多模态覆盖 VLM/video/OCR/visual encoder/agent；推理覆盖 release/scheduling/KV cache/P-D/kernel/serving/edge；压缩覆盖 quantization/pruning/distillation/sparsity/low-rank/KV quantization；训练覆盖 post-training/RL/rollout/optimizer/data mixture/scaling/MoE/distributed training/memory/communication。
3. 再扫官方发布面：头部实验室与机器人公司官方 blog/模型卡，及 vLLM、SGLang、TensorRT-LLM、DeepSpeed、Megatron、FSDP/torchtitan、verl 等 GitHub Releases。普通搜索结果只用于发现线索。
4. 对候选逐条打开一手源：论文核对 arXiv abs 页的标题、编号、v1 日期和摘要；软件核对 GitHub Release/tag 日期与正文；模型核对官方模型卡/博客；公司动态核对官方新闻稿。未打开一手源的候选不得写入“已核实”。
5. “头部公司本周没发模型”不等于该路无动态。只有完成 arXiv 全窗口扫描、官方发布扫描和 GitHub Release 扫描后，才允许写“本周无可核实新动态”。
6. 日期按正式公开日期判定；预创建但尚未正式发布的仓库不算发布。窗口外发布不得因仓库创建时间落在窗口内而提前收录，可在边界说明中注明并归下一期。
7. 最后做交叉检查：确认五路不重复、每个链接可打开、所有数字均标【自报】、arXiv 编号年月与日期一致，并从候选池中仅保留每路最值得的 5–6 条。

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
  echo "「具身智能 + 大模型」五路进展周报存档 —— 本地 cron 每周一自动生成 + push。"
  echo
  echo "- ①VLA/遥操作/具身 · ②多模态大模型 · ③部署/推理 infra · ④轻量化/压缩 · ⑤训练进展"
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
  pushed=""
  for i in 1 2 3; do
    if git push --quiet origin main >> "$LOG" 2>&1; then pushed=1; break; fi
    echo "!! push 第 $i 次失败，20s 后重试…" >> "$LOG"; sleep 20
  done
  if [ -n "$pushed" ]; then
    echo "===== $(date '+%F %T') DONE pushed $OUT =====" >> "$LOG"
  else
    echo "!! push 三次均失败（已本地 commit；下次运行 pull+push 会自动补推积压的提交）" >> "$LOG"
  fi
else
  echo "!! 无变更可提交" >> "$LOG"
fi
