# LZ4 Compress 深度优化指南
## 基于代码分析 + HLSPilot 论文 + 竞赛要求

---

## 📊 一、当前 Baseline 性能分析

### 1.1 官方 Baseline 数据（Windows Vitis 2024.2）
```
Target Clock Period:    15 ns
Estimated Clock Period: 13.220 ns
Clock Uncertainty:      1.5 ns (10% of Target)
Slack:                  15 × 0.9 - 13.220 = 1.280 ns ✅ (Pass)
Cosim Latency:          3390 cycles
执行时间:                13.220 × 3390 = 44,815.8 ns
```

### 1.2 优化目标
- **目标执行时间**: < 15,000 ns (加速 3x)
- **时序要求**: Slack > 0 (避免扣 10 分)
- **资源约束**: xc7z020-clg484-1 (LUT: 53,200, FF: 106,400, BRAM: 140, DSP: 220)

---

## 🔍 二、LZ4 Compress 代码架构深度分析

### 2.1 核心流程拆解

LZ4 压缩算法在测试文件 `lz4_compress_test.cpp` 中的调用链：

```
lz4CompressEngineRun (Top-level)
    ├─ lzCompress          (Stage 1: 字典匹配)
    ├─ lzBestMatchFilter   (Stage 2: 最佳匹配过滤)
    ├─ lzBooster           (Stage 3: 匹配长度扩展)
    └─ lz4Compress         (Stage 4: LZ4 编码)
          ├─ lz4CompressPart1 (分离 literal 和 match)
          └─ lz4CompressPart2 (状态机编码输出)
```

**已有优化**：
- ✅ Top-level 使用 `#pragma HLS dataflow` (4 个 stage 流水线)
- ✅ 所有关键循环都有 `#pragma HLS PIPELINE II=1`
- ✅ 使用 `hls::stream` 进行 stage 间通信

---

### 2.2 各模块详细分析

#### 🎯 **Stage 1: lzCompress (字典匹配) - 性能瓶颈 #1**

**位置**: `lz_compress.hpp` 第 58-168 行

**核心循环**: `lz_compress` (第 87-153 行)
```cpp
lz_compress:
for (uint32_t i = MATCH_LEN - 1; i < input_size - LEFT_BYTES; i++) {
    #pragma HLS PIPELINE II = 1
    #pragma HLS dependence variable = dict inter false
    
    // 1. 滑动窗口更新 (MATCH_LEN=6 次)
    for (int m = 0; m < MATCH_LEN - 1; m++) {
        #pragma HLS UNROLL
        present_window[m] = present_window[m + 1];
    }
    present_window[MATCH_LEN - 1] = inStream.read();
    
    // 2. 哈希计算
    uint32_t hash = (present_window[0] << 4) ^ 
                    (present_window[1] << 3) ^ 
                    (present_window[2] << 2) ^ 
                    (present_window[3]);
    
    // 3. 字典查找
    hash &= (LZ_DICT_SIZE - 1);  // LZ_DICT_SIZE = 256
    uintDictV_t dictReadValue = dict[hash];
    
    // 4. 匹配搜索 (MATCH_LEVEL=6 次并行比较)
    for (int l = 0; l < MATCH_LEVEL; l++) {
        uint8_t len = 0;
        for (int m = 0; m < MATCH_LEN; m++) {
            if (present_window[m] == compareWith[m] && !done) {
                len++;
            }
        }
        if (len > match_length) {
            match_length = len;
            match_offset = currIdx - compareIdx - 1;
        }
    }
    
    // 5. 字典更新
    dict[hash] = dictWriteValue;
    
    // 6. 输出
    outStream << outValue;
}
```

**性能瓶颈分析**:
1. ⚠️ **字典访问冲突**: `dict[hash]` 读写在同一周期，可能造成 II > 1
2. ⚠️ **嵌套循环**: MATCH_LEVEL=6 × MATCH_LEN=6 = 36 次比较操作
3. ⚠️ **关键路径**: 哈希计算 → 字典读 → 匹配比较 → 字典写

**当前优化状态**:
- ✅ `dict` 使用 `RAM_T2P` (真双端口)，支持同时读写
- ✅ 匹配循环已展开 (`#pragma HLS UNROLL`)
- ❌ 哈希计算仍在关键路径上

