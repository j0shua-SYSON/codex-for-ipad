.section .text
.global _start
_start:
    xorl %ebx, %ebx
next_mask:
    movl %ebx, %eax
    shll $31, %eax
    movl %eax, vector
    movl %ebx, %eax
    shrl $1, %eax
    shll $31, %eax
    movl %eax, vector+4
    movl %ebx, %eax
    shrl $2, %eax
    shll $31, %eax
    movl %eax, vector+8
    movl %ebx, %eax
    shrl $3, %eax
    shll $31, %eax
    movl %eax, vector+12
    movups vector, %xmm0
    movl $-1, %edx
    # Set carry using an instruction supported by the baseline emulator.
    # The test is about MOVMSKPS, not the separately unsupported STC opcode.
    xorl %eax, %eax
    cmpl $1, %eax
    movmskps %xmm0, %edx
    jnc failed
    cmpl %ebx, %edx
    jne failed
    incl %ebx
    cmpl $16, %ebx
    jne next_mask
    movups nan_vector, %xmm7
    movmskps %xmm7, %esi
    cmpl $10, %esi
    jne failed
    xorl %ebx, %ebx
    jmp finish
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
.balign 16
vector: .long 0, 0, 0, 0
nan_vector: .long 0, 0x80000000, 0x7fc00000, 0xffc00000
.section .note.GNU-stack,"",@progbits
