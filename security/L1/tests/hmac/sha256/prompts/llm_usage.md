# 大模型辅助使用记录

## 基本信息

- **模型名称**：
  - **Anthropic 系列**：Claude 4.5 Sonnet (通过 Augment Agent)
  - **OpenAI 系列**：GPT-5 Pro (通过 Cursor AI)
  - **Anthropic 系列**：Claude 4.1 Opus (API 直接调用)
- **提供方 / 访问方式**：
  - Augment Code (augmentcode.com) - Claude 4.5 Sonnet
  - Cursor IDE (cursor.sh) - GPT-5 Pro
  - Anthropic API - Claude 4.1 Opus
- **使用日期**：2025-10-21 至 2025-10-25
- **项目名称**：SHA-256 HMAC L1 算子优化

---

## 使用场景 1：理解新评分规则并制定优化策略

### 主要用途
理解竞赛组委会更新的评分细则，分析新的执行时间计算公式和时序约束要求。

### 完整 Prompt 内容
```
由于竞赛组委会更新细则 @README.md @命题式基础赛道初赛评分细则.md 
我们需要根据新的要求，重新对HLS进行优化，这是我之前的优化记录，
你可以查看，并且根据最新要求做出适合的修改 @sha256_opt.md
```

### 模型输出摘要
AI 分析了新评分规则的关键变化：
1. 执行时间公式：T_exec = Estimated_Clock_Period × Cosim_Latency
2. 时序约束：Slack = (Target × 0.9) - Estimated_Clock_Period 必须 > 0
3. 违反时序约束将扣除10分
4. 优化目标：在满足时序的前提下最小化 T_exec

建议优化方向：
- 利用 dataflow 架构实现流水线并行
- 优化消息调度和轮函数的关键路径
- 调整 FIFO 深度减少同步开销

### 人工审核与采纳情况
- ✅ 采纳了时序约束分析方法和 T_exec 计算公式
- ✅ 采纳了 dataflow 优化方向
- ✅ 确认了只能修改 `.hpp` 文件的限制
- ⚠️ 对激进优化保持谨慎，需要逐步验证

---

## 使用场景 2：SHA-256 消息调度 2路打包优化

### 主要用途
优化消息调度模块，通过数据打包提高每周期处理的 W 值数量。

### 完整 Prompt 内容
```
在 sha224_256.hpp 内实现消息调度优化，将 W 流从 32-bit 改为 64-bit，
每周期生成 2 个 W 值，同时在 digest 函数中每周期处理 2 轮迭代。
```

### 模型输出摘要
AI 提供了详细的实现方案：
1. 修改 `generateMsgSchedule` 函数：
   - 将 `w_strm` 类型从 `hls::stream<uint32_t>` 改为 `hls::stream<ap_uint<64>>`
   - 循环步长从 `t++` 改为 `t+=2`
   - 每次迭代计算 wt0 和 wt1，打包成 64-bit 输出
   - 添加 `#pragma HLS DEPENDENCE variable=W inter false` 消除依赖

2. 修改 `sha256Digest` 函数：
   - 读取 64-bit 数据并解包成两个 32-bit W 值
   - 每周期调用两次 `sha256_iter_val` 处理 2 轮

### 人工审核与采纳情况
- ✅ 完全采纳并实现了 2路打包方案
- ✅ 通过 C Simulation 和 Co-simulation 验证
- ✅ 功能正确性验证通过
- ⚠️ Latency 保持在 800 cycles（HMAC 算法固有限制）

---

## 使用场景 3：HMAC Dataflow FIFO 深度优化

### 主要用途
优化 HMAC 模块中 dataflow 进程间的 FIFO 深度配置。

### 完整 Prompt 内容
```
HMAC 使用 dataflow 架构，多个 FIFO 深度默认为 4，
能否通过增加 FIFO 深度来减少进程间的阻塞和同步开销？
```

