# FPGA创新设计大赛 AMD赛道命题式基础赛道 - 参赛项目

**团队编号**：44006  
**团队名称**：AAA_FPGA批发  


---

## 项目概述

本项目为2025年FPGA创新设计大赛AMD赛道命题式基础赛道的参赛作品，基于Vitis HLS 2024.2对Vitis Library L1算法进行性能优化。

## 优化成果

| 题目 | 算法 | 执行时间(ns) | 性能提升 | 时序状态 |
|------|------|-------------|---------|---------|
| **题目1** | SHA-256 (HMAC) | 6,433.1 | ↓ 42.6% | ✅ 通过 |
| **题目2** | LZ4 Compress | 12,351 | ↓ 72.4% | ✅ 通过 |
| **题目3** | Cholesky (Complex) | 15,884.1 | ↓ 48.5% | ✅ 通过 |

**综合性能提升**：54.5%

## 项目结构

```
hlstrack2025/
├── security/L1/tests/hmac/sha256/          # 题目1: SHA-256优化
│   ├── kernel/                             # 修改后的算法头文件
│   └── reports/                            # 综合报告与仿真日志
├── data_compression/L1/tests/lz4_compress/ # 题目2: LZ4优化
│   ├── kernel/                             # 修改后的算法头文件
│   └── reports/                            # 综合报告与仿真日志
├── solver/L1/tests/cholesky/               # 题目3: Cholesky优化
│   └── complex_fixed_arch0/
│       ├── kernel/                         # 修改后的算法头文件
│       └── reports/                        # 综合报告与仿真日志
└── prompts/                                # LLM辅助优化记录
```

## 技术规格

- **开发工具**：Vitis HLS 2024.2
- **目标器件**：Zynq-7000 (xc7z020-clg484-1)
- **优化目标**：最小化执行时间 `T_exec = Clock_Period × Latency`
- **验证标准**：通过C Simulation和Co-simulation功能验证

## 主要优化技术

- **SHA-256**：移位寄存器架构消除动态索引，Rewind优化循环控制
- **LZ4**：字典展开(UNROLL=4) + Stream深度调优 + 时钟频率优化
- **Cholesky**：ARCH1架构选择 + 流水线深度优化 + 时序收敛调优

## 文档说明

- **设计报告**：`AMD赛道命题式赛道初赛报告.pdf` - 包含完整的优化过程与性能分析
- **LLM使用记录**：`prompts/llm_usage.md` - 大模型辅助优化的详细交互记录
- **仿真报告**：各题目`reports/`目录下的C仿真、联合仿真和综合报告

## 运行测试

各题目的测试方法与相应目录下的`submission_guide.md`一致：

```bash
# 题目1 - SHA-256
cd security/L1/tests/hmac/sha256/
make run CSIM=1 CSYNTH=1 COSIM=1

# 题目2 - LZ4
cd data_compression/L1/tests/lz4_compress/
make run CSIM=1 CSYNTH=1 COSIM=1

# 题目3 - Cholesky
cd solver/L1/tests/cholesky/complex_fixed_arch0/
make run CSIM=1 CSYNTH=1 COSIM=1
```

## 致谢

感谢大赛组委会提供的学习与竞技平台，感谢指导教师的悉心指导，感谢队友们的通力协作。

---

**提交日期**：2025年11月2日  
**仓库地址**：https://github.com/hlstrack2025-44006/hlstrack2025

> 本项目严格遵守竞赛规则，所有优化均在允许范围内进行，功能验证完整，资源使用合规。
