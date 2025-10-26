#!/bin/bash
# HLS Track 2025 - 报告整理脚本
# 用途: 整理所有题目的报告到 reports 目录和统一的 Reports 目录

PROJECT_ROOT="/home/zxw/project/hlstrack2025"

echo "=========================================="
echo "整理报告文件"
echo "=========================================="
echo ""

# ==========================================
# SHA-256 (提交要求的四个文件)
# ==========================================
echo "整理 SHA-256 reports..."
SHA256_DIR="$PROJECT_ROOT/security/L1/tests/hmac/sha256"
SHA256_REPORTS="$SHA256_DIR/reports"
mkdir -p "$SHA256_REPORTS"

echo "  复制 csynth.xml..."
cp "$SHA256_DIR/hls/hls/syn/report/csynth.xml" "$SHA256_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 test_hmac_sha256_cosim.rpt..."
cp "$SHA256_DIR/hls/reports/hls_cosim.rpt" "$SHA256_REPORTS/test_hmac_sha256_cosim.rpt" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 test_hmac_sha256_csim.log..."
cp "$SHA256_DIR/hls/hls/csim/report/test_hmac_sha256_csim.log" "$SHA256_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 export_impl.rpt..."
cp "$SHA256_DIR/hls/hls/impl/report/verilog/export_impl.rpt" "$SHA256_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "SHA-256 reports (提交要求):"
ls -lh "$SHA256_REPORTS"
echo ""

# ==========================================
# LZ4 (提交要求的四个文件)
# ==========================================
echo "整理 LZ4 Compress reports..."
LZ4_DIR="$PROJECT_ROOT/data_compression/L1/tests/lz4_compress"
LZ4_REPORTS="$LZ4_DIR/reports"
mkdir -p "$LZ4_REPORTS"

echo "  复制 csynth.xml..."
cp "$LZ4_DIR/hls/hls/syn/report/csynth.xml" "$LZ4_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 lz4CompressEngineRun_cosim.rpt..."
cp "$LZ4_DIR/hls/reports/hls_cosim.rpt" "$LZ4_REPORTS/lz4CompressEngineRun_cosim.rpt" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 lz4CompressEngineRun_csim.log..."
# LZ4 的 csim log 可能在不同位置
if [ -f "$LZ4_DIR/hls/hls/csim/report/lz4CompressEngineRun_csim.log" ]; then
    cp "$LZ4_DIR/hls/hls/csim/report/lz4CompressEngineRun_csim.log" "$LZ4_REPORTS/"
elif [ -f "$LZ4_DIR/reports/lz4CompressEngineRun_csim.log" ]; then
    echo "  (csim.log 已存在于 reports/)"
else
    echo "  ⚠️  未找到 csim.log"
fi

echo "  复制 export_impl.rpt..."
cp "$LZ4_DIR/hls/hls/impl/report/verilog/export_impl.rpt" "$LZ4_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "LZ4 Compress reports (提交要求):"
ls -lh "$LZ4_REPORTS"
echo ""

# ==========================================
# Cholesky (提交要求的四个文件)
# ==========================================
echo "整理 Cholesky reports..."
CHOLESKY_DIR="$PROJECT_ROOT/solver/L1/tests/cholesky/complex_fixed_arch0"
CHOLESKY_REPORTS="$CHOLESKY_DIR/reports"
mkdir -p "$CHOLESKY_REPORTS"

echo "  复制 csynth.xml..."
cp "$CHOLESKY_DIR/hls/hls/syn/report/csynth.xml" "$CHOLESKY_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 kernel_cholesky_0_cosim.rpt..."
cp "$CHOLESKY_DIR/hls/reports/hls_cosim.rpt" "$CHOLESKY_REPORTS/kernel_cholesky_0_cosim.rpt" 2>/dev/null || echo "  ⚠️  未找到"

echo "  复制 kernel_cholesky_0_csim.log..."
# Cholesky 的 csim log 可能已经在 reports 目录
if [ -f "$CHOLESKY_DIR/hls/hls/csim/report/kernel_cholesky_0_csim.log" ]; then
    cp "$CHOLESKY_DIR/hls/hls/csim/report/kernel_cholesky_0_csim.log" "$CHOLESKY_REPORTS/"
elif [ -f "$CHOLESKY_DIR/reports/kernel_cholesky_0_csim.log" ]; then
    echo "  (csim.log 已存在于 reports/)"
else
    echo "  ⚠️  未找到 csim.log"
fi

echo "  复制 export_impl.rpt..."
cp "$CHOLESKY_DIR/hls/hls/impl/report/verilog/export_impl.rpt" "$CHOLESKY_REPORTS/" 2>/dev/null || echo "  ⚠️  未找到"

echo "Cholesky reports (提交要求):"
ls -lh "$CHOLESKY_REPORTS"
echo ""

# ==========================================
# 复制到统一的 Reports 目录
# ==========================================
echo "=========================================="
echo "整理统一 Reports 目录"
echo "=========================================="

UNIFIED_REPORTS="$PROJECT_ROOT/Reports"
mkdir -p "$UNIFIED_REPORTS/sha256"
mkdir -p "$UNIFIED_REPORTS/lz4"
mkdir -p "$UNIFIED_REPORTS/cholesky"

echo "复制 SHA-256 报告..."
cp -r "$SHA256_REPORTS"/* "$UNIFIED_REPORTS/sha256/" 2>/dev/null
echo "✅ 已复制到 Reports/sha256/"

echo "复制 LZ4 报告..."
cp -r "$LZ4_REPORTS"/* "$UNIFIED_REPORTS/lz4/" 2>/dev/null
echo "✅ 已复制到 Reports/lz4/"

echo "复制 Cholesky 报告..."
cp -r "$CHOLESKY_REPORTS"/* "$UNIFIED_REPORTS/cholesky/" 2>/dev/null
echo "✅ 已复制到 Reports/cholesky/"

echo ""
echo "=========================================="
echo "验证报告文件"
echo "=========================================="
echo ""

# 显示 SHA-256 Cosim 结果
echo "SHA-256 Cosim 结果:"
if [ -f "$SHA256_REPORTS/test_hmac_sha256_cosim.rpt" ]; then
    grep -A 2 "Verilog" "$SHA256_REPORTS/test_hmac_sha256_cosim.rpt" 2>/dev/null || echo "  ⚠️  无法解析"
else
    echo "  ⚠️  文件不存在"
fi

echo ""
echo "LZ4 Compress Cosim 结果:"
if [ -f "$LZ4_REPORTS/lz4CompressEngineRun_cosim.rpt" ]; then
    grep -A 2 "Verilog" "$LZ4_REPORTS/lz4CompressEngineRun_cosim.rpt" 2>/dev/null || echo "  ⚠️  无法解析"
else
    echo "  ⚠️  文件不存在"
fi

echo ""
echo "Cholesky Cosim 结果:"
if [ -f "$CHOLESKY_REPORTS/kernel_cholesky_0_cosim.rpt" ]; then
    grep -A 2 "Verilog" "$CHOLESKY_REPORTS/kernel_cholesky_0_cosim.rpt" 2>/dev/null || echo "  ⚠️  无法解析"
else
    echo "  ⚠️  文件不存在"
fi

echo ""
echo "=========================================="
echo "生成对比报告"
echo "=========================================="
python3 "$PROJECT_ROOT/generate_comparison.py"
echo ""
echo "📊 对比报告已生成到 Reports/comparison_report.md"
echo ""
