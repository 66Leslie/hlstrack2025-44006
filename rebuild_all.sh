#!/bin/bash
# HLS Track 2025 - 完整重建脚本
# 用途: 清理所有题目，重新运行 csim, csynth, cosim, vivado_impl

set -e  # 遇到错误立即退出

echo "=========================================="
echo "HLS Track 2025 - 完整重建脚本"
echo "=========================================="
echo ""

# 设置环境变量
export XPART=xc7z020-clg484-1
source /home/zxw/AMD/Vitis/2024.2/settings64.sh

# 定义项目根目录
PROJECT_ROOT="/home/zxw/project/hlstrack2025"

# ==========================================
# 题目 1: SHA-256
# ==========================================
echo "=========================================="
echo "题目 1: SHA-256"
echo "=========================================="

SHA256_DIR="$PROJECT_ROOT/security/L1/tests/hmac/sha256"
cd "$SHA256_DIR"

echo "1. 清理旧文件..."
make clean

echo "2. 运行 C Simulation..."
make run TARGET=csim

echo "3. 运行 C Synthesis..."
make run TARGET=syn

echo "4. 运行 Co-simulation..."
make run TARGET=cosim

echo "5. 运行 Vivado Implementation (检查资源)..."
make run TARGET=vivado_impl

echo "✅ SHA-256 完成！"
echo ""

# ==========================================
# 题目 2: LZ4 Compress
# ==========================================
echo "=========================================="
echo "题目 2: LZ4 Compress"
echo "=========================================="

LZ4_DIR="$PROJECT_ROOT/data_compression/L1/tests/lz4_compress"
cd "$LZ4_DIR"

echo "1. 清理旧文件..."
make clean

echo "2. 运行 C Simulation..."
make run TARGET=csim

echo "3. 运行 C Synthesis..."
make run TARGET=syn

echo "4. 运行 Co-simulation..."
make run TARGET=cosim

echo "5. 运行 Vivado Implementation (检查资源)..."
make run TARGET=vivado_impl

echo "✅ LZ4 Compress 完成！"
echo ""

# ==========================================
# 题目 3: Cholesky
# ==========================================
echo "=========================================="
echo "题目 3: Cholesky"
echo "=========================================="

CHOLESKY_DIR="$PROJECT_ROOT/solver/L1/tests/cholesky/complex_fixed_arch0"
cd "$CHOLESKY_DIR"

echo "1. 清理旧文件..."
make clean

echo "2. 运行 C Simulation..."
make run TARGET=csim

echo "3. 运行 C Synthesis..."
make run TARGET=syn

echo "4. 运行 Co-simulation..."
make run TARGET=cosim

echo "5. 运行 Vivado Implementation (检查资源)..."
make run TARGET=vivado_impl

echo "✅ Cholesky 完成！"
echo ""

echo "=========================================="
echo "✅ 所有测试完成！"
echo "=========================================="
echo ""
echo "请运行以下命令手动整理报告:"
echo "  ./organize_reports.sh"
echo ""
