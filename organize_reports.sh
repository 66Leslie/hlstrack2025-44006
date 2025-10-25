#!/bin/bash
# HLS Track 2025 - 自动整理 reports 目录脚本
# 用途: 将所有必需的报告文件复制到各题目的 reports/ 目录

set -e  # 遇到错误立即退出

echo "=========================================="
echo "HLS Track 2025 - 整理 reports 目录"
echo "=========================================="
echo ""

# 定义项目根目录
PROJECT_ROOT="/home/zxw/project/hlstrack2025"

# ==========================================
# 题目 1: SHA-256
# ==========================================
echo "📁 整理 SHA-256 reports..."
SHA256_DIR="$PROJECT_ROOT/security/L1/tests/hmac/sha256"
SHA256_REPORTS="$SHA256_DIR/reports"

# 确保 reports 目录存在
mkdir -p "$SHA256_REPORTS"

# 复制 csynth.xml
if [ -f "$SHA256_DIR/hls/hls/syn/report/csynth.xml" ]; then
    cp "$SHA256_DIR/hls/hls/syn/report/csynth.xml" "$SHA256_REPORTS/"
    echo "  ✅ 复制 csynth.xml"
else
    echo "  ❌ 未找到 csynth.xml"
fi

# 复制 csim.log (如果存在)
if [ -f "$SHA256_DIR/hls/hls/csim/report/test_hmac_sha256_csim.log" ]; then
    cp "$SHA256_DIR/hls/hls/csim/report/test_hmac_sha256_csim.log" "$SHA256_REPORTS/"
    echo "  ✅ 复制 test_hmac_sha256_csim.log"
else
    echo "  ⚠️  未找到 test_hmac_sha256_csim.log (可能需要重新运行 csim)"
fi

# cosim.rpt 已经存在
if [ -f "$SHA256_REPORTS/test_hmac_sha256_cosim.rpt" ]; then
    echo "  ✅ test_hmac_sha256_cosim.rpt 已存在"
else
    echo "  ❌ 未找到 test_hmac_sha256_cosim.rpt"
fi

echo ""

# ==========================================
# 题目 2: LZ4 Compress
# ==========================================
echo "📁 整理 LZ4 Compress reports..."
LZ4_DIR="$PROJECT_ROOT/data_compression/L1/tests/lz4_compress"
LZ4_REPORTS="$LZ4_DIR/reports"

# 确保 reports 目录存在
mkdir -p "$LZ4_REPORTS"

# 复制 csynth.xml
if [ -f "$LZ4_DIR/hls/hls/syn/report/csynth.xml" ]; then
    cp "$LZ4_DIR/hls/hls/syn/report/csynth.xml" "$LZ4_REPORTS/"
    echo "  ✅ 复制 csynth.xml"
else
    echo "  ❌ 未找到 csynth.xml"
fi

# 复制 csim.log
if [ -f "$LZ4_DIR/hls/hls/csim/report/lz4CompressEngineRun_csim.log" ]; then
    cp "$LZ4_DIR/hls/hls/csim/report/lz4CompressEngineRun_csim.log" "$LZ4_REPORTS/"
    echo "  ✅ 复制 lz4CompressEngineRun_csim.log"
else
    echo "  ⚠️  未找到 lz4CompressEngineRun_csim.log (可能需要重新运行 csim)"
fi

# 复制 cosim.rpt (从 hls/reports/)
if [ -f "$LZ4_DIR/hls/reports/hls_cosim.rpt" ]; then
    cp "$LZ4_DIR/hls/reports/hls_cosim.rpt" "$LZ4_REPORTS/"
    echo "  ✅ 复制 hls_cosim.rpt"
else
    echo "  ❌ 未找到 hls_cosim.rpt"
fi

echo ""

# ==========================================
# 题目 3: Cholesky
# ==========================================
echo "📁 整理 Cholesky reports..."
CHOLESKY_DIR="$PROJECT_ROOT/solver/L1/tests/cholesky/complex_fixed_arch0"
CHOLESKY_REPORTS="$CHOLESKY_DIR/reports"

# 确保 reports 目录存在
mkdir -p "$CHOLESKY_REPORTS"

# 复制 csynth.xml
if [ -f "$CHOLESKY_DIR/hls/hls/syn/report/csynth.xml" ]; then
    cp "$CHOLESKY_DIR/hls/hls/syn/report/csynth.xml" "$CHOLESKY_REPORTS/"
    echo "  ✅ 复制 csynth.xml"
else
    echo "  ❌ 未找到 csynth.xml"
fi

# 复制 csim.log
if [ -f "$CHOLESKY_DIR/hls/hls/csim/report/kernel_cholesky_0_csim.log" ]; then
    cp "$CHOLESKY_DIR/hls/hls/csim/report/kernel_cholesky_0_csim.log" "$CHOLESKY_REPORTS/"
    echo "  ✅ 复制 kernel_cholesky_0_csim.log"
else
    echo "  ⚠️  未找到 kernel_cholesky_0_csim.log (可能需要重新运行 csim)"
fi

# 复制 cosim.rpt
if [ -f "$CHOLESKY_DIR/hls/hls/sim/report/kernel_cholesky_0_cosim.rpt" ]; then
    cp "$CHOLESKY_DIR/hls/hls/sim/report/kernel_cholesky_0_cosim.rpt" "$CHOLESKY_REPORTS/"
    echo "  ✅ 复制 kernel_cholesky_0_cosim.rpt"
else
    echo "  ❌ 未找到 kernel_cholesky_0_cosim.rpt"
fi

echo ""

# ==========================================
# 总结
# ==========================================
echo "=========================================="
echo "📊 整理完成！检查结果："
echo "=========================================="
echo ""

echo "SHA-256 reports 目录:"
ls -lh "$SHA256_REPORTS" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
echo ""

echo "LZ4 Compress reports 目录:"
ls -lh "$LZ4_REPORTS" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
echo ""

echo "Cholesky reports 目录:"
ls -lh "$CHOLESKY_REPORTS" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
echo ""

echo "=========================================="
echo "✅ 所有 reports 目录已整理完成！"
echo "=========================================="
echo ""
echo "下一步操作："
echo "1. 检查上述文件列表，确认所有必需文件都已复制"
echo "2. 撰写设计报告 (参考 命题式基础赛道报告模板.md)"
echo "3. 将仓库推送到 Gitee/GitHub"
echo "4. 创建压缩包: zip -r hlstrack2025_队伍编码.zip hlstrack2025/"
echo ""

