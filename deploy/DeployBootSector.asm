BITS 32

STD_INPUT_HANDLE	equ -10
STD_OUTPUT_HANDLE	equ -11
STD_ERROR_HANDLE	equ -12

INVALID_HANDLE_VALUE	equ -1

extern GetCommandLineA
extern GetStdHandle
extern ExitProcess
extern WriteConsoleA

section code

start:
			cld
			push dword STD_ERROR_HANDLE
			call GetStdHandle
			mov [error_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
            je err_exit

			push dword STD_OUTPUT_HANDLE
			call GetStdHandle
			mov [output_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
            je err_exit

; expecting DeployBootSector.exe [-d <logical drive>] <boot file>

			call GetCommandLineA
			mov	ebx, eax
skip_name:
			mov al, [ebx]
			inc ebx
			cmp al, 20h
			ja skip_name
			cmp al, 0
			je no_arguments
skip_space:
			inc ebx
			mov al, [ebx]
			cmp al, 0
			je no_arguments
            cmp al, 20h
			jbe skip_space

			cmp al, '-'
			jne no_drive_specified
			cmp byte [ebx+1], 'd'
			jne invalid_arguments

no_drive_specified:
			; ebx -> file name

			xor eax, eax
			push eax
			call ExitProcess

no_arguments:
			mov eax, [output_handle]
			mov edx, no_filename_msg
			mov ecx, no_filename_end - no_filename_msg
			call print_message

print_usage_exit:
			mov eax, [output_handle]
			mov edx, usage_msg
			mov ecx, usage_msg_end - usage_msg
			call print_message

err_exit:
			push dword 1
			call ExitProcess

invalid_arguments:		; ebx -> cmd arguments
			mov edi, err_msg_buffer
			mov esi, invalid_arguments_msg
			mov ecx, invalid_arguments_end - invalid_arguments_msg
			rep movsb

copy_loop:
			mov al, [ebx]
			mov [edi], al
			inc edi
			inc ebx
			cmp edi, err_msg_buffer_end
			jae too_long
			cmp al, 0
            jne copy_loop
too_long:
			mov eax, [output_handle]
			mov edx, err_msg_buffer
			mov ecx, edi
			sub ecx, err_msg_buffer
			call print_message
			jmp print_usage_exit
			
print_message:
			push dword 0
			push chars_written
			push ecx	; size
			push edx	; string
			push eax	; handle
			call WriteConsoleA
			test eax, eax
			jz err_exit
			ret

section .data
error_handle	dd	0
output_handle	dd	0
chars_written	dd	0
invalid_arguments_msg	db	'Invalid arguments: '
invalid_arguments_end:
no_filename_msg	db	'No boot sector file specified.'
no_filename_end:
usage_msg	db	0Dh, 0Ah, 'Expecting: DeployBootSector.exe [-d <logical drive>] <boot sector file>'
usage_msg_end:
drive_wanted	db	0

section .bss
err_msg_buffer	db 512 dup(?)
err_msg_buffer_end: