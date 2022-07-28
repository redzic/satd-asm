; Copyright (c) 2022, The rav1e contributors. All rights reserved
;
; This source code is subject to the terms of the BSD 2 Clause License and
; the Alliance for Open Media Patent License 1.0. If the BSD 2 Clause License
; was not distributed with this source code in the LICENSE file, you can
; obtain it at www.aomedia.org/license/software. If the Alliance for Open
; Media Patent License 1.0 was not distributed with this source code in the
; PATENTS file, you can obtain it at www.aomedia.org/license/patent.

%include "config.asm"
%include "x86inc.asm"

SECTION_RODATA 32

align 16
pw_1x16:   times 16 dw 1

SECTION .text

; <num args>, <GPRs>, <num X/Y/ZMM regs used>

; Add and subtract registers
;
; Takes m0 and m1 as both input and output.
; Requires m2 as a free register.
;
; If we start with this permutation:
;
; m0    0 1  2  3    4  5  6  7
; m1    8 9 10 11   12 13 14 15
;
; Then the output will be as such:
;
; m0    [0+8][1+9][2+10][3+11] [4+12][5+13][6+14][7+15]
; m1    [0-8][1-9][2-10][3-11] [4-12][5-13][6-14][7-15]
%macro BUTTERFLY 2
    %define BIT_PRECISION %1
    %define VEC_SIZE %2

    %if VEC_SIZE == 32
        %define V ym
    %elif VEC_SIZE == 16
        %define V xm
    %endif

    ; Use m2 as a temporary register, then swap
    ; so that m0 and m1 contain the output.
    %if BIT_PRECISION == 16
        paddw       V%+ 2, V%+ 0, V%+ 1
        psubw       V%+ 0, V%+ 1
    %elif BIT_PRECISION == 32
        ; for 32-bit, we cannot do 2 transforms at the same time
        ; since we don't have 512-bit registers in AVX2
        paddd       ym2, ym0, ym1
        psubd       ym0, ym1
    %else
        %error Incorrect precision specified (16 or 32 expected)
    %endif

    SWAP 2, 1, 0, 1
%endmacro

; Interleave packed rows together (in m0 and m1).
; m2 should contain a free register.
;
; Macro argument takes size in bits of each element (where one
; element is the difference between two original source pixels).
;
; If we start with this permutation:
;
; m0    0 1  2  3    4  5  6  7
; m1    8 9 10 11   12 13 14 15
;
; Then, after INTERLEAVE, this will be the permutation:
;
; m0    0  8  1  9   2 10  3 11
; m1    4 12  5 13   6 14  7 15
%macro INTERLEAVE 2

%define BIT_PRECISION %1
%define VEC_SIZE %2

    ; TODO make macro out of this block?
    ; would deduplicate some code
    %if VEC_SIZE == 16
        %define V xm
    %elif VEC_SIZE == 32
        %define V ym
    %else
        %error Invalid vector size (expected 16 or 32)
    %endif

    %if BIT_PRECISION == 16
        punpcklwd   V%+ 2, V%+ 0, V%+ 1
        punpckhwd   V%+ 0, V%+ 1
        SWAP 2, 1, 0, 1
    %elif BIT_PRECISION == 32
        punpckldq   ym2, ym0, ym1
        punpckhdq   ym0, ym1
        ; AVX2 shuffles operate over 128-bit halves of the full ymm register
        ; in parallel, so these shuffles are required to fix up the permutation.
        vperm2i128  ym1, ym2, ym0, 0x20
        vperm2i128  ym0, ym2, ym0, 0x31
        SWAP 0, 1
    %else
        %error Incorrect precision specified (16 or 32 expected)
    %endif
%endmacro

