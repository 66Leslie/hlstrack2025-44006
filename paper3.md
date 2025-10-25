

<!-- Meanless: updates-->

# Exploring Code Language Models for Automated HLS-based Hardware Generation: Benchmark, Infrastructure and Analysis

Jiahao Gai ${}^{2}$ , Hao (Mark) Chen ${}^{1}$ , Zhican Wang ${}^{3}$ , Hongyu Zhou ${}^{4}$ ,

Wanru ${\mathrm{{Zhao}}}^{2}$ ,Nicholas Lane ${}^{2}$ ,Hongxiang ${\mathrm{{Fan}}}^{1\& 2}$

${}^{1}$ Imperial College London, ${}^{2}$ University of Cambridge, ${}^{3}$ Shanghai Jiao Tong University, ${}^{4}$ University of Sydney

Email: jg2123@cam.ac.uk, hongxiangfan@ieee.org

## Abstract

Recent advances in code generation have illuminated the potential of employing large language models (LLMs) for general-purpose programming languages such as Python and $C +  +$ ,opening new opportunities for automating software development and enhancing programmer productivity. The potential of LLMs in software programming has sparked significant interest in exploring automated hardware generation and automation. Although preliminary endeavors have been made to adopt LLMs in generating hardware description languages (HDLs) such as Verilog and SystemVerilog, several challenges persist in this direction. First, the volume of available HDL training data is substantially smaller compared to that for software programming languages. Second, the pre-trained LLMs, mainly tailored for software code, tend to produce HDL designs that are more error-prone. Third, the generation of HDL requires a significantly higher number of tokens compared to software programming, leading to inefficiencies in cost and energy consumption. To tackle these challenges, this paper explores leveraging LLMs to generate High-Level Synthesis (HLS)-based hardware design. Although code generation for domain-specific programming languages is not new in the literature, we aim to provide experimental results, insights, benchmarks, and evaluation infrastructure to investigate the suitability of HLS over low-level HDLs for LLM-assisted hardware design generation. To achieve this, we first finetune pre-trained models for HLS-based hardware generation, using a collected dataset with text prompts and corresponding reference HLS designs. An LLM-assisted framework is then proposed to automate end-to-end hardware code generation, which also investigates the impact of chain-of-thought and feedback loops promoting techniques on HLS- design generation. Comprehensive experiments demonstrate the effectiveness of our methods.

## ACM Reference Format:

