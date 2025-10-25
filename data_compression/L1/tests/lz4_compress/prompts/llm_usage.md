# 大模型辅助使用记录

## 基本信息

- **模型名称**：
  - **Anthropic 系列**：Claude 4.1 Opus (通过 Augment Agent)
  - **OpenAI 系列**：GPT-5 (通过 Cursor AI)
  - **Anthropic 系列**：Claude 4.5 Sonnet (API 直接调用)
- **提供方 / 访问方式**：
  - Augment Code (augmentcode.com) - Claude 4.1 Opus
  - Cursor IDE (cursor.sh) - GPT-5
  - Anthropic API - Claude 4.5 Sonnet
- **使用日期**：2025-10-25
- **项目名称**：LZ4 Compress L1 算子优化

---

## 使用场景 1：分析优化策略并制定分阶段计划

### 主要用途
分析 LZ4 压缩算法的性能瓶颈，制定分阶段优化计划。

### 完整 Prompt 内容
```
快速扫描 data_compression/L1/tests/lz4_compress 工程，
定位需要修改的文件，创建分阶段的优化计划。
从基线验证开始（csim/csynth/cosim），确保工程可编译可仿真。
```

### 模型输出摘要
AI 分析了 LZ4 压缩的关键模块并提出优化计划：

**Phase 1 - 基础优化**：
1. 字典初始化循环展开：`dict_flush` 的 UNROLL factor 从 2 增加到 4
2. Stream 深度优化：增加 `lit_outStream` 和 `lenOffset_Stream` 深度
3. 时钟周期调整：从 15ns 降低到 12-14ns

**Phase 2 - 进阶优化**（如需要）：
- 状态机优化和条件预计算
- 哈希计算优化
- 字典分区优化

### 人工审核与采纳情况
- ✅ 采纳了分阶段优化策略
- ✅ 采纳了 Phase 1 的三项基础优化
- ✅ 确认了修改文件：`lz_compress.hpp`, `lz4_compress.hpp`, `hls_config.cfg`
- ⚠️ Phase 2 保留为备选方案

---

## 使用场景 2：字典初始化循环展开优化

### 主要用途
优化 LZ4 字典初始化的性能，减少初始化延迟。

### 完整 Prompt 内容
```
在 lz_compress.hpp 中，dict_flush 循环的 UNROLL FACTOR 当前是 2，
能否增加到 4 来加速字典初始化？
```

### 模型输出摘要
AI 建议将 `dict_flush` 循环的展开因子从 2 增加到 4：
```cpp
dict_flush:
    for (int i = 0; i < LZ_DICT_SIZE; i++) {
#pragma HLS PIPELINE II = 1
#pragma HLS UNROLL FACTOR = 4  // 从 2 改为 4
        dict[i] = resetValue;
    }
```

这样可以每周期初始化 4 个字典条目，减少初始化延迟。

### 人工审核与采纳情况
- ✅ 完全采纳，修改了两处 `lzCompress` 函数中的 `dict_flush` 循环
- ✅ 通过 C Simulation 验证
- ✅ 资源使用在可接受范围内

---

## 使用场景 3：Stream 深度和存储类型优化

### 主要用途
优化 dataflow 架构中的 FIFO 深度和存储类型，减少阻塞。

### 完整 Prompt 内容
```
lz4Compress 函数中的 lit_outStream 和 lenOffset_Stream 深度较小，
能否增加深度并绑定到 BRAM 以减少 dataflow 进程间的阻塞？
```

### 模型输出摘要
AI 建议优化 Stream 配置：

1. **lz4Compress 函数**：
   - `lit_outStream`: depth = MAX_LIT_COUNT → (MAX_LIT_COUNT > 64 ? MAX_LIT_COUNT : 64)
   - `lenOffset_Stream`: depth = c_gmemBurstSize → (c_gmemBurstSize * 4)
   - 绑定类型：SRL → BRAM

2. **hlsLz4Core 函数**：
   - `compressdStream`, `bestMatchStream`, `boosterStream`: depth = 8 → 32
   - 绑定类型：SRL → BRAM

