# 大模型辅助使用记录

## 基本信息

- **模型名称**：
  - **Anthropic 系列**：claude-3.5-sonnet (通过 Augment Agent)
  - **Cursor AI**：Cursor IDE 内置 AI 助手 (1.7.53)
- **提供方 / 访问方式**：
  - Augment Code (augmentcode.com) - Claude 3.5 Sonnet
  - Cursor IDE (cursor.sh)
- **使用日期**：2025-10-21
- **项目名称**：Cholesky 分解（复数定点 ARCH0）L1 算子优化

---

## 使用场景 1：理解 SEL_ARCH 宏并确保 ARCH0 生效

### 主要用途
理解题目要求使用 ARCH0 架构，确保 SEL_ARCH 宏正确生效。

### 完整 Prompt 内容
```
根据新的评分细则，需要对 Cholesky 进行优化。
题目要求使用 ARCH0（choleskyBasic），需要确保 SEL_ARCH 宏生效。
请检查 cholesky.hpp 中的 traits 定义，确保所有特化都支持 SEL_ARCH。
```

### 模型输出摘要
AI 分析了 `choleskyTraits` 的多个特化版本，发现：
1. 部分特化版本缺少 `#ifdef SEL_ARCH` 的支持
2. 需要在所有 traits 特化中添加 SEL_ARCH 宏检查
3. 确保 `hls_config.tmpl` 中定义了 `SEL_ARCH=0`

建议在以下特化中添加 SEL_ARCH 支持：
- 基础模板
- `hls::x_complex<InputBaseType>` 特化
- `std::complex<InputBaseType>` 特化
- `ap_fixed` 特化
- `hls::x_complex<ap_fixed>` 特化

### 人工审核与采纳情况
- ✅ 完全采纳，在所有 traits 特化中添加了 SEL_ARCH 支持
- ✅ 验证 `hls_config.tmpl` 中定义了 `syn.directive=set_directive_define -value SEL_ARCH=0`
- ✅ 通过综合报告确认使用了 choleskyBasic 函数

---

## 使用场景 2：修复对角累加的算法错误

### 主要用途
发现并修复 choleskyBasic 中对角元素累加的逻辑错误。

### 完整 Prompt 内容
```
在 choleskyBasic 的 diag_loop 中，对角元素的累加逻辑有问题：
当前代码是 `sum[j] = hls::x_conj(retrieved_L) * retrieved_L;`
这会覆盖而不是累加。应该改为 `sum[j] += ...`
```

### 模型输出摘要
AI 确认了算法错误：
- 原代码每次迭代都覆盖 `sum[j]`，导致只保留最后一项
- 正确的 Cholesky 算法需要累加所有 k < j 的项
- 修改为 `sum[j] += hls::x_conj(retrieved_L) * retrieved_L;`

### 人工审核与采纳情况
- ✅ 完全采纳，修复了累加逻辑
- ✅ 通过 C Simulation 验证功能正确性
- ✅ 这是关键的算法修复，影响计算正确性

---

## 使用场景 3：对角循环流水线优化

### 主要用途
为 diag_loop 添加流水线指令以提高性能。

### 完整 Prompt 内容
```
diag_loop 当前没有流水线指令，能否添加 
`#pragma HLS PIPELINE II = CholeskyTraits::INNER_II` 
来提高对角元素计算的吞吐量？
```

### 模型输出摘要
AI 建议添加流水线指令：
```cpp
diag_loop:
    for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
        if (k <= (j - 1)) {
            // ... 累加逻辑
        }
    }
