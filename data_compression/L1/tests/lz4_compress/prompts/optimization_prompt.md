# LZ4 Compress HLS 优化指令 Prompt

## 任务背景

你是一位 FPGA HLS 优化专家，正在参加 Vitis Library HLS 算法优化竞赛。你需要对 **LZ4 压缩算法** 进行 HLS 优化，目标是在保持功能正确性的前提下，**最小化执行时间**。

### 评分标准
```
执行时间 (ns) = Estimated_Clock_Period × Cosim_Latency
```

### 硬件平台与约束
- **FPGA 器件**: Zynq-7000 (xc7z020-clg484-1)
- **工具版本**: Vitis HLS 2024.2
- **时序约束**: Clock Uncertainty = Target Clock Period × 10% (固定不可修改)
- **Slack 计算**: Slack = (Target × 0.9) - Estimated_Clock_Period
- **时序违例惩罚**: 若 Slack ≤ 0，该题扣除 10 分

### Baseline 性能指标
- **Target Clock**: 15 ns
- **Estimated Clock**: 13.220 ns
- **Cosim Latency**: 3390 cycles
- **执行时间**: 44815.8 ns
- **时序状态**: Pass (Slack > 0)

### 优化目标
你需要超越 Baseline 的执行时间 (44815.8 ns)，同时尽量避免时序违例。

---

## 允许修改的文件

你可以修改以下头文件来实现优化：
1. `data_compression/L1/include/hw/lz4_compress.hpp` - LZ4 压缩核心实现
2. `data_compression/L1/include/hw/lz_compress.hpp` - 通用 LZ 压缩框架
3. `data_compression/L1/include/hw/lz_optional.hpp` - 可选优化组件
4. `data_compression/L1/tests/lz4_compress/hls_config.tmpl` - 时钟频率配置（允许修改）
5. `data_compression/L1/tests/lz4_compress/run_hls.tcl` - Tcl 脚本（允许修改时钟配置）

**注意**: 不得修改测试文件 `lz4_compress_test.cpp`，优化后必须通过 C Simulation 和 Co-simulation 验证。

---

## HLS 优化策略知识库

基于 HLSPilot 论文和 Xilinx HLS 用户手册，以下是针对 LZ4 压缩算法的优化策略：

### 1. 数据流流水线优化 (Dataflow Pipelining)

**策略概述**:
- 将复杂的计算内核分解为多个相互依赖的任务
- 使用 `#pragma HLS dataflow` 实现任务级流水线
- 通过 `hls::stream` 进行任务间数据传输

**适用场景**:
- LZ4 压缩包含多个阶段：哈希匹配、回溯、编码
- 这些阶段可以并行处理不同的数据块

**优化示例**:
```cpp
void lz4_compress_dataflow(input_t* in, output_t* out, int size) {
    #pragma HLS dataflow
    
    hls::stream<hash_t> hash_stream;
    hls::stream<match_t> match_stream;
    
    // 任务1: 哈希计算
    compute_hash(in, hash_stream, size);
    
    // 任务2: 匹配查找
    find_matches(hash_stream, match_stream, size);
    
    // 任务3: 编码输出
    encode_output(match_stream, out, size);
}
```

**参数说明**:
- 确保任务之间通过 `hls::stream` 通信，避免全局数组依赖
- 每个任务内部也需要优化循环 II (Initiation Interval)

---

### 2. 循环流水线优化 (Loop Pipelining)

**策略概述**:
- 使用 `#pragma HLS pipeline II=<value>` 减少循环的启动间隔
- 目标 II=1 可实现每个时钟周期启动一次新迭代

**适用场景**:
- LZ4 的字节扫描循环、哈希表查找循环
- 数据依赖较少的顺序处理循环

**优化示例**:
```cpp
// 优化前
for (int i = 0; i < size; i++) {
    hash = compute_hash(data[i]);
    table[hash] = i;
}

// 优化后
for (int i = 0; i < size; i++) {
    #pragma HLS pipeline II=1
    hash = compute_hash(data[i]);
    table[hash] = i;
}
```

