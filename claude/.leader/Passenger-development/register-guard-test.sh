#!/bin/zsh
# Offline tests for the register guard, publish stamp, reviewer and daily check. Temp copies only.
H=${0:A:h}; S=$(mktemp -d); trap 'rm -rf $S' EXIT; cd $S; mkdir leader briefs
export REG_LEADER_DIR=$S/leader REG_FILE=$S/reg.html REG_BRIEFS_DIR=$S/briefs REG_REPO_DIR=$S
export REG_PR_STATES='{"3":"OPEN","4":"OPEN","5":"OPEN"}' REG_NO_NOTIFY=1
unset WEZTERM_PANE PASSENGER_ROLE
G=$H/register-guard.py; P=$H/register-published.py; R=$H/register-review.py
TODAY=$(python3 -c "import datetime as d;t=d.date.today();print(f'{t:%a} {t.day} {t:%b}')")
page() { # $1 = PROGRESS rows, $2 = DONE days
  python3 - "$HOME/Passenger-research/daily-register.html" "$1" "$2" > reg.html <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
s=re.sub(r"const PROGRESS = \[.*?\n\];", "const PROGRESS = [\n"+sys.argv[2]+"\n];", s, flags=re.S)
s=re.sub(r"const NEXT = \[.*?\n\];", 'const NEXT = [\n  ["Stops", "Fix the stop upload", "To do"]\n];', s, flags=re.S)
s=re.sub(r"const DONE = \[.*?\n\];", "const DONE = [\n"+sys.argv[3]+"\n];", s, flags=re.S)
print(s, end="")
PY
}
GOOD_P='  ["Compliance", "Street View link on the compliance tab", "PR #5, waiting for Zabih'"'"'s review"]'
GOOD_D="  { date: \"$TODAY\", rows: [[\"Dev setup\", \"Created the staging branch\", \"Done\"]] }"
good() { page "$GOOD_P" "$GOOD_D"; touch -t 202610021200 reg.html; publish_ok; }
publish_ok() { echo "{\"tool_input\":{\"file_path\":\"$S/reg.html\"},\"tool_response\":{\"url\":\"u\",\"version\":\"v\"}}" | python3 $P; }
iso() { python3 -c "import datetime as d;print(d.datetime.strptime('$1','%Y%m%d%H%M').astimezone(d.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))"; }
LATE=$(iso 202610021300); EARLY=$(iso 202610021100); PROMPT=$(iso 202610021000)
mk() { python3 -c "
import json,sys
print(json.dumps({'type':'user','timestamp':sys.argv[4],'message':{'content':'do it'}}))
print(json.dumps({'type':'assistant','timestamp':sys.argv[1],'message':{'content':[{'type':'tool_use','name':sys.argv[2],'input':json.loads(sys.argv[3])}]}}))" "$1" "$2" "$3" "${4:-$PROMPT}" > t.jsonl; }
fails=0
result() { [[ $1 == FAIL ]] && ((fails++)); echo "$1  $2"; }
check() { out=$(echo "{\"transcript_path\":\"$S/t.jsonl\",\"stop_hook_active\":${3:-false}}" | env ${2:+WEZTERM_PANE=$2} python3 $G)
  if [[ "$1" == block ]]; then [[ "$out" == *'"decision": "block"'* ]] && r=PASS || r=FAIL; else [[ -z "$out" ]] && r=PASS || r=FAIL; fi
  [[ $r == FAIL && -n $out ]] && echo "      got: ${out:0:220}"; result $r "$4"; }
echo 412 413 573 > leader/worker-panes

echo "== guard: who and when"
good; mk $LATE Read '{"file_path":"/x"}';  check allow 3 false "1 read-only reply"
mk $LATE Edit '{"file_path":"/Users/hassanjan/Passenger-streetview/a.ts"}'; check block 3 false "2 code edit after register"
check allow 3 true "3 no loop on second stop"
check allow 412 false "4 known worker pane is never blocked"
PASSENGER_ROLE=worker check allow 99 false "4b worker started with PASSENGER_ROLE"
check block 99 false "4c unknown pane counts as leader"
check block "" false "4d no pane info counts as leader"
mk $EARLY Edit '{"file_path":"/Users/hassanjan/Passenger-streetview/a.ts"}'; check allow 3 false "5 work before register update"
mk $LATE Edit "{\"file_path\":\"$S/leader/state.md\"}"; check allow 3 false "6 bookkeeping edit"
echo "== guard: work types"
mk $LATE Bash '{"command":"git push origin main"}'; check block 3 false "7 Passenger push"
mk $LATE Bash '{"command":"gh pr create --base staging"}'; check block 3 false "7b gh pr create"
mk $LATE Bash '{"command":"echo \"git push\" > notes.txt"}'; check allow 3 false "7c quoted mention only"
mk $LATE Bash "{\"command\":\"python3 - <<'EOF'\\nx = 1\\nEOF\\ngit status\"}"; check allow 3 false "7d heredoc and read-only git"
mk $LATE Artifact '{"file_path":"/x/report.html"}'; check block 3 false "8 other page published"
mk $LATE Artifact '{"action":"read","url":"x"}'; check allow 3 false "8b page read"
mk bad Edit '{"file_path":"/Users/hassanjan/Passenger-streetview/a.ts"}' $LATE; check block 3 false "8c bad timestamp still counts"
echo "== guard: skip notes"
echo "not register work" > leader/register.ack; check allow 3 false "9 skip note clears a small edit"
mk $LATE Bash '{"command":"cd ~/dotfiles && git push"}'; check allow 3 false "9b non-Passenger push is small, skip note clears it"
mk $LATE Bash '{"command":"git commit -m x"}'; check block 3 false "9c skip note can NOT clear a Passenger commit"
rm leader/register.ack
mk $EARLY Read '{}'; touch briefs/C-status.txt; check block 3 false "10 worker status change"
echo "skip" > leader/register.ack; check block 3 false "10b skip note can NOT clear a worker status change"
rm leader/register.ack briefs/C-status.txt
echo "== guard: page content"
good; mk $EARLY Read '{}'; check allow 3 false "11 good page"
page '  ["Design", "UI audit — report", "To do"]' "$GOOD_D"; publish_ok; check block 3 false "12 long dash"
page '  ["Design", "UI audit report", "Sort of done"]' "$GOOD_D"; publish_ok; check block 3 false "13 status not on the list"
page '  ["Design", "UI audit report", ""]' "$GOOD_D"; publish_ok; check block 3 false "14 empty cell"
page '  ["Stops", "Fix the stop upload", "To do"]' "$GOOD_D"; publish_ok; check block 3 false "15 same task in two tabs"
page "$GOOD_P" '  { date: "Mon 7 Sep", rows: [["A", "B", "Done"]] }'; publish_ok; check block 3 false "16 Done day from an earlier month"
page "$GOOD_P" '  { date: "yesterday", rows: [["A", "B", "Done"]] }'; publish_ok; check block 3 false "17 bad Done date"
page "$GOOD_P" "$GOOD_D"; sed -i '' 's/const PAST = \[\];/const PAST = [/' reg.html; publish_ok; check block 3 false "18 page script broken"
good; REG_PR_STATES='{"5":"MERGED"}' check block 3 false "19 PR merged on GitHub but still waiting on the page"
good; REG_PR_STATES='{"3":"OPEN"}' check block 3 false "19b PR number that does not exist"
good; REG_PR_STATES='null' check allow 3 false "19c GitHub unreachable: not a block on its own"
echo "== publish stamp"
good; echo '<!-- edit -->' >> reg.html; check block 3 false "20 edited, not published"
echo "{\"tool_input\":{\"file_path\":\"$S/reg.html\"},\"tool_response\":{\"error\":\"x\"}}" | python3 $P; check block 3 false "20b failed publish leaves it blocked"
echo "{\"tool_input\":{\"file_path\":\"$S/other.html\"},\"tool_response\":{\"url\":\"u\",\"version\":\"v\"}}" | python3 $P; check block 3 false "20c other file published leaves it blocked"
publish_ok; check allow 3 false "20d real publish clears it"
[[ -f leader/register.last-published.html ]] && result PASS "20e copy of the published page kept" || result FAIL "20e copy kept"
echo "== guard breaks loudly"
good; out=$(echo "{\"transcript_path\":\"$S/t.jsonl\"}" | REG_TEST_RAISE=1 WEZTERM_PANE=3 python3 $G); [[ "$out" == *block*"guard itself failed"* ]] && result PASS "21 guard error blocks with the reason" || result FAIL "21 guard error"
echo "== reviewer (fake reviewer model)"
fake() { printf '#!/bin/sh\ncat > /dev/null\necho %q\n' "$1" > fakeclaude; chmod +x fakeclaude; }
rv() { echo "{\"tool_input\":{\"file_path\":\"$1\"}}" | REG_CLAUDE_BIN=$S/fakeclaude python3 $R; }
good
fake '{"result": "{\"approve\": true, \"problems\": []}"}'; out=$(rv $S/reg.html); [[ -z $out ]] && result PASS "22 approved publish goes through" || result FAIL "22 approve"
fake '{"result": "{\"approve\": false, \"problems\": [\"row 1: jargon\"]}"}'; out=$(rv $S/reg.html); [[ $out == *deny*jargon* ]] && result PASS "23 rejected publish is refused with the reason" || result FAIL "23 reject"
fake 'not json at all'; out=$(rv $S/reg.html); [[ $out == *deny* ]] && result PASS "24 reviewer gives no verdict: refused" || result FAIL "24 no verdict"
fake '{"result": "{\"approve\": true, \"problems\": [\"x\"]}"}'; out=$(rv $S/reg.html); [[ $out == *deny* ]] && result PASS "25 approve with problems: refused" || result FAIL "25"
out=$(rv /x/other.html); [[ -z $out ]] && result PASS "26 other pages are not reviewed" || result FAIL "26"
page '  ["Design", "UI audit report", "Sort of done"]' "$GOOD_D"; fake '{"result": "{\"approve\": true, \"problems\": []}"}'; out=$(rv $S/reg.html); [[ $out == *deny*allowed* ]] && result PASS "27 content checks run before the model" || result FAIL "27"
printf '#!/bin/sh\nsleep 1; exit 3\n' > fakeclaude; good; out=$(rv $S/reg.html); [[ $out == *deny* ]] && result PASS "28 reviewer crash: refused" || result FAIL "28"
echo "== daily check"
REG_PR_STATES='{"5":"OPEN","9":"OPEN"}' REG_DAILY_SKIP_TESTS=1 python3 $H/register-daily.py > daily.out 2>&1; grep -q "#9" daily.out && result PASS "29 daily: open PR missing from the page is reported" || result FAIL "29 daily missing PR"
REG_PR_STATES='{"5":"MERGED"}' REG_DAILY_SKIP_TESTS=1 python3 $H/register-daily.py > daily.out 2>&1; grep -q "merged" daily.out && result PASS "30 daily: PR merged outside Claude is reported" || result FAIL "30 daily merged"
REG_PR_STATES='{"5":"OPEN"}' REG_DAILY_SKIP_TESTS=1 python3 $H/register-daily.py > daily.out 2>&1 && ! grep -q NOTIFY daily.out && result PASS "31 daily: all good, no notification" || result FAIL "31 daily quiet"
echo "failures: $fails"; exit $fails
