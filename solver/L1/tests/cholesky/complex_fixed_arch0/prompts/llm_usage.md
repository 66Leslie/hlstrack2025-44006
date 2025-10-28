# 大模型辅助使用记录

## 基本信息

- **模型名称**：
  - **OpenAI 系列**：GPT-5 (通过 Augment Agent)
  - **Anthropic 系列**：Claude 4.5 Sonnet (通过 Cursor AI)
- **提供方 / 访问方式**：
  - Augment Code (augmentcode.com) - GPT-5
  - Cursor IDE (cursor.sh) - Claude 4.5 Sonnet
- **使用日期**：2025-10-21 至 2025-10-28
- **项目名称**：Cholesky 分解（复数定点 ARCH1）L1 算子 HLS 性能优化

---

## 项目背景说明

### 题目架构要求
- **题目目录名**：`complex_fixed_arch0`（具有迷惑性）
- **实际测试要求**：使用 `SEL_ARCH=1` 即 **choleskyAlt** 架构
- **官方说明**：TEST 文件按照 ARCH1 实现测试，ARCH0 和 ARCH2 无法通过仿真
- **优化范围**：只能修改头文件 `cholesky.hpp`，不能修改 kernel source 和 test 文件

### Cholesky 分解算法原理

对称正定矩阵 $A$ 的 Cholesky 分解：$A = L \cdot L^H$

**对角元素计算**：
$$L_{jj} = \sqrt{A_{jj} - \sum_{k=0}^{j-1} |L_{jk}|^2}$$

**非对角元素计算**（$i > j$）：
$$L_{ij} = \frac{A_{ij} - \sum_{k=0}^{j-1} L_{ik} \cdot \overline{L_{jk}}}{L_{jj}}$$

### choleskyAlt (ARCH1) 架构特点
- 使用 1D 压缩存储 `L_internal[(n²-n)/2]` 代替 2D 数组
- 对角元素预存储为**倒数形式**，避免非对角元素计算时的除法
- 行优先遍历：先计算非对角元素，累加对角 square_sum，最后计算对角元素
- 使用索引生成逻辑 `i_off = ((i-1)²-(i-1))/2 + (i-1)` 访问三角矩阵

---

## 使用场景 1：理解题目架构要求与 SEL_ARCH 宏支持

### 主要用途
理解题目实际要求使用 ARCH1 架构，确保 SEL_ARCH 宏在所有 traits 特化中正确生效。

### 完整 Prompt 内容
```
根据竞赛组委会更新的评分细则，需要对 Cholesky 进行优化。
题目虽然名为 arch0，但实际 TEST 文件按照 ARCH1 实现测试。
请检查 cholesky.hpp 中的 traits 定义，确保所有特化都支持 SEL_ARCH 宏，
让编译时可以通过 -DSEL_ARCH=1 选择 choleskyAlt 架构。
```

### 模型输出摘要
AI 分析了 `choleskyTraits` 的多个特化版本，发现：
1. 基础模板缺少 `#ifdef SEL_ARCH` 的支持，直接硬编码 `ARCH = 1`
2. 需要在所有 traits 特化中添加条件编译，支持外部宏 `SEL_ARCH`
3. 确保 `hls_config.tmpl` 中定义了 `-DSEL_ARCH=1`

建议在以下特化中添加 SEL_ARCH 支持：
- 基础模板 `choleskyTraits<...>`
- 复数特化 `hls::x_complex<InputBaseType>`
- 标准复数特化 `std::complex<InputBaseType>`
- 定点特化 `ap_fixed<...>`
- 复数定点特化 `hls::x_complex<ap_fixed<...>>`

### 人工审核与采纳情况
- ✅ 完全采纳，在所有 5 个 traits 特化中添加了 SEL_ARCH 条件编译支持
- ✅ 验证 `hls_config.tmpl` 中定义了 `-DSEL_ARCH=1`
- ✅ 通过综合报告确认最终调用了 `choleskyAlt` 函数

---

## 使用场景 2：cholesky_rsqrt 函数的牛顿迭代优化

### 主要用途
优化定点数的倒数平方根计算，使用牛顿迭代法提高精度和性能。

