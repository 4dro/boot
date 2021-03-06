CPU 286
BITS 16

segment	'code'

OUR_ADDRESS         equ     7C00h
ROOT_LOAD_ADDR      equ     OUR_ADDRESS + 0A00h
FAT_CACHE_ADDR      equ     OUR_ADDRESS + 200h

SEG_ADDRESS_TO_LOAD equ     2000h

data_start          equ     -0Ah
cached_fat_sector   equ     -6
fat_start           equ     -4

            jmp    short actual_start
cluster_mask        db  0Fh
; --------------- Bios Parameters Block ------------------------------------
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
actually_read:
not_used			db 0
nt_signature		db 29h
volume_serial		dd 12345678h
disk_label			db ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '
fs_name				db 'F', 'A', 'T', '1', '2', ' ', ' ', ' '

; ------------------------------------------------------------------------

actual_start:
            xor     ax, ax

            mov     ss, ax
            mov     sp, OUR_ADDRESS
            mov     bp, sp
            mov     es, ax
            mov     ds, ax

            mov     ah, 41h				; DISK - check ext read	support
            mov     bx, 55AAh			; signature
            mov     bp[byte drive], dl	; rely on drive number sent in dl
            int     13h
            jc      short no_ext_bios
            and     cl, 1
            jz      short no_ext_bios
            mov     word [OUR_ADDRESS + to_be_changed + 1], 0EB42h  ; change command to 42h, and unconditional jump

no_ext_bios:
            cld
; calculate data start secotor
            xor     cx, cx
            mov     al, byte bp[byte num_of_fats]
            cbw
            mul     word bp[byte fat_size]		; dx:ax - fats size in sectors
            xchg    ax, bx
            mov     si, dx                      ; si:bx -> fat size in sectors
            mov     ax, word bp[byte reserved_sectors]
            cwd
            add     ax, word bp[byte hidden_sectors]
            adc     dx, word bp[byte hidden_sectors+2]
            push    dx              ; put into fat_start
            push    ax
            add     ax, bx          ; + fat size
            adc     dx, si
            mov     si, word bp[byte root_file_entries]
            push    ax      ; init cached_fat_sector with	root start sector (invalid)
            push    dx
            push    ax      ; put root start (dx:ax) into var_datastart
            pusha
            xchg    ax, si
            cwd
            shl     ax, 5	; multiply by file entry size (32)
            mov     bx, word bp[byte sector_size]
            add     ax, bx
            dec     ax
            div     bx		; calculate number of sectors needed for root folder (x + sector_size - 1) / sector size
            add     word bp[byte data_start], ax        ; add root size to data_start
            adc     word bp[byte data_start + 2], cx

; calculate total number	of data	clusters
            mov     ax, word bp[byte total_sect_low]
            or      ax, word bp[byte total_sect_large]
            mov     dx, word bp[byte total_sect_large + 2]
            sub     ax, word bp[byte data_start]
            sbb     dx, word bp[byte data_start + 2]
            add     ax, word bp[byte hidden_sectors]
            adc     dx, word bp[byte hidden_sectors + 2]
            mov     cl, byte bp[byte sec_per_cluster]
            div     cx		; get number of	clusters

; fat type is defined by number of clusters
            cmp     ax, 0FF5h
            jb      short its_fat12
            mov     byte bp[byte cluster_mask], 0FFh

its_fat12:
            popa        ; si - number of root entries
                        ; dx:ax	- root start sector
                        ; cx - 0

read_root:
            mov     bx, ROOT_LOAD_ADDR
            mov     di, bx
            call    read_one_sector

next_file:
            cmp     [di], cl
            je      short file_not_found
            pusha
            mov     cl, 11
            mov     si, loader_file_name + OUR_ADDRESS
            repe    cmpsb
            popa
            je      short loader_found
            dec     si
            jz      short file_not_found
            add     di, 20h         ; file entry size in directory
            cmp     di, bx
            jb      short next_file
            jmp     short read_root
; -------------------------------------------------------------------
file_not_found:
            mov     al, missing_file_msg - 100h
            jmp     short message_exit