Jiahao Gai, Hao (Mark) Chen, Zhican Wang, Hongyu Zhou, Wanru Zhao, Nicholas Lane, Hongxiang Fan. 2025. Exploring Code Language Models for Automated HLS-based Hardware Generation. In Proceedings of Asia and South Pacific Design Automation Conference (ASP-DAC'25). ACM, New York, NY, USA, 8 pages. https://doi.org/10.1145/3658617.3697616

<!-- Media -->

<!-- figureText: 100 40.52× Volume Size/KB 1E+8 1E+7 1E+6 1E+5 ${2.26} \times  {1E4} \times$ 1E+4 Gap 1E+3 1.33 1E+2 1E+0 (b) CodeParrot vs RTLLM Volume Size/GB 86.94 60 60.89 64.71 53.89 48.92 40 20 (a) Starcoder Dataset -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_0.jpg?x=931&y=561&w=710&h=291&r=0"/>

Figure 1: Comparison of data availability between HDLs and other software programming languages.

<!-- Media -->

## 1 INTRODUCTION

In the field of Generative AI (GenAI), significant strides have been made in producing complex and creative content across various domains such as text [4], image [2, 22], and video [33]. Among various GenAI technologies, large language models (LLMs) have emerged as particularly influential techniques in the realm of natural language processing [31]. This great capability of LLMs also raises intensive industrial interests in leveraging these models in automated code generation, as evidenced by GitHub Copilot [5] and DeepMind's AlphaCode [14]. Meanwhile, over 50 pre-trained models and more than 170 programming language datasets have been published in the past few years [30]. Although significant progress has been made in this direction, most of these works mainly focus on software code generation ${}^{ * }$ ,and the potential of LLM for hardware design generations has not been fully exploited.

The promises of LLM-assisted software programming has led to several recent attempts to explore automated code generation for hardware description languages (HDLs) such as Verilog and Sys-temVerilog $\left\lbrack  {{13},{17},{19},{24}}\right\rbrack$ . Although multiple datasets,pre-trained models, and code infrastructures have been introduced, several key challenges reamin in LLM-assisted hardware design generation:

- The data availability of HLD designs for LLM training and finetuning. Figure 1 compares the volume of training samples for software programming languages versus HDLs. For instance, the general-purpose code dataset StarCoder [13], as presented in Figure 1 (a), shows that the available amount of HDL designs is less than $1\%$ of those for $C +  +$ . Similar trends can also be observed in specialized datasets, such as RTLLM [19] for Verilog and CodeParrot [26] for Python. Figure 1(b) indicates that the dataset size of RTLLM is less than 1% of that for CodeParrot. Therefore, the quantity of training data available for hardware design is significantly lower than for software programming languages.

- Inability of utilizing learned knowledge from pre-trained coding LLMs. Pre-trained coding LLMs are primarily trained on software programming languages, which differ significantly in semantics and syntax from HDLs. Therefore, the knowledge acquired during pre-training cannot be directly applied to hardware code generation, compounding the data scarcity issue.

---

<!-- Footnote -->

*This paper mainly focuses on text-to-code generation.

<!-- Footnote -->

---

<!-- Meanless: This work is licensed under a Creative Commons Attribution International 4.0 License. ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan © 2025 Copyright held by the owner/author(s). ACM ISBN 979-8-4007-0635-6/25/01 https://doi.org/10.1145/3658617.3697616 988-->




<!-- Meanless: ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan Gai et al.-->

<!-- Media -->

<!-- figureText: HLS-based design Verilog-based design nodule multi-16bit( input elk, input [15:0] aim. always @(posedge clk or negedge rst_n always @(posedge clk or negedge rst n) begin if (!net n) berin yout r <= 32 h000000000: breg <= bin; yout_r <= yout_r + ((16'h0000, breg) << (i-1)); endinodule static void compute_mult_16bit( hls::stream<uint16 t>& inStream1. hls::stream<uint16_t>& inStream2 hls::stream< uint16 t>& outStream, int vSize) \{ execute for (int i = 0; i < vSize; i++) \{ outStream << (inStream1.read(   ) * inStream2.read(   )); Token Comparison HLS Code Verilog Code Generatic Power Con sumption -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_1.jpg?x=151&y=238&w=717&h=422&r=0"/>

Figure 2: HLS-based and Verilog-based programs.

<!-- Media -->

- Cost of HDL generation using LLMs. Figure 2 illustrates the number of tokens required for generating identical hardware designs using High-Level Synthesis (HLS) versus HDL. It shows that HDL implementations require approximately $3 \sim  4$ times more tokens than HLS designs, making HLS-based design generation a more sustainable solution considering the latency, energy, and monetary costs associated with LLM inference.

To address the aforementioned issues, this paper proposes an LLM-assisted framework for generating HLS-based ${}^{ \dagger  }$ hardware designs. By crawling HLS designs from open-source Github repositories, we collect a dataset to facilitate the fine-tuning of pre-trained LLM for the downstream HLS code generation. The benefits of generating HLS code are two folds: i) Given that HLS shares main semantics and syntax with $C/C +  +$ ,the coding knowledge acquired during the pre-training phase of the LLMs can be effectively utilized for hardware design. This compatibility also reduces the learning curve and dataset requirements for fine-tuning, as the additional knowledge needed for HLS is less than for traditional HDL coding. ii) The number of tokens required to generate ${HLS}$ code is lower compared to HDLs, rendering our approach more cost-effective and energy-efficient than previous methodologies. To further improve the quality of the generated designs, the framework incorporates debugging feedback loops and a chain-of-thought enhancement mechanism, systematically integrating detected bugs back into the input for iterative refinement. Overall, our contributions can be summarized as follows:

- Finetuning pre-trained code language models for HLS-based hardware generation, using a collected dataset with over 40,000 data entries, each containing a text prompt and the corresponding HLS-based hardware design (Section 3).

- Developing a framework that automatically produces HLS designs from input prompts, with an end-to-end evaluation of the syntax and functionality correctness (Section 4.1).

- Integrating multiple optimization techniques such as feedback loops and chain-of-thought techniques, which improve the pass rate for syntax and functionality (Section 4.2 & Section 4.3).

## 2 BACKGROUND AND RELATED WORK

### 2.1 LLM-Assisted Software Engineering

Based on the modality of inputs and outputs, language models for software engineering can be categorized into several downstream code tasks [30] such as text-to-code (code generation/synthesis [15]), code-to-text (code summarization [9]), and code-to-pattern processing (defect detection [20]). This paper focuses on code generation that aims at producing code from natural language descriptions/prompts. To facilitate the development of code generation with language models, various datasets, approaches, and pre-trained models have been introduced over the past decade.

Due to the lack of model capability, the early-stage methods [10, 15] of code generation mainly focus on a few programming languages such as Python or Java. Subsequently, with the increasing computational power, larger datasets are introduced to train models for multiple general-purpose programming languages. CodeXGLUE [18] presents a comprehensive code dataset consisting of different code tasks such as clone detection and code repair. HumanEval [5] dataset together with the code model CodeX marks as a milestone by using pre-trained LLMs for code generation. The promising capability shown by CodeX sparks significant academic and industrial interests in developing LLM-assisted code generation. Larger code datasets, such as StarCoder [13] and CodeParrot [26], and LLMs, including Code-LLaMA [21] and CodeFuse [7], are open-sourced in this community. However, most of these recent efforts focus on software programming languages.

### 2.2 Automated Hardware Design Generation

Building on the success of LLM-assisted software programming, recent studies have explored using language models for automated hardware generation. Since the data is the key to training LLMs for hardware code generation, multiple HDL datasets have been introduced recently. Thakur et al. present Verigen [24] dataset that contains 17 hardware designs with ${0.3}\mathrm{\;K}$ lines of HDL code. To increase the diversity of hardware designs for training and evaluation, Lu et al. open-source a larger benchmark consisting of 30 designs with more than ${2.5}\mathrm{\;K}$ lines. Sourced from HDLBits ${}^{ \ddagger  }$ ,Verilogeval [17] introduces larger datasets with 156 problems. These open-sourced datasets provide public benchmarks for text-to-HDL generation.

The evaluation metrics of LLM-assisted hardware code generation focus on three aspects: i) syntax, ii) functionality, and iii) quality. In previous literature [5, 17], syntax correctness and functionality are measured using pass@k metric which represents whether any of $k$ generated code samples can pass the syntax check of synthesis tools or functional unit tests. The quality usually is defined as power, performance, and area of the generated hardware, collectively reflect the capability of the code generation methods.

Aiming at improving these metrics, existing approaches [17, 19, 24] fine-tune pre-trained LLMs on the downstream task with optimized sampling schemes. These LLMs are mainly pre-trained using software programming languages. RTLFixer [25] introduces an automated framework that adopts retrieval-augmented generation [11] and ReAct prompting [29] to enable LLM-assisted debugging for RTL designs. LLM-VeriPPA [1] enhances the code generation of

---

<!-- Footnote -->

${}^{ \dagger  }$ This paper focues on C-based HLS.

†https://hdlbits.01xz.net/wiki/Main_Page

<!-- Footnote -->

---

<!-- Meanless: 989-->




<!-- Meanless: Exploring Code Language Models for Automated HLS-based Hardware Generation ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan-->

<!-- Media -->

<!-- figureText: Template of Design Point Instruction Prompt: Specify coding language and requirements. Design Description: High level description of the design details. Reference Design: Canonical HLS program. -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_2.jpg?x=253&y=237&w=509&h=209&r=0"/>

Figure 3: Template of design points.

<!-- Media -->

RTL using a two-stage refinement process to progressively improve syntax, functionality, and hardware performance. However, these approaches focus on low-level hardware languages instead of HLS. In this work, we take the first step to investigate the HLS code generation with LLM. Since HLS shares similar semantics and syntax with programming languages commonly used during LLM pretraining, this paper explores whether HLS is better than low-level hardware languages for automated hardware design generation. Although code generation with feedback and CoT prompting is not new in the literature of coding language models, our experimental results, insights, benchmark, and evaluation infrastructure specific to LLM-assisted HLS design offer valuable contributions to the future development of automated hardware generation.

## 3 HLS GENERATION BENCHMARK

### 3.1 Format of Design Points

Following the practices of Python benchmark HumanEval [5] and Verilog dataset VerilogEval [17], each design point has three components: i) user instruction prompts, ii) design descriptions and iii) reference designs. Figure 3 shows the standardized format template, with each data point stored as a JSONL following the Alpaca format. The default user instruction prompt is Generate HLS code with the following instructions:, which can be enhanced using the chain-of-thought (COT) prompting technique as detailed in Section 4.2.

### 3.2 Dataset Collection

We collect 52 HLS-based designs from open-source repositories, including HLSyn [3] ${}^{§}$ and ML4Accel ${}^{¶}$ . These designs are split into training and testing sets at a 4:1 ratio and fall into five categories:

- Matrix and Linear Algebra Operations: Includes sparse matrix-vector multiplications, dense matrix-matrix multiplication, array transformation and stencil computations.

- Scientific Simulations: Methods for solving physical and mathematical problems such as heat distribution and electromagnetic simulations.

- Statistical Computations: Calculations of statistical metrics from datasets.

- Iterative Methods: Techniques for solving equations using iterative approaches.

- Other Computational Kernels: Specialized computational tasks like molecular dynamics and interactions, encryption algorithms, and optical flow.

Each of these 52 designs is associated with different combinations of programs such as PIPELINE, PARALLEL and TILE. We filter out the HLS programs that are invalid, resulting in a collection of over ${42},{000}\mathrm{{HLS}}$ programs. The whole dataset is split into training and test sets for supervised fine-tuning and evaluation, respectively.

### 3.3 Generation of Design Description

Given that the dataset encompasses over 42,000 HLS programs, manually generating design descriptions for each program is both labor-intensive and time-consuming. Inspired by both HumanEval [5] and Verilog, we utilize ChatGPT (version 3.5 and 4) to automate the creation of design descriptions for the datasets. We append each HLS program with this base prompt when utilizing ChatGPT to generate the corresponding design descriptions. Both the reference design and its generated description are stored in JSON format, adhering to the structure outlined in Section 3.1. This method ensures streamlined and consistent documentation of design descriptions across the dataset. Following the practice of [17], we provide two versions of prompts for each HLS program in the test set: Machine-Gen and HumanRefine. The MachineGen version comprises prompts and instructions generated by GPT-based models without any human modifications. In contrast, the HumanRefine includes manually refined prompts to ensure more concise and human-like natural language instructions.

### 3.4 Assessment Infrastructure

We provide evaluation infrastructure for both syntax and functionality. For syntax verification, we use the GCC compiler with the "-fsyntax-only" option. It allows us to verify the syntax without the overhead of compiling the code, thereby enhancing time and space efficiency. Regarding functionality correctness, we design unit tests tailored for each example in the test dataset. Each test case is associated with its corresponding 'source_file'. To achieve this goal, we modified the original test JSONL file to add another attribute 'source_file'. The testing process involves executing both the generated code and the original source code to compare their outputs. For instance, if the outputs from both codes consist of matrices, we conduct a targeted comparison. This is done by selecting specific positions within the matrices from both outputs at random and verifying if they match.

