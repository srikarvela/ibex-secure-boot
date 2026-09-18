#!/usr/bin/env bash
# Run tcl/rot_synth.tcl inside a Parallels Windows VM from macOS (Apple Silicon
# can't run Vivado natively) and copy reports/ back. Mirrors the mechanism used
# in the sibling cordic-engine repo.
#
#   ./scripts/vivado_in_parallels.sh                       # default block list
#   ./scripts/vivado_in_parallels.sh sha256_core key_store # specific blocks
#
# rtl/, tcl/, constraints/ are zipped into a Parallels shared folder, unzipped
# to a local VM disk, built with `prlctl exec --current-user`, and reports/ is
# copied back. One Vivado process per block, so a flaky x86-emulation read only
# repeats that block.
#
# Env overrides: ROT_VM (default "Windows 11"), ROT_VIVADO, ROT_VM_WORKDIR,
# ROT_SHARE_MAC, ROT_SHARE_VM, ROT_TRIES.
set -euo pipefail
cd "$(dirname "$0")/.."

BLOCKS=("$@")
VM="${ROT_VM:-Windows 11}"
VIVADO="${ROT_VIVADO:-C:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat}"
WORK="${ROT_VM_WORKDIR:-C:\\rot}"
SHARE_MAC="${ROT_SHARE_MAC:-$HOME/Downloads/rot-vm-transfer}"
SHARE_VM="${ROT_SHARE_VM:-Z:\\Downloads\\rot-vm-transfer}"
TRIES="${ROT_TRIES:-3}"

command -v prlctl >/dev/null || { echo "prlctl not found (Parallels Desktop Pro/Business required)"; exit 1; }
state="$(prlctl list -a -o status,name | awk -v vm="$VM" '$0 ~ vm {print $1}')"
case "$state" in
  running)   ;;
  suspended) echo "resuming VM '$VM'"; prlctl resume "$VM" >/dev/null ;;
  stopped)   echo "starting VM '$VM'";  prlctl start  "$VM" >/dev/null ;;
  *) echo "VM '$VM' not found (set ROT_VM)"; exit 1 ;;
esac

mkdir -p "$SHARE_MAC"
zip -qr "$SHARE_MAC/rot-src.zip" rtl tcl constraints
prlctl exec "$VM" --current-user cmd.exe /c \
  "if exist $WORK rmdir /s /q $WORK & mkdir $WORK & powershell -command \"Expand-Archive -Force '$SHARE_VM\\rot-src.zip' '$WORK'\""

n=0; ok=0
for blk in "${BLOCKS[@]:-}"; do
  n=$((n+1)); try=0
  until [ "$try" -ge "$TRIES" ]; do
    try=$((try+1))
    if prlctl exec "$VM" --current-user cmd.exe /c \
        "cd /d $WORK && \"$VIVADO\" -mode batch -nolog -nojournal -source tcl\\rot_synth.tcl -tclargs $blk"; then
      ok=$((ok+1)); break
    fi
    echo "  $blk attempt $try failed, retrying"
  done
done

prlctl exec "$VM" --current-user cmd.exe /c \
  "powershell -command \"Compress-Archive -Force '$WORK\\reports\\*' '$SHARE_VM\\rot-reports.zip'\""
unzip -oq "$SHARE_MAC/rot-reports.zip" -d reports
echo "=== ${ok} block(s) built, reports/ updated ==="
