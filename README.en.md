[中文](README.md) | **English**

# FPGA Innovation Design Contest, AMD Set-Topic Basic Track — Entry

**Team ID**: 44006
**Team name**: AAA_FPGA批发

---

## Overview

This is the 2025 FPGA Innovation Design Contest entry for the AMD set-topic basic track: a
performance optimisation of Vitis Library L1 algorithms using Vitis HLS 2024.2.

## Results

| Task | Algorithm | Execution time (ns) | Speed-up | Timing |
|------|-----------|--------------------|----------|--------|
| **Task 1** | SHA-256 (HMAC) | 6,433.1 | ↓ 42.6% | ✅ met |
| **Task 2** | LZ4 Compress | 12,351 | ↓ 72.4% | ✅ met |
| **Task 3** | Cholesky (Complex) | 15,884.1 | ↓ 48.5% | ✅ met |

**Overall speed-up**: 54.5%

## Project layout

```
hlstrack2025/
├── security/L1/tests/hmac/sha256/          # Task 1: SHA-256 optimisation
│   ├── kernel/                             # Modified algorithm headers
│   └── reports/                            # Synthesis reports and simulation logs
├── data_compression/L1/tests/lz4_compress/ # Task 2: LZ4 optimisation
│   ├── kernel/                             # Modified algorithm headers
│   └── reports/                            # Synthesis reports and simulation logs
├── solver/L1/tests/cholesky/               # Task 3: Cholesky optimisation
│   └── complex_fixed_arch0/
│       ├── kernel/                         # Modified algorithm headers
│       └── reports/                        # Synthesis reports and simulation logs
└── prompts/                                # LLM-assisted optimisation records
```

## Technical specification

- **Tooling**: Vitis HLS 2024.2
- **Target device**: Zynq-7000 (xc7z020-clg484-1)
- **Objective**: minimise execution time, `T_exec = Clock_Period × Latency`
- **Verification**: C simulation and co-simulation

## Key optimisation techniques

- **SHA-256**: shift-register architecture to remove dynamic indexing, plus `Rewind` loop control.
- **LZ4**: dictionary unrolling (`UNROLL=4`), stream-depth tuning, and clock-frequency optimisation.
- **Cholesky**: `ARCH1` architecture selection, pipeline-depth tuning, and timing closure work.

## Documentation

- **Design report**: `AMD赛道命题式赛道初赛报告.pdf` — the full optimisation process and performance analysis.
- **LLM usage log**: `prompts/llm_usage.md` — detailed interactions from LLM-assisted optimisation.
- **Simulation reports**: C simulation, co-simulation, and synthesis reports under each task's `reports/`.

## Running the tests

Each task is tested as described in its own `submission_guide.md`:

```bash
# Task 1 - SHA-256
cd security/L1/tests/hmac/sha256/
make run CSIM=1 CSYNTH=1 COSIM=1

# Task 2 - LZ4
cd data_compression/L1/tests/lz4_compress/
make run CSIM=1 CSYNTH=1 COSIM=1

# Task 3 - Cholesky
cd solver/L1/tests/cholesky/complex_fixed_arch0/
make run CSIM=1 CSYNTH=1 COSIM=1
```

## Acknowledgements

Thanks to the contest organisers for the platform, to our advisor for the guidance, and to our
teammates for the collaboration.

---

**Submission date**: 2 November 2025
**Repository**: <https://github.com/hlstrack2025-44006/hlstrack2025>

> This project followed the contest rules strictly: all optimisations stayed within the permitted
> scope, functional verification is complete, and resource usage is compliant.