**参数说明**:
- `II=1`: 每个时钟周期启动一次循环迭代
- 若存在数据依赖，可能需要 `II=2` 或更大值
- 检查综合报告中的 "Estimated Achieved II"

---

### 3. 循环展开优化 (Loop Unrolling)

**策略概述**:
- 使用 `#pragma HLS unroll factor=<N>` 并行处理多个迭代
- 可以提高吞吐量，但会增加资源使用

**适用场景**:
- 小规模固定迭代次数的循环
- 需要并行处理多个字节的场景（如 4 字节、8 字节并行匹配）

**优化示例**:
```cpp
// 匹配长度扫描
for (int i = 0; i < MAX_MATCH_LEN; i++) {
    #pragma HLS unroll factor=4
    if (src[i] == ref[i]) {
        match_len++;
    } else {
        break;
    }
}
```

**参数说明**:
- `factor=N`: 展开 N 次迭代
- `factor=0`: 完全展开（迭代次数必须是常量）
- 注意资源约束（LUT、DSP 不能超限）

---

### 4. 数组分区优化 (Array Partition)

**策略概述**:
- 使用 `#pragma HLS array_partition` 将数组分割为多个小数组
- 允许并行访问多个元素，消除访存瓶颈

**适用场景**:
- LZ4 哈希表（需要并行查找多个哈希值）
- 局部缓冲区（需要并行读写）

**优化示例**:
```cpp
// 哈希表分区
void lz4_compress(...) {
    static uint32_t hash_table[HASH_SIZE];
    #pragma HLS array_partition variable=hash_table cyclic factor=4
    
    // 现在可以并行访问 4 个不同的哈希桶
}
```

**参数说明**:
- `complete`: 完全分区（每个元素独立存储）
- `cyclic factor=N`: 循环分区（相邻 N 个元素分布到不同 bank）
- `block factor=N`: 块分区（连续 N 个元素一组）
- `dim=N`: 多维数组指定分区维度

---

### 5. 内存优化 (Memory Optimization)

**策略概述**:
- 使用 `#pragma HLS bind_storage` 指定存储类型（BRAM/URAM）
- 使用 `#pragma HLS data_pack` 打包结构体减少访存次数
- 使用局部缓存 (Local Buffer) 减少外部内存访问

**适用场景**:
- LZ4 的滑动窗口需要高效访问历史数据
- 哈希表需要快速查找

**优化示例**:
```cpp
// 数据打包
typedef struct {
    uint32_t offset;
    uint16_t length;
    uint8_t literal_len;
} match_info_t;
#pragma HLS data_pack variable=match_info

// 指定存储类型
static uint8_t window[WINDOW_SIZE];
#pragma HLS bind_storage variable=window type=RAM_2P impl=BRAM

// 局部缓存
void process_block(uint8_t* input, ...) {
    uint8_t local_buf[BLOCK_SIZE];
    #pragma HLS array_partition variable=local_buf cyclic factor=8
    
    // 批量读取到本地缓存
    memcpy(local_buf, input, BLOCK_SIZE);
    
    // 在本地缓存上进行处理
    for (int i = 0; i < BLOCK_SIZE; i++) {
        #pragma HLS pipeline II=1
        // 处理 local_buf[i]
    }
}
```

**参数说明**:
- `RAM_1P`: 单端口 RAM (1 read/write per cycle)
- `RAM_2P`: 双端口 RAM (1 read + 1 write per cycle)
- `RAM_T2P`: 真双端口 RAM (2 reads or 2 writes per cycle)
- `BRAM`: 使用 Block RAM
- `URAM`: 使用 Ultra RAM (更大容量，较少数量)

---

### 6. 数据类型优化 (Datatype Optimization)

