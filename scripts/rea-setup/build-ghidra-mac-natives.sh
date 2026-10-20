#!/bin/bash
# Build the Apple Silicon native helpers that official Ghidra release zips do not ship:
#   Ghidra/Features/Decompiler/os/mac_arm_64/{decompile,sleigh}
#   GPL/DemanglerGnu/os/mac_arm_64/{demangler_gnu_v2_41,demangler_gnu_v2_24}
# Usage: build-ghidra-mac-natives.sh [GHIDRA_INSTALL_DIR]   (default: $GHIDRA_INSTALL_DIR)
# Needs only Xcode Command Line Tools (clang, make, bison 2.3). Never overwrites existing binaries.
set -euo pipefail
G="${1:-${GHIDRA_INSTALL_DIR:?pass the Ghidra install dir}}"
[ "$(uname -s)/$(uname -m)" = "Darwin/arm64" ] || { echo "This script is for macOS arm64 only."; exit 1; }
install_new() { [ -e "$2" ] || [ -L "$2" ] && { echo "keep existing $2"; return; }; install -m 755 "$1" "$2"; echo "installed $2"; }

# Decompiler + sleigh. Build each target in its own make call: with two goals the
# Makefile falls back to the BFD-based dependency set and fails on bfd.h.
cd "$G/Ghidra/Features/Decompiler/src/decompile/cpp"
D="$G/Ghidra/Features/Decompiler/os/mac_arm_64"; mkdir -p "$D"
make -j"$(sysctl -n hw.ncpu)" ghidra_opt ARCH_TYPE="-arch arm64" OSDIR=mac_arm_64 >/dev/null
make -j"$(sysctl -n hw.ncpu)" sleigh_opt ARCH_TYPE="-arch arm64" OSDIR=mac_arm_64 >/dev/null
install_new ghidra_opt "$D/decompile"
install_new sleigh_opt "$D/sleigh"

# GNU demanglers (C++ symbol names). Flags mirror GPL/DemanglerGnu/build.gradle for Clang.
S="$G/GPL/DemanglerGnu/src"; O="$G/GPL/DemanglerGnu/os/mac_arm_64"; B="$(mktemp -d)"; mkdir -p "$O"
clang -O2 -w -arch arm64 -DHAVE_STDLIB_H -DHAVE_STRING_H -I "$S/demangler_gnu_v2_41/headers" "$S"/demangler_gnu_v2_41/c/*.c -o "$B/demangler_gnu_v2_41"
clang -O2 -w -arch arm64 -DMAIN_CPLUS_DEM -DHAVE_STDLIB_H -DHAVE_STRING_H -I "$S/demangler_gnu_v2_24/headers" "$S"/demangler_gnu_v2_24/c/*.c -o "$B/demangler_gnu_v2_24"
test "$(echo _ZN3foo3barEPKci | "$B/demangler_gnu_v2_41")" = "foo::bar(char const*, int)" || { echo "demangler self-test failed"; exit 1; }
install_new "$B/demangler_gnu_v2_41" "$O/demangler_gnu_v2_41"
install_new "$B/demangler_gnu_v2_24" "$O/demangler_gnu_v2_24"
rm -rf "$B"

echo "Done. Check with: rea doctor --provider ghidra --json"