; Interleave pairs of 2 elements (in m0 and m1)
; m2 should contain a free register.
%macro INTERLEAVE_PAIRS 2
    %define BIT_PRECISION %1
    %define VEC_SIZE %2
    %if BIT_PRECISION == 16
        punpckldq   xm2, xm0, xm1
        punpckhdq   xm0, xm1
    %elif BIT_PRECISION == 32
        punpcklqdq  ym2, ym0, ym1
        punpckhqdq  ym0, ym1
    %else
        %error Incorrect precision specified (16 or 32 expected)
    %endif
    SWAP 2, 1, 0, 1
%endmacro

%macro HADAMARD_4X4_PACKED 2

%define BIT_PRECISION %1
; Register size to use (in bytes)
%define VEC_SIZE %2
    %if VEC_SIZE == 16
        %define V xm
    %elif VEC_SIZE == 32
        %define V ym
    %else
        %error Invalid vector size (expected 16 or 32)
    %endif

    ; Starting registers:

    ; m0    0    1   2   3
    ; m1    4    5   6   7
    ; m2    8    9  10  11
    ; m3    12  13  14  15

    ; Where each number represents an index of the
    ; original block of differences.

        ; Pack rows 0,2 and 1,3 into m0 and m1
    %if BIT_PRECISION == 16
        ; In this case, each row only has 64 bits, so we use
        ; punpcklqdq only.
        punpcklqdq  V%+ 0, V%+ 2
        punpcklqdq  V%+ 1, V%+ 3

        ; ; Interleave high 64 bits as well
        ; %if VEC_SIZE == 32
        ; punpckhqdq  xm0, xm2
        ; punpckhqdq  xm1, xm3
        ; %endif

    %elif BIT_PRECISION == 32
        vinserti128 ym0, ym0, xm2, 1
        vinserti128 ym1, ym1, xm3, 1
    %else
        %error Invalid bit precision (expected 16 or 32)
    %endif

    ; Now that we've packed rows 0-2 and 1-3 together,
    ; this is our permutation:

    ; m0    0 1 2 3   8  9 10 11
    ; m1    4 5 6 7  12 13 14 15

    BUTTERFLY %1, %2

    ; m0    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m1    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    INTERLEAVE %1, %2

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m1    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    BUTTERFLY %1, %2

    ; m0    [0+4+8+12][0-4+8-12][1+5+9+13][1-5+9-13] [2+6+10+14][2-6+10-14][3+7+11+15][3-7+11-15]
    ; m1    [0+4-8-12][0-4-8+12][1+5-9-13][1-5-9+13] [2+6-10-14][2-6-10+14][3+7-11-15][3-7-11+15]

    ; for one row:
    ; [0+1+2+3][0-1+2-3][0+1-2-3][0-1-2+3]
    ; For the vertical transform, these are packed into a new column.

    INTERLEAVE_PAIRS %1, %2

    ;                p0         p1         p2         p3
    ; m0    [0+4+ 8+12][0-4+ 8-12][0+4- 8-12][0-4- 8+12] [1+5+ 9+13][1-5+ 9-13][1+5- 9-13][1-5- 9+13]
    ; m1    [2+6+10+14][2-6+10-14][2+6-10-14][2-6-10+14] [3+7+11+15][3-7+11-15][3+7-11-15][3-7-11+15]

    ; According to this grid:

    ; p0  q0  r0  s0
    ; p1  q1  r1  s1
    ; p2  q2  r2  s2
    ; p3  q3  r3  s3

    ; Horizontal transform; since the output is flipped from the original order,
    ; we can do the same steps as the vertical transform and the result will be the same.
    BUTTERFLY %1, %2
    INTERLEAVE %1, %2
    BUTTERFLY %1, %2

    ; Finished horizontal transform except for the last step (interleaving pairs),
    ; which we skip since the order we sum up the transform coefficients does not
    ; matter.
%endmacro