### 模型输出摘要
AI 建议增加关键 FIFO 的深度并指定存储类型：
- `mergeKipadStrm`: 4 → 256 (BRAM)
- `mergeKipadLenStrm`: 4 → 32 (LUTRAM)
- `kipadStrm`, `kopadStrm`: 4 → 32 (BRAM)
- `msgHashStrm`: 4 → 32 (BRAM)

### 人工审核与采纳情况
- ✅ 采纳了 FIFO 深度增加的建议
- ✅ 添加了 `#pragma HLS RESOURCE` 指定 BRAM/LUTRAM
- ✅ 验证无死锁，功能正确
- ⚠️ Latency 未改变（800 cycles 是算法固有的）

---

## 使用场景 4：发现并修复 test.cpp 违规修改

### 主要用途
发现测试文件被错误修改，违反了竞赛规则。

### 完整 Prompt 内容
```
发现 Latency 从 800 降到了 773，但检查后发现 test.cpp 中的 
MSG_SIZE 被从 4 改成了 8，这违反了竞赛规则（只能修改 .hpp 文件）。
需要恢复原始文件。
```

### 模型输出摘要
AI 确认了违规情况并建议：
1. 使用 `git checkout` 恢复 test.cpp
2. 重新运行测试验证
3. 确保所有修改都在允许的 `.hpp` 文件中

### 人工审核与采纳情况
- ✅ 完全采纳，使用 `git checkout` 恢复了 test.cpp
- ✅ 重新运行测试，Latency 恢复到 800 cycles
- ✅ 确认所有优化符合竞赛规则

---

## 使用场景 5：多次激进优化尝试与回退

### 主要用途
尝试降低 Target Clock Period 等激进优化，但发现导致时序违例。

### 完整 Prompt 内容
```
Clock Period: 12.882 ns 相对于 Target 15.0 ns 还有裕量，
尝试降低 Target Clock 到 14.0 ns 或 13.5 ns，看能否触发更激进的优化。
```

### 模型输出摘要
AI 分析了时序裕量并建议尝试降低 Target Clock，但警告需要确保：
- Slack = (14.0 × 0.9) - Estimated_Clock_Period > 0
- 如果 Estimated_Clock_Period 保持 12.882 ns，则会违例

### 人工审核与采纳情况
- ❌ 尝试 Target Clock = 14.0 ns：导致 Slack = -0.282 ns（时序违例）→ 已撤销
- ❌ 尝试循环展开 factor=2：Clock Period 增加 → 已撤销
- ✅ 学习到：800 cycles 是 HMAC 固有限制（内层+外层 SHA-256）
- ✅ 最终确认：Target Clock = 15.0 ns 是最优配置

---

## 总结

### 整体贡献度评估
- **大模型在本项目中的总体贡献占比**：约 50%
  - 代码优化建议与实现：30%
  - 问题分析与调试：15%
  - 规则理解与策略制定：5%
- **主要帮助领域**：
  - HLS 优化技术（dataflow, pipeline, 数据打包）
  - 时序分析与约束理解
  - 代码重构与模块化设计
- **人工介入与修正比例**：约 50%
  - 验证每个优化的实际效果
  - 撤销导致性能恶化的优化
  - 修复违反竞赛规则的修改
  - 理解算法固有限制

### 最终优化结果
- **Latency**: 800 cycles
- **Clock Period**: 12.882 ns
- **T_exec**: 10,305.6 ns
- **Slack**: +0.618 ns（时序安全）
- **预估得分**: 30/30 (100%)

### 学习收获
1. **时序约束的重要性**：必须确保 Slack > 0，否则扣10分
2. **算法固有限制**：HMAC 需要两次 SHA-256 计算，800 cycles 无法突破
3. **优化权衡**：降低 Clock Period 和降低 Latency 往往矛盾
4. **验证的重要性**：每次优化都必须通过仿真验证
5. **规则遵守**：只能修改 `.hpp` 文件

---

## 附注

- 本项目使用了多个大模型辅助：Claude 4.5 Sonnet、GPT-5 Pro、Claude 4.1 Opus
- 所有优化都经过了严格的功能验证和性能测试
- 最终代码完全符合竞赛规则要求
- AI 提供了优化建议，人工进行了严格筛选和验证