---

#### 🎯 **Stage 2: lzBestMatchFilter (最佳匹配过滤)**

**位置**: `lz_optional.hpp` 第 244 行

**功能**: 从 6 个候选匹配中选择最优的 offset
- ⏱️ **Latency**: 较小 (单次比较)
- 🟢 **优化空间**: 有限

---

#### 🎯 **Stage 3: lzBooster (匹配扩展)**

**位置**: `lz_optional.hpp` 第 366 行

**核心循环**: `lz_booster`
```cpp
lz_booster:
for (uint32_t i = 0; i < input_size; i++) {
    #pragma HLS PIPELINE II = 1
    
    if (tLen) {
        // 向前扩展匹配长度
        for (uint8_t j = MATCH_LEN; j < MAX_MATCH_LEN; j++) {
            #pragma HLS UNROLL
            if (inStream.read() == lookAheadBuffer[matchIdx + j]) {
                boostVal++;
            } else {
                break;
            }
        }
    }
}
```

**性能瓶颈**:
- ⚠️ **循环依赖**: `inStream.read()` 必须顺序执行
- ⚠️ **展开限制**: MAX_MATCH_LEN=255，完全展开不现实

---

#### 🎯 **Stage 4: lz4Compress (LZ4 编码) - 性能瓶颈 #2**

**位置**: `lz4_compress.hpp` 第 284-303 行

**子模块 4.1: lz4CompressPart1** (第 45-102 行)
```cpp
lz4_divide:
for (uint32_t i = 0; i < input_size;) {
    #pragma HLS PIPELINE II = 1
    
    ap_uint<32> tmpEncodedValue = nextEncodedValue;
    if (i < (input_size - 1)) 
        nextEncodedValue = inStream.read();  // 预读优化
    
    uint8_t tCh = tmpEncodedValue.range(7, 0);
    uint8_t tLen = tmpEncodedValue.range(15, 8);
    uint16_t tOffset = tmpEncodedValue.range(31, 16);
    
    if (lit_count >= MAX_LIT_COUNT) {
        lit_count_flag = 1;
    } else if (tLen) {
        // 输出 match
        ap_uint<64> tmpValue;
        tmpValue.range(63, 32) = lit_count;
        tmpValue.range(15, 0) = match_len;
        tmpValue.range(31, 16) = match_offset;
        lenOffset_Stream << tmpValue;
        lit_count = 0;
    } else {
        // 输出 literal
        lit_outStream << tCh;
        lit_count++;
    }
    
    // 动态步进
    i += (tLen ? tLen : 1);
}
```

**性能瓶颈**:
- ⚠️ **动态步进**: `i += tLen` 导致循环边界不确定
- ⚠️ **分支预测**: if-else 分支较多

**子模块 4.2: lz4CompressPart2** (第 104-258 行)
```cpp
// 6 状态状态机
enum lz4CompressStates { 
    WRITE_TOKEN, WRITE_LIT_LEN, WRITE_MATCH_LEN, 
    WRITE_LITERAL, WRITE_OFFSET0, WRITE_OFFSET1 
};

lz4_compress:
for (uint32_t inIdx = 0; (inIdx < input_size) || (!readOffsetFlag);) {
    #pragma HLS PIPELINE II = 1
    #pragma HLS DEPENDENCE variable=match_offset inter false
    #pragma HLS DEPENDENCE variable=lit_length inter false
    
    // 状态机处理
    if (next_state == WRITE_TOKEN) {
        // 解析 token
        lit_length = nextLenOffsetValue.range(63, 32);
        match_length = nextLenOffsetValue.range(15, 0);
        match_offset = nextLenOffsetValue.range(31, 16);
        
        // 决定下一状态
        if (lit_length >= 15) {
            next_state = WRITE_LIT_LEN;
        } else if (lit_length > 0) {
            next_state = WRITE_LITERAL;
        } else {
            next_state = WRITE_OFFSET0;
        }
    } else if (next_state == WRITE_LIT_LEN) {
        // 写额外的 literal 长度
    } else if (next_state == WRITE_LITERAL) {
        // 逐字节写 literal
        outValue = in_lit_inStream.read();
        write_lit_length--;
    }
    // ... 其他状态
}
```