## 4 AUTOMATED HARDWARE GENERATION

### 4.1 Framework Overview

An overview of our proposed framework is depicted in Figure 4. The framework comprises two main stages: i) model fine-tuning and ${ii}$ ) iterative code generation. The final output is an HLS-based program that can be synthesized into the corresponding hardware design. While focused on Vivado-HLS, our framework is adaptable to any HLS language with appropriate datasets for fine-tuning and evaluation.

In the model fine-tuning stage, our framework initiates by retrieving coding LLMs from open-source repositories, such as Code-Llama ${}^{\parallel }$ and Start-Coder**. Then,supervised fine-tuning is conducted on these pre-trained models using the HLS training data (Section 3.2). We adopt axolot ${l}^{\dagger  \dagger  }$ to perform the fine-tuning,allowing for customization of models and training parameters, such as learning rate, batch size, and epoch number to fit specific scenarios and available resources.

---

<!-- Footnote -->

Ihttps://huggingface.co/codellama

**https://huggingface.co/blog/starcoder

${}^{\dagger  \dagger  }$ https://github.com/OpenAccess-AI-Collective/axolotl

§https://github.com/UCLA-DM/HLSyn

Ihttps://github.com/UT-LCA/ML4Accel-Dataset

<!-- Footnote -->

---

<!-- Meanless: 990-->




<!-- Meanless: ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan Gai et al.-->

<!-- Media -->

<!-- figureText: HLS-based HLS Source Code Filter Diverse High-quality Code-to-Text LLM Corresponding Code Kernels Prompts Label: $y$ Data: $x$ Proposed Dataset Split Dataset Dataset Preparation Compile (Basic Syntax Check) Functionality Check Generated HLS Code Vivadc Synthesis Vivado" HLS ③ programs Hugging Face ① Model Fine-Tuning StarCoder Pre-trained Text-to- Training Code LLM Dataset Supervised Fine-tuning Fine-tuned Text-to- Chain- Code LLM Input Prompt Thought Completed Codes Syntax Check Instruction Prompt: xxxxx Design Description: xxxxxx Feedback with Located Errors ②Iterative Code Generation -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_3.jpg?x=371&y=240&w=1047&h=563&r=0"/>

Figure 4: An overview of our proposed framework.

<!-- figureText: Chain-of-Thought Prompt for Generating HLS Design Instruction Prompt: "Let's think step by step. First, Consider the characteristics of FPGA. Second, Determine the program structure. Third, Write code logic Fourth, Consider data types and interfaces." -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_3.jpg?x=212&y=861&w=592&h=235&r=0"/>

Figure 5: Chain-of-thought prompts for HLS generation.

<!-- Media -->

In the second stage, we employ the fine-tuned LLM for iterative code generation. The process begins with initial inputs consisting of user instruction prompts and design descriptions. To enhance the quality of the generated HLS designs, we incorporate a chain-of-thought optimization technique (Section 4.2) into the instruction prompts. The code generation then proceeds with a feedback loop (Section 4.3) that iteratively improves the correctness of the HLS designs. This iterative process continues until a refined HLS program is generated as the final output. Users can specify the number of iterations, providing the flexibility to navigate this trade-off according to their specific needs, with more iterations typically yielding higher quality at increased runtime expense.

### 4.2 Chain-of-Thought

Previous studies indicate that the quality of generated content is significantly influenced by the instructional prompt [32]. The Chain-of-Thought (CoT) [28] technique has proven simple and effective for enhancing the performance of LLMs across a wide range of tasks, including arithmetic, commonsense, and symbolic reasoning [28]. Although initially, COT yielded a modest 0.82 point increase in the pass@1 metric in code generation, this improvement was substantially augmented through structured prompting [12]. In this paper, we investigate the effect of CoT in generating HLS-based hardware designs.

Figure 5 illustrates the CoT prompt structured for HLS code generation. The prompt guides a systematic approach through several targeted steps: understanding FPGA characteristics, defining program structure, developing logic, selecting data types and interfaces, before finalizing the code. This structured process ensures thorough consideration of each key aspect to optimize the HLS code generation.

### 4.3 Two-Step Feedback Loops

Code generation with feedback loop has shown promising results in previous literature $\left\lbrack  {1,{16},{23},{27}}\right\rbrack$ . This paper investigates its impact on HLS code generation using a two-step feedback loop tailored for automated hardware generation, focusing on HLS-related feedback. At each iteration, the framework evaluates the syntax and functional correctness of the generated HLS program. The located syntax error and functional defects are then incorporated back into the input prompts as additional information for subsequent code generation.

In the first step, syntax feedback is provided using the GCC compiler with the '-fsyntax-only' option, as specified in 3.4. It captures the syntax errors without fully compiling the code. It allows rapid identification including the types and locations, and precise error mapping for targeted corrections. If the syntax check passes, our framework proceeds to the second step by executing predefined unit tests to compare the outputs of the generated and the original source code. Functional defects are recorded and added to the prompts for the next iteration. This two-step feedback loop continues for a user-specified number of iterations, providing flexibility to balance the trade-off between design quality and runtime cost.

## 5 EVALUATION

### 5.1 Experimental Setup

