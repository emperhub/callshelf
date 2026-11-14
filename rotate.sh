#!/usr/bin/env bash
set -o pipefail

usage() {
  cat <<'USAGE'
Usage: rotate.sh [--rotate] [--deep] [--json] [--timeout-sec N] [--retries N]

Show the current WARP egress IP by default, or rotate it with --rotate.
Options:
  --rotate          Reconnect WARP and wait for a new IP
  --deep            Re-register if reconnect does not change the IP
  --json            Print a compact JSON result
  --timeout-sec N   Seconds to wait for a new IP (default: 20)
  --retries N       Reconnect attempts (default: 2)
  -h, --help        Show this help
USAGE
}

json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

error() {
  local message=$1
  if ((json)); then
    printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$message")"
    printf 'callshelf: %s\n' "$message" >&2
  else
    printf 'callshelf: %s\n' "$message" >&2
  fi
  exit 1
}

json=0
rotate=0
deep=0
timeout_sec=20
retries=2

while (($#)); do
  case "$1" in
    --rotate) rotate=1 ;;
    --deep) deep=1 ;;
    --json) json=1 ;;
    --timeout-sec|--retries)
      option=$1
      (($# >= 2)) || { printf 'callshelf: %s requires a value\n' "$option" >&2; exit 2; }
      value=$2
      [[ $value =~ ^[0-9]+$ ]] && ((10#$value > 0)) || {
        printf 'callshelf: %s must be a positive integer\n' "$option" >&2
        exit 2
      }
      if [[ $option == --timeout-sec ]]; then
        timeout_sec=$((10#$value))
      else
        retries=$((10#$value))
      fi
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'callshelf: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

((deep)) && rotate=1

command -v warp-cli >/dev/null 2>&1 || error 'warp-cli not found. Install Cloudflare WARP first.'
command -v curl >/dev/null 2>&1 || error 'curl not found. Install curl first.'

invoke_warp() {
  warp-cli --accept-tos --no-ansi "$@"
}

settings=$(invoke_warp settings 2>&1) || error "warp-cli settings failed: $settings"
port=0
shopt -s nocasematch
if [[ $settings =~ Mode:[[:space:]]*WarpProxy[[:space:]]on[[:space:]]port[[:space:]]([0-9]+) ]]; then
  port=${BASH_REMATCH[1]}
elif [[ $settings =~ Mode:[[:space:]]*Warp([[:space:]]|$) ]]; then
  port=0
else
  error "unrecognized WARP settings: $settings"
fi
shopt -u nocasematch

get_egress_ip() {
  local output
  if ((port > 0)); then
    output=$(curl -fsS --max-time 8 --socks5-hostname "127.0.0.1:$port" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null) || return 1
  else
    output=$(curl -fsS --max-time 8 --noproxy '*' https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null) || return 1
  fi
  if [[ $output =~ (^|$'\n')ip=([^$'\n']+) ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  else
    return 1
  fi
}

warp_connected() {
  local status
  status=$(invoke_warp status 2>&1) || return 1
  status=${status,,}
  [[ $status == *connected* && $status != *disconnected* ]]
}

warp_connected || error 'WARP is not connected'
before=$(get_egress_ip) || error 'tunnel is not answering'
account=$(invoke_warp registration show 2>&1) || error "warp-cli registration show failed: $account"
managed=0
if [[ $account =~ Account[[:space:]]type:[[:space:]]*(Team|Enterprise|Managed) ]]; then
  managed=1
fi

if ((!rotate)); then
  if ((json)); then
    printf '{"ok":true,"ip":"%s","proxyPort":%s,"mode":"%s","managed":%s}\n' \
      "$(json_escape "$before")" "$port" "$([[ $port -gt 0 ]] && printf warp-proxy || printf full-tunnel)" \
      "$([[ $managed -eq 1 ]] && printf true || printf false)"
  else
    printf 'Egress IP: %s\nMode: %s\nAccount: %s\n' "$before" \
      "$([[ $port -gt 0 ]] && printf 'WarpProxy on 127.0.0.1:%s' "$port" || printf 'full tunnel')" \
      "$([[ $managed -eq 1 ]] && printf managed || printf personal)"
  fi
  exit 0
fi

((managed == 0)) || error 'managed registration; refusing to rotate'

connect_warp() {
  invoke_warp connect >/dev/null 2>&1 || true
  sleep 1
}

wait_new_ip() {
  local start=$SECONDS ip
  while ((SECONDS - start < $1)); do
    ip=$(get_egress_ip 2>/dev/null || true)
    if [[ -n $ip && $ip != "$before" ]]; then
      printf '%s' "$ip"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

fast_rotate() {
  local attempt ip
  for ((attempt = 1; attempt <= retries; attempt++)); do
    invoke_warp disconnect >/dev/null 2>&1 || true
    sleep 1
    invoke_warp connect >/dev/null 2>&1 || true
    ip=$(wait_new_ip "$timeout_sec" || true)
    if [[ -n $ip ]]; then
      result_ok=1
      result_ip=$ip
      result_method=reconnect
      return
    fi
  done
  result_ip=$(get_egress_ip 2>/dev/null || true)
  result_method=reconnect
}

deep_rotate() {
  local attempt output registered=0 ip
  invoke_warp disconnect >/dev/null 2>&1 || true
  sleep 2
  for ((attempt = 1; attempt <= 3; attempt++)); do
    invoke_warp registration delete >/dev/null 2>&1 || true
    sleep 2
    output=$(invoke_warp registration show 2>&1 || true)
    if [[ $output == *'Missing registration'* ]]; then
      registered=1
      break
    fi
  done
  if ((!registered)); then
    connect_warp
    result_ip=$(get_egress_ip 2>/dev/null || true)
    result_method=register
    return
  fi

  for ((attempt = 1; attempt <= 2; attempt++)); do
    if invoke_warp registration new >/dev/null 2>&1; then
      registered=2
      break
    fi
    sleep 8
  done
  if ((registered != 2)); then
    connect_warp
    result_ip=$(get_egress_ip 2>/dev/null || true)
    result_method=register
    return
  fi

  connect_warp
  ip=$(wait_new_ip "$((timeout_sec > 15 ? timeout_sec : 15))" || true)
  if [[ -n $ip ]]; then
    result_ok=1
    result_ip=$ip
  else
    result_ip=$(get_egress_ip 2>/dev/null || true)
  fi
  result_method=register
}

started=$SECONDS
result_ok=0
result_ip=$before
result_method=reconnect
if ((deep)); then
  deep_rotate
else
  fast_rotate
  if ((result_ok == 0)); then
    deep_rotate
  fi
fi

if ! warp_connected; then
  connect_warp
fi
elapsed=$((SECONDS - started))

if ((json)); then
  printf '{"ok":%s,"before":"%s","after":"%s","method":"%s","elapsedSec":%s.0}\n' \
    "$([[ $result_ok -eq 1 ]] && printf true || printf false)" \
    "$(json_escape "$before")" "$(json_escape "$result_ip")" "$result_method" "$elapsed"
elif ((result_ok)); then
  printf '%s -> %s (%s, %ss)\n' "$before" "$result_ip" "$result_method" "$elapsed"
else
  printf 'IP unchanged: %s (%s, %ss)\n' "$result_ip" "$result_method" "$elapsed" >&2
fi

((result_ok))
