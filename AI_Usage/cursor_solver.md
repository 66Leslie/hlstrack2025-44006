# solver
_Exported on 2025/10/21 at GMT+8 23:24:44 from Cursor (1.7.53)_

---

**User**

由于竞赛组委会更新细则@README.md @命题式基础赛道初赛评分细则.md @SUBMISSION_GUIDE_Linux.md 我们需要根据新的要求，重新对第三题 HLS进行优化，这是我之前的优化记录@cholesky_optimize.md ，你可以查看并思考或者也可以参考同目录下的修改记录，可以参考但是必须根据当前题目的特殊地方，做出对应修改（特别是上一轮修改效果很差）


---

**Cursor**

我先快速核对最新评分细则与题目限定，并定位可修改文件与当前实现：我会并行读取仓库 `README.md`、搜索评分细则文件、定位 `cholesky.hpp`、以及查看本题测试目录下的 `hls_config.tmpl` 和 `dut_type.hpp`。随后我会基于新的限制制定并执行优化编辑。

我将并行读取评分细则与 `cholesky.hpp`，并确认 `SUBMISSION_GUIDE_Linux.md` 的具体限制，以便制定与新规一致的优化方案和必要编辑。随后我会根据读取结果更新具体优化计划并实施。

我将读取 `solver/L1/include/hw/cholesky.hpp` 以定位 ARCH0 的实现与可插入 pragma 的循环与数组，确保优化在 `SEL_ARCH=0` 路径内生效。

我将更新 `cholesky.hpp` 以满足新细则：1) 让 `SEL_ARCH` 生效（确保 ARCH0 路径），2) 修复 ARCH0 对角累加的错误，3) 为 `diag_loop` 加流水线，4) 预计算对角倒数并用乘法替代除法，5) 对 `L_internal` 做二维完全分区并消除伪相关。这些都是头文件内的合规编辑。接着我会检查静态分析报错。

