# boot
Boot sector written in x86 assembler
Boot sector that fits into one sector (512 bytes). It works for both FAT16 and FAT12.
Loader code does not use 32-bit commands, therefore it works on 80286.

## fat16
Boot secror that implements:

- Uses Extened bios read (ah=42h) API if supported. If not, usual ah=01 read is used.
- Error messages
- Sector size not equal to 512. FAT supports logical sectors of size multiply of 512.
- Reads whole (all clusters) loader file into memory.

## deploy
A windows 32-bit console program that deploys boot sector file into FAT drive's boot sector.
Starting from Windows Vista, it required administrative privileges to read/write boot sector of fixed disks. However, you still can read/write removable disks filesystem with regular privileges.
So, if you want to deploy a boot sector on a hard drive on Windows 10, you should run the program as an administrator.

## osloader
Sample OS loaded program. It displays the address at which it is loaded and checks that all of it's content is loaded into memory.

## build
To compile the files you need NASM assembler compliler. You can download it from https://www.nasm.us.
The Deploy program also needs a linker - I use GoLink from http://www.godevtool.com
I encourage you to build the programs by yourself, it easy. You don't have to install anything - just updack compiler and linker archives and update the paths in comp.bat file. Anyway, the binaries are aslo provided for those who not want to build themselves.