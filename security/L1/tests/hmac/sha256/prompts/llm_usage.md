# 大模型辅助使用记录

## 基本信息

- **模型名称**：
  - **OpenAI 系列**：GPT-5
  - **Anthropic 系列**：Claude Sonnet 4.5

- **提供方 / 访问方式**：
  - Cursor IDE (cursor.sh) - Claude Sonnet 4.5、GPT-5
  - Augment (vscode-extension) - Claude Sonnet 4.5、GPT-5
- **使用日期**：2025-10-21 至 2025-10-28
- **项目名称**：SHA-256 HMAC L1 算子 HLS 性能优化

---

## 使用场景 1：关键路径分析与架构重构

### 主要用途
定位 SHA-256 消息调度模块的时序瓶颈，重构数据访问模式消除多路选择器与动态索引开销。

### 完整 Prompt 内容
```
我在 Vivado 实现报告中看到关键路径位于 generateMsgSchedule 的 W 计算逻辑，
涉及 wr_idx 寄存器、16:1 MUX、XOR/SHIFT 逻辑和 7 级 CARRY4 加法器，
路由延迟占数据路径延迟的 69%（8.04ns / 11.66ns）。

请在 sha224_256.hpp 中将 generateMsgSchedule 的 W[16] 动态索引访问模式
改为固定索引的移位寄存器结构，消除多路选择器，同时保持 II=1 流水。
```

### 模型输出摘要
AI 提供了详细的重构方案：
1. 将 `W[16]` 循环缓冲区（用 `ap_uint<4>` 动态索引）改为每周期显式移位的结构
2. 使用 `for(i=0; i<15; i++) { W[i] = W[i+1]; }` 配合 `#pragma HLS UNROLL`
3. 固定访问 `W[14]`, `W[9]`, `W[1]`, `W[0]` 计算新值写入 `W[15]`
4. 保持 `#pragma HLS DEPENDENCE variable=W inter false`

### 人工审核与采纳情况
- ✅ 完全采纳并实现了 16 级移位寄存器方案
- ✅ 通过 C Simulation 和 Co-simulation 验证功能正确性
- ✅ EstimatedClockPeriod 保持稳定（未恶化），为后续优化创造条件
- ✅ 消除了 RTL 中的 16:1 多路选择器，降低组合路径复杂度

---

## 使用场景 2：循环控制开销优化

### 主要用途
通过添加 `rewind` pragma 降低流水线循环的控制逻辑开销，改善 HLS 时序估计。

### 完整 Prompt 内容
```
在保持 II=1 的前提下，对 sha256Digest 的 64 轮更新循环、generateMsgSchedule 的 WT64 扩展循环
以及 preProcessing 中的多个按字节/按字读流循环，添加 #pragma HLS pipeline II=1 rewind，
以优化循环控制逻辑，减少回绕开销。验证对 EstimatedClockPeriod 和 Cosim Latency 的影响。
```

### 模型输出摘要
AI 建议在以下循环中添加 `rewind` pragma：
1. `sha256Digest` → `LOOP_SHA256_UPDATE_64_ROUNDS` (64 轮主循环)
2. `generateMsgSchedule` → `LOOP_SHA256_PREPARE_WT16` 和 `LOOP_SHA256_PREPARE_WT64`
3. `preProcessing` → `LOOP_SHA256_GEN_ONE_FULL_BLK`, `LOOP_SHA256_GEN_COPY_TAIL_AND_ONE` 等
4. `dup_strm` → `VITIS_LOOP_504_1`

并强调：
- `rewind` 不改变 II，只优化循环控制电路
- 需要逐一验证避免功能回归

### 人工审核与采纳情况
- ✅ 采纳并应用到所有建议的循环位置
- ✅ 分批验证：sha256Digest 的 rewind 使 EstimatedClockPeriod 从 11.796ns 降至 10.546ns（**核心突破**）
- ✅ preProcessing 与 dup_strm 的 rewind 使 Cosim Latency 从 778 降至 610 cycles（**核心突破**）
- ✅ 所有修改通过 csim/cosim 验证，功能正确