```cpp
/*
 * Copyright 2021 Xilinx, Inc.
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

/**
 * @file cholesky.hpp
 * @brief This file contains cholesky functions
 *   - cholesky                 : Entry point function
 *   - choleskyTop             : Top level function that selects implementation architecture and internal types based
 * on a traits class.
 *   - choleskyBasic           : Basic implementation requiring lower resource
 *   - choleskyAlt             : Lower latency architecture requiring more resources
 *   - choleskyAlt2            : Further improved latency architecture requiring higher resource
 */

#ifndef _XF_SOLVER_CHOLESKY_HPP_
#define _XF_SOLVER_CHOLESKY_HPP_

#include "ap_fixed.h"
#include "hls_x_complex.h"
#include <complex>
#include "utils/std_complex_utils.h"
#include "utils/x_matrix_utils.hpp"
#include "hls_stream.h"

namespace xf {
namespace solver {

// ===================================================================================================================
// Default traits struct defining the internal variable types for the cholesky function
template <bool LowerTriangularL, int RowsColsA, typename InputType, typename OutputType>
struct choleskyTraits {
    typedef InputType PROD_T;
    typedef InputType ACCUM_T;
    typedef InputType ADD_T;
    typedef InputType DIAG_T;
    typedef InputType RECIP_DIAG_T;
    typedef InputType OFF_DIAG_T;
    typedef OutputType L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH; // Select implementation via external macro when provided
#else
    static const int ARCH =
        1; // Select implementation: 0=Basic, 1=Lower latency architecture, 2=Further improved latency architecture
#endif
    static const int INNER_II = 1; // Specify the pipelining target for the inner loop
    static const int UNROLL_FACTOR =
        1; // Specify the inner loop unrolling factor for the choleskyAlt2 architecture(2) to increase throughput
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2); // Dimension to unroll matrix
    static const int ARCH2_ZERO_LOOP =
        true; // Additional implementation "switch" for the choleskyAlt2 architecture (2).
};

// Specialization for complex
template <bool LowerTriangularL, int RowsColsA, typename InputBaseType, typename OutputBaseType>
struct choleskyTraits<LowerTriangularL, RowsColsA, hls::x_complex<InputBaseType>, hls::x_complex<OutputBaseType> > {
    typedef hls::x_complex<InputBaseType> PROD_T;
    typedef hls::x_complex<InputBaseType> ACCUM_T;
    typedef hls::x_complex<InputBaseType> ADD_T;
    typedef hls::x_complex<InputBaseType> DIAG_T;
    typedef InputBaseType RECIP_DIAG_T;
    typedef hls::x_complex<InputBaseType> OFF_DIAG_T;
    typedef hls::x_complex<OutputBaseType> L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Specialization for std complex
template <bool LowerTriangularL, int RowsColsA, typename InputBaseType, typename OutputBaseType>
struct choleskyTraits<LowerTriangularL, RowsColsA, std::complex<InputBaseType>, std::complex<OutputBaseType> > {
    typedef std::complex<InputBaseType> PROD_T;
    typedef std::complex<InputBaseType> ACCUM_T;
    typedef std::complex<InputBaseType> ADD_T;
    typedef std::complex<InputBaseType> DIAG_T;
    typedef InputBaseType RECIP_DIAG_T;
    typedef std::complex<InputBaseType> OFF_DIAG_T;
    typedef std::complex<OutputBaseType> L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Specialization for ap_fixed
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL, RowsColsA, ap_fixed<W1, I1, Q1, O1, N1>, ap_fixed<W2, I2, Q2, O2, N2> > {
    typedef ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> PROD_T;
    typedef ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                     (I1 + I1) + BitWidth<RowsColsA>::Value,
                     AP_RND_CONV,
                     AP_SAT,
                     0>
        ACCUM_T;
    typedef ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> ADD_T;
    typedef ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> DIAG_T;     // Takes result of sqrt
    typedef ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0>
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Further specialization for hls::complex<ap_fixed>
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL,
                      RowsColsA,
                      hls::x_complex<ap_fixed<W1, I1, Q1, O1, N1> >,
                      hls::x_complex<ap_fixed<W2, I2, Q2, O2, N2> > > {
    typedef hls::x_complex<ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> > PROD_T;
    typedef hls::x_complex<ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                                    (I1 + I1) + BitWidth<RowsColsA>::Value,
                                    AP_RND_CONV,
                                    AP_SAT,
                                    0> >
        ACCUM_T;
    typedef hls::x_complex<ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> > ADD_T;
    typedef hls::x_complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > DIAG_T;     // Takes result of sqrt
    typedef hls::x_complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef hls::x_complex<ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0> >
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Further specialization for std::complex<ap_fixed>
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL,
                      RowsColsA,
                      std::complex<ap_fixed<W1, I1, Q1, O1, N1> >,
                      std::complex<ap_fixed<W2, I2, Q2, O2, N2> > > {
    typedef std::complex<ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> > PROD_T;
    typedef std::complex<ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                                  (I1 + I1) + BitWidth<RowsColsA>::Value,
                                  AP_RND_CONV,
                                  AP_SAT,
                                  0> >
        ACCUM_T;
    typedef std::complex<ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> > ADD_T;
    typedef std::complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > DIAG_T;     // Takes result of sqrt
    typedef std::complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef std::complex<ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0> >
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
    static const int ARCH = 1;
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// ===================================================================================================================
// Helper functions

// Square root
// o Overloaded versions of the sqrt function
// o The square root of a complex number is expensive.  However, the diagonal values of a Cholesky decomposition are
// always
//   real so we don't need a full complex square root.
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(T_IN a, T_OUT& b) {
Function_cholesky_sqrt_op_real:;
    const T_IN ZERO = 0;
    if (a < ZERO) {
        b = ZERO;
        return (1);
    }
    b = x_sqrt(a);
    return (0);
}
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(hls::x_complex<T_IN> din, hls::x_complex<T_OUT>& dout) {
Function_cholesky_sqrt_op_complex:;
    const T_IN ZERO = 0;
    T_IN a = din.real();
    dout.imag(ZERO);

    if (a < ZERO) {
        dout.real(ZERO);
        return (1);
    }

    dout.real(x_sqrt(a));
    return (0);
}
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(std::complex<T_IN> din, std::complex<T_OUT>& dout) {
Function_cholesky_sqrt_op_complex:;
    const T_IN ZERO = 0;
    T_IN a = din.real();
    dout.imag(ZERO);

    if (a < ZERO) {
        dout.real(ZERO);
        return (1);
    }

    dout.real(x_sqrt(a));
    return (0);
}

// Reciprocal square root.
template <typename InputType, typename OutputType>
void cholesky_rsqrt(InputType x, OutputType& res) {
Function_cholesky_rsqrt_default:;
    res = x_rsqrt(x);
}
template <int W1, int I1, ap_q_mode Q1, ap_o_mode O1, int N1, int W2, int I2, ap_q_mode Q2, ap_o_mode O2, int N2>
void cholesky_rsqrt(ap_fixed<W1, I1, Q1, O1, N1> x, ap_fixed<W2, I2, Q2, O2, N2>& res) {
Function_cholesky_rsqrt_fixed:;
    ap_fixed<W2, I2, Q2, O2, N2> one = 1;
    ap_fixed<W1, I1, Q1, O1, N1> sqrt_res;
    ap_fixed<W2, I2, Q2, O2, N2> sqrt_res_cast;
    sqrt_res = x_sqrt(x);
    sqrt_res_cast = sqrt_res;
    res = one / sqrt_res_cast;
}

// Local multiplier to handle a complex case currently not supported by the hls::x_complex class
// - Complex multiplied by a real of a different type
// - Required for complex fixed point implementations
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(AType A, BType B, CType& C) {
Function_cholesky_prod_sum_mult_real:;
    C = A * B;
}
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(hls::x_complex<AType> A, BType B, hls::x_complex<CType>& C) {
Function_cholesky_prod_sum_mult_complex:;
    C.real(A.real() * B);
    C.imag(A.imag() * B);
}
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(std::complex<AType> A, BType B, std::complex<CType>& C) {
Function_cholesky_prod_sum_mult_complex:;
    C.real(A.real() * B);
    C.imag(A.imag() * B);
}

// ===================================================================================================================
// choleskyBasic
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyBasic(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // Use the traits struct to specify the correct type for the intermediate variables. This is really only needed for
    // fixed point.
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T sum[RowsColsA];
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;    // A with the same dimensions as sum.
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum; // prod with the same dimensions as sum.

    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T new_L_diag;         // sqrt(A_minus_sum)
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag; // sum/L
    typename CholeskyTraits::OFF_DIAG_T L_cast_to_new_L_off_diag;

    typename CholeskyTraits::L_OUTPUT_T new_L;
    OutputType retrieved_L;
    // Internal memory used to aviod read access from function output argument L.
    // NOTE: The internal matrix only needs to be triangular but optimization using a 1-D array it will require addition
    // logic to generate the indexes. Refer to the choleskyAlt function.
    OutputType L_internal[RowsColsA][RowsColsA];

col_loop:
    for (int j = 0; j < RowsColsA; j++) {
        sum[j] = 0;

    // Calculate the diagonal value for this column
    diag_loop:
        for (int k = 0; k < RowsColsA; k++) {
            if (k <= (j - 1)) {
                if (LowerTriangularL == true) {
                    retrieved_L = L_internal[j][k];
                } else {
                    retrieved_L = L_internal[k][j];
                }
                sum[j] = hls::x_conj(retrieved_L) * retrieved_L;
            }
        }
        A_cast_to_sum = A[j][j];

        A_minus_sum = A_cast_to_sum - sum[j];

        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }

        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;

        if (LowerTriangularL == true) {
            L_internal[j][j] = new_L;
            L[j][j] = new_L;
        } else {
            L_internal[j][j] = hls::x_conj(new_L);
            L[j][j] = hls::x_conj(new_L);
        }

    // Calculate the off diagonal values for this column
    off_diag_loop:
        for (int i = 0; i < RowsColsA; i++) {
            if (i > j) {
                if (LowerTriangularL == true) {
                    sum[j] = A[i][j];
                } else {
                    sum[j] = hls::x_conj(A[j][i]);
                }

            sum_loop:
                for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
                    if (k <= (j - 1)) {
                        if (LowerTriangularL == true) {
                            prod = -L_internal[i][k] * hls::x_conj(L_internal[j][k]);
                        } else {
                            prod = -hls::x_conj(L_internal[k][i]) * (L_internal[k][j]);
                        }

                        prod_cast_to_sum = prod;
                        sum[j] += prod_cast_to_sum;
                    }
                }

                new_L_off_diag = sum[j];

                L_cast_to_new_L_off_diag = L_internal[j][j];

                // Diagonal is always real, avoid complex division
                new_L_off_diag = new_L_off_diag / hls::x_real(L_cast_to_new_L_off_diag);

                // Round to target format using method specifed by traits defined types.
                new_L = new_L_off_diag;

                if (LowerTriangularL == true) {
                    L[i][j] = new_L;
                    L_internal[i][j] = new_L;
                } else {
                    L[j][i] = hls::x_conj(new_L);
                    L_internal[j][i] = hls::x_conj(new_L);
                }
            } else if (i < j) {
                if (LowerTriangularL == true) {
                    L[i][j] = 0;
                } else {
                    L[j][i] = 0;
                }
            }
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyAlt: Alternative architecture with improved latency at the expense of higher resource
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyAlt(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // Optimize internal memories
    // - For complex data types the diagonal will be real only, plus for fixed point it must be stored to a
    //   higher precision.
    // - Requires additional logic to generate the memory indexes
    // - For smaller matrix sizes there maybe be an increase in memory usage
    OutputType L_internal[(RowsColsA * RowsColsA - RowsColsA) / 2];
    typename CholeskyTraits::RECIP_DIAG_T diag_internal[RowsColsA];

    typename CholeskyTraits::ACCUM_T square_sum;
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;
    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag;
    typename CholeskyTraits::DIAG_T new_L_diag;
    typename CholeskyTraits::RECIP_DIAG_T new_L_diag_recip;
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum;
    typename CholeskyTraits::ACCUM_T product_sum;
    typename CholeskyTraits::OFF_DIAG_T prod_cast_to_off_diag;
    typename CholeskyTraits::RECIP_DIAG_T L_diag_recip;
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag;
    typename CholeskyTraits::L_OUTPUT_T new_L;
    typename CholeskyTraits::L_OUTPUT_T new_L_recip;

row_loop:
    for (int i = 0; i < RowsColsA; i++) {
        // Index generation for optimized/packed L_internal memory
        int i_sub1 = i - 1;
        int i_off = ((i_sub1 * i_sub1 - i_sub1) / 2) + i_sub1;

        // Off diagonal calculation
        square_sum = 0;
    col_loop:
        for (int j = 0; j < i; j++) {
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
            // Index generation
            int j_sub1 = j - 1;
            int j_off = ((j_sub1 * j_sub1 - j_sub1) / 2) + j_sub1;
            // Prime the off-diagonal sum with target elements A value.
            if (LowerTriangularL == true) {
                product_sum = A[i][j];
            } else {
                product_sum = hls::x_conj(A[j][i]);
            }
        sum_loop:
            for (int k = 0; k < j; k++) {
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
                prod = -L_internal[i_off + k] * hls::x_conj(L_internal[j_off + k]);
                prod_cast_to_sum = prod;
                product_sum += prod_cast_to_sum;
            }
            prod_cast_to_off_diag = product_sum;
            // Fetch diagonal value
            L_diag_recip = diag_internal[j];
            // Diagonal is stored in its reciprocal form so only need to multiply the product sum
            cholesky_prod_sum_mult(prod_cast_to_off_diag, L_diag_recip, new_L_off_diag);
            // Round to target format using method specifed by traits defined types.
            new_L = new_L_off_diag;
            // Build sum for use in diagonal calculation for this row.
            square_sum += hls::x_conj(new_L) * new_L;
            // Store result
            L_internal[i_off + j] = new_L;
            if (LowerTriangularL == true) {
                L[i][j] = new_L; // store in lower triangle
                L[j][i] = 0;     // Zero upper
            } else {
                L[j][i] = hls::x_conj(new_L); // store in upper triangle
                L[i][j] = 0;                  // Zero lower
            }
        }

        // Diagonal calculation
        A_cast_to_sum = A[i][i];
        A_minus_sum = A_cast_to_sum - square_sum;
        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }
        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;
        // Generate the reciprocal of the diagonal for internal use to aviod the latency of a divide in every
        // off-diagonal calculation
        A_minus_sum_cast_diag = A_minus_sum;
        cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);
        // Store diagonal value
        diag_internal[i] = new_L_diag_recip;
        if (LowerTriangularL == true) {
            L[i][i] = new_L;
        } else {
            L[i][i] = hls::x_conj(new_L);
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyAlt2: Further improved latency architecture requiring higher resource
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyAlt2(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // To avoid array index calculations every iteration this architecture uses a simple 2D array rather than a
    // optimized/packed triangular matrix.
    OutputType L_internal[RowsColsA][RowsColsA];
    OutputType prod_column_top;
    typename CholeskyTraits::ACCUM_T square_sum_array[RowsColsA];
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;
    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag;
    typename CholeskyTraits::DIAG_T new_L_diag;
    typename CholeskyTraits::RECIP_DIAG_T new_L_diag_recip;
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum;
    typename CholeskyTraits::ACCUM_T product_sum;
    typename CholeskyTraits::ACCUM_T product_sum_array[RowsColsA];
    typename CholeskyTraits::OFF_DIAG_T prod_cast_to_off_diag;
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag;
    typename CholeskyTraits::L_OUTPUT_T new_L;

#pragma HLS ARRAY_PARTITION variable = A cyclic dim = CholeskyTraits::UNROLL_DIM factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = L cyclic dim = CholeskyTraits::UNROLL_DIM factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = L_internal cyclic dim = CholeskyTraits::UNROLL_DIM factor = \
    CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = square_sum_array cyclic dim = 1 factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = product_sum_array cyclic dim = 1 factor = CholeskyTraits::UNROLL_FACTOR

col_loop:
    for (int j = 0; j < RowsColsA; j++) {
        // Diagonal calculation
        A_cast_to_sum = A[j][j];
        if (j == 0) {
            A_minus_sum = A_cast_to_sum;
        } else {
            A_minus_sum = A_cast_to_sum - square_sum_array[j];
        }
        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }
        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;
        // Generate the reciprocal of the diagonal for internal use to aviod the latency of a divide in every
        // off-diagonal calculation
        A_minus_sum_cast_diag = A_minus_sum;
        cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);
        // Store diagonal value
        if (LowerTriangularL == true) {
            L[j][j] = new_L;
        } else {
            L[j][j] = hls::x_conj(new_L);
        }

    sum_loop:
        for (int k = 0; k <= j; k++) {
// Define average trip count for reporting, loop reduces in length for every iteration of col_loop
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
            // Same value used in all calcs
            // o Implement -1* here
            prod_column_top = -hls::x_conj(L_internal[j][k]);

        // NOTE: Using a fixed loop length combined with a "if" to implement reducing loop length
        // o Ensures the inner loop can achieve the maximum II (1)
        // o May introduce a small overhead resolving the "if" statement but HLS struggled to schedule when the variable
        //   loop bound expression was used.
        // o Will report inaccurate trip count as it will reduce by one with the col_loop
        // o Variable loop bound code: row_loop: for(int i = j+1; i < RowsColsA; i++) {
        row_loop:
            for (int i = 0; i < RowsColsA; i++) {
// IMPORTANT: row_loop must not merge with sum_loop as the merged loop becomes variable length and HLS will struggle
// with scheduling
#pragma HLS LOOP_FLATTEN off
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
#pragma HLS UNROLL FACTOR = CholeskyTraits::UNROLL_FACTOR

                if (i > j) {
                    prod = L_internal[i][k] * prod_column_top;
                    prod_cast_to_sum = prod;

                    if (k == 0) {
                        // Prime first sum
                        if (LowerTriangularL == true) {
                            A_cast_to_sum = A[i][j];
                        } else {
                            A_cast_to_sum = hls::x_conj(A[j][i]);
                        }
                        product_sum = A_cast_to_sum;
                    } else {
                        product_sum = product_sum_array[i];
                    }

                    if (k < j) {
                        // Accumulate row sum of columns
                        product_sum_array[i] = product_sum + prod_cast_to_sum;
                    } else {
                        // Final calculation for off diagonal value
                        prod_cast_to_off_diag = product_sum;
                        // Diagonal is stored in its reciprocal form so only need to multiply the product sum
                        cholesky_prod_sum_mult(prod_cast_to_off_diag, new_L_diag_recip, new_L_off_diag);
                        // Round to target format using method specifed by traits defined types.
                        new_L = new_L_off_diag;
                        // Build sum for use in diagonal calculation for this row.
                        if (k == 0) {
                            square_sum_array[j] = hls::x_conj(new_L) * new_L;
                        } else {
                            square_sum_array[j] = hls::x_conj(new_L) * new_L;
                        }
                        // Store result
                        L_internal[i][j] = new_L;
                        // NOTE: Use the upper/lower triangle zeroing in the subsequent loop so the double memory access
                        // does not
                        // become a bottleneck
                        // o Results in a further increase of DSP resources due to the higher II of this loop.
                        // o Retaining the zeroing operation here can give this a loop a max II of 2 and HLS will
                        // resource share.
                        if (LowerTriangularL == true) {
                            L[i][j] = new_L;                                   // Store in lower triangle
                            if (!CholeskyTraits::ARCH2_ZERO_LOOP) L[j][i] = 0; // Zero upper
                        } else {
                            L[j][i] = hls::x_conj(new_L);                      // Store in upper triangle
                            if (!CholeskyTraits::ARCH2_ZERO_LOOP) L[i][j] = 0; // Zero lower
                        }
                    }
                }
            }
        }
    }
    // Zero upper/lower triangle
    // o Use separate loop to ensure main calcuation can achieve an II of 1
    // o As noted above this may increase the DSP resources.
    // o Required when unrolling the inner loop due to array dimension access
    if (CholeskyTraits::ARCH2_ZERO_LOOP) {
    zero_rows_loop:
        for (int i = 0; i < RowsColsA - 1; i++) {
        zero_cols_loop:
            for (int j = i + 1; j < RowsColsA; j++) {
// Define average trip count for reporting, loop reduces in length for every iteration of zero_rows_loop
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
#pragma HLS PIPELINE
                if (LowerTriangularL == true) {
                    L[i][j] = 0; // Zero upper
                } else {
                    L[j][i] = 0; // Zero lower
                }
            }
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyTop: Top level function that selects implementation architecture and internal types based on the
// traits class provided via the CholeskyTraits template parameter.
// o Call this function directly if you wish to override the default architecture choice or internal types
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyTop(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    switch (CholeskyTraits::ARCH) {
        case 0:
            return choleskyBasic<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        case 1:
            return choleskyAlt<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        case 2:
            return choleskyAlt2<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        default:
            return choleskyBasic<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
    }
}

/**
* @brief cholesky
*
* @tparam LowerTriangularL   When false generates the result in the upper triangle
* @tparam RowsColsA          Defines the matrix dimensions
* @tparam InputType          Input data type
* @tparam OutputType         Output data type
* @tparam TRAITS             choleskyTraits class
*
* @param matrixAStrm         Stream of Hermitian/symmetric positive definite input matrix
* @param matrixLStrm         Stream of Lower or upper triangular output matrix
*
* @return                    An integer type. 0=Success. 1=Failure. The function attempted to find the square root of
* a negative number i.e. the input matrix A was not Hermitian/symmetric positive definite.
*/
template <bool LowerTriangularL,
          int RowsColsA,
          class InputType,
          class OutputType,
          typename TRAITS = choleskyTraits<LowerTriangularL, RowsColsA, InputType, OutputType> >
int cholesky(hls::stream<InputType>& matrixAStrm, hls::stream<OutputType>& matrixLStrm) {
    InputType A[RowsColsA][RowsColsA];
    OutputType L[RowsColsA][RowsColsA];

    for (int r = 0; r < RowsColsA; r++) {
#pragma HLS PIPELINE
        for (int c = 0; c < RowsColsA; c++) {
            matrixAStrm.read(A[r][c]);
        }
    }

    int ret = 0;
    ret = choleskyTop<LowerTriangularL, RowsColsA, TRAITS, InputType, OutputType>(A, L);

    for (int r = 0; r < RowsColsA; r++) {
#pragma HLS PIPELINE
        for (int c = 0; c < RowsColsA; c++) {
            matrixLStrm.write(L[r][c]);
        }
    }
    return ret;
}

} // end namespace solver
} // end namespace xf
#endif

```

