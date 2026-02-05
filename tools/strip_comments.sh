#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
modified=0

strip_file() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  awk '
  BEGIN {
    NORMAL=0; LINE=1; BLOCK=2; STRING=3; CHAR=4; VERBATIM=5;
    state=NORMAL;
  }
  {
    line=$0 "\n";
    i=1;
    n=length(line);
    while (i<=n) {
      ch=substr(line,i,1);
      nxt=(i<n)?substr(line,i+1,1):"";

      if (state==NORMAL) {
        if (ch=="/" && nxt=="/") { state=LINE; i+=2; continue; }
        if (ch=="/" && nxt=="*") { state=BLOCK; i+=2; continue; }
        if (ch=="\"") {
          if (substr(line,i,3)=="\"\"\"") { printf "\"\"\""; i+=3; state=VERBATIM; continue; }
          printf "%s", ch; i++; state=STRING; continue;
        }
        if (ch=="'\''") { printf "%s", ch; i++; state=CHAR; continue; }
        printf "%s", ch; i++; continue;
      }

      if (state==LINE) {
        if (ch=="\n") { printf "\n"; state=NORMAL; }
        i++; continue;
      }

      if (state==BLOCK) {
        if (ch=="*" && nxt=="/") { i+=2; state=NORMAL; continue; }
        if (ch=="\n") printf "\n";
        i++; continue;
      }

      if (state==STRING) {
        printf "%s", ch;
        if (ch=="\\" && i<n) { printf "%s", nxt; i+=2; continue; }
        if (ch=="\"") state=NORMAL;
        i++; continue;
      }

      if (state==CHAR) {
        printf "%s", ch;
        if (ch=="\\" && i<n) { printf "%s", nxt; i+=2; continue; }
        if (ch=="'\''") state=NORMAL;
        i++; continue;
      }

      if (state==VERBATIM) {
        if (substr(line,i,3)=="\"\"\"") { printf "\"\"\""; i+=3; state=NORMAL; continue; }
        printf "%s", ch; i++; continue;
      }
    }
  }
  ' "$file" > "$tmp"

  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    modified=$((modified+1))
  else
    rm -f "$tmp"
  fi
}

export -f strip_file
export modified

while IFS= read -r -d '' file; do
  strip_file "$file"
done < <(find "$root" \
  -type d \( -name build -o -name builddir -o -name .git \) -prune -o \
  -type f \( -name "*.vala" -o -name "*.vala.in" -o -name "*.c" -o -name "*.h" -o -name "*.vapi" -o -name "*.c.in" -o -name "*.h.in" \) \
  ! -name "*.md" -print0)

echo "strip_comments: modified $modified files"