loader_found:
            mov     ax, [di + 1Ah]          ; fist cluster of the file
            mov     di, SEG_ADDRESS_TO_LOAD ; start address (segment) to load file to

            push    di      ; save the address to jump to
            push    cx      ; later we will return far to SEG_ADDRESS_TO_LOAD:0

read_loader_cluster:
            push	ax
            dec		ax
            dec		ax
            mov		cl, byte bp[byte sec_per_cluster]
            mul		cx
            add		ax, word bp[byte data_start]
            adc		dx, word bp[byte data_start + 2]
            push	es
            mov		es, di
            xor		bx, bx
            call	read_sectors
            pop		es
            shr		bx, 4
            add		di, bx
            pop		ax          ; ax - cluster
            xor		dx, dx

; --------- find next cluster ----------------------------------------------
            ; calculate FAT record offset on FAT12
            mov     bx, ax
            cmp     byte bp [byte cluster_mask], 0FFh
            je      short offset_fat16      ; c flag = 0 for FAT16 since operands are equal
            shr     bx, 1                   ; for FAT12, bx = 0,5 * ax
offset_fat16:
            pushf               ; c flag indicates on FAT12 cluster is XXX0h - need shift
            add     ax, bx		; ax = offset in FAT (either ax * 1.5 or ax * 2)
            adc     dx, cx      ; fat16 offset could overflow - 0FFFFh * 2

; ------------- Get next cluster record from FAT ------------------------------
            ; cx = 0
            ; dx:ax - byte offset of the cluster in FAT

            mov     bx, FAT_CACHE_ADDR
            div     word bp [byte sector_size]
            lea     si, [bx + 1]
            add     si, dx      ; dx - offset in sector
            cwd
            add     ax, word bp [byte fat_start]
            adc     dx, word bp [byte fat_start + 2]
            cmp     ax, bp [byte cached_fat_sector]
            jz      short already_read
            mov     bp [byte cached_fat_sector], ax

read_one_more:
            call    read_one_sector

take_fat_record:
            ; bx -> pointer to the next sector
            ; si -> pointer to the record + 1
            ; on FAT12 it is possible that record is split between two sectors
            cmp     si, bx
            jae     short read_one_more
            dec     si
            lodsw               ; read next cluster word

            popf
            jnc     short lower_half_byte
            shr     ax, 4       ; on fat12 shift 0XXX0h -> 00XXXh
lower_half_byte:
            mov     bl, 0FFh
            mov     bh, bp [byte cluster_mask]  ; bx 0FFFFh on FAT16, 0FFFh on FAT12
            and     ax, bx
            ; ax - next cluster
            mov     bl, 0F8h    ; 0FFF8h or 0FF8h
            cmp     ax, bx      ; is last cluster?
            jb      short read_loader_cluster

; ------------- File is loaded, execute it --------------------------------------------
            mov     dl, bp[byte drive]
            retf            ; jump to SEG_ADDRESS_TO_LOAD:0 - start of the	loader

; -------------------------------------------------------------------------------

already_read:
            call    adjust_to_next
            jmp     short take_fat_record
; ---------------------------------------------------------------------------

print_replace_disk:
            mov     al, replace_disk_msg - 100h ; "Replace the disk"

message_exit:
            mov     ah, 7Dh     ; our address + 100h high byte
            xchg    ax, si

print_char:
            lodsb
            test    al, al
            js      short print_replace_disk
            jz      short wait_exit
            mov     ah, 0Eh		; video	- display char and move	cursor;	al-char
            mov     bx, 7		; color	7, page	0
            int     10h
            jmp     short print_char
; --------------------------------------------------------------------------------

disk_error_msg      db  'Disk error'
; next byte is "cbw" command (98h) which is > 80h
; ---------------------------------------------------------------------------
wait_exit:
            ; al is always 0 here
            cbw
            int     16h     ; ah = 0, wait for a key press
            int     19h     ; reboot the computer

; --------------------------------------------------------------------------
missing_file_msg    db 'Missing '