我已开始根据新细则在 `cholesky.hpp` 的 ARCH0 路径实施合规优化：使 `SEL_ARCH` 覆盖生效后，我将对 `choleskyBasic` 修复对角累加、加入流水线、用倒数乘法替代除法，并对 `L_internal` 做二维完全分区与依赖解除，随后检查该文件的 lints。接下来我会应用这些编辑。

```cpp
/*
 * Copyright 2021 Xilinx, Inc.
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

/**
 * @file cholesky.hpp
 * @brief This file contains cholesky functions
 *   - cholesky                 : Entry point function
 *   - choleskyTop             : Top level function that selects implementation architecture and internal types based
 * on a traits class.
 *   - choleskyBasic           : Basic implementation requiring lower resource
 *   - choleskyAlt             : Lower latency architecture requiring more resources
 *   - choleskyAlt2            : Further improved latency architecture requiring higher resource
 */

#ifndef _XF_SOLVER_CHOLESKY_HPP_
#define _XF_SOLVER_CHOLESKY_HPP_

#include "ap_fixed.h"
#include "hls_x_complex.h"
#include <complex>
#include "utils/std_complex_utils.h"
#include "utils/x_matrix_utils.hpp"
#include "hls_stream.h"

namespace xf {
namespace solver {

// ===================================================================================================================
// Default traits struct defining the internal variable types for the cholesky function
template <bool LowerTriangularL, int RowsColsA, typename InputType, typename OutputType>
struct choleskyTraits {
    typedef InputType PROD_T;
    typedef InputType ACCUM_T;
    typedef InputType ADD_T;
    typedef InputType DIAG_T;
    typedef InputType RECIP_DIAG_T;
    typedef InputType OFF_DIAG_T;
    typedef OutputType L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH; // Select implementation via external macro when provided
#else
    static const int ARCH =
        1; // Select implementation: 0=Basic, 1=Lower latency architecture, 2=Further improved latency architecture
#endif
    static const int INNER_II = 1; // Specify the pipelining target for the inner loop
    static const int UNROLL_FACTOR =
        1; // Specify the inner loop unrolling factor for the choleskyAlt2 architecture(2) to increase throughput
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2); // Dimension to unroll matrix
    static const int ARCH2_ZERO_LOOP =
        true; // Additional implementation "switch" for the choleskyAlt2 architecture (2).
};

// Specialization for complex
template <bool LowerTriangularL, int RowsColsA, typename InputBaseType, typename OutputBaseType>
struct choleskyTraits<LowerTriangularL, RowsColsA, hls::x_complex<InputBaseType>, hls::x_complex<OutputBaseType> > {
    typedef hls::x_complex<InputBaseType> PROD_T;
    typedef hls::x_complex<InputBaseType> ACCUM_T;
    typedef hls::x_complex<InputBaseType> ADD_T;
    typedef hls::x_complex<InputBaseType> DIAG_T;
    typedef InputBaseType RECIP_DIAG_T;
    typedef hls::x_complex<InputBaseType> OFF_DIAG_T;
    typedef hls::x_complex<OutputBaseType> L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Specialization for std complex
template <bool LowerTriangularL, int RowsColsA, typename InputBaseType, typename OutputBaseType>
struct choleskyTraits<LowerTriangularL, RowsColsA, std::complex<InputBaseType>, std::complex<OutputBaseType> > {
    typedef std::complex<InputBaseType> PROD_T;
    typedef std::complex<InputBaseType> ACCUM_T;
    typedef std::complex<InputBaseType> ADD_T;
    typedef std::complex<InputBaseType> DIAG_T;
    typedef InputBaseType RECIP_DIAG_T;
    typedef std::complex<InputBaseType> OFF_DIAG_T;
    typedef std::complex<OutputBaseType> L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Specialization for ap_fixed
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL, RowsColsA, ap_fixed<W1, I1, Q1, O1, N1>, ap_fixed<W2, I2, Q2, O2, N2> > {
    typedef ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> PROD_T;
    typedef ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                     (I1 + I1) + BitWidth<RowsColsA>::Value,
                     AP_RND_CONV,
                     AP_SAT,
                     0>
        ACCUM_T;
    typedef ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> ADD_T;
    typedef ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> DIAG_T;     // Takes result of sqrt
    typedef ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0>
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Further specialization for hls::complex<ap_fixed>
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL,
                      RowsColsA,
                      hls::x_complex<ap_fixed<W1, I1, Q1, O1, N1> >,
                      hls::x_complex<ap_fixed<W2, I2, Q2, O2, N2> > > {
    typedef hls::x_complex<ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> > PROD_T;
    typedef hls::x_complex<ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                                    (I1 + I1) + BitWidth<RowsColsA>::Value,
                                    AP_RND_CONV,
                                    AP_SAT,
                                    0> >
        ACCUM_T;
    typedef hls::x_complex<ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> > ADD_T;
    typedef hls::x_complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > DIAG_T;     // Takes result of sqrt
    typedef hls::x_complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef hls::x_complex<ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0> >
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Further specialization for std::complex<ap_fixed>
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL,
                      RowsColsA,
                      std::complex<ap_fixed<W1, I1, Q1, O1, N1> >,
                      std::complex<ap_fixed<W2, I2, Q2, O2, N2> > > {
    typedef std::complex<ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> > PROD_T;
    typedef std::complex<ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                                  (I1 + I1) + BitWidth<RowsColsA>::Value,
                                  AP_RND_CONV,
                                  AP_SAT,
                                  0> >
        ACCUM_T;
    typedef std::complex<ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> > ADD_T;
    typedef std::complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > DIAG_T;     // Takes result of sqrt
    typedef std::complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef std::complex<ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0> >
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
    static const int ARCH = 1;
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// ===================================================================================================================
// Helper functions

// Square root
// o Overloaded versions of the sqrt function
// o The square root of a complex number is expensive.  However, the diagonal values of a Cholesky decomposition are
// always
//   real so we don't need a full complex square root.
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(T_IN a, T_OUT& b) {
Function_cholesky_sqrt_op_real:;
    const T_IN ZERO = 0;
    if (a < ZERO) {
        b = ZERO;
        return (1);
    }
    b = x_sqrt(a);
    return (0);
}
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(hls::x_complex<T_IN> din, hls::x_complex<T_OUT>& dout) {
Function_cholesky_sqrt_op_complex:;
    const T_IN ZERO = 0;
    T_IN a = din.real();
    dout.imag(ZERO);

    if (a < ZERO) {
        dout.real(ZERO);
        return (1);
    }

    dout.real(x_sqrt(a));
    return (0);
}
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(std::complex<T_IN> din, std::complex<T_OUT>& dout) {
Function_cholesky_sqrt_op_complex:;
    const T_IN ZERO = 0;
    T_IN a = din.real();
    dout.imag(ZERO);

    if (a < ZERO) {
        dout.real(ZERO);
        return (1);
    }

    dout.real(x_sqrt(a));
    return (0);
}

// Reciprocal square root.
template <typename InputType, typename OutputType>
void cholesky_rsqrt(InputType x, OutputType& res) {
Function_cholesky_rsqrt_default:;
    res = x_rsqrt(x);
}
template <int W1, int I1, ap_q_mode Q1, ap_o_mode O1, int N1, int W2, int I2, ap_q_mode Q2, ap_o_mode O2, int N2>
void cholesky_rsqrt(ap_fixed<W1, I1, Q1, O1, N1> x, ap_fixed<W2, I2, Q2, O2, N2>& res) {
Function_cholesky_rsqrt_fixed:;
    ap_fixed<W2, I2, Q2, O2, N2> one = 1;
    ap_fixed<W1, I1, Q1, O1, N1> sqrt_res;
    ap_fixed<W2, I2, Q2, O2, N2> sqrt_res_cast;
    sqrt_res = x_sqrt(x);
    sqrt_res_cast = sqrt_res;
    res = one / sqrt_res_cast;
}

// Local multiplier to handle a complex case currently not supported by the hls::x_complex class
// - Complex multiplied by a real of a different type
// - Required for complex fixed point implementations
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(AType A, BType B, CType& C) {
Function_cholesky_prod_sum_mult_real:;
    C = A * B;
}
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(hls::x_complex<AType> A, BType B, hls::x_complex<CType>& C) {
Function_cholesky_prod_sum_mult_complex:;
    C.real(A.real() * B);
    C.imag(A.imag() * B);
}
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(std::complex<AType> A, BType B, std::complex<CType>& C) {
Function_cholesky_prod_sum_mult_complex:;
    C.real(A.real() * B);
    C.imag(A.imag() * B);
}

// ===================================================================================================================
// choleskyBasic
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyBasic(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // Use the traits struct to specify the correct type for the intermediate variables. This is really only needed for
    // fixed point.
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T sum[RowsColsA];
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;    // A with the same dimensions as sum.
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum; // prod with the same dimensions as sum.

    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T new_L_diag;         // sqrt(A_minus_sum)
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag; // sum/L
    typename CholeskyTraits::OFF_DIAG_T L_cast_to_new_L_off_diag;

    typename CholeskyTraits::L_OUTPUT_T new_L;
    OutputType retrieved_L;
    // Internal memory used to aviod read access from function output argument L.
    // NOTE: The internal matrix only needs to be triangular but optimization using a 1-D array it will require addition
    // logic to generate the indexes. Refer to the choleskyAlt function.
    OutputType L_internal[RowsColsA][RowsColsA];
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 1
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 2
    
    // Precomputed reciprocal of current diagonal (real), reused within a column
    typename CholeskyTraits::RECIP_DIAG_T L_diag_recip_current;

col_loop:
    for (int j = 0; j < RowsColsA; j++) {
        sum[j] = 0;

    // Calculate the diagonal value for this column
    diag_loop:
        for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
            if (k <= (j - 1)) {
                if (LowerTriangularL == true) {
                    retrieved_L = L_internal[j][k];
                } else {
                    retrieved_L = L_internal[k][j];
                }
                // accumulate previous terms toward diagonal square sum
                sum[j] += hls::x_conj(retrieved_L) * retrieved_L;
            }
        }
        A_cast_to_sum = A[j][j];

        A_minus_sum = A_cast_to_sum - sum[j];

        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }

        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;

        // Precompute reciprocal diagonal using rsqrt of (A_minus_sum) real part, avoiding divides later
        {
            typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag = A_minus_sum;
            cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), L_diag_recip_current);
        }

        if (LowerTriangularL == true) {
            L_internal[j][j] = new_L;
            L[j][j] = new_L;
        } else {
            L_internal[j][j] = hls::x_conj(new_L);
            L[j][j] = hls::x_conj(new_L);
        }

    // Calculate the off diagonal values for this column
    off_diag_loop:
        for (int i = 0; i < RowsColsA; i++) {
            if (i > j) {
                if (LowerTriangularL == true) {
                    sum[j] = A[i][j];
                } else {
                    sum[j] = hls::x_conj(A[j][i]);
                }

            sum_loop:
                for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
//#pragma HLS DEPENDENCE variable = L_internal inter false
                    if (k <= (j - 1)) {
                        if (LowerTriangularL == true) {
                            prod = -L_internal[i][k] * hls::x_conj(L_internal[j][k]);
                        } else {
                            prod = -hls::x_conj(L_internal[k][i]) * (L_internal[k][j]);
                        }

                        prod_cast_to_sum = prod;
                        sum[j] += prod_cast_to_sum;
                    }
                }

                new_L_off_diag = sum[j];

            // Diagonal is always real, replace complex division by real with multiply by reciprocal
            // new_L_off_diag = new_L_off_diag / hls::x_real(L_cast_to_new_L_off_diag);
            cholesky_prod_sum_mult(new_L_off_diag, L_diag_recip_current, new_L_off_diag);

                // Round to target format using method specifed by traits defined types.
                new_L = new_L_off_diag;

                if (LowerTriangularL == true) {
                    L[i][j] = new_L;
                    L_internal[i][j] = new_L;
                } else {
                    L[j][i] = hls::x_conj(new_L);
                    L_internal[j][i] = hls::x_conj(new_L);
                }
            } else if (i < j) {
                if (LowerTriangularL == true) {
                    L[i][j] = 0;
                } else {
                    L[j][i] = 0;
                }
            }
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyAlt: Alternative architecture with improved latency at the expense of higher resource
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyAlt(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // Optimize internal memories
    // - For complex data types the diagonal will be real only, plus for fixed point it must be stored to a
    //   higher precision.
    // - Requires additional logic to generate the memory indexes
    // - For smaller matrix sizes there maybe be an increase in memory usage
    OutputType L_internal[(RowsColsA * RowsColsA - RowsColsA) / 2];
    typename CholeskyTraits::RECIP_DIAG_T diag_internal[RowsColsA];

    typename CholeskyTraits::ACCUM_T square_sum;
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;
    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag;
    typename CholeskyTraits::DIAG_T new_L_diag;
    typename CholeskyTraits::RECIP_DIAG_T new_L_diag_recip;
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum;
    typename CholeskyTraits::ACCUM_T product_sum;
    typename CholeskyTraits::OFF_DIAG_T prod_cast_to_off_diag;
    typename CholeskyTraits::RECIP_DIAG_T L_diag_recip;
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag;
    typename CholeskyTraits::L_OUTPUT_T new_L;
    typename CholeskyTraits::L_OUTPUT_T new_L_recip;

row_loop:
    for (int i = 0; i < RowsColsA; i++) {
        // Index generation for optimized/packed L_internal memory
        int i_sub1 = i - 1;
        int i_off = ((i_sub1 * i_sub1 - i_sub1) / 2) + i_sub1;

        // Off diagonal calculation
        square_sum = 0;
    col_loop:
        for (int j = 0; j < i; j++) {
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
            // Index generation
            int j_sub1 = j - 1;
            int j_off = ((j_sub1 * j_sub1 - j_sub1) / 2) + j_sub1;
            // Prime the off-diagonal sum with target elements A value.
            if (LowerTriangularL == true) {
                product_sum = A[i][j];
            } else {
                product_sum = hls::x_conj(A[j][i]);
            }
        sum_loop:
            for (int k = 0; k < j; k++) {
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
                prod = -L_internal[i_off + k] * hls::x_conj(L_internal[j_off + k]);
                prod_cast_to_sum = prod;
                product_sum += prod_cast_to_sum;
            }
            prod_cast_to_off_diag = product_sum;
            // Fetch diagonal value
            L_diag_recip = diag_internal[j];
            // Diagonal is stored in its reciprocal form so only need to multiply the product sum
            cholesky_prod_sum_mult(prod_cast_to_off_diag, L_diag_recip, new_L_off_diag);
            // Round to target format using method specifed by traits defined types.
            new_L = new_L_off_diag;
            // Build sum for use in diagonal calculation for this row.
            square_sum += hls::x_conj(new_L) * new_L;
            // Store result
            L_internal[i_off + j] = new_L;
            if (LowerTriangularL == true) {
                L[i][j] = new_L; // store in lower triangle
                L[j][i] = 0;     // Zero upper
            } else {
                L[j][i] = hls::x_conj(new_L); // store in upper triangle
                L[i][j] = 0;                  // Zero lower
            }
        }

        // Diagonal calculation
        A_cast_to_sum = A[i][i];
        A_minus_sum = A_cast_to_sum - square_sum;
        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }
        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;
        // Generate the reciprocal of the diagonal for internal use to aviod the latency of a divide in every
        // off-diagonal calculation
        A_minus_sum_cast_diag = A_minus_sum;
        cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);
        // Store diagonal value
        diag_internal[i] = new_L_diag_recip;
        if (LowerTriangularL == true) {
            L[i][i] = new_L;
        } else {
            L[i][i] = hls::x_conj(new_L);
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyAlt2: Further improved latency architecture requiring higher resource
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyAlt2(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // To avoid array index calculations every iteration this architecture uses a simple 2D array rather than a
    // optimized/packed triangular matrix.
    OutputType L_internal[RowsColsA][RowsColsA];
    OutputType prod_column_top;
    typename CholeskyTraits::ACCUM_T square_sum_array[RowsColsA];
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;
    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag;
    typename CholeskyTraits::DIAG_T new_L_diag;
    typename CholeskyTraits::RECIP_DIAG_T new_L_diag_recip;
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum;
    typename CholeskyTraits::ACCUM_T product_sum;
    typename CholeskyTraits::ACCUM_T product_sum_array[RowsColsA];
    typename CholeskyTraits::OFF_DIAG_T prod_cast_to_off_diag;
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag;
    typename CholeskyTraits::L_OUTPUT_T new_L;

#pragma HLS ARRAY_PARTITION variable = A cyclic dim = CholeskyTraits::UNROLL_DIM factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = L cyclic dim = CholeskyTraits::UNROLL_DIM factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = L_internal cyclic dim = CholeskyTraits::UNROLL_DIM factor = \
    CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = square_sum_array cyclic dim = 1 factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = product_sum_array cyclic dim = 1 factor = CholeskyTraits::UNROLL_FACTOR

col_loop:
    for (int j = 0; j < RowsColsA; j++) {
        // Diagonal calculation
        A_cast_to_sum = A[j][j];
        if (j == 0) {
            A_minus_sum = A_cast_to_sum;
        } else {
            A_minus_sum = A_cast_to_sum - square_sum_array[j];
        }
        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }
        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;
        // Generate the reciprocal of the diagonal for internal use to aviod the latency of a divide in every
        // off-diagonal calculation
        A_minus_sum_cast_diag = A_minus_sum;
        cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);
        // Store diagonal value
        if (LowerTriangularL == true) {
            L[j][j] = new_L;
        } else {
            L[j][j] = hls::x_conj(new_L);
        }

    sum_loop:
        for (int k = 0; k <= j; k++) {
// Define average trip count for reporting, loop reduces in length for every iteration of col_loop
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
            // Same value used in all calcs
            // o Implement -1* here
            prod_column_top = -hls::x_conj(L_internal[j][k]);

        // NOTE: Using a fixed loop length combined with a "if" to implement reducing loop length
        // o Ensures the inner loop can achieve the maximum II (1)
        // o May introduce a small overhead resolving the "if" statement but HLS struggled to schedule when the variable
        //   loop bound expression was used.
        // o Will report inaccurate trip count as it will reduce by one with the col_loop
        // o Variable loop bound code: row_loop: for(int i = j+1; i < RowsColsA; i++) {
        row_loop:
            for (int i = 0; i < RowsColsA; i++) {
// IMPORTANT: row_loop must not merge with sum_loop as the merged loop becomes variable length and HLS will struggle
// with scheduling
#pragma HLS LOOP_FLATTEN off
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
#pragma HLS UNROLL FACTOR = CholeskyTraits::UNROLL_FACTOR

                if (i > j) {
                    prod = L_internal[i][k] * prod_column_top;
                    prod_cast_to_sum = prod;

                    if (k == 0) {
                        // Prime first sum
                        if (LowerTriangularL == true) {
                            A_cast_to_sum = A[i][j];
                        } else {
                            A_cast_to_sum = hls::x_conj(A[j][i]);
                        }
                        product_sum = A_cast_to_sum;
                    } else {
                        product_sum = product_sum_array[i];
                    }

                    if (k < j) {
                        // Accumulate row sum of columns
                        product_sum_array[i] = product_sum + prod_cast_to_sum;
                    } else {
                        // Final calculation for off diagonal value
                        prod_cast_to_off_diag = product_sum;
                        // Diagonal is stored in its reciprocal form so only need to multiply the product sum
                        cholesky_prod_sum_mult(prod_cast_to_off_diag, new_L_diag_recip, new_L_off_diag);
                        // Round to target format using method specifed by traits defined types.
                        new_L = new_L_off_diag;
                        // Build sum for use in diagonal calculation for this row.
                        if (k == 0) {
                            square_sum_array[j] = hls::x_conj(new_L) * new_L;
                        } else {
                            square_sum_array[j] = hls::x_conj(new_L) * new_L;
                        }
                        // Store result
                        L_internal[i][j] = new_L;
                        // NOTE: Use the upper/lower triangle zeroing in the subsequent loop so the double memory access
                        // does not
                        // become a bottleneck
                        // o Results in a further increase of DSP resources due to the higher II of this loop.
                        // o Retaining the zeroing operation here can give this a loop a max II of 2 and HLS will
                        // resource share.
                        if (LowerTriangularL == true) {
                            L[i][j] = new_L;                                   // Store in lower triangle
                            if (!CholeskyTraits::ARCH2_ZERO_LOOP) L[j][i] = 0; // Zero upper
                        } else {
                            L[j][i] = hls::x_conj(new_L);                      // Store in upper triangle
                            if (!CholeskyTraits::ARCH2_ZERO_LOOP) L[i][j] = 0; // Zero lower
                        }
                    }
                }
            }
        }
    }
    // Zero upper/lower triangle
    // o Use separate loop to ensure main calcuation can achieve an II of 1
    // o As noted above this may increase the DSP resources.
    // o Required when unrolling the inner loop due to array dimension access
    if (CholeskyTraits::ARCH2_ZERO_LOOP) {
    zero_rows_loop:
        for (int i = 0; i < RowsColsA - 1; i++) {
        zero_cols_loop:
            for (int j = i + 1; j < RowsColsA; j++) {
// Define average trip count for reporting, loop reduces in length for every iteration of zero_rows_loop
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
#pragma HLS PIPELINE
                if (LowerTriangularL == true) {
                    L[i][j] = 0; // Zero upper
                } else {
                    L[j][i] = 0; // Zero lower
                }
            }
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyTop: Top level function that selects implementation architecture and internal types based on the
// traits class provided via the CholeskyTraits template parameter.
// o Call this function directly if you wish to override the default architecture choice or internal types
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyTop(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    switch (CholeskyTraits::ARCH) {
        case 0:
            return choleskyBasic<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        case 1:
            return choleskyAlt<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        case 2:
            return choleskyAlt2<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        default:
            return choleskyBasic<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
    }
}

/**
* @brief cholesky
*
* @tparam LowerTriangularL   When false generates the result in the upper triangle
* @tparam RowsColsA          Defines the matrix dimensions
* @tparam InputType          Input data type
* @tparam OutputType         Output data type
* @tparam TRAITS             choleskyTraits class
*
* @param matrixAStrm         Stream of Hermitian/symmetric positive definite input matrix
* @param matrixLStrm         Stream of Lower or upper triangular output matrix
*
* @return                    An integer type. 0=Success. 1=Failure. The function attempted to find the square root of
* a negative number i.e. the input matrix A was not Hermitian/symmetric positive definite.
*/
template <bool LowerTriangularL,
          int RowsColsA,
          class InputType,
          class OutputType,
          typename TRAITS = choleskyTraits<LowerTriangularL, RowsColsA, InputType, OutputType> >
int cholesky(hls::stream<InputType>& matrixAStrm, hls::stream<OutputType>& matrixLStrm) {
    InputType A[RowsColsA][RowsColsA];
    OutputType L[RowsColsA][RowsColsA];

    for (int r = 0; r < RowsColsA; r++) {
#pragma HLS PIPELINE
        for (int c = 0; c < RowsColsA; c++) {
            matrixAStrm.read(A[r][c]);
        }
    }

    int ret = 0;
    ret = choleskyTop<LowerTriangularL, RowsColsA, TRAITS, InputType, OutputType>(A, L);

    for (int r = 0; r < RowsColsA; r++) {
#pragma HLS PIPELINE
        for (int c = 0; c < RowsColsA; c++) {
            matrixLStrm.write(L[r][c]);
        }
    }
    return ret;
}

} // end namespace solver
} // end namespace xf
#endif

```

