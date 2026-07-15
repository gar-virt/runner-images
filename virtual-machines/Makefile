PYTHON ?= python3

# Enable SSH forwarding (set to 1)
SSH_FORWARD ?= 0
# Local port to access the VM via SSH
SSH_FORWARD_PORT ?= 2222

# MiB memory assigned to virtual machines during build
LINUX_VM_MEMORY ?= 2048
WINDOWS_VM_MEMORY ?= 2048

# Virtual machine base disk size supplied to qemu-img
LINUX_VM_DISK_SIZE ?= 25G
WINDOWS_VM_DISK_SIZE ?= 40G

nic_options := user,model=virtio
ifeq ($(SSH_FORWARD),1)
	nic_options := $(nic_options),hostfwd=tcp::$(SSH_FORWARD_PORT)-:22
endif

root_dir := $(PWD)
scripts_dir := $(root_dir)/scripts
build_dir := $(root_dir)/build
res_dir := $(root_dir)/res

linux_res_dir := $(res_dir)/linux
linux_build_dir := $(build_dir)/linux
linux_base_build_dir := $(linux_build_dir)/base
linux_base_image := $(linux_base_build_dir)/ubuntu-26.04-base.qcow2
linux_test_build_dir := $(linux_build_dir)/test
linux_test_image=${linux_test_build_dir}/ubuntu-26.04.qcow2
linux_seed_image := $(linux_base_build_dir)/seed.iso
linux_cloud_image := $(linux_build_dir)/source_images/ubuntu-26.04-server-cloudimg-amd64.img
linux_hostname := gitea-runner-ubuntu-26.04

windows_res_dir := $(res_dir)/windows
windows_build_dir := $(build_dir)/windows
windows_base_build_dir := $(windows_build_dir)/base
windows_base_image = $(windows_base_build_dir)/windows-2025-base.qcow2
windows_test_build_dir := $(windows_build_dir)/test
windows_test_image=${windows_test_build_dir}/windows-2025.qcow2
windows_seed_image = $(windows_base_build_dir)/seed.iso
windows_setup_image = $(windows_build_dir)/source_images/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso
windows_virtio_image = $(windows_build_dir)/source_images/virtio-win-0.1.285.iso

vs_build_tools_build_embed_dir_symlink := $(windows_build_dir)/embed/tools/vs_build_tools
vs_build_tools_build_dir := $(windows_build_dir)/vs_build_tools
vs_build_tools_res_dir := $(windows_res_dir)/embed/tools/vs_build_tools
vs_build_tools_exe := $(vs_build_tools_build_dir)/vs_BuildTools.exe

.PHONY: all
all: linux-base windows-base

$(linux_build_dir)/resources.json.stamp:
	"$(PYTHON)" "$(scripts_dir)/fetch_resources.py" --base-dir "$(linux_build_dir)" "$(linux_res_dir)/resources.json"
	mkdir -p "$$(dirname "$@")"
	touch "$@"

$(linux_base_build_dir)/meta-data:
	mkdir -p "$(linux_base_build_dir)"
	echo "instance-id: $$(uuidgen)" > "$@"
	echo "local-hostname: $(linux_hostname)" >> "$@"

$(linux_base_build_dir)/user-data: \
$(linux_res_dir)/scripts/gen_user_data.py \
$(linux_res_dir)/embed/config.json \
$(linux_res_dir)/cloud-init/user-data \
$(linux_res_dir)/embed/scripts/post_install.sh
	"$(PYTHON)" "$(linux_res_dir)/scripts/gen_user_data.py" "$(linux_res_dir)/embed/config.json" \
		< "$(linux_res_dir)/cloud-init/user-data" \
		> "$@"

$(linux_build_dir)/dependencies.stamp: \
$(linux_build_dir)/resources.json.stamp
	mkdir -p "$$(dirname "$@")"
	touch "$@"

$(linux_seed_image): \
$(linux_build_dir)/dependencies.stamp \
$(linux_base_build_dir)/meta-data \
$(linux_base_build_dir)/user-data \
$(shell find "$(linux_res_dir)/embed" -type f)
	genisoimage -follow-links -joliet -rock -input-charset utf8 -graft-points -volid cidata \
		-output "$@" \
		"$(linux_base_build_dir)/user-data" \
		"$(linux_base_build_dir)/meta-data" \
		"/=$(linux_build_dir)/embed" \
		"/=$(linux_res_dir)/embed"

.PHONY: linux-deps
linux-deps: $(linux_build_dir)/dependencies.stamp

.PHONY: linux-seed
linux-seed: $(linux_seed_image)

