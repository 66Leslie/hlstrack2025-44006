# Security
_Exported on 2025/10/21 at GMT+8 23:24:16 from Cursor (1.7.53)_

---

**User**

由于竞赛组委会更新细则@README.md @命题式基础赛道初赛评分细则.md 我们需要根据新的要求，重新对HLS进行优化，这是我之前的优化记录，你可以查看，并且根据最新要求做出适合的修改@sha256_opt.md 

---

**Cursor**

我先创建任务清单并开始阅读新规与当前实现，以比对需要调整的点，随后再做代码修改与验证。接下来我会并行读取 `README.md`、`命题式基础赛道初赛评分细则.md` 以及 `security/L1/include/xf_security/sha224_256.hpp`。

我将并行读取新规与关键实现文件，以便比对差异后立刻给出修改方案并开始编辑。接下来会读取 `README.md`、`命题式基础赛道初赛评分细则.md`、以及当前实现的 `sha256_opt.md`（含优化记录）与核心头文件。

我将查阅当前头文件与测试目录，确认接口与可修改的时钟脚本位置，以便按新规（执行时间=估计周期×Latency）做针对性调整。随后我会据此修改头文件和Makefile/Tcl的时钟设置。现在读取头文件并列出测试目录内容。

我刚阅读了新规和现有头文件，接下来我会检查 SHA-256 的测试 Makefile/Tcl 时钟配置，并确认应优先使用的测试路径，然后评估是否需要在 `*.hpp` 或时钟脚本中做修改。现在并行读取两个测试路径的 Makefile 和 Tcl。

我将搜索测试入口符号以确认使用哪个测试路径与顶层函数名称，从而运行仿真与综合。随后会根据结果生成/执行命令。

我将把新规差异落实为代码：在 `sha224_256.hpp` 内实现四发射消息调度与每拍四轮压缩，并在 `sha256_top` 改为128位内部通道。同时保持外部接口不变，满足“仅改头文件与时钟”的要求。接着我会应用编辑。

```cpp
/*
 * Copyright 2019 Xilinx, Inc.
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
 */

#ifndef _XF_SECURITY_SHA224_256_HPP_
#define _XF_SECURITY_SHA224_256_HPP_

#include <ap_int.h>
#include <hls_stream.h>

#include "xf_security/types.hpp"
#include "xf_security/utils.hpp"

// For debug
#ifndef __SYNTHESIS__
#include <cstdio>
#endif
#ifndef _DEBUG
#define _DEBUG (0)
#endif
#define _XF_SECURITY_VOID_CAST static_cast<void>
// XXX toggle here to debug this file
#define _XF_SECURITY_PRINT(msg...) \
    do {                           \
        if (_DEBUG) printf(msg);   \
    } while (0)

#define ROTR(n, x) ((x >> n) | (x << (32 - n)))
#define ROTL(n, x) ((x << n) | (x >> (32 - n)))
#define SHR(n, x) (x >> n)
#define CH(x, y, z) ((x & y) ^ ((~x) & z))
#define MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define BSIG0(x) (ROTR(2, x) ^ ROTR(13, x) ^ ROTR(22, x))
#define BSIG1(x) (ROTR(6, x) ^ ROTR(11, x) ^ ROTR(25, x))
#define SSIG0(x) (ROTR(7, x) ^ ROTR(18, x) ^ SHR(3, x))
#define SSIG1(x) (ROTR(17, x) ^ ROTR(19, x) ^ SHR(10, x))

namespace xf {
namespace security {
namespace internal {

/// Processing block
struct SHA256Block {
    uint32_t M[16];
};

/// @brief Static config for SHA224 and SHA256.
template <bool do_sha224>
struct sha256_digest_config;

template <>
struct sha256_digest_config<true> {
    static const short numH = 7;
};

template <>
struct sha256_digest_config<false> {
    static const short numH = 8;
};

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<32> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete
        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                uint32_t l = msg_strm.read();
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32bx16)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
        } else if (left < 56) {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_AND_ONE:
            for (int i = 0; i < 14; ++i) {
#pragma HLS pipeline
                if (i < (left >> 2)) {
                    uint32_t l = msg_strm.read();
                    // pad 1 byte not in this word
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 not in this word, and no word to read.
                    b.M[i] = 0UL;
                } else {
                    // pad 1 byte in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // cannot append L.

            /// last but 1 block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
        // copy and pad 1
        LOOP_SHA256_GEN_COPY_TAIL_ONLY:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                if (i < (left >> 2)) {
                    // pad 1 byte not in this word
                    uint32_t l = msg_strm.read();
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 byte not in this word, and no msg word to read
                    b.M[i] = 0UL;
                } else {
                    // last in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");

            /// last block.
            SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
        LOOP_SHA256_GEN_L_ONLY_BLK:
            for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                b1.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
            }
            // append L
            b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b1.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

            blk_strm.write(b1);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (32-bit ver)

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<64> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        _XF_SECURITY_PRINT("DEBUG: working on a new message of %ld bytes\n", len);
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete

        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; i += 2) {
#pragma HLS unroll
                uint64_t ll = msg_strm.read().to_uint64();
                // low
                uint32_t l = ll & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 low)\n", i, b0.M[i]);
                // high
                l = (ll >> 32) & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i + 1] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 high)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_PAD_ONE:
            for (int i = 0; i < ((left < 56) ? 7 : 8); ++i) {
#pragma HLS pipeline
                if (i < (left >> 3)) {
                    // pad 1 not in this 64b word, and need to copy
                    uint64_t ll = msg_strm.read().to_uint64();
                    // low
                    uint32_t l = ll & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i * 2, b.M[i * 2]);
                    // high
                    l = (ll >> 32) & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2 + 1] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b high)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else if (i > (left >> 3)) {
                    // pad 1 not in this 64b word, and no word to read.
                    b.M[i * 2] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2, b.M[i * 2]);
                    b.M[i * 2 + 1] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else {
                    // pad 1 byte in this 64b word
                    if ((left & 4) == 0) {
                        // left in low 32b
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2] = 0x80000000UL;
                        } else if (e == 1) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2] = l | 0x00800000UL;
                        } else if (e == 2) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2] = l | 0x00008000UL;
                        } else {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2, b.M[i * 2]);
                        // high
                        b.M[i * 2 + 1] = 0UL;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    } else {
                        // left in high 32b
                        uint64_t ll = msg_strm.read().to_uint64();
                        // low 32b
                        uint32_t l = ll & 0xffffffffUL;
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                            ((0xff000000UL & l) >> 24);
                        b.M[i * 2] = l;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i, b.M[i * 2]);
                        // high 32b
                        l = (ll >> 32) & 0xffffffffUL;
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2 + 1] = 0x80000000UL;
                        } else if (e == 1) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2 + 1] = l | 0x00800000UL;
                        } else if (e == 2) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2 + 1] = l | 0x00008000UL;
                        } else {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2 + 1] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    }
                }
            }

            if (left < 56) {
                // append L
                b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } else {
                // send block without L
                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");

                /// last block.
                SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
            LOOP_SHA256_GEN_L_ONLY_BLK:
                for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                    b1.M[i] = 0;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
                }
                // append L
                b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b1.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

                blk_strm.write(b1);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } // left < 56
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (64bit ver)

inline void dup_strm(hls::stream<uint64_t>& in_strm,
                     hls::stream<bool>& in_e_strm,
                     hls::stream<uint64_t>& out1_strm,
                     hls::stream<bool>& out1_e_strm,
                     hls::stream<uint64_t>& out2_strm,
                     hls::stream<bool>& out2_e_strm) {
    bool e = in_e_strm.read();

    while (!e) {
#pragma HLS loop_tripcount min = 1 max = 1 avg = 1
#pragma HLS pipeline II = 1
        uint64_t in_r = in_strm.read();

        out1_strm.write(in_r);
        out1_e_strm.write(false);
        out2_strm.write(in_r);
        out2_e_strm.write(false);

        e = in_e_strm.read();
    }

    out1_e_strm.write(true);
    out2_e_strm.write(true);
}

inline void generateMsgSchedule(hls::stream<SHA256Block>& blk_strm,
                                hls::stream<uint64_t>& nblk_strm,
                                hls::stream<bool>& end_nblk_strm,
                                hls::stream<ap_uint<128> >& w4_strm) {
    bool e = end_nblk_strm.read();
    while (!e) {
        uint64_t n = nblk_strm.read();
        for (uint64_t i = 0; i < n; ++i) {
#pragma HLS latency max = 65

            SHA256Block blk = blk_strm.read();
#pragma HLS array_partition variable = blk.M complete

            /// message schedule W, from message or
            uint32_t W[16];
#pragma HLS array_partition variable = W complete

        // Seed first 16 words and emit four at a time
        LOOP_SHA256_PREPARE_WT16_PACK:
            for (short t = 0; t < 16; t += 4) {
#pragma HLS pipeline II = 1
                uint32_t w0 = blk.M[t + 0];
                uint32_t w1 = blk.M[t + 1];
                uint32_t w2 = blk.M[t + 2];
                uint32_t w3 = blk.M[t + 3];
                W[t + 0] = w0;
                W[t + 1] = w1;
                W[t + 2] = w2;
                W[t + 3] = w3;
                ap_uint<128> pack;
                pack.range(31, 0) = w0;
                pack.range(63, 32) = w1;
                pack.range(95, 64) = w2;
                pack.range(127, 96) = w3;
                w4_strm.write(pack);
            }

        // Extend words and emit in groups of four using a 16-word sliding window
        LOOP_SHA256_PREPARE_WT64_PACK:
            for (short t = 16; t < 64; t += 4) {
#pragma HLS pipeline II = 1
#pragma HLS DEPENDENCE variable = W inter false
                uint32_t wt0 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                // shift and insert wt0
                for (unsigned char j = 0; j < 15; ++j) {
                    W[j] = W[j + 1];
                }
                W[15] = wt0;

                uint32_t wt1 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j1 = 0; j1 < 15; ++j1) {
                    W[j1] = W[j1 + 1];
                }
                W[15] = wt1;

                uint32_t wt2 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j2 = 0; j2 < 15; ++j2) {
                    W[j2] = W[j2 + 1];
                }
                W[15] = wt2;

                uint32_t wt3 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j3 = 0; j3 < 15; ++j3) {
                    W[j3] = W[j3 + 1];
                }
                W[15] = wt3;

                ap_uint<128> pack;
                pack.range(31, 0) = wt0;
                pack.range(63, 32) = wt1;
                pack.range(95, 64) = wt2;
                pack.range(127, 96) = wt3;
                w4_strm.write(pack);
            }
        }
        e = end_nblk_strm.read();
    }
}

inline void sha256_iter(uint32_t& a,
                        uint32_t& b,
                        uint32_t& c,
                        uint32_t& d,
                        uint32_t& e,
                        uint32_t& f,
                        uint32_t& g,
                        uint32_t& h,
                        hls::stream<uint32_t>& w_strm,
                        uint32_t& Kt,
                        const uint32_t K[],
                        short t) {
    uint32_t Wt = w_strm.read();
    /// temporal variables
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    // update working variables.
    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    _XF_SECURITY_PRINT(
        "DEBUG: Kt=%08x, Wt=%08x\n"
        "\ta=%08x, b=%08x, c=%08x, d=%08x\n"
        "\te=%08x, f=%08x, g=%08x, h=%08x\n",
        Kt, Wt, a, b, c, d, e, f, g, h);

    // for next cycle
    Kt = K[(t + 1) & 63];
}

/// @brief Digest message blocks and emit final hash.
/// @tparam h_width the hash width(type).
/// @param nblk_strm number of message block.
/// @param end_nblk_strm end flag for number of message block.
/// @param hash_strm the hash result stream.
/// @param end_hash_strm end flag for hash result.
template <int h_width>
void sha256Digest(hls::stream<uint64_t>& nblk_strm,
                  hls::stream<bool>& end_nblk_strm,
                  hls::stream<uint32_t>& w_strm,
                  hls::stream<ap_uint<h_width> >& hash_strm,
                  hls::stream<bool>& end_hash_strm) {
    // h_width determine the hash type.
    XF_SECURITY_STATIC_ASSERT((h_width == 256) || (h_width == 224),
                              "Unsupported hash stream width, must be 224 or 256");

    /// constant K
    static const uint32_t K[64] = {
        0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
        0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL, 0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
        0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
        0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
        0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL, 0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
        0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
        0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
        0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL, 0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};
#pragma HLS array_partition variable = K complete

LOOP_SHA256_DIGEST_MAIN:
    for (bool end_flag = end_nblk_strm.read(); !end_flag; end_flag = end_nblk_strm.read()) {
        /// total number blocks to digest.
        uint64_t blk_num = nblk_strm.read();
        // _XF_SECURITY_PRINT("expect %ld blocks.\n", blk_num);

        /// internal states
        uint32_t H[8];
#pragma HLS array_partition variable = H complete

        // initialize
        if (h_width == 224) {
            H[0] = 0xc1059ed8UL;
            H[1] = 0x367cd507UL;
            H[2] = 0x3070dd17UL;
            H[3] = 0xf70e5939UL;
            H[4] = 0xffc00b31UL;
            H[5] = 0x68581511UL;
            H[6] = 0x64f98fa7UL;
            H[7] = 0xbefa4fa4UL;
        } else {
            H[0] = 0x6a09e667UL;
            H[1] = 0xbb67ae85UL;
            H[2] = 0x3c6ef372UL;
            H[3] = 0xa54ff53aUL;
            H[4] = 0x510e527fUL;
            H[5] = 0x9b05688cUL;
            H[6] = 0x1f83d9abUL;
            H[7] = 0x5be0cd19UL;
        }

    LOOP_SHA256_DIGEST_NBLK:
        for (uint64_t n = 0; n < blk_num; ++n) {
#pragma HLS loop_tripcount min = 1 max = 1
#pragma HLS latency max = 65

            /// working variables.
            uint32_t a, b, c, d, e, f, g, h;

            // loading working variables.
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];
            e = H[4];
            f = H[5];
            g = H[6];
            h = H[7];

            uint32_t Kt = K[0];
        LOOP_SHA256_UPDATE_64_ROUNDS:
            for (short t = 0; t < 64; ++t) {
#pragma HLS pipeline II = 1
                sha256_iter(a, b, c, d, e, f, g, h, w_strm, Kt, K, t);
            } // 64 round loop

            // store working variables to internal states.
            H[0] = a + H[0];
            H[1] = b + H[1];
            H[2] = c + H[2];
            H[3] = d + H[3];
            H[4] = e + H[4];
            H[5] = f + H[5];
            H[6] = g + H[6];
            H[7] = h + H[7];
        } // block loop

        // Emit digest
        if (h_width == 224) {
            ap_uint<224> w224;
        LOOP_SHA256_EMIT_H224:
            for (short i = 0; i < sha256_digest_config<true>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w224.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w224);
        } else {
            ap_uint<256> w256;
        LOOP_SHA256_EMIT_H256:
            for (short i = 0; i < sha256_digest_config<false>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w256.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w256);
        }
        end_hash_strm.write(false);
    } // main loop
    end_hash_strm.write(true);

} // sha256Digest (pipelined override)

/// @brief SHA-256/224 implementation top overload for ap_uint input.
/// @tparam m_width the input message stream width.
/// @tparam h_width the output hash stream width.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed in byte.
/// @param end_len_strm end flag stream of input, one per message.
/// @param hash_strm the result.
/// @param end_hash_strm end falg stream of output, one per hash.
template <int m_width, int h_width>
inline void sha256_top(hls::stream<ap_uint<m_width> >& msg_strm,
                       hls::stream<ap_uint<64> >& len_strm,
                       hls::stream<bool>& end_len_strm,
                       hls::stream<ap_uint<h_width> >& hash_strm,
                       hls::stream<bool>& end_hash_strm) {
#pragma HLS DATAFLOW
    /// 512-bit Block stream
    hls::stream<SHA256Block> blk_strm("blk_strm");
#pragma HLS STREAM variable = blk_strm depth = 32
#pragma HLS RESOURCE variable = blk_strm core = FIFO_LUTRAM

    /// number of Blocks, send per msg
    hls::stream<uint64_t> nblk_strm("nblk_strm");
#pragma HLS STREAM variable = nblk_strm depth = 32
#pragma HLS RESOURCE variable = nblk_strm core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm1("nblk_strm1");
#pragma HLS STREAM variable = nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = nblk_strm1 core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm2("nblk_strm2");
#pragma HLS STREAM variable = nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = nblk_strm2 core = FIFO_LUTRAM

    /// end flag, send per msg.
    hls::stream<bool> end_nblk_strm("end_nblk_strm");
#pragma HLS STREAM variable = end_nblk_strm depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm1("end_nblk_strm1");
#pragma HLS STREAM variable = end_nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm1 core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm2("end_nblk_strm2");
#pragma HLS STREAM variable = end_nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm2 core = FIFO_LUTRAM

    /// W, 64 items for each block
    hls::stream<uint32_t> w_strm("w_strm");
#pragma HLS STREAM variable = w_strm depth = 32
#pragma HLS RESOURCE variable = w_strm core = FIFO_LUTRAM

    // Generate block stream
    preProcessing(msg_strm, len_strm, end_len_strm, //
                  blk_strm, nblk_strm, end_nblk_strm);

    // Duplicate number of block stream and its end flag stream
    dup_strm(nblk_strm, end_nblk_strm, nblk_strm1, end_nblk_strm1, nblk_strm2, end_nblk_strm2);

    // Generate the message schedule in stream
    generateMsgSchedule(blk_strm, nblk_strm1, end_nblk_strm1, w_strm);

    // Digest block stream, and write hash stream.
    // fully pipelined version will calculate SHA-224 if hash_strm width is 224.
    sha256Digest(nblk_strm2, end_nblk_strm2, w_strm, //
                 hash_strm, end_hash_strm);
} // sha256_top
} // namespace internal

/// @brief SHA-224 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha224(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<224> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}

/// @brief SHA-256 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha256(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<256> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}
} // namespace security
} // namespace xf

// Clean up macros.
#undef ROTR
#undef ROTL
#undef SHR
#undef CH
#undef MAJ
#undef BSIG0
#undef BSIG1
#undef SSIG0
#undef SSIG1

#undef _XF_SECURITY_PRINT
#undef _XF_SECURITY_VOID_CAST

#endif // XF_SECURITY_SHA2_H
// -*- cpp -*-
// vim: ts=8:sw=2:sts=2:ft=cpp

```

我已开始在头文件中实现四发射，下一步我会更新 `sha256Digest` 与 `sha256_top` 以接入 `ap_uint<128>` 流，并新增按值版 `sha256_iter`。完成后我会运行语法检查。

```cpp
/*
 * Copyright 2019 Xilinx, Inc.
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
 */

#ifndef _XF_SECURITY_SHA224_256_HPP_
#define _XF_SECURITY_SHA224_256_HPP_

#include <ap_int.h>
#include <hls_stream.h>

#include "xf_security/types.hpp"
#include "xf_security/utils.hpp"

// For debug
#ifndef __SYNTHESIS__
#include <cstdio>
#endif
#ifndef _DEBUG
#define _DEBUG (0)
#endif
#define _XF_SECURITY_VOID_CAST static_cast<void>
// XXX toggle here to debug this file
#define _XF_SECURITY_PRINT(msg...) \
    do {                           \
        if (_DEBUG) printf(msg);   \
    } while (0)

#define ROTR(n, x) ((x >> n) | (x << (32 - n)))
#define ROTL(n, x) ((x << n) | (x >> (32 - n)))
#define SHR(n, x) (x >> n)
#define CH(x, y, z) ((x & y) ^ ((~x) & z))
#define MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define BSIG0(x) (ROTR(2, x) ^ ROTR(13, x) ^ ROTR(22, x))
#define BSIG1(x) (ROTR(6, x) ^ ROTR(11, x) ^ ROTR(25, x))
#define SSIG0(x) (ROTR(7, x) ^ ROTR(18, x) ^ SHR(3, x))
#define SSIG1(x) (ROTR(17, x) ^ ROTR(19, x) ^ SHR(10, x))

namespace xf {
namespace security {
namespace internal {

/// Processing block
struct SHA256Block {
    uint32_t M[16];
};

/// @brief Static config for SHA224 and SHA256.
template <bool do_sha224>
struct sha256_digest_config;

template <>
struct sha256_digest_config<true> {
    static const short numH = 7;
};

template <>
struct sha256_digest_config<false> {
    static const short numH = 8;
};

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<32> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete
        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                uint32_t l = msg_strm.read();
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32bx16)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
        } else if (left < 56) {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_AND_ONE:
            for (int i = 0; i < 14; ++i) {
#pragma HLS pipeline
                if (i < (left >> 2)) {
                    uint32_t l = msg_strm.read();
                    // pad 1 byte not in this word
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 not in this word, and no word to read.
                    b.M[i] = 0UL;
                } else {
                    // pad 1 byte in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // cannot append L.

            /// last but 1 block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
        // copy and pad 1
        LOOP_SHA256_GEN_COPY_TAIL_ONLY:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                if (i < (left >> 2)) {
                    // pad 1 byte not in this word
                    uint32_t l = msg_strm.read();
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 byte not in this word, and no msg word to read
                    b.M[i] = 0UL;
                } else {
                    // last in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");

            /// last block.
            SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
        LOOP_SHA256_GEN_L_ONLY_BLK:
            for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                b1.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
            }
            // append L
            b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b1.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

            blk_strm.write(b1);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (32-bit ver)

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<64> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        _XF_SECURITY_PRINT("DEBUG: working on a new message of %ld bytes\n", len);
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete

        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; i += 2) {
#pragma HLS unroll
                uint64_t ll = msg_strm.read().to_uint64();
                // low
                uint32_t l = ll & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 low)\n", i, b0.M[i]);
                // high
                l = (ll >> 32) & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i + 1] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 high)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_PAD_ONE:
            for (int i = 0; i < ((left < 56) ? 7 : 8); ++i) {
#pragma HLS pipeline
                if (i < (left >> 3)) {
                    // pad 1 not in this 64b word, and need to copy
                    uint64_t ll = msg_strm.read().to_uint64();
                    // low
                    uint32_t l = ll & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i * 2, b.M[i * 2]);
                    // high
                    l = (ll >> 32) & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2 + 1] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b high)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else if (i > (left >> 3)) {
                    // pad 1 not in this 64b word, and no word to read.
                    b.M[i * 2] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2, b.M[i * 2]);
                    b.M[i * 2 + 1] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else {
                    // pad 1 byte in this 64b word
                    if ((left & 4) == 0) {
                        // left in low 32b
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2] = 0x80000000UL;
                        } else if (e == 1) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2] = l | 0x00800000UL;
                        } else if (e == 2) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2] = l | 0x00008000UL;
                        } else {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2, b.M[i * 2]);
                        // high
                        b.M[i * 2 + 1] = 0UL;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    } else {
                        // left in high 32b
                        uint64_t ll = msg_strm.read().to_uint64();
                        // low 32b
                        uint32_t l = ll & 0xffffffffUL;
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                            ((0xff000000UL & l) >> 24);
                        b.M[i * 2] = l;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i, b.M[i * 2]);
                        // high 32b
                        l = (ll >> 32) & 0xffffffffUL;
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2 + 1] = 0x80000000UL;
                        } else if (e == 1) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2 + 1] = l | 0x00800000UL;
                        } else if (e == 2) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2 + 1] = l | 0x00008000UL;
                        } else {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2 + 1] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    }
                }
            }

            if (left < 56) {
                // append L
                b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } else {
                // send block without L
                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");

                /// last block.
                SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
            LOOP_SHA256_GEN_L_ONLY_BLK:
                for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                    b1.M[i] = 0;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
                }
                // append L
                b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b1.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

                blk_strm.write(b1);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } // left < 56
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (64bit ver)

inline void dup_strm(hls::stream<uint64_t>& in_strm,
                     hls::stream<bool>& in_e_strm,
                     hls::stream<uint64_t>& out1_strm,
                     hls::stream<bool>& out1_e_strm,
                     hls::stream<uint64_t>& out2_strm,
                     hls::stream<bool>& out2_e_strm) {
    bool e = in_e_strm.read();

    while (!e) {
#pragma HLS loop_tripcount min = 1 max = 1 avg = 1
#pragma HLS pipeline II = 1
        uint64_t in_r = in_strm.read();

        out1_strm.write(in_r);
        out1_e_strm.write(false);
        out2_strm.write(in_r);
        out2_e_strm.write(false);

        e = in_e_strm.read();
    }

    out1_e_strm.write(true);
    out2_e_strm.write(true);
}

inline void generateMsgSchedule(hls::stream<SHA256Block>& blk_strm,
                                hls::stream<uint64_t>& nblk_strm,
                                hls::stream<bool>& end_nblk_strm,
                                hls::stream<ap_uint<128> >& w4_strm) {
    bool e = end_nblk_strm.read();
    while (!e) {
        uint64_t n = nblk_strm.read();
        for (uint64_t i = 0; i < n; ++i) {
#pragma HLS latency max = 65

            SHA256Block blk = blk_strm.read();
#pragma HLS array_partition variable = blk.M complete

            /// message schedule W, from message or
            uint32_t W[16];
#pragma HLS array_partition variable = W complete

        // Seed first 16 words and emit four at a time
        LOOP_SHA256_PREPARE_WT16_PACK:
            for (short t = 0; t < 16; t += 4) {
#pragma HLS pipeline II = 1
                uint32_t w0 = blk.M[t + 0];
                uint32_t w1 = blk.M[t + 1];
                uint32_t w2 = blk.M[t + 2];
                uint32_t w3 = blk.M[t + 3];
                W[t + 0] = w0;
                W[t + 1] = w1;
                W[t + 2] = w2;
                W[t + 3] = w3;
                ap_uint<128> pack;
                pack.range(31, 0) = w0;
                pack.range(63, 32) = w1;
                pack.range(95, 64) = w2;
                pack.range(127, 96) = w3;
                w4_strm.write(pack);
            }

        // Extend words and emit in groups of four using a 16-word sliding window
        LOOP_SHA256_PREPARE_WT64_PACK:
            for (short t = 16; t < 64; t += 4) {
#pragma HLS pipeline II = 1
#pragma HLS DEPENDENCE variable = W inter false
                uint32_t wt0 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                // shift and insert wt0
                for (unsigned char j = 0; j < 15; ++j) {
                    W[j] = W[j + 1];
                }
                W[15] = wt0;

                uint32_t wt1 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j1 = 0; j1 < 15; ++j1) {
                    W[j1] = W[j1 + 1];
                }
                W[15] = wt1;

                uint32_t wt2 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j2 = 0; j2 < 15; ++j2) {
                    W[j2] = W[j2 + 1];
                }
                W[15] = wt2;

                uint32_t wt3 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j3 = 0; j3 < 15; ++j3) {
                    W[j3] = W[j3 + 1];
                }
                W[15] = wt3;

                ap_uint<128> pack;
                pack.range(31, 0) = wt0;
                pack.range(63, 32) = wt1;
                pack.range(95, 64) = wt2;
                pack.range(127, 96) = wt3;
                w4_strm.write(pack);
            }
        }
        e = end_nblk_strm.read();
    }
}

inline void sha256_iter(uint32_t& a,
                        uint32_t& b,
                        uint32_t& c,
                        uint32_t& d,
                        uint32_t& e,
                        uint32_t& f,
                        uint32_t& g,
                        uint32_t& h,
                        hls::stream<uint32_t>& w_strm,
                        uint32_t& Kt,
                        const uint32_t K[],
                        short t) {
    uint32_t Wt = w_strm.read();
    /// temporal variables
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    // update working variables.
    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    _XF_SECURITY_PRINT(
        "DEBUG: Kt=%08x, Wt=%08x\n"
        "\ta=%08x, b=%08x, c=%08x, d=%08x\n"
        "\te=%08x, f=%08x, g=%08x, h=%08x\n",
        Kt, Wt, a, b, c, d, e, f, g, h);

    // for next cycle
    Kt = K[(t + 1) & 63];
}

// Value-driven variant for superscalar rounds
inline void sha256_iter_val(uint32_t& a,
                            uint32_t& b,
                            uint32_t& c,
                            uint32_t& d,
                            uint32_t& e,
                            uint32_t& f,
                            uint32_t& g,
                            uint32_t& h,
                            uint32_t Wt,
                            uint32_t& Kt,
                            const uint32_t K[],
                            short t) {
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    Kt = K[(t + 1) & 63];
}

/// @brief Digest message blocks and emit final hash.
/// @tparam h_width the hash width(type).
/// @param nblk_strm number of message block.
/// @param end_nblk_strm end flag for number of message block.
/// @param hash_strm the hash result stream.
/// @param end_hash_strm end flag for hash result.
template <int h_width>
void sha256Digest(hls::stream<uint64_t>& nblk_strm,
                  hls::stream<bool>& end_nblk_strm,
                  hls::stream<ap_uint<128> >& w4_strm,
                  hls::stream<ap_uint<h_width> >& hash_strm,
                  hls::stream<bool>& end_hash_strm) {
    // h_width determine the hash type.
    XF_SECURITY_STATIC_ASSERT((h_width == 256) || (h_width == 224),
                              "Unsupported hash stream width, must be 224 or 256");

    /// constant K
    static const uint32_t K[64] = {
        0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
        0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL, 0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
        0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
        0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
        0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL, 0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
        0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
        0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
        0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL, 0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};
#pragma HLS array_partition variable = K complete

LOOP_SHA256_DIGEST_MAIN:
    for (bool end_flag = end_nblk_strm.read(); !end_flag; end_flag = end_nblk_strm.read()) {
        /// total number blocks to digest.
        uint64_t blk_num = nblk_strm.read();
        // _XF_SECURITY_PRINT("expect %ld blocks.\n", blk_num);

        /// internal states
        uint32_t H[8];
#pragma HLS array_partition variable = H complete

        // initialize
        if (h_width == 224) {
            H[0] = 0xc1059ed8UL;
            H[1] = 0x367cd507UL;
            H[2] = 0x3070dd17UL;
            H[3] = 0xf70e5939UL;
            H[4] = 0xffc00b31UL;
            H[5] = 0x68581511UL;
            H[6] = 0x64f98fa7UL;
            H[7] = 0xbefa4fa4UL;
        } else {
            H[0] = 0x6a09e667UL;
            H[1] = 0xbb67ae85UL;
            H[2] = 0x3c6ef372UL;
            H[3] = 0xa54ff53aUL;
            H[4] = 0x510e527fUL;
            H[5] = 0x9b05688cUL;
            H[6] = 0x1f83d9abUL;
            H[7] = 0x5be0cd19UL;
        }

    LOOP_SHA256_DIGEST_NBLK:
        for (uint64_t n = 0; n < blk_num; ++n) {
#pragma HLS loop_tripcount min = 1 max = 1
#pragma HLS latency max = 65

            /// working variables.
            uint32_t a, b, c, d, e, f, g, h;

            // loading working variables.
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];
            e = H[4];
            f = H[5];
            g = H[6];
            h = H[7];

            uint32_t Kt = K[0];
        LOOP_SHA256_UPDATE_64_ROUNDS_PACK4:
            for (short t = 0; t < 64; t += 4) {
#pragma HLS pipeline II = 1
                ap_uint<128> pack = w4_strm.read();
                uint32_t wt0 = pack.range(31, 0);
                uint32_t wt1 = pack.range(63, 32);
                uint32_t wt2 = pack.range(95, 64);
                uint32_t wt3 = pack.range(127, 96);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt0, Kt, K, t + 0);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt1, Kt, K, t + 1);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt2, Kt, K, t + 2);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt3, Kt, K, t + 3);
            } // 64 round loop, 4 rounds per cycle

            // store working variables to internal states.
            H[0] = a + H[0];
            H[1] = b + H[1];
            H[2] = c + H[2];
            H[3] = d + H[3];
            H[4] = e + H[4];
            H[5] = f + H[5];
            H[6] = g + H[6];
            H[7] = h + H[7];
        } // block loop

        // Emit digest
        if (h_width == 224) {
            ap_uint<224> w224;
        LOOP_SHA256_EMIT_H224:
            for (short i = 0; i < sha256_digest_config<true>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w224.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w224);
        } else {
            ap_uint<256> w256;
        LOOP_SHA256_EMIT_H256:
            for (short i = 0; i < sha256_digest_config<false>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w256.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w256);
        }
        end_hash_strm.write(false);
    } // main loop
    end_hash_strm.write(true);

} // sha256Digest (pipelined override)

/// @brief SHA-256/224 implementation top overload for ap_uint input.
/// @tparam m_width the input message stream width.
/// @tparam h_width the output hash stream width.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed in byte.
/// @param end_len_strm end flag stream of input, one per message.
/// @param hash_strm the result.
/// @param end_hash_strm end falg stream of output, one per hash.
template <int m_width, int h_width>
inline void sha256_top(hls::stream<ap_uint<m_width> >& msg_strm,
                       hls::stream<ap_uint<64> >& len_strm,
                       hls::stream<bool>& end_len_strm,
                       hls::stream<ap_uint<h_width> >& hash_strm,
                       hls::stream<bool>& end_hash_strm) {
#pragma HLS DATAFLOW
    /// 512-bit Block stream
    hls::stream<SHA256Block> blk_strm("blk_strm");
#pragma HLS STREAM variable = blk_strm depth = 32
#pragma HLS RESOURCE variable = blk_strm core = FIFO_LUTRAM

    /// number of Blocks, send per msg
    hls::stream<uint64_t> nblk_strm("nblk_strm");
#pragma HLS STREAM variable = nblk_strm depth = 32
#pragma HLS RESOURCE variable = nblk_strm core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm1("nblk_strm1");
#pragma HLS STREAM variable = nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = nblk_strm1 core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm2("nblk_strm2");
#pragma HLS STREAM variable = nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = nblk_strm2 core = FIFO_LUTRAM

    /// end flag, send per msg.
    hls::stream<bool> end_nblk_strm("end_nblk_strm");
#pragma HLS STREAM variable = end_nblk_strm depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm1("end_nblk_strm1");
#pragma HLS STREAM variable = end_nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm1 core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm2("end_nblk_strm2");
#pragma HLS STREAM variable = end_nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm2 core = FIFO_LUTRAM

    /// W, 64 items per block, packed 4-per-cycle
    hls::stream<ap_uint<128> > w4_strm("w4_strm");
#pragma HLS STREAM variable = w4_strm depth = 32
#pragma HLS RESOURCE variable = w4_strm core = FIFO_LUTRAM

    // Generate block stream
    preProcessing(msg_strm, len_strm, end_len_strm, //
                  blk_strm, nblk_strm, end_nblk_strm);

    // Duplicate number of block stream and its end flag stream
    dup_strm(nblk_strm, end_nblk_strm, nblk_strm1, end_nblk_strm1, nblk_strm2, end_nblk_strm2);

    // Generate the message schedule in stream
    generateMsgSchedule(blk_strm, nblk_strm1, end_nblk_strm1, w4_strm);

    // Digest block stream, and write hash stream.
    // fully pipelined version will calculate SHA-224 if hash_strm width is 224.
    sha256Digest(nblk_strm2, end_nblk_strm2, w4_strm, //
                 hash_strm, end_hash_strm);
} // sha256_top
} // namespace internal

/// @brief SHA-224 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha224(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<224> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}

/// @brief SHA-256 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha256(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<256> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}
} // namespace security
} // namespace xf

// Clean up macros.
#undef ROTR
#undef ROTL
#undef SHR
#undef CH
#undef MAJ
#undef BSIG0
#undef BSIG1
#undef SSIG0
#undef SSIG1

#undef _XF_SECURITY_PRINT
#undef _XF_SECURITY_VOID_CAST

#endif // XF_SECURITY_SHA2_H
// -*- cpp -*-
// vim: ts=8:sw=2:sts=2:ft=cpp

```