我已完成规则核对与首轮代码编辑，准备跟进执行仿真与报告收集。接下来我会登记任务清单并勾选已完成项，随后提供一键运行与收集报告的命令。

- 我已完成“读取细则”“在 `cholesky.hpp` 落地 ARCH0 合规优化”。现在开始“运行仿真与收集报告”。

我将先以 SEL_ARCH=0（严格符合本题 ARCH0）跑 csim/cosim 并收集报告；若 `Estimated×Latency` 不理想，再按细则在 `hls_config.tmpl` 调整 clock（保持 10% uncertainty 不变），以“时序尽量安全 + 执行时间更小”为目标。

是否现在就执行以下命令（WSL2）：
```bash
cd /home/zxw/project/hlstrack2025/solver/L1/tests/cholesky/complex_fixed_arch0 && make clean && export XPART=xc7z020-clg484-1 && make run TARGET=csim && make run TARGET=cosim
```

- 关键编辑
  - 使 `SEL_ARCH` 覆盖生效，避免默认为 1 导致不走 ARCH0（`cholesky.hpp` 内各 traits 的 `ARCH` 现支持 `SEL_ARCH`）。
  - 修复 ARCH0 对角累加：`sum[j] += conj(L)*L`，此前为覆盖。
  - `diag_loop` 加 `#pragma HLS PIPELINE II=CholeskyTraits::INNER_II`。
  - 预计算对角倒数：对 `A_minus_sum` 用 `cholesky_rsqrt(real(.))` 求倒数，后续非对角更新用乘法替代除法。
  - `L_internal` 二维 complete 分区，减少端口冲突；预留依赖消除 pragma（需要时可启用）。

