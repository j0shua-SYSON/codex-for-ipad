.section .text
.global _start
.macro clock_get destination
    movl $265, %eax
    movl $1, %ebx
    movl $\destination, %ecx
    int $0x80
    testl %eax, %eax
    jne failed
.endm
.macro sleep flags, duration
    movl $267, %eax
    movl $1, %ebx
    movl $\flags, %ecx
    movl $\duration, %edx
    movl $remaining, %esi
    int $0x80
.endm
.macro clone stack
    movl $120, %eax
    movl $0x111, %ebx
    movl $\stack, %ecx
    xorl %edx, %edx
    xorl %esi, %esi
    xorl %edi, %edi
    int $0x80
.endm
.macro pdeath signal
    movl $172, %eax
    movl $1, %ebx
    movl $\signal, %ecx
    int $0x80
.endm
_start:
    sleep 0, invalid
    cmpl $-22, %eax
    jne failed
    sleep 1, expired
    testl %eax, %eax
    jne failed
    clock_get before
    sleep 0, duration
    testl %eax, %eax
    jne failed
    cmpl $123, remaining
    jne failed
    clock_get after
    movl after, %eax
    subl before, %eax
    imull $1000000000, %eax
    addl after+4, %eax
    subl before+4, %eax
    cmpl $20000000, %eax
    jl failed
    pdeath 65
    cmpl $-22, %eax
    jne failed
    clone worker_stack_end
    testl %eax, %eax
    js failed
    jz worker
    # This executable is guest PID 1 and receives the orphaned grandchild.
    movl %eax, %ebx
    movl $7, %eax
    movl $status, %ecx
    xorl %edx, %edx
    int $0x80
    testl %eax, %eax
    js failed
    cmpl $10752, status
    jne failed
    movl $7, %eax
    movl grandchild_pid, %ebx
    movl $status, %ecx
    xorl %edx, %edx
    int $0x80
    testl %eax, %eax
    js failed
    cmpl $15, status
    jne failed
    xorl %ebx, %ebx
    jmp finish
worker:
    pdeath 9
    testl %eax, %eax
    jne failed
    clone grandchild_stack_end
    testl %eax, %eax
    js failed
    jz grandchild
    movl %eax, grandchild_pid
wait_ready:
    cmpl $1, ready
    je worker_exit
    movl $158, %eax
    int $0x80
    jmp wait_ready
worker_exit:
    movl $42, %ebx
    jmp finish
grandchild:
    movl $172, %eax
    movl $2, %ebx
    movl $setting, %ecx
    int $0x80
    testl %eax, %eax
    jne failed
    cmpl $0, setting
    jne failed
    pdeath 15
    testl %eax, %eax
    jne failed
    movl $1, ready
    movl $29, %eax
    int $0x80
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
.balign 4
before: .long 0, 0
after: .long 0, 0
duration: .long 0, 20000000
invalid: .long 0, 1000000000
expired: .long 0, 0
remaining: .long 123, 456
status: .long 0
setting: .long -1
ready: .long 0
grandchild_pid: .long 0
.balign 16
worker_stack: .skip 8192
worker_stack_end:
grandchild_stack: .skip 8192
grandchild_stack_end:
.section .note.GNU-stack,"",@progbits
