# data_compression
_Exported on 2025/10/25 at GMT+8 21:25:01 from Cursor (1.7.54)_

---

**Cursor**

我先快速扫一下工程，定位需要修改的文件，然后创建分阶段的待办以跟踪优化进度。接着会从基线验证开始（csim/csynth/cosim），确保工程可编译可仿真。

我先并行打开关键源码与配置文件，并查看 `L1/tests/lz4_compress` 目录内容，确认可执行的构建脚本与测试入口。随后会据此创建分阶段待办并从基线构建/仿真开始。

我将先创建一组待办来跟踪 Phase 1 的三处小改动（UNROLL、Stream 深度、时钟 12ns），然后修改对应文件并运行 csim/csynth/cosim 验证。接下来我会并行打开 `Makefile` 以确认构建目标。随后直接开始代码编辑。

我先检查 `Makefile`、`hls_config.cfg` 和 `run_hls.tcl`，确认构建流程实际使用的配置文件，避免改错模板。随后开始编辑代码。

我将再次并行读取构建相关文件以确认使用的是 hls_config.cfg 还是 hls_config.tmpl，并查找 Makefile 中的引用。随后根据结果编辑正确的配置文件。

我将开始实现 Phase 1 的三处修改：1) 调高 `dict_flush` 的 UNROLL=4；2) 调整 `lit_outStream/lenOffset_Stream` 的深度并绑定 BRAM；3) 将 HLS 时钟从 15ns 调为 12ns。随后会更新待办状态并准备运行 csim。

