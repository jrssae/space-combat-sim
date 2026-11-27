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
