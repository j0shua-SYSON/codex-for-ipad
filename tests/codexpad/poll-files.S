.section .text
.global _start
_start:
    movl $5, %eax
    movl $self_path, %ebx
    xorl %ecx, %ecx
    int $0x80
    testl %eax, %eax
    js failed
    movl %eax, entries
    movl %eax, entries+8
    # Two entries for the same read-only regular file: both must count.
    call poll_ready
    cmpl $2, %eax
    jne failed
    cmpw $1, entries+6
    jne failed
    cmpw $4, entries+14
    jne failed
    # EOF is still immediately readable.
    movl $19, %eax
    movl entries, %ebx
    xorl %ecx, %ecx
    movl $2, %edx
    int $0x80
    testl %eax, %eax
    js failed
    call poll_ready
    cmpl $2, %eax
    jne failed
    # Invalid descriptors must return POLLNVAL without blocking forever.
    movl $6, %eax
    movl entries, %ebx
    int $0x80
    call poll_ready
    cmpl $2, %eax
    jne failed
    cmpw $32, entries+6
    jne failed
    cmpw $32, entries+14
    jne failed
    xorl %ebx, %ebx
    jmp finish
poll_ready:
    movl $168, %eax
    movl $entries, %ebx
    movl $2, %ecx
    movl $-1, %edx
    int $0x80
    ret
failed:
    movl $1, %ebx
finish:
    movl $1, %eax
    int $0x80
.section .data
self_path: .asciz "/poll-files"
.align 4
entries: .long 0
         .short 1, 0
         .long 0
         .short 4, 0
