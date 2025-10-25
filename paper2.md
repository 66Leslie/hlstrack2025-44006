

<!-- Meanless: (Special Session)-->

# TimelyHLS: LLM-Based Timing-Aware and Architecture-Specific FPGA HLS Optimization

Nowfel Mashnoor, Mohammad Akyash, Hadi Kamali, Kimia Azar

Department of Electrical and Computer Engineering (ECE), University of Central Florida, Orlando, FL 32816, USA \{nowfel.mashnoor, mohammad.akyash, kamali, azar\}@ucf.edu

Abstract-Achieving timing closure and design-specific optimizations in FPGA-targeted High-Level Synthesis (HLS) remains a significant challenge due to the complex interaction between architectural constraints, resource utilization, and the absence of automated support for platform-specific pragmas. In this work, we propose TimelyHLS, a novel framework integrating Large Language Models (LLMs) with Retrieval-Augmented Generation (RAG) to automatically generate and iteratively refine HLS code optimized for FPGA-specific timing and performance requirements. TimelyHLS is driven by a structured architectural knowledge base containing FPGA-specific features, synthesis directives, and pragma templates. Given a kernel, TimelyHLS generates HLS code annotated with both timing-critical and design-specific pragmas. The synthesized RTL is then evaluated using commercial toolchains, and simulation correctness is verified against reference outputs via custom testbenches. TimelyHLS iteratively incorporates synthesis logs and performance reports into the LLM engine for refinement in the presence of functional discrepancies. Experimental results across 10 FPGA architectures and diverse benchmarks show that TimelyHLS reduces the need for manual tuning by up to ${70}\%$ ,while achieving up to $4 \times$ latency speedup (e.g., ${3.85} \times$ for Matrix Multiplication, ${3.7} \times$ for Bitonic Sort) and over ${50}\%$ area savings in certain cases (e.g., ${57}\% \mathrm{{FF}}$ reduction in Viterbi). TimelyHLS consistently achieves timing closure and functional correctness across platforms, highlighting the effectiveness of LLM-driven, architecture-aware synthesis in automating FPGA design.

Index Terms-FPGA, Large Language Models, High-Level Synthesis, Timing Closure, Retrieval-Augmented Generation

## I. INTRODUCTION

FPGAs provide a flexible platform for accelerating diverse algorithms, but achieving timing closure on FPGAs remains a persistent challenge [1]. Timing closure entails ensuring that all signal paths meet the FPGA's timing constraints (setup/hold times, clock delays, etc.), and it is critical for correct operation at the target clock frequency [2]. In practice, reaching timing closure is an iterative and complex process, hindered by high clock rates, large and interconnected designs, and physical effects like routing delays [3]. Modern FPGA design flows often demand manual tuning and optimization to meet timing, especially when using High-Level Synthesis (HLS) tools to generate hardware from $\mathrm{C}/\mathrm{C} +  +$ code [4],[5].

HLS tools such as Xilinx Vitis HLS [6] raise the design abstraction to high-level code, but they still rely heavily on user guidance to produce efficient, timing-compliant hardware [7]. In particular, performance-critical optimizations (e.g. loop pipelining, loop unrolling, memory partitioning) are typically controlled by pragmas or directives embedded in the HLS source [8]. Selecting the right combination of pragmas for a given design and FPGA is a non-trivial task that often requires deep hardware expertise [9].

Currently, there is a lack of automated support within HLS tools for platform-specific pragmas (i.e. directives tailored to a specific FPGA architecture or vendor). Each FPGA platform introduces unique resources and constraints, which often necessitates different pragmas or coding styles. Designers must manually adapt and tune their HLS code for each target device, since a pragma that works well (or is even recognized) on one toolchain may not apply on another [10]. For instance, a designer targeting Xilinx FPGAs might use the PIPELINE pragma to improve loop initiation intervals, while Intel's HLS compiler requires a different pragma (ivdep) or coding convention to achieve similar results [11].

To ease the challenges of HLS optimization, researchers have developed automated methods like Design Space Exploration (DSE) frameworks [12], [13], which search large pragma spaces to find configurations with good Quality of Results (QoR). Tools such as AutoDSE [14] use heuristic searches but require many HLS runs, making them slow. Analytical methods, like formulating pragma selection as a non-linear optimization problem [8], reduce this cost by pruning poor choices. ML-based tools (e.g., HARP [15]) predict performance to guide optimizations more efficiently. However, models often struggle to generalize to new designs or architectures [10]. Despite progress, fully automated, widely adopted solutions remain lacking, especially for timing-driven optimization, leaving designers to rely on manual tuning.

Recent advances in Large Language Models (LLMs) have opened new possibilities in automating HLS optimization for FPGA design [7], [16], [17]. Tools like LIFT [16] fine-tune LLMs with Graph Neural Network (GNN) analyses to insert pragmas,achieving up to ${3.5} \times$ speedup over prior methods. HLSPilot [7] uses in-context learning and retrieval from vendor docs, combining DSE and profile-guided refinement to produce results comparable to expert designs. However, prompting general LLMs without domain-specific context can significantly degrade performance [18], demonstrating the need for integrated domain knowledge and feedback.