**性能瓶颈**:
- ⚠️ **复杂状态机**: 6 个状态，分支较多
- ⚠️ **循环条件**: `(inIdx < input_size) || (!readOffsetFlag)` 复杂
- ⚠️ **位选择操作**: `range(63,32)` 等操作在关键路径上

---

## 🚀 三、针对性优化策略（基于 HLSPilot 论文）

### 3.1 Stage 1 优化: lzCompress 字典匹配

#### ✅ **优化 1.1: 数组分区 - 消除字典访问冲突**

**问题**: 字典 `dict[256]` 只有 1 个读端口和 1 个写端口，限制了并行度

**HLSPilot 策略**: Array Partition (论文 Table II)

**优化方案**:
```cpp
// 原代码
uintDictV_t dict[LZ_DICT_SIZE];  // 256 entries
#pragma HLS BIND_STORAGE variable = dict type = RAM_T2P impl = BRAM

// 优化后
uintDictV_t dict[LZ_DICT_SIZE];
#pragma HLS ARRAY_PARTITION variable=dict cyclic factor=4 dim=1
#pragma HLS BIND_STORAGE variable = dict type = RAM_T2P impl = BRAM
```

**预期效果**:
- ✅ 4 路并行访问，减少端口冲突
- ⚠️ BRAM 使用增加 4 倍 (从 ~34 个 → ~136 个，接近上限 140)
- 💡 **权衡**: 可尝试 `factor=2` (仅 2 倍资源)

---

#### ✅ **优化 1.2: 哈希计算流水线化**

**问题**: 哈希计算在循环关键路径上

**优化方案**:
```cpp
// 原代码
uint32_t hash = (present_window[0] << 4) ^ 
                (present_window[1] << 3) ^ 
                (present_window[2] << 2) ^ 
                (present_window[3]);

// 优化后 - 分级计算
uint32_t hash_part1 = (present_window[0] << 4) ^ (present_window[1] << 3);
uint32_t hash_part2 = (present_window[2] << 2) ^ present_window[3];
uint32_t hash = hash_part1 ^ hash_part2;
```

**预期效果**:
- ✅ 缩短关键路径延迟
- ✅ 可能降低 Estimated Clock Period

---

#### ✅ **优化 1.3: 字典初始化加速**

**问题**: `dict_flush` 循环初始化 256 个 entry，Latency = 128 cycles

```cpp
dict_flush:
for (int i = 0; i < LZ_DICT_SIZE; i++) {
    #pragma HLS PIPELINE II = 1
    #pragma HLS UNROLL FACTOR = 2  // 当前已有
    dict[i] = resetValue;
}
```

**优化方案**:
```cpp
dict_flush:
for (int i = 0; i < LZ_DICT_SIZE; i++) {
    #pragma HLS PIPELINE II = 1
    #pragma HLS UNROLL FACTOR = 4  // 提高到 4
    dict[i] = resetValue;
}
```

**预期效果**:
- ✅ 初始化 Latency: 128 → 64 cycles
- ⚠️ 资源增加有限 (仅初始化逻辑)

---

### 3.2 Stage 4 优化: lz4Compress 编码

#### ✅ **优化 2.1: 简化状态机逻辑**

**问题**: `lz4CompressPart2` 的状态机有 6 个状态，分支复杂

**HLSPilot 策略**: 减少分支，合并状态

**优化方案 A - 减少位选择操作**:
```cpp
// 原代码 (每次都进行位选择)
ap_uint<32> lit_len_tmp = nextLenOffsetValue.range(63, 32);
ap_uint<16> match_len_tmp = nextLenOffsetValue.range(15, 0);
ap_uint<16> match_off_tmp = nextLenOffsetValue.range(31, 16);

// 优化后 (使用本地变量缓存)
if (readOffsetFlag) {
    nextLenOffsetValue = in_lenOffset_Stream.read();
    lit_length_cached = nextLenOffsetValue.range(63, 32);
    match_length_cached = nextLenOffsetValue.range(15, 0);
    match_offset_cached = nextLenOffsetValue.range(31, 16);
    readOffsetFlag = false;
}

// 后续直接使用 cached 值
lit_length = lit_length_cached;
match_length = match_length_cached;
match_offset = match_offset_cached;
```

