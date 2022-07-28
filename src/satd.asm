%include "config.asm"
%include "x86inc.asm"

SECTION_RODATA 32

align 16
pw_1x16:   times 16 dw 1

SECTION .text

; <num args>, <GPRs>, <num X/Y/ZMM regs used>

%define m(x) mangle(private_prefix %+ _ %+ x %+ SUFFIX)

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
%macro BUTTERFLY 1
    ; use m2 as a temporary register, then swap
    ; so that m0 and m1 contain the output
%if %1 == 16
    paddw       xm2, xm0, xm1
    psubw       xm0, xm1
%elif %1 == 32
    paddd       ym2, ym0, ym1
    psubd       ym0, ym1
%else
    %error Incorrect precision specified (16 or 32 expected, found %1)
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
%macro INTERLEAVE 1
%if %1 == 16
    punpcklwd   xm2, xm0, xm1
    punpckhwd   xm0, xm1
    SWAP 2, 1, 0, 1
%elif %1 == 32
    punpckldq   ym2, ym0, ym1
    punpckhdq   ym0, ym1
    vperm2i128  ym1, ym2, ym0, 0x20
    vperm2i128  ym0, ym2, ym0, 0x31
    SWAP 0, 1
%else
    %error Incorrect precision specified (16 or 32 expected, found %1)
%endif

%endmacro

; Interleave pairs of 2 elements
; m0 and m1 are input
%macro INTERLEAVE_PAIRS 1
%if %1 == 16
    punpckldq   xm2, xm0, xm1
    punpckhdq   xm0, xm1
%elif %1 == 32
    ; TODO not sure if this is right
    punpcklqdq  ym2, ym0, ym1
    punpckhqdq  ym0, ym1
%else
    %error Incorrect precision specified (16 or 32 expected, found %1)
%endif
    SWAP 2, 1, 0, 1
%endmacro

; macro parameter; 16-bit precision or 32-bit precision
%macro HADAMARD_4X4_PACKED 1
    ; Starting registers:

    ; m0    0    1   2   3
    ; m1    4    5   6   7
    ; m2    8    9  10  11
    ; m3    12  13  14  15

    ; Where each number represents an index of the
    ; original block of differences.

%if %1 == 16
    ; In this case, each row only has 64 bits.
    ; Each element is 16 bits, and there are 4 of them.
    ; Pack rows 0 and 2
    punpcklqdq  xm0, xm2
    ; Pack rows 1 and 3
    punpcklqdq  xm1, xm3
%elif %1 == 32
    ; pack rows next to each other
    vinserti128 ym0, ym0, xm2, 1
    ; pack rows (128 bits) next to each other
    vinserti128 ym1, ym1, xm3, 1
%endif

    ; Now that we've packed rows 0-2 and 1-3 together,
    ; this is our permutation:

    ; m0    0 1 2 3   8  9 10 11
    ; m1    4 5 6 7  12 13 14 15

    BUTTERFLY %1

    ; m0    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m1    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    INTERLEAVE %1

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m1    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    BUTTERFLY %1

    ; m0    [0+4+8+12][0-4+8-12][1+5+9+13][1-5+9-13] [2+6+10+14][2-6+10-14][3+7+11+15][3-7+11-15]
    ; m1    [0+4-8-12][0-4-8+12][1+5-9-13][1-5-9+13] [2+6-10-14][2-6-10+14][3+7-11-15][3-7-11+15]

    ; for one row:
    ; [0+1+2+3][0-1+2-3][0+1-2-3][0-1-2+3]
    ; For the vertical transform, these are packed into a new column.

    INTERLEAVE_PAIRS %1

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
    BUTTERFLY %1
    INTERLEAVE %1
    BUTTERFLY %1

    ; don't interleave pairs, as order of summation doesn't matter
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
%define PRFX xm
%elif REG_SIZE == 32
%define PRFX ym
%else
    %error Invalid register size (expected 16 or 32)
%endif

; reduce to 32-bits
%if E_SIZE == 16
    pmaddwd     PRFX%+INPUT, [pw_1x16]
%endif

%if mmsize == 32 && REG_SIZE == 32
    ; add upper half of ymm to xmm
    vextracti128    xm%+TMP, ym%+INPUT, 1
    paddd       xm%+INPUT, xm%+TMP
%endif

    ; reduce 32-bit results
    pshufd      xm%+TMP,     xm%+INPUT, q2323
    paddd       xm%+INPUT,   xm%+TMP
    pshufd      xm%+TMP,     xm%+INPUT, q1111
    paddd       xm%+INPUT,   xm%+TMP
    movd        OUTPUT,      xm%+INPUT
%endmacro

INIT_YMM avx2
cglobal satd_4x4_16bpc, 5, 7, 8, src, src_stride, dst, dst_stride, bdmax, \
                               src_stride3, dst_stride3
    ; TODO implement with double hadamard transform in ymm registers
    ; for 12-bit... might have to resort to calling 4x4 transform twice
    ; since we don't have AVX-512
    lea         src_stride3q, [3*src_strideq]
    lea         dst_stride3q, [3*dst_strideq]

    cmp         bdmaxd, (1 << 10) - 1
    jne         .12bpc

    ; first row and third (4 bytes/row)
    ; load second and fourth row (32 bits, 4x8b)
    movq        xm0, [srcq + 0*src_strideq]
    movq        xm1, [srcq + 1*src_strideq]
    movq        xm2, [srcq + 2*src_strideq]
    movq        xm3, [srcq + src_stride3q ]

    psubw       xm0, [dstq + 0*dst_strideq]
    psubw       xm1, [dstq + 1*dst_strideq]
    psubw       xm2, [dstq + 2*dst_strideq]
    psubw       xm3, [dstq + dst_stride3q ]

    HADAMARD_4X4_PACKED 16

    pabsw       xm0, xm0
    pabsw       xm1, xm1
    paddw       xm0, xm1

    HSUM 16, 16, 0, 1, eax
    RET
.12bpc:
    ; make disassembly nicer
    RESET_MM_PERMUTATION

    ; zero-extend to 32-bits
    pmovzxwd    xm0, [srcq + 0*src_strideq]
    pmovzxwd    xm1, [srcq + 1*src_strideq]
    pmovzxwd    xm2, [srcq + 2*src_strideq]
    pmovzxwd    xm3, [srcq + src_stride3q ]

    pmovzxwd    xm4, [dstq + 0*dst_strideq]
    pmovzxwd    xm5, [dstq + 1*dst_strideq]
    pmovzxwd    xm6, [dstq + 2*dst_strideq]
    pmovzxwd    xm7, [dstq + dst_stride3q ]

    psubd       xm0, xm4
    psubd       xm1, xm5
    psubd       xm2, xm6
    psubd       xm3, xm7

    HADAMARD_4X4_PACKED 32

    pabsd       m0, m0
    pabsd       m1, m1
    paddd       m0, m1

    HSUM 32, 32, 0, 1, eax
    RET