```

这样可以实现 II=1 的流水线，提高对角元素计算的吞吐量。

### 人工审核与采纳情况
- ✅ 完全采纳，添加了流水线指令
- ✅ 验证 II=1 达成
- ✅ Latency 有所降低

---

## 使用场景 4：用乘法替代除法优化

### 主要用途
预计算对角元素的倒数，用乘法替代除法操作以降低延迟。

### 完整 Prompt 内容
```
在非对角元素计算中，当前使用除法：
`new_L_off_diag = new_L_off_diag / hls::x_real(L_cast_to_new_L_off_diag);`
能否预计算对角元素的倒数，然后用乘法替代除法？
```

### 模型输出摘要
AI 建议使用 `cholesky_rsqrt` 函数预计算倒数：

1. 在计算对角元素后，立即计算其倒数：
```cpp
typename CholeskyTraits::RECIP_DIAG_T L_diag_recip_current;
cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), L_diag_recip_current);
```

2. 在非对角元素计算中使用乘法：
```cpp
cholesky_prod_sum_mult(new_L_off_diag, L_diag_recip_current, new_L_off_diag);
```

这样可以避免每个非对角元素都执行一次除法操作。

### 人工审核与采纳情况
- ✅ 完全采纳，实现了倒数预计算
- ✅ 使用 `cholesky_prod_sum_mult` 处理复数乘法
- ✅ Clock Period 有所降低
- ✅ 功能验证通过

---

## 使用场景 5：数组分区优化

### 主要用途
对内部数组进行完全分区以提高并行访问能力。

### 完整 Prompt 内容
```
L_internal 和 sum 数组当前没有分区指令，
能否添加完全分区来提高并行访问能力？
```

### 模型输出摘要
AI 建议添加数组分区指令：
```cpp
OutputType L_internal[RowsColsA][RowsColsA];
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 1
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 2

typename CholeskyTraits::ACCUM_T sum[RowsColsA];
#pragma HLS ARRAY_PARTITION variable = sum complete dim = 1
```

完全分区可以：
- 消除数组访问的端口冲突
- 提高并行读写能力
- 降低访问延迟

### 人工审核与采纳情况
- ✅ 采纳了 L_internal 的二维完全分区
- ✅ 采纳了 sum 的一维完全分区
- ⚠️ 资源使用增加（寄存器），但在可接受范围内
- ✅ 性能有所提升

---

## 使用场景 6：循环展开尝试

### 主要用途
尝试对 sum_loop 进行部分展开以提高吞吐量。

### 完整 Prompt 内容
```
sum_loop 能否添加 `#pragma HLS UNROLL factor = 2` 
来提高非对角元素计算的吞吐量？
```

### 模型输出摘要
AI 建议尝试 factor=2 的部分展开，但警告：
- 可能增加资源使用
- 可能增加 Clock Period
- 需要验证实际效果

### 人工审核与采纳情况
- ✅ 尝试了 UNROLL factor=2
- ⚠️ 发现 Clock Period 略有增加
- ⚠️ 总体 T_exec 略有改善
- ✅ 保留了该优化（效果为正）

---

## 总结

### 整体贡献度评估
- **大模型在本项目中的总体贡献占比**：约 60%
  - 算法错误发现与修复：20%
  - 代码优化建议与实现：30%
  - 架构理解与配置：10%
- **主要帮助领域**：
  - Cholesky 算法理解与错误修复
  - HLS 优化技术（pipeline, array partition, unroll）
  - 除法优化（倒数预计算）
- **人工介入与修正比例**：约 40%
  - 验证算法正确性
  - 评估资源与性能权衡
  - 确认 ARCH0 架构生效

### 最终优化结果
- **架构**: ARCH0 (choleskyBasic)
- **功能**: 算法错误已修复，验证通过
- **性能**: Latency 和 Clock Period 均有优化
- **时序**: 满足时序约束
- **预估得分**: 35/35 (100%)

### 学习收获
1. **算法正确性优先**：修复累加错误是最关键的
2. **架构选择的重要性**：确保 SEL_ARCH 宏正确生效
3. **除法优化技巧**：预计算倒数可以显著降低延迟
4. **数组分区的作用**：完全分区可以提高并行访问能力
5. **资源与性能权衡**：完全分区增加寄存器但提升性能

---

## 附注

- 本项目使用了 Augment Agent (Claude 3.5 Sonnet) 和 Cursor AI 辅助
- 修复了关键的算法错误（对角累加逻辑）
- 所有优化都经过了 C Simulation 和 Co-simulation 验证
- 最终代码完全符合竞赛规则要求
- 确认使用 ARCH0 (choleskyBasic) 架构

