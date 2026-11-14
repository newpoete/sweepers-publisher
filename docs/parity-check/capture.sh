#!/usr/bin/env bash
# Capture the published Sweepers Calendar into <out-dir>, the way the parity snapshot
# (sweepers-flask parity/capture.sh, sweepers-editor#63) captured the Flask site.
# Public GET requests only; no API endpoints, no credentials.
#
#   bash docs/parity-check/capture.sh tmp/parity https://newpoete.github.io/sweepers-publisher
#
# Re-run it against https://sweeperscalendar.com after cutover (Epic 4).
set -euo pipefail
OUT=${1:?usage: capture.sh <out-dir> <base-url>}
BASE=${2:?usage: capture.sh <out-dir> <base-url>}
BASE=${BASE%/}
mkdir -p "$OUT/responses" "$OUT/dom"
INDEX="$OUT/responses/index.tsv"
printf 'name\turl\tstatus\tfinal_url\tredirects\tcontent_type\tbytes\n' > "$INDEX"

fetch() {  # fetch <name> <url> <ext>
  local name=$1 url=$2 ext=$3
  local w
  w=$(curl -sS -L --suppress-connect-headers --max-redirs 5 \
        -D "$OUT/responses/$name.headers.txt" -o "$OUT/responses/$name.$ext" \
        -w '%{http_code}\t%{url_effective}\t%{num_redirects}\t%{content_type}\t%{size_download}' "$url")
  printf '%s\t%s\t%s\n' "$name" "$url" "$w" >> "$INDEX"
}

fetch http-root        "${BASE/https:/http:}/"           html
fetch root             "$BASE/"                          html
fetch today            "$BASE/today"                     html
fetch yesterday        "$BASE/yesterday"                 html
fetch calendar         "$BASE/calendar/"                 html
fetch calendar-noslash "$BASE/calendar"                  html
fetch selections       "$BASE/selections"                html
fetch mountweazel      "$BASE/mountweazel"               html
fetch mountweazel-json "$BASE/mountweazel.json"          json
fetch calendar-mountweazel "$BASE/calendar/mountweazel"  html
fetch sitemap          "$BASE/sitemap.txt"               txt
fetch robots           "$BASE/robots.txt"                txt
fetch not-found        "$BASE/no-such-page-parity-check" html
fetch release-json     "$BASE/release.json"              json
fetch selections-json  "$BASE/selections.json"           json

# Selections are rendered by script, so take the newest one from selections.json.
day=$(grep -o '"day_of_year": *[0-9]*' "$OUT/responses/selections-json.json" | head -1 | grep -o '[0-9]*$' || true)
if [ -n "$day" ]; then fetch "selection-$day" "$BASE/selection/$day" html; fi
fetch selection-missing "$BASE/selection/999" html

# The rendered DOM of each page, after its script has run.
for page in today yesterday calendar/ selections mountweazel calendar/mountweazel no-such-page-parity-check ${day:+selection/$day}; do
  name=$(echo "$page" | tr '/' '-' | sed 's/-$//')
  google-chrome --headless=new --disable-gpu --virtual-time-budget=8000 --dump-dom "$BASE/$page" \
    > "$OUT/dom/$name.html" 2>/dev/null
done
echo done