3. **hlsLz4 函数**：
   - `inStream`, `outStream`: depth = c_gmemBurstSize → (c_gmemBurstSize * 4)
   - 绑定类型：SRL → BRAM

### 人工审核与采纳情况
- ✅ 完全采纳了 Stream 深度增加的建议
- ✅ 修改了存储类型绑定（SRL → BRAM）
- ✅ 验证无死锁，功能正确
- ✅ 资源使用增加但在可接受范围内

---

## 使用场景 4：时钟周期优化与时序验证

### 主要用途
调整目标时钟周期以优化性能，同时确保时序约束满足。

### 完整 Prompt 内容
```
将 HLS 时钟从 15ns 调整为 12ns，运行综合后发现 Slack < 0（时序违例），
需要调整到 14ns 以确保时序安全。
```

### 模型输出摘要
AI 分析了时序约束：
- Target Clock = 12ns：Estimated ≈ 12.27ns，Slack = (12 × 0.9) - 12.27 = -0.47ns ❌
- Target Clock = 14ns：Estimated ≈ 12.31ns，Slack = (14 × 0.9) - 12.31 = +0.29ns ✅

建议使用 14ns 作为目标时钟周期。

### 人工审核与采纳情况
- ❌ 尝试 12ns：时序违例 → 已撤销
- ✅ 采纳 14ns：时序安全，性能优秀
- ✅ 修改了 `hls_config.cfg` 和 `hls_config.tmpl`
- ✅ 重新运行综合和联仿验证通过

---

## 使用场景 5：字典大小优化

### 主要用途
调整字典大小以平衡性能和资源使用。

### 完整 Prompt 内容
```
LZ_DICT_SIZE 当前是 1 << 12 (4096)，能否减小到 1 << 8 (256) 
来降低资源使用并可能提高时钟频率？
```

### 模型输出摘要
AI 分析了字典大小的影响：
- 减小字典可以降低 BRAM 使用
- 可能略微降低压缩比，但对性能影响较小
- 需要添加 `hash &= (LZ_DICT_SIZE - 1)` 确保哈希值在范围内

### 人工审核与采纳情况
- ✅ 采纳了字典大小减小的建议（4096 → 256）
- ✅ 添加了哈希值掩码操作
- ✅ 验证压缩比保持在 2.21（正常范围）
- ✅ 资源使用显著降低

---

## 总结

### 整体贡献度评估
- **大模型在本项目中的总体贡献占比**：约 55%
  - 代码优化建议与实现：35%
  - 配置调整与参数优化：15%
  - 问题分析与调试：5%
- **主要帮助领域**：
  - HLS pragma 优化（UNROLL, PIPELINE, BIND_STORAGE）
  - Dataflow 架构的 Stream 深度配置
  - 时序约束分析与时钟周期调整
- **人工介入与修正比例**：约 45%
  - 验证每个优化的实际效果
  - 调整时钟周期以满足时序约束
  - 确认压缩比和功能正确性

### 最终优化结果
- **Latency**: 1376 cycles
- **Clock Period**: 12.303 ns
- **T_exec**: 16,928.93 ns
- **Slack**: +0.297 ns（时序安全）
- **压缩比**: 2.21（正常）
- **加速比**: 2.65x vs baseline
- **预估得分**: ~93.5/100

### 学习收获
1. **分阶段优化策略**：从基础优化开始，逐步验证
2. **时序与性能的平衡**：不能盲目降低时钟周期
3. **资源与性能的权衡**：字典大小影响资源和性能
4. **Dataflow 优化**：合理的 FIFO 深度可以减少阻塞
5. **压缩比验证**：优化不应影响算法的功能正确性

---

## 附注

- 本项目使用了多个大模型辅助：Claude 4.1 Opus、GPT-5、Claude 4.5 Sonnet
- 所有优化都经过了 C Simulation 和 Co-simulation 验证
- 压缩比保持在正常范围（2.21），功能正确
- 最终代码完全符合竞赛规则要求

