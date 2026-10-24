#!/bin/bash
# New type errors in place/ compared with the untouched baseline (by file and message, ignoring line numbers).
# Usage: tools/typecheck.sh [file ...]   (default: every changed .luau file)
set -e
W=/tmp/claude-0/work
LSP=/tmp/claude-0/tools/lsp/luau-lsp
DEFS=/tmp/claude-0/tools/globalTypes.d.luau
cd /home/user/Claude
files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(cd place && find . -name "*.luau" | sed 's|^\./||' | while read f; do if ! cmp -s "place/$f" "$W/base_yum/$f" 2>/dev/null; then echo "$f"; fi; done)
fi
/tmp/claude-0/tools/l5/lune run tools/build_place.luau $W/yum/edit_yum.rbxl place $W/check.rbxl >/dev/null
/tmp/claude-0/tools/l5/lune run $W/sourcemap.luau $W/check.rbxl place $W/sm_new.json >/dev/null 2>&1 || true
for f in "${files[@]}"; do
  new=$($LSP analyze --sourcemap $W/sm_new.json --defs $DEFS "place/$f" 2>&1 | grep -E "^place/$f" | sed -E 's/\([0-9]+,[0-9]+\)//' | sort | uniq -c || true)
  old=""
  if [ -f "$W/base_yum/$f" ]; then
    old=$( (cd $W && $LSP analyze --sourcemap $W/sm_base_yum.json --defs $DEFS "base_yum/$f" 2>&1) | grep -E "^base_yum/$f" | sed -E 's/\([0-9]+,[0-9]+\)//; s|^base_yum/|place/|' | sort | uniq -c || true)
  fi
  diffo=$(diff <(echo "$old" | sed -E 's/^ *[0-9]+ //' | sort -u) <(echo "$new" | sed -E 's/^ *[0-9]+ //' | sort -u) | grep '^>' || true)
  if [ -n "$diffo" ]; then echo "== $f"; echo "$diffo"; fi
done
