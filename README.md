# SwitchrootAndroidUtils
Utils for Switchroot's LineageOS Android ROM for Nintendo Switch

## flash.sh
An interactive bash script to flash Switchroot's Android image on a microSD card. It allows customizing the size for the Nintendo Switch partition and Android user partition, therefore enables the usage of the same microSD card for the Nintendo Switch and Android (and a Homebrew enabled Switch on a [EMUMMC partition](https://nh-server.github.io/switch-guide/user_guide/emummc/making_emummc/)). Unlike flashing the whole image with Etcher and resizing the partitions afterwards, the script has the following advantages:
* Size for Nintendo Switch partition and Android user partition can be defined by the user
* Support for an additional partition for EMUMMC
* No wasted space on the microSD card, no matter what size the card has
* The whole process is faster, because it does not dump Gigabytes of empty partition data to the microSD card
* No fragmentation or breaking the (hybrid MBR) partition table because of moving and resizing partitions
* The partitions are properly aligned (to 1 MiB)

### Requirements
* bash (v4+)
* sfdisk
* awk
* lsblk
* sfdisk
* mkfs
* gdisk
* dd
* losetup

All these programs / commands should be preinstalled on most recent Linux distributions. If you don't have Linux installed, it is possible to run everything from the [Ubuntu Live-USB](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-windows). 

Unfortunately, I was not able to run the script within WSL on Windows 10, because there is no access to block level devices.

### Usage
1. Download the 16GB image from [Switchroot's XDA-Developers post](https://forum.xda-developers.com/nintendo-switch/nintendo-switch-news-guides-discussion--development/rom-switchroot-lineageos-15-1-t3951389) and extract the ZIP file.
2. Download "flash.sh" to the same directory where the image is.
3. Open Terminal emulator and navigate to the directory where the image and script are (in Ubuntu, you can use the File explorer to navigate there, right click the folder and select "Open in Terminal").
4. Execute the script and pass the path to the Android image as a parameter:
    ```
    sudo ./flash.sh ./android-16gb.img
    ```
5. Follow the instructions in the interactive script.
6. Follow the remaining instructions in the XDA-Developers post (from step 3).

![Screenshot](/screenshot.png)
