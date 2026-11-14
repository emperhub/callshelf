#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
export CALL_LOG="$TMP_DIR/calls.log"
export IP_FILE="$TMP_DIR/ip"
export REG_FILE="$TMP_DIR/registration"
export CURL_COUNT="$TMP_DIR/curl-count"
export WARP_STATE_FILE="$TMP_DIR/warp-state"
export CURRENT_IP="203.0.113.7"
printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
printf 'personal\n' >"$REG_FILE"
printf 'connected\n' >"$WARP_STATE_FILE"

cat >"$BIN_DIR/warp-cli" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
case " $* " in
  *" settings "*)
    if [[ "${BAD_SETTINGS:-0}" == 1 ]]; then
      printf 'WARP state unavailable\n'
      exit 0
    fi
    if [[ "${FULL_TUNNEL:-0}" == 1 ]]; then
      printf 'Mode: Warp\n'
    else
      printf 'Mode: WarpProxy on port 40000\n'
    fi
    ;;
  *" status "*)
    if [[ "$(cat "$WARP_STATE_FILE")" == disconnected ]]; then
      printf 'Status update: Disconnected\n'
    else
      printf 'Status update: Connected\n'
    fi
    ;;
  *" registration show "*)
    if [[ "${MANAGED:-0}" == 1 ]]; then
      printf 'Account type: Team\n'
    elif [[ "${DEEP_FAIL:-0}" == 1 ]]; then
      printf 'Account type: Personal\n'
    elif [[ "$(cat "$REG_FILE")" == missing ]]; then
      printf 'Missing registration\n'
    else
      printf 'Account type: Personal\n'
    fi
    ;;
  *" registration delete "*)
    printf 'missing\n' >"$REG_FILE"
    ;;
  *" registration new "*)
    printf 'personal\n' >"$REG_FILE"
    ;;
  *" connect "*)
    if [[ "${HOLD_DISCONNECTED:-0}" != 1 ]]; then
      printf 'connected\n' >"$WARP_STATE_FILE"
    fi
    if [[ -n "${ROTATE_IP:-}" ]]; then
      printf '%s\n' "$ROTATE_IP" >"$IP_FILE"
    fi
    ;;
  *" disconnect "*)
    printf 'disconnected\n' >"$WARP_STATE_FILE"
    ;;
esac
STUB

cat >"$BIN_DIR/curl" <<'STUB'
#!/usr/bin/env bash
count=0
[[ -f "$CURL_COUNT" ]] && read -r count <"$CURL_COUNT"
count=$((count + 1))
printf '%s\n' "$count" >"$CURL_COUNT"
if [[ "${FAIL_AFTER_FIRST:-0}" == 1 && $count -gt 1 ]]; then
  exit 7
fi
printf 'ip=%s\n' "$(cat "$IP_FILE")"
STUB
chmod +x "$BIN_DIR/warp-cli" "$BIN_DIR/curl"

test_status_json() {
  local output
  printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
  printf 'connected\n' >"$WARP_STATE_FILE"
  output="$(PATH="$BIN_DIR:$PATH" "$ROOT/rotate.sh" --json)"
  [[ "$output" == '{"ok":true,"ip":"203.0.113.7","proxyPort":40000,"mode":"warp-proxy","managed":false}' ]]
}

test_status_json
printf 'PASS test_status_json\n'

test_rotation_json() {
  local output
  printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
  printf 'connected\n' >"$WARP_STATE_FILE"
  output="$(PATH="$BIN_DIR:$PATH" ROTATE_IP=198.51.100.42 "$ROOT/rotate.sh" --rotate --json --timeout-sec 1)"
  [[ "$output" == *'"ok":true,"before":"203.0.113.7","after":"198.51.100.42","method":"reconnect"'* ]]
  [[ "$output" == *'"elapsedSec":'* ]]
}

test_rotation_json
printf 'PASS test_rotation_json\n'

test_unrecognized_status_fails() {
  local output status
  status=0
  printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
  printf 'connected\n' >"$WARP_STATE_FILE"
  output="$(PATH="$BIN_DIR:$PATH" BAD_SETTINGS=1 "$ROOT/rotate.sh" --json 2>&1)" || status=$?
  [[ $status -ne 0 ]]
  [[ "$output" == *'"ok":false'* ]]
}

test_unrecognized_status_fails
printf 'PASS test_unrecognized_status_fails\n'

test_deep_rotation() {
  local output
  : >"$CALL_LOG"
  printf 'personal\n' >"$REG_FILE"
  printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
  printf 'connected\n' >"$WARP_STATE_FILE"
  output="$(PATH="$BIN_DIR:$PATH" ROTATE_IP=198.51.100.42 "$ROOT/rotate.sh" --deep --json --timeout-sec 1)"
  [[ "$output" == *'"ok":true,"before":"203.0.113.7","after":"198.51.100.42","method":"register"'* ]]
  grep -q 'registration delete' "$CALL_LOG"
  grep -q 'registration new' "$CALL_LOG"
}

test_deep_rotation
printf 'PASS test_deep_rotation\n'

