.section .text
.global _start
.macro pair destination
    movl $360, %eax
    movl $1, %ebx
    movl $0x80801, %ecx
    xorl %edx, %edx
    movl $\destination, %esi
    int $0x80
.endm
.macro close offset
    movl $6, %eax
    movl sockets+\offset, %ebx
    int $0x80
    testl %eax, %eax
    jne failed
.endm
_start:
    pair sockets
    testl %eax, %eax
    jne failed
    movl sockets, %eax
    movl %eax, first_fd
    movl $55, %eax
    movl sockets, %ebx
    movl $1, %ecx
    int $0x80
    cmpl $1, %eax # FD_CLOEXEC
    jne failed
    movl $55, %eax
    movl $3, %ecx
    int $0x80
    testl $0x800, %eax # O_NONBLOCK
    jz failed
    movl $3, %eax
    movl sockets+4, %ebx
    movl $buffer, %ecx
    movl $4, %edx
    int $0x80
    cmpl $-11, %eax
    jne failed
    movl $4, %eax
    movl sockets, %ebx
    movl $payload, %ecx
    int $0x80
    cmpl $4, %eax
    jne failed
    movl $3, %eax
    movl sockets+4, %ebx
    movl $buffer, %ecx
    int $0x80
    cmpl $4, %eax
    jne failed
    cmpl $0x12345678, buffer
    jne failed
    close 0
    movl $3, %eax
    movl sockets+4, %ebx
    movl $buffer, %ecx
    movl $4, %edx
    int $0x80
    testl %eax, %eax # EOF after peer's final close
    jne failed
    close 4
    pair 0
    cmpl $-14, %eax # EFAULT must release both descriptors
    jne failed
    # Force failure installing the second guest fd. This used to deadlock
    # through sock_close while peer_lock was held, then double-close host fds.
    movl $340, %eax # prlimit64 avoids legacy getrlimit's signed limit
    xorl %ebx, %ebx
    movl $7, %ecx
    xorl %edx, %edx
    movl $old_limit, %esi
    int $0x80
    testl %eax, %eax
    jne failed
    movl first_fd, %eax
    incl %eax
    movl %eax, new_limit
    movl old_limit+8, %eax
    movl %eax, new_limit+8
    movl old_limit+12, %eax
    movl %eax, new_limit+12
    movl $340, %eax
    movl $new_limit, %edx
    xorl %esi, %esi
    int $0x80
    testl %eax, %eax
    jne failed
    pair sockets
    cmpl $-24, %eax
    jne failed
    movl $340, %eax
    xorl %ebx, %ebx
    movl $7, %ecx
    movl $old_limit, %edx
    xorl %esi, %esi
    int $0x80
    testl %eax, %eax
    jne failed
    pair sockets
    testl %eax, %eax
    jne failed
    movl first_fd, %eax
    cmpl %eax, sockets
    jne failed
    close 0
    close 4
    xorl %ebx, %ebx
    jmp finish
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
payload: .long 0x12345678
sockets: .long 0, 0
first_fd: .long 0
buffer: .long 0
old_limit: .long 0, 0, 0, 0
new_limit: .long 0, 0, 0, 0
