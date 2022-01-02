
cpu 286
bits 16

; make it 75Kb - more than any cluster size
SECTORS_OCCUPY	equ	150
; any number is OK for signature
SIGNATURE		equ 0F629h

segment code
start:
        ; dl - boot drive
        ; cs:ip our absolute address

        ; expecting we are loaded at 2000:0
        ; but need to check this (could be loaded by another bootloader)

        push cs
        pop bx

        call get_ip
get_ip:
        pop ax
        sub ax, get_ip

        ; bx:ax -> absolute address of start:
        test ax, 0Fh
        jz align_ok
        ; lame bootloader loaded our program not on the segment boundary
        ; should not happen - we cannot continue
        push bx
        push ax
        pop si
        pop ds
        add si, invalid_load
        call print_string
        jmp press_key_and_reboot

align_ok:
        ; get base segment address
        shr ax, 4
        add ax, bx

        mov ds, ax
        mov es, ax
        mov [base_address], ax

        ; convert our base address into hex string
        mov cx, 4
        mov di, addr_string + 3

address_to_hex:
        mov bx, ax
        shr ax, 4
        and bx, 0Fh
        mov dl, [bx + hex_chars]
        mov [di], dl
        dec di
        loop address_to_hex

        mov si, greetings
        call print_string

        mov si, loaded_at_addr
        call print_string

        ; begin checking if all the file is loaded to the momory
        xor cx, cx
        xor si, si
check_sector:
        inc cx
        add si, 512
        jnc no_overflow
        mov ax, es
        add ax, 1000h
        mov es, ax
no_overflow:
        cmp word es:[si], SIGNATURE
        jne sect_failed
        cmp word es:[si + 2], cx
        jne sect_failed
        cmp cx, SECTORS_OCCUPY - 1
        jb check_sector

        ; all sectors passed
        mov si, all_loaded_msg
        call print_string

press_key_and_reboot:
        mov ah, 0
        int 16h
        int 19h

; Display "Sector XX is NOT LOADED!"
sect_failed:
        mov bp, sp
        mov bx, 10
        mov ax, cx

more_digits:
        xor dx, dx
        div bx
        push dx
        test ax, ax
        jnz more_digits

        mov di, sector_str
take_digits:
        pop ax
        add ax, '0'
        mov [di], al
        inc di
        cmp bp, sp
        jne take_digits
        mov byte [di], 0

        mov si, sector_msg
        call print_string

        mov si, not_loaded_msg
        call print_string

        jmp press_key_and_reboot

; --------------------- Print string -------------------------------------------------
print_string:
        ; ds:si -> string
        mov al, [si]
        inc si
        test al, al
        jz string_ended
        mov ah, 0Eh		; video	- display char and move	cursor;	al-char
        mov bx, 7		; color	7, page	0
        int 10h
        jmp print_string
string_ended:
        ret

align 4
base_address	dw	0
hex_chars		db	'0123456789ABCDF'
greetings		db	'osloader has started', 0Dh, 0Ah, 0
invalid_load	db	'osloader is loaded out of segment boundary', 0Dh, 0Ah, 0
loaded_at_addr	db	'osloader is loaded at address: '
addr_string		db 4 dup(' '), 0Dh, 0Ah, 0
all_loaded_msg	db 'All program sectors are loaded into the memory.', 0Dh, 0Ah, 0
sector_msg		db 'Sector '
sector_str		db 4 dup(' '), 0
not_loaded_msg	db ' is NOT LOADED!', 0Dh, 0Ah, 0

; Make program size SECTORS_OCCUPY * 512
; and mark every sector with a signature
; to check every cluster of the program is correctly loaded

%assign sec_num 0
%rep SECTORS_OCCUPY
    dw SIGNATURE, sec_num
align 512, db 0
%assign sec_num sec_num + 1
%endrep