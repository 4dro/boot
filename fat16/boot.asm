CPU 286
BITS 16

segment	'code'

OUR_ADDRESS			equ	7C00h

var_data_start		equ	-0Ah
var_last_fat_sector	equ	-6
var_reserved		equ	-4

		jmp	short actual_start
; -------------------------------------------------------------------------
			db 90h			; nop -	not used
os_name				db 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'
sector_size			dw 200h
sec_per_cluster		db 1
reserved_sectors	dw 1
num_of_fats			db 2
root_file_entries	dw 0E0h
total_sect_low		dw 0B40h
media_type			db 0F0h
fat_size			dw 9
sec_per_track		dw 12h
num_heads			dw 2
hidden_sectors		dd 0
total_sect_large	dd 0
drive				db 0
not_used			db 0
nt_signature		db 29h
volume_serial		dd 12345678h
disk_label			db ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '
fs_name				db 'F', 'A', 'T', '1', '2', ' ', ' ', ' '
; ------------------------------------------------------------------------

actual_start:
			xor	cx, cx

			mov		ss, cx
			mov		sp, OUR_ADDRESS
			mov		bp, sp
			mov		es, cx
			mov		ds, cx
			mov		ah, 41h
			mov		bx, 55AAh
			mov		bp[byte drive], dl	; rely on drive number sent in dl
			int		13h		; DISK - check ext read	support
			jb		short no_ext_bios
			and		cl, 1
			jz		short no_ext_bios
			mov		byte [bios_read_command + 2	+ OUR_ADDRESS], 42h

no_ext_bios:
			xor		cx, cx
			mov		al, byte bp[byte num_of_fats]
			cbw
			cld
			mul		word bp[byte fat_size]
			xchg	ax, bx
			xchg	si, dx		; si:bx	-> fat size in sectors
			mov		ax, word bp[byte reserved_sectors]
			cwd
			add		ax, word bp[byte hidden_sectors]
			adc		dx, word bp[byte hidden_sectors+2]
			push	dx		; put into var_reserved
			push	ax
			add		ax, bx
			adc		dx, si
			mov		si, word bp[byte root_file_entries]
			push	ax		; init var_last_fat_sector with	root start sector (invalid)
			push	dx		; put root start (dx:ax) into var_datastart
			push	ax
			pusha
			xchg	ax, si
			cwd
			shl		ax, 5
			mov		bx, word bp[byte sector_size]
			add		ax, bx
			dec		ax
			div		bx
			add		word bp[byte var_data_start], ax
			adc		word bp[byte var_data_start + 2],	cx
	;calculate total number	of data	clusters
			mov		ax, word bp[byte total_sect_low]
			or		ax, word bp[byte total_sect_large]
			mov		dx, word bp[byte total_sect_large + 2]
			sub		ax, word bp[byte var_data_start]
			sbb		dx, word bp[byte var_data_start + 2]
			add		ax, word bp[byte hidden_sectors]
			adc		dx, word bp[byte hidden_sectors + 2]
			mov		cl, byte bp[byte sec_per_cluster]
			div		cx		; get number of	clusters
			cmp		ax, 0FF5h
			jb		short its_fat12
			add		byte [fat_type_jump	+ 1 + OUR_ADDRESS], fat16_continue - fat12_continue

its_fat12:
			popa		; si - number of root entries
						; dx:ax	- root start sector
						; cx - 0

read_root:
			mov		bx, 8600h
			mov		di, bx
			call	read_one_sector

next_file:
			cmp		[di], cl
			jz		short file_not_found
			pusha
			mov		cl, 11
			mov		si, loader_file_name + OUR_ADDRESS
			repe	 cmpsb
			popa
			jz		short loader_found
			dec		si
			jz		short file_not_found
			add		di, 20h
			cmp		di, bx
			jb		short next_file
			jmp		short read_root
; -------------------------------------------------------------------

loader_found:
			mov		ax, [di+1Ah]	; fist cluster start in	file record
			mov		di, 2000h	; start	address	(segment) to load file to
			push	di
			push	cx

read_loader_cluster:
			push	ax
			dec		ax
			dec		ax
			mov		cl, byte bp[byte sec_per_cluster]
			mul		cx
			add		ax, word bp[byte var_data_start]
			adc		dx, word bp[byte var_data_start + 2]
			push	es
			mov		es, di
			xor		bx, bx
			call	read_sectors
			pop		es
			shr		bx, 4
			add		di, bx
			pop		ax
			xor		dx, dx

fat_type_jump:
			jmp		short fat12_continue

fat12_continue:
			mov		bx, ax
			shr		bx, 1
			jnc		short lower_half_byte
			call	next_cluster_fat12
			shr		ax, 4
			jmp		short check_last_fat12
