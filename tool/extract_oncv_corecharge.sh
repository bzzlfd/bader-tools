#!/usr/bin/env bash
# Convert a patched ONCVPSP !R report to r [bohr], rho_core [e/bohr^3].
# The report contains 4*pi*rho_core; remove that factor exactly once here.
set -eu

usage() {
    cat <<'EOF'
Usage: extract_oncv_corecharge.sh [ONCV_OUTPUT|-] [options]

Extract the '!R' radial core charge rows from an existing patched ONCVPSP
output. Write a .corecharge table with r [bohr], rho_core [e/bohr^3].
The ONCVPSP 4*pi factor is removed; no generator is run.

Input defaults to stdin; '-' also selects stdin.
Output defaults to stdout. Summaries, warnings and errors go to stderr.

Options:
  -o, --output PATH     write the table to PATH ('-' means stdout)
      --source-upf PATH record the source UPF in the header (metadata only)
  -h, --help            show this help

Examples:
  extract_oncv_corecharge.sh oncvpsp.stdout -o Na.corecharge
  extract_oncv_corecharge.sh < oncvpsp.stdout > Na.corecharge

File output is replaced only after the full report has been validated.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

input=- output=- source_upf= have_input=false
while [ $# -gt 0 ]; do
    case $1 in
        -o|--output)    [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires a path"
                        output=$2; shift 2 ;;
        --source-upf)   [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires a path"
                        source_upf=$2; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        --)             shift
                        [ $# -eq 1 ] && [ "$have_input" = false ] || die "expected one input after --"
                        input=$1; have_input=true; shift ;;
        -)              [ "$have_input" = false ] || die "only one input is accepted"
                        input=$1; have_input=true; shift ;;
        -*)             die "unknown option: $1 (try --help)" ;;
        *)              [ "$have_input" = false ] || die "only one input is accepted"
                        input=$1; have_input=true; shift ;;
    esac
done

if [ "$input" = - ]; then
    input_label=stdin
    input_path=/dev/stdin
else
    [ -f "$input" ] && [ -r "$input" ] || die "cannot read ONCVPSP output: $input"
    input_label=$input
    input_path=$input
fi

# Stage the table so invalid reports produce neither partial stdout nor a
# truncated destination. File output is staged beside its destination.
if [ "$output" = - ]; then
    table_tmp=$(mktemp "${TMPDIR:-/tmp}/oncv2cc.XXXXXX")
else
    table_tmp=$(mktemp -- "${output}.tmp.XXXXXX")
fi
trap 'rm -f -- "$table_tmp"' EXIT

# Pass metadata through the environment: awk -v would interpret backslashes
# in paths as escapes. Metadata is never evaluated as awk or shell code.
CC_INPUT_LABEL="$input_label" CC_SOURCE_UPF="$source_upf" \
awk '
    function fail(message) {
        print "ERROR: " message > "/dev/stderr"
        failed = 1
        exit 1
    }
    function is_number(value) {
        return value ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([EeDd][+-]?[0-9]+)?$/
    }
    function finite(value) {
        return tolower(sprintf("%g", value)) !~ /inf|nan/
    }
    BEGIN {
        four_pi = 16*atan2(1, 1)
        source = ENVIRON["CC_INPUT_LABEL"]
        source_upf = ENVIRON["CC_SOURCE_UPF"]
    }
    {
        line = $0
        sub(/^[ \t\r]+/, "", line)
        if (substr(line, 1, 2) != "!R") next
        rest = substr(line, 3)
        sub(/^[ \t\r]+/, "", rest)
        sub(/[ \t\r]+$/, "", rest)
        fields = split(rest, values, /[ \t]+/)
        # Ignore textual !R headings; reject broken numeric rows.
        if (!is_number(values[1])) {
            if (values[1] ~ /^[+0-9.-]/ || tolower(values[1]) ~ /^(nan|inf)/)
                fail(source ": invalid !R radius at line " NR)
            next
        }
        if (fields != 2 || !is_number(values[2]))
            fail(source ": expected !R radius density at line " NR)
        gsub(/[Dd]/, "E", values[1])
        gsub(/[Dd]/, "E", values[2])
        radius = values[1] + 0
        density = values[2] + 0
        if (!finite(radius) || !finite(density) || radius < 0)
            fail(source ": !R values must be finite with radius >= 0 at line " NR)
        if (n && radius <= r[n]) fail(source ": !R radii are not strictly increasing")
        n++
        r[n] = radius
        rho_core[n] = density/four_pi
    }
    END {
        if (failed) exit 1
        if (n < 2) fail(source ": need at least two !R data rows; use output from the patched ONCVPSP")
        q = 0
        for (i = 2; i <= n; i++)
            q += 0.5*(rho_core[i]*r[i]*r[i] + rho_core[i-1]*r[i-1]*r[i-1])*(r[i] - r[i-1])
        q *= four_pi
        if (!finite(q)) fail(source ": core charge integral is not finite")

        print "# AE core density from the !R block of a patched ONCVPSP run"
        print "# source ONCVPSP output: " source
        if (source_upf != "") print "# source UPF: " source_upf
        print "# columns: r [bohr]   rho_core(r) [e/bohr^3]"
        printf "# 4*pi*int rho_core*r^2 dr = %.6f\n", q
        for (i = 1; i <= n; i++)
            printf "% .16E  % .16E\n", r[i], rho_core[i]

        printf "  !R points: %d,  r in [%.4f, %.4f] bohr\n", n, r[1], r[n] > "/dev/stderr"
        printf "  4*pi*int rho_core*r^2 dr = %.6f\n", q > "/dev/stderr"
    }
' < "$input_path" > "$table_tmp"

if [ "$output" = - ]; then
    cat -- "$table_tmp"
else
    mv -f -- "$table_tmp" "$output"
fi