进展：已完成四发射与按值迭代的集成，语法检查无误。接下来我会在 HLS 测试中按新规运行 csim/cosim，并根据执行时间指标评估时钟设定。由于你在 WSL 已有环境，我将直接运行。

我先提取本次综合和协同仿真的关键指标（Estimated Clock Period 与 Latency），以计算执行时间并据此决定是否需要改回“两发射”或加入 add 绑定与多周期约束来降低估计时钟。随后我会在同一轮继续应用必要的编辑。

我先运行综合以生成 csynth 报告，随后提取 Estimated Clock Period 并计算执行时间；若执行时间不理想，我会立即回退到“二发射/单发射”架构并重跑验证。

```cpp
/*
 * Copyright 2019 Xilinx, Inc.
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
 */

#ifndef _XF_SECURITY_SHA224_256_HPP_
#define _XF_SECURITY_SHA224_256_HPP_

#include <ap_int.h>
#include <hls_stream.h>

#include "xf_security/types.hpp"
#include "xf_security/utils.hpp"

// For debug
#ifndef __SYNTHESIS__
#include <cstdio>
#endif
#ifndef _DEBUG
#define _DEBUG (0)
#endif
#define _XF_SECURITY_VOID_CAST static_cast<void>
// XXX toggle here to debug this file
#define _XF_SECURITY_PRINT(msg...) \
    do {                           \
        if (_DEBUG) printf(msg);   \
    } while (0)

#define ROTR(n, x) ((x >> n) | (x << (32 - n)))
#define ROTL(n, x) ((x << n) | (x >> (32 - n)))
#define SHR(n, x) (x >> n)
#define CH(x, y, z) ((x & y) ^ ((~x) & z))
#define MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define BSIG0(x) (ROTR(2, x) ^ ROTR(13, x) ^ ROTR(22, x))
#define BSIG1(x) (ROTR(6, x) ^ ROTR(11, x) ^ ROTR(25, x))
#define SSIG0(x) (ROTR(7, x) ^ ROTR(18, x) ^ SHR(3, x))
#define SSIG1(x) (ROTR(17, x) ^ ROTR(19, x) ^ SHR(10, x))

namespace xf {
namespace security {
namespace internal {

/// Processing block
struct SHA256Block {
    uint32_t M[16];
};

/// @brief Static config for SHA224 and SHA256.
template <bool do_sha224>
struct sha256_digest_config;

template <>
struct sha256_digest_config<true> {
    static const short numH = 7;
};

template <>
struct sha256_digest_config<false> {
    static const short numH = 8;
};

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<32> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete
        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                uint32_t l = msg_strm.read();
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32bx16)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
        } else if (left < 56) {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_AND_ONE:
            for (int i = 0; i < 14; ++i) {
#pragma HLS pipeline
                if (i < (left >> 2)) {
                    uint32_t l = msg_strm.read();
                    // pad 1 byte not in this word
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 not in this word, and no word to read.
                    b.M[i] = 0UL;
                } else {
                    // pad 1 byte in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // cannot append L.

            /// last but 1 block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
        // copy and pad 1
        LOOP_SHA256_GEN_COPY_TAIL_ONLY:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                if (i < (left >> 2)) {
                    // pad 1 byte not in this word
                    uint32_t l = msg_strm.read();
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 byte not in this word, and no msg word to read
                    b.M[i] = 0UL;
                } else {
                    // last in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");

            /// last block.
            SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
        LOOP_SHA256_GEN_L_ONLY_BLK:
            for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                b1.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
            }
            // append L
            b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b1.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

            blk_strm.write(b1);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (32-bit ver)

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<64> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        _XF_SECURITY_PRINT("DEBUG: working on a new message of %ld bytes\n", len);
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete

        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; i += 2) {
#pragma HLS unroll
                uint64_t ll = msg_strm.read().to_uint64();
                // low
                uint32_t l = ll & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 low)\n", i, b0.M[i]);
                // high
                l = (ll >> 32) & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i + 1] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 high)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_PAD_ONE:
            for (int i = 0; i < ((left < 56) ? 7 : 8); ++i) {
#pragma HLS pipeline
                if (i < (left >> 3)) {
                    // pad 1 not in this 64b word, and need to copy
                    uint64_t ll = msg_strm.read().to_uint64();
                    // low
                    uint32_t l = ll & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i * 2, b.M[i * 2]);
                    // high
                    l = (ll >> 32) & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2 + 1] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b high)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else if (i > (left >> 3)) {
                    // pad 1 not in this 64b word, and no word to read.
                    b.M[i * 2] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2, b.M[i * 2]);
                    b.M[i * 2 + 1] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else {
                    // pad 1 byte in this 64b word
                    if ((left & 4) == 0) {
                        // left in low 32b
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2] = 0x80000000UL;
                        } else if (e == 1) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2] = l | 0x00800000UL;
                        } else if (e == 2) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2] = l | 0x00008000UL;
                        } else {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2, b.M[i * 2]);
                        // high
                        b.M[i * 2 + 1] = 0UL;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    } else {
                        // left in high 32b
                        uint64_t ll = msg_strm.read().to_uint64();
                        // low 32b
                        uint32_t l = ll & 0xffffffffUL;
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                            ((0xff000000UL & l) >> 24);
                        b.M[i * 2] = l;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i, b.M[i * 2]);
                        // high 32b
                        l = (ll >> 32) & 0xffffffffUL;
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2 + 1] = 0x80000000UL;
                        } else if (e == 1) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2 + 1] = l | 0x00800000UL;
                        } else if (e == 2) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2 + 1] = l | 0x00008000UL;
                        } else {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2 + 1] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    }
                }
            }

            if (left < 56) {
                // append L
                b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } else {
                // send block without L
                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");

                /// last block.
                SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
            LOOP_SHA256_GEN_L_ONLY_BLK:
                for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                    b1.M[i] = 0;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
                }
                // append L
                b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b1.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

                blk_strm.write(b1);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } // left < 56
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (64bit ver)

inline void dup_strm(hls::stream<uint64_t>& in_strm,
                     hls::stream<bool>& in_e_strm,
                     hls::stream<uint64_t>& out1_strm,
                     hls::stream<bool>& out1_e_strm,
                     hls::stream<uint64_t>& out2_strm,
                     hls::stream<bool>& out2_e_strm) {
    bool e = in_e_strm.read();

    while (!e) {
#pragma HLS loop_tripcount min = 1 max = 1 avg = 1
#pragma HLS pipeline II = 1
        uint64_t in_r = in_strm.read();

        out1_strm.write(in_r);
        out1_e_strm.write(false);
        out2_strm.write(in_r);
        out2_e_strm.write(false);

        e = in_e_strm.read();
    }

    out1_e_strm.write(true);
    out2_e_strm.write(true);
}

inline void generateMsgSchedule(hls::stream<SHA256Block>& blk_strm,
                                hls::stream<uint64_t>& nblk_strm,
                                hls::stream<bool>& end_nblk_strm,
                                hls::stream<ap_uint<64> >& w2_strm) {
    bool e = end_nblk_strm.read();
    while (!e) {
        uint64_t n = nblk_strm.read();
        for (uint64_t i = 0; i < n; ++i) {
#pragma HLS latency max = 65

            SHA256Block blk = blk_strm.read();
#pragma HLS array_partition variable = blk.M complete

            /// message schedule W, from message or
            uint32_t W[16];
#pragma HLS array_partition variable = W complete

        // Seed first 16 words and emit two at a time
        LOOP_SHA256_PREPARE_WT16_PACK2:
            for (short t = 0; t < 16; t += 2) {
#pragma HLS pipeline II = 1
                uint32_t w0 = blk.M[t + 0];
                uint32_t w1 = blk.M[t + 1];
                W[t + 0] = w0;
                W[t + 1] = w1;
                ap_uint<64> pack;
                pack.range(31, 0) = w0;
                pack.range(63, 32) = w1;
                w2_strm.write(pack);
            }

        // Extend words and emit in groups of two using a 16-word sliding window
        LOOP_SHA256_PREPARE_WT64_PACK2:
            for (short t = 16; t < 64; t += 2) {
#pragma HLS pipeline II = 1
#pragma HLS DEPENDENCE variable = W inter false
                uint32_t wt0 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                // shift and insert wt0
                for (unsigned char j = 0; j < 15; ++j) {
                    W[j] = W[j + 1];
                }
                W[15] = wt0;

                uint32_t wt1 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j1 = 0; j1 < 15; ++j1) {
                    W[j1] = W[j1 + 1];
                }
                W[15] = wt1;

                ap_uint<64> pack;
                pack.range(31, 0) = wt0;
                pack.range(63, 32) = wt1;
                w2_strm.write(pack);
            }
        }
        e = end_nblk_strm.read();
    }
}

inline void sha256_iter(uint32_t& a,
                        uint32_t& b,
                        uint32_t& c,
                        uint32_t& d,
                        uint32_t& e,
                        uint32_t& f,
                        uint32_t& g,
                        uint32_t& h,
                        hls::stream<uint32_t>& w_strm,
                        uint32_t& Kt,
                        const uint32_t K[],
                        short t) {
    uint32_t Wt = w_strm.read();
    /// temporal variables
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    // update working variables.
    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    _XF_SECURITY_PRINT(
        "DEBUG: Kt=%08x, Wt=%08x\n"
        "\ta=%08x, b=%08x, c=%08x, d=%08x\n"
        "\te=%08x, f=%08x, g=%08x, h=%08x\n",
        Kt, Wt, a, b, c, d, e, f, g, h);

    // for next cycle
    Kt = K[(t + 1) & 63];
}

// Value-driven variant for superscalar rounds
inline void sha256_iter_val(uint32_t& a,
                            uint32_t& b,
                            uint32_t& c,
                            uint32_t& d,
                            uint32_t& e,
                            uint32_t& f,
                            uint32_t& g,
                            uint32_t& h,
                            uint32_t Wt,
                            uint32_t& Kt,
                            const uint32_t K[],
                            short t) {
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    Kt = K[(t + 1) & 63];
}

/// @brief Digest message blocks and emit final hash.
/// @tparam h_width the hash width(type).
/// @param nblk_strm number of message block.
/// @param end_nblk_strm end flag for number of message block.
/// @param hash_strm the hash result stream.
/// @param end_hash_strm end flag for hash result.
template <int h_width>
void sha256Digest(hls::stream<uint64_t>& nblk_strm,
                  hls::stream<bool>& end_nblk_strm,
                  hls::stream<ap_uint<128> >& w4_strm,
                  hls::stream<ap_uint<h_width> >& hash_strm,
                  hls::stream<bool>& end_hash_strm) {
    // h_width determine the hash type.
    XF_SECURITY_STATIC_ASSERT((h_width == 256) || (h_width == 224),
                              "Unsupported hash stream width, must be 224 or 256");

    /// constant K
    static const uint32_t K[64] = {
        0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
        0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL, 0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
        0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
        0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
        0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL, 0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
        0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
        0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
        0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL, 0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};
#pragma HLS array_partition variable = K complete

LOOP_SHA256_DIGEST_MAIN:
    for (bool end_flag = end_nblk_strm.read(); !end_flag; end_flag = end_nblk_strm.read()) {
        /// total number blocks to digest.
        uint64_t blk_num = nblk_strm.read();
        // _XF_SECURITY_PRINT("expect %ld blocks.\n", blk_num);

        /// internal states
        uint32_t H[8];
#pragma HLS array_partition variable = H complete

        // initialize
        if (h_width == 224) {
            H[0] = 0xc1059ed8UL;
            H[1] = 0x367cd507UL;
            H[2] = 0x3070dd17UL;
            H[3] = 0xf70e5939UL;
            H[4] = 0xffc00b31UL;
            H[5] = 0x68581511UL;
            H[6] = 0x64f98fa7UL;
            H[7] = 0xbefa4fa4UL;
        } else {
            H[0] = 0x6a09e667UL;
            H[1] = 0xbb67ae85UL;
            H[2] = 0x3c6ef372UL;
            H[3] = 0xa54ff53aUL;
            H[4] = 0x510e527fUL;
            H[5] = 0x9b05688cUL;
            H[6] = 0x1f83d9abUL;
            H[7] = 0x5be0cd19UL;
        }

    LOOP_SHA256_DIGEST_NBLK:
        for (uint64_t n = 0; n < blk_num; ++n) {
#pragma HLS loop_tripcount min = 1 max = 1
#pragma HLS latency max = 65

            /// working variables.
            uint32_t a, b, c, d, e, f, g, h;

            // loading working variables.
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];
            e = H[4];
            f = H[5];
            g = H[6];
            h = H[7];

            uint32_t Kt = K[0];
        LOOP_SHA256_UPDATE_64_ROUNDS_PACK4:
            for (short t = 0; t < 64; t += 4) {
#pragma HLS pipeline II = 1
                ap_uint<128> pack = w4_strm.read();
                uint32_t wt0 = pack.range(31, 0);
                uint32_t wt1 = pack.range(63, 32);
                uint32_t wt2 = pack.range(95, 64);
                uint32_t wt3 = pack.range(127, 96);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt0, Kt, K, t + 0);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt1, Kt, K, t + 1);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt2, Kt, K, t + 2);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt3, Kt, K, t + 3);
            } // 64 round loop, 4 rounds per cycle

            // store working variables to internal states.
            H[0] = a + H[0];
            H[1] = b + H[1];
            H[2] = c + H[2];
            H[3] = d + H[3];
            H[4] = e + H[4];
            H[5] = f + H[5];
            H[6] = g + H[6];
            H[7] = h + H[7];
        } // block loop

        // Emit digest
        if (h_width == 224) {
            ap_uint<224> w224;
        LOOP_SHA256_EMIT_H224:
            for (short i = 0; i < sha256_digest_config<true>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w224.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w224);
        } else {
            ap_uint<256> w256;
        LOOP_SHA256_EMIT_H256:
            for (short i = 0; i < sha256_digest_config<false>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w256.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w256);
        }
        end_hash_strm.write(false);
    } // main loop
    end_hash_strm.write(true);

} // sha256Digest (pipelined override)

/// @brief SHA-256/224 implementation top overload for ap_uint input.
/// @tparam m_width the input message stream width.
/// @tparam h_width the output hash stream width.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed in byte.
/// @param end_len_strm end flag stream of input, one per message.
/// @param hash_strm the result.
/// @param end_hash_strm end falg stream of output, one per hash.
template <int m_width, int h_width>
inline void sha256_top(hls::stream<ap_uint<m_width> >& msg_strm,
                       hls::stream<ap_uint<64> >& len_strm,
                       hls::stream<bool>& end_len_strm,
                       hls::stream<ap_uint<h_width> >& hash_strm,
                       hls::stream<bool>& end_hash_strm) {
#pragma HLS DATAFLOW
    /// 512-bit Block stream
    hls::stream<SHA256Block> blk_strm("blk_strm");
#pragma HLS STREAM variable = blk_strm depth = 32
#pragma HLS RESOURCE variable = blk_strm core = FIFO_LUTRAM

    /// number of Blocks, send per msg
    hls::stream<uint64_t> nblk_strm("nblk_strm");
#pragma HLS STREAM variable = nblk_strm depth = 32
#pragma HLS RESOURCE variable = nblk_strm core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm1("nblk_strm1");
#pragma HLS STREAM variable = nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = nblk_strm1 core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm2("nblk_strm2");
#pragma HLS STREAM variable = nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = nblk_strm2 core = FIFO_LUTRAM

    /// end flag, send per msg.
    hls::stream<bool> end_nblk_strm("end_nblk_strm");
#pragma HLS STREAM variable = end_nblk_strm depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm1("end_nblk_strm1");
#pragma HLS STREAM variable = end_nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm1 core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm2("end_nblk_strm2");
#pragma HLS STREAM variable = end_nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm2 core = FIFO_LUTRAM

    /// W, 64 items per block, packed 4-per-cycle
    hls::stream<ap_uint<128> > w4_strm("w4_strm");
#pragma HLS STREAM variable = w4_strm depth = 32
#pragma HLS RESOURCE variable = w4_strm core = FIFO_LUTRAM

    // Generate block stream
    preProcessing(msg_strm, len_strm, end_len_strm, //
                  blk_strm, nblk_strm, end_nblk_strm);

    // Duplicate number of block stream and its end flag stream
    dup_strm(nblk_strm, end_nblk_strm, nblk_strm1, end_nblk_strm1, nblk_strm2, end_nblk_strm2);

    // Generate the message schedule in stream
    generateMsgSchedule(blk_strm, nblk_strm1, end_nblk_strm1, w4_strm);

    // Digest block stream, and write hash stream.
    // fully pipelined version will calculate SHA-224 if hash_strm width is 224.
    sha256Digest(nblk_strm2, end_nblk_strm2, w4_strm, //
                 hash_strm, end_hash_strm);
} // sha256_top
} // namespace internal

/// @brief SHA-224 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha224(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<224> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}

/// @brief SHA-256 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha256(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<256> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}
} // namespace security
} // namespace xf

// Clean up macros.
#undef ROTR
#undef ROTL
#undef SHR
#undef CH
#undef MAJ
#undef BSIG0
#undef BSIG1
#undef SSIG0
#undef SSIG1

#undef _XF_SECURITY_PRINT
#undef _XF_SECURITY_VOID_CAST

#endif // XF_SECURITY_SHA2_H
// -*- cpp -*-
// vim: ts=8:sw=2:sts=2:ft=cpp

```

```cpp
/*
 * Copyright 2019 Xilinx, Inc.
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
 */

#ifndef _XF_SECURITY_SHA224_256_HPP_
#define _XF_SECURITY_SHA224_256_HPP_

#include <ap_int.h>
#include <hls_stream.h>

#include "xf_security/types.hpp"
#include "xf_security/utils.hpp"

// For debug
#ifndef __SYNTHESIS__
#include <cstdio>
#endif
#ifndef _DEBUG
#define _DEBUG (0)
#endif
#define _XF_SECURITY_VOID_CAST static_cast<void>
// XXX toggle here to debug this file
#define _XF_SECURITY_PRINT(msg...) \
    do {                           \
        if (_DEBUG) printf(msg);   \
    } while (0)

#define ROTR(n, x) ((x >> n) | (x << (32 - n)))
#define ROTL(n, x) ((x << n) | (x >> (32 - n)))
#define SHR(n, x) (x >> n)
#define CH(x, y, z) ((x & y) ^ ((~x) & z))
#define MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define BSIG0(x) (ROTR(2, x) ^ ROTR(13, x) ^ ROTR(22, x))
#define BSIG1(x) (ROTR(6, x) ^ ROTR(11, x) ^ ROTR(25, x))
#define SSIG0(x) (ROTR(7, x) ^ ROTR(18, x) ^ SHR(3, x))
#define SSIG1(x) (ROTR(17, x) ^ ROTR(19, x) ^ SHR(10, x))

namespace xf {
namespace security {
namespace internal {

/// Processing block
struct SHA256Block {
    uint32_t M[16];
};

/// @brief Static config for SHA224 and SHA256.
template <bool do_sha224>
struct sha256_digest_config;

template <>
struct sha256_digest_config<true> {
    static const short numH = 7;
};

template <>
struct sha256_digest_config<false> {
    static const short numH = 8;
};

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<32> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete
        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                uint32_t l = msg_strm.read();
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32bx16)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
        } else if (left < 56) {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_AND_ONE:
            for (int i = 0; i < 14; ++i) {
#pragma HLS pipeline
                if (i < (left >> 2)) {
                    uint32_t l = msg_strm.read();
                    // pad 1 byte not in this word
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 not in this word, and no word to read.
                    b.M[i] = 0UL;
                } else {
                    // pad 1 byte in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // cannot append L.

            /// last but 1 block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
        // copy and pad 1
        LOOP_SHA256_GEN_COPY_TAIL_ONLY:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                if (i < (left >> 2)) {
                    // pad 1 byte not in this word
                    uint32_t l = msg_strm.read();
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 byte not in this word, and no msg word to read
                    b.M[i] = 0UL;
                } else {
                    // last in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");

            /// last block.
            SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
        LOOP_SHA256_GEN_L_ONLY_BLK:
            for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                b1.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
            }
            // append L
            b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b1.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

            blk_strm.write(b1);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (32-bit ver)

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<64> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        _XF_SECURITY_PRINT("DEBUG: working on a new message of %ld bytes\n", len);
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete

        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; i += 2) {
#pragma HLS unroll
                uint64_t ll = msg_strm.read().to_uint64();
                // low
                uint32_t l = ll & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 low)\n", i, b0.M[i]);
                // high
                l = (ll >> 32) & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i + 1] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 high)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_PAD_ONE:
            for (int i = 0; i < ((left < 56) ? 7 : 8); ++i) {
#pragma HLS pipeline
                if (i < (left >> 3)) {
                    // pad 1 not in this 64b word, and need to copy
                    uint64_t ll = msg_strm.read().to_uint64();
                    // low
                    uint32_t l = ll & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i * 2, b.M[i * 2]);
                    // high
                    l = (ll >> 32) & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2 + 1] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b high)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else if (i > (left >> 3)) {
                    // pad 1 not in this 64b word, and no word to read.
                    b.M[i * 2] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2, b.M[i * 2]);
                    b.M[i * 2 + 1] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else {
                    // pad 1 byte in this 64b word
                    if ((left & 4) == 0) {
                        // left in low 32b
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2] = 0x80000000UL;
                        } else if (e == 1) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2] = l | 0x00800000UL;
                        } else if (e == 2) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2] = l | 0x00008000UL;
                        } else {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2, b.M[i * 2]);
                        // high
                        b.M[i * 2 + 1] = 0UL;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    } else {
                        // left in high 32b
                        uint64_t ll = msg_strm.read().to_uint64();
                        // low 32b
                        uint32_t l = ll & 0xffffffffUL;
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                            ((0xff000000UL & l) >> 24);
                        b.M[i * 2] = l;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i, b.M[i * 2]);
                        // high 32b
                        l = (ll >> 32) & 0xffffffffUL;
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2 + 1] = 0x80000000UL;
                        } else if (e == 1) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2 + 1] = l | 0x00800000UL;
                        } else if (e == 2) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2 + 1] = l | 0x00008000UL;
                        } else {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2 + 1] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    }
                }
            }

            if (left < 56) {
                // append L
                b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } else {
                // send block without L
                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");

                /// last block.
                SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
            LOOP_SHA256_GEN_L_ONLY_BLK:
                for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                    b1.M[i] = 0;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
                }
                // append L
                b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b1.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

                blk_strm.write(b1);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } // left < 56
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (64bit ver)

inline void dup_strm(hls::stream<uint64_t>& in_strm,
                     hls::stream<bool>& in_e_strm,
                     hls::stream<uint64_t>& out1_strm,
                     hls::stream<bool>& out1_e_strm,
                     hls::stream<uint64_t>& out2_strm,
                     hls::stream<bool>& out2_e_strm) {
    bool e = in_e_strm.read();

    while (!e) {
#pragma HLS loop_tripcount min = 1 max = 1 avg = 1
#pragma HLS pipeline II = 1
        uint64_t in_r = in_strm.read();

        out1_strm.write(in_r);
        out1_e_strm.write(false);
        out2_strm.write(in_r);
        out2_e_strm.write(false);

        e = in_e_strm.read();
    }

    out1_e_strm.write(true);
    out2_e_strm.write(true);
}

inline void generateMsgSchedule(hls::stream<SHA256Block>& blk_strm,
                                hls::stream<uint64_t>& nblk_strm,
                                hls::stream<bool>& end_nblk_strm,
                                hls::stream<ap_uint<64> >& w2_strm) {
    bool e = end_nblk_strm.read();
    while (!e) {
        uint64_t n = nblk_strm.read();
        for (uint64_t i = 0; i < n; ++i) {
#pragma HLS latency max = 65

            SHA256Block blk = blk_strm.read();
#pragma HLS array_partition variable = blk.M complete

            /// message schedule W, from message or
            uint32_t W[16];
#pragma HLS array_partition variable = W complete

        // Seed first 16 words and emit two at a time
        LOOP_SHA256_PREPARE_WT16_PACK2:
            for (short t = 0; t < 16; t += 2) {
#pragma HLS pipeline II = 1
                uint32_t w0 = blk.M[t + 0];
                uint32_t w1 = blk.M[t + 1];
                W[t + 0] = w0;
                W[t + 1] = w1;
                ap_uint<64> pack;
                pack.range(31, 0) = w0;
                pack.range(63, 32) = w1;
                w2_strm.write(pack);
            }

        // Extend words and emit in groups of two using a 16-word sliding window
        LOOP_SHA256_PREPARE_WT64_PACK2:
            for (short t = 16; t < 64; t += 2) {
#pragma HLS pipeline II = 1
#pragma HLS DEPENDENCE variable = W inter false
                uint32_t wt0 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                // shift and insert wt0
                for (unsigned char j = 0; j < 15; ++j) {
                    W[j] = W[j + 1];
                }
                W[15] = wt0;

                uint32_t wt1 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j1 = 0; j1 < 15; ++j1) {
                    W[j1] = W[j1 + 1];
                }
                W[15] = wt1;

                ap_uint<64> pack;
                pack.range(31, 0) = wt0;
                pack.range(63, 32) = wt1;
                w2_strm.write(pack);
            }
        }
        e = end_nblk_strm.read();
    }
}

inline void sha256_iter(uint32_t& a,
                        uint32_t& b,
                        uint32_t& c,
                        uint32_t& d,
                        uint32_t& e,
                        uint32_t& f,
                        uint32_t& g,
                        uint32_t& h,
                        hls::stream<uint32_t>& w_strm,
                        uint32_t& Kt,
                        const uint32_t K[],
                        short t) {
    uint32_t Wt = w_strm.read();
    /// temporal variables
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    // update working variables.
    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    _XF_SECURITY_PRINT(
        "DEBUG: Kt=%08x, Wt=%08x\n"
        "\ta=%08x, b=%08x, c=%08x, d=%08x\n"
        "\te=%08x, f=%08x, g=%08x, h=%08x\n",
        Kt, Wt, a, b, c, d, e, f, g, h);

    // for next cycle
    Kt = K[(t + 1) & 63];
}

// Value-driven variant for superscalar rounds
inline void sha256_iter_val(uint32_t& a,
                            uint32_t& b,
                            uint32_t& c,
                            uint32_t& d,
                            uint32_t& e,
                            uint32_t& f,
                            uint32_t& g,
                            uint32_t& h,
                            uint32_t Wt,
                            uint32_t& Kt,
                            const uint32_t K[],
                            short t) {
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    Kt = K[(t + 1) & 63];
}

/// @brief Digest message blocks and emit final hash.
/// @tparam h_width the hash width(type).
/// @param nblk_strm number of message block.
/// @param end_nblk_strm end flag for number of message block.
/// @param hash_strm the hash result stream.
/// @param end_hash_strm end flag for hash result.
template <int h_width>
void sha256Digest(hls::stream<uint64_t>& nblk_strm,
                  hls::stream<bool>& end_nblk_strm,
                  hls::stream<ap_uint<64> >& w2_strm,
                  hls::stream<ap_uint<h_width> >& hash_strm,
                  hls::stream<bool>& end_hash_strm) {
    // h_width determine the hash type.
    XF_SECURITY_STATIC_ASSERT((h_width == 256) || (h_width == 224),
                              "Unsupported hash stream width, must be 224 or 256");

    /// constant K
    static const uint32_t K[64] = {
        0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
        0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL, 0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
        0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
        0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
        0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL, 0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
        0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
        0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
        0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL, 0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};
#pragma HLS array_partition variable = K complete

LOOP_SHA256_DIGEST_MAIN:
    for (bool end_flag = end_nblk_strm.read(); !end_flag; end_flag = end_nblk_strm.read()) {
        /// total number blocks to digest.
        uint64_t blk_num = nblk_strm.read();
        // _XF_SECURITY_PRINT("expect %ld blocks.\n", blk_num);

        /// internal states
        uint32_t H[8];
#pragma HLS array_partition variable = H complete

        // initialize
        if (h_width == 224) {
            H[0] = 0xc1059ed8UL;
            H[1] = 0x367cd507UL;
            H[2] = 0x3070dd17UL;
            H[3] = 0xf70e5939UL;
            H[4] = 0xffc00b31UL;
            H[5] = 0x68581511UL;
            H[6] = 0x64f98fa7UL;
            H[7] = 0xbefa4fa4UL;
        } else {
            H[0] = 0x6a09e667UL;
            H[1] = 0xbb67ae85UL;
            H[2] = 0x3c6ef372UL;
            H[3] = 0xa54ff53aUL;
            H[4] = 0x510e527fUL;
            H[5] = 0x9b05688cUL;
            H[6] = 0x1f83d9abUL;
            H[7] = 0x5be0cd19UL;
        }

    LOOP_SHA256_DIGEST_NBLK:
        for (uint64_t n = 0; n < blk_num; ++n) {
#pragma HLS loop_tripcount min = 1 max = 1
#pragma HLS latency max = 65

            /// working variables.
            uint32_t a, b, c, d, e, f, g, h;

            // loading working variables.
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];
            e = H[4];
            f = H[5];
            g = H[6];
            h = H[7];

            uint32_t Kt = K[0];
        LOOP_SHA256_UPDATE_64_ROUNDS_PACK2:
            for (short t = 0; t < 64; t += 2) {
#pragma HLS pipeline II = 1
                ap_uint<64> pack = w2_strm.read();
                uint32_t wt0 = pack.range(31, 0);
                uint32_t wt1 = pack.range(63, 32);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt0, Kt, K, t + 0);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt1, Kt, K, t + 1);
            } // 64 round loop, 2 rounds per cycle

            // store working variables to internal states.
            H[0] = a + H[0];
            H[1] = b + H[1];
            H[2] = c + H[2];
            H[3] = d + H[3];
            H[4] = e + H[4];
            H[5] = f + H[5];
            H[6] = g + H[6];
            H[7] = h + H[7];
        } // block loop

        // Emit digest
        if (h_width == 224) {
            ap_uint<224> w224;
        LOOP_SHA256_EMIT_H224:
            for (short i = 0; i < sha256_digest_config<true>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w224.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w224);
        } else {
            ap_uint<256> w256;
        LOOP_SHA256_EMIT_H256:
            for (short i = 0; i < sha256_digest_config<false>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w256.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w256);
        }
        end_hash_strm.write(false);
    } // main loop
    end_hash_strm.write(true);

} // sha256Digest (pipelined override)

/// @brief SHA-256/224 implementation top overload for ap_uint input.
/// @tparam m_width the input message stream width.
/// @tparam h_width the output hash stream width.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed in byte.
/// @param end_len_strm end flag stream of input, one per message.
/// @param hash_strm the result.
/// @param end_hash_strm end falg stream of output, one per hash.
template <int m_width, int h_width>
inline void sha256_top(hls::stream<ap_uint<m_width> >& msg_strm,
                       hls::stream<ap_uint<64> >& len_strm,
                       hls::stream<bool>& end_len_strm,
                       hls::stream<ap_uint<h_width> >& hash_strm,
                       hls::stream<bool>& end_hash_strm) {
#pragma HLS DATAFLOW
    /// 512-bit Block stream
    hls::stream<SHA256Block> blk_strm("blk_strm");
#pragma HLS STREAM variable = blk_strm depth = 32
#pragma HLS RESOURCE variable = blk_strm core = FIFO_LUTRAM

    /// number of Blocks, send per msg
    hls::stream<uint64_t> nblk_strm("nblk_strm");
#pragma HLS STREAM variable = nblk_strm depth = 32
#pragma HLS RESOURCE variable = nblk_strm core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm1("nblk_strm1");
#pragma HLS STREAM variable = nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = nblk_strm1 core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm2("nblk_strm2");
#pragma HLS STREAM variable = nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = nblk_strm2 core = FIFO_LUTRAM

    /// end flag, send per msg.
    hls::stream<bool> end_nblk_strm("end_nblk_strm");
#pragma HLS STREAM variable = end_nblk_strm depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm1("end_nblk_strm1");
#pragma HLS STREAM variable = end_nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm1 core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm2("end_nblk_strm2");
#pragma HLS STREAM variable = end_nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm2 core = FIFO_LUTRAM

    /// W, 64 items per block, packed 4-per-cycle
    hls::stream<ap_uint<128> > w4_strm("w4_strm");
#pragma HLS STREAM variable = w4_strm depth = 32
#pragma HLS RESOURCE variable = w4_strm core = FIFO_LUTRAM

    // Generate block stream
    preProcessing(msg_strm, len_strm, end_len_strm, //
                  blk_strm, nblk_strm, end_nblk_strm);

    // Duplicate number of block stream and its end flag stream
    dup_strm(nblk_strm, end_nblk_strm, nblk_strm1, end_nblk_strm1, nblk_strm2, end_nblk_strm2);

    // Generate the message schedule in stream
    generateMsgSchedule(blk_strm, nblk_strm1, end_nblk_strm1, w4_strm);

    // Digest block stream, and write hash stream.
    // fully pipelined version will calculate SHA-224 if hash_strm width is 224.
    sha256Digest(nblk_strm2, end_nblk_strm2, w4_strm, //
                 hash_strm, end_hash_strm);
} // sha256_top
} // namespace internal

/// @brief SHA-224 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha224(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<224> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}

/// @brief SHA-256 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha256(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<256> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}
} // namespace security
} // namespace xf

// Clean up macros.
#undef ROTR
#undef ROTL
#undef SHR
#undef CH
#undef MAJ
#undef BSIG0
#undef BSIG1
#undef SSIG0
#undef SSIG1

#undef _XF_SECURITY_PRINT
#undef _XF_SECURITY_VOID_CAST

#endif // XF_SECURITY_SHA2_H
// -*- cpp -*-
// vim: ts=8:sw=2:sts=2:ft=cpp

```

```cpp
/*
 * Copyright 2019 Xilinx, Inc.
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
 */

#ifndef _XF_SECURITY_SHA224_256_HPP_
#define _XF_SECURITY_SHA224_256_HPP_

#include <ap_int.h>
#include <hls_stream.h>

#include "xf_security/types.hpp"
#include "xf_security/utils.hpp"

// For debug
#ifndef __SYNTHESIS__
#include <cstdio>
#endif
#ifndef _DEBUG
#define _DEBUG (0)
#endif
#define _XF_SECURITY_VOID_CAST static_cast<void>
// XXX toggle here to debug this file
#define _XF_SECURITY_PRINT(msg...) \
    do {                           \
        if (_DEBUG) printf(msg);   \
    } while (0)

#define ROTR(n, x) ((x >> n) | (x << (32 - n)))
#define ROTL(n, x) ((x << n) | (x >> (32 - n)))
#define SHR(n, x) (x >> n)
#define CH(x, y, z) ((x & y) ^ ((~x) & z))
#define MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define BSIG0(x) (ROTR(2, x) ^ ROTR(13, x) ^ ROTR(22, x))
#define BSIG1(x) (ROTR(6, x) ^ ROTR(11, x) ^ ROTR(25, x))
#define SSIG0(x) (ROTR(7, x) ^ ROTR(18, x) ^ SHR(3, x))
#define SSIG1(x) (ROTR(17, x) ^ ROTR(19, x) ^ SHR(10, x))

namespace xf {
namespace security {
namespace internal {

/// Processing block
struct SHA256Block {
    uint32_t M[16];
};

/// @brief Static config for SHA224 and SHA256.
template <bool do_sha224>
struct sha256_digest_config;

template <>
struct sha256_digest_config<true> {
    static const short numH = 7;
};

template <>
struct sha256_digest_config<false> {
    static const short numH = 8;
};

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<32> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete
        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                uint32_t l = msg_strm.read();
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32bx16)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
        } else if (left < 56) {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_AND_ONE:
            for (int i = 0; i < 14; ++i) {
#pragma HLS pipeline
                if (i < (left >> 2)) {
                    uint32_t l = msg_strm.read();
                    // pad 1 byte not in this word
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 not in this word, and no word to read.
                    b.M[i] = 0UL;
                } else {
                    // pad 1 byte in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // cannot append L.

            /// last but 1 block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
        // copy and pad 1
        LOOP_SHA256_GEN_COPY_TAIL_ONLY:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                if (i < (left >> 2)) {
                    // pad 1 byte not in this word
                    uint32_t l = msg_strm.read();
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 byte not in this word, and no msg word to read
                    b.M[i] = 0UL;
                } else {
                    // last in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");

            /// last block.
            SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
        LOOP_SHA256_GEN_L_ONLY_BLK:
            for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                b1.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
            }
            // append L
            b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b1.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

            blk_strm.write(b1);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (32-bit ver)

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<64> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        _XF_SECURITY_PRINT("DEBUG: working on a new message of %ld bytes\n", len);
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete

        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; i += 2) {
#pragma HLS unroll
                uint64_t ll = msg_strm.read().to_uint64();
                // low
                uint32_t l = ll & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 low)\n", i, b0.M[i]);
                // high
                l = (ll >> 32) & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i + 1] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 high)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_PAD_ONE:
            for (int i = 0; i < ((left < 56) ? 7 : 8); ++i) {
#pragma HLS pipeline
                if (i < (left >> 3)) {
                    // pad 1 not in this 64b word, and need to copy
                    uint64_t ll = msg_strm.read().to_uint64();
                    // low
                    uint32_t l = ll & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i * 2, b.M[i * 2]);
                    // high
                    l = (ll >> 32) & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2 + 1] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b high)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else if (i > (left >> 3)) {
                    // pad 1 not in this 64b word, and no word to read.
                    b.M[i * 2] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2, b.M[i * 2]);
                    b.M[i * 2 + 1] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else {
                    // pad 1 byte in this 64b word
                    if ((left & 4) == 0) {
                        // left in low 32b
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2] = 0x80000000UL;
                        } else if (e == 1) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2] = l | 0x00800000UL;
                        } else if (e == 2) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2] = l | 0x00008000UL;
                        } else {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2, b.M[i * 2]);
                        // high
                        b.M[i * 2 + 1] = 0UL;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    } else {
                        // left in high 32b
                        uint64_t ll = msg_strm.read().to_uint64();
                        // low 32b
                        uint32_t l = ll & 0xffffffffUL;
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                            ((0xff000000UL & l) >> 24);
                        b.M[i * 2] = l;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i, b.M[i * 2]);
                        // high 32b
                        l = (ll >> 32) & 0xffffffffUL;
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2 + 1] = 0x80000000UL;
                        } else if (e == 1) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2 + 1] = l | 0x00800000UL;
                        } else if (e == 2) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2 + 1] = l | 0x00008000UL;
                        } else {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2 + 1] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    }
                }
            }

            if (left < 56) {
                // append L
                b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } else {
                // send block without L
                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");

                /// last block.
                SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
            LOOP_SHA256_GEN_L_ONLY_BLK:
                for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                    b1.M[i] = 0;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
                }
                // append L
                b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b1.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

                blk_strm.write(b1);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } // left < 56
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (64bit ver)

inline void dup_strm(hls::stream<uint64_t>& in_strm,
                     hls::stream<bool>& in_e_strm,
                     hls::stream<uint64_t>& out1_strm,
                     hls::stream<bool>& out1_e_strm,
                     hls::stream<uint64_t>& out2_strm,
                     hls::stream<bool>& out2_e_strm) {
    bool e = in_e_strm.read();

    while (!e) {
#pragma HLS loop_tripcount min = 1 max = 1 avg = 1
#pragma HLS pipeline II = 1
        uint64_t in_r = in_strm.read();

        out1_strm.write(in_r);
        out1_e_strm.write(false);
        out2_strm.write(in_r);
        out2_e_strm.write(false);

        e = in_e_strm.read();
    }

    out1_e_strm.write(true);
    out2_e_strm.write(true);
}

inline void generateMsgSchedule(hls::stream<SHA256Block>& blk_strm,
                                hls::stream<uint64_t>& nblk_strm,
                                hls::stream<bool>& end_nblk_strm,
                                hls::stream<ap_uint<64> >& w2_strm) {
    bool e = end_nblk_strm.read();
    while (!e) {
        uint64_t n = nblk_strm.read();
        for (uint64_t i = 0; i < n; ++i) {
#pragma HLS latency max = 65

            SHA256Block blk = blk_strm.read();
#pragma HLS array_partition variable = blk.M complete

            /// message schedule W, from message or
            uint32_t W[16];
#pragma HLS array_partition variable = W complete

        // Seed first 16 words and emit two at a time
        LOOP_SHA256_PREPARE_WT16_PACK2:
            for (short t = 0; t < 16; t += 2) {
#pragma HLS pipeline II = 1
                uint32_t w0 = blk.M[t + 0];
                uint32_t w1 = blk.M[t + 1];
                W[t + 0] = w0;
                W[t + 1] = w1;
                ap_uint<64> pack;
                pack.range(31, 0) = w0;
                pack.range(63, 32) = w1;
                w2_strm.write(pack);
            }

        // Extend words and emit in groups of two using a 16-word sliding window
        LOOP_SHA256_PREPARE_WT64_PACK2:
            for (short t = 16; t < 64; t += 2) {
#pragma HLS pipeline II = 1
#pragma HLS DEPENDENCE variable = W inter false
                uint32_t wt0 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                // shift and insert wt0
                for (unsigned char j = 0; j < 15; ++j) {
                    W[j] = W[j + 1];
                }
                W[15] = wt0;

                uint32_t wt1 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j1 = 0; j1 < 15; ++j1) {
                    W[j1] = W[j1 + 1];
                }
                W[15] = wt1;

                ap_uint<64> pack;
                pack.range(31, 0) = wt0;
                pack.range(63, 32) = wt1;
                w2_strm.write(pack);
            }
        }
        e = end_nblk_strm.read();
    }
}

inline void sha256_iter(uint32_t& a,
                        uint32_t& b,
                        uint32_t& c,
                        uint32_t& d,
                        uint32_t& e,
                        uint32_t& f,
                        uint32_t& g,
                        uint32_t& h,
                        hls::stream<uint32_t>& w_strm,
                        uint32_t& Kt,
                        const uint32_t K[],
                        short t) {
    uint32_t Wt = w_strm.read();
    /// temporal variables
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    // update working variables.
    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    _XF_SECURITY_PRINT(
        "DEBUG: Kt=%08x, Wt=%08x\n"
        "\ta=%08x, b=%08x, c=%08x, d=%08x\n"
        "\te=%08x, f=%08x, g=%08x, h=%08x\n",
        Kt, Wt, a, b, c, d, e, f, g, h);

    // for next cycle
    Kt = K[(t + 1) & 63];
}

// Value-driven variant for superscalar rounds
inline void sha256_iter_val(uint32_t& a,
                            uint32_t& b,
                            uint32_t& c,
                            uint32_t& d,
                            uint32_t& e,
                            uint32_t& f,
                            uint32_t& g,
                            uint32_t& h,
                            uint32_t Wt,
                            uint32_t& Kt,
                            const uint32_t K[],
                            short t) {
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    Kt = K[(t + 1) & 63];
}

/// @brief Digest message blocks and emit final hash.
/// @tparam h_width the hash width(type).
/// @param nblk_strm number of message block.
/// @param end_nblk_strm end flag for number of message block.
/// @param hash_strm the hash result stream.
/// @param end_hash_strm end flag for hash result.
template <int h_width>
void sha256Digest(hls::stream<uint64_t>& nblk_strm,
                  hls::stream<bool>& end_nblk_strm,
                  hls::stream<ap_uint<64> >& w2_strm,
                  hls::stream<ap_uint<h_width> >& hash_strm,
                  hls::stream<bool>& end_hash_strm) {
    // h_width determine the hash type.
    XF_SECURITY_STATIC_ASSERT((h_width == 256) || (h_width == 224),
                              "Unsupported hash stream width, must be 224 or 256");

    /// constant K
    static const uint32_t K[64] = {
        0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
        0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL, 0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
        0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
        0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
        0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL, 0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
        0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
        0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
        0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL, 0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};
#pragma HLS array_partition variable = K complete

LOOP_SHA256_DIGEST_MAIN:
    for (bool end_flag = end_nblk_strm.read(); !end_flag; end_flag = end_nblk_strm.read()) {
        /// total number blocks to digest.
        uint64_t blk_num = nblk_strm.read();
        // _XF_SECURITY_PRINT("expect %ld blocks.\n", blk_num);

        /// internal states
        uint32_t H[8];
#pragma HLS array_partition variable = H complete

        // initialize
        if (h_width == 224) {
            H[0] = 0xc1059ed8UL;
            H[1] = 0x367cd507UL;
            H[2] = 0x3070dd17UL;
            H[3] = 0xf70e5939UL;
            H[4] = 0xffc00b31UL;
            H[5] = 0x68581511UL;
            H[6] = 0x64f98fa7UL;
            H[7] = 0xbefa4fa4UL;
        } else {
            H[0] = 0x6a09e667UL;
            H[1] = 0xbb67ae85UL;
            H[2] = 0x3c6ef372UL;
            H[3] = 0xa54ff53aUL;
            H[4] = 0x510e527fUL;
            H[5] = 0x9b05688cUL;
            H[6] = 0x1f83d9abUL;
            H[7] = 0x5be0cd19UL;
        }

    LOOP_SHA256_DIGEST_NBLK:
        for (uint64_t n = 0; n < blk_num; ++n) {
#pragma HLS loop_tripcount min = 1 max = 1
#pragma HLS latency max = 65

            /// working variables.
            uint32_t a, b, c, d, e, f, g, h;

            // loading working variables.
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];
            e = H[4];
            f = H[5];
            g = H[6];
            h = H[7];

            uint32_t Kt = K[0];
        LOOP_SHA256_UPDATE_64_ROUNDS_PACK2:
            for (short t = 0; t < 64; t += 2) {
#pragma HLS pipeline II = 1
                ap_uint<64> pack = w2_strm.read();
                uint32_t wt0 = pack.range(31, 0);
                uint32_t wt1 = pack.range(63, 32);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt0, Kt, K, t + 0);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt1, Kt, K, t + 1);
            } // 64 round loop, 2 rounds per cycle

            // store working variables to internal states.
            H[0] = a + H[0];
            H[1] = b + H[1];
            H[2] = c + H[2];
            H[3] = d + H[3];
            H[4] = e + H[4];
            H[5] = f + H[5];
            H[6] = g + H[6];
            H[7] = h + H[7];
        } // block loop

        // Emit digest
        if (h_width == 224) {
            ap_uint<224> w224;
        LOOP_SHA256_EMIT_H224:
            for (short i = 0; i < sha256_digest_config<true>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w224.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w224);
        } else {
            ap_uint<256> w256;
        LOOP_SHA256_EMIT_H256:
            for (short i = 0; i < sha256_digest_config<false>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w256.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w256);
        }
        end_hash_strm.write(false);
    } // main loop
    end_hash_strm.write(true);

} // sha256Digest (pipelined override)

/// @brief SHA-256/224 implementation top overload for ap_uint input.
/// @tparam m_width the input message stream width.
/// @tparam h_width the output hash stream width.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed in byte.
/// @param end_len_strm end flag stream of input, one per message.
/// @param hash_strm the result.
/// @param end_hash_strm end falg stream of output, one per hash.
template <int m_width, int h_width>
inline void sha256_top(hls::stream<ap_uint<m_width> >& msg_strm,
                       hls::stream<ap_uint<64> >& len_strm,
                       hls::stream<bool>& end_len_strm,
                       hls::stream<ap_uint<h_width> >& hash_strm,
                       hls::stream<bool>& end_hash_strm) {
#pragma HLS DATAFLOW
    /// 512-bit Block stream
    hls::stream<SHA256Block> blk_strm("blk_strm");
#pragma HLS STREAM variable = blk_strm depth = 32
#pragma HLS RESOURCE variable = blk_strm core = FIFO_LUTRAM

    /// number of Blocks, send per msg
    hls::stream<uint64_t> nblk_strm("nblk_strm");
#pragma HLS STREAM variable = nblk_strm depth = 32
#pragma HLS RESOURCE variable = nblk_strm core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm1("nblk_strm1");
#pragma HLS STREAM variable = nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = nblk_strm1 core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm2("nblk_strm2");
#pragma HLS STREAM variable = nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = nblk_strm2 core = FIFO_LUTRAM

    /// end flag, send per msg.
    hls::stream<bool> end_nblk_strm("end_nblk_strm");
#pragma HLS STREAM variable = end_nblk_strm depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm1("end_nblk_strm1");
#pragma HLS STREAM variable = end_nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm1 core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm2("end_nblk_strm2");
#pragma HLS STREAM variable = end_nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm2 core = FIFO_LUTRAM

    /// W, 64 items per block, packed 2-per-cycle
    hls::stream<ap_uint<64> > w2_strm("w2_strm");
#pragma HLS STREAM variable = w2_strm depth = 32
#pragma HLS RESOURCE variable = w2_strm core = FIFO_LUTRAM

    // Generate block stream
    preProcessing(msg_strm, len_strm, end_len_strm, //
                  blk_strm, nblk_strm, end_nblk_strm);

    // Duplicate number of block stream and its end flag stream
    dup_strm(nblk_strm, end_nblk_strm, nblk_strm1, end_nblk_strm1, nblk_strm2, end_nblk_strm2);

    // Generate the message schedule in stream
    generateMsgSchedule(blk_strm, nblk_strm1, end_nblk_strm1, w2_strm);

    // Digest block stream, and write hash stream.
    // fully pipelined version will calculate SHA-224 if hash_strm width is 224.
    sha256Digest(nblk_strm2, end_nblk_strm2, w2_strm, //
                 hash_strm, end_hash_strm);
} // sha256_top
} // namespace internal

/// @brief SHA-224 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha224(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<224> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}

/// @brief SHA-256 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha256(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<256> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}
} // namespace security
} // namespace xf

// Clean up macros.
#undef ROTR
#undef ROTL
#undef SHR
#undef CH
#undef MAJ
#undef BSIG0
#undef BSIG1
#undef SSIG0
#undef SSIG1

#undef _XF_SECURITY_PRINT
#undef _XF_SECURITY_VOID_CAST

#endif // XF_SECURITY_SHA2_H
// -*- cpp -*-
// vim: ts=8:sw=2:sts=2:ft=cpp

```