; ------------------------------------------------------------------------

lower_half_byte:
			call	next_cluster_fat12
			and		ax, 0FFFh

check_last_fat12:
			cmp		ax, 0FF8h
			jmp		short is_last_cluster
; ---------------------------------------------------------------------------

fat16_continue:
			add		ax, ax
			adc		dx, cx
			call	next_cluster_fat16
			cmp		ax, 0FFF8h

is_last_cluster:
			jb		short read_loader_cluster
			mov		dl, bp[byte drive]
			retf			; jump to 2000:0 - start of the	loader
; -------------------------------------------------------------------------------

file_not_found:
			mov		al, missing_file_msg - 100h

message_exit:
			mov		ah, 7Dh
			xchg	ax, si

print_char:
			lodsb
			cbw
			inc		ax
			js		short print_replace_disk
			dec		ax
			jz		short wait_exit
			mov		ah, 0Eh		; video	- display char and move	cursor;	al-char
			mov		bx, 7		; color	7, page	0
			int		10h
			jmp		short print_char
; --------------------------------------------------------------------------------

print_replace_disk:
			mov		al, replace_disk_msg - 100h ; "\r\nReplace the disk"
			jmp		short message_exit
; ---------------------------------------------------------------------------
disk_error_msg		db 0Dh,	0Ah, 'Disk error'
; ---------------------------------------------------------------------------

wait_exit:
			int	16h		; KEYBOARD -
			int	19h		; DISK BOOT
					; causes reboot	of disk	system
; --------------------------------------------------------------------------
missing_file_msg	 db 0Dh, 0Ah, 'Missing '

loader_file_name	 db 'NTLDR', 6 dup(' ')

; ---------------------------------------------------------------------------

disk_error_exit:
			mov		al, disk_error_msg - 100h
			jmp		short message_exit
; --------------------------------------------------------------------------

read_one_sector:

			inc		cx

read_sectors:
			pusha			; Read one sector:
						; es:bx	-> buffer
						; dx:ax	- address of the sector
						; cx - number of sectors to read
			push	ds
			push	ds
			push	dx
			push	ax		; 8byte	absolute number	of sector
			push	es
			push	bx		; address to read to
			push	1		; num sectors
			push	10h		; 42h -	stucture size
					; DAP block
			xchg	ax, cx		; save lower address to	cx
			mov	ax, word bp[byte sec_per_track]
			xchg	ax, si
			xchg	ax, dx		; higher -> ax
			cwd
			div	si		; higher address / sectors per track
			xchg	ax, cx		; store	higher result in cx
			div	si		; lower	address	/ sectors per track
			inc	dx
			xchg	cx, dx		; cx - remainder + 1, dx - higher result
			div	word bp[byte num_heads]
			mov	dh, dl		; dh - head (remainder of division)
			mov	ch, al
			ror	ah, 2
			or	cl, ah

bios_read_command:
			mov	ax, 201h
			mov	si, sp		; pointer to DAP packet	in stack
			mov	dl, bp[byte drive]
			int	13h		; DISK - READ SECTORS INTO MEMORY
					; AL = number of sectors to read, CH = track, CL = sector
					; DH = head, DL	= drive, ES:BX -> buffer to fill
					; Return: CF set on error, AH =	status,	AL = number of sectors read
			popa
			popa
			jb	short disk_error_exit
			inc	ax		; increase read	address
			jnz	short no_addr_overflow
			inc	dx

no_addr_overflow:
			add	bx, word bp[byte sector_size]
			loop	read_sectors
			retn
; ----------------------------------------------------------------------------

next_cluster_fat12:

			add	ax, bx		; bx = ax / 2

next_cluster_fat16:
			mov	bx, OUR_ADDRESS + 200h
			div	word bp[byte sector_size]
			lea	si, [bx+1]
			add	si, dx
			cwd
			add	ax, word bp[byte var_reserved]
			adc	dx, word bp[byte var_reserved + 2]
			cmp	ax, bp[byte var_last_fat_sector]
			jz	short already_read
			mov	bp[byte var_last_fat_sector], ax

read_one_more:
			call	read_one_sector

take_fat_record:
			cmp	si, bx
			jnb	short read_one_more
			dec	si
			lodsw			; read next cluster word
			retn
; ----------------------------------------------------------------------------

already_read:
			add	bx, word bp[byte sector_size]
			inc	ax
			jnz	short take_fat_record
			inc	dx
			jmp	short take_fat_record
; ---------------------------------------------------------------------------
replace_disk_msg	db 0Dh,0Ah,'Replace the disk',0
		db 'DROOPY1', 0
		db 55h,	0AAh