loader_file_name    db 'OSLOADER', 3 dup(' ')
; next byte is "mov al" command (B0) which is > 80h
; ---------------------------------------------------------------------------

disk_error_exit:
            mov     al, disk_error_msg - 100h
            jmp     short message_exit

; -------------- Read one sector ------------------------------------
            ; expects cx to be 0
            ; rest parameters are the same as for read_sectors
read_one_sector:

            inc     cx
; -------------- Read sectors procedure ------------------------------------
            ; es:bx	-> buffer
            ; dx:ax	- address of the sector
            ; cx - number of sectors to read
        ; on return:
            ; cx = 0
            ; dx:ax - next sector address
            ; es:bx -> adjusted to point to next address
            ; other registers are unchanged
read_sectors:

            pusha           ; save registers

; DAP block end
            push    ds      ; 0
            push    ds      ; 0
            push    dx
            push    ax		; 8 byte absolute number of sector
            push    es
            push    bx		; address to read to
            push    cx		; num sectors
            push    10h		; DAP block size
; DAP block start

            push    bx
            push    cx

; convert abs address to cylinders, heads and tracks for ah=2 bios API
            xchg    ax, cx		; save lower address to	cx
            mov     bx, word bp[byte sec_per_track]
            xchg    ax, dx		; higher -> ax
            cwd
            ; dx:ax = 0:high address
            div     bx		    ; higher address / sectors per track
            ; dx = high address % sec_per_track
            xchg    ax, cx		; cx = high address / sec_per_track
            ; ax = low address
            div     bx		    ; lower	address	/ sectors per track

            sub     bx, dx      ; bx - sectors remaining on the track

            xchg    cx, dx		; cx - remainder, dx - higher result
            ; dx:ax = abs address / sec_per_track
            ; cx = abs address % sec_per_track
            div     word bp [byte num_heads]
            ; ax - cylinder, cx - sector, dx - head
            mov     dh, dl		; dh - head (remainder of division)

            xchg    al, ah      ; conver cylinder into bios format
            shl     al, 6       ; bits 0-7 go to CH, 8-9 to bits 6-7 of CL
            inc     cx          ; inc sector number because it starts with 1
            or      cx, ax


            pop     ax
            ; I have concerns about crossing physical 64K segment boundary
            ; (1000:0, 2000:0, etc) with ah=02 API
            ; remove following "mov bl, 1" command if your BIOS supports this
            ; so we still read 1 sector with ah=02
            ; although track crossing restriction is passed
            mov     bl, 1
            ; ax - requested number of sectors
            ; bx - allowed number to read for ah=02
            cmp     ax, bx
to_be_changed:
            mov     ah, 02h             ; would be replaced with "mov ah, 42h"
            jbe     short fit_or_ext    ; would be replaced with "jmp short fit_or_ext"
            mov     al, bl
fit_or_ext:
            pop     bx
            mov     byte bp [byte actually_read], al

            mov     si, sp		; pointer to DAP packet	in stack
            mov     dl, bp[byte drive]

    		; DISK - READ SECTORS INTO MEMORY
            ; AL = number of sectors to read, CH = track, CL = sector
            ; DH = head, DL	= drive, ES:BX -> buffer to fill
            ; Return: CF set on error, AH =	status,	AL = number of sectors read
            int     13h

            popa    ; release DAP block from stack (same as add sp, 10h)

            popa    ; restore all registers
            jc      short disk_error_exit

            ; cx - number of sectors requested
increase_values:
            call    adjust_to_next
            dec     byte bp [byte actually_read]
            loopnz    increase_values

            jcxz    read_done
            jmp     short read_sectors

; -------------------------------------------------

adjust_to_next:
            inc     ax		; increase read	address
            jnz     short no_addr_overflow
            inc     dx
no_addr_overflow:
            add     bx, word bp [byte sector_size]
read_done:
            retn

; ----------------------------------------------------------------------------

replace_disk_msg	db 0Dh,0Ah,'Replace the disk',0
        db  55h, 0AAh