Despite recent progress, HLS-based FPGA design continues to face two critical challenges: (i) ensuring that synthesized designs meet strict timing requirements, which is complicated by factors like deep logic pipelines, routing congestion, and critical paths that are difficult to predict and optimize at a high level; and (ii) adapting optimizations to the unique characteristics of each FPGA architecture, where vendor-specific toolchains, resource constraints, and low-level features often necessitate custom pragma configurations and design patterns that do not generalize across platforms. These issues contribute to a persistent "closure gap" that current tools struggle to overcome without huge manual intervention.

---

<!-- Footnote -->

979-8-3315-2037-3/25/\$31.00 ©2025 IEEE

<!-- Footnote -->

---

<!-- Meanless: をなったことがあるときできることで、ここで、ここで、ここで、ここでは、ここでは、ここでは Authorized licensed use limited to: NANJING NORMAL UNIVERSITY. Downloaded on October 24,2025 at 05:37:48 UTC from IEEE Xplore. Restrictions apply.-->


To address these limitations, we propose TimelyHLS, a framework that combines LLMs with retrieval-augmented generation (RAG) and iterative refinement. TimelyHLS is guided by a structured knowledge base encoding FPGA-specific features, pragmas, and optimization heuristics. The LLM queries this knowledge during inference to generate HLS code tailored to the target architecture. This initial generation is followed by an iterative loop: synthesized RTL is evaluated using commercial tools, testbenches verify functional correctness, and synthesis logs are fed back into the model. The LLM then revises the code based on this feedback until the design achieves timing closure and correctness ${}^{1}$ . We evaluate TimelyHLS on various FPGA devices and benchmark kernels. Results show that TimelyHLS reduces manual iterations, consistently meets timing constraints, and delivers performance comparable to hand-tuned designs. Our contributions include:

(i) LLM + RAG for FPGA HLS: We propose TimelyHLS, the first framework to integrate an LLM with RAG for FPGA-specific HLS code generation. By grounding the model in a curated knowledge base of FPGA-specific architectural features, synthesis directives, and pragma strategies, TimelyHLS generates HLS code tailored to the target device.

(ii) Iterative Refinement with Tool Feedback: TimelyHLS employs an iterative refinement loop where synthesis reports, timing analysis, and functional verification feedback are reintegrated into the LLM. This enables the model to progressively resolve timing violations and improve design quality in a closed-loop, minimizing the need for manual tuning.

(iii) Effective Timing Closure/Optimization: Extensive experiments show that TimelyHLS achieves timing closure at an acceptable oveheard (area) across diverse FPGAs while significantly reducing manual intervention. It delivers performance and overall QoR (latency, area, timing) on par with, and in many cases exceeding, expert-optimized HLS designs.

## II. Related Works

Early work on automating HLS optimization used heuristic search and static modeling to explore the design space of synthesis directives (pragmas) [19] ${}^{2}$ . OpenTuner [19],a general auto-tuning framework adapted for HLS that orchestrates many search strategies (greedy, genetic algorithms, simulated annealing, etc.) via a multi-armed bandit approach. By dynamically choosing among strategies, OpenTuner effectively navigated large pragma spaces, often finding better solutions than any single algorithm alone. AutoDSE [14], a DSE tool that iteratively tunes one pragma at a time, always addressing the current performance bottleneck. By focusing on the most critical optimization step-by-step, AutoDSE achieved expert-level results with far fewer directives. Many DSE frameworks employed simulated annealing [20] or hill-climbing [21] to automate pragma selection. These rule-based searches marked a big step in reducing engineering effort. However, purely heuristic approaches can miss global optima or get stuck in local optima, especially in very large parameter spaces.

Complementing above search techniques, analytical modeling approaches sought to speed up exploration by predicting HLS outcomes without full synthesis. Tools like Lin-Analyzer [22], COMBA [23], and more recently ScaleHLS [24], use static code analysis (e.g., loop dependence graphs, pipeline initiation interval formulas) to estimate a design's latency and resource usage under different pragma choices. By evaluating design points with these mathematical models, unpromising configurations can be pruned orders of magnitude faster than actually synthesizing them. In practice, these models often need re-tuning for each tool or hardware target, and they handle only a subset of possible pragmas or code structures (to keep the formulas tractable). As a result, analytical estimation is usually used as a component in a larger system.

Recent work has explored learning-based methods. ML frameworks like HARP [15] use surrogate models, often GNNs to predict performance from code and pragma configurations, enabling rapid DSE without full synthesis. Bayesian optimization (BO) tools like Sherlock [17] further improve efficiency by prioritizing high-potential candidates through probabilistic modeling, excelling in multi-objective tuning.

Reinforcement learning (RL) frames HLS as sequential decision-making, where agents learn to apply transformations or insert pragmas to improve performance. Methods like AutoAnnotate [25] report up to $4 \times$ speedup,though RL faces challenges with large design spaces and training times. Hybrid solutions like AutoHLS [26] combine neural prediction with BO to prune poor candidates,achieving up to ${70} \times$ speedup.

LLM-based approaches, which are heavily in use in Register Transfer Language (RTL) design and verification [27]- [29], aim to generate optimized HLS code directly. While general-purpose models like GPT-4 struggle without domain grounding, LIFT [16] improves results by fine-tuning on ${40}\mathrm{k} +$ annotated HLS samples with graph-based features, achieving ${3.5} \times$ speedup over baselines. However,it lacks adaptability to new platforms and toolchains. HLSPilot [7] uses RAG, guiding the LLM with relevant HLS examples and vendor-specific rules at inference time. It enables structural code transformations and rivals expert performance.

Building on this, proposed TimelyHLS enhances adaptability by dynamically querying an evolving, platform-aware knowledge base during generation. This ensures that all optimizations are context-aware, verifiable, and tailored to current toolchains, avoiding hallucinated or outdated directives.

---

<!-- Footnote -->

${}^{1}$ While TimelyHLS mainly focuses on improving timing closure with functional correctness, the same flow can be used for power/area efficiency (if targeted and needed by the design specification).

${}^{2}$ Exhaustive search is infeasible as the combination of directives,e.g.,loop unrolling, pipelining, memory partitioning, etc. grows exponentially, so studies applied heuristics to guide DSE without brute force.

<!-- Footnote -->

---

<!-- Meanless: Authorized licensed use limited to: NANJING NORMAL UNIVERSITY. Downloaded on October 24,2025 at 05:37:48 UTC from IEEE Xplore. Restrictions apply.-->


<!-- Media -->

<!-- figureText: Prompting LLM First Verification Stage Second Verification Stage HLS Code .v code Compile HLS code in Vitis - Export RTL from Vitis - Run C++ testbench Synthesize with Vivado - Check functional correctness - Run Verilog testbench Extract timing & synthesis logs Detect WNS/TNS violations Second Feedback Check RTL Sim Correctness Send Issues to LLM for fix Data FPGA Extract Specs Open-source - Select benchmark (e.g., HLS Code matrix mul, FIR filter) - Load C++ and testbench - Use RAG to fetch constraints - Retrieve FPGA specs (DSPs, Generate HLS code with pragmas LUTs, BRAMs) - Align code with target FPGA - Format specs into structured input (e.g., Parse Vitis logs JSON/dictionary) Detect Syntax/runtime errors - Tag benchmark with known First Feedback Identify failed pragmas or loop synthesis issues Prompts LLM for Correction -->

<img src="https://cdn.noedgeai.com/bo_d3th2cref24c73d1s6ag_2.jpg?x=147&y=141&w=1508&h=414&r=0"/>

Fig. 1: Overview of TimelyHLS Framework.

<!-- Media -->

## III. OVERVIEW OF TIMELYHLS

The TimelyHLS framework automates timing-aware HLS code generation through a combination of LLM, RAG, and iterative synthesis feedback. Fig. 1, shows the top view of TimelyHLS framework. The workflow operates in two main verification stages, HLS-level and RTL-level, and leverages FPGA-specific knowledge to guide the model toward platform-compliant and timing-closure-friendly designs. To accomplish optimization for speed-up, the TimelyHLS framework consists of four main components, which are as follows:

## A. Dataset Collection

To establish (and evaluate) our framework, we curated a dataset of real-world HLS design examples gathered from open-source repositories, e.g., CHStone [30], LegUp benchmarks [31], and MachSuite [32]. These repositories provide diverse $\mathrm{C}/\mathrm{C} +  +$ programs widely used in HLS,covering a range of computational domains. We selected 10 representative HLS applications that reflect common optimization bottlenecks in FPGA synthesis, including timing violations, long critical paths, inefficient pipelining, and suboptimal resource allocation. A detailed description of each benchmark and its associated synthesis challenge is provided in Table I.

For each benchmark, we developed corresponding HLS C++ source files as well as custom testbenches to verify functional correctness during simulation and synthesis. All designs were compiled and analyzed using the Xilinx Vitis HLS toolchain. To ensure architectural diversity and practical relevance, we evaluated each design across 10 distinct FPGA targets spanning multiple device families. For each FPGA architecture, we collected synthesis reports, timing summaries, and resource utilization logs. Additionally, we captured the output of testbench simulations to verify functional correctness. This comprehensive dataset, which includes source code, testbenches, and tool-generated logs across multiple architectures, forms the basis for evaluating the effectiveness of our proposed LLM-based (prompting) TimelyHLS framework.

## B. Prompting LLM for Initial Code Generation

For each sample in our dataset, we craft a task-specific prompt that describes the functionality and performance objectives of the design (e.g., loop behavior, target throughput, or memory access constraints). This prompt is paired with target FPGA metadata (i.e. device family, number of DSPs, BRAMs, LUTs, and timing constraints as part of a RAG pipeline). The architectural specifications are embedded from datasheets and vendor tool documentation into a structured knowledge base.

<!-- Media -->

TABLE I: HLS Selected Benchmarks with Synthesis Challenges (Timing-wise) Targeted and Used in TimelyHLS.

<table><tr><td>Application</td><td>Optimization Challenge</td></tr><tr><td>Matrix Multiplication</td><td>Long critical path due to nested loops; loop pipelining inefficiencies.</td></tr><tr><td>Convolution</td><td>Timing violations caused by inefficient memory access and computation overlap.</td></tr><tr><td>Vector Dot Product</td><td>Underutilized resources and insufficient parallelism.</td></tr><tr><td>Vector Addition</td><td>Suboptimal loop unrolling with moderate timing slack.</td></tr><tr><td>Bitonic Sort</td><td>Deep logic pipelines leading to routing congestion and critical path delays.</td></tr><tr><td>Viterbi Decoder</td><td>Control dependencies causing resource contention.</td></tr><tr><td>Adaptive FIR Filter (LMS)</td><td>Feedback loop latency and failed timing closure due to iteration dependencies.</td></tr><tr><td>CORDIC Algorithm</td><td>Inefficient pipelining due to iterative data dependencies.</td></tr><tr><td>Matrix-Vector Multiplication</td><td>Memory partitioning bottlenecks leading to timing degradation.</td></tr><tr><td>Needleman-Wunsch (DP)</td><td>Irregular memory access patterns causing critical path delay and low throughput.</td></tr></table>

<!-- Media -->

We then query the LLM (e.g., Code LLaMA or GPT-4) with the prompt and retrieved FPGA constraints to generate HLS-compliant $\mathrm{C}/\mathrm{C} +  +$ code. The model is expected to insert relevant synthesis directives (pragmas) such as #pragma HLS pipeline, unroll, or array_partition, aligned with the resource capabilities of the target device.

## C. HLS-Level Verification and Correction

The generated HLS code is compiled and simulated using Xilinx Vitis ${\mathrm{{HLS}}}^{3}$ ,paired with the testbench we previously crafted for each benchmark. This first stage ensures that the model's output is functionally correct and synthesizable at the C level. If the compilation fails or the functional simulation does not produce expected results, we extract relevant information from Vitis logs (e.g., syntax errors, resource binding issues, or pipeline depth violations) and return this feedback to the LLM in the form of an augmented prompt. The LLM is asked to revise its output to address the specific failures. This process is repeated iteratively until the design passes both HLS synthesis and functional simulation.

---

<!-- Footnote -->

${}^{3}$ All prompts and scripts are configurable (parametrized) to be reusable for different vendors (to be easily used with different toolsets.

<!-- Footnote -->

---

<!-- Meanless: Authorized licensed use limited to: NANJING NORMAL UNIVERSITY. Downloaded on October 24,2025 at 05:37:48 UTC from IEEE Xplore. Restrictions apply.-->


## D. RTL-Level Verification and Timing Evaluation

Once the HLS design passes the first verification stage, we export the RTL (Verilog) output and proceed with the second stage using Xilinx Vivado. In this phase, we generate the corresponding Verilog testbenches and synthesize the design for the selected FPGA target. Vivado's post-synthesis reports are then used to evaluate timing closure (e.g., Worst Negative Slack (WNS), Total Negative Slack (TNS)), resource utilization, and syntactic validity of the RTL. We also simulate the design at the RTL level using the generated testbenches to verify behavioral equivalence with the HLS-level outputs. If the synthesizer (i.e., Xilinx Vivado) fails to synthesize the design or simulation results deviate from the expected output, we extract detailed logs, including synthesis errors, critical path reports, and functional mismatches and pass them as feedback to the LLM. This closes the second loop of iterative refinement, allowing the model to correct deeper architectural or low-level issues not observable during HLS.

This two-stage refinement loop continues until the design satisfies these criteria: (i) Passes functional simulation in both HLS and RTL levels; (ii) Is synthesizable by Vivado for the target FPGA architecture; and (iii) Meets timing closure requirements with no negative slack.

By integrating FPGA-specific architectural guidance into generation and leveraging compiler logs as feedback, Time-lyHLS transforms the traditional trial-and-error-based HLS optimization into an automated, LLM-driven pipeline.

## IV. EXPERIMENTAL SETUP

## A. Experimental Environment and Tools

All experiments were conducted on a Linux-based development environment (Ubuntu 24.04.2 LTS) using Xilinx Vitis HLS (Version 2024.2) for HLS and Vivado (Version 2024.2) for RTL synthesis and implementation. The experimental infrastructure consisted of 13th Gen Intel(R) Core(TM) i7-13700 Processor and 32GB of memory capacity to accommodate the synthesis flows, parallel DSE, and iterative LLM inference processes. We evaluated TimelyHLS across 10 diverse FPGA devices, including Artix-7, Spartan-7, Zynq, and Virtex UltraScale+, to ensure comprehensive architectural coverage. The selected devices represent a wide spectrum of resource capacities, from low-cost embedded solutions to high-end accelerators listed in Table II. All designs were synthesized with constraints of achieving the maximum frequency.

## B. Large Language Model Configuration

We conducted comparative experiments using two state-of-the-art LLMs: OpenAI GPT-4 and Anthropic Claude-3.5- Sonnet, both accessed via their respective APIs with default temperature settings (0.7) to balance creativity and determinism in code generation. The RAG knowledge base was constructed by extracting and structuring information from official FPGA datasheets, vendor HLS user guides, and architectural reference manuals for each target device family.

<!-- Media -->

TABLE II: Targeted FPGA Families and their Applications.

<table><tr><td>FPGA Family</td><td>Part Number(s)</td><td>Typical Applications</td></tr><tr><td>Zynq</td><td>xc7z020-clg484-1</td><td>Embedded applications</td></tr><tr><td>Zynq UltraScale+</td><td>xczu3eg-sbva484-1-e</td><td>Heterogeneous computing</td></tr><tr><td>Artix/Kintex-7</td><td>xc7a200tfbg676-2, xc7k325tffg676-2</td><td>Cost-optimized designs</td></tr><tr><td>Spartan-7</td><td>xc7s50-ftgb196-2</td><td>Ultra-low-cost applications</td></tr><tr><td>Virtex UltraScale+</td><td>xcvu9p-flgb2104-2-e, xcvu11p-flga2577-1-e, xcvu9p-flgb2104-1-e</td><td>High-performance computing</td></tr><tr><td>Kintex UltraScale+</td><td>xck26-sfvc784-2LV-c</td><td>Balanced performance-power</td></tr><tr><td>Versal AI Edge</td><td>xave2602-nsvh1369-1LJ-i-L</td><td>AI/ML acceleration</td></tr></table>

<!-- Media -->

## V. RESULTS AND EVALUATION

To evaluate TimelyHLS, the benchmarks span a variety of domains, e.g., linear algebra, signal processing, sorting, and dynamic programming, each presenting unique challenges such as long critical paths, deep loop dependencies, or inefficient memory access. The evaluation focuses on four key metric categories: timing and performance, resource utilization, loop-level optimizations, and structural design changes.

## A. Performance Improvements

TimelyHLS demonstrated significant performance gains across several benchmarks. As illustrated in Fig. 2, speedup values on Artix-7 reached up to $4 \times$ ,with applications like Matrix Multiplication, LMS Filter, and Bitonic Sort showing the most notable improvements. These gains are primarily the result of architecture-specific pipelining strategies and effective insertion of pragmas such as pragma HLS pipeline and loop unrolling. These changes reduce the initiation interval (II) and enable higher parallelism.

## B. Timing and Latency Analysis

The timing closure performance of TimelyHLS is substantiated by latency and slack results presented in Table III. Across multiple benchmarks, the framework not only resolved negative slack violations but also preserved optimal latency characteristics when further improvement was infeasible or unnecessary. As shown, in the Matrix Multiplication benchmark, the baseline design exhibited negative slack, a direct result of deep loop nesting and non-optimized memory access, which introduced excessive combinational delay. TimelyHLS resolved this by restructuring loop hierarchies and selectively applying pipelining with loop unrolling and array partitioning, resulting in a fully timing-closed implementation with zero slack. Similarly, for the Vector Dot Product, the baseline implementation underutilized available DSP resources and suffered from inefficient loop scheduling, leading to intermittent timing violations. TimelyHLS addressed this by rebalancing the loop-carried dependencies and improving the data flow via pipelining and unrolling.

<!-- Media -->

<!-- figureText: VecDoc (up to 1.2x) Viterbi (up to 2.6x) VecAdd (up to 1.65x) MatMul (up to 3.85x) Conv (up to 2.7x) CORDIC (up to 2.2x) Bitonic (up to 3.7x) LMS (up to 2.55x) Speed-up 2x 2.5x 3x 3.5x 4x Benchmarks under Test MatVecDot (up to 1.15x) 0.5x 1x 1.5x -->

<img src="https://cdn.noedgeai.com/bo_d3th2cref24c73d1s6ag_3.jpg?x=912&y=1662&w=738&h=403&r=0"/>

Fig. 2: Performance Speedup Ratios for Artix 7.

<!-- Meanless: Authorized licensed use limited to: NANJING NORMAL UNIVERSITY. Downloaded on October 24,2025 at 05:37:48 UTC from IEEE Xplore. Restrictions apply.-->


TABLE III: Latency Comparison: Base vs. TimelyHLS.

<table><tr><td/><td>Bitonic</td><td>CORDIC</td><td>Mat-Vec</td><td>Mat Mul</td><td>VecAdd</td><td>VecDot</td><td>Viterbi</td></tr><tr><td>Base (ns)</td><td>0.1</td><td>2.7</td><td>0.54</td><td>-0.08</td><td>2.7</td><td>-0.54</td><td>2.7</td></tr><tr><td>TimelyHLS (ns)</td><td>0.1</td><td>2.7</td><td>0.62</td><td>0.1</td><td>2.7</td><td>0.54</td><td>2.7</td></tr></table>

<!-- Media -->

## C. Resource Utilization and Performance Tradeoffs

Tables IV and V reflect the impact of TimelyHLS on balancing hardware area consumption, measured through flipflop (FF) and lookup table (LUT) usage, with improvements in latency and timing closure. The observed trade-offs underscore the framework's architecture-aware optimization strategy, where moderate increases in resource utilization achieve the latency improvements, while in other cases, aggressive area savings are prioritized when latency is already near-optimal.

In benchmarks such as vector addition and matrix-vector multiplication, TimelyHLS used deeper pipelining and memory partitioning to eliminate bottlenecks and sustain loop throughput. While this increased LUT usage by ${50} - {65}\%$ , improvements in timing slack and loop initiation intervals justified the added area (deliberate trade-off: reducing latency with parallelism and logic duplication increases area). On the other hand, for benchmarks like the Viterbi Decoder, TimelyHLS reduced FF and LUT usage by over ${50}\%$ . This implies that the original design had redundant control logic or non-optimized datapath that could be compacted without affecting latency. These observations highlight the context-sensitive nature of the latency-area trade-off. TimelyHLS adapts its optimization to the designs' needs, aggressively optimizing for performance when needed, and concentrating on compactness when further gains are unnecessary. All final designs met FPGA resource constraints, showing both adaptability and architectural feasibility.

<!-- Media -->

TABLE IV: Flip-Flop (FF) Usage across FPGA Families.

<table><tr><td>Benchmark</td><td>Family</td><td>$\mathbf{{Part}}$</td><td>FF Used</td><td>FF Change (%)</td></tr><tr><td>Viterbi</td><td>Artix-7</td><td>$\mathrm{{xc}}7\mathrm{a}{200}\mathrm{t}$</td><td>247</td><td>-57.34</td></tr><tr><td>Viterbi</td><td>Spartan-7</td><td>xc7s50</td><td>247</td><td>-57.34</td></tr><tr><td>CORDIC</td><td>Spartan-7</td><td>xc7s50</td><td>329</td><td>-12.27</td></tr><tr><td>Vec Dot</td><td>Artix-7</td><td>xc7a200t</td><td>572</td><td>22.75</td></tr><tr><td>Vec Add</td><td>Zynq</td><td>xc7z020</td><td>2479</td><td>38.11</td></tr><tr><td>Vec Add</td><td>Spartan-7</td><td>xc7s50</td><td>2468</td><td>39.91</td></tr><tr><td>Vec Add</td><td>Virtex-U+</td><td>xcvu11p</td><td>2479</td><td>38.11</td></tr></table>

TABLE V: LUTs Usage across FPGA Families.

<table><tr><td>Benchmark</td><td>Family</td><td>$\mathbf{{Part}}$</td><td>$\mathbf{{LUTsUsed}}$</td><td>LUTs Change (%)</td></tr><tr><td>Viterbi Dec.</td><td>Artix-7</td><td>$\mathrm{{xc}}7\mathrm{a}{200}\mathrm{t}$</td><td>619</td><td>-48.24</td></tr><tr><td>Viterbi Dec.</td><td>Spartan-7</td><td>xc7s50</td><td>647</td><td>-47.91</td></tr><tr><td>Vec. Dot Prod.</td><td>Artix-7</td><td>$\mathrm{{xc}}7\mathrm{a}{200}\mathrm{t}$</td><td>669</td><td>40.84</td></tr><tr><td>Vec. Addition</td><td>Spartan-7</td><td>xc7s50</td><td>2460</td><td>46.43</td></tr><tr><td>Viterbi</td><td>Versal AI</td><td>xcvc2602</td><td>479</td><td>0.00</td></tr><tr><td>Vec. Addition</td><td>Virtex-U+</td><td>xcvu11p</td><td>2578</td><td>52.82</td></tr><tr><td>Viterbi Dec.</td><td>Virtex-U+</td><td>xcvu11p</td><td>1946</td><td>58.47</td></tr><tr><td>Mat-Vec Mult.</td><td>Artix-7</td><td>xc7a200t</td><td>3132</td><td>65.18</td></tr><tr><td>Mat-Vec Mult.</td><td>Spartan-7</td><td>xc7s50</td><td>3132</td><td>65.18</td></tr></table>

TABLE VI: Impact of TimelyHLS on Loop II.

<table><tr><td>Project</td><td>Base</td><td>TimelyHLS</td><td>Reason</td></tr><tr><td>Matrix Multiplication</td><td>16</td><td>1-2</td><td>Faster throughput.</td></tr><tr><td>Bitonic Sort</td><td>Non-pip.</td><td>All $\mathrm{{II}} = 1$</td><td>Loop pipelined.</td></tr><tr><td>Matrix-Vector Mult.</td><td>Not pip.</td><td>Pip. $\left( {\mathrm{{II}} = 1}\right)$</td><td>Added pipelining.</td></tr><tr><td>Vector Dot Product</td><td>1</td><td>1</td><td>Fixed timing.</td></tr><tr><td>Vector Addition</td><td>1-2</td><td>1</td><td>Higher BRAM usage.</td></tr><tr><td>CORDIC</td><td>2</td><td>Unrolled</td><td>Loop unrolled.</td></tr></table>

<!-- Media -->

## D. Loop-Level Optimization Strategies

Table VI shows the performance impact of TimelyHLS on key look initiation interval (II). As shown, in Matrix Multiplication, the initiation interval (II) was reduced from 16 to 1-2, significantly enhancing throughput. Bitonic Sort, previously limited by non-pipelined loops, was fully pipelined with II=1, resolving the primary performance bottleneck. Similarly, Matrix-Vector Multiplication and CORDIC benefited from loop unrolling and pipelining, leading to reduced latency and improved data movement. These results indicate that TimelyHLS effectively identifies loop-carried dependencies and applies appropriate directives to maximize hardware utilization and scheduling efficiency. An example of such impact has shown in Fig. 3 that represents code snippet of Vector Add (base vs. TimelyHLS implementation).

## E. Structural Optimization across FPGA Architectures

Evaluation across FPGA families (e.g., Artix-7) shows that TimelyHLS often restructures modules and interfaces to enhance performance. For instance, in Matrix Multiplication, latency dropped significantly, from 16,531 to 4,277 cycles, accompanied by the use of AXI interfaces for improved modularity. Similarly,Bitonic Sort saw a ${3.6} \times$ speedup,enabled by the addition of sparsemux units for faster scheduling. In contrast, Vector Dot Product saw a modest latency increase (519 to 640 cycles) but a dramatic rise in DSP usage (5 to 160), indicating operator duplication to meet timing. Overall, structural changes via TimelyHLS often led to performance gains, though at the cost of complexity or resource overhead.

<!-- Media -->

<!-- figureText: void vector_add( i void vector_add( const unsigned int *in1 #pragma HLS INTERFACE #_axi port=in1 offset=slave bundle=gnem depth=1024 #pragma HLS INTERFACE m_axi port=in2 offset=slave bundle=gnem depth=1024 #branma HLS INTERFACE # axi port=out offset=slave bundle=omem death=16 #pragma HLS INTERFACE S_axilite port=size bundle=control unsigned int local_in2[1024] unsigned int local_out[1024] #pragma HLS ARRAY_PARTITION variable=local_in1 cyclic factor=16 dim= #pragma HLS ARRAY_PARTITION variable=local_out cyclic factor=16 dim=1 // Burst read input arrays for ( int i = 0; i < size; i++ ) \{ #pragma HLS PIPELINE II=3 (b) TimelyHLS Code local_in1[i] = in1[i]; local_in2[i] = in2[i]; const unsigned int *in1 const unsigned int *in2 #pragma HLS INTERFACE M_axi port=in1 depth=1024 #pragma HLS INTERFACE M_axi port=in2 depth=1024 #pragma HLS INTERFACE M_axi port=out depth=102 #pragma HLS INTERFACE S_axilite port=size #pragma HLS INTERFACE s_axilite port=return ``---------------------------- // Perform vector addition for (int i = 0; i < size; i++) \{ #oragma HLS PIPELINE ITE] // Burst write output array for (int i = 0; i < size; i++) \{ #pragma HLS PIPELINE II=1 out[i] = local_out[i]; // Perform -->

<img src="https://cdn.noedgeai.com/bo_d3th2cref24c73d1s6ag_4.jpg?x=908&y=1723&w=751&h=342&r=0"/>

Fig. 3: TimelyHLS Code Example with Optimization.

<!-- Meanless: Authorized licensed use limited to: NANJING NORMAL UNIVERSITY. Downloaded on October 24,2025 at 05:37:48 UTC from IEEE Xplore. Restrictions apply-->


<!-- figureText: FPGA Families Zynq Versal Kintex Ultrascale+ $\leftarrow$ Virtex Ultrascale+ Pass Rate (Synthesis and Functional) 96% Spartan 7 Artix 7 91% 92% -->

<img src="https://cdn.noedgeai.com/bo_d3th2cref24c73d1s6ag_5.jpg?x=138&y=146&w=742&h=275&r=0"/>

Fig. 4: Code Generation Success across FPGA Families.

<!-- Media -->

## F. Architectural Adaptability and Design Quality

TimelyHLS demonstrates strong architectural adaptability, consistently generating synthesizable HLS code across a wide range of FPGA families, from low-cost devices like Spartan- 7 and Artix-7 to high-end platforms such as Zynq Ultra-Scale+ and Virtex UltraScale+ (see Fig. 4). Most benchmarks compiled successfully across nearly all devices, indicating broad generalizability without the need for manual retargeting. Failures were mostly limited to complex designs with irregular memory access or feedback-heavy loops, which struggled on resource-constrained FPGAs. In contrast, high-end devices like the Virtex UltraScale+ consistently supported even the most challenging designs. This suggests that TimelyHLS adapts its code generation to match platform capabilities-favoring compact, efficient structures on smaller FPGAs and leveraging advanced features (e.g., AXI interfacing, etc.) on larger ones.

## VI. CONCLUSION AND FUTURE WORK

This paper presented TimelyHLS, a framework that combines large language models, retrieval-augmented generation, and synthesis feedback to automate timing-aware, architecture-specific HLS code generation for FPGAs. By leveraging a structured knowledge base, TimelyHLS produces functionally correct, synthesizable designs that meet timing constraints across a broad range of FPGA architectures. Experiments show that TimelyHLS generalizes well to both low-end and high-performance platforms, adapting its optimization strategies to balance latency, area, and throughput. It automates complex design transformation, while maintaining high synthesis success rates even on resource-limited devices. Future work will extend the framework to support multi-objective optimization (e.g., power, area, performance trade-offs), integrate additional toolchains and hardware platforms, and improve model generalization through fine-tuning and curriculum learning. REFERENCES

[1] Q. Yanghua et al., "Improving classification accuracy of a machine learning approach for FPGA timing closure", in 2016 IEEE 24th FCCM. IEEE, 2016, pp. 80-83.

[2] J. Cong et al., "FPGA HLS today: successes, challenges, and opportunities", ACM TRETS, vol. 15, no. 4, pp. 1-42, 2022.

[3] M. W. Numan et al., "Towards Automatic High-Level Code Deployment on Reconfigurable Platforms: A Survey of High-Level Synthesis Tools and Toolchains", IEEE Access, vol. 8, pp. 174692-174722, 2020.

[4] E. Ustun et al., "LAMDA: Learning-assisted multi-stage autotuning for FPGA design closure", in FCCM. IEEE, 2019, pp. 74-77.

[5] Q. Sun et al., "Correlated multi-objective multi-fidelity optimization for HLS directives design", ACM TODAES, vol. 27, no. 4, pp. 1-27, 2022.

[6] AMD, "AMD Vitis HLS, High-Level Synthesis Tool," https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vitis/vitis-hls.html.

[7] C. Xiong et al., "HLSPilot: LLM-based high-level synthesis", in Proc. of 43rd IEEE/ACM ICCAD, 2024, pp. 1-9.

[8] S. Pouget et al., "Automatic hardware pragma insertion in high-level synthesis: A non-linear programming approach", ACM Tran. on Design Auto. of Elec. Sys., vol. 30, no. 2, pp. 1-44, 2025.

[9] Y. Chi et al., "Democratizing domain-specific computing", Commun. of the ACM, vol. 66, no. 1, pp. 74-85, 2022.

[10] S. Lahti et al., "High-level Synthesis for FPGAs-A Hardware Engineer's Perspective", IEEE Access, 2025.

[11] AMD, #pragma HLS pipeline -Vitis HLS User Guide (UG1399), AMD Inc., Santa Clara, CA, USA. [Online]. Available: https://docs.amd.com/r/en-US/ug1399-vitis-hls/pragma-HLS-pipeline

[12] S. Liu et al., "Accelerating FPGA prototyping through predictive model-based HLS design space exploration", in DAC, 2019, pp. 1-6.

[13] L. Ferretti et al., "Lattice-Traversing Design Space Exploration for High Level Synthesis", in 2018 IEEE 36th ICCD, 2018, pp. 210-217.

[14] A. Sohrabizadeh et al., "AutoDSE: Enabling software programmers to design efficient FPGA accelerators", ACM TODAES, vol. 27, no. 4, pp. 1-27, 2022.

[15] A.Sohrabizadeh et al., "Robust GNN-based representation learning for HLS", in 2023 IEEE/ACM ICCAD, IEEE, 2023, pp. 1-9.

[16] N. Prakriya et al., "LIFT: LLM-based pragma insertion for HLS via GNN supervised fine-tuning", arXiv, preprint arXiv:2504.21187, 2025.

[17] Q. Gautier et al., "Sherlock: A multi-objective design space exploration framework", ACM TODAES, vol. 27, no. 4, pp. 1-20, 2022.

[18] B. Peng et al., "Check your facts and try again: Improving large language models with external knowledge and automated feedback", arXiv, preprint arXiv:2302.12813, 2023.

[19] J. Ansel et al., "Opentuner: An extensible framework for program autotuning", in Proc. 23rd Int. Conf. on Par. arch. and comp., 2014, pp. 303-316.

[20] Z. Ding et al., "Efficient task transfer for HLS DSE", in Proc. 43rd IEEE/ACM ICCAD, 2024, pp. 1-9.

[21] N. K. Pham et al., "Exploiting loop-array dependencies to accelerate the design space exploration with high level synthesis", in 2015 IEEE DATE. IEEE, 2015, pp. 157-162.

[22] G. Zhong et al., "Lin-analyzer: A high-level performance analysis tool for FPGA-based accelerators", in Proc. 53rd DAC, 2016, pp. 1-6.

[23] J. Zhao et al., "COMBA: A comprehensive model-based analysis framework for high level synthesis of real applications", in 2017 IEEE/ACM ICCAD. IEEE, 2017, pp. 430-437.

[24] H. Ye et al., "ScaleHLS: A new scalable high-level synthesis framework on multi-level intermediate representation", in 2022 IEEE HPCA, IEEE, 2022, pp. 741-755.

[25] H. Shahzad et al., "Autoannotate: Reinforcement learning based code annotation for high level synthesis", in 2024 25th ISQED, IEEE, 2024, pp. 1-9.

[26] M. R. Ahmed et al., "AutoHLS: Learning to Accelerate Design Space Exploration for HLS Designs", in 2023 IEEE 66th MWSCAS, IEEE, 2023, pp. 491-495.

[27] M. Akyash et al., "Evolutionary large language models for hardware security: A comparative survey", in Proc. of the great lakes symposium on VLSI 2024, 2024, pp. 496-501.

[28] N. Mashnoor et al., "LLM-IFT: LLM-Powered Information Flow Tracking for Secure Hardware", in 2025 IEEE 43rd VTS. IEEE, 2025, pp. 1-5.

[29] M. Akyash et al., "RTL++: Graph-enhanced LLM for RTL Code Generation", arXiv, preprint arXiv:2505.13479, 2025.

[30] Y. Hara et al., "CHStone: A benchmark program suite for practical C-based high-level synthesis", in 2008 IEEE ISCAS. IEEE, 2008, pp. 1192-1195.

[31] A. Canis et al., "LegUp: An open-source high-level synthesis tool for FPGA-based processor/accelerator systems", ACM TECS, vol. 13, no. 2, pp. 1-27, 2013.

[32] B. Reagen et al., "MachSuite: Benchmarks for accelerator design and customized architectures", in 2014 IEEE IISWC. IEEE, 2014, pp. 110- 119.

<!-- Meanless: Authorized licensed use limited to: NANJING NORMAL UNIVERSITY. Downloaded on October 24,2025 at 05:37:48 UTC from IEEE Xplore. Restrictions apply.-->

