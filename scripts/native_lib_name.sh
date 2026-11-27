#!/usr/bin/env bash
# The native library's file name on this OS (sourced, never run; M9-T01). The same name is cargo's output in target/release/
# and the file in bin/ that bin/scs_native.gdextension points at: scs_native.dll under Git Bash on Windows, else libscs_native.so.
# Every script that names the library calls native_lib_name, so the per-OS choice lives here only.
source "$(dirname "${BASH_SOURCE[0]}")/lib_platform.sh"
native_lib_name() {
    if is_windows; then echo "scs_native.dll"; else echo "libscs_native.so"; fi
}
