#!/usr/bin/env bash
# Launch a disposable Google Chrome window from Docker on the local X11 display.
# Extra arguments are passed to Chrome (URLs, flags). Env toggles:
#   CHROME_NO_SANDBOX=1  run with --no-sandbox instead of granting SYS_ADMIN
#   CHROME_GPU=1         pass /dev/dri for hardware acceleration
#   CHROME_DEBUG=1       expose Chrome DevTools on 127.0.0.1:$CHROME_DEBUG_PORT (default 9222);
#                        any local process can then control the browser
#   CHROME_COOKIES=file  inject cookies saved with cookies.mjs once Chrome is up (needs CHROME_DEBUG=1)
#   CHROME_DNS="ip ..."  DNS servers for the container (e.g. the VPN resolver for split-DNS names)
#   CHROME_CA_DIR=dir    extra CA certs (*.crt) to trust (default /usr/local/share/ca-certificates)
set -euo pipefail

IMAGE=chrome-sandbox:latest
DOWNLOADS="${CHROME_DOWNLOADS:-$HOME/Downloads/chrome-sandbox}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building $IMAGE ..." >&2
  docker build --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" -t "$IMAGE" "$HERE"
fi

mkdir -p "$DOWNLOADS"

args=(
  --rm --init
  --name "chrome-sandbox-$$"
  --shm-size=1g
  --tmpfs /tmp:rw,exec,size=2g
  -e DISPLAY
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro
  -v "$DOWNLOADS":/home/chrome/Downloads
)

# Extra CAs trusted by the host (corporate roots); entrypoint.sh imports them into Chrome.
CA_DIR="${CHROME_CA_DIR:-/usr/local/share/ca-certificates}"
if [[ -d "$CA_DIR" ]]; then
  args+=(-v "$CA_DIR":/usr/local/share/ca-certificates:ro)
fi

# Docker copies the host's upstream resolvers but not systemd-resolved split DNS, so VPN-only
# names may resolve to public IPs. CHROME_DNS="100.100.100.100 ..." overrides the resolvers.
for dns in ${CHROME_DNS:-}; do
  args+=(--dns "$dns")
done

if [[ -n "${XAUTHORITY:-}" && -r "$XAUTHORITY" ]]; then
  args+=(-e XAUTHORITY=/tmp/.Xauthority -v "$XAUTHORITY":/tmp/.Xauthority:ro)
else
  xhost +SI:localuser:"$(id -un)" >/dev/null
fi

chrome_flags=()
if [[ "${CHROME_NO_SANDBOX:-0}" == 1 ]]; then
  chrome_flags+=(--no-sandbox)
else
  # Chrome's namespace sandbox needs clone(CLONE_NEWUSER), which Docker's
  # default seccomp profile only permits when SYS_ADMIN is in the bounding set.
  args+=(--cap-add=SYS_ADMIN)
fi

if [[ "${CHROME_GPU:-0}" == 1 && -d /dev/dri ]]; then
  args+=(--device /dev/dri)
else
  # Without /dev/dri Mesa would still probe the host GPU driver via GLX and log errors.
  args+=(-e LIBGL_ALWAYS_SOFTWARE=1)
fi

if [[ "${CHROME_DEBUG:-0}" == 1 ]]; then
  port="${CHROME_DEBUG_PORT:-9222}"
  args+=(-p "127.0.0.1:$port:9223" -e CHROME_DEBUG_PORT="$port")
  echo "DevTools: http://127.0.0.1:$port" >&2
fi

if [[ -n "${CHROME_COOKIES:-}" ]]; then
  [[ "${CHROME_DEBUG:-0}" == 1 ]] || { echo "CHROME_COOKIES requires CHROME_DEBUG=1" >&2; exit 1; }
  [[ -r "$CHROME_COOKIES" ]] || { echo "cookie file not readable: $CHROME_COOKIES" >&2; exit 1; }
  (
    for _ in $(seq 1 60); do
      curl -fs --max-time 1 "http://127.0.0.1:$port/json/version" >/dev/null 2>&1 && break
      sleep 0.5
    done
    CHROME_DEVTOOLS_URL="http://127.0.0.1:$port" node "$HERE/cookies.mjs" load "$CHROME_COOKIES" >&2
  ) &
fi

exec docker run "${args[@]}" "$IMAGE" "${chrome_flags[@]}" "$@"
