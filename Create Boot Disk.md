How to create a FAT16/FAT12 drive.

You need a spare flash drive.

We will use Windows diskpart utility to create volumes. It requires administrative privileges to be executed.
https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart


Type of the FAT is defined entirely by the number of clusters used. The number of clusters is determined from drive size and cluster size. Hopefully, we can set both.

| Cluster size | FAT12 | FAT16 | FAT32 |
| ------ | ---- | ----- | ----- |
| 512 | 0 - 2Mb | 2Mb - X | |
| 1024 | 0 - 4Mb | 4Mb - X | |
| 2048 | 0 - 8Mb | 8Mb - X | |
| 4096 | 0 - 16Mb | 16Mb - X | |

diskpart

list disk
select disk 1
clean
convert mbr
create partition primary size=6
active
list partition
list volume
format quick unit=1024
select volume 4
assign letter=e
remove letter

exit


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
