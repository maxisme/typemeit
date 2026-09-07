#!/bin/bash
# Checks that typeme.it/download still hands out a DMG, and pushes to notifi
# when it does not.
#
#   Scripts/download-healthcheck.sh
#
# The Worker streams the DMG from GitHub, so the download breaks if GitHub is
# down, if a release ships without a TypeMeIt.dmg asset, or if the Worker fails
# to deploy -- none of which touch the site itself. The page keeps loading and
# the button keeps looking fine, so nothing else would ever tell us.
#
# Requires NOTIFI_TOKEN.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${NOTIFI_TOKEN:?set NOTIFI_TOKEN}"

URL="${URL:-https://typeme.it/download}"

# HEAD, so the probe transfers no bytes: the Worker still has to reach GitHub
# and resolve the asset to answer it, which is the part that breaks. Pulling the
# body instead would spend bandwidth every run and, worse, tick GitHub's
# download counter -- the probe would end up polluting the numbers it exists to
# protect.
read -r code type <<<"$(curl -sS -I -o /dev/null \
  -w '%{http_code} %{content_type}' --max-time 30 "$URL" || true)"
: "${code:=000}" "${type:=none}"   # a curl that fails outright prints nothing

if [[ "$code" == "200" ]] && [[ "$type" == application/x-apple-diskimage* ]]; then
  echo "ok -- $code $type"
  exit 0
fi

echo "broken -- $code $type" >&2
curl -fsS -X POST https://notifi.it/send \
  -H "Authorization: Bearer $NOTIFI_TOKEN" \
  --data-urlencode "title=type me it · the download is broken" \
  --data-urlencode "message=$URL answered $code ($type). Nobody can install the app until this is fixed." \
  --data-urlencode "link=$URL" \
  > /dev/null || echo "could not reach notifi either" >&2
exit 1