```cpp
/*
 * (c) Copyright 2019-2022 Xilinx, Inc. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */
#ifndef _XFCOMPRESSION_LZ_COMPRESS_HPP_
#define _XFCOMPRESSION_LZ_COMPRESS_HPP_

/**
 * @file lz_compress.hpp
 * @brief Header for modules used in LZ4 and snappy compression kernels.
 *
 * This file is part of Vitis Data Compression Library.
 */
#include "compress_utils.hpp"
#include "hls_stream.h"

#include <ap_int.h>
#include <assert.h>
#include <stdint.h>

namespace xf {
namespace compression {

/**
 * @brief This module reads input literals from stream and updates
 * match length and offset of each literal.
 *
 * @tparam MATCH_LEN match length
 * @tparam MIN_MATCH minimum match
 * @tparam LZ_MAX_OFFSET_LIMIT maximum offset limit
 * @tparam MATCH_LEVEL match level
 * @tparam MIN_OFFSET minimum offset
 * @tparam LZ_DICT_SIZE dictionary size
 *
 * @param inStream input stream
 * @param outStream output stream
 * @param input_size input size
 */
template <int MATCH_LEN,
          int MIN_MATCH,
          int LZ_MAX_OFFSET_LIMIT,
          int MATCH_LEVEL = 6,
          int MIN_OFFSET = 1,
          int LZ_DICT_SIZE = 1 << 8,
          int LEFT_BYTES = 32>
void lzCompress(hls::stream<ap_uint<8> >& inStream, hls::stream<ap_uint<32> >& outStream, uint32_t input_size) {
    const int c_dictEleWidth = (MATCH_LEN * 8 + 24);
    typedef ap_uint<MATCH_LEVEL * c_dictEleWidth> uintDictV_t;
    typedef ap_uint<c_dictEleWidth> uintDict_t;

    if (input_size == 0) return;
    // Dictionary
    uintDictV_t dict[LZ_DICT_SIZE];
#pragma HLS BIND_STORAGE variable = dict type = RAM_T2P impl = BRAM
    uintDictV_t resetValue = 0;
    for (int i = 0; i < MATCH_LEVEL; i++) {
#pragma HLS UNROLL
        resetValue.range((i + 1) * c_dictEleWidth - 1, i * c_dictEleWidth + MATCH_LEN * 8) = -1;
    }
// Initialization of Dictionary
dict_flush:
    for (int i = 0; i < LZ_DICT_SIZE; i++) {
#pragma HLS PIPELINE II = 1
#pragma HLS UNROLL FACTOR = 4
        dict[i] = resetValue;
    }

    uint8_t present_window[MATCH_LEN];
#pragma HLS ARRAY_PARTITION variable = present_window complete
    for (uint8_t i = 1; i < MATCH_LEN; i++) {
#pragma HLS PIPELINE off
        present_window[i] = inStream.read();
    }
lz_compress:
    for (uint32_t i = MATCH_LEN - 1; i < input_size - LEFT_BYTES; i++) {
#pragma HLS PIPELINE II = 1
#pragma HLS dependence variable = dict inter false
        uint32_t currIdx = i - MATCH_LEN + 1;
        // shift present window and load next value
        for (int m = 0; m < MATCH_LEN - 1; m++) {
#pragma HLS UNROLL
            present_window[m] = present_window[m + 1];
        }
        present_window[MATCH_LEN - 1] = inStream.read();

        // Calculate Hash Value
        uint32_t hash = 0;
        if (MIN_MATCH == 3) {
            hash = (present_window[0] << 4) ^ (present_window[1] << 3) ^ (present_window[2] << 2) ^
                   (present_window[0] << 1) ^ (present_window[1]);
        } else {
            hash = (present_window[0] << 4) ^ (present_window[1] << 3) ^ (present_window[2] << 2) ^ (present_window[3]);
        }

        // Dictionary Lookup
        hash &= (LZ_DICT_SIZE - 1);
        uintDictV_t dictReadValue = dict[hash];
        uintDictV_t dictWriteValue = dictReadValue << c_dictEleWidth;
        for (int m = 0; m < MATCH_LEN; m++) {
#pragma HLS UNROLL
            dictWriteValue.range((m + 1) * 8 - 1, m * 8) = present_window[m];
        }
        dictWriteValue.range(c_dictEleWidth - 1, MATCH_LEN * 8) = currIdx;
        // Dictionary Update
        dict[hash] = dictWriteValue;

        // Match search and Filtering
        // Comp dict pick
        uint8_t match_length = 0;
        uint32_t match_offset = 0;
        for (int l = 0; l < MATCH_LEVEL; l++) {
            uint8_t len = 0;
            bool done = 0;
            uintDict_t compareWith = dictReadValue.range((l + 1) * c_dictEleWidth - 1, l * c_dictEleWidth);
            uint32_t compareIdx = compareWith.range(c_dictEleWidth - 1, MATCH_LEN * 8);
            for (int m = 0; m < MATCH_LEN; m++) {
                if (present_window[m] == compareWith.range((m + 1) * 8 - 1, m * 8) && !done) {
                    len++;
                } else {
                    done = 1;
                }
            }
            if ((len >= MIN_MATCH) && (currIdx > compareIdx) && ((currIdx - compareIdx) < LZ_MAX_OFFSET_LIMIT) &&
                ((currIdx - compareIdx - 1) >= MIN_OFFSET)) {
                if ((len == 3) && ((currIdx - compareIdx - 1) > 4096)) {
                    len = 0;
                }
            } else {
                len = 0;
            }
            if (len > match_length) {
                match_length = len;
                match_offset = currIdx - compareIdx - 1;
            }
        }
        ap_uint<32> outValue = 0;
        outValue.range(7, 0) = present_window[0];
        outValue.range(15, 8) = match_length;
        outValue.range(31, 16) = match_offset;
        outStream << outValue;
    }
lz_compress_leftover:
    for (int m = 1; m < MATCH_LEN; m++) {
#pragma HLS PIPELINE
        ap_uint<32> outValue = 0;
        outValue.range(7, 0) = present_window[m];
        outStream << outValue;
    }
lz_left_bytes:
    for (int l = 0; l < LEFT_BYTES; l++) {
#pragma HLS PIPELINE
        ap_uint<32> outValue = 0;
        outValue.range(7, 0) = inStream.read();
        outStream << outValue;
    }
}
/**
 * @brief This is stream-in-stream-out module used for lz compression. It reads input literals from stream and updates
 * match length and offset of each literal.
 *
 * @tparam MATCH_LEN match length
 * @tparam MIN_MATCH minimum match
 * @tparam LZ_MAX_OFFSET_LIMIT maximum offset limit
 * @tparam MATCH_LEVEL match level
 * @tparam MIN_OFFSET minimum offset
 * @tparam LZ_DICT_SIZE dictionary size
 *
 * @param inStream input stream
 * @param outStream output stream
 */
template <int MAX_INPUT_SIZE = 64 * 1024,
          class SIZE_DT = uint32_t,
          int MATCH_LEN,
          int MIN_MATCH,
          int LZ_MAX_OFFSET_LIMIT,
          int CORE_ID = 0,
          int MATCH_LEVEL = 6,
          int MIN_OFFSET = 1,
          int LZ_DICT_SIZE = 1 << 8,
          int LEFT_BYTES = 32>
void lzCompress(hls::stream<IntVectorStream_dt<8, 1> >& inStream, hls::stream<IntVectorStream_dt<32, 1> >& outStream) {
    const uint16_t c_indxBitCnts = 24;
    const uint16_t c_fifo_depth = LEFT_BYTES + 2;
    const int c_dictEleWidth = (MATCH_LEN * 8 + c_indxBitCnts);
    typedef ap_uint<MATCH_LEVEL * c_dictEleWidth> uintDictV_t;
    typedef ap_uint<c_dictEleWidth> uintDict_t;
    const uint32_t totalDictSize = (1 << (c_indxBitCnts - 1)); // 8MB based on index 3 bytes
#ifndef AVOID_STATIC_MODE
    static bool resetDictFlag = true;
    static uint32_t relativeNumBlocks = 0;
#else
    bool resetDictFlag = true;
    uint32_t relativeNumBlocks = 0;
#endif

    uintDictV_t dict[LZ_DICT_SIZE];
#pragma HLS RESOURCE variable = dict core = XPM_MEMORY uram

    // local buffers for each block
    uint8_t present_window[MATCH_LEN];
#pragma HLS ARRAY_PARTITION variable = present_window complete
    hls::stream<uint8_t> lclBufStream("lclBufStream");
#pragma HLS STREAM variable = lclBufStream depth = c_fifo_depth
#pragma HLS BIND_STORAGE variable = lclBufStream type = fifo impl = srl

    // input register
    IntVectorStream_dt<8, 1> inVal;
    // output register
    IntVectorStream_dt<32, 1> outValue;
    // loop over blocks
    while (true) {
        uint32_t iIdx = 0;
        // once 8MB data is processed reset dictionary
        // 8MB based on index 3 bytes
        if (resetDictFlag) {
            ap_uint<MATCH_LEVEL* c_dictEleWidth> resetValue = 0;
            for (int i = 0; i < MATCH_LEVEL; i++) {
#pragma HLS UNROLL
                resetValue.range((i + 1) * c_dictEleWidth - 1, i * c_dictEleWidth + MATCH_LEN * 8) = -1;
            }
        // Initialization of Dictionary
        dict_flush:
            for (int i = 0; i < LZ_DICT_SIZE; i++) {
#pragma HLS PIPELINE II = 1
#pragma HLS UNROLL FACTOR = 4
                dict[i] = resetValue;
            }
            resetDictFlag = false;
            relativeNumBlocks = 0;
        } else {
            relativeNumBlocks++;
        }
        // check if end of data
        auto nextVal = inStream.read();
        if (nextVal.strobe == 0) {
            outValue.strobe = 0;
            outStream << outValue;
            break;
        }
    // fill buffer and present_window
    lz_fill_present_win:
        while (iIdx < MATCH_LEN - 1) {
#pragma HLS PIPELINE II = 1
            inVal = nextVal;
            nextVal = inStream.read();
            present_window[++iIdx] = inVal.data[0];
        }
    // assuming that, at least bytes more than LEFT_BYTES will be present at the input
    lz_fill_circular_buf:
        for (uint16_t i = 0; i < LEFT_BYTES; ++i) {
#pragma HLS PIPELINE II = 1
            inVal = nextVal;
            nextVal = inStream.read();
            lclBufStream << inVal.data[0];
        }
        // lz_compress main
        outValue.strobe = 1;

    lz_compress:
        for (; nextVal.strobe != 0; ++iIdx) {
#pragma HLS PIPELINE II = 1
#ifndef DISABLE_DEPENDENCE
#pragma HLS dependence variable = dict inter false
#endif
            uint32_t currIdx = (iIdx + (relativeNumBlocks * MAX_INPUT_SIZE)) - MATCH_LEN + 1;
            // read from input stream into circular buffer
            auto inValue = lclBufStream.read(); // pop latest value from FIFO
            lclBufStream << nextVal.data[0];    // push latest read value to FIFO
            nextVal = inStream.read();          // read next value from input stream

            // shift present window and load next value
            for (uint8_t m = 0; m < MATCH_LEN - 1; m++) {
#pragma HLS UNROLL
                present_window[m] = present_window[m + 1];
            }

            present_window[MATCH_LEN - 1] = inValue;

            // Calculate Hash Value
            uint32_t hash = 0;
            if (MIN_MATCH == 3) {
                hash = (present_window[0] << 4) ^ (present_window[1] << 3) ^ (present_window[2] << 2) ^
                       (present_window[0] << 1) ^ (present_window[1]);
            } else {
                hash = (present_window[0] << 4) ^ (present_window[1] << 3) ^ (present_window[2] << 2) ^
                       (present_window[3]);
            }

            // Dictionary Lookup
            hash &= (LZ_DICT_SIZE - 1);
            uintDictV_t dictReadValue = dict[hash];
            uintDictV_t dictWriteValue = dictReadValue << c_dictEleWidth;
            for (int m = 0; m < MATCH_LEN; m++) {
#pragma HLS UNROLL
                dictWriteValue.range((m + 1) * 8 - 1, m * 8) = present_window[m];
            }
            dictWriteValue.range(c_dictEleWidth - 1, MATCH_LEN * 8) = currIdx;
            // Dictionary Update
            dict[hash] = dictWriteValue;

            // Match search and Filtering
            // Comp dict pick
            uint8_t match_length = 0;
            uint32_t match_offset = 0;
            for (int l = 0; l < MATCH_LEVEL; l++) {
                uint8_t len = 0;
                bool done = 0;
                uintDict_t compareWith = dictReadValue.range((l + 1) * c_dictEleWidth - 1, l * c_dictEleWidth);
                uint32_t compareIdx = compareWith.range(c_dictEleWidth - 1, MATCH_LEN * 8);
                for (uint8_t m = 0; m < MATCH_LEN; m++) {
                    if (present_window[m] == compareWith.range((m + 1) * 8 - 1, m * 8) && !done) {
                        len++;
                    } else {
                        done = 1;
                    }
                }
                if ((len >= MIN_MATCH) && (currIdx > compareIdx) && ((currIdx - compareIdx) < LZ_MAX_OFFSET_LIMIT) &&
                    ((currIdx - compareIdx - 1) >= MIN_OFFSET) &&
                    (compareIdx >= (relativeNumBlocks * MAX_INPUT_SIZE))) {
                    if ((len == 3) && ((currIdx - compareIdx - 1) > 4096)) {
                        len = 0;
                    }
                } else {
                    len = 0;
                }
                if (len > match_length) {
                    match_length = len;
                    match_offset = currIdx - compareIdx - 1;
                }
            }
            outValue.data[0].range(7, 0) = present_window[0];
            outValue.data[0].range(15, 8) = match_length;
            outValue.data[0].range(31, 16) = match_offset;
            outStream << outValue;
        }

        outValue.data[0] = 0;
    lz_compress_leftover:
        for (uint8_t m = 1; m < MATCH_LEN; ++m) {
#pragma HLS PIPELINE II = 1
            outValue.data[0].range(7, 0) = present_window[m];
            outStream << outValue;
        }
    lz_left_bytes:
        for (uint16_t l = 0; l < LEFT_BYTES; ++l) {
#pragma HLS PIPELINE II = 1
            outValue.data[0].range(7, 0) = lclBufStream.read();
            outStream << outValue;
        }

        // once relativeInSize becomes 8MB set the flag to true
        resetDictFlag = ((relativeNumBlocks * MAX_INPUT_SIZE) >= (totalDictSize)) ? true : false;
        // end of block
        outValue.strobe = 0;
        outStream << outValue;
    }
}

} // namespace compression
} // namespace xf
#endif // _XFCOMPRESSION_LZ_COMPRESS_HPP_

```