**策略概述**:
- 使用 `ap_uint<N>`、`ap_int<N>` 精确指定位宽
- 使用 `ap_fixed<W,I>` 进行定点运算（如需浮点转定点）
- 减少不必要的位宽可降低资源使用和延迟

**适用场景**:
- LZ4 的偏移量字段（通常不需要 32 位）
- 长度计数器（可使用更小位宽）

**优化示例**:
```cpp
#include "ap_int.h"

// 优化前
uint32_t offset;  // 浪费位宽
uint32_t length;

// 优化后
ap_uint<16> offset;  // LZ4 最大偏移 64KB
ap_uint<8> length;   // LZ4 长度字段 8 位
```

**参数说明**:
- `ap_uint<N>`: N 位无符号整数
- `ap_int<N>`: N 位有符号整数
- 选择最小满足需求的位宽

---

### 7. 接口优化 (Interface Optimization)

**策略概述**:
- 使用 `#pragma HLS interface` 优化输入/输出接口
- 使用 AXI-Stream 提高数据传输效率
- 使用 m_axi 接口进行突发传输

**适用场景**:
- LZ4 的输入/输出数据流
- 大块数据传输

**优化示例**:
```cpp
void lz4_compress(
    hls::stream<ap_uint<512>>& in,
    hls::stream<ap_uint<512>>& out,
    int size
) {
    #pragma HLS interface axis port=in
    #pragma HLS interface axis port=out
    #pragma HLS interface s_axilite port=size
    #pragma HLS interface s_axilite port=return
    
    // 每次处理 64 字节 (512 bits)
}
```

---

### 8. 程序树分解策略 (Program Tree Decomposition)

**策略概述**:
- 基于 HLSPilot 论文的程序树分解方法
- 将复杂嵌套循环分解为多个任务

**LZ4 压缩的任务分解建议**:

```
lz4_compress_kernel
├── Task 1: 读取输入数据块
│   └── 从全局内存读取到本地缓冲
├── Task 2: 哈希计算与匹配查找
│   ├── Sub-task 2.1: 计算滚动哈希
│   └── Sub-task 2.2: 查找哈希表并更新
├── Task 3: 匹配验证与扩展
│   ├── Sub-task 3.1: 向后扩展匹配长度
│   └── Sub-task 3.2: 选择最优匹配
└── Task 4: 编码输出
    ├── Sub-task 4.1: 输出 literal token
    └── Sub-task 4.2: 输出 match token
```

使用 `#pragma HLS dataflow` 连接这些任务，通过 `hls::stream` 传递数据。

---

## 优化策略执行步骤

### Step 1: 代码分析与性能瓶颈识别

**任务**:
1. 阅读并理解 `lz4_compress.hpp` 中的核心算法实现
2. 识别以下性能瓶颈：
   - 最耗时的循环（通过初始综合报告的 Loop Latency 分析）
   - 存在数据依赖的代码段
   - 内存访问密集的操作（哈希表查找、滑动窗口访问）
3. 确定优化优先级

**输出**:
- 列出 Top 3 性能瓶颈及其对应的优化策略

---

### Step 2: 应用循环流水线优化

**任务**:
1. 对主循环（字节扫描循环）应用 `#pragma HLS pipeline II=1`
2. 检查综合报告中是否存在 II 违例（II Violation）
3. 如有违例，分析依赖关系（RAW/WAR/WAW）并解决：
   - 使用数组分区消除内存依赖
   - 插入延迟变量打破循环依赖
   - 重构代码消除伪依赖

**验证**:
- C Simulation 通过
- 综合报告显示 Achieved II ≤ 目标 II

---

### Step 3: 应用数据流流水线优化

**任务**:
1. 将 LZ4 压缩流程分解为 3-5 个独立任务
2. 使用 `hls::stream` 进行任务间通信
3. 在顶层函数添加 `#pragma HLS dataflow`

