#!/usr/bin/env bash
# Rerun ONCVPSP on the generator input embedded in an ONCVPSP UPF file
# and save its report (the generator's stdout).  The <PP_INPUTFILE> block is
# extracted and fed to the appropriate executable; UPF relativistic
# metadata selects one of:
#   scalar          oncvpsp.x
#   full            oncvpspr.x (or upstream oncvpsp_r.x)
#   nonrelativistic oncvpspnr.x (or upstream oncvpsp_nr.x)
# No core-charge extraction is performed here: the report is converted to a
# .corecharge table separately by extract_oncv_corecharge.sh, which removes
# ONCVPSP's 4*pi factor exactly once.

set -eu

RUN_TIMEOUT=300

usage() {
    cat <<'EOF'
Usage: run_oncvpsp_from_upf.sh FILE.UPF [options]

Extract the <PP_INPUTFILE> generator input embedded in a UPF file and rerun
ONCVPSP with it; save the generator's report (its stdout). The report
is not processed further here. Convert its AE-core-charge block to a
.corecharge table (r [bohr], rho_core [e/bohr^3], 4*pi factor removed) as a
separate step, e.g.
  extract_oncv_corecharge.sh Na.oncvpsp.stdout --source-upf Na.UPF -o Na.corecharge

Options:
  -o, --output PATH  write the report to PATH ('-' means stdout); default:
                     replace .UPF (case-insensitive) with .oncvpsp.stdout,
                     or append .oncvpsp.stdout if the suffix is absent
      --oncvpsp PATH executable file to force, or installation directory in
                     which to select the required version
      --keep-workdir DIR
                     run in a new DIR and retain oncvpsp.in, oncvpsp.stdout,
                     oncvpsp.stderr and any generator-created files, even
                     on failure; DIR must not already exist, and its
                     parent directory must exist
  -h, --help         show this help

Without --oncvpsp, a non-empty ONCVPSP_DIR selects the installation directory;
otherwise the required executable is found in PATH. An executable FILE
forces that program (type inference is advisory); a directory requires
unambiguous UPF metadata for automatic selection.

Type inference ignores PP_INFO. Standard SOC quantum numbers must agree with
has_so; PWmat 10/20/30 channels require has_so=false. Metadata conflicts stop
automatic selection, but --oncvpsp FILE overrides inference.

The script inherits its runtime environment.  Load modules or set compiler
runtime variables in the calling shell or job script, not here.

By default, run in a unique .oncvpsp-work.XXXXXX directory under the calling
directory and remove it on exit. Temporary files are not placed in /tmp.
Reports are published only after a successful run. File output is staged
beside its destination before replacement. Diagnostics go to stderr.

Examples:
  run_oncvpsp_from_upf.sh Na.UPF
  run_oncvpsp_from_upf.sh Na.UPF --keep-workdir Na-run -o Na.out
  run_oncvpsp_from_upf.sh Na.UPF -o - | extract_oncv_corecharge.sh -o Na.corecharge
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

absolute_path() {
    case $1 in
        /*) printf '%s\n' "$1" ;;
        *)  (CDPATH= cd -- "$(dirname -- "$1")" && printf '%s/%s\n' "$PWD" "$(basename -- "$1")") ;;
    esac
}

# Set upf_type, inference_reason, and inference_conflict from structured
# metadata only. PP_INFO descriptions and example tags are ignored here;
# extracting its embedded PP_INPUTFILE is handled separately below.
detect_upf_type() {
    local metadata key value header_types has_so_true has_so_false standard_soc encoded_soc soc_errors
    local effective_has_so soc_reason
    metadata=$(awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
            return s
        }
        # Read actual attributes, not attribute-like text inside quoted values.
        function attributes(s,    item, name, quote, endpos, k) {
            for (k in attrs) delete attrs[k]
            sub(/^<[[:space:]]*[^[:space:]\/>]+/, "", s)
            while (match(s, /^[[:space:]]*[[:alnum:]_:.-]+[[:space:]]*=[[:space:]]*[\047\042]/)) {
                item = substr(s, 1, RLENGTH)
                s = substr(s, RLENGTH + 1)
                quote = substr(item, length(item), 1)
                name = item; sub(/[[:space:]]*=.*$/, "", name); name = trim(name)
                endpos = index(s, quote)
                if (!endpos) break
                attrs[name] = trim(substr(s, 1, endpos - 1))
                s = substr(s, endpos + 1)
            }
        }
        function error(message) {
            soc_errors = soc_errors (soc_errors ? "; " : "") message
        }
        # j must be l+1/2 or, for l>0, l-1/2. A tag name alone is not data.
        function valid_lj(l, j) {
            if (l !~ /^[+]?[0-9]+$/) return 0
            if (j !~ /^[+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eEdD][+-]?[0-9]+)?$/) return 0
            gsub(/[dD]/, "e", j)
            return (j + 0 == l + 0.5 || (l + 0 > 0 && j + 0 == l - 0.5))
        }
        function without_comments(s,    result) {
            result = ""
            while (length(s)) {
                if (in_comment) {
                    if (!match(s, /-->/)) return result
                    s = substr(s, RSTART + RLENGTH); in_comment = 0
                } else if (match(s, /<!--/)) {
                    result = result substr(s, 1, RSTART - 1)
                    s = substr(s, RSTART + RLENGTH); in_comment = 1
                } else return result s
            }
            return result
        }
        function without_info(s,    result, opening) {
            result = ""
            while (length(s)) {
                if (in_info) {
                    if (!match(s, /<\/[[:space:]]*PP_INFO[[:space:]]*>/)) return result
                    s = substr(s, RSTART + RLENGTH)
                    in_info = 0
                } else if (match(s, /<[[:space:]]*PP_INFO([[:space:]>]|\/>|$)/)) {
                    result = result substr(s, 1, RSTART - 1)
                    opening = substr(s, RSTART)
                    s = substr(s, RSTART + RLENGTH); in_info = 1
                    if (match(opening, /^<[[:space:]]*PP_INFO([[:space:]][^>]*|)\/>/)) {
                        s = substr(opening, RLENGTH + 1); in_info = 0
                    }
                } else {
                    return result s
                }
            }
            return result
        }
        function process_tag(s,    name, closing, v, lname, jname) {
            closing = (s ~ /^<[[:space:]]*\//)
            name = s
            sub(/^<[[:space:]]*\/?[[:space:]]*/, "", name)
            sub(/[[:space:]\/>].*$/, "", name)
            if (name == "PP_SPIN_ORB") {
                if (closing) {
                    if (!in_spin_orb) error("unmatched PP_SPIN_ORB closing tag")
                    else if (!block_data) error("PP_SPIN_ORB has no valid RELBETA/RELWFC data")
                    in_spin_orb = 0
                } else if (s ~ /\/[[:space:]]*>$/) {
                    error("PP_SPIN_ORB has no valid RELBETA/RELWFC data")
                } else {
                    if (in_spin_orb) error("nested PP_SPIN_ORB blocks")
                    in_spin_orb = 1; block_data = 0
                }
                return
            }
            if (closing) return
            attributes(s)
            if (name == "PP_HEADER") {
                v = tolower(attrs["relativistic"])
                if (v == "scalar" || v == "full" || v == "nonrelativistic") headers[v] = 1
                v = tolower(attrs["has_so"])
                if (v ~ /^(t|[.]t[.]|true|1|yes)$/) has_so_true = 1
                if (v ~ /^(f|[.]f[.]|false|0|no)$/) has_so_false = 1
            } else if (name ~ /^PP_BETA([.][0-9]+)?$/) {
                # Confirmed PWmat l*10 encoding; native ONCVPSP lmax <= 3.
                v = attrs["angular_momentum"]
                if (v == "10" || v == "20" || v == "30") encoded_soc = 1
                if (!("lll" in attrs) && !("jjj" in attrs)) return
                if (valid_lj(attrs["lll"], attrs["jjj"])) standard_soc = 1
                else error(name " has invalid or incomplete lll/jjj")
            } else if (name ~ /^PP_REL(BETA|WFC)([.][0-9]+)?$/) {
                if (!in_spin_orb) error(name " is outside PP_SPIN_ORB")
                lname = (name ~ /^PP_RELBETA/ ? "lll" : "lchi")
                jname = (name ~ /^PP_RELBETA/ ? "jjj" : "jchi")
                if (valid_lj(attrs[lname], attrs[jname])) {
                    standard_soc = 1
                    if (in_spin_orb) block_data = 1
                } else error(name " has invalid or incomplete " lname "/" jname)
            }
        }
        # Scan tags, respecting quoted > characters and multiline attributes.
        # Numeric radial arrays are skipped without character-by-character work.
        {
            line = without_info(without_comments($0))
            while (length(line)) {
                if (!in_tag) {
                    pos = index(line, "<")
                    if (!pos) break
                    line = substr(line, pos + 1); tag = "<"; in_tag = 1; quote = ""
                }
                consumed = 0
                for (i = 1; i <= length(line); i++) {
                    c = substr(line, i, 1); tag = tag c
                    if (quote != "") { if (c == quote) quote = "" }
                    else if (c == "\047" || c == "\042") quote = c
                    else if (c == ">") {
                        process_tag(tag); in_tag = 0; consumed = i; break
                    }
                }
                if (!consumed) { tag = tag "\n"; break }
                line = substr(line, consumed + 1)
            }
        }
        END {
            if (in_spin_orb) error("PP_SPIN_ORB is not closed")
            for (v in headers) types = types (types ? "," : "") v
            print "header_types=" types
            print "has_so_true=" (has_so_true ? 1 : 0)
            print "has_so_false=" (has_so_false ? 1 : 0)
            print "standard_soc=" (standard_soc ? 1 : 0)
            print "encoded_soc=" (encoded_soc ? 1 : 0)
            print "soc_errors=" soc_errors
        }
    ' "$upf") || die "$upf: could not parse UPF metadata"

    header_types= has_so_true=0 has_so_false=0 standard_soc=0 encoded_soc=0 soc_errors=
    while IFS='=' read -r key value; do
        case $key in
            header_types) header_types=$value ;;
            has_so_true) has_so_true=$value ;;
            has_so_false) has_so_false=$value ;;
            standard_soc) standard_soc=$value ;;
            encoded_soc) encoded_soc=$value ;;
            soc_errors) soc_errors=$value ;;
        esac
    done <<EOF