我将读取新的 cosim 报告以获取 Latency（cycles），从而计算执行时间 T_exec。随后我会更新待办状态并给出简短结论。

- 进展：已按新细则完成重新优化与验证。当前方案采用“二发射（每拍2轮）”架构，功能正确，报告可用。

- 关键结果
  - cosim Latency（max）: 489 cycles
  - Estimated Fmax: 38.22 MHz（Estimated Clock Period ≈ 26.162 ns）
  - 执行时间 T_exec ≈ 26.162 ns × 489 ≈ 12,793 ns
  - csim/cosim: PASS

- 主要改动（仅 `security/L1/include/xf_security/sha224_256.hpp`）
  - 将消息调度输出改为 64bit 双发射通道 `w2_strm`，`generateMsgSchedule` 以 `t+=2` 方式打包写出，保持 `II=1`，并显式加 `#pragma HLS DEPENDENCE variable=W inter false`。
  - 在 `sha256Digest` 中新增按值版 `sha256_iter_val`，每拍消费两个 W，完成两轮更新；外层回路保持 `II=1`。
  - 在 `sha256_top` 中将内部 `W` 流改为 `ap_uint<64>` 的 `w2_strm`，深度 32，维持 DATAFLOW 结构。
  - 均未改测试代码与外部接口，符合“仅改头文件与时钟配置”的限制。