---

## 使用场景 3：表达式树平衡与实现绑定

### 主要用途
通过重组加法树关联、XOR 分组和明确绑定实现类型，优化关键路径的组合逻辑深度。

### 完整 Prompt 内容
```
在 sha256_iter_val 函数中：
1) 将 SSIG0/SSIG1 的三路 XOR 改为两级 pairwise XOR（先算 r6^r25，再 ^r11）以平衡 LUT 树；
2) 将 T1 加法树从 ((h+Wt) + (Kt+ch)) + s1 调整为 (h+Wt) + ((Kt+ch)+s1) 以重新平衡进位链；
3) 对所有关键加法器显式添加 #pragma HLS bind_op variable=XX op=add impl=fabric，
   避免 HLS 自动映射到 DSP 导致时序估计恶化。
验证 EstimatedClockPeriod 是否能从 10.546ns 降至 10.3ns 左右。
```

### 模型输出摘要
AI 提供了多种表达式重组方案：
1. BSIG/SSIG 的 XOR 从左结合 `(a^b)^c` 改为 pairwise `x=a^c; s=x^b`
2. T1 加法树的不同关联顺序：`(h+Wt+s1) + (Kt+ch)` vs `(h+Wt) + ((Kt+ch)+s1)`
3. CH/MAJ 布尔逻辑的两种等价形式（深度优化 vs 直接展开）
4. 对所有加法器绑定 `impl=fabric`，并尝试过 `impl=dsp` 对比

### 人工审核与采纳情况
- ✅ 采纳了 pairwise XOR 分组方案
- ✅ 采纳了 `bind_op impl=fabric` 绑定（保持 EstimatedClockPeriod 稳定）
- ❌ `impl=dsp` 绑定导致 EstimatedClockPeriod 恶化至 13.267ns → 已回退
- ⚠️ 多种加法树关联实验后，EstimatedClockPeriod 稳定在 10.546ns，未能进一步突破至 10.3ns
- ✅ 所有变体均通过功能验证，选择了最优且稳定的组合

---

## 使用场景 4：FIFO 深度与存储类型调优

### 主要用途
优化 dataflow 进程间的 FIFO 缓冲深度和存储资源类型，减少同步开销和阻塞。

### 完整 Prompt 内容
```
在 sha256_top 函数中，w_strm 当前深度为 128，使用 FIFO_BRAM。
请分析是否需要调整深度（尝试 96/160）和存储类型（BRAM vs LUTRAM）
以优化 generateMsgSchedule 与 sha256Digest 之间的数据流，
目标是在不增加 Cosim Latency 的前提下降低 EstimatedClockPeriod。
同时检查 blk_strm 和 nblk_strm 的深度配置是否合理。
```

### 模型输出摘要
AI 建议了多组 FIFO 配置实验：
1. `w_strm` 深度：96/128/160，资源类型：BRAM/LUTRAM
2. `blk_strm` 深度：128（BRAM）保持
3. `nblk_strm` 深度：64（LUTRAM）保持
4. 建议逐一测试并对比 EstimatedClockPeriod 和 Cosim Latency

### 人工审核与采纳情况
- ✅ 实验验证：`w_strm` 深度 96/128/160 对 EstimatedClockPeriod 无显著影响
- ✅ 最终采纳深度 160 + FIFO_LUTRAM（资源充裕，保持最大缓冲裕量）
- ✅ Cosim Latency 保持在 610 cycles，无退化
- ✅ BRAM 使用率 ~23%，LUTRAM 充足，配置合理

---

## 使用场景 5：Vivado 实现报告分析与反向优化指导

### 主要用途
分析 Vivado 布局布线后的实际关键路径和资源利用，反向指导 HLS 代码优化。

