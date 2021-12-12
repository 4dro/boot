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

; expecting DeployBootSector.exe [-d <logical drive>] [-r] [-w <boot file>]

			call GetCommandLineA
			mov	ebx, eax
			xor edx, edx	; double quotes indicator
			cmp byte [ebx], '"'
			jne skip_name
			inc edx
			inc ebx
skip_name:
			mov al, [ebx]
			inc ebx
			cmp al, '"'
			je skip_space
			cmp al, 20h
			ja skip_name
			cmp al, 0
			je no_arguments
			test edx, edx	; we are inside double quotes
			jnz skip_name
skip_space:
			mov al, [ebx]
			inc ebx
			cmp al, 0
			je no_arguments
            cmp al, 20h
			jbe skip_space
			dec ebx

; -------------------- arguments parsing ---------------------------------------------
			cmp al, '-'
			jne no_drive_specified
			cmp byte [ebx+1], 'd'
			jne invalid_arguments
			cmp byte [ebx+1], 0
			je invalid_arguments
			

no_drive_specified:
			; ebx -> file name expected
			xor ecx, ecx
			mov esi, ebx
			mov edi, boot_file_name
copy_filename:
			mov al, [ebx + ecx]
			mov [edi + ecx], al
			inc ecx
			cmp al, 20h
			ja copy_filename
			mov [filename_size], ecx
			cmp al, 0
			je cmd_ended
			mov byte [edi + ecx - 1], 0	; end filename
check_no_more:
			mov al, [ebx + ecx]
			inc ecx
			cmp al, 20h
			ja invalid_arguments
			cmp al, 0
			jne check_no_more
cmd_ended:
			mov ebx, boot_file_name
			mov esi, file_used_msg
			mov ecx, file_used_end - file_used_msg
			call print_complex

no_arguments:
; ------------- get available drives ---------------------------------------------
			push dword SEM_FAILCRITICALERRORS
			call SetErrorMode
			mov [prev_err_mode], eax

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
			mov edi, description_string + 24 + 12
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

; -----------------------------------------------------------------------------
invalid_arguments:		; ebx -> cmd arguments

			mov esi, invalid_arguments_msg
			mov ecx, invalid_arguments_end - invalid_arguments_msg
			call print_complex
			jmp print_usage_exit

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
			mov [drive_size_string + 15], cl
			mov byte [drive_size_string + 14], ' '
			mov edi, drive_size_string + 13
next_digit:		
			xor edx, edx
			div dword [ten_divisor]
			add dl, '0'
			mov [edi], dl
			dec edi
			test eax, eax
			jnz next_digit

			mov edx, drive_size_string
align_right:
			mov al, [edi]
			mov [edx], al
			inc edi
			inc edx
			cmp edx, drive_size_string + 32
			jb align_right
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
file_used_msg	db	'Using boot sector file: '
file_used_end:
avail_drives_msg	db	0Dh, 0Ah, 'Available drives:', 0Dh, 0Ah
	db	'  Name        Type      System       Size                 ', 0Dh, 0Ah
avail_drives_end:
description_string:
	db	'    C        Unknown                                      ', 0Dh, 0Ah
description_str_end:
drive_size_unknown	db '-', 15 dup(' ')
drive_size_string	db 32 dup(' ')
drive_path	db 'A:\', 0

drive_wanted	db	0

section .bss
available_drives	db 32 dup(?)
fs_name			db 512 dup(?)
fs_volume_name	db 512 dup(?)
boot_file_name	db 512 dup(?)
err_msg_buffer	db 1024 dup(?)
err_msg_buffer_end: