#!/usr/bin/env bash
# Per-OS helpers shared by the scripts (sourced, never run; M9-T06): is this Git Bash on Windows, and which Python to use.
# The one `uname -s` test lives here, so a script never repeats it.

# is_windows: true under Git Bash / MSYS2 / Cygwin.
is_windows() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

# find_python: prints the first Python that actually runs: the project's .venv (Windows layout, then Linux layout), then
# python3, then python. A candidate must execute, because Windows has a Microsoft Store stub named python3 that is on PATH
# but only opens the Store. Prints `python3` and returns 1 when none works, so the caller's own error still names it.
find_python() {
    local root candidate
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    for candidate in "${root}/.venv/Scripts/python.exe" "${root}/.venv/bin/python" python3 python; do
        if [[ "${candidate}" == */* ]]; then
            [[ -x "${candidate}" ]] || continue
        else
            command -v "${candidate}" > /dev/null 2>&1 || continue
        fi
        if "${candidate}" -c 'import sys' > /dev/null 2>&1; then
            echo "${candidate}"
            return 0
        fi
    done
    echo python3
    return 1
}

# unzip_member <zip> <dest dir> <member>: extracts one member flat into dest. Uses unzip where there is one (Linux; some Git
# Bash installs lack it), else Windows' own bsdtar (System32\tar.exe, which reads zips; the GNU tar first on PATH does not).
unzip_member() {
    local zip="$1" dest="$2" member="$3" bsdtar
    if command -v unzip > /dev/null 2>&1; then
        unzip -q -o -j "${zip}" "${member}" -d "${dest}"
        return
    fi
    bsdtar="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")/System32/tar.exe"
    "${bsdtar}" -xf "$(cygpath -m "${zip}")" -C "$(cygpath -m "${dest}")" --strip-components="$(awk -F/ '{print NF-1}' <<< "${member}")" "${member}"
}

# godot_default_bin: the project-local editor that setup_godot.sh installs (godot.exe on Windows, the godot symlink elsewhere).
godot_default_bin() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if is_windows; then echo "${root}/.tools/godot/godot.exe"; else echo "${root}/.tools/godot/godot"; fi
}
