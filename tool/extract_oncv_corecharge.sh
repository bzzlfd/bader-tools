#!/usr/bin/env bash
# Convert an ONCVPSP !R (patched) or !r (plot) report to r [bohr],
# rho_core [e/bohr^3]. Both blocks carry 4*pi*rho_core; remove that factor
# exactly once here.
set -eu

usage() {
    cat <<'EOF'
Usage: extract_oncv_corecharge.sh [ONCV_OUTPUT|-] [options]

Extract radial core charge rows from an existing ONCVPSP output. Write a
.corecharge table with r [bohr], rho_core [e/bohr^3]. The ONCVPSP 4*pi
factor is removed; no generator is run.

By default the '!R' block of a patched ONCVPSP (oncvpsp-patch/run_plot.patch)
is read. If the report has no '!R' data rows, fall back to the '!r' plot
block (columns 1 and 3) of an unpatched run and report the substitution:
that block is thinned to the plot mesh, and core charge at or above
max(5*rho, rhomod) is replaced by that limit (such rows with r <= 0.01 bohr
are dropped entirely), so clipped values and the printed core integral can
underestimate the core charge.

Input defaults to stdin; '-' also selects stdin.
For file input, output defaults to the input path with .oncvpsp.stdout
replaced by .corecharge; other filenames have .corecharge appended.
For stdin input, -o PATH or -o - is required.
Summaries, warnings and errors go to stderr.

Options:
  -o, --output PATH     write the table to PATH ('-' means stdout)
      --tag TAG         auto (default), R for '!R' (patched ONCVPSP), or
                        r for '!r' (plot block); auto prefers '!R' and
                        falls back to '!r' only if '!R' data is absent
      --source-upf PATH record the source UPF in the header (metadata only)
  -h, --help            show this help

Examples:
  extract_oncv_corecharge.sh Na.oncvpsp.stdout
  extract_oncv_corecharge.sh < Na.oncvpsp.stdout -o Na.corecharge
  extract_oncv_corecharge.sh Na.oncvpsp.stdout -o -

File output is replaced only after the full report has been validated.
For stdout output, staging uses the calling directory, not /tmp.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

input=- output= source_upf= tag_mode=auto have_input=false
while [ $# -gt 0 ]; do
    case $1 in
        -o|--output)    [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires a path"
                        output=$2; shift 2 ;;
        --tag)          [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires auto, R or r"
                        tag_mode=${2#\!}
                        case $tag_mode in
                            auto|R|r) ;;
                            *) die "invalid --tag value: $2 (expected auto, R or r)" ;;
                        esac
                        shift 2 ;;
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
    [ -n "$output" ] || die "stdin input requires -o PATH or -o - (try --help)"
    input_label=stdin
    input_path=/dev/stdin
else
    [ -f "$input" ] && [ -r "$input" ] || die "cannot read ONCVPSP output: $input"
    input_label=$input
    input_path=$input
    output=${output:-${input%.oncvpsp.stdout}.corecharge}
fi

if [ "$output" != - ]; then
    [ ! -d "$output" ] || die "output is a directory: $output"
    [[ "$input" = - || ! "$input" -ef "$output" ]] || die "output would overwrite the input report: $output"
    [[ -z "$source_upf" || ! "$source_upf" -ef "$output" ]] || die "output would overwrite the source UPF: $output"
fi

# Stage the table so invalid reports produce neither partial stdout nor a
# truncated destination. File output is staged beside its destination.
if [ "$output" = - ]; then
    table_tmp=$(mktemp "$PWD/.oncv-corecharge.XXXXXX")
else
    table_tmp=$(mktemp -- "${output}.tmp.XXXXXX")
fi
trap 'rm -f -- "$table_tmp"' EXIT

# Pass metadata through the environment: awk -v would interpret backslashes
# in paths as escapes. Metadata is never evaluated as awk or shell code.
CC_INPUT_LABEL="$input_label" CC_SOURCE_UPF="$source_upf" CC_TAG_MODE="$tag_mode" \
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
    function warn_plot_block(reason) {
        print "NOTE: " reason > "/dev/stderr"
        print "      The !r block is ONCVPSP plot output: the mesh is thinned to the plot" > "/dev/stderr"
        print "      grid, and where rhoc >= max(5*rho, rhomod) the printed value is that" > "/dev/stderr"
        print "      limit instead of rhoc (such rows with r <= 0.01 bohr are dropped)." > "/dev/stderr"
        print "      Clipped values and the core integral below can underestimate the" > "/dev/stderr"
        print "      core charge; apply oncvpsp-patch/run_plot.patch and rerun for exact data." > "/dev/stderr"
    }
    BEGIN {
        four_pi = 16*atan2(1, 1)
        source = ENVIRON["CC_INPUT_LABEL"]
        source_upf = ENVIRON["CC_SOURCE_UPF"]
        mode = ENVIRON["CC_TAG_MODE"]
        if (mode != "R" && mode != "r" && mode != "auto")
            fail("invalid tag mode: " mode)
    }
    {
        line = $0
        sub(/^[ \t\r]+/, "", line)
        tag = substr(line, 1, 2)
        if (tag != "!R" && tag != "!r") next
        # A forced block must not fail because the other block is malformed.
        if ((mode == "R" && tag != "!R") || (mode == "r" && tag != "!r")) next
        dcol = (tag == "!R") ? 2 : 3
        rest = substr(line, 3)
        sub(/^[ \t\r]+/, "", rest)
        sub(/[ \t\r]+$/, "", rest)
        fields = split(rest, values, /[ \t]+/)
        # Ignore textual !R/!r headings; reject broken numeric rows.
        if (!is_number(values[1])) {
            if (values[1] ~ /^[+0-9.-]/ || tolower(values[1]) ~ /^(nan|inf)/)
                fail(source ": invalid " tag " radius at line " NR)
            next
        }
        # !R rows are "r rhoc"; !r plot rows are "r rho rhoc [rhomod ...]".
        malformed = (tag == "!R") ? (fields != 2) : (fields < 3)
        if (malformed || !is_number(values[dcol]))
            fail(source ": expected " tag " radius density at line " NR)
        gsub(/[Dd]/, "E", values[1])
        gsub(/[Dd]/, "E", values[dcol])
        radius = values[1] + 0
        density = values[dcol] + 0
        if (!finite(radius) || !finite(density) || radius < 0)
            fail(source ": " tag " values must be finite with radius >= 0 at line " NR)
        if (rows[tag] && radius <= rad[tag, rows[tag]])
            fail(source ": " tag " radii are not strictly increasing")
        rows[tag]++
        rad[tag, rows[tag]] = radius
        den[tag, rows[tag]] = density
    }
    END {
        if (failed) exit 1
        fell_back = 0
        if (mode == "R") {
            if (rows["!R"] == 0) {
                message = source ": no !R data rows; use output from the patched ONCVPSP"
                fail(message)
            }
            if (rows["!R"] < 2) fail(source ": need at least two !R data rows")
            chosen = "!R"
        } else if (mode == "r") {
            if (rows["!r"] < 2) fail(source ": need at least two !r data rows")
            chosen = "!r"
        } else if (rows["!R"] > 0) {
            if (rows["!R"] < 2) fail(source ": need at least two !R data rows")
            chosen = "!R"
        } else if (rows["!r"] > 0) {
            if (rows["!r"] < 2) fail(source ": need at least two !r data rows")
            chosen = "!r"
            fell_back = 1
        } else {
            fail(source ": need at least two !R or !r data rows; use ONCVPSP output containing plot blocks")
        }
        if (fell_back)
            warn_plot_block("no !R block found; falling back to the !r block (columns 1 and 3).")
        else if (chosen == "!r")
            warn_plot_block("reading the !r block (columns 1 and 3), forced by --tag r.")
        n = rows[chosen]
        for (i = 1; i <= n; i++) {
            r[i] = rad[chosen, i]
            rho_core[i] = den[chosen, i]/four_pi
        }
        q = 0
        for (i = 2; i <= n; i++)
            q += 0.5*(rho_core[i]*r[i]*r[i] + rho_core[i-1]*r[i-1]*r[i-1])*(r[i] - r[i-1])
        q *= four_pi
        if (!finite(q)) fail(source ": core charge integral is not finite")

        if (chosen == "!R")
            print "# AE core density from the !R block of a patched ONCVPSP run"
        else
            print "# AE core density from the !r plot block of an ONCVPSP run (thinned mesh, clipped core charge)"
        print "# source ONCVPSP output: " source
        if (source_upf != "") print "# source UPF: " source_upf
        print "# columns: r [bohr]   rho_core(r) [e/bohr^3]"
        printf "# 4*pi*int rho_core*r^2 dr = %.6f\n", q
        for (i = 1; i <= n; i++)
            printf "% .16E  % .16E\n", r[i], rho_core[i]

        printf "  %s points: %d,  r in [%.4f, %.4f] bohr\n", chosen, n, r[1], r[n] > "/dev/stderr"
        printf "  4*pi*int rho_core*r^2 dr = %.6f\n", q > "/dev/stderr"
    }
' < "$input_path" > "$table_tmp"

if [ "$output" = - ]; then
    cat -- "$table_tmp"
else
    mv -fT -- "$table_tmp" "$output"
    printf '%s -> %s\n' "$input_label" "$output" >&2
fi
