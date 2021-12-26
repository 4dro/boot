How to create a FAT16/FAT12 drive.


The type of the FAT is defined entirely by the number of clusters used. The rule is simple - if the number fits into 12 bit (0FFFh) - it's FAT12, if in 16 bit (0FFFFh) - it's FAT16, otherwise (up to 0FFFFFFFFh) - FAT32. The number of clusters is determined from drive size and cluster size. Hopefully, we can set both.

We can make some calculation to find the magnitude of disk size which is allowed for each filesystem type. For a cluster size of 512 it would be 0FFFh * 512 = ~2Mb, while 0FFFFh * 512 = ~32Mb and 0FFFFFFFF * 512 = ~2Tb. These are the limits for the drive size.


| Cluster size | FAT12 | FAT16 | FAT32 |
| ------ | ---- | ----- | ----- |
| 512 | 0 - 2Mb | 2Mb - 32Mb | 32Mb - 2Tb |
| 1024 | 0 - 4Mb | 4Mb - 64Mb | 64Mb - 4Tb |
| 2048 | 0 - 8Mb | 8Mb - 128Mb | 128Mb - 8Tb |
| 4096 | 0 - 16Mb | 16Mb - 256Mb | 256Mb - 16Tb |
| 8192 | 0 - 32Mb | 32Mb - 512Mb | 512Mb - 32Tb |
| 16384 | 0 - 64Mb | 64Mb - 1Gb | 1Gb - 64Tb |

So, we can define the type of filesystem indirectly (by specifying cluster size) when we format a drive. For example, if we have a disk of size 50Mb, if we format it with cluster size 16Kb it would become FAT12, for 8K cluster - would become FAT16, and for 512b - FAT32. That's how we can create different types of FAT filesystem.

You need a spare flash drive.

We will use Windows *diskpart* utility to create volumes. It requires administrative privileges to be executed.
https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart

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
