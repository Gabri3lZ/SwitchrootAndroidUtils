#!/bin/bash

RED=$(printf '\033[01;31m')
NC=$(printf '\033[0m')

CR=$'\n> '
NL=${CR%> }

EMUMMC_SECTORS=61104128
MIN_NINTENDO_SWITCH_SIZE_IN_MIB=2048
MIN_ANDROID_USER_SIZE_IN_MIB=8192

androidImage=$1

devices=[]
devicePaths=[]
deviceIndex=-1
emummc=false

shouldContinueCheck () {
	while :
	do
		read -p "${NL}Continue? ${RED}[y,n]${NC}:$CR" yesNo
		if [[ $yesNo =~ ^[yY]e?s?$ ]]
		then
			break
		fi
		if [[ $yesNo =~ ^[nN]o?$ ]]
		then
			exit 1
		fi
		echo "${NL}Enter ${RED}Y${NC}es or ${RED}N${NC}o"
	done
}


# exit if android image is either not provided or cannot be found

if [ ! -f $androidImage ]
then
	echo 'Android image file not found. Please provide path to file as script param.'
	exit 1
fi


# dump android image partition table config to variable

partitionTable=$(sfdisk -d $androidImage)


# read offsets, sizes and names form android image partition scheme

imagePartitionOffsets=[]
imagePartitionSizes=[]
imagePartitionNames=[]

mapfile -t  imagePartitionOffsets < <(echo "$partitionTable" | awk '{ if ($4) { print int($4); } }')
mapfile -t  imagePartitionSizes < <(echo "$partitionTable" | awk '{ if ($6) { print int($6); } }')
mapfile -t  imagePartitionNames < <(echo "$partitionTable" | awk '{ if ($9) { print substr($9, 6); } }')


# fix partition alignment from android image (align to 1 MiB)

partitionSizes=[]

mapfile -t  partitionSizes < <(echo "$partitionTable" | awk \
	'{
		if ($6) {
			$6=int(($6+2047)/2048)*2048;
			print $6
		}
	}')

numOfImagePartitions=${#partitionSizes}


# let user select device

echo "${NL}Available devices:${NL}"

mapfile -t -s 1 devices < <(lsblk -S -o PATH,VENDOR,MODEL,SIZE)
mapfile -t -s 1 devicePaths < <(lsblk -S -o PATH)
lsblk -S -o PATH,VENDOR,MODEL,SIZE | awk -v r=$RED -v n=$NC \
	'NR == 1 {
		print("    "$0);
	}
	NR > 1 {
		print(r"["NR-2"] "n$0);
	}'