**优化方案 B - 预计算条件**:
```cpp
// 原代码
if (lit_length >= 15) {
    next_state = WRITE_LIT_LEN;
} else if (lit_length > 0) {
    next_state = WRITE_LITERAL;
} else {
    next_state = WRITE_OFFSET0;
}

// 优化后 - 使用查找表
const uint8_t next_state_lut[16] = {
    WRITE_OFFSET0,   // lit_length = 0
    WRITE_LITERAL,   // lit_length = 1
    WRITE_LITERAL,   // lit_length = 2
    // ...
    WRITE_LITERAL,   // lit_length = 14
    WRITE_LIT_LEN    // lit_length = 15
};
next_state = (lit_length < 15) ? next_state_lut[lit_length] : WRITE_LIT_LEN;
```

**预期效果**:
- ✅ 减少关键路径上的 MUX 层数
- ✅ 可能降低 Estimated Clock Period 0.5-1 ns

---

#### ✅ **优化 2.2: Stream 深度调优**

**当前配置**:
```cpp
#pragma HLS STREAM variable = lit_outStream depth = (MAX_LIT_COUNT > 64 ? MAX_LIT_COUNT : 64)  // 4096
#pragma HLS STREAM variable = lenOffset_Stream depth = (c_gmemBurstSize * 4)  // 128
#pragma HLS BIND_STORAGE variable = lenOffset_Stream type = FIFO impl = BRAM
```

**问题**: `lit_outStream` 深度过大 (4096)，占用 BRAM

**优化方案**:
```cpp
// 减小深度 (根据实际数据流速率)
#pragma HLS STREAM variable = lit_outStream depth = 512  // 从 4096 减少
#pragma HLS BIND_STORAGE variable = lit_outStream type = FIFO impl = BRAM
```

**预期效果**:
- ✅ 节省 BRAM: ~30 个 → ~8 个
- ⚠️ 需验证不会造成 dataflow 阻塞

---

### 3.3 Top-level Dataflow 优化

#### ✅ **优化 3.1: 检查 Dataflow 平衡性**

**当前状态**: 4 个 stage 流水线

**分析工具**: 查看综合报告的 "Dataflow Report"

**优化思路**:
1. 识别最慢的 stage (Latency 最大)
2. 将慢 stage 进一步分解为子任务
3. 确保各 stage Latency 相近 (平衡流水线)

**示例 - 如果 lzCompress 是瓶颈**:
```cpp
// 原来是单个函数
lzCompress(inStream, compressdStream, input_size);

// 分解为两个子任务
#pragma HLS dataflow
lzCompress_hash(inStream, hashStream, input_size);
lzCompress_match(hashStream, compressdStream, input_size);
```

---

### 3.4 时钟频率优化策略

#### ✅ **优化 4.1: 激进高频方案 (目标 8-10 ns)**

**修改文件**: `hls_config.tmpl` 或 `run_hls.tcl`

**方案 A - 平衡策略**:
```tcl
# 原配置
create_clock -period 15

# 优化后
create_clock -period 10
config_schedule -enable_dsp_full_reg=1
```

**预期结果**:
```
Target = 10 ns
Estimated ≈ 8.5-9.5 ns (需实测)
Slack = 10 × 0.9 - 9.0 = 0 ns (边缘安全)
Latency ≈ 3000 cycles (假设优化 10%)
执行时间 = 9.0 × 3000 = 27,000 ns
加速比 = 44815.8 / 27000 = 1.66x
```

**方案 B - 激进策略**:
```tcl
create_clock -period 7
config_compile -pipeline_style=flp
```

**预期结果**:
```
Target = 7 ns
Estimated ≈ 6.5-7.2 ns (可能时序违例)
Slack = 7 × 0.9 - 7.2 = -0.9 ns ⚠️ (扣 10 分)
Latency ≈ 3000 cycles
执行时间 = 7.0 × 3000 = 21,000 ns
加速比 = 44815.8 / 21000 = 2.13x
```