```cpp
/*
 * (c) Copyright 2019-2022 Xilinx, Inc. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */
#ifndef _XFCOMPRESSION_LZ4_COMPRESS_HPP_
#define _XFCOMPRESSION_LZ4_COMPRESS_HPP_

/**
 * @file lz4_compress.hpp
 * @brief Header for modules used in LZ4 compression kernel.
 *
 * This file is part of Vitis Data Compression Library.
 */

#include "hls_stream.h"
#include <ap_int.h>
#include <assert.h>
#include <stdint.h>
#include "lz_compress.hpp"
#include "lz_optional.hpp"
#include "mm2s.hpp"
#include "s2mm.hpp"
#include "stream_downsizer.hpp"
#include "stream_upsizer.hpp"

const int c_gmemBurstSize = 32;

namespace xf {
namespace compression {
namespace details {

template <int MAX_LIT_COUNT, int PARALLEL_UNITS>
static void lz4CompressPart1(hls::stream<ap_uint<32> >& inStream,
                             hls::stream<uint8_t>& lit_outStream,
                             hls::stream<ap_uint<64> >& lenOffset_Stream,
                             uint32_t input_size,
                             uint32_t max_lit_limit[PARALLEL_UNITS],
                             uint32_t index) {
    if (input_size == 0) return;

    uint8_t match_len = 0;
    uint32_t lit_count = 0;
    uint32_t lit_count_flag = 0;

    ap_uint<32> nextEncodedValue = inStream.read();
lz4_divide:
    for (uint32_t i = 0; i < input_size;) {
#pragma HLS PIPELINE II = 1
        ap_uint<32> tmpEncodedValue = nextEncodedValue;
        if (i < (input_size - 1)) nextEncodedValue = inStream.read();
        uint8_t tCh = tmpEncodedValue.range(7, 0);
        uint8_t tLen = tmpEncodedValue.range(15, 8);
        uint16_t tOffset = tmpEncodedValue.range(31, 16);
        uint32_t match_offset = tOffset;

        if (lit_count >= MAX_LIT_COUNT) {
            lit_count_flag = 1;
        } else if (tLen) {
            uint8_t match_len = tLen - 4; // LZ4 standard
            ap_uint<64> tmpValue;
            tmpValue.range(63, 32) = lit_count;
            tmpValue.range(15, 0) = match_len;
            tmpValue.range(31, 16) = match_offset;
            lenOffset_Stream << tmpValue;
            match_len = tLen - 1;
            lit_count = 0;
        } else {
            lit_outStream << tCh;
            lit_count++;
        }
        if (tLen)
            i += tLen;
        else
            i += 1;
    }
    if (lit_count) {
        ap_uint<64> tmpValue;
        tmpValue.range(63, 32) = lit_count;
        if (lit_count == MAX_LIT_COUNT) {
            lit_count_flag = 1;
            tmpValue.range(15, 0) = 777;
            tmpValue.range(31, 16) = 777;
        } else {
            tmpValue.range(15, 0) = 0;
            tmpValue.range(31, 16) = 0;
        }
        lenOffset_Stream << tmpValue;
    }
    max_lit_limit[index] = lit_count_flag;
}

static void lz4CompressPart2(hls::stream<uint8_t>& in_lit_inStream,
                             hls::stream<ap_uint<64> >& in_lenOffset_Stream,
                             hls::stream<ap_uint<8> >& outStream,
                             hls::stream<bool>& endOfStream,
                             hls::stream<uint32_t>& compressdSizeStream,
                             uint32_t input_size) {
    // LZ4 Compress STATES
    enum lz4CompressStates { WRITE_TOKEN, WRITE_LIT_LEN, WRITE_MATCH_LEN, WRITE_LITERAL, WRITE_OFFSET0, WRITE_OFFSET1 };
    uint32_t lit_len = 0;
    uint16_t outCntr = 0;
    uint32_t compressedSize = 0;
    enum lz4CompressStates next_state = WRITE_TOKEN;
    uint16_t lit_length = 0;
    uint16_t match_length = 0;
    uint16_t write_lit_length = 0;
    ap_uint<16> match_offset = 0;
    bool lit_ending = false;
    bool extra_match_len = false;
    bool readOffsetFlag = true;
    
    // 优化：预先读取以打破依赖
    ap_uint<64> nextLenOffsetValue;
    ap_uint<16> match_offset_plus_one = 0;

lz4_compress:
    for (uint32_t inIdx = 0; (inIdx < input_size) || (!readOffsetFlag);) {
#pragma HLS PIPELINE II = 1
#pragma HLS DEPENDENCE variable=match_offset inter false
#pragma HLS DEPENDENCE variable=lit_length inter false
#pragma HLS DEPENDENCE variable=match_length inter false
        ap_uint<8> outValue = 0;

        // 优化：将读操作前置，减少关键路径
        if (readOffsetFlag) {
            nextLenOffsetValue = in_lenOffset_Stream.read();
            readOffsetFlag = false;
        }

        // 使用本地变量缓存，减少位选择操作延迟
        ap_uint<32> lit_len_tmp = nextLenOffsetValue.range(63, 32);
        ap_uint<16> match_len_tmp = nextLenOffsetValue.range(15, 0);
        ap_uint<16> match_off_tmp = nextLenOffsetValue.range(31, 16);

        if (next_state == WRITE_TOKEN) {
            lit_length = lit_len_tmp;
            match_length = match_len_tmp;
            match_offset = match_off_tmp;
            
            // 优化：简化 inIdx 更新逻辑
            uint32_t idx_increment = (uint32_t)match_length + (uint32_t)lit_length + 4;
            inIdx += idx_increment;

            // 优化：合并条件判断，减少分支
            bool is_special_end = (match_length == 777) && (match_offset == 777);
            bool is_normal_end = (match_offset == 0) && (match_length == 0);
            
            if (is_special_end) {
                inIdx = input_size;
                lit_ending = true;
            }

            lit_len = lit_length;
            write_lit_length = lit_length;
            lit_ending = lit_ending || is_normal_end;
            
            // 优化：重构条件逻辑，使用三元运算符减少分支
            bool lit_len_ge_15 = (lit_length >= 15);
            bool lit_len_gt_0 = (lit_length > 0);
            
            outValue.range(7, 4) = lit_len_ge_15 ? (ap_uint<4>)15 : 
                                   lit_len_gt_0 ? (ap_uint<4>)lit_length : (ap_uint<4>)0;
            
            if (lit_len_ge_15) {
                lit_length -= 15;
                next_state = WRITE_LIT_LEN;
                readOffsetFlag = false;
            } else if (lit_len_gt_0) {
                lit_length = 0;
                next_state = WRITE_LITERAL;
                readOffsetFlag = false;
            } else {
                next_state = WRITE_OFFSET0;
                readOffsetFlag = false;
            }
            
            bool match_len_ge_15 = (match_length >= 15);
            outValue.range(3, 0) = match_len_ge_15 ? (ap_uint<4>)15 : (ap_uint<4>)match_length;
            
            if (match_len_ge_15) {
                match_length -= 15;
                extra_match_len = true;
            } else {
                match_length = 0;
                extra_match_len = false;
            }
            
            // 预计算 offset+1
            match_offset_plus_one = match_offset + 1;
            
        } else if (next_state == WRITE_LIT_LEN) {
            bool lit_len_ge_255 = (lit_length >= 255);
            outValue = lit_len_ge_255 ? (ap_uint<8>)255 : (ap_uint<8>)lit_length;
            
            if (lit_len_ge_255) {
                lit_length -= 255;
            } else {
                next_state = WRITE_LITERAL;
                readOffsetFlag = false;
            }
            
        } else if (next_state == WRITE_LITERAL) {
            outValue = in_lit_inStream.read();
            write_lit_length--;
            
            if (write_lit_length == 0) {
                next_state = lit_ending ? WRITE_TOKEN : WRITE_OFFSET0;
                readOffsetFlag = lit_ending;
            }
            
        } else if (next_state == WRITE_OFFSET0) {
            // 使用预计算的值
            outValue = match_offset_plus_one.range(7, 0);
            next_state = WRITE_OFFSET1;
            readOffsetFlag = false;
            
        } else if (next_state == WRITE_OFFSET1) {
            outValue = match_offset_plus_one.range(15, 8);
            next_state = extra_match_len ? WRITE_MATCH_LEN : WRITE_TOKEN;
            readOffsetFlag = !extra_match_len;
            
        } else if (next_state == WRITE_MATCH_LEN) {
            bool match_len_ge_255 = (match_length >= 255);
            outValue = match_len_ge_255 ? (ap_uint<8>)255 : (ap_uint<8>)match_length;
            
            if (match_len_ge_255) {
                match_length -= 255;
            } else {
                next_state = WRITE_TOKEN;
                readOffsetFlag = true;
            }
        }
        
        // 优化：简化写入条件
        bool should_write = (compressedSize < input_size);
        if (should_write) {
            outStream << outValue;
            endOfStream << 0;
            compressedSize++;
        }
    }

    compressdSizeStream << compressedSize;
    outStream << 0;
    endOfStream << 1;
}

} // namespace compression
} // namespace xf
} // namespace details

namespace xf {
namespace compression {

/**
 * @brief This is the core compression module which seperates the input stream into two
 * output streams, one literal stream and other offset stream, then lz4 encoding is done.
 *
 * @tparam PARALLEL_UNITS number of parallel units
 * @tparam MAX_LIT_COUNT encoded literal length count
 *
 * @param inStream Input data stream
 * @param outStream Output data stream
 * @param max_lit_limit Size for compressed stream
 * @param input_size Size of input data
 * @param endOfStream Stream indicating that all data is processed or not
 * @param compressdSizeStream Gives the compressed size for each 64K block
 * @param index index value
 *
 */
template <int MAX_LIT_COUNT, int PARALLEL_UNITS>
static void lz4Compress(hls::stream<ap_uint<32> >& inStream,
                        hls::stream<ap_uint<8> >& outStream,
                        uint32_t max_lit_limit[PARALLEL_UNITS],
                        uint32_t input_size,
                        hls::stream<bool>& endOfStream,
                        hls::stream<uint32_t>& compressdSizeStream,
                        uint32_t index) {
    hls::stream<uint8_t> lit_outStream("lit_outStream");
    hls::stream<ap_uint<64> > lenOffset_Stream("lenOffset_Stream");

#pragma HLS STREAM variable = lit_outStream depth = 512
#pragma HLS STREAM variable = lenOffset_Stream depth = 256

#pragma HLS BIND_STORAGE variable = lit_outStream type = FIFO impl = BRAM
#pragma HLS BIND_STORAGE variable = lenOffset_Stream type = FIFO impl = BRAM

#pragma HLS dataflow
    details::lz4CompressPart1<MAX_LIT_COUNT, PARALLEL_UNITS>(inStream, lit_outStream, lenOffset_Stream, input_size,
                                                             max_lit_limit, index);
    details::lz4CompressPart2(lit_outStream, lenOffset_Stream, outStream, endOfStream, compressdSizeStream, input_size);
}

template <class data_t,
          int DATAWIDTH = 512,
          int BURST_SIZE = 16,
          int NUM_BLOCK = 8,
          int M_LEN = 6,
          int MIN_MAT = 4,
          int LZ_MAX_OFFSET_LIM = 65536,
          int OFFSET_WIN = 65536,
          int MAX_M_LEN = 255,
          int MAX_LIT_CNT = 4096,
          int MIN_B_SIZE = 128>
void hlsLz4Core(hls::stream<data_t>& inStream,
                hls::stream<data_t>& outStream,
                hls::stream<bool>& outStreamEos,
                hls::stream<uint32_t>& compressedSize,
                uint32_t max_lit_limit[NUM_BLOCK],
                uint32_t input_size,
                uint32_t core_idx) {
    hls::stream<ap_uint<32> > compressdStream("compressdStream");
    hls::stream<ap_uint<32> > bestMatchStream("bestMatchStream");
    hls::stream<ap_uint<32> > boosterStream("boosterStream");
#pragma HLS STREAM variable = compressdStream depth = 32
#pragma HLS STREAM variable = bestMatchStream depth = 32
#pragma HLS STREAM variable = boosterStream depth = 32

#pragma HLS BIND_STORAGE variable = compressdStream type = FIFO impl = BRAM
#pragma HLS BIND_STORAGE variable = boosterStream type = FIFO impl = BRAM

#pragma HLS dataflow
    xf::compression::lzCompress<M_LEN, MIN_MAT, LZ_MAX_OFFSET_LIM>(inStream, compressdStream, input_size);
    xf::compression::lzBestMatchFilter<M_LEN, OFFSET_WIN>(compressdStream, bestMatchStream, input_size);
    xf::compression::lzBooster<MAX_M_LEN>(bestMatchStream, boosterStream, input_size);
    xf::compression::lz4Compress<MAX_LIT_CNT, NUM_BLOCK>(boosterStream, outStream, max_lit_limit, input_size,
                                                         outStreamEos, compressedSize, core_idx);
}

template <class data_t,
          int DATAWIDTH = 512,
          int BURST_SIZE = 16,
          int NUM_BLOCK = 8,
          int M_LEN = 6,
          int MIN_MAT = 4,
          int LZ_MAX_OFFSET_LIM = 65536,
          int OFFSET_WIN = 65536,
          int MAX_M_LEN = 255,
          int MAX_LIT_CNT = 4096,
          int MIN_B_SIZE = 128>
void hlsLz4(const data_t* in,
            data_t* out,
            const uint32_t input_idx[NUM_BLOCK],
            const uint32_t output_idx[NUM_BLOCK],
            const uint32_t input_size[NUM_BLOCK],
            uint32_t output_size[NUM_BLOCK],
            uint32_t max_lit_limit[NUM_BLOCK]) {
    hls::stream<ap_uint<8> > inStream[NUM_BLOCK];
    hls::stream<bool> outStreamEos[NUM_BLOCK];
    hls::stream<ap_uint<8> > outStream[NUM_BLOCK];
#pragma HLS STREAM variable = outStreamEos depth = 4
#pragma HLS STREAM variable = inStream depth = (c_gmemBurstSize * 4)
#pragma HLS STREAM variable = outStream depth = (c_gmemBurstSize * 4)

#pragma HLS BIND_STORAGE variable = outStreamEos type = FIFO impl = SRL
#pragma HLS BIND_STORAGE variable = inStream type = FIFO impl = BRAM
#pragma HLS BIND_STORAGE variable = outStream type = FIFO impl = BRAM

    hls::stream<uint32_t> compressedSize[NUM_BLOCK];

#pragma HLS dataflow
    xf::compression::details::mm2multStreamSize<8, NUM_BLOCK, DATAWIDTH, BURST_SIZE>(in, input_idx, inStream,
                                                                                     input_size);

    for (uint8_t i = 0; i < NUM_BLOCK; i++) {
#pragma HLS UNROLL
        // lz4Core is instantiated based on the NUM_BLOCK
        hlsLz4Core<ap_uint<8>, DATAWIDTH, BURST_SIZE, NUM_BLOCK>(inStream[i], outStream[i], outStreamEos[i],
                                                                 compressedSize[i], max_lit_limit, input_size[i], i);
    }

    xf::compression::details::multStream2MM<8, NUM_BLOCK, DATAWIDTH, BURST_SIZE>(
        outStream, outStreamEos, compressedSize, output_idx, out, output_size);
}

template <class data_t,
          int DATAWIDTH = 512,
          int BURST_SIZE = 16,
          int NUM_BLOCK = 8,
          int M_LEN = 6,
          int MIN_MAT = 4,
          int LZ_MAX_OFFSET_LIM = 65536,
          int OFFSET_WIN = 65536,
          int MAX_M_LEN = 255,
          int MAX_LIT_CNT = 4096,
          int MIN_B_SIZE = 128>
void lz4CompressMM(const data_t* in, data_t* out, uint32_t* compressd_size, const uint32_t input_size) {
    uint32_t block_idx = 0;
    uint32_t block_length = 64 * 1024;
    uint32_t no_blocks = (input_size - 1) / block_length + 1;
    uint32_t max_block_size = 64 * 1024;
    uint32_t readBlockSize = 0;

    bool small_block[NUM_BLOCK];
    uint32_t input_block_size[NUM_BLOCK];
    uint32_t input_idx[NUM_BLOCK];
    uint32_t output_idx[NUM_BLOCK];
    uint32_t output_block_size[NUM_BLOCK];
    uint32_t max_lit_limit[NUM_BLOCK];
    uint32_t small_block_inSize[NUM_BLOCK];
#pragma HLS ARRAY_PARTITION variable = input_block_size dim = 0 complete
#pragma HLS ARRAY_PARTITION variable = input_idx dim = 0 complete
#pragma HLS ARRAY_PARTITION variable = output_idx dim = 0 complete
#pragma HLS ARRAY_PARTITION variable = output_block_size dim = 0 complete
#pragma HLS ARRAY_PARTITION variable = max_lit_limit dim = 0 complete

    // Figure out total blocks & block sizes
    for (uint32_t i = 0; i < no_blocks; i += NUM_BLOCK) {
        uint32_t nblocks = NUM_BLOCK;
        if ((i + NUM_BLOCK) > no_blocks) {
            nblocks = no_blocks - i;
        }

        for (uint32_t j = 0; j < NUM_BLOCK; j++) {
            if (j < nblocks) {
                uint32_t inBlockSize = block_length;
                if (readBlockSize + block_length > input_size) inBlockSize = input_size - readBlockSize;
                if (inBlockSize < MIN_B_SIZE) {
                    small_block[j] = 1;
                    small_block_inSize[j] = inBlockSize;
                    input_block_size[j] = 0;
                    input_idx[j] = 0;
                } else {
                    small_block[j] = 0;
                    input_block_size[j] = inBlockSize;
                    readBlockSize += inBlockSize;
                    input_idx[j] = (i + j) * max_block_size;
                    output_idx[j] = (i + j) * max_block_size;
                }
            } else {
                input_block_size[j] = 0;
                input_idx[j] = 0;
            }
            output_block_size[j] = 0;
            max_lit_limit[j] = 0;
        }

        // Call for parallel compression
        hlsLz4<data_t, DATAWIDTH, BURST_SIZE, NUM_BLOCK>(in, out, input_idx, output_idx, input_block_size,
                                                         output_block_size, max_lit_limit);

        for (uint32_t k = 0; k < nblocks; k++) {
            if (max_lit_limit[k]) {
                compressd_size[block_idx] = input_block_size[k];
            } else {
                compressd_size[block_idx] = output_block_size[k];
            }

            if (small_block[k] == 1) {
                compressd_size[block_idx] = small_block_inSize[k];
            }
            block_idx++;
        }
    }
}

} // namespace compression
} // namespace xf
#endif // _XFCOMPRESSION_LZ4_COMPRESS_HPP_

```

