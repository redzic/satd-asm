%include "config.asm"
%include "x86inc.asm"

SECTION_RODATA 32

pw_1:   times 8 dw 1

SECTION .text
    GLOBAL satd4x4_asm

; row size in bytes
; 4 pixels * byte_per_pixel
; = 8 for HBD
%define ROW_SIZE 8

; so for 10-bit, this is fine...
; just not for 12-bit. for that we need 32-bit precision

; TODO Make this actually subtract differences from 2 planes

; r0 = Pointer to src [u8; 16]
INIT_XMM sse4
satd4x4_asm:
    ; first row and third (4 bytes/row)
    ; load second and fourth row (32 bits, 4x8b)
    movq        m0, [r0 + 0*ROW_SIZE]
    movq        m2, [r0 + 1*ROW_SIZE]
    movq        m1, [r0 + 2*ROW_SIZE]
    movq        m3, [r0 + 3*ROW_SIZE]

    ; pack rows next to each other
    ; store in m0
    punpcklqdq  m0, m1
    ; pack rows (64 bits) next to each other
    punpcklqdq  m2, m3

    ; do vertical transform

    ; m1 is free now
    ; only m0 and m2 are occupied

    ; 0 1 2 3   8  9 10 11
    ; 4 5 6 7  12 13 14 15

    ; TODO minimize these 3-operand instructions

    paddw       m1, m0, m2
    psubw       m3, m0, m2

    ; m1    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m3    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    ; interleave
    punpcklwd   m0, m1, m3
    punpckhwd   m2, m1, m3

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m2    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    ; we have the numbers needed for the 

    ; butterfly
    paddw       m1, m0, m2
    psubw       m3, m0, m2

    ; m1    [0+4+8+12][0-4+8-12][1+5+9+13][1-5+9-13] [2+6+10+14][2-6+10-14][3+7+11+15][3-7+11-15]
    ; m3    [0+4-8-12][0-4-8+12][1+5-9-13][1-5-9+13] [2+6-10-14][2-6-10+14][3+7-11-15][3-7-11+15]

    ; for one row:
    ; [0+1+2+3][0-1+2-3][0+1-2-3][0-1-2+3]
    ; For the vertical transform, these are packed into a new column.

    ; pack together
    punpckldq   m0, m1, m3
    punpckhdq   m2, m1, m3

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

    paddw       m1, m0, m2
    psubw       m3, m0, m2

    ; m1    [0+4][1+5][2+6][3+7] [8+12][9+13][10+14][11+15]
    ; m3    [0-4][1-5][2-6][3-7] [8-12][9-13][10-14][11-15]

    ; interleave
    punpcklwd   m0, m1, m3
    punpckhwd   m2, m1, m3

    ; m0    [ 0+4][ 0-4][ 1+5][ 1-5] [2 + 6][2 - 6][3 + 7][3 - 7]
    ; m2    [8+12][8-12][9+13][9-13] [10+14][10-14][11+15][11-15]

    ; we have the numbers needed for the 

    ; butterfly
    paddw       m1, m0, m2
    psubw       m0, m2

    ; transform has all the same numbers, just in the wrong order
    ; but since we're doing an associative (?) reduction, the wrong
    ; order does not affect the final result

    ; --- 2D TRANSFORM DONE ---

    ; sum absolute value of all numbers

    pabsw       m1, m1
    pabsw       m0, m0
    paddw       m1, m0

    ; horizontal reduce
    ; multiply by 1 and accumulate adjacent 16-bit pairs into 32-bit results
    pmaddwd     m1, [pw_1]
    ; reduce 32-bit results
    pshufd      m0, m1, q2323
    paddd       m1, m0
    pshufd      m0, m1, q1111
    paddd       m1, m0
    movd        eax, m1
    ret