**决策**:
- 若其他优化使 Latency 降至 2000 cycles，方案 B 更优
- 若 Latency 仅降至 2800 cycles，方案 A 更安全

---

## 📋 四、分阶段优化执行计划

### Phase 1: 低风险优化（先保证时序安全）

| 优化项 | 修改文件 | 预期 Latency 减少 | 预期时序影响 | 优先级 |
|--------|---------|------------------|-------------|--------|
| 字典初始化加速 (UNROLL=4) | `lz_compress.hpp` | -64 cycles | 无影响 | ⭐⭐⭐ |
| Stream 深度调优 | `lz4_compress.hpp` | 0 cycles | 节省 BRAM | ⭐⭐ |
| 预计算条件简化 | `lz4_compress.hpp` | -50 cycles | 改善 0.5ns | ⭐⭐⭐ |
| 时钟频率 15→12 ns | `hls_config.tmpl` | 0 cycles | 安全 | ⭐⭐⭐ |

**预期结果**:
```
Latency: 3390 → 3276 cycles (-3.4%)
Clock: 13.220 → 10.5 ns (Target=12, Estimated≈10.5)
执行时间: 44815.8 → 34396.8 ns (1.30x)
Slack: 12×0.9 - 10.5 = +0.3 ns ✅
```

---

### Phase 2: 中等风险优化（激进 Latency 优化）

| 优化项 | 修改文件 | 预期 Latency 减少 | 预期时序影响 | 风险 |
|--------|---------|------------------|-------------|------|
| 字典分区 (factor=2) | `lz_compress.hpp` | -200 cycles | BRAM +34 | 中 |
| 哈希计算流水线化 | `lz_compress.hpp` | -100 cycles | 改善 0.5ns | 低 |
| 状态机优化 | `lz4_compress.hpp` | -150 cycles | 改善 0.8ns | 中 |
| 时钟频率 12→9 ns | `hls_config.tmpl` | 0 cycles | Slack 边缘 | 高 |

**预期结果**:
```
Latency: 3276 → 2826 cycles (-16.6%)
Clock: 10.5 → 8.2 ns (Target=9, Estimated≈8.2)
执行时间: 34396.8 → 23173.2 ns (1.93x)
Slack: 9×0.9 - 8.2 = +0.9 ns ✅
```

---

### Phase 3: 高风险优化（冲击最佳成绩）

| 优化项 | 修改文件 | 预期 Latency 减少 | 预期时序影响 | 风险 |
|--------|---------|------------------|-------------|------|
| 字典分区 (factor=4) | `lz_compress.hpp` | -300 cycles | BRAM +102 ⚠️ | 高 |
| lzCompress 二级流水线 | `lz_compress.hpp` | -400 cycles | 复杂重构 | 极高 |
| 时钟频率 9→6 ns | `hls_config.tmpl` | 0 cycles | 可能违例 | 极高 |

**预期结果 (最优情况)**:
```
Latency: 2826 → 2126 cycles (-24.8%)
Clock: 8.2 → 5.8 ns (Target=6, Estimated≈5.8)
执行时间: 23173.2 → 12330.8 ns (3.63x) 🏆
Slack: 6×0.9 - 5.8 = -0.4 ns ⚠️ (扣 10 分)
```

**决策**:
- 若能保证 Slack > 0，Phase 2 已能获得优秀成绩
- Phase 3 适合冲击榜首，但需权衡扣分风险

---

## 🔧 五、具体代码修改示例

### 示例 1: lz_compress.hpp - 字典初始化加速

**位置**: 第 73-78 行

```cpp
// ========== 原代码 ==========
dict_flush:
for (int i = 0; i < LZ_DICT_SIZE; i++) {
    #pragma HLS PIPELINE II = 1
    #pragma HLS UNROLL FACTOR = 2
    dict[i] = resetValue;
}

// ========== 优化后 ==========
dict_flush:
for (int i = 0; i < LZ_DICT_SIZE; i++) {
    #pragma HLS PIPELINE II = 1
    #pragma HLS UNROLL FACTOR = 4  // 🔧 修改点 1: 2 → 4
    dict[i] = resetValue;
}
```

