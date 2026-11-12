#!/bin/sh
# Domaca pevnost OFFLINE: auto RAM model switching + one-click macOS start.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CFG="$ROOT/config"
AI="$ROOT/data/ai"
LOGS="$ROOT/logs"
mkdir -p "$CFG" "$LOGS"
[ -d "$AI" ] || { echo "Chyba data/ai na SSD: $AI" >&2; exit 1; }
MODE=''
[ "$#" -eq 0 ] || MODE=$1
case "$MODE" in ''|--select-only) ;; *) echo 'Pouzitie: --select-only' >&2; exit 2 ;; esac
set +u; TEST_RAM=$DP_TEST_RAM_GIB; set -u
if [ "$MODE" = '--select-only' ] && [ -n "$TEST_RAM" ]; then
  case "$TEST_RAM" in *[!0-9]*|'') echo 'Neplatne test RAM' >&2; exit 2 ;; esac
  RAM=$((TEST_RAM * 1073741824))
else
  RAM=$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || sysctl -n hw.memsize 2>/dev/null || true)
fi
case "$RAM" in *[!0-9]*|'') echo 'RAM sa nepodarilo zistit.' >&2; exit 1 ;; esac
[ "$RAM" -gt 0 ] || exit 1
if [ "$RAM" -le 17179869184 ]; then PROFILE=small; else PROFILE=large; fi
read_first() {
  [ -f "$1" ] || return 1
  IFS= read -r line < "$1" || [ -n "$line" ]
  line=$(printf '%s' "$line" | tr -d '\r')
  [ -n "$line" ] || return 1
  printf '%s\n' "$line"
}
resolve_path() {
  case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$ROOT" "$1" ;; esac
}
model_path() {
  raw=$(read_first "$1") || return 1
  resolve_path "$raw"
}
size_of() {
  if [ "$(uname -s)" = Darwin ]; then stat -f %z "$1"; else stat -c %s "$1"; fi
}
SMALL_FILE="$CFG/ai-model-small.txt"
LARGE_FILE="$CFG/ai-model-large.txt"
if [ -f "$SMALL_FILE" ] && [ -f "$LARGE_FILE" ]; then
  SMALL=$(model_path "$SMALL_FILE") || exit 1
  LARGE=$(model_path "$LARGE_FILE") || exit 1
elif [ -f "$SMALL_FILE" ] || [ -f "$LARGE_FILE" ]; then
  echo 'Konfiguracia modelov je nekompletna.' >&2
  exit 1
else
  N=0; MIN=''; MAX=''; SMALL=''; LARGE=''
  while IFS= read -r p; do
    case "$(basename "$p" | tr '[:upper:]' '[:lower:]')" in
      *mmproj*|*projector*|*embedding*|*tokenizer*|*clip*|*vision*|*reranker*) continue ;;
    esac
    N=$((N + 1))
    SZ=$(size_of "$p")
    if [ -z "$MIN" ] || [ "$SZ" -lt "$MIN" ]; then MIN=$SZ; SMALL=$p; fi
    if [ -z "$MAX" ] || [ "$SZ" -ge "$MAX" ]; then MAX=$SZ; LARGE=$p; fi
  done <<EOF_MODELS
$(find "$AI" -type f -iname '*.gguf' -print)
EOF_MODELS
  if [ "$N" -lt 2 ]; then echo "Potrebne su aspon 2 GGUF modely; najdenych: $N." >&2; exit 1; fi
fi
[ -f "$SMALL" ] && [ -f "$LARGE" ] && [ "$SMALL" != "$LARGE" ] || {
  echo 'Mensie a vacsie GGUF modely neboli najdene.' >&2; exit 1;
}
if [ "$PROFILE" = small ]; then MODEL=$SMALL; else MODEL=$LARGE; fi
PORT=$(read_first "$CFG/ai-port.txt" || printf 8099)
case "$PORT" in *[!0-9]*|'') echo 'Neplatny AI port.' >&2; exit 1 ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || { echo 'Neplatny AI port.' >&2; exit 1; }
ENDPOINT="http://127.0.0.1:$PORT"
printf '%s\n' "$MODEL" > "$CFG/ai-active-model.txt"
printf '%s\n' "$PROFILE" > "$CFG/ai-active-profile.txt"
printf '%s\n' "$ENDPOINT" > "$CFG/ai-endpoint.txt"
printf 'RAM=%s GiB | profil=%s | model=%s\n' "$((RAM / 1073741824))" "$PROFILE" "$MODEL"
[ "$MODE" = '--select-only' ] && exit 0
export DOMACA_OFFLINE_AI_MODEL="$MODEL"
export DOMACA_OFFLINE_AI_PROFILE="$PROFILE"
export DOMACA_OFFLINE_AI_ENDPOINT="$ENDPOINT"
ARCH=$(uname -m)
SERVER=''
case "$ARCH" in
  arm64|aarch64)
    for p in "$ROOT/apps/macos/arm64/llama-server" "$ROOT/apps/macos/aarch64/llama-server"; do
      if [ -x "$p" ]; then SERVER=$p; break; fi
    done ;;
  x86_64|amd64)
    for p in "$ROOT/apps/macos/x86_64/llama-server" "$ROOT/apps/macos/intel/llama-server"; do
      if [ -x "$p" ]; then SERVER=$p; break; fi
    done ;;
esac
if [ -z "$SERVER" ]; then
  for p in "$ROOT/apps/macos/llama-server" "$ROOT/apps/macos/bin/llama-server" "$ROOT/apps/macos/llama.cpp/build/bin/llama-server"; do
    if [ -x "$p" ]; then SERVER=$p; break; fi
  done
fi
[ -n "$SERVER" ] || { echo 'Na SSD chyba spustitelny llama-server pre macOS.' >&2; exit 1; }
BUSY=0
if curl --noproxy '*' -sS --max-time 2 "$ENDPOINT/health" >/dev/null 2>&1; then BUSY=1; fi
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then BUSY=1; fi
if [ "$BUSY" -eq 1 ]; then
  curl --noproxy '*' -fsS --max-time 3 "$ENDPOINT/props" 2>/dev/null |
    grep -F "$MODEL" >/dev/null || {
      echo "Port $PORT je obsadeny inym modelom alebo aplikaciou." >&2; exit 1;
    }
else
  nohup "$SERVER" -m "$MODEL" --host 127.0.0.1 --port "$PORT" -c 2048 \
    > "$LOGS/ai-server-macos.log" 2>&1 < /dev/null &
  PID=$!
  echo "$PID" > "$CFG/ai-server-macos.pid"
  N=0
  while [ "$N" -lt 90 ]; do
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "AI server skoncil. Log: $LOGS/ai-server-macos.log" >&2; exit 1
    fi
    if curl --noproxy '*' -fsS --max-time 2 "$ENDPOINT/health" >/dev/null 2>&1; then break; fi
    sleep 1
    N=$((N + 1))
  done
  if [ "$N" -ge 90 ]; then echo "AI sa nespustila do 90 sekund. Log: $LOGS/ai-server-macos.log" >&2; exit 1; fi
fi
APP=''
for p in "$ROOT/apps/macos/START.app" "$ROOT/apps/macos/START.command" "$ROOT/apps/macos/START" "$ROOT/START.app"; do
  if [ -e "$p" ]; then APP=$p; break; fi
done
case "$APP" in
  *.app) /usr/bin/open "$APP" ;;
  *.command|*.sh) nohup /bin/sh "$APP" >/dev/null 2>&1 < /dev/null & ;;
  '') /usr/bin/open "$ENDPOINT" ;;
  *) nohup "$APP" >/dev/null 2>&1 < /dev/null & ;;
esac