In our evaluation, we adopt Code-Llama-7B as the pre-trained model for fine-tuning, employing the low-rank-adaption (QLoRA) [6, 8] technique for faster training and lower memory consumption. Key configurations include loading the model in 8-bit, a sequence length of 4096 , sample packing, and padding to sequence length. We set the warmup steps to 100 , with a gradient accumulation of 4 steps, a micro-batch size of 4 , and an inference batch size of 2 . For both syntax and functionality checks, we measure pass@3 accuracy as metrics. In the ablation study from Section 5.2 to Section 5.6, we adopt MachineGen for evaluation.

<!-- Meanless: 991-->




<!-- Meanless: Exploring Code Language Models for Automated HLS-based Hardware Generation ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan-->

Experiments are conducted on a server with four NVIDIA L20 GPUs (48 GB each), an 80 vCPU Intel® Xeon® Platinum 8457C, and 100GB of RAM. This setup ensures sufficient computational power and memory to handle the intensive demands of fine-tuning and inference efficiently, especially for long data sequences in the feedback loop experiment.

### 5.2 Effect of Supervised Finetuning

Our first ablation study investigates the effect of the model fine-tuning. We evaluated the performance based on both syntax and functionality checks. As shown in Figure 6(a), the results demonstrate that the finetuning dramatically increases syntax correctness from 54.85% to 88.44%. More importantly, the impact of finetuning is even more pronounced in the functionality evaluation, where the non-finetuned model failed to achieve any correct functionality test,but the accuracy is improved to 53.20% in the finetuned model. These enhancements highlight the critical role of finetuning in producing not only syntactically correct but also functionally viable codes, which demonstrates the benefits of finetuning LLMs for hardware design in the HLS code generation task.

### 5.3 Effect of Chain-of-Thought Prompting

To assess the effect of the chain-of-thought (CoT) technique, we perform both syntax and functionality evaluation on the fine-tuned model with and without the use of CoT. As indicated in Figure 6(b), incorporating CoT leads to a noticeable improvement in both metrics. Specifically, syntax correctness increases from 88.44% to 94.33%, and functionality score rises from 53.20% to 61.45%. The result demonstrates the effectiveness of CoT in enhancing the reasoning capability, thereby improving its overall performance.

### 5.4 Effect of Feedback Loops

Our two-step feedback loop provides both syntax and functionality feedback. We evaluate the impact of these feedback loops with different numbers of iterations, ranging from 0 to 2 .The results, shown in Figure Figure 7 and Figure 8, indicate that both syntax and functionality feedback loops significantly improve model performance, especially when combined with COT prompting. The initial feedback loop yields substantial accuracy improvements in both syntax correctness and functionality evaluation, though the second loop shows diminishing returns.Syntax feedback loops enhance both syntax correctness and functionality performance, suggesting that iterative refinement is particularly effective for complex tasks. Similarly, functionality feedback loops not only improve functionality checks but also boost syntax accuracy, indicating that enhancements in functional understanding contribute to better syntactic performance.

<!-- Media -->

<!-- figureText: 100.00% 88.44% pass@3 accuracy 100.00% 88.44% 94.33% 80.00% 61.45% 60.00% 53.20% 40.00% 20.00% 0.00% w/o COT with COT - synax check - functionality check (b) Effect of chain-of-thought prompting pass@3 accuracy 80.00% 60.00% 53.20% 40.00% 20.00% 0.00% w/o Finetune with Finetune - synax check - functionality check (a) Effect of fine-tuning -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_4.jpg?x=926&y=239&w=722&h=277&r=0"/>

Figure 6: Effect of fine-tuning and chain-of-thought.

<!-- figureText: 100.00% syntax feedback syntax feedback (max 1 loop) (max 2 loops) - syntax check with COT -functionality check with COT pass@3 accuracy 90.00% 80.00% 70.00% 60.00% 50.00% w/o feedback - $\times$ -syntax check w/o COT - - functionality check w/o COT -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_4.jpg?x=943&y=638&w=684&h=345&r=0"/>

Figure 7: Effect of syntax feedback loop.

<!-- figureText: 100.00% functionality feedback functionality feedback (max 1 loop) (max 2 loops) -syntax check with COT -functionality check with COT pass@3 accuracy 90.00% 80.00% 70.00% 60.00% 50.00% w/o feedback -x-syntax check w/o COT functionality check w/o -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_4.jpg?x=943&y=1107&w=689&h=332&r=0"/>

Figure 8: Effect of functionality feedback loop.

<!-- Media -->

### 5.5 Time Cost and Hardware Performance

Figure 9 shows the time cost for generating 120 data entries under different conditions, measuring the impact of CoT and feedback loops. Without a feedback loop, CoT significantly reduces the time. Adding a syntax feedback loop increases the time, but CoT continues to notably decrease the duration. The functionality feedback loop is the most time-consuming, though CoT still provides a notable reduction, albeit less dramatic. This demonstrates CoT's effectiveness in reducing operational times across varying complexities.

For the test set, we evaluate the latency and resource consumption of the generated HLS designs using a Xilinx VCU118 as our target FPGA,with a clock frequency of ${200}\mathrm{{MHz}}$ and Xilinx Vi-vado 2020.1 for synthesis. As shown in Table 1, all HLS designs demonstrate reasonable performance, with BRAM usage consistently remained at zero due to the design scale.

<!-- Meanless: 992-->




<!-- Meanless: ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan Gai et al.-->

<!-- Media -->

<!-- figureText: w/o feedback 10 12 Inference Time averaged by 120 Data Points (second) loop syntax loop (max 1) functionality loop (max 1) 0 $\square \mathrm{w}/\mathrm{{oCOT}}\;\square$ with COT -->

<img src="https://cdn.noedgeai.com/bo_d3th3kbef24c73d1s6ng_5.jpg?x=166&y=237&w=684&h=368&r=0"/>

Figure 9: Time cost of code generation.

Table 1: Latency and resource usage of LLM-generated designs synthesized on a VCU118 FPGA.

<table><tr><td/><td>Latency (ms)</td><td>$\mathbf{{LUTs}}$</td><td>Registers</td><td>$\mathbf{{DSP48s}}$</td><td>BRAMs</td></tr><tr><td>Available</td><td>-</td><td>1182240</td><td>2364480</td><td>6840</td><td>4320</td></tr><tr><td>ellpack</td><td>0.304</td><td>1011</td><td>1079</td><td>11</td><td>0</td></tr><tr><td>syrk</td><td>21.537</td><td>1371</td><td>1621</td><td>19</td><td>0</td></tr><tr><td>syr2k</td><td>40.626</td><td>1572</td><td>1771</td><td>19</td><td>0</td></tr><tr><td>stencil2d</td><td>1.368</td><td>287</td><td>123</td><td>3</td><td>0</td></tr><tr><td>trmm-opt</td><td>15.889</td><td>1262</td><td>1239</td><td>11</td><td>0</td></tr><tr><td>stencil3d</td><td>21.537</td><td>1173</td><td>1271</td><td>20</td><td>0</td></tr><tr><td>symm</td><td>24.601</td><td>1495</td><td>1777</td><td>19</td><td>0</td></tr><tr><td>symm-opt</td><td>16.153</td><td>1361</td><td>1608</td><td>19</td><td>0</td></tr><tr><td>symm-opt-medium</td><td>579.0</td><td>2223</td><td>2245</td><td>22</td><td>0</td></tr></table>

<!-- Media -->

### 5.6 Effect of Task Complexity

We analyze the effects of code complexity on the performance of fine-tuning our language model with CoT prompting and tested without the use of any feedback loops during inference. We categorize MachineGen into three classes according to their code complexity: easy, medium, and difficult. The results shown in the Table 2 indicates a clear trend: as the complexity of the generated code increases, both syntax and functionality correctness rates decline. This outcome could be attributed to several factors. First, more complex code inherently presents more challenges in maintaining syntactic integrity and functional accuracy. Second, the absence of feedback loops in the inference phase may have limited the model's ability to self-correct emerging errors in more complicated code generations.

<!-- Media -->

Table 2: Performance across different complexity levels.

<table><tr><td>Test Set</td><td>Syntax Check</td><td>Functionality</td></tr><tr><td>Easy</td><td>96.67%</td><td>63.33%</td></tr><tr><td>Medium</td><td>96.67%</td><td>53.33%</td></tr><tr><td>Difficult</td><td>90%</td><td>53.33%</td></tr></table>

<!-- Media -->

### 5.7 Analysis of MachineGen and HumanRefine

As shown in Table 3, this section compares the performance of our model on MachineGen and HumanRefine test sets. Our findings reveal that the performance on the HumanRefine is significantly lower than on the MachineGen. This disparity suggests that the model is

<!-- Media -->

Table 3: Performance on MachineGen and HumanRefine.

<table><tr><td>Test Set</td><td>Syntax Check</td><td>Functionality Check</td></tr><tr><td>MachineGen</td><td>93.83%</td><td>62.24%</td></tr><tr><td>HumanRefine</td><td>47.29%</td><td>21.36%</td></tr></table>

<!-- Media -->

more adept at handling machine-generated prompts. The primary reasons for this are: the model's training data bias towards machine-generated prompts, the increased complexity and nuanced nature of human-generated prompts, and the conciseness and clarity of human-generated prompts that often omit repetitive or explicit details found in machine-generated prompts, making it harder for the model to generate syntactically and functionally correct code.

### 5.8 Thoughts, Insights and Future Directions

${HLS}$ versus ${HDL}$ for AI-assisted code generation: The selection of programming language for hardware code generation should mainly depend on two factors:

- Quality of Generated Hardware Design: The evaluation of hardware design's quality includes syntax correctness, functionality, and hardware performance. Since HLS shares similar semantics and syntax with programming languages commonly used during LLM pre-training, this work demonstrates that the LLM-assisted code generation for ${HLS}$ has the potential to achieve high syntax and functional correctness in hardware designs. While this work does not leverage hardware performance as feedback for design generation, it identifies this aspect as a key direction for future research and enhancements.

- Runtime Cost of Hardware Generation: Although HLS-based designs typically require fewer tokens compared to HDL during the code generation phase-suggesting potentially lower costs-the overall runtime costs associated with HLS synthesis must also be considered. A more comprehensive quantitative comparison of these runtime costs is planned for our future work.