**验证**:
- 运行 `make run TARGET=csim` - 必须 PASS
- 检查综合报告: `dict_flush` 的 Trip Count 应为 64 (256/4)

---

### 示例 2: lz_compress.hpp - 字典数组分区

**位置**: 第 64-67 行

```cpp
// ========== 原代码 ==========
uintDictV_t dict[LZ_DICT_SIZE];
#pragma HLS BIND_STORAGE variable = dict type = RAM_T2P impl = BRAM

// ========== 优化后 (保守) ==========
uintDictV_t dict[LZ_DICT_SIZE];
#pragma HLS ARRAY_PARTITION variable=dict cyclic factor=2 dim=1  // 🔧 修改点 2
#pragma HLS BIND_STORAGE variable = dict type = RAM_T2P impl = BRAM

// ========== 优化后 (激进) ==========
uintDictV_t dict[LZ_DICT_SIZE];
#pragma HLS ARRAY_PARTITION variable=dict cyclic factor=4 dim=1  // 🔧 修改点 2 (激进)
#pragma HLS BIND_STORAGE variable = dict type = RAM_T2P impl = BRAM
```

**验证**:
- 检查综合报告 `Resource Utilization`: BRAM 不能超过 140
- 若超限，改回 `factor=2` 或移除分区

---

### 示例 3: lz4_compress.hpp - Stream 深度调优

**位置**: 第 294-295 行

```cpp
// ========== 原代码 ==========
#pragma HLS STREAM variable = lit_outStream depth = (MAX_LIT_COUNT > 64 ? MAX_LIT_COUNT : 64)  // 4096
#pragma HLS STREAM variable = lenOffset_Stream depth = (c_gmemBurstSize * 4)  // 128

// ========== 优化后 ==========
#pragma HLS STREAM variable = lit_outStream depth = 512  // 🔧 修改点 3: 4096 → 512
#pragma HLS STREAM variable = lenOffset_Stream depth = 256  // 🔧 修改点 4: 128 → 256
#pragma HLS BIND_STORAGE variable = lit_outStream type = FIFO impl = BRAM
```

**验证**:
- 运行 `make run TARGET=cosim` - 必须 PASS
- 若出现 deadlock，逐步增加深度 (512 → 1024 → 2048)

---

### 示例 4: lz4_compress.hpp - 状态机简化 (高级)

**位置**: 第 147-198 行

```cpp
// ========== 原代码片段 ==========
if (next_state == WRITE_TOKEN) {
    lit_length = lit_len_tmp;
    match_length = match_len_tmp;
    match_offset = match_off_tmp;
    
    // ... 复杂逻辑
    if (lit_length >= 15) {
        next_state = WRITE_LIT_LEN;
    } else if (lit_length > 0) {
        next_state = WRITE_LITERAL;
    } else {
        next_state = WRITE_OFFSET0;
    }
}

// ========== 优化后 - 预计算 ==========
if (next_state == WRITE_TOKEN) {
    // 🔧 修改点 5: 提前缓存位选择结果
    lit_length = lit_length_cached;
    match_length = match_length_cached;
    match_offset = match_offset_cached;
    
    // 🔧 修改点 6: 使用三元运算符减少分支
    bool lit_ge_15 = (lit_length >= 15);
    bool lit_gt_0 = (lit_length > 0);
    next_state = lit_ge_15 ? WRITE_LIT_LEN : 
                 (lit_gt_0 ? WRITE_LITERAL : WRITE_OFFSET0);
}
```

---

### 示例 5: hls_config.tmpl - 时钟频率调整

**位置**: `L1/tests/lz4_compress/hls_config.tmpl`

```bash
# ========== 原配置 ==========
[hls]
clock=15

# ========== 优化后 (Phase 1: 保守) ==========
[hls]
clock=12

# ========== 优化后 (Phase 2: 平衡) ==========
[hls]
clock=9

# ========== 优化后 (Phase 3: 激进) ==========
[hls]
clock=6
```

---

## 📊 六、验证与评估流程