test_managed_registration_refuses_rotation() {
  local output status
  : >"$CALL_LOG"
  status=0
  output="$(PATH="$BIN_DIR:$PATH" MANAGED=1 "$ROOT/rotate.sh" --rotate --json 2>&1)" || status=$?
  [[ $status -ne 0 ]]
  [[ "$output" == *'"error":"managed registration; refusing to rotate"'* ]]
  ! grep -Eq 'disconnect|registration delete' "$CALL_LOG"
}

test_managed_registration_refuses_rotation
printf 'PASS test_managed_registration_refuses_rotation\n'

test_unknown_option_rejected_before_warp() {
  local status
  : >"$CALL_LOG"
  status=0
  PATH="$BIN_DIR:$PATH" "$ROOT/rotate.sh" --unknown >/dev/null 2>&1 || status=$?
  [[ $status -eq 2 ]]
  [[ ! -s "$CALL_LOG" ]]
}

test_unknown_option_rejected_before_warp
printf 'PASS test_unknown_option_rejected_before_warp\n'

test_invalid_timeout_rejected_before_warp() {
  local status
  : >"$CALL_LOG"
  status=0
  PATH="$BIN_DIR:$PATH" "$ROOT/rotate.sh" --timeout-sec 0 >/dev/null 2>&1 || status=$?
  [[ $status -eq 2 ]]
  [[ ! -s "$CALL_LOG" ]]
}

test_invalid_timeout_rejected_before_warp
printf 'PASS test_invalid_timeout_rejected_before_warp\n'

test_missing_warp_cli() {
  local output status dir
  dir="$TMP_DIR/no-warp"
  mkdir -p "$dir"
  cp "$BIN_DIR/curl" "$dir/curl"
  status=0
  output="$(PATH="$dir" /bin/bash "$ROOT/rotate.sh" --json 2>&1)" || status=$?
  [[ $status -ne 0 ]]
  [[ "$output" == *'"error":"warp-cli not found.'* ]]
}

test_missing_warp_cli
printf 'PASS test_missing_warp_cli\n'

test_missing_curl() {
  local output status dir
  dir="$TMP_DIR/no-curl"
  mkdir -p "$dir"
  cp "$BIN_DIR/warp-cli" "$dir/warp-cli"
  status=0
  output="$(PATH="$dir" /bin/bash "$ROOT/rotate.sh" --json 2>&1)" || status=$?
  [[ $status -ne 0 ]]
  [[ "$output" == *'"error":"curl not found.'* ]]
}

test_missing_curl
printf 'PASS test_missing_curl\n'

test_json_dependency_error_keeps_json_on_stdout_and_hint_on_stderr() {
  local status dir stdout_file stderr_file
  dir="$TMP_DIR/no-warp-json"
  mkdir -p "$dir"
  cp "$BIN_DIR/curl" "$dir/curl"
  stdout_file="$TMP_DIR/dependency-stdout"
  stderr_file="$TMP_DIR/dependency-stderr"
  status=0
  PATH="$dir" /bin/bash "$ROOT/rotate.sh" --json >"$stdout_file" 2>"$stderr_file" || status=$?
  [[ $status -ne 0 ]]
  grep -q '"ok":false' "$stdout_file"
  grep -q 'warp-cli not found' "$stderr_file"
}

test_json_dependency_error_keeps_json_on_stdout_and_hint_on_stderr
printf 'PASS test_json_dependency_error_keeps_json_on_stdout_and_hint_on_stderr\n'

test_failed_probe_reconnects_warp() {
  local output status
  : >"$CALL_LOG"
  rm -f "$CURL_COUNT"
  printf 'personal\n' >"$REG_FILE"
  printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
  printf 'connected\n' >"$WARP_STATE_FILE"
  status=0
  output="$(PATH="$BIN_DIR:$PATH" FAIL_AFTER_FIRST=1 "$ROOT/rotate.sh" --rotate --json --timeout-sec 1 --retries 1 2>&1)" || status=$?
  [[ $status -ne 0 ]]
  [[ "$output" == *'"ok":false'* ]]
  awk '/ disconnect$/ {last_disconnect=NR} / connect$/ {last_connect=NR} END {exit !(last_connect > last_disconnect)}' "$CALL_LOG"
}

test_failed_probe_reconnects_warp
printf 'PASS test_failed_probe_reconnects_warp\n'

test_full_tunnel_failure_reconnects_even_when_direct_probe_succeeds() {
  local output status connects
  : >"$CALL_LOG"
  printf 'connected\n' >"$WARP_STATE_FILE"
  printf 'personal\n' >"$REG_FILE"
  printf '%s\n' "$CURRENT_IP" >"$IP_FILE"
  status=0
  output="$(PATH="$BIN_DIR:$PATH" FULL_TUNNEL=1 HOLD_DISCONNECTED=1 DEEP_FAIL=1 "$ROOT/rotate.sh" --rotate --json --timeout-sec 1 --retries 1 2>&1)" || status=$?
  connects="$(grep -c ' connect$' "$CALL_LOG" || true)"
  [[ $status -ne 0 ]]
  [[ "$output" == *'"ok":false'* ]]
  ((connects >= 3))
}

test_full_tunnel_failure_reconnects_even_when_direct_probe_succeeds
printf 'PASS test_full_tunnel_failure_reconnects_even_when_direct_probe_succeeds\n'
