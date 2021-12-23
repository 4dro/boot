
cpu 286
bits 16

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
		pop bx
		pop ds
		add bx, invalid_load
		jmp print_exit
align_ok:
		; get segment address
		shr ax, 4
		add ax, bx

		mov ds, ax
		mov es, ax


press_key_and_reboot:
		int 16h
		int 19h

print_exit:
		jmp press_key_and_reboot

greetings	db	'OS loader loaded', 0
invalid_load	db	'', 0