### 完整 Prompt 内容
```
cholesky_rsqrt 函数中，对于 ap_fixed 类型，当前使用 sqrt 后再除以 1。
能否使用牛顿迭代法直接计算 rsqrt，公式为：
y_{n+1} = y_n * (1.5 - 0.5 * x * y_n^2)
以单精度 rsqrt 作为初值，一次迭代应该足以满足 3x3 矩阵的固定点精度要求。
```

### 模型输出摘要
AI 提供了牛顿迭代实现方案：
```cpp
void cholesky_rsqrt(ap_fixed<W1, I1, Q1, O1, N1> x, 
                    ap_fixed<W2, I2, Q2, O2, N2>& res) {
    const ap_fixed<W2, I2, Q2, O2, N2> one_point_five = 1.5;
    const ap_fixed<W2, I2, Q2, O2, N2> half = 0.5;
    ap_fixed<W2, I2, Q2, O2, N2> x_cast = x;
    // 使用单精度初值，避免综合出 double rsqrt IP
    ap_fixed<W2, I2, Q2, O2, N2> y0 = x_rsqrt((float)x);
    ap_fixed<W2, I2, Q2, O2, N2> y0_sq = y0 * y0;
    ap_fixed<W2, I2, Q2, O2, N2> term = one_point_five - half * x_cast * y0_sq;
    res = y0 * term;
}
```

优点：
1. 避免综合出 double 精度的 sqrt 和 div IP
2. 使用 float rsqrt 作为初值，硬件开销小
3. 一次牛顿迭代即可满足 3x3 定点精度要求

### 人工审核与采纳情况
- ✅ 完全采纳牛顿迭代方案
- ✅ 通过 C Simulation 和 Co-simulation 验证精度满足要求
- ✅ 避免了高精度 sqrt/div IP 的综合，降低资源使用

---

## 使用场景 3：choleskyAlt 数组分区优化

### 主要用途
对 choleskyAlt 的内部数组进行完全分区，提高并行访问能力。

### 完整 Prompt 内容
```
choleskyAlt 函数中，L_internal 和 diag_internal 数组当前没有分区指令。
由于 L_internal 在 sum_loop 中被频繁随机访问（i_off+k 和 j_off+k），
能否添加完全分区来提高并行访问能力，减少访存冲突？
```

### 模型输出摘要
AI 建议添加数组分区指令：
```cpp
OutputType L_internal[(RowsColsA * RowsColsA - RowsColsA) / 2];
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 1

typename CholeskyTraits::RECIP_DIAG_T diag_internal[RowsColsA];
#pragma HLS ARRAY_PARTITION variable = diag_internal complete dim = 1
```

完全分区可以：
- 消除数组访问的端口冲突
- 提高并行读写能力（sum_loop 中同时访问 L_internal[i_off+k] 和 L_internal[j_off+k]）
- 降低访问延迟，支持 II=1 流水线

### 人工审核与采纳情况
- ✅ 完全采纳，添加了两个数组的完全分区
- ✅ 验证 sum_loop 保持 II=1 流水线
- ⚠️ FF 资源使用增加约 3%，但在可接受范围内（总使用率 15%）
- ✅ 性能有明显提升

---

## 使用场景 4：choleskyAlt 局部寄存器优化

### 主要用途
通过局部寄存器降低数组到 DSP 的扇出与布线压力，改善时序。

### 完整 Prompt 内容
```
在 choleskyAlt 的 sum_loop 中，L_internal[i_off + k] 和 L_internal[j_off + k]
被直接用于乘法和共轭操作：
  prod = -L_internal[i_off + k] * hls::x_conj(L_internal[j_off + k]);

这可能导致从 L_internal 到 DSP 的高扇出和布线压力。
能否先读取到局部变量，再进行运算？
```

### 模型输出摘要
AI 建议引入局部寄存器：
```cpp
sum_loop:
    for (int k = 0; k < j; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
        // 局部寄存，降低从 L_internal 到 DSP 的扇出与布线压力
        auto Li_local = L_internal[i_off + k];
        auto Lj_local = L_internal[j_off + k];
        auto Ljc_local = hls::x_conj(Lj_local);
        prod = -(Li_local * Ljc_local);
        // ...
    }
```

优点：
1. 降低 L_internal 数组的扇出
2. 将共轭操作分离，减少关键路径延迟
3. 给 HLS 工具更多的寄存器重定时优化空间