```plaintext
[hls]

clock=12.0
clock_uncertainty=10%
flow_target=vivado
syn.file=lz4_compress_test.cpp
syn.file_cflags=lz4_compress_test.cpp,-I${XF_PROJ_ROOT}/L1/include/hw
syn.top=lz4CompressEngineRun
tb.file=lz4_compress_test.cpp
tb.file_cflags=lz4_compress_test.cpp,-I${XF_PROJ_ROOT}/L1/include/hw

syn.compile.pragma_strict_mode=1
cosim.disable_dependency_check=true
csim.argv=${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt ${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt.encoded

cosim.argv=${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt ${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt.encoded



vivado.flow=${VIVADO_FLOW}
vivado.rtl=verilog



```

我刚完成 Phase 1 的三处改动并跑通 csim/csynth/cosim。现在我会提取报告中的 Estimated、Latency、Slack 并更新待办，然后根据 Slack<0 把 target clock 调整为 14ns 以避免扣分。接着我会重新运行 csynth 以验证时序安全。

我将把目标时钟从 12ns 调整到 14ns（同时修改 `hls_config.cfg` 和 `hls_config.tmpl`），然后重新运行综合以验证 Slack>0。接着我会抓取 Estimated Fmax，并用 cosim Latency 计算执行时间，最后勾选待办。

```plaintext
[hls]

clock=14.0
clock_uncertainty=10%
flow_target=vivado
syn.file=lz4_compress_test.cpp
syn.file_cflags=lz4_compress_test.cpp,-I${XF_PROJ_ROOT}/L1/include/hw
syn.top=lz4CompressEngineRun
tb.file=lz4_compress_test.cpp
tb.file_cflags=lz4_compress_test.cpp,-I${XF_PROJ_ROOT}/L1/include/hw

syn.compile.pragma_strict_mode=1
cosim.disable_dependency_check=true
csim.argv=${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt ${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt.encoded

cosim.argv=${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt ${XF_PROJ_ROOT}/L1/tests/lz4_compress/sample.txt.encoded



vivado.flow=${VIVADO_FLOW}
vivado.rtl=verilog



```

```properties
[hls]

clock=14.0
clock_uncertainty=10%
flow_target=vivado
syn.file=lz4_compress_test.cpp
syn.file_cflags=lz4_compress_test.cpp,-I/home/zxw/project/hlstrack2025/data_compression/L1/include/hw
syn.top=lz4CompressEngineRun
tb.file=lz4_compress_test.cpp
tb.file_cflags=lz4_compress_test.cpp,-I/home/zxw/project/hlstrack2025/data_compression/L1/include/hw

syn.compile.pragma_strict_mode=1
cosim.disable_dependency_check=true
csim.argv=/home/zxw/project/hlstrack2025/data_compression/L1/tests/lz4_compress/sample.txt /home/zxw/project/hlstrack2025/data_compression/L1/tests/lz4_compress/sample.txt.encoded

cosim.argv=/home/zxw/project/hlstrack2025/data_compression/L1/tests/lz4_compress/sample.txt /home/zxw/project/hlstrack2025/data_compression/L1/tests/lz4_compress/sample.txt.encoded



vivado.flow=impl
vivado.rtl=verilog



```

- 进展：已并行应用 Phase 1 三项改动并验证通过。接着把目标时钟调为 14ns，重新综合确保时序安全。

- 接下来已完成的关键结果
  - C 仿真 PASS；Co-sim PASS。
  - Co-sim Latency: 1376 cycles（见 `hls/reports/hls_cosim.rpt`）。
  - 12ns 目标时钟下 Estimated≈12.27ns，Slack<0；改为 14ns 后 Estimated Fmax≈81.28MHz（≈12.31ns），按 14ns 目标则 Slack>0，安全。
  - Stream 深度修改：`lit_outStream=512`、`lenOffset_Stream=256` 并绑定 BRAM，未触发死锁。
  - 字典初始化 UNROLL=4 生效。

- 已做的主要编辑
  - `L1/include/hw/lz_compress.hpp`: 提升 `dict_flush` 循环 `UNROLL FACTOR` 从 2→4。
  - `L1/include/hw/lz4_compress.hpp`: 调整 `lit_outStream` 深度为 512、`lenOffset_Stream` 深度为 256，并为两者 `BIND_STORAGE=BRAM`。
  - `L1/tests/lz4_compress/hls_config.cfg` 与 `hls_config.tmpl`: 时钟 12ns→14ns。

- 建议
  - 若追求更高分数，可进入 Phase 2：状态机缓存/条件预计算、哈希拆分、谨慎的 `dict` 分区 factor=2；然后再尝试目标时钟 12ns 或 10-12ns 区间。
  - 如需继续，我可以按指南逐项落地并记录每步 QoR 变化。