Input instructions and datasets are crucial: The fine-tuning of pre-trained LLMs on HLS dataset can bring a significant improvement in the design quality, echoing findings from previous studies on Verilog code generation [24]. Additionally, during our evaluation, we found that employing simple CoT prompting largely improves hardware design quality. This result contrasts with the application of CoT in general-purpose programming languages, where a specialized form of CoT is necessary [12]. Therefore, future efforts for further enhancement can focus on collecting high-quality datasets and exploring better refinement of input prompts.

## 6 CONCLUSION

This paper explores automating hardware generation with code language models and High-Level Synthesis (HLS). We aim to investigate the suitability of HLS over low-level hardware description languages for hardware design generation. To facilitate this, we propose benchmarks and code infrastructures for evaluating LLM-assisted HLS design generation. Our experimental findings reveal that, with the integration of advanced optimizations such as feedback loops and chain-of-thought techniques, LLM-assisted HLS code generation shows substantial promise in designing complex hardware with high levels of syntax and functional correctness. REFERENCES

<!-- Meanless: 993-->




<!-- Meanless: Exploring Code Language Models for Automated HLS-based Hardware Generation ASP-DAC'25, January 20-23, 2025, Tokyo Odaiba Miraikan, Japan-->

[1] Anonymous Authors. 2024. LLM-VeriPPA: Power, Performance, and Area-aware Verilog Code Generation and Refinement with Large Language Models. https: //openreview.net/pdf?id=nZL6S0b-HcI

[2] Omri Avrahami, Dani Lischinski, and Ohad Fried. 2022. Blended diffusion for text-driven editing of natural images. In IEEE/CVF Conference on Computer Vision and Pattern Recognition. 18208-18218.

[3] Yunsheng Bai, Atefeh Sohrabizadeh, Zongyue Qin, Ziniu Hu, Yizhou Sun, and Jason Cong. 2023. Towards a Comprehensive Benchmark for High-Level Synthesis Targeted to FPGAs. Advances in Neural Information Processing Systems 36 (2023), 45288-45299.

[4] Tom Brown, Benjamin Mann, Nick Ryder, Melanie Subbiah, Jared D Kaplan, Prafulla Dhariwal, Arvind Neelakantan, Pranav Shyam, Girish Sastry, Amanda Askell, et al. 2020. Language models are few-shot learners. Advances in Neural Information Processing Systems 33 (2020), 1877-1901.

[5] Mark Chen, Jerry Tworek, Heewoo Jun, Qiming Yuan, Henrique Ponde de Oliveira Pinto, Jared Kaplan, Harri Edwards, Yuri Burda, Nicholas Joseph, Greg Brockman, et al. 2021. Evaluating large language models trained on code. arXiv preprint arXiv:2107.03374 (2021).

[6] Tim Dettmers, Artidoro Pagnoni, Ari Holtzman, and Luke Zettlemoyer. 2024. Qlora: Efficient finetuning of quantized llms. Advances in Neural Information Processing Systems 36 (2024).

[7] Peng Di, Jianguo Li, Hang Yu, Wei Jiang, Wenting Cai, Yang Cao, Chaoyu Chen, Dajun Chen, Hongwei Chen, Liang Chen, et al. 2023. Codefuse-13b: A pretrained multi-lingual code large language model. arXiv preprint arXiv:2310.06266 (2023).

[8] Edward J Hu, Yelong Shen, Phillip Wallis, Zeyuan Allen-Zhu, Yuanzhi Li, Shean Wang, Lu Wang, and Weizhu Chen. 2021. Lora: Low-rank adaptation of large language models. arXiv preprint arXiv:2106.09685 (2021).

[9] Srinivasan Iyer, Ioannis Konstas, Alvin Cheung, and Luke Zettlemoyer. 2016. Summarizing source code using a neural attention model. In 54th Annual Meeting of the Association for Computational Linguistics 2016. Association for Computational Linguistics, 2073-2083.

[10] Srinivasan Iyer, Ioannis Konstas, Alvin Cheung, and Luke Zettlemoyer. 2018. Mapping language to code in programmatic context. arXiv preprint arXiv:1808.09588 (2018).

[11] Patrick Lewis, Ethan Perez, Aleksandra Piktus, Fabio Petroni, Vladimir Karpukhin, Naman Goyal, Heinrich Küttler, Mike Lewis, Wen-tau Yih, Tim Rocktäschel, et al. 2020. Retrieval-augmented generation for knowledge-intensive nlp tasks. Advances in Neural Information Processing Systems 33 (2020), 9459-9474.

[12] Jia Li, Ge Li, Yongmin Li, and Zhi Jin. 2023. Structured chain-of-thought prompting for code generation. arXiv preprint arXiv:2305.06599 (2023).

[13] Raymond Li, Loubna Ben Allal, Yangtian Zi, Niklas Muennighoff, Denis Kocetkov, Chenghao Mou, Marc Marone, Christopher Akiki, Jia Li, Jenny Chim, et al. 2023. Starcoder: may the source be with you! arXiv preprint arXiv:2305.06161 (2023).

[14] Yujia Li, David Choi, Junyoung Chung, Nate Kushman, Julian Schrittwieser, Rémi Leblond, Tom Eccles, James Keeling, Felix Gimeno, Agustin Dal Lago, et al. 2022. Competition-level code generation with alphacode. Science 378, 6624 (2022), 1092-1097.

[15] Wang Ling, Edward Grefenstette, Karl Moritz Hermann, Tomáš Kočiský, Andrew Senior, Fumin Wang, and Phil Blunsom. 2016. Latent predictor networks for code generation. arXiv preprint arXiv:1603.06744 (2016).

[16] Jiate Liu, Yiqin Zhu, Kaiwen Xiao, Qiang Fu, Xiao Han, Wei Yang, and Deheng Ye. 2023. Rltf: Reinforcement learning from unit test feedback. arXiv preprint arXiv:2307.04349 (2023).

[17] Mingjie Liu, Nathaniel Pinckney, Brucek Khailany, and Haoxing Ren. 2023. Ver-ilogeval: Evaluating large language models for verilog code generation. In 2023 IEEE/ACM International Conference on Computer Aided Design (ICCAD). IEEE,

[18] Shuai Lu, Daya Guo, Shuo Ren, Junjie Huang, Alexey Svyatkovskiy, Ambrosio Blanco, Colin Clement, Dawn Drain, Daxin Jiang, Duyu Tang, et al. 2021. Codexglue: A machine learning benchmark dataset for code understanding and generation. arXiv preprint arXiv:2102.04664 (2021).

[19] Yao Lu, Shang Liu, Qijun Zhang, and Zhiyao Xie. 2024. RTLLM: An open-source benchmark for design rtl generation with large language model. In 2024 29th Asia and South Pacific Design Automation Conference (ASP-DAC). IEEE, 722-727.

[20] Baishakhi Ray, Vincent Hellendoorn, Saheel Godhane, Zhaopeng Tu, Alberto Bacchelli, and Premkumar Devanbu. 2016. On the" naturalness" of buggy code. In Proceedings of the 38th International Conference on Software Engineering. 428-439.

[21] Baptiste Roziere, Jonas Gehring, Fabian Gloeckle, Sten Sootla, Itai Gat, Xiao-qing Ellen Tan, Yossi Adi, Jingyu Liu, Tal Remez, Jérémy Rapin, et al. 2023. Code llama: Open foundation models for code. arXiv preprint arXiv:2308.12950 (2023).

[22] Chitwan Saharia, Jonathan Ho, William Chan, Tim Salimans, David J Fleet, and Mohammad Norouzi. 2022. Image super-resolution via iterative refinement. IEEE Transactions on Pattern Analysis and Machine Intelligence 45, 4 (2022), 4713-4726.

[23] Parshin Shojaee, Aneesh Jain, Sindhu Tipirneni, and Chandan K Reddy. 2023. Execution-based code generation using deep reinforcement learning. arXiv preprint arXiv:2301.13816 (2023).

[24] Shailja Thakur, Baleegh Ahmad, Hammond Pearce, Benjamin Tan, Brendan Dolan-Gavitt, Ramesh Karri, and Siddharth Garg. 2023. Verigen: A large language model for verilog code generation. ACM Transactions on Design Automation of Electronic Systems (2023).

[25] YunDa Tsai, Mingjie Liu, and Haoxing Ren. 2023. Rtlfixer: Automatically fixing rtl syntax errors with large language models. arXiv preprint arXiv:2311.16543 (2023).

[26] Lewis Tunstall, Leandro Von Werra, and Thomas Wolf. 2022. Natural language processing with transformers. " O'Reilly Media, Inc.".

[27] Xin Wang, Yasheng Wang, Yao Wan, Fei Mi, Yitong Li, Pingyi Zhou, Jin Liu, Hao Wu, Xin Jiang, and Qun Liu. 2022. Compilable neural code generation with compiler feedback. arXiv preprint arXiv:2203.05132 (2022).

[28] Jason Wei, Xuezhi Wang, Dale Schuurmans, Maarten Bosma, Fei Xia, Ed Chi, Quoc V Le, Denny Zhou, et al. 2022. Chain-of-thought prompting elicits reasoning in large language models. Advances in neural information processing systems 35 (2022), 24824-24837.

[29] Shunyu Yao, Jeffrey Zhao, Dian Yu, Nan Du, Izhak Shafran, Karthik Narasimhan, and Yuan Cao. 2022. React: Synergizing reasoning and acting in language models. arXiv preprint arXiv:2210.03629 (2022).

[30] Ziyin Zhang, Chaoyu Chen, Bingchang Liu, Cong Liao, Zi Gong, Hang Yu, Jianguo Li, and Rui Wang. 2023. Unifying the perspectives of nlp and software engineering: A survey on language models for code. arXiv preprint arXiv:2311.07989 (2023).

[31] Wayne Xin Zhao, Kun Zhou, Junyi Li, Tianyi Tang, Xiaolei Wang, Yupeng Hou, Yingqian Min, Beichen Zhang, Junjie Zhang, Zican Dong, et al. 2023. A survey of large language models. arXiv preprint arXiv:2303.18223 (2023).

[32] Zihao Zhao, Eric Wallace, Shi Feng, Dan Klein, and Sameer Singh. 2021. Calibrate before use: Improving few-shot performance of language models. In International conference on machine learning. PMLR, 12697-12706.

[33] Zangwei Zheng, Xiangyu Peng, and Yang You. 2024. Open-Sora: Democratizing Efficient Video Production for All. https://github.com/hpcaitech/Open-Sora

<!-- Meanless: 994-->

