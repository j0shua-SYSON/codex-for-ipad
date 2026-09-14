.section .text
.global _start
.macro futex operation, expected, timeout, mask
    movl $240, %eax
    movl $word, %ebx
    movl $\operation, %ecx
    movl $\expected, %edx
    movl $\timeout, %esi
    xorl %edi, %edi
    movl $\mask, %ebp
    int $0x80
.endm
_start:
    # A mismatched value must return EAGAIN, even with an expired deadline.
    futex 137, 1, expired, -1
    cmpl $-11, %eax
    jne failed
    futex 137, 0, expired, -1
    cmpl $-110, %eax
    jne failed
    # Realtime absolute deadlines and ordinary relative waits.
    futex 393, 0, expired, -1
    cmpl $-110, %eax
    jne failed
    futex 128, 0, expired, 0
    cmpl $-110, %eax
    jne failed
    futex 137, 0, invalid_time, -1
    cmpl $-22, %eax
    jne failed
    futex 137, 0, 0, 0
    cmpl $-22, %eax
    jne failed
    futex 138, 1, 0, 0
    cmpl $-22, %eax
    jne failed
    # A child sharing the address space waits on bit 2. Waking bit 1 must
    # never release it, and waking bit 2 must release exactly one waiter.
    movl $120, %eax
    movl $0x111, %ebx  # CLONE_VM | SIGCHLD
    movl $child_stack_end, %ecx
    xorl %edx, %edx
    xorl %esi, %esi
    xorl %edi, %edi
    int $0x80
    testl %eax, %eax
    js failed
    jz child
    movl %eax, child_pid
    movl $100000, attempts
retry_wake:
    futex 138, 1, 0, 1
    testl %eax, %eax
    jne failed
    futex 138, 1, 0, 2
    cmpl $1, %eax
    je join
    testl %eax, %eax
    jne failed
    movl $158, %eax  # sched_yield
    int $0x80
    decl attempts
    jnz retry_wake
    jmp failed
join:
    movl $7, %eax
    movl child_pid, %ebx
    movl $child_status, %ecx
    xorl %edx, %edx
    int $0x80
    cmpl child_pid, %eax
    jne failed
    cmpl $10752, child_status  # normal exit 42
    jne failed
    xorl %ebx, %ebx
    jmp finish
child:
    futex 137, 0, 0, 2
    testl %eax, %eax
    jne failed
    movl $42, %ebx
    jmp finish
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
.balign 4
word: .long 0
expired: .long 0, 0
invalid_time: .long 0, 1000000000
attempts: .long 0
child_pid: .long 0
child_status: .long 0
.balign 16
child_stack: .skip 8192
child_stack_end:
.section .note.GNU-stack,"",@progbits
