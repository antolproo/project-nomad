#!/bin/sh
set -eu
BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT HUP INT TERM
ROOT="$BASE/Domaca pevnost OFFLINE"
mkdir -p "$ROOT/scripts" "$ROOT/data/ai" "$ROOT/config"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cp "$HERE/scripts/start-offline.sh" "$ROOT/scripts/"
printf tiny > "$ROOT/data/ai/qwen-small.gguf"
printf 'larger model bytes' > "$ROOT/data/ai/qwen-large.gguf"
for ram in 8 16 32; do
  DP_TEST_RAM_GIB=$ram /bin/sh "$ROOT/scripts/start-offline.sh" --select-only > /dev/null
  if [ "$ram" -le 16 ]; then want=small; else want=large; fi
  got=$(cat "$ROOT/config/ai-active-profile.txt")
  [ "$want" = "$got" ] || { echo "FAIL ram=$ram profile=$got"; exit 1; }
  grep "qwen-$want.gguf" "$ROOT/config/ai-active-model.txt" > /dev/null || exit 1
  echo "PASS $ram GiB => $want"
done
printf 'multiple' > "$ROOT/data/ai/qwen-third.gguf"
DP_TEST_RAM_GIB=32 /bin/sh "$ROOT/scripts/start-offline.sh" --select-only > /dev/null
grep -q 'qwen-large.gguf' "$ROOT/config/ai-active-model.txt"
echo 'PASS more than two GGUF files'
printf 'projector' > "$ROOT/data/ai/mmproj-lens.gguf"
DP_TEST_RAM_GIB=8 /bin/sh "$ROOT/scripts/start-offline.sh" --select-only > /dev/null
grep -q 'qwen-small.gguf' "$ROOT/config/ai-active-model.txt"
echo 'PASS ignore projector'
printf 'data/ai/qwen-small.gguf\r\n' > "$ROOT/config/ai-model-small.txt"
printf 'data/ai/qwen-large.gguf\r\n' > "$ROOT/config/ai-model-large.txt"
DP_TEST_RAM_GIB=32 /bin/sh "$ROOT/scripts/start-offline.sh" --select-only > /dev/null
grep -q 'qwen-large.gguf' "$ROOT/config/ai-active-model.txt"
echo 'PASS cross-platform CRLF configs'
