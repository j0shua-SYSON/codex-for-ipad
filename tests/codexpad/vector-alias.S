.section .text
.global _start
.macro check a, b, c, d
    movups %xmm0, result
    cmpl $\a, result
    jne failed
    cmpl $\b, result+4
    jne failed
    cmpl $\c, result+8
    jne failed
    cmpl $\d, result+12
    jne failed
.endm
_start:
    movups source, %xmm0
    shufps $0x41, %xmm0, %xmm0
    check 20, 10, 10, 20
    movups source, %xmm0
    movups other, %xmm1
    shufps $0x41, %xmm1, %xmm0
    check 20, 10, 50, 60
    movups source, %xmm0
    shufpd $1, %xmm0, %xmm0
    check 30, 40, 10, 20
    movups source, %xmm0
    unpcklps %xmm0, %xmm0
    check 10, 10, 20, 20
    movups source, %xmm0
    unpckhpd %xmm1, %xmm0
    check 30, 40, 70, 80
    xorl %ebx, %ebx
    jmp finish
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
.balign 16
source: .long 10, 20, 30, 40
other: .long 50, 60, 70, 80
result: .long 0, 0, 0, 0
.section .note.GNU-stack,"",@progbits
