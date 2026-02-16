#!/bin/bash
SECONDS=0
set -e

# Set kernel path
KERNEL_PATH="out/arch/arm64/boot"

# Set kernel file
OBJ="${KERNEL_PATH}/Image"
GZIP="${KERNEL_PATH}/Image.gz"

# Set dts file
DTB="${KERNEL_PATH}/dtb.img"
DTBO="${KERNEL_PATH}/dtbo.img"

# Set date kernel
DATE="$(TZ=Asia/Jakarta date +%Y%m%d%H%M)"

# Set defconfig path
DEFCONFIG="arch/arm64/configs/surya_defconfig"

# Set kernel name
KERNEL_NAME="rethinking-$1-$2-$3.zip"

# Set anykernel
if [ "$1" = "SnowCone" ]; then
	ANYKERNEL="S"
elif [ "$1" = "Tiramisu" ]; then
	ANYKERNEL="T"
else
	ANYKERNEL="U"
fi

set_cfg() {
	local key="$1"; local val="$2"
	if [ "$val" = "y" ]; then sed -i "s/^# $key is not set/$key=y/; s/^$key=.*/$key=y/" "$DEFCONFIG"
	else sed -i "s/^$key=.*/# $key is not set/" "$DEFCONFIG"; fi
}

# Setup Variant
case "$1" in
	SnowCone) set_cfg CONFIG_CAMERA_BOOTCLOCK_TIMESTAMP n ;;
	Tiramisu) set_cfg CONFIG_CAMERA_BOOTCLOCK_TIMESTAMP y ;;
	*) echo "Unknown variant: $1"; exit 1 ;;
esac

# Setup Root
case "$2" in
	KSU)
		set_cfg CONFIG_KSU y
		set_cfg CONFIG_KSU_SUSFS n ;;

	KSU+SUSFS)
		set_cfg CONFIG_KSU y
		set_cfg CONFIG_KSU_SUSFS y ;;

	NoKSU)
		set_cfg CONFIG_KSU n
		set_cfg CONFIG_KSU_SUSFS n ;;

		*) echo "Unknown root: $2"; exit 1 ;;
esac

# Kernel Compiler
function KERNEL_COMPILE() {
	# Set environment variables
	export USE_CCACHE=1
	export KBUILD_BUILD_HOST=builder
	export KBUILD_BUILD_USER=khayloaf

	# Create output directory and do a clean build
	rm -rf out anykernel && mkdir -p out

	# Download clang if not present
	if [[ ! -d clang ]]; then mkdir -p clang
		wget https://github.com/Impqxr/aosp_clang_ci/releases/download/13289611/clang-13289611-linux-x86.tar.xz -O clang.tar.gz
		tar -xf clang.tar.gz -C clang && if [ -d clang/clang-* ]; then mv clang/clang-*/* clang; fi && rm -rf clang.tar.gz
	fi

	# Add clang bin directory to PATH
	export PATH="${PWD}/clang/bin:$PATH"

	# Make the config
	make O=out ARCH=arm64 surya_defconfig

	# Build the kernel with clang and log output
	make -j$(nproc --all) O=out ARCH=arm64 CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 2>&1
}

# Kernel Results
function KERNEL_RESULT() {
	# Run compiler
	KERNEL_COMPILE

	# Check if build is successful
	if [ ! -f "$OBJ" ] || [ ! -f "$GZIP" ] || [ ! -f "$DTB" ] || [ ! -f "$DTBO" ]; then
		exit 1
	fi

	# Create anykernel
	rm -rf anykernel
	git clone https://github.com/kylieeXD/AK3-Surya.git -b "$1" anykernel

	# Copying image
	cp "$DTB" "anykernel/kernels/"
	cp "$DTBO" "anykernel/kernels/"
	cp "$GZIP" "anykernel/kernels/"

	# Created zip kernel
	cd anykernel && zip -r9 "$2" *

	# Add kernel to artifact
	cp "$2" "$3"

	# Back to kernel root
	cd - >/dev/null
}

# Run all function
rm -rf compile.log
KERNEL_RESULT "$ANYKERNEL" "$KERNEL_NAME" "$4" | tee -a compile.log

# Done bang
echo -e "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !\n"
git restore "$DEFCONFIG"