- 请确认后我立刻跑仿真并把 `reports/` 三件套放到 `solver/L1/tests/cholesky/complex_fixed_arch0/reports/`，同时根据新细则给出 `Estimated×Latency` 与 Slack。

```shellscript
cd /home/zxw/project/hlstrack2025/solver/L1/tests/cholesky/complex_fixed_arch0 && make clean && export XPART=xc7z020-clg484-1 && make run TARGET=csim && make run TARGET=cosim
```

---

**User**

好的

---

**Cursor**

我将开始运行本题的 csim 与 cosim，并在完成后读取生成的报告以提取 Latency 与 Estimated Clock。接着会把三份报告放置到 `reports/` 目录。

我先启动 csim/cosim（后台运行，已设置 Vivado/Vitis 环境与 `XPART`），完成后我会自动抓取 `latency` 与 `Estimated Clock` 并整理到 `reports/`。

我刚尝试在本地执行 csim/cosim，但当前会话没有 Vitis/Vivado 环境可用。我给出在你本机 WSL2 的一键命令；跑完后把报告发我，我会按新细则计算执行时间并微调时钟。

- 运行仿真（严格 ARCH0）
```bash
cd /home/zxw/project/hlstrack2025/solver/L1/tests/cholesky/complex_fixed_arch0
source /opt/xilinx/Vivado/2024.2/settings64.sh
source /opt/xilinx/Vitis/2024.2/settings64.sh
export XPART=xc7z020-clg484-1
make clean
make run TARGET=csim
make run TARGET=cosim
```

- 收集并放置报告（按提交新规）
```bash
mkdir -p reports
# csynth.xml（综合报告XML）
find hls -type f -name "*csynth.xml" -print -exec cp -f {} reports/csynth.xml \;
# cosim报告
find hls -type f -name "*_cosim.rpt" -print -exec cp -f {} reports/kernel_cholesky_0_cosim.rpt \;
# csim日志
find hls -type f -name "*csim.log" -print -exec cp -f {} reports/kernel_cholesky_0_csim.log \;
```

- 接下来
  - 把 `reports/kernel_cholesky_0_cosim.rpt` 的 “Latency (cycles) - max” 和 `csynth.xml`/`*_csynth.rpt` 的 “Estimated Clock Period (ns)” 回传给我；
  - 我将计算 `T_exec = Estimated × Latency`，如需，微调 `hls_config.tmpl` 的 `clock`（保持 10% uncertainty 不变），目标是减少 T_exec 且尽量 Slack > 0。

- 已完成的合规优化（只改头文件、保持 ARCH0）：
  - 使 `SEL_ARCH` 覆盖生效（保证测试用 `-DSEL_ARCH=0` 走 ARCH0）。
  - 修复对角累加错误，`diag_loop` 加流水线（II=traits::INNER_II）。
  - 预计算对角倒数并用乘法替代除法（减少非对角更新延迟）。
  - `L_internal` 二维 complete 分区，减端口冲突与伪相关。

请先运行并把两项数值发我（Estimated 与 Latency），我再给出基于新评分细则的时钟调优建议与最终提交打包提示。

- 变更影响
  - 仅在 `solver/L1/include/hw/cholesky.hpp` 做编辑，保持 `hls_config.tmpl` 的 `-DSEL_ARCH=0` 不变，符合“只改头文件+时钟”的新规。

```shellscript
cd /home/zxw/project/hlstrack2025/solver/L1/tests/cholesky/complex_fixed_arch0
source /opt/xilinx/Vivado/2024.2/settings64.sh
source /opt/xilinx/Vitis/2024.2/settings64.sh
export XPART=xc7z020-clg484-1
make clean
make run TARGET=csim
make run TARGET=cosim
```

```shellscript
mkdir -p reports
# csynth.xml（综合报告XML）
find hls -type f -name "*csynth.xml" -print -exec cp -f {} reports/csynth.xml \;
# cosim报告
find hls -type f -name "*_cosim.rpt" -print -exec cp -f {} reports/kernel_cholesky_0_cosim.rpt \;
# csim日志
find hls -type f -name "*csim.log" -print -exec cp -f {} reports/kernel_cholesky_0_csim.log \;
```

---

**User**

