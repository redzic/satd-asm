%include "config.asm"
%include "x86inc.asm"

SECTION_RODATA 32

pw_1:   times 8 dw 1

SECTION .text


; so for 10-bit, this is fine...
; just not for 12-bit. for that we need 32-bit precision

; TODO Make this actually subtract differences from 2 planes

; r0 = Pointer to src [u8; 16]
INIT_YMM avx2
cglobal satd_4x4_10bpc, 1, 1, 4, src
    ; row size in bytes
    ; 4 pixels * byte_per_pixel
    ; = 8 for HBD
    %define     ROW_SIZE 8

    ; first row and third (4 bytes/row)
    ; load second and fourth row (32 bits, 4x8b)
    movq        xm0, [r0 + 0*ROW_SIZE]
    movq        xm2, [r0 + 1*ROW_SIZE]
    movq        xm1, [r0 + 2*ROW_SIZE]
    movq        xm3, [r0 + 3*ROW_SIZE]

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

    ; transform has all the same numbers, just in the wrong order
    ; but since we're doing an associative (?) reduction, the wrong
    ; order does not affect the final result

    ; --- 2D TRANSFORM DONE ---

    ; sum absolute value of all numbers

    pabsw       xm1, xm1
    pabsw       xm0, xm0
    paddw       xm1, xm0

    ; horizontal reduce
    ; multiply by 1 and accumulate adjacent 16-bit pairs into 32-bit results
    pmaddwd     xm1, [pw_1]
    ; reduce 32-bit results
    pshufd      xm0, xm1, q2323
    paddd       xm1, xm0
    pshufd      xm0, xm1, q1111
    paddd       xm1, xm0
    movd        eax, xm1
    RET
