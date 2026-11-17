# Shared helpers for lab setup.sh / check.sh scripts (sourced, run on the Mac).
# multipass exec quirks worked around here:
#  - it hangs when its output goes to /dev/null, so output is always captured
#  - it hangs (re-running the command) when the remote exit code is > 1, so
#    remote commands are wrapped to exit 0 or 1 only

CP=cks-cp
WORKER=cks-worker
K="kubectl --kubeconfig /etc/kubernetes/admin.conf"
pass=0
total=0

# on NODE 'command' -> runs as root on NODE, prints output, exits 0/1
on() {
  local node="$1"; shift
  multipass exec "$node" -- sudo bash -c 'bash -c "$1" || exit 1' _ "$*" </dev/null
}

# remote NODE <<'EOF' ... EOF -> runs stdin as a root bash script on NODE, exits 0/1
remote() {
  multipass exec "$1" -- sudo bash -c 'bash -s || exit 1'
}

node_ip() {
  multipass info "$1" --format json |
    python3 -Ic "import sys,json;print(json.load(sys.stdin)['info']['$1']['ipv4'][0])"
}

# wait_for 'command on cks-cp' [tries]
wait_for() {
  local i _out
  for i in $(seq 1 "${2:-60}"); do
    _out="$(on "$CP" "$1" 2>&1)" && return 0
    sleep 3
  done
  echo "timed out waiting for: $1" >&2
  return 1
}

# check 'description' 'command' [node]  -> PASS if command exits 0 (as root on node, default cks-cp)
check() {
  local _out
  total=$((total + 1))
  if _out="$(on "${3:-$CP}" "$2" 2>&1)"; then
    echo "PASS  $1"; pass=$((pass + 1))
  else
    echo "FAIL  $1"
  fi
}

section() { echo "== $*"; }
summary() { echo; echo "Score: $pass/$total"; }