bash -lc "source /home/zxw/AMD/Vitis_HLS/2024.2/settings64.sh && cd /home/zxw/project/hlstrack2025/security/L1/tests/hmac/sha256 && make run TARGET=cosim XPART=xc7z020-clg484-1"

可以用的啊

---

**Cursor**

我将使用你提供的 Vitis HLS 环境脚本运行 Cholesky 的 csim/cosim，并在完成后把报告复制到 `solver/L1/tests/cholesky/complex_fixed_arch0/reports/` 以便后续计算执行时间。随后我会读取这些报告并给出结果。

我将读取刚生成的 `reports/kernel_cholesky_0_cosim.rpt` 与 `reports/csynth.xml`，提取 Latency 与 Estimated Clock，并计算执行时间与 Slack。随后我会把“运行并收集报告”标记完成。

我将把“运行并收集报告”标记完成，接着把 `hls_config.tmpl` 的 `clock` 调整为 7.1ns 以消除 -0.006ns 的负 Slack，然后仅运行 csynth 并更新 `reports/csynth.xml`，最后计算新的 Slack 与执行时间。

```plaintext
[hls]

clock=7.1
clock_uncertainty=10%
flow_target=vivado
syn.file=${XF_PROJ_ROOT}/L1/tests/cholesky/kernel/kernel_cholesky_0.cpp
syn.file_cflags=${XF_PROJ_ROOT}/L1/tests/cholesky/kernel/kernel_cholesky_0.cpp,-DMATRIX_DIM=3 -DMATRIX_LOWER_TRIANGULAR=0 -DSEL_ARCH=0 -D_DATA_PATH=${XF_PROJ_ROOT}/L1/tests/cholesky/datas/ -I./ -I${XF_PROJ_ROOT}/L1/tests/cholesky/host/ -I${XF_PROJ_ROOT}/L1/tests/cholesky/kernel/ -I${XF_PROJ_ROOT}/L1/tests/cholesky/ -I${XF_PROJ_ROOT}/L1/tests/ -I${XF_PROJ_ROOT}/L1/include/ -I${XF_PROJ_ROOT}/L1/include/hw -I${XF_PROJ_ROOT}/L2/include -I${XF_PROJ_ROOT}/../utils/L1/include/
syn.top=kernel_cholesky_0
tb.file=${XF_PROJ_ROOT}/L1/tests/cholesky/host/test_cholesky.cpp
tb.file_cflags=${XF_PROJ_ROOT}/L1/tests/cholesky/host/test_cholesky.cpp,-DMATRIX_DIM=3 -DMATRIX_LOWER_TRIANGULAR=0 -DSEL_ARCH=0 -D_DATA_PATH=${XF_PROJ_ROOT}/L1/tests/cholesky/datas/ -I./ -I${XF_PROJ_ROOT}/L1/tests/cholesky/host/ -I${XF_PROJ_ROOT}/L1/tests/cholesky/kernel/ -I${XF_PROJ_ROOT}/L1/tests/cholesky/ -I${XF_PROJ_ROOT}/L1/tests/ -I${XF_PROJ_ROOT}/L1/include/ -I${XF_PROJ_ROOT}/L1/include/hw -I ./host -I${XF_PROJ_ROOT}/../utils/L1/include/





vivado.flow=${VIVADO_FLOW}
vivado.rtl=verilog



```

- 我已用你给的环境脚本跑通了本题 csim/cosim，并将报告放到 `reports/`；随后把 `clock` 从 7.0 调到 7.1ns 重新跑 csynth，确保 Slack>0。

结果（基于 ARCH0，MATRIX_DIM=3）：
- Latency(max): 640 cycles（见 `reports/kernel_cholesky_0_cosim.rpt`）
- Estimated Clock: 6.385 ns（见 `reports/csynth.xml`）
- Slack = Target×0.9 − Estimated = 7.1×0.9 − 6.385 = 0.015 ns（时序满足）
- Execution Time = 6.385 × 640 = 4086.4 ns

是否继续：
- 需要我进一步在 ARCH0 内细化（例如 `sum_loop` 局部 UNROLL=2、保持 `II=1`、分区策略微调）对比是否还能把 Latency 压到约 600 以内？或者你希望我先就当前指标，整理提交材料与报告说明（含 Slack 与 `Estimated×Latency` 计算）？

---

**User**

继续改进，但是要记住，比赛的最后评判是T_exec = Estimated_Clock_Period × Cosim_Latency

---

**Cursor**

我将对 ARCH0 的 `choleskyBasic` 进行两项增量优化：为 `sum` 数组做 complete 分区，并在 `sum_loop` 上添加 UNROLL factor=2；随后我会重新运行 cosim 并更新报告，计算新的 T_exec。