$metadata
EOF

    # Stage 1: validate SOC metadata, then derive has_so-prime (effective_has_so).
    # Missing has_so is unknown, not false; valid data can supply the signal.
    inference_conflict=$soc_errors
    if [ "$has_so_true" = 1 ] && [ "$has_so_false" = 1 ]; then
        inference_conflict="${inference_conflict:+$inference_conflict; }conflicting PP_HEADER has_so values"
    fi
    if [ "$standard_soc" = 1 ] && [ "$has_so_false" = 1 ]; then
        inference_conflict="${inference_conflict:+$inference_conflict; }PP_HEADER has_so=false but valid standard SOC quantum-number data was found"
    fi
    if [ "$encoded_soc" = 1 ]; then
        if [ "$has_so_false" != 1 ] || [ "$has_so_true" = 1 ]; then
            inference_conflict="${inference_conflict:+$inference_conflict; }PP_BETA angular_momentum encoding (10/20/30) requires PP_HEADER has_so=false"
        fi
    elif [ "$has_so_true" = 1 ] && [ "$standard_soc" != 1 ]; then
        inference_conflict="${inference_conflict:+$inference_conflict; }PP_HEADER has_so=true but no valid standard SOC quantum-number data was found"
    fi

    effective_has_so=unknown
    soc_reason="no SOC flag or data"
    if [ "$encoded_soc" = 1 ]; then
        effective_has_so=true
        soc_reason="PP_BETA angular_momentum encoding (10/20/30; PWmat SOC convention)"
    elif [ "$standard_soc" = 1 ]; then
        effective_has_so=true
        soc_reason="valid standard SOC quantum-number data"
    elif [ "$has_so_true" = 1 ]; then
        effective_has_so=true
        soc_reason="PP_HEADER has_so=true (data missing)"
    elif [ "$has_so_false" = 1 ]; then
        effective_has_so=false
        soc_reason="PP_HEADER has_so=false"
    fi

    # Stage 2: reconcile has_so-prime with relativistic. Never resolve a conflict
    # by choosing a convenient executable; --oncvpsp FILE remains an override.
    upf_type=unknown
    inference_reason="no recognized PP_HEADER relativistic value or structured SOC evidence (effective_has_so=$effective_has_so)"
    if [[ $header_types == *,* ]]; then
        inference_conflict="${inference_conflict:+$inference_conflict; }conflicting PP_HEADER relativistic values: $header_types"
    fi
    if [ "$effective_has_so" = true ]; then
        upf_type=full
        inference_reason="effective_has_so=true: $soc_reason"
    elif [ -n "$header_types" ] && [[ $header_types != *,* ]]; then
        upf_type=$header_types
        inference_reason="PP_HEADER relativistic=$header_types (effective_has_so=$effective_has_so)"
    fi
    if [ "$effective_has_so" = true ] && \
       [[ ,$header_types, == *,scalar,* || ,$header_types, == *,nonrelativistic,* ]]; then
        inference_conflict="${inference_conflict:+$inference_conflict; }PP_HEADER says $header_types but effective_has_so=true"
    fi
}

find_in_directory() {
    local directory=$1 candidate
    [ -d "$directory" ] || die "ONCVPSP directory does not exist or is not a directory: $directory"
    case $upf_type in
        scalar)          candidates='oncvpsp.x' ;;
        full)            candidates='oncvpspr.x oncvpsp_r.x' ;;
        nonrelativistic) candidates='oncvpspnr.x oncvpsp_nr.x' ;;
        *) die "internal error: cannot choose an executable for type $upf_type" ;;
    esac
    for candidate in $candidates; do
        if [ -f "$directory/$candidate" ] && [ -x "$directory/$candidate" ]; then
            absolute_path "$directory/$candidate"
            return 0
        fi
    done
    die "no executable for $upf_type UPF in $directory (looked for: $candidates)"
}

find_in_path() {
    local candidate found
    case $upf_type in
        scalar)          candidates='oncvpsp.x' ;;
        full)            candidates='oncvpspr.x oncvpsp_r.x' ;;
        nonrelativistic) candidates='oncvpspnr.x oncvpsp_nr.x' ;;
        *) die "internal error: cannot choose an executable for type $upf_type" ;;
    esac
    for candidate in $candidates; do
        found=$(command -v "$candidate" || true)
        if [ -n "$found" ] && [ -f "$found" ] && [ -x "$found" ]; then
            absolute_path "$found"
            return 0
        fi
    done
    die "no executable for $upf_type UPF found in PATH (looked for: $candidates)"
}

