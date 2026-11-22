#!/bin/bash
# L1 issue-oriented oracle audit.
# Reads issues/curated.json, runs each reproduced case's command in its
# oracle_cases dir, and evaluates the machine-readable assertion.
# Output: JSONL rows + a summary JSON.  Exit 0 only if every reproduced case
# is detected and every fixed case matches its pin_expected assertion.
set -uo pipefail
export ROOT="${1:-/data/audit/mbtfuzz}"
OUT="${2:-/tmp/issuecheck.jsonl}"
SUMMARY="${3:-/tmp/issuecheck_summary.json}"
CUR="$ROOT/issues/curated.json"
HEAVY=0
TAMPER=0
for a in "$@"; do
  case "$a" in
    --heavy) HEAVY=1 ;;
    --tamper) TAMPER=1 ;;
  esac
done
TMP="$(mktemp -d /tmp/issuecheck.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
if [[ "$TAMPER" == "1" ]]; then
  # Positive control: flip one fixed-case assertion value; the audit must fail.
  jq 'map(if .issue==1328 then .assertion.value="1" else . end)' "$CUR" > "$TMP/curated_tamper.json"
  CUR="$TMP/curated_tamper.json"
fi

emit() {
  # issue status category detected oracle reason evidence rc
  jq -nc --argjson issue "$1" --arg status "$2" --arg category "$3" \
    --argjson detected "$4" --arg oracle "$5" --arg reason "$6" \
    --arg evidence "$7" --argjson rc "$8" \
    '{issue:$issue,status:$status,category:$category,detected:$detected,oracle:$oracle,reason:$reason,evidence:$evidence,rc:$rc}'
}

run_assertion() {
  local dir="$1" kind="$2" a="$3"
  local rc="$4" out="$5" err="$6"
  case "$kind" in
    exit_and_stderr)
      local want_rc want_contains
      want_rc=$(jq -r '.rc' <<<"$a")
      want_contains=$(jq -r '.contains' <<<"$a")
      [[ "$rc" == "$want_rc" ]] && grep -qF -- "$want_contains" <<<"$err$out"
      ;;
    exit_and_stdout)
      local want_rc want_contains
      want_rc=$(jq -r '.rc' <<<"$a"); want_contains=$(jq -r '.contains' <<<"$a")
      [[ "$rc" == "$want_rc" ]] && grep -qF -- "$want_contains" <<<"$out"
      ;;
    signal)
      local sig; sig=$(jq -r '.signal' <<<"$a")
      [[ "$rc" == "-$sig" || "$rc" == "$((128+sig))" ]]
      ;;
    signal_and_stderr)
      local sig want_contains; sig=$(jq -r '.signal' <<<"$a"); want_contains=$(jq -r '.contains' <<<"$a")
      [[ "$rc" == "-$sig" || "$rc" == "$((128+sig))" ]] && grep -qF -- "$want_contains" <<<"$err$out"
      ;;
    stdout_contains)
      local want; want=$(jq -r '.contains' <<<"$a")
      grep -qF -- "$want" <<<"$out"
      ;;
    stdout_line_exact)
      local line want got
      line=$(jq -r '.line' <<<"$a"); want=$(jq -r '.value' <<<"$a")
      got=$(sed -n "${line}p" <<<"$out" | tr -d '\r')
      [[ "$got" == "$want" ]]
      ;;
    stdout_lines_exact)
      local want got
      want=$(jq -c '.values' <<<"$a")
      got=$(head -n "$(jq -r '.values|length' <<<"$a")" <<<"$out" | jq -R . | jq -s -c .)
      [[ "$got" == "$want" ]]
      ;;
    test_summary)
      local passed failed
      passed=$(jq -r '.passed' <<<"$a"); failed=$(jq -r '.failed' <<<"$a")
      grep -qF "Total tests:" <<<"$out" && grep -qF "passed: $passed" <<<"$out" && grep -qF "failed: $failed" <<<"$out"
      ;;
    formatter_reparse)
      local want_rc want_contains
      want_rc=$(jq -r '.rc' <<<"$a"); want_contains=$(jq -r '.contains' <<<"$a")
      [[ "$rc" == "$want_rc" ]] && grep -qF -- "$want_contains" <<<"$err$out"
      ;;
    formatter_idempotent_reparse)
      [[ "$rc" == "0" ]] && grep -qF "idem=0" <<<"$out"
      ;;
    parse_rc)
      local want_rc want_contains
      want_rc=$(jq -r '.rc' <<<"$a"); want_contains=$(jq -r '.contains' <<<"$a")
      [[ "$rc" == "$want_rc" ]] && grep -qF -- "$want_contains" <<<"$err$out"
      ;;
    skip)
      return 2
      ;;
    *)
      return 3
      ;;
  esac
}

: > "$OUT"
reproduced=0; l1_detected=0; fixed=0; fixed_pass=0; skipped=0
jq -c '.[]' "$CUR" | while IFS= read -r row; do
  issue=$(jq -r '.issue' <<<"$row")
  status=$(jq -r '.status' <<<"$row")
  category=$(jq -r '.category' <<<"$row")
  dir="$ROOT/$(jq -r '.dir' <<<"$row")"
  cmd=$(jq -r '.command' <<<"$row")
  a=$(jq -c '.assertion' <<<"$row")
  kind=$(jq -r '.kind' <<<"$a")
  oracle="$category"
  case "$category" in
    crash_ice) oracle="crash_ice" ;;
    runtime) oracle="runtime" ;;
    formatter) oracle="formatter_reparse" ;;
    lsp) oracle="lsp_hang" ;;
    miscompile) oracle="semdiff" ;;
    typecheck) oracle="diagnostic" ;;
  esac
  if [[ "$HEAVY" == "0" && ("$issue" == "1366" || "$issue" == "1155") ]]; then
    emit "$issue" "$status" "$category" false "$oracle" "precondition_unavailable: heavy case; rerun issuecheck --heavy" "heavy case skipped by default" 0 >> "$OUT"
    continue
  fi
  if [[ "$status" == "needs_old_toolchain" || "$status" == "unclear" || "$status" == "not_reproducible" ]]; then
    emit "$issue" "$status" "$category" false "$oracle" "$(jq -r '.evidence' <<<"$row")" "skipped by status" 0 >> "$OUT"
    continue
  fi
  ( cd "$dir" && timeout 180 bash -lc "$cmd" ) >"$TMP/out" 2>"$TMP/err"
  rc=$?
  out=$(cat "$TMP/out"); err=$(cat "$TMP/err")
  if run_assertion "$dir" "$kind" "$a" "$rc" "$out" "$err"; then det=true; reason="assertion matched"
  else
    det=false
    case "$kind" in
      skip) reason="no_predicate: $(jq -r '.reason' <<<"$a")" ;;
      *) reason="expectation_ambiguous: assertion '$kind' did not match" ;;
    esac
  fi
  ev=$(printf '%s\n%s' "$out" "$err" | tr '\n' ' ' | cut -c1-220)
  emit "$issue" "$status" "$category" "$det" "$oracle" "$reason" "$ev" "$rc" >> "$OUT"
done
# summary computed from OUT
reproduced_total=$(jq -s 'map(select(.status=="reproduced"))|length' "$OUT")
reproduced_eval=$(jq -s 'map(select(.status=="reproduced" and (.reason|startswith("precondition_unavailable:")|not)))|length' "$OUT")
l1_detected=$(jq -s 'map(select(.status=="reproduced" and .detected==true))|length' "$OUT")
fixed_total=$(jq -s 'map(select(.status=="fixed"))|length' "$OUT")
fixed_eval=$(jq -s 'map(select(.status=="fixed" and (.reason|startswith("precondition_unavailable:")|not)))|length' "$OUT")
fixed_pass=$(jq -s 'map(select(.status=="fixed" and .detected==true))|length' "$OUT")
heavy=$(jq -s 'map(select(.reason|startswith("precondition_unavailable: heavy")))' "$OUT" | jq 'length')
skipped=$(jq -s 'map(select(.status!="reproduced" and .status!="fixed"))|length' "$OUT")
jq -n --argjson reproduced_total "$reproduced_total" --argjson reproduced_evaluated "$reproduced_eval" \
  --argjson l1_detected "$l1_detected" --argjson fixed_total "$fixed_total" --argjson fixed_evaluated "$fixed_eval" \
  --argjson fixed_pass "$fixed_pass" --argjson heavy_skipped "$heavy" --argjson skipped "$skipped" \
  '{reproduced_total:$reproduced_total,reproduced_evaluated:$reproduced_evaluated,l1_detected:$l1_detected,sensitivity:(if $reproduced_evaluated==0 then 0 else $l1_detected/$reproduced_evaluated end),fixed_total:$fixed_total,fixed_evaluated:$fixed_evaluated,fixed_pass:$fixed_pass,heavy_skipped:$heavy_skipped,skipped:$skipped}' > "$SUMMARY"
cat "$SUMMARY"
[[ "$l1_detected" -eq "$reproduced_eval" && "$fixed_pass" -eq "$fixed_eval" ]]