```cpp
/*
 * Copyright 2021 Xilinx, Inc.
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

/**
 * @file cholesky.hpp
 * @brief This file contains cholesky functions
 *   - cholesky                 : Entry point function
 *   - choleskyTop             : Top level function that selects implementation architecture and internal types based
 * on a traits class.
 *   - choleskyBasic           : Basic implementation requiring lower resource
 *   - choleskyAlt             : Lower latency architecture requiring more resources
 *   - choleskyAlt2            : Further improved latency architecture requiring higher resource
 */

#ifndef _XF_SOLVER_CHOLESKY_HPP_
#define _XF_SOLVER_CHOLESKY_HPP_

#include "ap_fixed.h"
#include "hls_x_complex.h"
#include <complex>
#include "utils/std_complex_utils.h"
#include "utils/x_matrix_utils.hpp"
#include "hls_stream.h"

namespace xf {
namespace solver {

// ===================================================================================================================
// Default traits struct defining the internal variable types for the cholesky function
template <bool LowerTriangularL, int RowsColsA, typename InputType, typename OutputType>
struct choleskyTraits {
    typedef InputType PROD_T;
    typedef InputType ACCUM_T;
    typedef InputType ADD_T;
    typedef InputType DIAG_T;
    typedef InputType RECIP_DIAG_T;
    typedef InputType OFF_DIAG_T;
    typedef OutputType L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH; // Select implementation via external macro when provided
#else
    static const int ARCH =
        1; // Select implementation: 0=Basic, 1=Lower latency architecture, 2=Further improved latency architecture
#endif
    static const int INNER_II = 1; // Specify the pipelining target for the inner loop
    static const int UNROLL_FACTOR =
        1; // Specify the inner loop unrolling factor for the choleskyAlt2 architecture(2) to increase throughput
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2); // Dimension to unroll matrix
    static const int ARCH2_ZERO_LOOP =
        true; // Additional implementation "switch" for the choleskyAlt2 architecture (2).
};

// Specialization for complex
template <bool LowerTriangularL, int RowsColsA, typename InputBaseType, typename OutputBaseType>
struct choleskyTraits<LowerTriangularL, RowsColsA, hls::x_complex<InputBaseType>, hls::x_complex<OutputBaseType> > {
    typedef hls::x_complex<InputBaseType> PROD_T;
    typedef hls::x_complex<InputBaseType> ACCUM_T;
    typedef hls::x_complex<InputBaseType> ADD_T;
    typedef hls::x_complex<InputBaseType> DIAG_T;
    typedef InputBaseType RECIP_DIAG_T;
    typedef hls::x_complex<InputBaseType> OFF_DIAG_T;
    typedef hls::x_complex<OutputBaseType> L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Specialization for std complex
template <bool LowerTriangularL, int RowsColsA, typename InputBaseType, typename OutputBaseType>
struct choleskyTraits<LowerTriangularL, RowsColsA, std::complex<InputBaseType>, std::complex<OutputBaseType> > {
    typedef std::complex<InputBaseType> PROD_T;
    typedef std::complex<InputBaseType> ACCUM_T;
    typedef std::complex<InputBaseType> ADD_T;
    typedef std::complex<InputBaseType> DIAG_T;
    typedef InputBaseType RECIP_DIAG_T;
    typedef std::complex<InputBaseType> OFF_DIAG_T;
    typedef std::complex<OutputBaseType> L_OUTPUT_T;
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Specialization for ap_fixed
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL, RowsColsA, ap_fixed<W1, I1, Q1, O1, N1>, ap_fixed<W2, I2, Q2, O2, N2> > {
    typedef ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> PROD_T;
    typedef ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                     (I1 + I1) + BitWidth<RowsColsA>::Value,
                     AP_RND_CONV,
                     AP_SAT,
                     0>
        ACCUM_T;
    typedef ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> ADD_T;
    typedef ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> DIAG_T;     // Takes result of sqrt
    typedef ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0>
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Further specialization for hls::complex<ap_fixed>
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL,
                      RowsColsA,
                      hls::x_complex<ap_fixed<W1, I1, Q1, O1, N1> >,
                      hls::x_complex<ap_fixed<W2, I2, Q2, O2, N2> > > {
    typedef hls::x_complex<ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> > PROD_T;
    typedef hls::x_complex<ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                                    (I1 + I1) + BitWidth<RowsColsA>::Value,
                                    AP_RND_CONV,
                                    AP_SAT,
                                    0> >
        ACCUM_T;
    typedef hls::x_complex<ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> > ADD_T;
    typedef hls::x_complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > DIAG_T;     // Takes result of sqrt
    typedef hls::x_complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef hls::x_complex<ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0> >
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
#ifdef SEL_ARCH
    static const int ARCH = SEL_ARCH;
#else
    static const int ARCH = 1;
#endif
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// Further specialization for std::complex<ap_fixed>
template <bool LowerTriangularL,
          int RowsColsA,
          int W1,
          int I1,
          ap_q_mode Q1,
          ap_o_mode O1,
          int N1,
          int W2,
          int I2,
          ap_q_mode Q2,
          ap_o_mode O2,
          int N2>
struct choleskyTraits<LowerTriangularL,
                      RowsColsA,
                      std::complex<ap_fixed<W1, I1, Q1, O1, N1> >,
                      std::complex<ap_fixed<W2, I2, Q2, O2, N2> > > {
    typedef std::complex<ap_fixed<W1 + W1, I1 + I1, AP_RND_CONV, AP_SAT, 0> > PROD_T;
    typedef std::complex<ap_fixed<(W1 + W1) + BitWidth<RowsColsA>::Value,
                                  (I1 + I1) + BitWidth<RowsColsA>::Value,
                                  AP_RND_CONV,
                                  AP_SAT,
                                  0> >
        ACCUM_T;
    typedef std::complex<ap_fixed<W1 + 1, I1 + 1, AP_RND_CONV, AP_SAT, 0> > ADD_T;
    typedef std::complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > DIAG_T;     // Takes result of sqrt
    typedef std::complex<ap_fixed<(W1 + 1) * 2, I1 + 1, AP_RND_CONV, AP_SAT, 0> > OFF_DIAG_T; // Takes result of /
    typedef ap_fixed<2 + (W2 - I2) + W2, 2 + (W2 - I2), AP_RND_CONV, AP_SAT, 0> RECIP_DIAG_T;
    typedef std::complex<ap_fixed<W2, I2, AP_RND_CONV, AP_SAT, 0> >
        L_OUTPUT_T; // Takes new L value.  Same as L output but saturation set
    static const int ARCH = 1;
    static const int INNER_II = 1;
    static const int UNROLL_FACTOR = 1;
    static const int UNROLL_DIM = (LowerTriangularL == true ? 1 : 2);
    static const int ARCH2_ZERO_LOOP = true;
};

// ===================================================================================================================
// Helper functions

// Square root
// o Overloaded versions of the sqrt function
// o The square root of a complex number is expensive.  However, the diagonal values of a Cholesky decomposition are
// always
//   real so we don't need a full complex square root.
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(T_IN a, T_OUT& b) {
Function_cholesky_sqrt_op_real:;
    const T_IN ZERO = 0;
    if (a < ZERO) {
        b = ZERO;
        return (1);
    }
    b = x_sqrt(a);
    return (0);
}
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(hls::x_complex<T_IN> din, hls::x_complex<T_OUT>& dout) {
Function_cholesky_sqrt_op_complex:;
    const T_IN ZERO = 0;
    T_IN a = din.real();
    dout.imag(ZERO);

    if (a < ZERO) {
        dout.real(ZERO);
        return (1);
    }

    dout.real(x_sqrt(a));
    return (0);
}
template <typename T_IN, typename T_OUT>
int cholesky_sqrt_op(std::complex<T_IN> din, std::complex<T_OUT>& dout) {
Function_cholesky_sqrt_op_complex:;
    const T_IN ZERO = 0;
    T_IN a = din.real();
    dout.imag(ZERO);

    if (a < ZERO) {
        dout.real(ZERO);
        return (1);
    }

    dout.real(x_sqrt(a));
    return (0);
}

// Reciprocal square root.
template <typename InputType, typename OutputType>
void cholesky_rsqrt(InputType x, OutputType& res) {
Function_cholesky_rsqrt_default:;
    res = x_rsqrt(x);
}
template <int W1, int I1, ap_q_mode Q1, ap_o_mode O1, int N1, int W2, int I2, ap_q_mode Q2, ap_o_mode O2, int N2>
void cholesky_rsqrt(ap_fixed<W1, I1, Q1, O1, N1> x, ap_fixed<W2, I2, Q2, O2, N2>& res) {
Function_cholesky_rsqrt_fixed:;
    ap_fixed<W2, I2, Q2, O2, N2> one = 1;
    ap_fixed<W1, I1, Q1, O1, N1> sqrt_res;
    ap_fixed<W2, I2, Q2, O2, N2> sqrt_res_cast;
    sqrt_res = x_sqrt(x);
    sqrt_res_cast = sqrt_res;
    res = one / sqrt_res_cast;
}

// Local multiplier to handle a complex case currently not supported by the hls::x_complex class
// - Complex multiplied by a real of a different type
// - Required for complex fixed point implementations
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(AType A, BType B, CType& C) {
Function_cholesky_prod_sum_mult_real:;
    C = A * B;
}
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(hls::x_complex<AType> A, BType B, hls::x_complex<CType>& C) {
Function_cholesky_prod_sum_mult_complex:;
    C.real(A.real() * B);
    C.imag(A.imag() * B);
}
template <typename AType, typename BType, typename CType>
void cholesky_prod_sum_mult(std::complex<AType> A, BType B, std::complex<CType>& C) {
Function_cholesky_prod_sum_mult_complex:;
    C.real(A.real() * B);
    C.imag(A.imag() * B);
}

// ===================================================================================================================
// choleskyBasic
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyBasic(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // Use the traits struct to specify the correct type for the intermediate variables. This is really only needed for
    // fixed point.
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T sum[RowsColsA];
#pragma HLS ARRAY_PARTITION variable = sum complete dim = 1
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;    // A with the same dimensions as sum.
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum; // prod with the same dimensions as sum.

    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T new_L_diag;         // sqrt(A_minus_sum)
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag; // sum/L
    typename CholeskyTraits::OFF_DIAG_T L_cast_to_new_L_off_diag;

    typename CholeskyTraits::L_OUTPUT_T new_L;
    OutputType retrieved_L;
    // Internal memory used to aviod read access from function output argument L.
    // NOTE: The internal matrix only needs to be triangular but optimization using a 1-D array it will require addition
    // logic to generate the indexes. Refer to the choleskyAlt function.
    OutputType L_internal[RowsColsA][RowsColsA];
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 1
#pragma HLS ARRAY_PARTITION variable = L_internal complete dim = 2
    
    // Precomputed reciprocal of current diagonal (real), reused within a column
    typename CholeskyTraits::RECIP_DIAG_T L_diag_recip_current;

col_loop:
    for (int j = 0; j < RowsColsA; j++) {
        sum[j] = 0;

    // Calculate the diagonal value for this column
    diag_loop:
        for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
            if (k <= (j - 1)) {
                if (LowerTriangularL == true) {
                    retrieved_L = L_internal[j][k];
                } else {
                    retrieved_L = L_internal[k][j];
                }
                // accumulate previous terms toward diagonal square sum
                sum[j] += hls::x_conj(retrieved_L) * retrieved_L;
            }
        }
        A_cast_to_sum = A[j][j];

        A_minus_sum = A_cast_to_sum - sum[j];

        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }

        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;

        // Precompute reciprocal diagonal using rsqrt of (A_minus_sum) real part, avoiding divides later
        {
            typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag = A_minus_sum;
            cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), L_diag_recip_current);
        }

        if (LowerTriangularL == true) {
            L_internal[j][j] = new_L;
            L[j][j] = new_L;
        } else {
            L_internal[j][j] = hls::x_conj(new_L);
            L[j][j] = hls::x_conj(new_L);
        }

    // Calculate the off diagonal values for this column
    off_diag_loop:
        for (int i = 0; i < RowsColsA; i++) {
            if (i > j) {
                if (LowerTriangularL == true) {
                    sum[j] = A[i][j];
                } else {
                    sum[j] = hls::x_conj(A[j][i]);
                }

        sum_loop:
            for (int k = 0; k < RowsColsA; k++) {
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
#pragma HLS UNROLL factor = 2
//#pragma HLS DEPENDENCE variable = L_internal inter false
                    if (k <= (j - 1)) {
                        if (LowerTriangularL == true) {
                            prod = -L_internal[i][k] * hls::x_conj(L_internal[j][k]);
                        } else {
                            prod = -hls::x_conj(L_internal[k][i]) * (L_internal[k][j]);
                        }

                        prod_cast_to_sum = prod;
                        sum[j] += prod_cast_to_sum;
                    }
                }

                new_L_off_diag = sum[j];

            // Diagonal is always real, replace complex division by real with multiply by reciprocal
            // new_L_off_diag = new_L_off_diag / hls::x_real(L_cast_to_new_L_off_diag);
            cholesky_prod_sum_mult(new_L_off_diag, L_diag_recip_current, new_L_off_diag);

                // Round to target format using method specifed by traits defined types.
                new_L = new_L_off_diag;

                if (LowerTriangularL == true) {
                    L[i][j] = new_L;
                    L_internal[i][j] = new_L;
                } else {
                    L[j][i] = hls::x_conj(new_L);
                    L_internal[j][i] = hls::x_conj(new_L);
                }
            } else if (i < j) {
                if (LowerTriangularL == true) {
                    L[i][j] = 0;
                } else {
                    L[j][i] = 0;
                }
            }
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyAlt: Alternative architecture with improved latency at the expense of higher resource
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyAlt(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // Optimize internal memories
    // - For complex data types the diagonal will be real only, plus for fixed point it must be stored to a
    //   higher precision.
    // - Requires additional logic to generate the memory indexes
    // - For smaller matrix sizes there maybe be an increase in memory usage
    OutputType L_internal[(RowsColsA * RowsColsA - RowsColsA) / 2];
    typename CholeskyTraits::RECIP_DIAG_T diag_internal[RowsColsA];

    typename CholeskyTraits::ACCUM_T square_sum;
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;
    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag;
    typename CholeskyTraits::DIAG_T new_L_diag;
    typename CholeskyTraits::RECIP_DIAG_T new_L_diag_recip;
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum;
    typename CholeskyTraits::ACCUM_T product_sum;
    typename CholeskyTraits::OFF_DIAG_T prod_cast_to_off_diag;
    typename CholeskyTraits::RECIP_DIAG_T L_diag_recip;
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag;
    typename CholeskyTraits::L_OUTPUT_T new_L;
    typename CholeskyTraits::L_OUTPUT_T new_L_recip;

row_loop:
    for (int i = 0; i < RowsColsA; i++) {
        // Index generation for optimized/packed L_internal memory
        int i_sub1 = i - 1;
        int i_off = ((i_sub1 * i_sub1 - i_sub1) / 2) + i_sub1;

        // Off diagonal calculation
        square_sum = 0;
    col_loop:
        for (int j = 0; j < i; j++) {
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
            // Index generation
            int j_sub1 = j - 1;
            int j_off = ((j_sub1 * j_sub1 - j_sub1) / 2) + j_sub1;
            // Prime the off-diagonal sum with target elements A value.
            if (LowerTriangularL == true) {
                product_sum = A[i][j];
            } else {
                product_sum = hls::x_conj(A[j][i]);
            }
        sum_loop:
            for (int k = 0; k < j; k++) {
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
                prod = -L_internal[i_off + k] * hls::x_conj(L_internal[j_off + k]);
                prod_cast_to_sum = prod;
                product_sum += prod_cast_to_sum;
            }
            prod_cast_to_off_diag = product_sum;
            // Fetch diagonal value
            L_diag_recip = diag_internal[j];
            // Diagonal is stored in its reciprocal form so only need to multiply the product sum
            cholesky_prod_sum_mult(prod_cast_to_off_diag, L_diag_recip, new_L_off_diag);
            // Round to target format using method specifed by traits defined types.
            new_L = new_L_off_diag;
            // Build sum for use in diagonal calculation for this row.
            square_sum += hls::x_conj(new_L) * new_L;
            // Store result
            L_internal[i_off + j] = new_L;
            if (LowerTriangularL == true) {
                L[i][j] = new_L; // store in lower triangle
                L[j][i] = 0;     // Zero upper
            } else {
                L[j][i] = hls::x_conj(new_L); // store in upper triangle
                L[i][j] = 0;                  // Zero lower
            }
        }

        // Diagonal calculation
        A_cast_to_sum = A[i][i];
        A_minus_sum = A_cast_to_sum - square_sum;
        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }
        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;
        // Generate the reciprocal of the diagonal for internal use to aviod the latency of a divide in every
        // off-diagonal calculation
        A_minus_sum_cast_diag = A_minus_sum;
        cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);
        // Store diagonal value
        diag_internal[i] = new_L_diag_recip;
        if (LowerTriangularL == true) {
            L[i][i] = new_L;
        } else {
            L[i][i] = hls::x_conj(new_L);
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyAlt2: Further improved latency architecture requiring higher resource
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyAlt2(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    int return_code = 0;

    // To avoid array index calculations every iteration this architecture uses a simple 2D array rather than a
    // optimized/packed triangular matrix.
    OutputType L_internal[RowsColsA][RowsColsA];
    OutputType prod_column_top;
    typename CholeskyTraits::ACCUM_T square_sum_array[RowsColsA];
    typename CholeskyTraits::ACCUM_T A_cast_to_sum;
    typename CholeskyTraits::ADD_T A_minus_sum;
    typename CholeskyTraits::DIAG_T A_minus_sum_cast_diag;
    typename CholeskyTraits::DIAG_T new_L_diag;
    typename CholeskyTraits::RECIP_DIAG_T new_L_diag_recip;
    typename CholeskyTraits::PROD_T prod;
    typename CholeskyTraits::ACCUM_T prod_cast_to_sum;
    typename CholeskyTraits::ACCUM_T product_sum;
    typename CholeskyTraits::ACCUM_T product_sum_array[RowsColsA];
    typename CholeskyTraits::OFF_DIAG_T prod_cast_to_off_diag;
    typename CholeskyTraits::OFF_DIAG_T new_L_off_diag;
    typename CholeskyTraits::L_OUTPUT_T new_L;

#pragma HLS ARRAY_PARTITION variable = A cyclic dim = CholeskyTraits::UNROLL_DIM factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = L cyclic dim = CholeskyTraits::UNROLL_DIM factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = L_internal cyclic dim = CholeskyTraits::UNROLL_DIM factor = \
    CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = square_sum_array cyclic dim = 1 factor = CholeskyTraits::UNROLL_FACTOR
#pragma HLS ARRAY_PARTITION variable = product_sum_array cyclic dim = 1 factor = CholeskyTraits::UNROLL_FACTOR

col_loop:
    for (int j = 0; j < RowsColsA; j++) {
        // Diagonal calculation
        A_cast_to_sum = A[j][j];
        if (j == 0) {
            A_minus_sum = A_cast_to_sum;
        } else {
            A_minus_sum = A_cast_to_sum - square_sum_array[j];
        }
        if (cholesky_sqrt_op(A_minus_sum, new_L_diag)) {
#ifndef __SYNTHESIS__
            printf("ERROR: Trying to find the square root of a negative number\n");
#endif
            return_code = 1;
        }
        // Round to target format using method specifed by traits defined types.
        new_L = new_L_diag;
        // Generate the reciprocal of the diagonal for internal use to aviod the latency of a divide in every
        // off-diagonal calculation
        A_minus_sum_cast_diag = A_minus_sum;
        cholesky_rsqrt(hls::x_real(A_minus_sum_cast_diag), new_L_diag_recip);
        // Store diagonal value
        if (LowerTriangularL == true) {
            L[j][j] = new_L;
        } else {
            L[j][j] = hls::x_conj(new_L);
        }

    sum_loop:
        for (int k = 0; k <= j; k++) {
// Define average trip count for reporting, loop reduces in length for every iteration of col_loop
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
            // Same value used in all calcs
            // o Implement -1* here
            prod_column_top = -hls::x_conj(L_internal[j][k]);

        // NOTE: Using a fixed loop length combined with a "if" to implement reducing loop length
        // o Ensures the inner loop can achieve the maximum II (1)
        // o May introduce a small overhead resolving the "if" statement but HLS struggled to schedule when the variable
        //   loop bound expression was used.
        // o Will report inaccurate trip count as it will reduce by one with the col_loop
        // o Variable loop bound code: row_loop: for(int i = j+1; i < RowsColsA; i++) {
        row_loop:
            for (int i = 0; i < RowsColsA; i++) {
// IMPORTANT: row_loop must not merge with sum_loop as the merged loop becomes variable length and HLS will struggle
// with scheduling
#pragma HLS LOOP_FLATTEN off
#pragma HLS PIPELINE II = CholeskyTraits::INNER_II
#pragma HLS UNROLL FACTOR = CholeskyTraits::UNROLL_FACTOR

                if (i > j) {
                    prod = L_internal[i][k] * prod_column_top;
                    prod_cast_to_sum = prod;

                    if (k == 0) {
                        // Prime first sum
                        if (LowerTriangularL == true) {
                            A_cast_to_sum = A[i][j];
                        } else {
                            A_cast_to_sum = hls::x_conj(A[j][i]);
                        }
                        product_sum = A_cast_to_sum;
                    } else {
                        product_sum = product_sum_array[i];
                    }

                    if (k < j) {
                        // Accumulate row sum of columns
                        product_sum_array[i] = product_sum + prod_cast_to_sum;
                    } else {
                        // Final calculation for off diagonal value
                        prod_cast_to_off_diag = product_sum;
                        // Diagonal is stored in its reciprocal form so only need to multiply the product sum
                        cholesky_prod_sum_mult(prod_cast_to_off_diag, new_L_diag_recip, new_L_off_diag);
                        // Round to target format using method specifed by traits defined types.
                        new_L = new_L_off_diag;
                        // Build sum for use in diagonal calculation for this row.
                        if (k == 0) {
                            square_sum_array[j] = hls::x_conj(new_L) * new_L;
                        } else {
                            square_sum_array[j] = hls::x_conj(new_L) * new_L;
                        }
                        // Store result
                        L_internal[i][j] = new_L;
                        // NOTE: Use the upper/lower triangle zeroing in the subsequent loop so the double memory access
                        // does not
                        // become a bottleneck
                        // o Results in a further increase of DSP resources due to the higher II of this loop.
                        // o Retaining the zeroing operation here can give this a loop a max II of 2 and HLS will
                        // resource share.
                        if (LowerTriangularL == true) {
                            L[i][j] = new_L;                                   // Store in lower triangle
                            if (!CholeskyTraits::ARCH2_ZERO_LOOP) L[j][i] = 0; // Zero upper
                        } else {
                            L[j][i] = hls::x_conj(new_L);                      // Store in upper triangle
                            if (!CholeskyTraits::ARCH2_ZERO_LOOP) L[i][j] = 0; // Zero lower
                        }
                    }
                }
            }
        }
    }
    // Zero upper/lower triangle
    // o Use separate loop to ensure main calcuation can achieve an II of 1
    // o As noted above this may increase the DSP resources.
    // o Required when unrolling the inner loop due to array dimension access
    if (CholeskyTraits::ARCH2_ZERO_LOOP) {
    zero_rows_loop:
        for (int i = 0; i < RowsColsA - 1; i++) {
        zero_cols_loop:
            for (int j = i + 1; j < RowsColsA; j++) {
// Define average trip count for reporting, loop reduces in length for every iteration of zero_rows_loop
#pragma HLS loop_tripcount max = 1 + RowsColsA / 2
#pragma HLS PIPELINE
                if (LowerTriangularL == true) {
                    L[i][j] = 0; // Zero upper
                } else {
                    L[j][i] = 0; // Zero lower
                }
            }
        }
    }
    return (return_code);
}

// ===================================================================================================================
// choleskyTop: Top level function that selects implementation architecture and internal types based on the
// traits class provided via the CholeskyTraits template parameter.
// o Call this function directly if you wish to override the default architecture choice or internal types
template <bool LowerTriangularL, int RowsColsA, typename CholeskyTraits, class InputType, class OutputType>
int choleskyTop(const InputType A[RowsColsA][RowsColsA], OutputType L[RowsColsA][RowsColsA]) {
    switch (CholeskyTraits::ARCH) {
        case 0:
            return choleskyBasic<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        case 1:
            return choleskyAlt<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        case 2:
            return choleskyAlt2<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
        default:
            return choleskyBasic<LowerTriangularL, RowsColsA, CholeskyTraits, InputType, OutputType>(A, L);
    }
}

/**
* @brief cholesky
*
* @tparam LowerTriangularL   When false generates the result in the upper triangle
* @tparam RowsColsA          Defines the matrix dimensions
* @tparam InputType          Input data type
* @tparam OutputType         Output data type
* @tparam TRAITS             choleskyTraits class
*
* @param matrixAStrm         Stream of Hermitian/symmetric positive definite input matrix
* @param matrixLStrm         Stream of Lower or upper triangular output matrix
*
* @return                    An integer type. 0=Success. 1=Failure. The function attempted to find the square root of
* a negative number i.e. the input matrix A was not Hermitian/symmetric positive definite.
*/
template <bool LowerTriangularL,
          int RowsColsA,
          class InputType,
          class OutputType,
          typename TRAITS = choleskyTraits<LowerTriangularL, RowsColsA, InputType, OutputType> >
int cholesky(hls::stream<InputType>& matrixAStrm, hls::stream<OutputType>& matrixLStrm) {
    InputType A[RowsColsA][RowsColsA];
    OutputType L[RowsColsA][RowsColsA];

    for (int r = 0; r < RowsColsA; r++) {
#pragma HLS PIPELINE
        for (int c = 0; c < RowsColsA; c++) {
            matrixAStrm.read(A[r][c]);
        }
    }

    int ret = 0;
    ret = choleskyTop<LowerTriangularL, RowsColsA, TRAITS, InputType, OutputType>(A, L);

    for (int r = 0; r < RowsColsA; r++) {
#pragma HLS PIPELINE
        for (int c = 0; c < RowsColsA; c++) {
            matrixLStrm.write(L[r][c]);
        }
    }
    return ret;
}

} // end namespace solver
} // end namespace xf
#endif

```

