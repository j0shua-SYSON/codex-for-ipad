.section .text
.global _start
.macro control operation, descriptor
    movl $255, %eax
    movl epoll_fd, %ebx
    movl $\operation, %ecx
    movl \descriptor, %edx
    movl $event, %esi
    int $0x80
.endm
_start:
    movl $42, %eax
    movl $pipe_a, %ebx
    int $0x80
    testl %eax, %eax
    jne failed
    movl $42, %eax
    movl $pipe_b, %ebx
    int $0x80
    testl %eax, %eax
    jne failed
    movl $254, %eax
    movl $1, %ebx
    int $0x80
    testl %eax, %eax
    js failed
    movl %eax, epoll_fd
    control 1, pipe_a
    testl %eax, %eax
    jne failed
    movl $2, event+4
    control 1, pipe_b
    testl %eax, %eax
    jne failed
    movl $4, %eax
    movl pipe_a+4, %ebx
    movl $payload, %ecx
    movl $1, %edx
    int $0x80
    cmpl $1, %eax
    jne failed
    movl $4, %eax
    movl pipe_b+4, %ebx
    int $0x80
    cmpl $1, %eax
    jne failed
    # maxevents=1 must not consume the other descriptor's edge/one-shot.
    call wait_one
    cmpl $1, %eax
    jne failed
    movl result+4, %eax
    movl %eax, seen
    call wait_one
    cmpl $1, %eax
    jne failed
    movl result+4, %eax
    orl seen, %eax
    cmpl $3, %eax
    jne failed
    call wait_one
    testl %eax, %eax
    jne failed
    # A delivered one-shot is still registered and rearmable.
    control 1, pipe_a
    cmpl $-17, %eax # EEXIST
    jne failed
    movl $3, event+4
    control 3, pipe_a
    testl %eax, %eax
    jne failed
    call wait_one
    cmpl $1, %eax
    jne failed
    cmpl $3, result+4
    jne failed
    # Reuse retired records while kernel notifications may still reference them.
    movl $128, iterations
again:
    control 2, pipe_a
    testl %eax, %eax
    jne failed
    control 1, pipe_a
    testl %eax, %eax
    jne failed
    call wait_one
    cmpl $1, %eax
    jne failed
    decl iterations
    jnz again
    # Closing a disabled entry must also cleanly unlink it.
    movl $6, %eax
    movl pipe_a, %ebx
    int $0x80
    call wait_one
    testl %eax, %eax
    jne failed
    xorl %ebx, %ebx
    jmp finish
wait_one:
    movl $256, %eax
    movl epoll_fd, %ebx
    movl $result, %ecx
    movl $1, %edx
    xorl %esi, %esi
    int $0x80
    ret
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
pipe_a: .long 0, 0
pipe_b: .long 0, 0
epoll_fd: .long 0
event: .long 0xc0000001, 1, 0 # EPOLLIN | EPOLLET | EPOLLONESHOT
result: .long 0, 0, 0
seen: .long 0
iterations: .long 0
payload: .byte 1