### 完整 Prompt 内容
```
请分析 Vivado 实现报告（impl/verilog/report/test_hmac_sha256_timing_routed.rpt）中的：
1) WNS (Worst Negative Slack) 和关键路径详情；
2) 资源利用率报告（utilization_routed.rpt）中的 LUT/FF/BRAM/DSP 使用情况；
3) 对比 HLS EstimatedClockPeriod 与实际 routed 时序的差异。

基于这些信息，建议是否可以进一步收紧目标时钟或调整 HLS pragma。
```

### 模型输出摘要
AI 分析了实现报告并给出建议：
1. 关键路径仍在 `generateMsgSchedule` 的 W 计算逻辑（已在场景1优化）
2. 资源利用充裕（LUT 16.8%, FF 11.6%, BRAM 23.2%），无资源瓶颈
3. WNS = +1.191ns（13.2ns 目标下），实际 routed 时序优于 HLS 估计
4. 建议可尝试收紧目标时钟至 13.0ns 甚至 12.0ns 以触发更激进优化

### 人工审核与采纳情况
- ✅ 采纳了收紧时钟的建议，验证了 13.0ns 和 12.0ns 目标
- ✅ 确认 EstimatedClockPeriod 10.546ns 在 12.0ns 目标下满足时序（Slack > 0）
- ✅ 实现验证通过，资源无超标
- ⚠️ 评分仅看 HLS 估计值，routed 结果仅作参考

---

## 总结

### 整体贡献度评估
- **大模型在本项目中的总体贡献占比**：约 60%
  - 代码架构重构建议与实现：35%（移位寄存器方案、rewind pragma 应用）
  - 时序分析与调试方向：15%（关键路径定位、表达式树平衡）
  - 实验设计与验证策略：10%（分批测试、负优化快速回退）
- **主要帮助领域**：
  - HLS 高级优化技术（dataflow, rewind, bind_op, array_partition）
  - Vivado 实现报告解读与反向优化指导
  - 表达式重组与硬件映射策略
- **人工介入与修正比例**：约 40%
  - 实时监控每次优化的指标变化
  - 快速识别并回退负优化（DSP 绑定、INLINE off）
  - 理解算法固有约束（HMAC 两次 SHA-256 串行）
  - 确认所有修改符合竞赛规则（仅修改 .hpp 文件）

### 最终优化结果
- **EstimatedClockPeriod**: 10.546 ns
- **Cosim Latency**: 610 cycles
- **T_exec**: 6.43 µs
- **资源利用**：LUT 16.8%, FF 11.6%, BRAM 23.2%, DSP 0%
- **合规性**：无打表/预计算，对任意 key 和消息逐拍计算，仅使用标准 K[64] 常量表

### 学习收获
1. **移位寄存器 vs 循环缓冲区**：在 FPGA 中固定索引移位结构优于动态索引，可消除多路选择器开销
2. **rewind pragma 的威力**：在不改变 II 的前提下，显著降低循环控制开销（Estimated -10%, Latency -21%）
3. **DSP vs Fabric 加法器权衡**：对于 32-bit 加法，CARRY4 链通常快于 DSP48E1 的 P 输出路径
4. **HLS 估计 vs 实际布线**：HLS 保守估计可能比实际 routed 延迟高 10-15%，但评分以 HLS 为准
5. **表达式树平衡的局限性**：在已高度优化的流水线中，微调加法/XOR 关联对时序改善有限
6. **负优化快速识别**：
   - DSP 绑定 T1 加法器导致 EstimatedClockPeriod 恶化至 13.267ns（回退至 fabric）
   - `INLINE off` 导致 Cosim Latency 从 610 回升至 798 cycles（回退至 inline）
   - 2x 超标量架构虽降低 Latency 至 486，但 EstimatedClockPeriod 恶化至 29.6ns（放弃方案）