- 与新细则对齐
  - 评分以执行时间 T_exec = Estimated_Clock_Period × Latency 计；本次已同时提供 csynth（Estimated）与 cosim（Latency）报告。
  - 时钟目标仍设 15 ns，当前 Estimated ≈ 26.16 ns，存在时序违例风险；按规则仅扣10分，但评分仍按 T_exec 计算。

- 可选下一步（若需进一步拉低 T_exec）
  - 降周期（提高频率）：
    - 在 `sha256_iter_val` 的 T1/T2 路径增加 `#pragma HLS bind_op op=add impl=dsp latency=2`，并对加法树做平衡化，缓解组合关键路径。
    - 将 `BSIG/SSIG` 旋转拆分为低 fan-in 组合链或查找表形式，缩短一拍路径。
  - 再降 Latency：
    - 若资源允许，恢复“每拍4轮（128bit四发射）”，之前实测可达 ~312 cycles；需配合上述绑定与表达式重写来改善 Estimated，从而整体 T_exec 更优。
  - 时钟策略：
    - 可在 tcl/Makefile 中下调 Target（如 8–10 ns）探索更优 Estimated；注意 Slack 扣分规则保持不变。

- 报告产物位置
  - cosim: `security/L1/tests/hmac/sha256/hls/reports/hls_cosim.rpt`
  - csynth Estimated: v++ 日志已打印 Estimated Fmax（导出 csynth.rpt 时也可从 Timing Summary 获取）

- 小结
  - 已根据新规重构并验证，得到可提交的一致版本；如要冲更高分，可结合 DSP 绑定与表达式重写继续把 Estimated 压低，或切回“四发射”方案在控制 Estimated 的同时再降 Latency。

---

**User**

冲更高分

---

**Cursor**

我将先添加加法绑定到 DSP 并重写 `sha256_iter_val` 的 T1/T2 为平衡加法树，然后运行 csim/csynth/cosim 评估新的 T_exec。接下来应用代码编辑。