**参考分解示例**:
```cpp
void lz4_compress_dataflow(...) {
    #pragma HLS dataflow
    
    hls::stream<data_t> input_stream;
    hls::stream<hash_t> hash_stream;
    hls::stream<match_t> match_stream;
    hls::stream<token_t> output_stream;
    
    read_input(in, input_stream, size);
    compute_hash(input_stream, hash_stream);
    find_matches(hash_stream, match_stream);
    encode_tokens(match_stream, output_stream);
    write_output(output_stream, out);
}
```

**验证**:
- C Simulation 通过（检查数据流是否正确）
- 综合报告显示 Dataflow 流水线生效

---

### Step 4: 应用数组分区与内存优化

**任务**:
1. 对哈希表应用 `#pragma HLS array_partition cyclic factor=4`
2. 对滑动窗口缓冲区应用合适的分区策略
3. 使用 `#pragma HLS bind_storage` 指定 BRAM/URAM

**示例**:
```cpp
static uint32_t hash_table[HASH_TABLE_SIZE];
#pragma HLS array_partition variable=hash_table cyclic factor=4

static uint8_t window[WINDOW_SIZE];
#pragma HLS bind_storage variable=window type=RAM_2P impl=BRAM
```

**验证**:
- 综合报告显示数组并行端口数量正确
- 资源使用（BRAM/URAM）在器件限制内

---

### Step 5: 时钟频率调优

**任务**:
1. 在 `hls_config.tmpl` 中修改时钟周期：
   ```
   config_compile -pipeline_style=flp
   config_schedule -enable_dsp_full_reg
   create_clock -period <value>
   ```
2. 尝试以下策略：
   - **保守策略**: 10-15 ns (时序安全，需极致优化 Latency)
   - **平衡策略**: 7-10 ns (适度优化 Latency，时序可控)
   - **激进策略**: 5-7 ns (可适当放松 Latency，但注意时序违例扣 10 分)

3. 计算 Slack 并评估风险：
   ```
   Slack = (Target × 0.9) - Estimated
   ```
   - Slack > 0.5 ns: 安全
   - 0 < Slack < 0.5 ns: 边缘安全
   - Slack ≤ 0: 违例（扣 10 分）

**建议**:
- 先实现时序安全的版本（Slack > 0）
- 再尝试激进版本并比较最终得分

---

### Step 6: 设计空间探索 (DSE)

**任务**:
1. 调整以下参数并记录结果：
   - 循环展开因子 (unroll factor: 1, 2, 4, 8)
   - 数组分区因子 (partition factor: 2, 4, 8, 16)
   - 流水线 II (II: 1, 2, 3)
   - 时钟周期 (period: 5, 7, 10, 15 ns)

2. 记录每组参数的：
   - Estimated Clock Period
   - Cosim Latency
   - 执行时间 = Estimated × Latency
   - Slack 状态
   - 资源使用（LUT, FF, BRAM, DSP）

3. 选择执行时间最短且资源不超限的方案

**工具推荐**:
- 手动 DSE: 编写脚本遍历参数组合
- 自动化工具: GenHLSOptimizer (如论文中所用)

---

### Step 7: 验证与提交

**验证流程**:
1. `make clean && make run TARGET=csim` - 必须 PASS
2. `make run TARGET=csynth` - 检查资源与时序
3. `make run TARGET=cosim` - 必须 PASS，获取最终 Latency

**提取关键指标**:
从 `hls/reports/lz4CompressEngineRun_csynth.rpt` 提取：
- Target Clock Period
- Estimated Clock Period
- Uncertainty (应为 Target × 10%)

从 `hls/reports/lz4CompressEngineRun_cosim.rpt` 提取：
- Latency (cycles) - max

**计算最终得分**:
```
Slack = (Target × 0.9) - Estimated
执行时间 = Estimated × Latency
Speedup = Baseline_Time / 执行时间 = 44815.8 / 执行时间
```