### Step 1: 编译与仿真
```bash
cd /home/zxw/project/hlstrack2025/data_compression/L1/tests/lz4_compress
export XPART=xc7z020-clg484-1

# 1. C 仿真 (必须 PASS)
make clean
make run TARGET=csim

# 2. HLS 综合
make run TARGET=csynth

# 3. Co-simulation (获取 Latency)
make run TARGET=cosim
```

### Step 2: 提取关键指标

**从 `hls/reports/hls_compile.rpt` 提取**:
```bash
grep -A 5 "Timing Summary" hls/reports/hls_compile.rpt
```

**输出示例**:
```
    |  Clock  |  Target | Estimated| Uncertainty|
    +---------+---------+----------+------------+
    |default  |  10.00  |   8.532  |    1.00    |
```

**从 Co-simulation 报告提取 Latency**:
```bash
grep "Latency" hls/reports/*_cosim.rpt
```

### Step 3: 计算最终得分

**公式**:
```
Slack = (Target × 0.9) - Estimated
执行时间 = Estimated × Latency
加速比 = 44815.8 / 执行时间

如果 Slack > 0:
    Score = 100 × (44815.8 - 执行时间) / (44815.8 - T_best)
否则:
    Score = 100 × (44815.8 - 执行时间) / (44815.8 - T_best) - 10
```

---

## 🎯 七、优化目标与预期成绩

### 目标 1: 及格线 (1.5x 加速)
```
执行时间: < 30,000 ns
Latency: < 3000 cycles
Clock: 10 ns (Estimated ≈ 9 ns, Slack > 0)
优化难度: ⭐⭐
预期得分: 60-70 分
```

### 目标 2: 优秀线 (2x 加速)
```
执行时间: < 22,500 ns
Latency: < 2500 cycles
Clock: 9 ns (Estimated ≈ 8 ns, Slack > 0)
优化难度: ⭐⭐⭐
预期得分: 75-85 分
```

### 目标 3: 满分线 (3x+ 加速)
```
执行时间: < 15,000 ns
Latency: < 2000 cycles
Clock: 7-8 ns (Estimated ≈ 6.5-7.5 ns, Slack 边缘)
优化难度: ⭐⭐⭐⭐⭐
预期得分: 90-100 分
```

---

## 📚 八、参考资料与工具

### 论文参考
- **HLSPilot 论文**: 第 III-C 节 (LLM-based Automatic HLS Optimization)
- **Table II**: Major Optimization Strategies Used

### Xilinx 官方文档
1. **UG902**: Vivado HLS User Guide
   - Chapter 3: High-Level Synthesis Pragmas
   - Section 3.2: ARRAY_PARTITION
   - Section 3.7: PIPELINE

2. **UG1270**: HLS Optimization Methodology Guide
   - Chapter 2: Dataflow Optimization
   - Chapter 4: Memory Optimization

3. **UG1399**: Vitis HLS User Guide (2024.2)
   - Appendix A: Pragma Quick Reference

### 在线工具
- **GenHLSOptimizer**: 自动 DSE 工具 (https://github.com/aferikoglou/GenHLSOptimizer)

---

## ✅ 优化检查清单

**Phase 1 完成后**:
- [ ] C Simulation 通过
- [ ] Latency < 3000 cycles
- [ ] Estimated Clock < 10 ns
- [ ] Slack > 0
- [ ] BRAM < 140

**Phase 2 完成后**:
- [ ] Co-simulation 通过
- [ ] 执行时间 < 25,000 ns
- [ ] Slack > 0 (时序安全)
- [ ] 资源不超限

**Phase 3 完成后**:
- [ ] 执行时间 < 15,000 ns
- [ ] 已权衡时序违例扣分风险
- [ ] 已填写 `prompts/llm_usage.md`
- [ ] 报告已复制到 `reports/` 目录

---

## 🎓 最后建议

1. **渐进式优化**: 每次修改一个优化点，立即验证
2. **版本管理**: 使用 git 分支管理不同优化方案
3. **记录数据**: 建立表格记录每次优化的 Latency、Clock、Slack
4. **时序优先**: 先保证 Slack > 0，再追求极致性能
5. **资源监控**: 实时检查 BRAM/LUT 使用情况

**祝你优化成功，取得好成绩！🚀**



