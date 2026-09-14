.section .text
.global _start
_start:
    movl $120, %eax
    movl $0x10900, %ebx # CLONE_THREAD | CLONE_SIGHAND | CLONE_VM
    movl $thread_stack_end, %ecx
    xorl %edx, %edx
    xorl %esi, %esi
    xorl %edi, %edi
    int $0x80
    testl %eax, %eax
    js failed
    jz thread
wait_thread:
    cmpl $1, complete
    je success
    movl $158, %eax
    int $0x80
    jmp wait_thread
thread:
    movl $20, %eax
    int $0x80
    cmpl $1, %eax
    jne failed
    movl $224, %eax
    int $0x80
    cmpl $1, %eax
    je failed
    movl $64, %eax
    int $0x80
    testl %eax, %eax # PID 1 and its threads have no guest parent
    jne failed
    movl $120, %eax
    movl $0x111, %ebx # independent process spawned by a non-leader thread
    movl $child_stack_end, %ecx
    xorl %edx, %edx
    xorl %esi, %esi
    xorl %edi, %edi
    int $0x80
    testl %eax, %eax
    js failed
    jz child
    movl %eax, %ebx
    movl $7, %eax
    movl $status, %ecx
    xorl %edx, %edx
    int $0x80
    testl %eax, %eax
    js failed
    cmpl $0, status
    jne failed
    movl $1, complete
    jmp success
child:
    movl $64, %eax
    int $0x80
    cmpl $1, %eax # Must match the spawning process's getpid, not gettid
    jne failed
success:
    xorl %ebx, %ebx
    movl $1, %eax
    int $0x80
failed:
    movl $1, %ebx
    movl $252, %eax
    int $0x80
.section .data
complete: .long 0
status: .long 0
.balign 16
thread_stack: .skip 8192
thread_stack_end:
child_stack: .skip 8192
child_stack_end:
.section .note.GNU-stack,"",@progbits