while :
do
	read -p "${NL}Choose device ${RED}[0-$((${#devicePaths[@]} - 1))]${NC}:$CR" deviceIndex
	if [[ $deviceIndex =~ ^[0-9]+$ ]] && (( $deviceIndex >= 0 )) && (( $deviceIndex < ${#devicePaths[@]} ))
		then
		break
	fi
	echo "${NL}Enter a valid number between ${RED}0${NC} and ${RED}$((${#devicePaths[@]} - 1))${NC}"
done

devicePath=${devicePaths[$deviceIndex]}
device=$(lsblk -S -o PATH,VENDOR,MODEL,SIZE $devicePath)
partitionTable=$(echo "$partitionTable" | sed -e "s|${androidImage}|${devicePath}|g" -e "/first-lba/d" -e "/last-lba/d")

echo "${NL}The following device will be used:${NL}${NL}${device}"

shouldContinueCheck


# read some basic informations from selected device

umount -q ${devicePath}?*

totalSectors=$(blockdev --getsz $devicePath)
lastUsableSector=$(($totalSectors - 34))
usableSectors=$(($lastUsableSector - 2048 + 1))
usableSizeInMiB=$(($usableSectors / 2048))
occupiedSectors=0

for i in "${!partitionSizes[@]}"
do
	if [ $i != 0 ] && [ $i != $((${numOfImagePartitions} - 1)) ]
	then
		((occupiedSectors+=${partitionSizes[$i]}))
	fi
done


# let user choose to create partition for emummc

while :
do
	read -p "${NL}Create partition for emummc? ${RED}[y,n]${NC}:$CR" yesNo
	if [[ $yesNo =~ ^[yY]e?s?$ ]]
	then
		emummc=true
		partitionSizes+=($EMUMMC_SECTORS)
		((occupiedSectors+=$EMUMMC_SECTORS))
		emummcPartitionConfig="${devicePath}$((${numOfImagePartitions} + 1)) : start= $(printf '%11s' '0'), size= $(printf '%11s' ${EMUMMC_SECTORS}), type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=emummc, attrs=RequiredPartition"
		partitionTable=$(echo "$partitionTable" | sed -e "$ a${emummcPartitionConfig}")
		break
	fi
	if [[ $yesNo =~ ^[nN]o?$ ]]
	then
		emummc=false
		break
	fi
	echo "${NL}Enter ${RED}Y${NC}es or ${RED}N${NC}o"
done

occupiedSizeInMiB=$(($occupiedSectors / 2048))
availableSectors=$(($usableSectors - $occupiedSectors))
availableSizeInMiB=$(($availableSectors / 2048))


# let user choose size for android user partition and use remaining space for nintendo switch partition

nintendoSwitchSizeInMiB=$MIN_NINTENDO_SWITCH_SIZE_IN_MIB
androidUserSizeInMiB=$(($availableSizeInMiB - $nintendoSwitchSizeInMiB))
maxAndroidUserSizeInMiB=$androidUserSizeInMiB

echo $NL
echo "Total usable device size:${NL}${RED}${usableSizeInMiB} MiB${NC}"
echo "Reserved size for Android system (and emummc) partitions:${NL}${RED}${occupiedSizeInMiB} MiB${NC}"
echo "Available size for Android user and Nintendo Switch partitions:${NL}${RED}${availableSizeInMiB} MiB${NC}"

while :
do
	read -p "${NL}Size in [MiB] for Android user partition ${RED}[$MIN_ANDROID_USER_SIZE_IN_MIB-$maxAndroidUserSizeInMiB]${NC}:$CR" androidUserSizeInMiB
	if [[ $androidUserSizeInMiB =~ ^[0-9]+$ ]] && (( $androidUserSizeInMiB >= $MIN_ANDROID_USER_SIZE_IN_MIB )) && (( $androidUserSizeInMiB <= $maxAndroidUserSizeInMiB ))
	then
		nintendoSwitchSizeInMiB=$(($availableSizeInMiB - $androidUserSizeInMiB))
		break
	fi
	echo "${NL}Enter a valid size in [MiB] between ${RED}${MIN_ANDROID_USER_SIZE_IN_MIB}${NC} and ${RED}${maxAndroidUserSizeInMiB}${NC}"
done

echo "${NL}Partitions will have the following size:${NL}"
echo "${RED}${nintendoSwitchSizeInMiB} MiB${NC} for Nintendo Switch partition"
echo "${RED}${androidUserSizeInMiB} MiB${NC} for Android user partition"


# warn user about data loss

echo "${RED}${NL}All data on the following device will be lost:${NL}"
echo "${device}${NC}"

shouldContinueCheck


# update partition table config

partitionSizes[0]=$(($nintendoSwitchSizeInMiB * 2048))
partitionSizes[(($numOfImagePartitions - 1))]=$(($androidUserSizeInMiB * 2048))

sectorsString=$(echo "${partitionSizes[@]}" | tr ' ' ',')

partitionTable=$(echo "$partitionTable" | \
	awk -v pointer=2048 -v sectorsString=$sectorsString \
	'BEGIN {
		split(sectorsString, sectors, ",");
	} {
		if (!$6) {
			NR=0
		}
		if ($6) {
			$6=sprintf("%12s", sectors[NR]",");
			$4=sprintf("%12s", pointer",");
			pointer=(pointer + $6)
		};
		print $0
	}')

echo "${NL}${partitionTable}${NL}"


# write new partition table according to partition table config

echo "$partitionTable" | sfdisk -w always -W always $devicePath
sfdisk --verify $devicePath


# make empty fs

echo "${NL}Making empty file systems:"
mkfs.fat -F 32 "${devicePath}1"
mkfs.fat -F 32 "${devicePath}$((${numOfImagePartitions} + 1))"
mkfs.ext4 "${devicePath}${numOfImagePartitions}"


# dump data from android image to sd card

for i in $(seq 2 $((${numOfImagePartitions} - 1)))
do
	index=$(($i - 1))
	echo "${NL}Dumping partition ${imagePartitionNames[$index]} to sd card:"
	dd bs=512 if=$androidImage of=/dev/zero skip=$((${imagePartitionOffsets[$index]} + ${imagePartitionSizes[$index]} - 2048)) count=2048
	dd bs=512 status=progress if=$androidImage of=${devicePath}${i} skip=${imagePartitionOffsets[$index]} count=${imagePartitionSizes[$index]}
done


# make hybrid mbr

no="N\n"
makeHybridMbr="r\nh\n"
mbrPartitions="1\n"
configureMbrPartitions="EE\n${no}"
writePartitionTable="o\nw\ny\n"

if $emummc
then
	mbrPartitions="1 $(($numOfImagePartitions + 1))\n"
	configureMbrPartitions+=$configureMbrPartitions
fi

printf "${makeHybridMbr}${mbrPartitions}${no}${configureMbrPartitions}${no}${writePartitionTable}" | sudo gdisk $devicePath


# copy data from nintendo switch partition of android image to sd card

loopDevice=$(losetup -o $((${imagePartitionOffsets[0]} * 512)) --sizelimit $((${imagePartitionSizes[0]} * 512)) -LPr --show -f $androidImage)

if [ ! -d /mnt ]
then
	mkdir /mnt
fi

imgMountPoint='img-switch'
sdMountPoint='sd-switch'

mkdir /mnt/$imgMountPoint
mkdir /mnt/$sdMountPoint
mount -r $loopDevice /mnt/$imgMountPoint
mount ${devicePath}1 /mnt/$sdMountPoint

cp -r /mnt/$imgMountPoint/* /mnt/$sdMountPoint/

umount $loopDevice
umount ${devicePath}1
rmdir /mnt/$imgMountPoint
rmdir /mnt/$sdMountPoint

losetup -d $loopDevice

