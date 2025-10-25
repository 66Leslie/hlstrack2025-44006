#!/bin/bash
# HLS Track 2025 - 完整重建脚本
# 用途: 清理所有题目，重新运行 csim, csynth, cosim，并整理 reports

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

echo "✅ Cholesky 完成！"
echo ""

# ==========================================
# 整理 reports 目录
# ==========================================
echo "=========================================="
echo "整理 reports 目录"
echo "=========================================="

cd "$PROJECT_ROOT"

# SHA-256
echo "整理 SHA-256 reports..."
SHA256_REPORTS="$SHA256_DIR/reports"
mkdir -p "$SHA256_REPORTS"

cp "$SHA256_DIR/hls/hls/syn/report/csynth.xml" "$SHA256_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 csynth.xml"
cp "$SHA256_DIR/hls/hls/csim/report/test_hmac_sha256_csim.log" "$SHA256_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 csim.log"
cp "$SHA256_DIR/hls/hls/sim/report/test_hmac_sha256_cosim.rpt" "$SHA256_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 cosim.rpt"

echo "SHA-256 reports 目录:"
ls -lh "$SHA256_REPORTS"
echo ""

# LZ4
echo "整理 LZ4 Compress reports..."
LZ4_REPORTS="$LZ4_DIR/reports"
mkdir -p "$LZ4_REPORTS"

cp "$LZ4_DIR/hls/hls/syn/report/csynth.xml" "$LZ4_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 csynth.xml"
cp "$LZ4_DIR/hls/hls/csim/report/lz4CompressEngineRun_csim.log" "$LZ4_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 csim.log"
cp "$LZ4_DIR/hls/reports/hls_cosim.rpt" "$LZ4_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 cosim.rpt"

echo "LZ4 Compress reports 目录:"
ls -lh "$LZ4_REPORTS"
echo ""

# Cholesky
echo "整理 Cholesky reports..."
CHOLESKY_REPORTS="$CHOLESKY_DIR/reports"
mkdir -p "$CHOLESKY_REPORTS"

cp "$CHOLESKY_DIR/hls/hls/syn/report/csynth.xml" "$CHOLESKY_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 csynth.xml"
cp "$CHOLESKY_DIR/hls/hls/csim/report/kernel_cholesky_0_csim.log" "$CHOLESKY_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 csim.log"
cp "$CHOLESKY_DIR/hls/hls/sim/report/kernel_cholesky_0_cosim.rpt" "$CHOLESKY_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到 cosim.rpt"

echo "Cholesky reports 目录:"
ls -lh "$CHOLESKY_REPORTS"
echo ""

# ==========================================
# 验证结果
# ==========================================
echo "=========================================="
echo "验证结果"
echo "=========================================="

echo ""
echo "SHA-256 Cosim 结果:"
grep -A 2 "Verilog" "$SHA256_REPORTS/test_hmac_sha256_cosim.rpt" 2>/dev/null || echo "  ⚠️  未找到 cosim 结果"

echo ""
echo "LZ4 Compress Cosim 结果:"
grep -A 2 "Verilog" "$LZ4_REPORTS/hls_cosim.rpt" 2>/dev/null || echo "  ⚠️  未找到 cosim 结果"

echo ""
echo "Cholesky Cosim 结果:"
grep -A 2 "Verilog" "$CHOLESKY_REPORTS/kernel_cholesky_0_cosim.rpt" 2>/dev/null || echo "  ⚠️  未找到 cosim 结果"

echo ""
echo "=========================================="
echo "✅ 所有测试完成！"
echo "=========================================="
echo ""
echo "下一步: 运行 python3 detailed_comparison.py 查看详细得分"