upf= out= keep_workdir= oncv_location= oncv_option_set=false
while [ $# -gt 0 ]; do
    case $1 in
        -o|--output) [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires an argument"; out=$2; shift 2 ;;
        --oncvpsp)   [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires a non-empty path"; oncv_location=$2; oncv_option_set=true; shift 2 ;;
        --keep-workdir) [ $# -ge 2 ] && [ -n "$2" ] || die "$1 requires a directory"; keep_workdir=$2; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        --)          shift
                     [ $# -eq 1 ] && [ -z "$upf" ] || die "expected one UPF file after --"
                     upf=$1; shift ;;
        -*)          die "unknown option: $1 (try --help)" ;;
        *) [ -z "$upf" ] || die "unexpected extra argument: $1"; upf=$1; shift ;;
    esac
done

[ -n "$upf" ] || die "missing UPF argument (try --help)"
[ -f "$upf" ] && [ -r "$upf" ] || die "cannot read UPF file: $upf"
out=${out:-${upf%.[Uu][Pp][Ff]}.oncvpsp.stdout}
if [ "$out" != - ]; then
    [ ! -d "$out" ] || die "output is a directory: $out"
    [[ ! "$upf" -ef "$out" ]] || die "output would overwrite the input UPF: $out"
fi

detect_upf_type
printf 'UPF inference: %s (%s)\n' "$upf_type" "$inference_reason" >&2
[ -z "$inference_conflict" ] || printf 'UPF metadata conflict: %s\n' "$inference_conflict" >&2

if [ "$oncv_option_set" = true ] && [ -f "$oncv_location" ]; then
    [ -x "$oncv_location" ] || die "--oncvpsp file is not executable: $oncv_location"
    oncv_executable=$(absolute_path "$oncv_location")
    oncv_selection="explicit executable (type inference is advisory)"
elif [ "$oncv_option_set" = true ]; then
    [ -d "$oncv_location" ] || die "--oncvpsp must name an executable file or directory: $oncv_location"
    [ "$upf_type" != unknown ] && [ -z "$inference_conflict" ] || die "cannot automatically select ONCVPSP: $inference_reason; use --oncvpsp FILE to force an executable"
    oncv_executable=$(find_in_directory "$oncv_location")
    oncv_selection="automatic selection from --oncvpsp directory"
elif [ -n "${ONCVPSP_DIR:-}" ]; then
    [ "$upf_type" != unknown ] && [ -z "$inference_conflict" ] || die "cannot automatically select ONCVPSP: $inference_reason; use --oncvpsp FILE to force an executable"
    oncv_executable=$(find_in_directory "$ONCVPSP_DIR")
    oncv_selection="automatic selection from ONCVPSP_DIR"
else
    [ "$upf_type" != unknown ] && [ -z "$inference_conflict" ] || die "cannot automatically select ONCVPSP: $inference_reason; use --oncvpsp FILE to force an executable"
    oncv_executable=$(find_in_path)
    oncv_selection="automatic selection from PATH"
fi
printf 'ONCVPSP selection: %s\nONCVPSP executable: %s\n' "$oncv_selection" "$oncv_executable" >&2

report_tmp= temporary_workdir=
if [ -n "$keep_workdir" ]; then
    # Create only a fresh leaf directory; never reuse existing run artifacts.
    workdir=$(absolute_path "$keep_workdir")
    mkdir -m 700 -- "$workdir" || die "cannot create new work directory: $keep_workdir"
else
    workdir=$(mktemp -d "$PWD/.oncvpsp-work.XXXXXX")
    temporary_workdir=$workdir
fi
cleanup() {
    [ -z "$report_tmp" ] || rm -f -- "$report_tmp"
    [ -z "$temporary_workdir" ] || rm -rf -- "$temporary_workdir"
    return 0
}
trap cleanup EXIT
printf 'ONCVPSP work directory: %s\n' "$workdir" >&2

# Resolve the destination before running. Staging beside it makes replacement
# atomic even when the work directory is on another filesystem.
if [ "$out" != - ]; then
    out=$(absolute_path "$out")
    case $out in
        "$workdir/oncvpsp.in"|"$workdir/oncvpsp.stderr")
            die "output conflicts with a work directory file: $out" ;;
    esac
    report_tmp=$(mktemp -- "${out}.tmp.XXXXXX")
fi

# oncvpsp reads stdin, but Fortran BACKSPACE on a pipe is a no-op. Keep the
# embedded generator card in a real file and redirect that file to stdin.
inp=$workdir/oncvpsp.in
if ! awk '
    BEGIN { inb = 0; found = 0 }
    {
        line = $0
        if (!inb) {
            if (line !~ /<[[:space:]]*PP_INPUTFILE[[:space:]]*>/) next
            sub(/^.*<[[:space:]]*PP_INPUTFILE[[:space:]]*>/, "", line)
            inb = 1
        }
        if (line ~ /<\/[[:space:]]*PP_INPUTFILE[[:space:]]*>/) {
            sub(/<\/[[:space:]]*PP_INPUTFILE[[:space:]]*>.*$/, "", line)
            print line
            found = 1
            exit
        }
        print line
    }
    END { if (!found) exit 1 }
' "$upf" > "$inp"; then
    die "$upf: no complete <PP_INPUTFILE> block; PWmat SOC files converted by upf2upfSO omit it and cannot be rerun directly"
fi

stdout_f=$workdir/oncvpsp.stdout
stderr_f=$workdir/oncvpsp.stderr
status=0
(
    cd "$workdir" || exit 1
    exec timeout -k 30 "$RUN_TIMEOUT" "$oncv_executable" < oncvpsp.in
) > "$stdout_f" 2> "$stderr_f" || status=$?

case $status in
    0) ;;
    124|137) cat -- "$stderr_f" >&2
             die "$oncv_executable timed out after ${RUN_TIMEOUT} s" ;;
    126|127) cat "$stderr_f" >&2
             die "$oncv_executable could not start (status $status) -- is its runtime environment loaded?" ;;
    *) cat "$stderr_f" >&2; die "$oncv_executable exited with status $status" ;;
esac
cat -- "$stderr_f" >&2

# Publish the report only after a successful run, so a failed rerun never
# replaces an existing report.
if [ "$out" = - ]; then
    cat -- "$stdout_f"
else
    cat -- "$stdout_f" > "$report_tmp"
    mv -fT -- "$report_tmp" "$out"
fi
printf '%s -> %s\n' "$upf" "$out" >&2