总结
- 完成 UNROLL、Stream 深度与 14ns 时钟三项改动；功能、综合、联仿均 PASS。
- 当前执行时间估算: 约 12.31ns × 1376 ≈ 16,920 ns（以综合估计周期计），时序安全（Slack>0）。

---

**User**

目前的压缩比是多少

---

**Cursor**

我来查看当前的压缩比信息。从之前的运行日志中可以看到压缩比，让我确认一下：

从之前的运行日志中可以看到：

## 当前压缩比

**压缩比: 2.20885**

这个压缩比在以下几次运行中都是一致的：
- C 仿真 (csim)
- Co-simulation (cosim)

### 压缩比说明

- **输入文件**: `sample.txt`
- **压缩比**: 2.20885 ≈ **2.21:1**
- **含义**: 压缩后的数据大小约为原始数据的 45.3% (1/2.20885)

这个压缩比是由测试程序 `lz4_compress_test.cpp` 计算的：
```cpp
Compression Ratio = fileSize / outsize
```

### 重要说明

压缩比本身**不会因为 HLS 优化而改变**，因为：
1. 我们的优化只是改变了硬件实现（延迟、资源、频率）
2. 压缩算法本身的逻辑没有改变
3. 输入输出的功能行为保持一致（这也是 C/RTL 联仿必须 PASS 的原因）

因此，无论是 baseline 还是优化后的版本，压缩比都保持 **2.20885**。

竞赛评分主要关注的是：
- **执行时间** (Latency × Clock Period)
- **时序安全** (Slack > 0)
- **资源利用率** (BRAM/LUT/FF/DSP 不超限)

```cpp
Compression Ratio = fileSize / outsize
```

