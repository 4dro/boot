BITS 32

SEM_FAILCRITICALERRORS	equ	1

STD_INPUT_HANDLE	equ -10
STD_OUTPUT_HANDLE	equ -11
STD_ERROR_HANDLE	equ -12

INVALID_HANDLE_VALUE	equ -1

extern CloseHandle
extern GetCommandLineA
extern GetDriveTypeA
extern GetDiskFreeSpaceExA
extern GetLogicalDrives
extern GetStdHandle
extern GetVolumeInformationA
extern ExitProcess
extern SetErrorMode
extern WriteConsoleA

section code

start:
			cld
			push STD_ERROR_HANDLE
			call GetStdHandle
			mov [error_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
            je err_exit

			push STD_OUTPUT_HANDLE
			call GetStdHandle
			mov [output_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
            je err_exit

			push dword SEM_FAILCRITICALERRORS
			call SetErrorMode
			mov [prev_err_mode], eax

			call parse_arguments
			test ebx, ebx
			jz args_ok

			mov esi, invalid_arguments_msg
			mov ecx, invalid_arguments_end - invalid_arguments_msg
			call print_complex
			jmp print_usage_exit

args_ok:
			mov ebx, drive_parameter
			mov esi, drive_specified_msg
			mov ecx, drive_specified_end - drive_specified_msg
			call print_complex

			mov ebx, save_file_name
			mov esi, save_file_msg
			mov ecx, save_file_end - save_file_msg
			call print_complex

			mov ebx, boot_file_name
			mov esi, file_used_msg
			mov ecx, file_used_end - file_used_msg
			call print_complex

			cmp byte [drive_parameter], 0
			je no_drive_specified
			cmp byte [drive_parameter + 1], 0
			je drive_specified

			mov ebx, drive_parameter
			mov esi, invalid_drive_msg
			mov ecx, invalid_drive_end - invalid_drive_msg
			call print_complex

no_drive_specified:
			call show_drives_info

drive_specified:
			push dword [prev_err_mode]
			call SetErrorMode

			xor eax, eax
			push eax
			call ExitProcess


print_usage_exit:
			mov eax, [output_handle]
			mov edx, usage_msg
			mov ecx, usage_msg_end - usage_msg
			call print_message

err_exit:
			push dword 1
			call ExitProcess

; ------------- get available drives ---------------------------------------------

show_drives_info:

			call GetLogicalDrives
			mov dl, 'A'
			mov ebx, available_drives
next_bit:
			test eax, 1
			jz no_drive
			mov byte [ebx], dl
			inc ebx
no_drive:
			inc dl
			shr eax, 1
			jnz next_bit
			sub ebx, available_drives
			mov [num_drives], ebx

			mov eax, [output_handle]
			mov edx, avail_drives_msg
			mov ecx, avail_drives_end - avail_drives_msg
			call print_message

			mov esi, 0
show_next_drive:
			cmp esi, [num_drives]
			jae no_more_drives

			mov al, available_drives[esi]
			mov [drive_path], al
			push dword drive_path
			call GetDriveTypeA
			cmp eax, 6
			jbe correct_type
			mov eax, 0
correct_type:
			mov edx, drive_types[eax * 4]
			mov al, [drive_path]
			mov [description_string + 4], al

			mov edi, description_string + 13
			mov ecx, drive_nodrive - drive_unknown
copy_type_str:
			mov al, [edx]
			mov [edi], al
			inc edx
			inc edi
			dec ecx
			jnz copy_type_str

			push dword 512
			push fs_name
			push file_system_flags
			push filename_size
			push fs_serial
			push dword 512
			push fs_volume_name
			push drive_path
			call GetVolumeInformationA
			test eax, eax
			jz info_error

			xor ecx, ecx
copy_volume:
			mov al, fs_name[ecx]
			cmp al, 0
			je name_ended
			mov ecx[description_string + 24], al
			inc ecx
			cmp ecx, 12
			jb copy_volume

name_ended:

info_error:
			push 0
			push total_drive_bytes
			push 0
			push drive_path
			call GetDiskFreeSpaceExA
			mov edx, drive_size_unknown
			test eax, eax
			jz no_total_size

			call convert_disk_size

			mov edx, drive_size_string
no_total_size:
			mov edi, description_string + 24 + 10
			mov ecx, 8

copy_drive_size:
			mov al, [edx]
			mov [edi], al
			inc edx
			inc edi
			dec ecx
			jnz copy_drive_size

			mov eax, [output_handle]
			mov edx, description_string
			mov ecx, description_str_end - description_string
			call print_message

			inc esi
			jmp show_next_drive

no_more_drives:
			ret

; -------------------- Parse arguments --------------------------------------------
; expecting DeployBootSector.exe [-d <logical drive>] [-r] [-w <boot file>]

parse_arguments:
			mov al, 0
			mov [boot_file_name], al
			mov [drive_parameter], al
			mov [save_file_name], al

			call GetCommandLineA
			mov	ebx, eax
			; skip program name
			mov edi, program_name
			call store_option

; -------------------- start arguments parsing ---------------------------------------------
next_argument:
			mov al, [ebx]
			cmp al, 0
			je no_arguments
			cmp al, '-'
			jne invalid_arguments
			mov al, [ebx + 1]
			cmp al, 0
			je invalid_arguments
			cmp al, 'd'
			je d_option
			cmp al, 'r'
			je r_option
			cmp al, 'w'
			jne invalid_arguments
w_option:
			add ebx, 2
			mov edi, boot_file_name
			call store_option
			jmp next_argument
d_option:
			add ebx, 2
			mov edi, drive_parameter
			call store_option
			jmp next_argument
r_option:
			add ebx, 2
			mov edi, save_file_name
			call store_option
			jmp next_argument

no_arguments:
			xor ebx, ebx
			ret

; -----------------------------------------------------------------------------
invalid_arguments:		; ebx -> cmd arguments
			ret

; -----------------------------------------------------------------------------
; ebx -> current cmd line position
; edi -> buffer to store the parameter (256 bytes)
; return
; ebx -> next non-blank argument
; al - next character (0 indicates the end)
store_option:
			xor edx, edx	; double quotes indicator
skip_leading_space:
			mov al, [ebx]
			inc ebx
			cmp al, 0
			je no_cmd_at_all
			cmp al, 20h
			jbe skip_leading_space
			dec ebx
			cmp byte [ebx], '"'
			jne skip_name
			inc edx
			inc ebx
skip_name:
			mov al, [ebx]
			inc ebx
			mov [edi], al
			inc edi
			cmp al, '"'
			je param_ended
			cmp al, 20h
			ja skip_name
			cmp al, 0
			je cmd_ended
			test edx, edx	; we are inside double quotes
			jnz skip_name
param_ended:
			xor edx, edx
skip_space:
			mov al, [ebx]
			inc ebx
			cmp al, 0
			je cmd_ended
            cmp al, 20h
			jbe skip_space

cmd_ended:
			mov byte [edi - 1], 0

no_cmd_at_all:
			dec ebx
			ret
; -----------------------------------------------------------------------------

; ebx -> null terminated second string
; esi -> first message
; ecx - first message size
print_complex:
			mov edi, err_msg_buffer
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
			ret

; -----------------------------------------------------------------------------
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

; ----------------------- Disk size human representaion --------------------------

convert_disk_size:
			mov eax, [total_drive_bytes + 4]
			test eax, eax
			jnz more_than_4G
			mov eax, [total_drive_bytes]
			cmp eax, 1024
			jae more_1K
			mov cl, 'b'
			jmp calc_done
more_1K:
			cmp eax, 1024 * 1024
			jae more_1M
			shr eax, 10
			adc eax, 0
			mov cl, 'K'
			jmp calc_done
more_1M:
			cmp eax, 1024 * 1024 * 1024
			jae more_1G
			shr eax, 20
			adc eax, 0
			mov cl, 'M'
			jmp calc_done
more_1G:
			shr eax, 30
			adc eax, 0
			mov cl, 'G'
			jmp calc_done
more_than_4G:
			cmp eax, 256
			jae more_than_1T
			shl eax, 2
			mov edx, [total_drive_bytes]
			rcl edx, 3
			adc eax, 0
			and edx, 3
			add eax, edx
			mov cl, 'G'
			jmp calc_done
more_than_1T:
			cmp eax, 256 * 1024
			jae more_than_1P
			shr eax, 8
			adc eax, 0
			mov cl, 'T'
			jmp calc_done
more_than_1P:
			shr eax, 18
			adc eax, 0
			mov cl, 'P'
calc_done:
			; eax - number, cl - suffix
			mov [drive_size_string + 7], cl
			mov byte [drive_size_string + 6], ' '
			mov edi, drive_size_string + 5
next_digit:
			xor edx, edx
			div dword [ten_divisor]
			add dl, '0'
			mov [edi], dl
			dec edi
			test eax, eax
			jnz next_digit

			mov al, ' '
pad_right:
			mov [edi], al
			dec edi
			cmp edi, drive_size_string
			jae pad_right
			ret

section .data
error_handle	dd	0
output_handle	dd	0
chars_written	dd	0
filename_size	dd	0
num_drives		dd	0
prev_err_mode	dd	0
ten_divisor		dd	10
file_system_flags	dd	0
fs_max_path		dd	0
fs_serial		dd	0
total_drive_bytes dd 0, 0


drive_types		dd	drive_unknown, drive_nodrive, drive_removable, drive_fixed,
				dd	drive_network, drive_cdrom, drive_ram
drive_unknown	db	'Unknown  '
drive_nodrive	db	'No drive '
drive_removable	db	'Removable'
drive_fixed		db	'Fixed    '
drive_network	db	'Network  '
drive_cdrom		db	'CD-ROM   '
drive_ram		db	'Ram disk '

invalid_arguments_msg	db	'Invalid arguments: '
invalid_arguments_end:
usage_msg	db	0Dh, 0Ah, 'DeployBootSector.exe [-d <logical drive>] [-r] [-w <boot sector file>]'
	db	0Dh, 0Ah, '-d <logical drive> - Drive name to work with, such as A,C'
	db	0Dh, 0Ah, '-r - Read (save) previous boot sector of the drive '
	db	0Dh, 0Ah, '-w <boot sector file> Deploy specified boot sector from the file to the selected drive'

usage_msg_end:
drive_specified_msg	db	'Drive requested: '
drive_specified_end:
save_file_msg	db	0Dh, 0Ah, 'File to save bootsector: '
save_file_end:
file_used_msg	db	0Dh, 0Ah, 'Boot sector file to write: '
file_used_end:
invalid_drive_msg	db	0dh, 0ah, 'Invalid drive letter: '
invalid_drive_end

avail_drives_msg	db	0Dh, 0Ah, 'Available drives:', 0Dh, 0Ah
	db	'  Name        Type      System       Size                 ', 0Dh, 0Ah
avail_drives_end:
description_string:
	db	'    C        Unknown                                      ', 0Dh, 0Ah
description_str_end:
drive_size_unknown	db '-', 15 dup(' ')
drive_size_string	db 8 dup(' ')
drive_path	db 'A:\', 0

drive_wanted	db	0

section .bss
available_drives	db 32 dup(?)
program_name	db	256 dup(?)
drive_parameter	db	256 dup(?)
save_file_name	db	256 dup(?)

fs_name			db 512 dup(?)
fs_volume_name	db 512 dup(?)
boot_file_name	db 512 dup(?)
err_msg_buffer	db 1024 dup(?)
err_msg_buffer_end: