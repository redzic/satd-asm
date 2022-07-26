%include "config.asm"
%include "x86inc.asm"

SECTION .text

; so for 10-bit, this is fine...
; just not for 12-bit. for that we need 32-bit precision

; TODO Make this actually subtract differences from 2 planes

; <num args>, <GPRs>, <num X/Y/ZMM regs used>

; TODO rename src and dst

align 16
pw_1x8:   times 8 dw 1

INIT_YMM avx2
cglobal satd_4x4_12bpc, 4, 6, 8, src, src_stride, dst, dst_stride, \
                                 src_stride3, dst_stride3
    lea         src_stride3q, [3*src_strideq]
    lea         dst_stride3q, [3*dst_strideq]

    ; zero-extend to 32-bits
    pmovzxwd    xm0, [srcq + 0*src_strideq]
    pmovzxwd    xm2, [srcq + 1*src_strideq]
    pmovzxwd    xm1, [srcq + 2*src_strideq]
    pmovzxwd    xm3, [srcq + src_stride3q ]

    ; load dst pixels
    pmovzxwd    xm4, [dstq + 0*dst_strideq]
    pmovzxwd    xm6, [dstq + 1*dst_strideq]
    pmovzxwd    xm5, [dstq + 2*dst_strideq]
    pmovzxwd    xm7, [dstq + dst_stride3q ]

    ; TODO is it possible to do this on ymm registers,
    ; so in 2 instructions?
    ; subtract differences
    psubd       xm0, xm4
    psubd       xm2, xm6
    psubd       xm1, xm5
    psubd       xm3, xm7

    ; [0, 1,  2,  3,  4,  5,  6,  7]
    ; [8, 9, 10, 11, 12, 13, 14, 15]

    ; ; pack rows next to each other
    ; vinserti128 ym0, ym0, xm2, 1
    ; ; pack rows (128 bits) next to each other
    ; vinserti128 ym2, ym1, xm3, 1
    ; ; CORRECT:


    ; pack rows next to each other
    vinserti128 ym0, ym0, xm1, 1
    ; pack rows (128 bits) next to each other
    vinserti128 ym2, ym2, xm3, 1

    ; do vertical transform

    ; m1 is free now
    ; only m0 and m2 are occupied

    ; m0    0 1 2 3   8  9 10 11
    ; m2    4 5 6 7  12 13 14 15

    paddd       m1, m0, m2
    psubd       m3, m0, m2

    ; m1    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m3    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    ; interleave
    ; TODO see if there's a way to do the entire shuffle in less steps
    punpckldq   m0, m1, m3
    punpckhdq   m2, m1, m3
    vperm2i128  m1, m0, m2, 0x20
    vperm2i128  m3, m0, m2, 0x31

    SWAP    0, 1, 2, 3

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m2    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    paddd       m1, m0, m2
    psubd       m3, m0, m2

    ; m1    [0+4+8+12][0-4+8-12][1+5+9+13][1-5+9-13] [2+6+10+14][2-6+10-14][3+7+11+15][3-7+11-15]
    ; m3    [0+4-8-12][0-4-8+12][1+5-9-13][1-5-9+13] [2+6-10-14][2-6-10+14][3+7-11-15][3-7-11+15]

    ; for one row:
    ; [0+1+2+3][0-1+2-3][0+1-2-3][0-1-2+3]
    ; For the vertical transform, these are packed into a new column.

    ; pack together
    punpcklqdq      m0, m1, m3
    punpckhqdq      m2, m1, m3
    vperm2i128      m1, m0, m2, 0x20
    vperm2i128      m3, m0, m2, 0x31
    
    ;               p0          p1        p2         p3
    ; m0    [0+4+ 8+12][0-4+ 8-12][0+4- 8-12][0-4- 8+12] [1+5+ 9+13][1-5+ 9-13][1+5- 9-13][1-5- 9+13] 
    ; m2    [2+6+10+14][2-6+10-14][2+6-10-14][2-6-10+14] [3+7+11+15][3-7+11-15][3+7-11-15][3-7-11+15]

    ; According to this grid:

    ; +----+----+----+----+
    ; | p0 | q0 | r0 | s0 |
    ; +----+----+----+----+
    ; | p1 | q1 | r1 | s1 |
    ; +----+----+----+----+
    ; | p2 | q2 | r2 | s2 |
    ; +----+----+----+----+
    ; | p3 | q3 | r3 | s3 |
    ; +----+----+----+----+

    SWAP 0, 1, 2, 3

    ; ---- END OF VERTICAL TRANSFORM

    paddd       m1, m0, m2
    psubd       m3, m0, m2

    ; m1    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m3    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    ; interleave
    ; TODO see if there's a way to do the entire shuffle in less steps
    punpckldq   m0, m1, m3
    punpckhdq   m2, m1, m3
    vperm2i128  m1, m0, m2, 0x20
    vperm2i128  m3, m0, m2, 0x31

    SWAP    0, 1, 2, 3

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m2    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    paddd       m1, m0, m2
    psubd       m3, m0, m2

    ; m1    [0+4+8+12][0-4+8-12][1+5+9+13][1-5+9-13] [2+6+10+14][2-6+10-14][3+7+11+15][3-7+11-15]
    ; m3    [0+4-8-12][0-4-8+12][1+5-9-13][1-5-9+13] [2+6-10-14][2-6-10+14][3+7-11-15][3-7-11+15]

    ; for one row:
    ; [0+1+2+3][0-1+2-3][0+1-2-3][0-1-2+3]
    ; For the vertical transform, these are packed into a new column.

    SWAP 0, 1, 2, 3

    ; sum up 32-bit values
    pabsd       m0, m0
    pabsd       m2, m2
    paddd       m0, m2

    ; reduce horizontally

    vextracti128    xm1, ym0, 1
    paddd       xm0, xm1

    pshufd      xm1, xm0, q2323
    paddd       xm0, xm1
    pshufd      xm1, xm0, q1111
    paddd       xm0, xm1
    movd        eax, xm0
    RET

