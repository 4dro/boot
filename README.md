# boot
Boot sector written in x86 assembler
Boot sector that fits into one sector (512 bytes). It works for both FAT16 and FAT12.
Loader code does not use 32-bit commands, therefore it works on 80286.

How to create a FAT16/FAT12 drive.

You need a spare flash drive.
We will use Windows diskpart utility to create volumes. It requires administrative privileges to be executed.

https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart

diskpart

list disk
select disk 1
clean
convert mbr
create partition primary size=64
create partition primary size=8
list partition
list volume
remove letter
format quick units=1024

exit
