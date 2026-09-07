#!/bin/bash
# The daily download report, pushed to the phone through notifi.
#
#   Scripts/download-report.sh
#
# GitHub's per-asset download_count is cumulative and counts every fetch, so the
# number on its own says nothing. This keeps a dated snapshot in
# data/downloads.json and reports the delta since the last one.
#
# Two counters matter, and they measure different things:
#
#   the DMG      -- traffic. Inflated by repeat clicks, scrapers and link
#                   unfurlers, because the Worker fetches the asset once per
#                   visitor request and GitHub counts all of it.
#   appcast.xml  -- users. Sparkle checks hourly from every install, so the
#                   daily delta over 24 approximates how many Macs are running
#                   the app. Nobody sustains a fake install for days, which is
#                   what makes this the number worth trusting.
#
# Requires NOTIFI_TOKEN. GH_TOKEN is optional and only raises the API rate limit.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${NOTIFI_TOKEN:?set NOTIFI_TOKEN}"

REPO="${REPO:-maxisme/typemeit}"
HISTORY="data/downloads.json"
TODAY="$(date -u +%F)"

AUTH=()
[[ -n "${GH_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")

releases="$(curl -fsS "${AUTH[@]}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases?per_page=100")"

# Sum across every release, not just the latest -- people keep downloading an
# older DMG for a while after a release, and those fetches are still downloads.
snapshot="$(jq -c --arg date "$TODAY" '
  {
    date:    $date,
    dmg:     ([.[].assets[] | select(.name | endswith(".dmg"))     | .download_count] | add // 0),
    appcast: ([.[].assets[] | select(.name == "appcast.xml")       | .download_count] | add // 0),
    latest:  ([.[] | select(.draft or .prerelease | not) | .tag_name] | first // "none"),
  }' <<<"$releases")"

[[ -f "$HISTORY" ]] || echo "[]" > "$HISTORY"
previous="$(jq -c 'last // empty' "$HISTORY")"

# Re-running on a day already recorded replaces that entry rather than stacking
# a second one, so a manual dispatch cannot skew the next delta.
jq --argjson s "$snapshot" '[.[] | select(.date != $s.date)] + [$s]' "$HISTORY" > "$HISTORY.tmp"
mv "$HISTORY.tmp" "$HISTORY"

if [[ -z "$previous" ]]; then
  echo "no previous snapshot -- recorded the baseline, nothing to compare"
  exit 0
fi

read -r days dmg_delta appcast_delta dmg_total latest <<<"$(jq -rn \
  --argjson p "$previous" --argjson s "$snapshot" '
  # Snapshots are not guaranteed a day apart: a failed or skipped run leaves a
  # longer gap, and the rates have to be divided by it to stay comparable.
  (((($s.date | strptime("%Y-%m-%d") | mktime) - ($p.date | strptime("%Y-%m-%d") | mktime)) / 86400) | floor) as $d
  | [([$d, 1] | max), ($s.dmg - $p.dmg), ($s.appcast - $p.appcast), $s.dmg, $s.latest] | @tsv')"

installs=$(( appcast_delta / (24 * days) ))
per_day=$(( dmg_delta / days ))

echo "downloads +$dmg_delta over $days day(s), appcast +$appcast_delta, ~$installs installs"

# A push saying nothing happened trains you to ignore the next one that matters.
if (( dmg_delta == 0 && appcast_delta == 0 )); then
  echo "nothing moved -- no notification sent"
  exit 0
fi

label="downloads"; (( per_day == 1 )) && label="download"
message="$per_day $label a day, $dmg_total all time
~$installs Macs running $latest
appcast checks +$appcast_delta"

curl -fsS -X POST https://notifi.it/send \
  -H "Authorization: Bearer $NOTIFI_TOKEN" \
  --data-urlencode "title=type me it · +$dmg_delta downloads" \
  --data-urlencode "message=$message" \
  --data-urlencode "link=https://github.com/$REPO/releases" \
  > /dev/null
echo "notification sent"
