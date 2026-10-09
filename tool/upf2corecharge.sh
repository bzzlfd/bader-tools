#!/usr/bin/env bash
# Regenerate the all-electron core charge stored in a UPF file.
#
# A UPF written by ONCVPSP embeds its generator input in the
# <PP_INPUTFILE> block.  This script extracts that input, reruns the
# patched oncvpsp.x in a scratch directory, then delegates the conversion
# of its '!R' report to extract_oncv_corecharge.sh. That script removes the ONCVPSP
# 4*pi factor and writes the actual AE core density.
#
# Output (default: the UPF path with its trailing .UPF replaced by
# .corecharge) is a two-column table:
#
#     r [bohr]    rho_core(r) [e/bohr^3]
#
# with '#' comment headers recording the source and the mesh integral
# 4*pi*int rho_core*r^2 dr, which should approach the number of core electrons
# of the atom.
#
# Usage: upf2corecharge.sh FILE.UPF [-o OUT] [--oncvpsp PATH]

set -eu

ONCVPSP=${ONCVPSP_X:-}
RUN_TIMEOUT=300
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
extractor=$script_dir/extract_oncv_corecharge.sh

usage() {
    cat <<'EOF'
Usage: upf2corecharge.sh FILE.UPF [options]

Rerun the patched oncvpsp.x on the input embedded in a UPF file and
convert its '!R' AE core charge block to a .corecharge density table.
Columns: r [bohr], rho_core [e/bohr^3] (the ONCVPSP 4*pi factor is removed).

Options:
  -o, --output OUT   output file (default: UPF name with .UPF -> .corecharge)
      --oncvpsp PATH oncvpsp.x path (default: $ONCVPSP_X, else PATH lookup)
      --keep-tmp DIR run oncvpsp.x in DIR instead of a scratch dir, keeping
                     all of its output files
  -h, --help         show this help

The script runs oncvpsp.x in the environment it inherits; set up that
environment (module load, setvars, ...) in the calling shell or job
script, not here.

Environment:
  ONCVPSP_X        oncvpsp.x path (fallback: PATH lookup)
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

upf= out= keeptmp=
while [ $# -gt 0 ]; do
    case $1 in
        -o|--output) [ $# -ge 2 ] || die "$1 requires an argument"; out=$2; shift 2 ;;
        --oncvpsp)   [ $# -ge 2 ] || die "$1 requires an argument"; ONCVPSP=$2; shift 2 ;;
        --keep-tmp)  [ $# -ge 2 ] || die "$1 requires an argument"; keeptmp=$2; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        -*)          die "unknown option: $1 (try --help)" ;;
        *) [ -z "$upf" ] || die "unexpected extra argument: $1"; upf=$1; shift ;;
    esac
done

[ -n "$upf" ] || die "missing UPF argument (try --help)"
[ -f "$upf" ] || die "no such file: $upf"
[ -f "$extractor" ] || die "missing extraction script: $extractor"
if [ -z "$ONCVPSP" ]; then
    ONCVPSP=$(command -v oncvpsp.x || true)
fi
{ [ -n "$ONCVPSP" ] && [ -x "$ONCVPSP" ]; } \
    || die "oncvpsp.x not found (put it in PATH, set ONCVPSP_X, or use --oncvpsp PATH)"
out=${out:-${upf%.[Uu][Pp][Ff]}.corecharge}

if [ -n "$keeptmp" ]; then
    mkdir -p "$keeptmp"
    workdir=$keeptmp
    tmpfiles=""
else
    workdir=$(mktemp -d "${TMPDIR:-/tmp}/upf2cc.XXXXXX")
    tmpfiles=$workdir
fi
cleanup() { [ -z "$tmpfiles" ] || rm -rf "$tmpfiles"; }
trap cleanup EXIT

# ---- extract the embedded generator input -------------------------------
inp=$workdir/oncvpsp.in
# oncvpsp reads its input from stdin, but Fortran BACKSPACE on a pipe is
# a no-op which truncates the run, so the card must be a real file.
if ! awk '
    BEGIN { inb = 0; found = 0 }
    {
        line = $0
        if (!inb) {
            p = index(line, "<PP_INPUTFILE>")
            if (!p) next
            line = substr(line, p + 14)
            inb = 1
        }
        e = index(line, "</PP_INPUTFILE>")
        if (e) {
            print substr(line, 1, e - 1)
            found = 1
            exit
        }
        print line
    }
    END { if (!found) exit 1 }
' "$upf" > "$inp"; then
    die "$upf: no <PP_INPUTFILE> block (not an ONCVPSP-generated UPF)"
fi

# ---- rerun oncvpsp.x inside the work directory --------------------------
stdout_f=$workdir/oncvpsp.stdout
stderr_f=$workdir/oncvpsp.stderr

status=0
(
    cd "$workdir" || exit 1
    exec timeout -k 30 "$RUN_TIMEOUT" "$ONCVPSP" < oncvpsp.in
) > "$stdout_f" 2> "$stderr_f" || status=$?

case $status in
    0) ;;
    124|137) die "oncvpsp.x timed out after ${RUN_TIMEOUT} s" ;;
    126|127) cat "$stderr_f" >&2
              die "oncvpsp.x could not start (status $status) -- is the runtime environment it needs loaded?" ;;
    *) cat "$stderr_f" >&2; die "oncvpsp.x exited with status $status" ;;
esac
if grep -q BACKSPACE "$stderr_f"; then
    cat "$stderr_f" >&2
fi

# ---- convert the report using the standalone extractor -----------------
case $upf in /*) src=$upf ;; *) src=$PWD/$upf ;; esac
bash "$extractor" "$stdout_f" -o "$out" --source-upf "$src"
printf '%s -> %s\n' "$upf" "$out"
