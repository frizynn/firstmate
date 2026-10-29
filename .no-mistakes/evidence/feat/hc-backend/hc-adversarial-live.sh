#!/usr/bin/env bash
# Live adversarial checks for the hc backend against a PRIVATE herdr-core.
set -u
ROOT=$1
R=$(mktemp -d /tmp/fmadv.XXXXXX); mkdir -p "$R/home/config" "$R/work" "$R/config" "$R/data" "$R/cache" "$R/shim"
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SCOPE FM_BACKEND
export HC_SESSION="fmadv$$" XDG_STATE_HOME="$R" XDG_RUNTIME_DIR="$R" XDG_CONFIG_HOME="$R/config" XDG_DATA_HOME="$R/data" XDG_CACHE_HOME="$R/cache"
export FM_HOME="$R/home" FM_ROOT_OVERRIDE="$R/home"
REAL_HC=$(command -v hc)
# Logging shim around the REAL hc: records the HC_SESSION of every call.
printf '#!/bin/sh\necho "HC_SESSION=[${HC_SESSION-unset}] $*" >> %s/hc-calls.log\nexec %s "$@"\n' "$R" "$REAL_HC" > "$R/shim/hc"; chmod +x "$R/shim/hc"
export PATH="$R/shim:$PATH"
cleanup(){ HC_SESSION="fmadv$$" "$REAL_HC" server stop --json >/dev/null 2>&1; rm -rf "$R"; }; trap cleanup EXIT
ok(){ echo "PASS - $1"; }; bad(){ echo "FAIL - $1"; FAILS=$((FAILS+1)); }; FAILS=0
. "$ROOT/bin/fm-backend.sh"; fm_backend_source hc
SES=$(fm_backend_hc_container_ensure)
A=$SES:$(fm_backend_hc_create_task "$SES" fm-a1 "$R/work"); O=$SES:$(fm_backend_hc_create_task "$SES" fm-other "$R/work")
echo "task fm-a1 -> $A ; task fm-other -> $O"
echo "labels on $A: $(hc get --json "${A#*:}" | jq -c .labels)"

# 1 kill with teardown arg shape (<target> <zellij_tab_id> <expected-label>) refuses another task's terminal
if fm_backend_kill hc "$O" "" fm-a1 2>"$R/err"; then bad "kill closed fm-other's terminal for label fm-a1"; else ok "kill refused: $(cat "$R/err")"; fi
[ "$(fm_backend_hc_endpoint_state "$O")" = ready ] && ok "fm-other terminal still alive after refused kill" || bad "fm-other terminal gone"
# 2 send / capture / interrupt key refuse wrong label
fm_backend_hc_send_text_line "$O" "echo SHOULD-NOT-RUN" fm-a1 2>/dev/null && bad "send to foreign label accepted" || ok "send_text_line refused foreign label"
fm_backend_capture hc "$O" 20 fm-a1 >/dev/null 2>&1 && bad "capture of foreign label accepted" || ok "capture refused foreign label"
fm_backend_send_key hc "$O" C-c fm-a1 2>/dev/null && bad "interrupt key to foreign label accepted" || ok "send_key C-c refused foreign label"
# 3 interrupt keys delivered to the right terminal: start sleep, C-c it
fm_backend_hc_send_text_line "$A" "sleep 300; echo AFTER-SLEEP" fm-a1; sleep 1.5
for k in C-c Escape C-u; do fm_backend_send_key hc "$A" $k fm-a1 && ok "send_key $k delivered" || bad "send_key $k failed"; done
fm_backend_hc_send_text_line "$A" "echo INTERRUPTED-OK" fm-a1; sleep 1.5
CAP=$(fm_backend_capture hc "$A" 30 fm-a1)
echo "$CAP" | grep -qx INTERRUPTED-OK && ! echo "$CAP" | grep -qx AFTER-SLEEP && ok "C-c interrupted sleep; next command ran" || { bad "interrupt not observed"; echo "$CAP"; }
fm_backend_send_key hc "$A" Enter fm-a1 && ok "send_key Enter delivered" || bad "Enter failed"
# 4 empty / invalid session refused before calling hc
: > "$R/hc-calls.log"
fm_backend_capture hc ":t1" 10 fm-a1 >/dev/null 2>"$R/err"; rc1=$?
fm_backend_kill hc ":t1" "" fm-a1 2>>"$R/err"; rc2=$?
fm_backend_send_key hc "bad session:t1" C-c fm-a1 2>>"$R/err"; rc3=$?
fm_backend_hc_cli "" server status >/dev/null 2>>"$R/err"; rc4=$?
calls=$(wc -l < "$R/hc-calls.log" | tr -d ' ')
[ $rc1 -ne 0 ] && [ $rc2 -ne 0 ] && [ $rc3 -ne 0 ] && [ $rc4 -ne 0 ] && [ "$calls" = 0 ] && ok "empty/invalid session refused with 0 hc calls (rc=$rc1,$rc2,$rc3,$rc4): $(tr '\n' ' ' < "$R/err")" || bad "empty session reached hc ($calls calls; rc=$rc1,$rc2,$rc3,$rc4)"
# 5 every hc call pins HC_SESSION even when caller env names another session
: > "$R/hc-calls.log"; HC_SESSION=someothercore fm_backend_capture hc "$A" 5 fm-a1 >/dev/null
grep -v "HC_SESSION=\[$SES\]" "$R/hc-calls.log" && bad "an hc call used a non-recorded session" || ok "all $(wc -l < "$R/hc-calls.log" | tr -d ' ') hc calls pinned HC_SESSION=$SES despite caller HC_SESSION=someothercore"
# 6 matching kill closes
fm_backend_kill hc "$A" "" fm-a1 && [ "$(fm_backend_hc_endpoint_state "$A")" = absent ] && ok "kill with matching label fm-a1 closed $A" || bad "matching kill failed"
fm_backend_kill hc "$O" "" fm-other && ok "cleanup kill of fm-other" || bad "fm-other kill failed"
# 7 not auto-detected: inherited HC_TERMINAL_ID does not select hc
out=$(HC_TERMINAL_ID=t9 HC_SESSION=default bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_detect; echo rc=\$?; echo name=\$(fm_backend_name 2>/dev/null)" 2>&1 | tail -2)
echo "$out" | grep -q 'name=hc' && bad "HC_TERMINAL_ID selected hc: $out" || ok "inherited HC_TERMINAL_ID does not select hc ($(echo $out))"
# 8 explicit selection
n1=$(FM_BACKEND=hc bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_name" 2>/dev/null); echo hc > "$R/home/config/backend"
n2=$(bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_name" 2>/dev/null)
[ "$n1" = hc ] && [ "$n2" = hc ] && ok "FM_BACKEND=hc and config/backend=hc select hc" || bad "explicit selection n1=$n1 n2=$n2"
echo "FAILURES=$FAILS"
