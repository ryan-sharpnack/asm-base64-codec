; main.asm — Base64 encoder/decoder in pure x86_64 assembly (Linux, NASM)
;
; No libc. All I/O and program exit go through raw Linux syscalls.
; Usage:
;   ./base64        < input   -> encodes stdin to Base64 on stdout
;   ./base64 -d     < input   -> decodes Base64 stdin to raw bytes on stdout
;
; Design notes:
;   - Input is read fully into a fixed-size buffer (IN_CAP bytes). This is a
;     deliberate simplicity/size tradeoff over dynamic (mmap-based) growth.
;   - Decode ignores trailing newlines/whitespace and stops at '=' padding.

%define IN_CAP   65536      ; max input bytes we'll buffer (64 KiB)
%define OUT_CAP  87381      ; ceil(IN_CAP * 4 / 3) + slack for decode's 4:3 too

; xlat_b64 table_reg, al_reg -> al_reg = byte [table_reg + al_reg]
; (tiny alphabet-lookup helper; avoids repeating the same two
; instructions at every one of the encoder's four index calculations)
%macro xlat_b64 2
    movzx r11, %2
    mov %2, [%1 + r11]
%endmacro

; ---- Linux x86_64 syscall numbers ----
%define SYS_read   0
%define SYS_write  1
%define SYS_exit   60

section .rodata
b64_alphabet: db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
pad_char:     db "="

; Decode lookup table: maps ASCII byte -> 6-bit value, or 0xFF if not a
; valid Base64 character. Built as 256 bytes so decoding is a single
; table lookup per input character (no branching per symbol).
align 16
b64_decode_tbl:
    times 43 db 0xFF          ; 0x00-0x2A
    db 0x3E                   ; '+' = 0x2B -> 62
    times 3 db 0xFF            ; 0x2C-0x2E
    db 0x3F                   ; '/' = 0x2F -> 63
    db 0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D ; '0'-'9' -> 52-61
    times 7 db 0xFF            ; 0x3A-0x40 ':' ';' '<' '=' '>' '?' '@'
    db 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F
    db 0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19  ; 'A'-'Z' -> 0-25
    times 6 db 0xFF            ; 0x5B-0x60
    db 0x1A,0x1B,0x1C,0x1D,0x1E,0x1F,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29
    db 0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,0x30,0x31,0x32,0x33  ; 'a'-'z' -> 26-51
    times 133 db 0xFF          ; 0x7B-0xFF

section .bss
in_buf:  resb IN_CAP
out_buf: resb OUT_CAP

section .text
global _start

_start:
    ; ---- Parse argv for "-d" (decode mode). Stack layout at entry:
    ; [rsp]      = argc
    ; [rsp+8]    = argv[0]
    ; [rsp+16]   = argv[1]  (present only if argc > 1)
    mov rax, [rsp]
    cmp rax, 2
    jl .mode_decided            ; no argv[1] -> default to encode

    mov rsi, [rsp+16]           ; rsi = argv[1] pointer
    mov al, [rsi]
    cmp al, '-'
    jne .mode_decided
    mov al, [rsi+1]
    cmp al, 'd'
    jne .mode_decided
    mov al, [rsi+2]
    cmp al, 0                   ; must be exactly "-d"
    jne .mode_decided
    mov byte [rel decode_mode], 1

.mode_decided:
    ; ---- Read all of stdin into in_buf, tracking total length in r15 ----
    xor r15, r15                ; r15 = bytes read so far
.read_loop:
    mov rax, SYS_read
    mov rdi, 0                  ; fd 0 = stdin
    lea rsi, [rel in_buf]
    add rsi, r15
    mov rdx, IN_CAP
    sub rdx, r15                ; remaining capacity
    syscall
    cmp rax, 0
    jle .read_done               ; 0 = EOF, negative = error -> stop
    add r15, rax
    cmp r15, IN_CAP
    jl .read_loop
.read_done:

    cmp byte [rel decode_mode], 1
    je do_decode
    jmp do_encode

; =====================================================================
; ENCODE: 3 input bytes -> 4 Base64 characters, manual bit-shifting.
; =====================================================================
do_encode:
    lea rsi, [rel in_buf]       ; rsi = input cursor
    lea rdi, [rel out_buf]      ; rdi = output cursor
    lea rbx, [rel b64_alphabet] ; rbx = alphabet table base
    xor rcx, rcx                ; rcx = bytes consumed so far

.enc_loop:
    mov rax, r15
    sub rax, rcx
    cmp rax, 3
    jl .enc_tail                 ; fewer than 3 bytes left -> handle padding

    ; Load 3 raw bytes
    movzx r8, byte [rsi]         ; byte0
    movzx r9, byte [rsi+1]       ; byte1
    movzx r10, byte [rsi+2]      ; byte2

    ; idx0 = byte0 >> 2
    mov al, r8b
    shr al, 2
    xlat_b64 rbx, al
    mov [rdi], al

    ; idx1 = (byte0 & 0x03) << 4 | byte1 >> 4
    mov al, r8b
    and al, 0x03
    shl al, 4
    mov dl, r9b
    shr dl, 4
    or al, dl
    xlat_b64 rbx, al
    mov [rdi+1], al

    ; idx2 = (byte1 & 0x0F) << 2 | byte2 >> 6
    mov al, r9b
    and al, 0x0F
    shl al, 2
    mov dl, r10b
    shr dl, 6
    or al, dl
    xlat_b64 rbx, al
    mov [rdi+2], al

    ; idx3 = byte2 & 0x3F
    mov al, r10b
    and al, 0x3F
    xlat_b64 rbx, al
    mov [rdi+3], al

    add rsi, 3
    add rdi, 4
    add rcx, 3
    jmp .enc_loop

.enc_tail:
    mov rax, r15
    sub rax, rcx                ; rax = 0, 1, or 2 bytes remaining
    cmp rax, 0
    je .enc_finish
    cmp rax, 1
    je .enc_one_left

    ; --- 2 bytes remaining: produces 3 chars + 1 '=' pad ---
    movzx r8, byte [rsi]
    movzx r9, byte [rsi+1]

    mov al, r8b
    shr al, 2
    xlat_b64 rbx, al
    mov [rdi], al

    mov al, r8b
    and al, 0x03
    shl al, 4
    mov dl, r9b
    shr dl, 4
    or al, dl
    xlat_b64 rbx, al
    mov [rdi+1], al

    mov al, r9b
    and al, 0x0F
    shl al, 2
    xlat_b64 rbx, al
    mov [rdi+2], al

    mov byte [rdi+3], '='
    add rdi, 4
    jmp .enc_finish

.enc_one_left:
    ; --- 1 byte remaining: produces 2 chars + 2 '=' pad ---
    movzx r8, byte [rsi]

    mov al, r8b
    shr al, 2
    xlat_b64 rbx, al
    mov [rdi], al

    mov al, r8b
    and al, 0x03
    shl al, 4
    xlat_b64 rbx, al
    mov [rdi+1], al

    mov byte [rdi+2], '='
    mov byte [rdi+3], '='
    add rdi, 4

.enc_finish:
    ; trailing newline for clean terminal/pipe output
    mov byte [rdi], 10
    inc rdi
    lea rax, [rel out_buf]
    sub rdi, rax                 ; rdi = total output length
    jmp write_output

; =====================================================================
; DECODE: 4 Base64 characters -> 3 output bytes via lookup table.
; Stops at '=' padding, EOF, or first invalid character.
; =====================================================================
do_decode:
    lea rsi, [rel in_buf]
    lea rdi, [rel out_buf]
    lea rbx, [rel b64_decode_tbl]
    xor rcx, rcx                 ; rcx = input bytes consumed
    xor r12, r12                 ; r12 = count of valid chars in current quad (0-3)
    xor r13, r13                 ; r13 = accumulator for the current quad's bits

.dec_loop:
    cmp rcx, r15
    jge .dec_finish
    movzx rax, byte [rsi+rcx]
    inc rcx

    cmp al, '='                  ; padding marks end of data
    je .dec_finish
    cmp al, 10                   ; skip newline
    je .dec_loop
    cmp al, 13                   ; skip carriage return
    je .dec_loop

    movzx rdx, byte [rbx+rax]    ; table lookup: ASCII -> 6-bit value
    cmp dl, 0xFF
    je .dec_loop                 ; silently skip any other non-alphabet byte

    shl r13, 6
    or r13, rdx
    inc r12
    cmp r12, 4
    jl .dec_loop

    ; We have 4 full sextets (24 bits) in r13 -> emit 3 bytes, MSB first
    mov rax, r13
    shr rax, 16
    mov [rdi], al
    mov rax, r13
    shr rax, 8
    mov [rdi+1], al
    mov al, r13b
    mov [rdi+2], al
    add rdi, 3
    xor r12, r12
    xor r13, r13
    jmp .dec_loop

.dec_finish:
    cmp r12, 0
    je .dec_done
    cmp r12, 2
    jl .dec_done                 ; 1 leftover char can't decode to a byte

    je .dec_two_leftover

    ; 3 leftover chars (18 bits) -> emit 2 bytes
    shl r13, 6                   ; pad to 24 bits total (as if 4th sextet = 0)
    mov rax, r13
    shr rax, 16
    mov [rdi], al
    mov rax, r13
    shr rax, 8
    mov [rdi+1], al
    add rdi, 2
    jmp .dec_done

.dec_two_leftover:
    ; 2 leftover chars (12 bits) -> emit 1 byte
    shl r13, 12                  ; pad to 24 bits total
    mov rax, r13
    shr rax, 16
    mov [rdi], al
    inc rdi

.dec_done:
    lea rax, [rel out_buf]
    sub rdi, rax                 ; rdi = total output length
    jmp write_output

; =====================================================================
; write_output: rdi = number of bytes in out_buf to write to stdout
; =====================================================================
write_output:
    mov rdx, rdi                 ; length
    lea rsi, [rel out_buf]
    mov rdi, 1                   ; fd 1 = stdout
    mov rax, SYS_write
    syscall

    mov rax, SYS_exit
    xor rdi, rdi
    syscall

section .data
decode_mode: db 0                ; 0 = encode (default), 1 = decode (-d)