; Horizontal sum of mm register
;
; Inputs:
; %1 = Element size in bits (16 or 32)
; %2 = Size of input register in bytes (16 or 32)
;      You can e.g. pass 16 for this argument if you
;      only want to sum up the bottom 128-bits of a
;      ymm register.
; %3 = Input register number
; %4 = Temporary register number
; %5 = Output register (e.g., eax)
%macro HSUM 5
    %define E_SIZE %1
    %define REG_SIZE %2
    %define INPUT %3
    %define TMP %4
    %define OUTPUT %5

    %if REG_SIZE == 16
    %define V xm
    %elif REG_SIZE == 32
    %define V ym
    %else
        %error Invalid register size (expected 16 or 32)
    %endif

    %if E_SIZE == 16
        ; Add adjacent pairs of 16-bit elements to produce 32-bit results,
        ; then proceed with 32-bit sum
        pmaddwd     V%+INPUT, [pw_1x16]
    %endif

    %if mmsize == 32 && REG_SIZE == 32
        ; Add upper half of ymm to xmm
        vextracti128    xm%+TMP,   ym%+INPUT, 1
        paddd           xm%+INPUT, xm%+TMP
    %endif

    ; Reduce 32-bit results
    pshufd      xm%+TMP,     xm%+INPUT, q2323
    paddd       xm%+INPUT,   xm%+TMP
    pshufd      xm%+TMP,     xm%+INPUT, q1111
    paddd       xm%+INPUT,   xm%+TMP
    movd        OUTPUT,      xm%+INPUT
%endmacro

INIT_YMM avx2
cglobal satd_4x4_16bpc, 5, 7, 8, src, src_stride, dst, dst_stride, bdmax, \
                               src_stride3, dst_stride3
    lea         src_stride3q, [3*src_strideq]
    lea         dst_stride3q, [3*dst_strideq]

    cmp         bdmaxd, (1 << 10) - 1
    jne         .12bpc

    ; Load src rows
    movq        xm0, [srcq + 0*src_strideq]
    movq        xm1, [srcq + 1*src_strideq]
    movq        xm2, [srcq + 2*src_strideq]
    movq        xm3, [srcq + src_stride3q ]

    ; src -= dst
    psubw       xm0, [dstq + 0*dst_strideq]
    psubw       xm1, [dstq + 1*dst_strideq]
    psubw       xm2, [dstq + 2*dst_strideq]
    psubw       xm3, [dstq + dst_stride3q ]

    HADAMARD_4X4_PACKED 16, 16

    ; Sum up absolute value of transform coefficients
    pabsw       xm0, xm0
    pabsw       xm1, xm1
    paddw       xm0, xm1
    HSUM 16, 16, 0, 1, eax
    RET
.12bpc:
    ; Make disassembly less confusing to read
    RESET_MM_PERMUTATION

    ; Load src rows
    pmovzxwd    xm0, [srcq + 0*src_strideq]
    pmovzxwd    xm1, [srcq + 1*src_strideq]
    pmovzxwd    xm2, [srcq + 2*src_strideq]
    pmovzxwd    xm3, [srcq + src_stride3q ]

    ; Load dst rows
    pmovzxwd    xm4, [dstq + 0*dst_strideq]
    pmovzxwd    xm5, [dstq + 1*dst_strideq]
    pmovzxwd    xm6, [dstq + 2*dst_strideq]
    pmovzxwd    xm7, [dstq + dst_stride3q ]

    ; src -= dst
    psubd       xm0, xm4
    psubd       xm1, xm5
    psubd       xm2, xm6
    psubd       xm3, xm7

    HADAMARD_4X4_PACKED 32, 32

    ; Sum up absolute value of transform coefficients
    pabsd       m0, m0
    pabsd       m1, m1
    paddd       m0, m1
    HSUM 32, 32, 0, 1, eax
    RET

INIT_YMM avx2
cglobal satd_8x4_16bpc, 5, 7, 8, src, src_stride, dst, dst_stride, bdmax, \
                               src_stride3, dst_stride3
    xor eax, eax
    RET