INIT_YMM avx2
cglobal satd_4x4_10bpc, 4, 6, 4, src, src_stride, dst, dst_stride, \
                                 src_stride3, dst_stride3
    lea         src_stride3q, [3*src_strideq]
    lea         dst_stride3q, [3*dst_strideq]

    ; first row and third (4 bytes/row)
    ; load second and fourth row (32 bits, 4x8b)
    movq        xm0, [srcq + 0*src_strideq]
    movq        xm2, [srcq + 1*src_strideq]
    movq        xm1, [srcq + 2*src_strideq]
    movq        xm3, [srcq + src_stride3q ]

    psubw       xm0, [dstq + 0*dst_strideq]
    psubw       xm2, [dstq + 1*dst_strideq]
    psubw       xm1, [dstq + 2*dst_strideq]
    psubw       xm3, [dstq + dst_stride3q ]

    ; pack rows next to each other
    ; store in m0
    punpcklqdq  xm0, xm1
    ; pack rows (64 bits) next to each other
    punpcklqdq  xm2, xm3

    ; do vertical transform

    ; m1 is free now
    ; only m0 and m2 are occupied

    ; 0 1 2 3   8  9 10 11
    ; 4 5 6 7  12 13 14 15

    paddw       xm1, xm0, xm2
    psubw       xm0, xm2

    SWAP 0, 3

    ; m1    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m3    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    ; interleave
    punpcklwd   xm0, xm1, xm3
    punpckhwd   xm1, xm3

    SWAP 2, 1

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m2    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    ; we have the numbers needed for the 

    ; butterfly
    paddw       xm1, xm0, xm2
    psubw       xm0, xm2

    SWAP 3, 0

    ; m1    [0+4+8+12][0-4+8-12][1+5+9+13][1-5+9-13] [2+6+10+14][2-6+10-14][3+7+11+15][3-7+11-15]
    ; m3    [0+4-8-12][0-4-8+12][1+5-9-13][1-5-9+13] [2+6-10-14][2-6-10+14][3+7-11-15][3-7-11+15]

    ; for one row:
    ; [0+1+2+3][0-1+2-3][0+1-2-3][0-1-2+3]
    ; For the vertical transform, these are packed into a new column.

    ; pack together
    punpckldq   xm0, xm1, xm3
    punpckhdq   xm1, xm3

    SWAP 2, 1

    ;               p0          p1        p2         p3
    ; m0    [0+4+ 8+12][0-4+ 8-12][0+4- 8-12][0-4- 8+12] [1+5+ 9+13][1-5+ 9-13][1+5- 9-13][1-5- 9+13] 
    ; m2    [2+6+10+14][2-6+10-14][2+6-10-14][2-6-10+14] [3+7+11+15][3-7+11-15][3+7-11-15][3-7-11+15]

    ; According to this grid:

    ; +----+----+----+----+
    ; | p0 | q0 | r0 | s0 |
    ; +----+----+----+----+
    ; | p1 | q1 | r1 | s1 |
    ; +----+----+----+----+
    ; | p2 | q2 | r2 | s2 |
    ; +----+----+----+----+
    ; | p3 | q3 | r3 | s3 |
    ; +----+----+----+----+

    ; our input is flipped, if we do the vertical transform again then
    ; it is equivalent to just doing the horizontal transform again

    ; TODO test if precision up until here is good with 12-bit
    ; maybe we could only cast to 32-bit when we do the second 1D transform

    ; --- Horizontal transform ---

    paddw       xm1, xm0, xm2
    psubw       xm0, xm2

    SWAP 3, 0

    ; m1    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m0    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    ; interleave
    punpcklwd   xm0, xm1, xm3
    punpckhwd   xm1, xm3

    SWAP 2, 1

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m2    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    ; we have the numbers needed for the 

    ; butterfly
    paddw       xm1, xm0, xm2
    psubw       xm0, xm2

    ; transform has all the same numbers, just in the wrong order
    ; but since we're doing an associative (?) reduction, the wrong
    ; order does not affect the final result

    ; --- 2D TRANSFORM DONE ---

    ; sum absolute value of all numbers

    pabsw       xm1, xm1
    pabsw       xm0, xm0
    paddw       xm1, xm0

    ; horizontally reduce coefficients
    ; accumulate adjacent 16-bit pairs into 32-bit results
    pmaddwd     xm1, [pw_1x8]
    ; reduce 32-bit results
    pshufd      xm0, xm1, q2323
    paddd       xm1, xm0
    pshufd      xm0, xm1, q1111
    paddd       xm1, xm0
    movd        eax, xm1
    RET