### 人工审核与采纳情况
- ✅ 完全采纳局部寄存器方案
- ✅ 与其他优化配合，Estimated Clock Period 达到 5.284ns
- ✅ II=1 流水线保持不变
- ✅ 通过 Co-simulation 验证功能正确

---

## 使用场景 5：choleskyAlt 倒数计算方式优化

### 主要用途
调整对角元素倒数的计算方式，从 cholesky_rsqrt 改为直接除法。

### 完整 Prompt 内容
```
在 choleskyAlt 对角元素计算后，当前使用：
  A_minus_sum_cast_diag = A_minus_sum;
  cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);

这需要先 sqrt(A_minus_sum) 得到 L_diag，再 rsqrt(A_minus_sum) 得到倒数。
能否改为先计算 L_diag = sqrt(A_minus_sum)，再直接 1 / L_diag？
```

### 模型输出摘要
AI 分析了两种方案的优劣：

**方案 A（原始）**：`rsqrt(A_minus_sum)` - 直接从 A_minus_sum 计算倒数
- 优点：理论上减少一次计算
- 缺点：rsqrt 的 IP 延迟可能较高

**方案 B（改进）**：`1 / sqrt(A_minus_sum)` - 先 sqrt 再除
```cpp
new_L = new_L_diag;
// 使用 one/diag（保守且周期更优的版本）
{
    typename CholeskyTraits::RECIP_DIAG_T one = 1;
    new_L_diag_recip = one / hls::x_real(new_L_diag);
}
diag_internal[i] = new_L_diag_recip;
```

建议：对于 3x3 复数定点矩阵，sqrt+div 的延迟可能比 rsqrt 更友好

### 人工审核与采纳情况
- ✅ 采纳方案 B（1/diag）
- ✅ 实验对比：rsqrt 版本 Clock Period ≈ 5.5ns，div 版本 ≈ 5.146ns
- ✅ 选择了时序更优的 div 版本
- ✅ 功能验证通过

---

## 使用场景 6：choleskyBasic 的补充优化（参考价值）

### 主要用途
虽然实际使用 ARCH1，但对 ARCH0 的优化可作为学习参考。

### 完整 Prompt 内容
```
choleskyBasic 中存在一些优化机会：
1. diag_loop 的对角累加有 bug：sum[j] = ... 应该改为 sum[j] += ...
2. 可以添加流水线和数组分区指令
3. 可以预计算对角倒数，用乘法替代除法

虽然我们使用 ARCH1，但能否顺便修复 ARCH0，供其他参赛者参考？
```

### 模型输出摘要
AI 提供了 choleskyBasic 的优化方案：

1. **修复对角累加 bug**：
```cpp
// 原代码（错误）
sum[j] = hls::x_conj(retrieved_L) * retrieved_L;
// 修复后
sum[j] += hls::x_conj(retrieved_L) * retrieved_L;
```

2. **添加数组分区**：
```cpp
OutputType L_internal[RowsColsA][RowsColsA];
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 1
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 2
```

3. **添加流水线指令**：
```cpp
diag_loop:
    for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
        // ...
    }
```

4. **预计算对角倒数**：
```cpp
cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), L_diag_recip_current);
// 后续用乘法替代除法
cholesky_prod_sum_mult(new_L_off_diag, L_diag_recip_current, new_L_off_diag);
```

### 人工审核与采纳情况
- ✅ 完全采纳，修复了 ARCH0 的算法错误和性能问题
- ⚠️ **注意：这些修改对最终得分无直接贡献**（因为实际使用 ARCH1）
- ✅ 但通过修复，加深了对 Cholesky 算法和 HLS 优化的理解

---

## 使用场景 7：choleskyAlt2 和 cholesky 入口函数优化

### 主要用途
对 ARCH2 进行补充优化，并调整入口函数的流水线策略。

### 完整 Prompt 内容
```
1. choleskyAlt2 的嵌套循环能否添加 UNROLL 和 DEPENDENCE pragma？
2. cholesky 入口函数中读写 stream 的循环是否需要 PIPELINE？
```

### 模型输出摘要
AI 建议：

1. **choleskyAlt2 优化**：
```cpp
#pragma HLS UNROLL FACTOR = 2
#pragma HLS DEPENDENCE variable = L_internal inter false
#pragma HLS DEPENDENCE variable = L_internal intra false
```

