BITS 32

SEM_FAILCRITICALERRORS	equ	1

FILE_BEGIN		equ	0

FILE_ATTRIBUTE_NORMAL	equ	80h

ENABLE_PROCESSED_INPUT	equ		0001h
ENABLE_LINE_INPUT		equ		0002h
ENABLE_ECHO_INPUT		equ		0004h
ENABLE_INSERT_MODE		equ		0020h
ENABLE_QUICK_EDIT_MODE	equ		0040h

OUR_MODE	equ	ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT	| ENABLE_ECHO_INPUT | ENABLE_INSERT_MODE

GENERIC_WRITE	equ	40000000h
GENERIC_READ	equ 80000000h

FILE_SHARE_READ		equ	1
FILE_SHARE_WRITE	equ 2

CREATE_ALWAYS		equ	2
OPEN_EXISTING		equ	3

STD_INPUT_HANDLE	equ -10
STD_OUTPUT_HANDLE	equ -11
STD_ERROR_HANDLE	equ -12

INVALID_HANDLE_VALUE	equ -1

ERROR_FILE_NOT_FOUND	equ	2
ERROR_ACCESS_DENIED		equ	5

extern CloseHandle
extern CreateFileA
extern GetCommandLineA
extern GetConsoleMode
extern GetDriveTypeA
extern GetDiskFreeSpaceExA
extern GetLastError
extern GetLogicalDrives
extern GetStdHandle
extern GetVolumeInformationA
extern ExitProcess
extern ReadConsoleA
extern ReadFile
extern SetConsoleMode
extern SetErrorMode
extern SetFilePointer
extern WriteConsoleA
extern WriteFile

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

			push STD_INPUT_HANDLE
			call GetStdHandle
			mov [input_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
            je err_exit

			push dword SEM_FAILCRITICALERRORS
			call SetErrorMode
			mov [prev_err_mode], eax

			push old_console_mode
			push dword [input_handle]
			call GetConsoleMode
			test eax, eax
			jz err_exit

			push OUR_MODE
			push dword [input_handle]
			call SetConsoleMode
			test eax, eax
			jz err_exit

			call parse_arguments
			test ebx, ebx
			jz args_ok

			mov esi, invalid_arguments_msg
			mov ecx, invalid_arguments_end - invalid_arguments_msg
			call print_complex
			jmp print_usage_exit

args_ok:

			cmp byte [drive_parameter], 0
			jne drive_specified

			call show_drives_info

			mov eax, [output_handle]
			mov edx, select_drive_msg
			mov ecx, select_drive_end - select_drive_msg
			call print_message

			push 0
			push num_chars_read
			push 256
			push console_read_buffer
			push dword [input_handle]
			call ReadConsoleA

			mov ecx, [num_chars_read]
			mov esi, console_read_buffer
			mov edi, drive_parameter
copy_input:
			lodsb
			cmp al, 0Dh
			je eol_met
			stosb
			loop copy_input
eol_met:
			mov byte [edi], 0

drive_specified:

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

			mov al, [drive_parameter]
			and al, 0DFh	; to uppercase
			mov [drive_wanted], al
			cmp al, 'A'
			jb wrong_drive
			cmp al, 'Z'
			ja wrong_drive
			cmp byte [drive_parameter + 1], 0
			je drive_ok

wrong_drive:
			mov ebx, drive_parameter
			mov esi, invalid_drive_msg
			mov ecx, invalid_drive_end - invalid_drive_msg
			call print_complex

			jmp err_exit

drive_ok:
			; try to read bootsector
			push 0
			push 0			; flags and attributes
			push OPEN_EXISTING
			push 0			; lpSecurityAttributes
			push FILE_SHARE_READ | FILE_SHARE_WRITE
			push GENERIC_READ
			push device_name
			call CreateFileA
			mov [drive_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
			jne successfully_opened

			call print_last_error
			jmp normal_exit

successfully_opened:
			push FILE_BEGIN
			push 0
			push 0
			push dword [drive_handle]
			call SetFilePointer
			test eax, eax
			jnz error_occured

			push 0
			push bytes_read
			push 512
			push sector_buffer
			push dword [drive_handle]
			call ReadFile
			test eax, eax
			jz error_occured
			cmp dword [bytes_read], 512
			je successfully_read

error_occured:
			call print_last_error

			push dword [drive_handle]
			call CloseHandle
			jmp normal_exit

successfully_read:
			mov byte [sector_read], 1

			push dword [drive_handle]
			call CloseHandle

			mov al, [boot_file_name]
			or al, [save_file_name]
			jz normal_exit

			; need to save boot sector to the file
			cmp byte [save_file_name], 0
			jne name_provided

			mov esi, default_save_file
			mov edi, save_file_name
copy_default_name:
			mov al, [esi]
			mov [edi], al
			inc esi
			inc edi
			test al, al
			jnz copy_default_name

name_provided:

			push 0
			push FILE_ATTRIBUTE_NORMAL			; flags and attributes
			push CREATE_ALWAYS
			push 0			; lpSecurityAttributes
			push 0			; share mode
			push GENERIC_WRITE
			push save_file_name
			call CreateFileA
			cmp eax, INVALID_HANDLE_VALUE
			je normal_exit

			mov [save_file_handle], eax

			push 0
			push bytes_read
			push 512
			push sector_buffer
			push dword [save_file_handle]
			call WriteFile

			push dword [save_file_handle]
			call CloseHandle

; ------------------- Check if we need to deploy ------------------------------------

			cmp byte [boot_file_name], 0
			je normal_exit

			cmp byte [sector_buffer + 10h], 0	; number of fats, zero on ntfs
			je not_a_fat

			; cmp byte [sector_buffer + 26h], 29h	; signature for fat12/16
			; jne not_a_fat
			; cmp byte [sector_buffer + 42h], 29h	; signature for fat32
			; jne not_a_fat

its_fat_on_drive:
			push 0
			push FILE_ATTRIBUTE_NORMAL			; flags and attributes
			push OPEN_EXISTING
			push 0			; lpSecurityAttributes
			push FILE_SHARE_READ			; share mode
			push GENERIC_READ
			push boot_file_name
			call CreateFileA
			mov [boot_file_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
			jne opened_write_file

			call print_last_error
			jmp err_exit

opened_write_file:

			push 0
			push bytes_read
			push 516
			push write_buffer
			push dword [boot_file_handle]
			call ReadFile
			test eax, eax
			jz boot_file_failed

			cmp dword [bytes_read], 512
			jne boot_file_failed

			cmp word [write_buffer + 1FEh], 0AA55h
			je boot_file_ok

boot_file_failed:
			call print_last_error
			push dword [boot_file_handle]
			call CloseHandle

			jmp err_exit
boot_file_ok:
			push dword [boot_file_handle]
			call CloseHandle

; --------------- Merge the content of boot sector with the file ---------------------------

			; Copy Bios parameters block for FAT 16 (03 - 3E)
			mov edi, write_buffer + 3
			mov esi, sector_buffer + 3
			mov ecx, 3Eh - 3
			rep movsb

;---------------- Write the bootsector file ---------------------------------------------

			push 0			; hTemplate
			push 0			; flags and attributes
			push OPEN_EXISTING
			push 0			; lpSecurityAttributes
			push FILE_SHARE_WRITE
			push GENERIC_WRITE
			push device_name
			call CreateFileA
			mov [drive_handle], eax
			cmp eax, INVALID_HANDLE_VALUE
			jne opedned_for_write

			call print_last_error
			jmp normal_exit

opedned_for_write:

			push FILE_BEGIN
			push 0
			push 0
			push dword [drive_handle]
			call SetFilePointer
			test eax, eax
			jnz write_error

			push 0			; overlapped
			push bytes_written
			push 512
			push write_buffer
			push dword [drive_handle]
			call WriteFile
			test eax, eax
			jz write_error
			cmp dword [bytes_written], 512
			jne write_error

			push dword [boot_file_handle]
			call CloseHandle

			mov eax, [output_handle]
			mov edx, successfully_written
			mov ecx, successfully_written_end - successfully_written
			call print_message
			jmp normal_exit

write_error:
			call print_last_error
			push dword [boot_file_handle]
			call CloseHandle

not_a_fat:

normal_exit:

			push dword [old_console_mode]
			push dword [input_handle]
			call SetConsoleMode

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
			jmp normal_exit

err_exit:
			push dword [old_console_mode]
			push dword [input_handle]
			call SetConsoleMode

			push dword [prev_err_mode]
			call SetErrorMode
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

			xor ecx, ecx
			mov edi, fs_unknown
			test eax, eax
			jz copy_volume
			mov edi, fs_name
copy_volume:
			mov al, [edi + ecx]
			cmp al, 0
			je pad_name_spaces
			mov [ecx + description_string + 24], al
			inc ecx
			cmp ecx, 12
			jb copy_volume

pad_name_spaces:
			lea edi, [ecx + description_string + 24]
			mov al, ' '
			neg ecx
			add ecx, 12
			rep stosb

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

; ------------------ Print last error ------------------------------------------
print_last_error:
			call GetLastError
			mov ebx, eax
			mov ecx, 8
letter_loop:
			mov eax, ebx
			and eax, 0Fh
			mov al, [hex_letters + eax]
			shr ebx, 4
			mov [last_error_code + ecx - 1], al
			loop letter_loop

			mov eax, [output_handle]
			mov edx, last_error_msg
			mov ecx, last_error_end - last_error_msg
			call print_message

			ret

section .data
error_handle	dd	0
output_handle	dd	0
input_handle	dd	0

drive_handle	dd	0
old_console_mode	dd	0
num_chars_read	dd	0
chars_written	dd	0
filename_size	dd	0
num_drives		dd	0
prev_err_mode	dd	0
ten_divisor		dd	10
file_system_flags	dd	0
fs_max_path		dd	0
fs_serial		dd	0
total_drive_bytes dd 0, 0
bytes_read		dd	0
bytes_written	dd	0
save_file_handle	dd	0
boot_file_handle	dd	0

drive_types		dd	drive_unknown, drive_nodrive, drive_removable, drive_fixed,
				dd	drive_network, drive_cdrom, drive_ram
drive_unknown	db	'Unknown  '
drive_nodrive	db	'No drive '
drive_removable	db	'Removable'
drive_fixed		db	'Fixed    '
drive_network	db	'Network  '
drive_cdrom		db	'CD-ROM   '
drive_ram		db	'Ram disk '

sector_read		db	0
invalid_arguments_msg	db	'Invalid arguments: '
invalid_arguments_end:
usage_msg	db 'DeployBootSector.exe [-d <logical drive>] [-r <save file>] [-w <boot sector file>]', 0Dh, 0Ah,
	db 'Writes a FAT boot sector taken from <boot sector file> to the specified <logical drive>', 0Dh, 0Ah,
	db 'Existing boot sector is saved in the <save file>', 0Dh, 0Ah,
	db	'-d <logical drive> - Drive name to work with, such as A,C,E', 0Dh, 0Ah,
	db	'-r <save file>- Read (save) previous boot sector of the drive ', 0Dh, 0Ah,
	db	'-w <boot sector file> Deploy specified boot sector from the file to the selected drive', 0Dh, 0Ah,

usage_msg_end:
drive_specified_msg	db	'Drive requested: '
drive_specified_end:
save_file_msg	db	0Dh, 0Ah, 'File to save bootsector: '
save_file_end:
file_used_msg	db	0Dh, 0Ah, 'Boot sector file to write: '
file_used_end:
invalid_drive_msg	db	0Dh, 0Ah, 'Invalid drive letter: '
invalid_drive_end:
select_drive_msg	db 'Please select the drive name (A-Z) and press Enter', 0Dh, 0Ah
select_drive_end:
hex_letters	db	'01234567890ABCDF'
default_save_file	db	'old.bin', 0
successfully_written	db	'Boot sector has been successfully written', 0Dh, 0Ah
successfully_written_end:
last_error_msg	db	'Last error: '
last_error_code	db	8 dup(' '), 0Dh, 0Ah
last_error_end:

avail_drives_msg	db	0Dh, 0Ah, 'Available drives:', 0Dh, 0Ah
	db	'  Name        Type      System       Size                 ', 0Dh, 0Ah
avail_drives_end:
description_string:
	db	'    C        Unknown                                      ', 0Dh, 0Ah
description_str_end:
drive_size_unknown	db '-', 15 dup(' ')
drive_size_string	db 8 dup(' ')
fs_unknown	db 'Unknown', 0
drive_path	db 'A:\', 0

device_name		db	'\\.\'
drive_wanted	db	'A:', 0

section .bss
available_drives	db 32 dup(?)
program_name	db	256 dup(?)
drive_parameter	db	256 dup(?)
save_file_name	db	256 dup(?)
sector_buffer	db	512 dup(?)
write_buffer	db	516 dup(?)

fs_name			db 512 dup(?)
fs_volume_name	db 512 dup(?)
boot_file_name	db 512 dup(?)
err_msg_buffer	db 1024 dup(?)
err_msg_buffer_end:
console_read_buffer	db	256 dup(?)