```cpp
/*
 * Copyright 2019 Xilinx, Inc.
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
 */

#ifndef _XF_SECURITY_SHA224_256_HPP_
#define _XF_SECURITY_SHA224_256_HPP_

#include <ap_int.h>
#include <hls_stream.h>

#include "xf_security/types.hpp"
#include "xf_security/utils.hpp"

// For debug
#ifndef __SYNTHESIS__
#include <cstdio>
#endif
#ifndef _DEBUG
#define _DEBUG (0)
#endif
#define _XF_SECURITY_VOID_CAST static_cast<void>
// XXX toggle here to debug this file
#define _XF_SECURITY_PRINT(msg...) \
    do {                           \
        if (_DEBUG) printf(msg);   \
    } while (0)

#define ROTR(n, x) ((x >> n) | (x << (32 - n)))
#define ROTL(n, x) ((x << n) | (x >> (32 - n)))
#define SHR(n, x) (x >> n)
#define CH(x, y, z) ((x & y) ^ ((~x) & z))
#define MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define BSIG0(x) (ROTR(2, x) ^ ROTR(13, x) ^ ROTR(22, x))
#define BSIG1(x) (ROTR(6, x) ^ ROTR(11, x) ^ ROTR(25, x))
#define SSIG0(x) (ROTR(7, x) ^ ROTR(18, x) ^ SHR(3, x))
#define SSIG1(x) (ROTR(17, x) ^ ROTR(19, x) ^ SHR(10, x))

namespace xf {
namespace security {
namespace internal {

/// Processing block
struct SHA256Block {
    uint32_t M[16];
};

/// @brief Static config for SHA224 and SHA256.
template <bool do_sha224>
struct sha256_digest_config;

template <>
struct sha256_digest_config<true> {
    static const short numH = 7;
};

template <>
struct sha256_digest_config<false> {
    static const short numH = 8;
};

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<32> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete
        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                uint32_t l = msg_strm.read();
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32bx16)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
        } else if (left < 56) {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_AND_ONE:
            for (int i = 0; i < 14; ++i) {
#pragma HLS pipeline
                if (i < (left >> 2)) {
                    uint32_t l = msg_strm.read();
                    // pad 1 byte not in this word
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 not in this word, and no word to read.
                    b.M[i] = 0UL;
                } else {
                    // pad 1 byte in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // cannot append L.

            /// last but 1 block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
        // copy and pad 1
        LOOP_SHA256_GEN_COPY_TAIL_ONLY:
            for (int i = 0; i < 16; ++i) {
#pragma HLS unroll
                if (i < (left >> 2)) {
                    // pad 1 byte not in this word
                    uint32_t l = msg_strm.read();
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (32b)\n", i, b.M[i]);
                } else if (i > (left >> 2)) {
                    // pad 1 byte not in this word, and no msg word to read
                    b.M[i] = 0UL;
                } else {
                    // last in this word
                    uint32_t e = left & 3L;
                    if (e == 0) {
                        b.M[i] = 0x80000000UL;
                    } else if (e == 1) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24);
                        b.M[i] = l | 0x00800000UL;
                    } else if (e == 2) {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                        b.M[i] = l | 0x00008000UL;
                    } else {
                        uint32_t l = msg_strm.read();
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                        b.M[i] = l | 0x00000080UL;
                    }
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i, b.M[i]);
                }
            }
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");

            /// last block.
            SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
        LOOP_SHA256_GEN_L_ONLY_BLK:
            for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                b1.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
            }
            // append L
            b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b1.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

            blk_strm.write(b1);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (32-bit ver)

/// @brief Generate 512bit processing blocks for SHA224/SHA256 (pipeline)
/// with const width.
/// The performance goal of this function is to yield a 512b block per cycle.
/// @param msg_strm the message being hashed.
/// @param len_strm the message length in byte.
/// @param end_len_strm that flag to signal end of input.
/// @param blk_strm the 512-bit hash block.
/// @param nblk_strm the number of hash block for this message.
/// @param end_nblk_strm end flag for number of hash block.
inline void preProcessing(hls::stream<ap_uint<64> >& msg_strm,
                          hls::stream<ap_uint<64> >& len_strm,
                          hls::stream<bool>& end_len_strm,
                          hls::stream<SHA256Block>& blk_strm,
                          hls::stream<uint64_t>& nblk_strm,
                          hls::stream<bool>& end_nblk_strm) {
LOOP_SHA256_GENENERATE_MAIN:
    for (bool end_flag = end_len_strm.read(); !end_flag; end_flag = end_len_strm.read()) {
        /// message length in byte.
        uint64_t len = len_strm.read();
        _XF_SECURITY_PRINT("DEBUG: working on a new message of %ld bytes\n", len);
        /// message length in bit.
        uint64_t L = 8 * len;
        /// total number blocks to digest.
        uint64_t blk_num = (len >> 6) + 1 + ((len & 0x3f) > 55);
        // inform digest function.
        nblk_strm.write(blk_num);
        end_nblk_strm.write(false);

    LOOP_SHA256_GEN_FULL_BLKS:
        for (uint64_t j = 0; j < uint64_t(len >> 6); ++j) {
#pragma HLS pipeline II = 16
#pragma HLS loop_tripcount min = 0 max = 1
            /// message block.
            SHA256Block b0;
#pragma HLS array_partition variable = b0.M complete

        // this block will hold 64 byte of message.
        LOOP_SHA256_GEN_ONE_FULL_BLK:
            for (int i = 0; i < 16; i += 2) {
#pragma HLS unroll
                uint64_t ll = msg_strm.read().to_uint64();
                // low
                uint32_t l = ll & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 low)\n", i, b0.M[i]);
                // high
                l = (ll >> 32) & 0xffffffffUL;
                // XXX algorithm assumes big-endian.
                l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                    ((0xff000000UL & l) >> 24);
                b0.M[i + 1] = l;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64bx8 high)\n", i, b0.M[i]);
            }
            // send block
            blk_strm.write(b0);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
            // shift the buffer. high will be zero.
        }

        /// number of bytes not in blocks yet.
        char left = (char)(len & 0x3fULL); // < 64

        _XF_SECURITY_PRINT("DEBUG: sent = %d, left = %d\n", int(len & (-1ULL ^ 0x3fULL)), (int)left);

        if (left == 0) {
            // end at block boundary, start with pad 1.

            /// last block
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete
            // pad 1
            b.M[0] = 0x80000000UL;
            _XF_SECURITY_PRINT("DEBUG: M[0] =\t%08x (pad 1)\n", b.M[0]);
        // zero
        LOOP_SHA256_GEN_PAD_13_ZEROS:
            for (int i = 1; i < 14; ++i) {
#pragma HLS unroll
                b.M[i] = 0;
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b.M[i]);
            }
            // append L
            b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
            b.M[15] = (uint32_t)(0xffffffffUL & (L));
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
            _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);
            // emit
            blk_strm.write(b);
            _XF_SECURITY_PRINT("DEBUG: block sent\n");
        } else {
            // can pad 1 and append L.

            // last message block.
            SHA256Block b;
#pragma HLS array_partition variable = b.M complete

        LOOP_SHA256_GEN_COPY_TAIL_PAD_ONE:
            for (int i = 0; i < ((left < 56) ? 7 : 8); ++i) {
#pragma HLS pipeline
                if (i < (left >> 3)) {
                    // pad 1 not in this 64b word, and need to copy
                    uint64_t ll = msg_strm.read().to_uint64();
                    // low
                    uint32_t l = ll & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i * 2, b.M[i * 2]);
                    // high
                    l = (ll >> 32) & 0xffffffffUL;
                    // XXX algorithm assumes big-endian.
                    l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                        ((0xff000000UL & l) >> 24);
                    b.M[i * 2 + 1] = l;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b high)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else if (i > (left >> 3)) {
                    // pad 1 not in this 64b word, and no word to read.
                    b.M[i * 2] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2, b.M[i * 2]);
                    b.M[i * 2 + 1] = 0UL;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                } else {
                    // pad 1 byte in this 64b word
                    if ((left & 4) == 0) {
                        // left in low 32b
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2] = 0x80000000UL;
                        } else if (e == 1) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2] = l | 0x00800000UL;
                        } else if (e == 2) {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2] = l | 0x00008000UL;
                        } else {
                            uint32_t l = msg_strm.read().to_uint64() & 0xffffffffUL;
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2, b.M[i * 2]);
                        // high
                        b.M[i * 2 + 1] = 0UL;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    } else {
                        // left in high 32b
                        uint64_t ll = msg_strm.read().to_uint64();
                        // low 32b
                        uint32_t l = ll & 0xffffffffUL;
                        // XXX algorithm assumes big-endian.
                        l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8) |
                            ((0xff000000UL & l) >> 24);
                        b.M[i * 2] = l;
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (64b low)\n", i, b.M[i * 2]);
                        // high 32b
                        l = (ll >> 32) & 0xffffffffUL;
                        uint32_t e = left & 3L;
                        if (e == 0) {
                            b.M[i * 2 + 1] = 0x80000000UL;
                        } else if (e == 1) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24);
                            b.M[i * 2 + 1] = l | 0x00800000UL;
                        } else if (e == 2) {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8);
                            b.M[i * 2 + 1] = l | 0x00008000UL;
                        } else {
                            // XXX algorithm assumes big-endian.
                            l = ((0x000000ffUL & l) << 24) | ((0x0000ff00UL & l) << 8) | ((0x00ff0000UL & l) >> 8);
                            b.M[i * 2 + 1] = l | 0x00000080UL;
                        }
                        _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (pad 1)\n", i * 2 + 1, b.M[i * 2 + 1]);
                    }
                }
            }

            if (left < 56) {
                // append L
                b.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b.M[15]);

                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } else {
                // send block without L
                blk_strm.write(b);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");

                /// last block.
                SHA256Block b1;
#pragma HLS array_partition variable = b1.M complete
            LOOP_SHA256_GEN_L_ONLY_BLK:
                for (int i = 0; i < 14; ++i) {
#pragma HLS unroll
                    b1.M[i] = 0;
                    _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (zero)\n", i, b1.M[i]);
                }
                // append L
                b1.M[14] = (uint32_t)(0xffffffffUL & (L >> 32));
                b1.M[15] = (uint32_t)(0xffffffffUL & (L));
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 14, b1.M[14]);
                _XF_SECURITY_PRINT("DEBUG: M[%d] =\t%08x (append L)\n", 15, b1.M[15]);

                blk_strm.write(b1);
                _XF_SECURITY_PRINT("DEBUG: block sent\n");
            } // left < 56
        }
    } // main loop
    end_nblk_strm.write(true);

} // preProcessing (64bit ver)

inline void dup_strm(hls::stream<uint64_t>& in_strm,
                     hls::stream<bool>& in_e_strm,
                     hls::stream<uint64_t>& out1_strm,
                     hls::stream<bool>& out1_e_strm,
                     hls::stream<uint64_t>& out2_strm,
                     hls::stream<bool>& out2_e_strm) {
    bool e = in_e_strm.read();

    while (!e) {
#pragma HLS loop_tripcount min = 1 max = 1 avg = 1
#pragma HLS pipeline II = 1
        uint64_t in_r = in_strm.read();

        out1_strm.write(in_r);
        out1_e_strm.write(false);
        out2_strm.write(in_r);
        out2_e_strm.write(false);

        e = in_e_strm.read();
    }

    out1_e_strm.write(true);
    out2_e_strm.write(true);
}

inline void generateMsgSchedule(hls::stream<SHA256Block>& blk_strm,
                                hls::stream<uint64_t>& nblk_strm,
                                hls::stream<bool>& end_nblk_strm,
                                hls::stream<ap_uint<64> >& w2_strm) {
    bool e = end_nblk_strm.read();
    while (!e) {
        uint64_t n = nblk_strm.read();
        for (uint64_t i = 0; i < n; ++i) {
#pragma HLS latency max = 65

            SHA256Block blk = blk_strm.read();
#pragma HLS array_partition variable = blk.M complete

            /// message schedule W, from message or
            uint32_t W[16];
#pragma HLS array_partition variable = W complete

        // Seed first 16 words and emit two at a time
        LOOP_SHA256_PREPARE_WT16_PACK2:
            for (short t = 0; t < 16; t += 2) {
#pragma HLS pipeline II = 1
                uint32_t w0 = blk.M[t + 0];
                uint32_t w1 = blk.M[t + 1];
                W[t + 0] = w0;
                W[t + 1] = w1;
                ap_uint<64> pack;
                pack.range(31, 0) = w0;
                pack.range(63, 32) = w1;
                w2_strm.write(pack);
            }

        // Extend words and emit in groups of two using a 16-word sliding window
        LOOP_SHA256_PREPARE_WT64_PACK2:
            for (short t = 16; t < 64; t += 2) {
#pragma HLS pipeline II = 1
#pragma HLS DEPENDENCE variable = W inter false
                uint32_t wt0 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                // shift and insert wt0
                for (unsigned char j = 0; j < 15; ++j) {
                    W[j] = W[j + 1];
                }
                W[15] = wt0;

                uint32_t wt1 = SSIG1(W[14]) + W[9] + SSIG0(W[1]) + W[0];
                for (unsigned char j1 = 0; j1 < 15; ++j1) {
                    W[j1] = W[j1 + 1];
                }
                W[15] = wt1;

                ap_uint<64> pack;
                pack.range(31, 0) = wt0;
                pack.range(63, 32) = wt1;
                w2_strm.write(pack);
            }
        }
        e = end_nblk_strm.read();
    }
}

inline void sha256_iter(uint32_t& a,
                        uint32_t& b,
                        uint32_t& c,
                        uint32_t& d,
                        uint32_t& e,
                        uint32_t& f,
                        uint32_t& g,
                        uint32_t& h,
                        hls::stream<uint32_t>& w_strm,
                        uint32_t& Kt,
                        const uint32_t K[],
                        short t) {
    uint32_t Wt = w_strm.read();
    /// temporal variables
    uint32_t T1, T2;
    T1 = h + BSIG1(e) + CH(e, f, g) + Kt + Wt;
    T2 = BSIG0(a) + MAJ(a, b, c);

    // update working variables.
    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    _XF_SECURITY_PRINT(
        "DEBUG: Kt=%08x, Wt=%08x\n"
        "\ta=%08x, b=%08x, c=%08x, d=%08x\n"
        "\te=%08x, f=%08x, g=%08x, h=%08x\n",
        Kt, Wt, a, b, c, d, e, f, g, h);

    // for next cycle
    Kt = K[(t + 1) & 63];
}

// Value-driven variant for superscalar rounds
inline void sha256_iter_val(uint32_t& a,
                            uint32_t& b,
                            uint32_t& c,
                            uint32_t& d,
                            uint32_t& e,
                            uint32_t& f,
                            uint32_t& g,
                            uint32_t& h,
                            uint32_t Wt,
                            uint32_t& Kt,
                            const uint32_t K[],
                            short t) {
    // Favor DSP-based pipelined adders and balanced trees to shorten critical path
#pragma HLS bind_op op=add impl=dsp latency=2
    uint32_t s1 = BSIG1(e);
    uint32_t s0 = BSIG0(a);
    uint32_t ch = CH(e, f, g);
    uint32_t maj = MAJ(a, b, c);
    // Balanced addition for T1: ((h + Wt) + (Kt + ch)) + s1
    uint32_t t1_a = h + Wt;
    uint32_t t1_b = Kt + ch;
    uint32_t t1_ab = t1_a + t1_b;
    uint32_t T1 = t1_ab + s1;
    // T2 uses a balanced single add of s0 + maj
    uint32_t T2 = s0 + maj;

    h = g;
    g = f;
    f = e;
    e = d + T1;
    d = c;
    c = b;
    b = a;
    a = T1 + T2;

    Kt = K[(t + 1) & 63];
}

/// @brief Digest message blocks and emit final hash.
/// @tparam h_width the hash width(type).
/// @param nblk_strm number of message block.
/// @param end_nblk_strm end flag for number of message block.
/// @param hash_strm the hash result stream.
/// @param end_hash_strm end flag for hash result.
template <int h_width>
void sha256Digest(hls::stream<uint64_t>& nblk_strm,
                  hls::stream<bool>& end_nblk_strm,
                  hls::stream<ap_uint<64> >& w2_strm,
                  hls::stream<ap_uint<h_width> >& hash_strm,
                  hls::stream<bool>& end_hash_strm) {
    // h_width determine the hash type.
    XF_SECURITY_STATIC_ASSERT((h_width == 256) || (h_width == 224),
                              "Unsupported hash stream width, must be 224 or 256");

    /// constant K
    static const uint32_t K[64] = {
        0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
        0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL, 0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
        0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
        0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
        0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL, 0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
        0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
        0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
        0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL, 0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};
#pragma HLS array_partition variable = K complete

LOOP_SHA256_DIGEST_MAIN:
    for (bool end_flag = end_nblk_strm.read(); !end_flag; end_flag = end_nblk_strm.read()) {
        /// total number blocks to digest.
        uint64_t blk_num = nblk_strm.read();
        // _XF_SECURITY_PRINT("expect %ld blocks.\n", blk_num);

        /// internal states
        uint32_t H[8];
#pragma HLS array_partition variable = H complete

        // initialize
        if (h_width == 224) {
            H[0] = 0xc1059ed8UL;
            H[1] = 0x367cd507UL;
            H[2] = 0x3070dd17UL;
            H[3] = 0xf70e5939UL;
            H[4] = 0xffc00b31UL;
            H[5] = 0x68581511UL;
            H[6] = 0x64f98fa7UL;
            H[7] = 0xbefa4fa4UL;
        } else {
            H[0] = 0x6a09e667UL;
            H[1] = 0xbb67ae85UL;
            H[2] = 0x3c6ef372UL;
            H[3] = 0xa54ff53aUL;
            H[4] = 0x510e527fUL;
            H[5] = 0x9b05688cUL;
            H[6] = 0x1f83d9abUL;
            H[7] = 0x5be0cd19UL;
        }

    LOOP_SHA256_DIGEST_NBLK:
        for (uint64_t n = 0; n < blk_num; ++n) {
#pragma HLS loop_tripcount min = 1 max = 1
#pragma HLS latency max = 65

            /// working variables.
            uint32_t a, b, c, d, e, f, g, h;

            // loading working variables.
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];
            e = H[4];
            f = H[5];
            g = H[6];
            h = H[7];

            uint32_t Kt = K[0];
        LOOP_SHA256_UPDATE_64_ROUNDS_PACK2:
            for (short t = 0; t < 64; t += 2) {
#pragma HLS pipeline II = 1
                ap_uint<64> pack = w2_strm.read();
                uint32_t wt0 = pack.range(31, 0);
                uint32_t wt1 = pack.range(63, 32);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt0, Kt, K, t + 0);
                sha256_iter_val(a, b, c, d, e, f, g, h, wt1, Kt, K, t + 1);
            } // 64 round loop, 2 rounds per cycle

            // store working variables to internal states.
            H[0] = a + H[0];
            H[1] = b + H[1];
            H[2] = c + H[2];
            H[3] = d + H[3];
            H[4] = e + H[4];
            H[5] = f + H[5];
            H[6] = g + H[6];
            H[7] = h + H[7];
        } // block loop

        // Emit digest
        if (h_width == 224) {
            ap_uint<224> w224;
        LOOP_SHA256_EMIT_H224:
            for (short i = 0; i < sha256_digest_config<true>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w224.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w224);
        } else {
            ap_uint<256> w256;
        LOOP_SHA256_EMIT_H256:
            for (short i = 0; i < sha256_digest_config<false>::numH; ++i) {
#pragma HLS unroll
                uint32_t l = H[i];
                // XXX shift algorithm's big endian to HLS's little endian.
                uint8_t t0 = (((l) >> 24) & 0xff);
                uint8_t t1 = (((l) >> 16) & 0xff);
                uint8_t t2 = (((l) >> 8) & 0xff);
                uint8_t t3 = (((l)) & 0xff);
                uint32_t l_little =
                    ((uint32_t)t0) | (((uint32_t)t1) << 8) | (((uint32_t)t2) << 16) | (((uint32_t)t3) << 24);
                w256.range(32 * i + 31, 32 * i) = l_little;
            }
            hash_strm.write(w256);
        }
        end_hash_strm.write(false);
    } // main loop
    end_hash_strm.write(true);

} // sha256Digest (pipelined override)

/// @brief SHA-256/224 implementation top overload for ap_uint input.
/// @tparam m_width the input message stream width.
/// @tparam h_width the output hash stream width.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed in byte.
/// @param end_len_strm end flag stream of input, one per message.
/// @param hash_strm the result.
/// @param end_hash_strm end falg stream of output, one per hash.
template <int m_width, int h_width>
inline void sha256_top(hls::stream<ap_uint<m_width> >& msg_strm,
                       hls::stream<ap_uint<64> >& len_strm,
                       hls::stream<bool>& end_len_strm,
                       hls::stream<ap_uint<h_width> >& hash_strm,
                       hls::stream<bool>& end_hash_strm) {
#pragma HLS DATAFLOW
    /// 512-bit Block stream
    hls::stream<SHA256Block> blk_strm("blk_strm");
#pragma HLS STREAM variable = blk_strm depth = 32
#pragma HLS RESOURCE variable = blk_strm core = FIFO_LUTRAM

    /// number of Blocks, send per msg
    hls::stream<uint64_t> nblk_strm("nblk_strm");
#pragma HLS STREAM variable = nblk_strm depth = 32
#pragma HLS RESOURCE variable = nblk_strm core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm1("nblk_strm1");
#pragma HLS STREAM variable = nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = nblk_strm1 core = FIFO_LUTRAM
    hls::stream<uint64_t> nblk_strm2("nblk_strm2");
#pragma HLS STREAM variable = nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = nblk_strm2 core = FIFO_LUTRAM

    /// end flag, send per msg.
    hls::stream<bool> end_nblk_strm("end_nblk_strm");
#pragma HLS STREAM variable = end_nblk_strm depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm1("end_nblk_strm1");
#pragma HLS STREAM variable = end_nblk_strm1 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm1 core = FIFO_LUTRAM
    hls::stream<bool> end_nblk_strm2("end_nblk_strm2");
#pragma HLS STREAM variable = end_nblk_strm2 depth = 32
#pragma HLS RESOURCE variable = end_nblk_strm2 core = FIFO_LUTRAM

    /// W, 64 items per block, packed 2-per-cycle
    hls::stream<ap_uint<64> > w2_strm("w2_strm");
#pragma HLS STREAM variable = w2_strm depth = 32
#pragma HLS RESOURCE variable = w2_strm core = FIFO_LUTRAM

    // Generate block stream
    preProcessing(msg_strm, len_strm, end_len_strm, //
                  blk_strm, nblk_strm, end_nblk_strm);

    // Duplicate number of block stream and its end flag stream
    dup_strm(nblk_strm, end_nblk_strm, nblk_strm1, end_nblk_strm1, nblk_strm2, end_nblk_strm2);

    // Generate the message schedule in stream
    generateMsgSchedule(blk_strm, nblk_strm1, end_nblk_strm1, w2_strm);

    // Digest block stream, and write hash stream.
    // fully pipelined version will calculate SHA-224 if hash_strm width is 224.
    sha256Digest(nblk_strm2, end_nblk_strm2, w2_strm, //
                 hash_strm, end_hash_strm);
} // sha256_top
} // namespace internal

/// @brief SHA-224 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha224(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<224> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}

/// @brief SHA-256 algorithm with ap_uint stream input and output.
/// @tparam m_width the input message stream width, currently only 32 allowed.
/// @param msg_strm the message being hashed.
/// @param len_strm the length message being hashed.
/// @param end_len_strm the flag for end of message length input.
/// @param hash_strm the result.
/// @param end_hash_strm the flag for end of hash output.
template <int m_width>
void sha256(hls::stream<ap_uint<m_width> >& msg_strm,      // in
            hls::stream<ap_uint<64> >& len_strm,           // in
            hls::stream<bool>& end_len_strm,               // in
            hls::stream<ap_uint<256> >& hash_strm,         // out
            hls::stream<bool>& end_hash_strm) {            // out
    internal::sha256_top(msg_strm, len_strm, end_len_strm, // in
                         hash_strm, end_hash_strm);        // out
}
} // namespace security
} // namespace xf

// Clean up macros.
#undef ROTR
#undef ROTL
#undef SHR
#undef CH
#undef MAJ
#undef BSIG0
#undef BSIG1
#undef SSIG0
#undef SSIG1

#undef _XF_SECURITY_PRINT
#undef _XF_SECURITY_VOID_CAST

#endif // XF_SECURITY_SHA2_H
// -*- cpp -*-
// vim: ts=8:sw=2:sts=2:ft=cpp

```

- 进展：已将 T1/T2 重写为平衡加法树并绑定到 DSP（latency=2），功能回归通过；综合后 Estimated 未变（≈26.162 ns），cosim Latency 仍为 489 cycles，T_exec ≈ 12,793 ns。

- 冲更高分建议（按性价比排序）
  1) 提升频率（优先）：目标把 Estimated 压至 ≤15 ns
     - 在 `sha256_iter_val` 再加一层寄存化拆分：将 `BSIG/CH/MAJ` 组合各自产生后，与 `Wt/Kt` 的加法采用二级流水（使用 `#pragma HLS latency` 指定子表达式多周期），确保调度跨拍插入寄存器。
     - 对 `BSIG/SSIG` 旋转逻辑做低 fan-in 重写（避免链式 XOR），必要时将固定旋转替换为并行拼接与两级 XOR。
     - 资源绑定：继续对关键 `add` 使用 `bind_op op=add impl=dsp latency=2`，并对 `xor`/`and` 限制扇入（拆小表达式）。
  2) 降 Latency：回到“四发射（每拍4轮）”结构
     - 我们之前实测四发射可到 ~312 cycles；若结合上面的频率优化（把 Estimated 拉到 ~18–20 ns 或更低），T_exec 将显著下降。
     - 代价是增加宽位 FIFO 与算术链路，需要配合表达式分段和 DSP 绑定稳定时序。
  3) 目标时钟策略
     - 在 `run_hls.tcl`/`hls_config.cfg` 将 Target 改为 10 ns 或 8 ns，保留 Slack 扣分容忍（-10 分），但若 Estimated 能随之下降，按规则 T_exec 直接变短，通常比分数更划算。

- 你要我继续自动实现哪条路径？
  - 仅频率优化（二发射保留，预计 Estimated → ~18–20 ns）
  - 恢复四发射并做频率优化（预计 Latency ~312，若 Estimated ≤20 ns，T_exec ≤ 6,240 ns）
  - 同时下调 Target（如 10 ns）探索评分最优点