2. **cholesky 入口函数**：
```cpp
// 去掉以下 PIPELINE（让内层函数自主优化）
for (int r = 0; r < RowsColsA; r++) {
    // #pragma HLS PIPELINE  // 移除
    for (int c = 0; c < RowsColsA; c++) {
        matrixAStrm.read(A[r][c]);
    }
}
```

理由：choleskyTop 内部已经高度优化，入口函数的 PIPELINE 可能引入不必要的约束

### 人工审核与采纳情况
- ✅ 采纳 choleskyAlt2 的优化（供完整性）
- ✅ 移除了 cholesky 入口函数的 PIPELINE pragma
- ✅ 验证对 ARCH1 性能无负面影响

---

## 总结

### 整体贡献度评估

- **大模型在本项目中的总体贡献占比**：约 **50%**
  
  **架构理解与配置（20%）**：
  - 理解题目要求使用 ARCH1 而非 ARCH0
  - 确保 SEL_ARCH 宏在所有 traits 特化中生效
  
  **HLS 优化技术指导（25%）**：
  - 局部寄存器优化方案
  - 数组分区策略
  - 倒数计算方式对比实验设计
  
  **代码实现与调试（5%）**：
  - 牛顿迭代 rsqrt 实现
  - 其他辅助优化

- **人工介入与修正比例**：约 **50%**
  - 理解评分规则与性能指标
  - 验证功能正确性（C Simulation, Co-simulation）
  - 实验对比与方案决策（rsqrt vs div）
  - 资源与时序权衡
  
- **重要说明**：
  - **性能改善 43.2% 的构成**：
    - Latency 改善 32.5%（ARCH1 架构）← AMD 官方优化架构
    - Clock Period 改善 15.8%（局部寄存器等优化）← 大模型辅助优化
  - **大模型的核心贡献**：
    - 理解题目要求使用 ARCH1（而非目录名的 arch0）
    - 在 ARCH1 基础上进行时序优化（15.8%）
    - 提供优化方向和实验验证方案
  - 对 choleskyBasic (ARCH0) 的修复虽然完整，但**对最终得分无贡献**（因为实际使用 ARCH1）

### 最终优化结果

#### 性能指标（ARCH1: choleskyAlt）

**C-Synthesis 估计** (用于评分)：
| 指标 | Baseline | 当前优化 | 改善 |
|------|----------|----------|------|
| **目标时钟周期** | 7.000 ns | 5.900 ns | ↓ 15.7% |
| **估计时钟周期** | 6.276 ns | 5.284 ns | ↓ **15.8%** |
| **Slack** | +0.024 ns | +0.026 ns | ✅ 满足 |
| **C-Syn Worst Latency** | - | 510 cycles | - |

**RTL Co-simulation 结果**：
| 指标 | Baseline | 当前优化 | 改善 |
|------|----------|----------|------|
| **Cosim Latency (Total)** | 4,919 cycles | **3,319 cycles** | ↓ **32.5%** |
| **单次迭代延迟** | - | 414 cycles | - |
| **测试次数** | 8 | 8 | - |
| **Status** | Pass | **Pass** ✅ | - |

**核心评分指标**：
```
T_exec = Estimated_Clock_Period × Cosim_Latency (Total)
       = 5.284 ns × 3,319 cycles
       = 17,537.6 ns
```

与 Baseline (30,871.6 ns) 相比，执行时间改善 **43.2%** 🎉

**说明**：
- Cosim Latency 使用 Total Execution Time (包含所有测试矩阵)
- 单次迭代延迟 414 cycles 仅供参考，不用于评分计算

#### 资源使用（XC7Z020 平台）

**C-Synthesis 估计** (用于评分)：
| 资源类型 | 使用量 | 可用量 | 利用率 | 状态 |
|---------|--------|--------|--------|------|
| **LUT** | 6,326 | 53,200 | 11.89% | ✅ 正常 |
| **FF** | 4,272 | 106,400 | 4.02% | ✅ 正常 |
| **DSP** | 14 | 220 | 6.36% | ✅ 正常 |
| **BRAM** | 0 | 280 | 0.00% | ✅ 正常 |