**提交材料**:
1. 修改后的头文件：`lz4_compress.hpp`, `lz_compress.hpp`, `lz_optional.hpp`
2. 修改后的配置文件：`hls_config.tmpl`, `run_hls.tcl`
3. `reports/` 目录：包含 `csynth.xml`, `*_cosim.rpt`, `*_csim.log`
4. `prompts/llm_usage.md`: 记录本 prompt 的使用情况

---

## 预期优化效果

基于论文中的优化经验，预期可达到的性能提升：

| 优化阶段 | 累计 Latency 减少 | 累计执行时间减少 | 关键优化 |
|---------|------------------|----------------|---------|
| Baseline | 3390 cycles | 44815.8 ns | - |
| + Pipeline | -30% ~ -50% | -20% ~ -40% | 循环 II=1 |
| + Dataflow | -40% ~ -60% | -30% ~ -50% | 任务并行 |
| + Memory Opt | -50% ~ -70% | -40% ~ -60% | 数组分区 |
| + Clock Tuning | -50% ~ -70% | -50% ~ -70% | 提高频率 |

**目标**: 执行时间 < 15000 ns (加速 3x 以上)

---

## 常见问题与调试技巧

### Q1: 循环流水线 II 违例
**原因**: 循环体内存在数据依赖（RAW/WAR/WAW）
**解决**:
- 检查综合报告的 "Loop Dependency" 部分
- 使用数组分区消除内存端口冲突
- 重构代码，消除跨迭代依赖

### Q2: Dataflow 警告 "cannot be scheduled"
**原因**: 任务间存在非 FIFO 通信或循环依赖
**解决**:
- 确保所有任务间通信使用 `hls::stream`
- 检查是否有全局变量被多个任务读写
- 确保任务调用顺序无循环依赖

### Q3: 资源超限
**原因**: 过度展开或分区
**解决**:
- 减小 unroll factor
- 使用 cyclic partition 代替 complete partition
- 检查综合报告的 "Resource Utilization"

### Q4: Co-simulation 失败
**原因**: 代码优化引入功能错误
**解决**:
- 逐步添加优化 pragma，每次验证
- 检查数组边界访问
- 使用 C Simulation 的 debug 模式

### Q5: 时序违例 (Slack < 0)
**原因**: 关键路径延迟过长
**解决**:
- 增大时钟周期 (降低频率)
- 在关键路径插入寄存器 (pipeline)
- 减少循环体复杂度

---

## 优化检查清单

在提交前，请确认：

- [ ] C Simulation 通过
- [ ] Co-simulation 通过
- [ ] 执行时间 < Baseline (44815.8 ns)
- [ ] Slack > 0 (或接受扣 10 分)
- [ ] 资源使用在器件限制内 (xc7z020)
- [ ] 已记录优化前后的性能对比数据
- [ ] 已填写 `prompts/llm_usage.md`
- [ ] 已将综合报告复制到 `reports/` 目录

---

## 参考资料

1. **HLSPilot 论文**: "HLSPilot: LLM-based High-Level Synthesis"
   - 第 III-C 节: LLM-based Automatic HLS Optimization
   - 表 II: Major Optimization Strategies

2. **Xilinx 官方文档**:
   - UG902: Vivado Design Suite User Guide: High-Level Synthesis
   - UG1270: Vivado HLS Optimization Methodology Guide
   - UG1399: Vitis High-Level Synthesis User Guide

3. **竞赛文档**:
   - 命题式基础赛道初赛评分细则.md
   - SUBMISSION_GUIDE_Linux.md

---

## 最后建议

1. **优先级排序**: Pipeline > Dataflow > Memory > Clock Tuning
2. **渐进式优化**: 每次添加一种优化，立即验证
3. **时序安全优先**: 先保证 Slack > 0，再追求极致性能
4. **记录实验数据**: 建立表格记录每次优化的效果
5. **权衡扣分风险**: 若时序违例但执行时间优势 > 10 分价值，可考虑激进策略

**祝你优化成功，取得好成绩！**

