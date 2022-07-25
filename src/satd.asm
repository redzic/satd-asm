%include "config.asm"
%include "x86inc.asm"

SECTION .text
    GLOBAL satd4x4_asm

%define ROW_SIZE 4

; r0 = Pointer to src [u8; 16]
; r1 = Pointer to buffer of [u16; 8] (may not be used)
INIT_XMM sse4
satd4x4_asm:
    ; first row and third (4 bytes/row)
    ; load second and fourth row (32 bits, 4x8b)
    movd        m0, [r0 + 0*ROW_SIZE]
    movd        m2, [r0 + 1*ROW_SIZE]
    movd        m1, [r0 + 2*ROW_SIZE]
    movd        m3, [r0 + 3*ROW_SIZE]

    ; pack rows next to each other
    ; store in m0
    punpckldq   m0, m1
    ; pack rows (32 bits) next to each other
    punpckldq   m2, m3

    ; zero-extend both sets of packed rows to 16-bits
    pmovzxbw    m0, m0
    pmovzxbw    m2, m2

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
    psubw       m3, m0, m2

    ; transform has all the same numbers, just in the wrong order
    ; but since we're doing an associative (?) reduction, the wrong
    ; order does not affect the final result

    ; dump registers
    movu    [r1],        m1
    movu    [r1+mmsize], m3
    xor     eax, eax
    ret