**RTL Implementation 实际**：
| 资源类型 | 使用量 | 利用率 | 状态 |
|---------|--------|--------|------|
| **LUT** | 2,393 | 4.50% | ✅ 优秀 |
| **FF** | 3,261 | 3.06% | ✅ 优秀 |
| **DSP** | 14 | 6.36% | ✅ 正常 |
| **BRAM** | 2 | 0.71% | ✅ 正常 |
| **SRL** | 39 | - | - |

**时序验证（Implementation）**：
- Target Clock: 5.900 ns
- Post-Synthesis: 6.171 ns
- **Timing NOT met** ⚠️ (Slack = -0.271 ns)
- **说明**：评分基于 C-Synthesis 时序，Implementation 时序不影响评分

#### 关键优化点排序

**执行时间改善 43.2% 的贡献分解**：
- Clock Period 改善：15.8% (6.276 → 5.284 ns)
- Latency 改善：32.5% (4,919 → 3,319 cycles)
- 综合效果：(1 - 0.842 × 0.675) = 43.2%

1. **架构选择：确保使用 ARCH1 (choleskyAlt)**（Latency ↓32.5%）
   - 行优先遍历，优化计算顺序
   - 1D 压缩存储，减少内存访问
   - 预存储对角倒数，避免除法运算
   - **贡献：Cosim Latency 从 4,919 降至 3,319 cycles**
   - **说明：ARCH1 是 AMD 官方提供的优化架构**

2. **局部寄存器优化**（Clock Period ↓15.8%）
   - 降低 L_internal → DSP 的扇出与布线压力
   - 分离共轭操作，优化关键路径
   - **贡献：Estimated Clock Period 从 6.276ns 降至 5.284ns**
   - **这是在 ARCH1 基础上的主要优化贡献**

3. **数组完全分区**（并行访问能力）
   - 消除 L_internal 和 diag_internal 的访存冲突
   - 支持 sum_loop 的 II=1 流水线
   - **贡献：保持高吞吐量，配合局部寄存器优化降低时序**

4. **倒数计算方式调整**（时序友好）
   - 从 cholesky_rsqrt(A_minus_sum) 改为 1/sqrt(A_minus_sum)
   - 实验验证：div 方案时序更优（5.284ns vs ~5.5ns）
   - **贡献：选择了时序最优的实现方式**

5. **牛顿迭代 rsqrt 实现**（资源优化）
   - 避免高精度 double IP 综合
   - 一次牛顿迭代满足 3x3 定点精度
   - **贡献：降低资源使用，间接改善时序**

### 学习收获

1. **正确理解题目要求至关重要**
   - 题目目录名为 `arch0` 但实际要求使用 ARCH1
   - 必须与组委会确认测试标准，避免在错误方向上浪费精力

2. **理解评分标准是优化的前提**
   - 评分公式：T_exec = Estimated_Clock_Period × Cosim_Latency (Total)
   - C-Synthesis 时序用于评分，Implementation 时序仅供参考
   - **Cosim Latency 使用 Total Execution Time，而非单次迭代延迟**
   - hls_cosim.rpt 中的 "Latency" 是单次，"Total Execution Time" 才是评分用的

3. **架构选择的重要影响**
   - ARCH1 相比 ARCH0 的 Latency 降低 32.5%（4,919 → 3,319 cycles）
   - 这是重要的性能提升来源，占总改善的约 75%
   - 配合时序优化（Clock Period ↓15.8%），总执行时间改善 43.2%

4. **局部寄存器优化的有效性**
   - 合理使用 `auto` 局部变量降低布线压力
   - 分离共轭操作，给 HLS 更多重定时优化空间
   - EstimatedClockPeriod 改善 15.8%

5. **实验验证的必要性**
   - rsqrt vs 1/div：实验证明 div 方案时序更优
   - 不能仅凭理论推断，需要实际综合对比

6. **资源与性能的权衡**
   - 数组完全分区：提升并行度但增加 FF 使用
   - 本题资源充裕，可以用空间换时间

7. **优化优先级排序**
   - 第一优先：确保使用正确的架构（ARCH1）→ Latency ↓32.5%
   - 第二优先：时序优化（局部寄存器、数组分区）→ Clock Period ↓15.8%
   - 第三优先：资源优化（在不影响性能前提下）
   - **不要盲目修复无关代码**：对 choleskyBasic 的修复虽然正确，但对 ARCH1 评分无贡献