我将定位并复制最新的 cosim 与 csynth 报告到 `reports/`，然后读取以计算新的 T_exec 和 Slack。随后我会勾选已完成的优化任务。

- 我已完成本轮增量优化并复测，开始计算以 T_exec 为目标的收益。

结果
- Cosim Latency(max): 634 cycles
- Estimated Clock: 6.385 ns（Target=7.1ns, Uncertainty=0.71ns）
- Slack = 7.1×0.9 − 6.385 = 0.015 ns（满足）
- T_exec = 6.385 × 634 = 4041.59 ns（较之前 4086.4 ns 再降约 1.1%）

解释
- 在 ARCH0 仅改头文件前提下，通过：
  - `sum` 完全分区 + `sum_loop` UNROLL=2
  - 保持 `II=1`，减少 k 向累加的串行占比
- Cosim 周期从 640 → 634；Estimated 基本不变，T_exec 下降。

是否继续
- 我可以尝试再把 `sum_loop` UNROLL 提到 3，并配合 `L_internal` 读端绑定/依赖断言，观察是否还能把 Latency 压到 ~630 或更低；若收益有限，则考虑微调 clock 至 7.2ns（在 Estimated 不变前提下不改变 T_exec，仅确保时序更稳）。请指示偏好：继续加大 UNROLL，还是到此收敛并整理提交材料与报告说明？