.PHONY: linux-base
linux-base: linux-seed
	mkdir -p "$$(dirname "$(linux_base_image)")"
	cp --force "$(linux_cloud_image)" "$(linux_base_image)"
	qemu-img resize "$(linux_base_image)" "$(LINUX_VM_DISK_SIZE)"

	kvm \
		-cpu host \
		-m "$(LINUX_VM_MEMORY)" \
		-smp 4 \
		-nic '$(nic_options)' \
		-nographic \
		-drive "file=$(linux_base_image),if=virtio" \
		-drive "file=$(linux_seed_image),media=cdrom"

.PHONY: linux-test
linux-test:
	mkdir -p "$(linux_test_build_dir)"
	qemu-img create -f qcow2 -o "backing_file=${linux_base_image}" -o backing_fmt=qcow2 "${linux_test_image}"

	kvm \
		-cpu host \
		-m "$(LINUX_VM_MEMORY)" \
		-smp 4 \
		-nic '$(nic_options)' \
		-nographic \
		-drive "file=$(linux_test_image),if=virtio"

$(vs_build_tools_exe):
	"$(PYTHON)" "$(scripts_dir)/fetch_resources.py" --base-dir "$(vs_build_tools_build_dir)" "$(windows_res_dir)/resources.vs_build_tools.json"

$(vs_build_tools_build_dir)/cache.stamp: \
$(vs_build_tools_exe)
	WINEPREFIX="$(windows_build_dir)/wine_prefix" winetricks --unattended dotnet472
	WINEPREFIX="$(windows_build_dir)/wine_prefix" wine "$(vs_build_tools_exe)" \
		--quiet --norestart --wait --layout 'C:\vs_build_tools' --lang en-US \
		--add Microsoft.VisualStudio.Workload.VCTools \
		--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
		--add Microsoft.VisualStudio.Component.Windows11SDK.26100
	mkdir -p "$$(dirname "$@")"
	touch "$@"

$(vs_build_tools_build_dir)/cache_embed_symlink.stamp: \
$(vs_build_tools_build_dir)/cache.stamp
	if [ -L "$(vs_build_tools_build_embed_dir_symlink)" ]; then rm --force "$(vs_build_tools_build_embed_dir_symlink)"; fi
	mkdir -p "$$(dirname "$(vs_build_tools_build_embed_dir_symlink)")"
	ln --symbolic --force "$(windows_build_dir)/wine_prefix/drive_c/vs_build_tools" "$(vs_build_tools_build_embed_dir_symlink)"
	mkdir -p "$$(dirname "$@")"
	touch "$@"

$(windows_build_dir)/resources.json.stamp:
	"$(PYTHON)" "$(scripts_dir)/fetch_resources.py" --base-dir "$(windows_build_dir)" "$(windows_res_dir)/resources.json"
	mkdir -p "$$(dirname "$@")"
	touch "$@"

$(windows_build_dir)/dependencies.stamp: \
$(windows_build_dir)/resources.json.stamp \
$(vs_build_tools_build_dir)/cache_embed_symlink.stamp
	mkdir -p "$$(dirname "$@")"
	touch "$@"

$(windows_seed_image): \
$(windows_build_dir)/dependencies.stamp \
$(shell find "$(windows_res_dir)/embed" -type f)
	mkdir -p "$(windows_base_build_dir)"
	genisoimage -follow-links -udf -input-charset utf8 -graft-points -volid seed \
		-output "$@" \
		"/=$(windows_build_dir)/embed" \
		"/=$(windows_res_dir)/embed"

.PHONY: windows-deps
windows-deps: $(windows_build_dir)/dependencies.stamp

.PHONY: windows-seed
windows-seed: $(windows_seed_image)

.PHONY: windows-base
windows-base: windows-seed
	mkdir -p "$(windows_base_build_dir)"
	qemu-img create -f qcow2 "$(windows_base_image)" "$(WINDOWS_VM_DISK_SIZE)"

	kvm \
		-cpu host \
		-m "$(WINDOWS_VM_MEMORY)" \
		-smp 4 \
		-nic '$(nic_options)' \
		-drive "file=${windows_base_image},if=virtio" \
		-drive "file=${windows_seed_image},media=cdrom" \
		-drive "file=${windows_virtio_image},media=cdrom" \
		-drive "file=${windows_setup_image},media=cdrom"

.PHONY: windows-test
windows-test:
	mkdir -p "$(windows_test_build_dir)"
	qemu-img create -f qcow2 -o "backing_file=${windows_base_image}" -o backing_fmt=qcow2 "${windows_test_image}"

	kvm \
		-cpu host \
		-m "$(WINDOWS_VM_MEMORY)" \
		-smp 4 \
		-nic '$(nic_options)' \
		-drive "file=${windows_test_image},if=virtio" \
		-drive "file=${windows_seed_image},media=cdrom"
