#!/usr/bin/env bash
# Fails if /ios drifted from /shared: bundle id, bundled resource folders,
# and every shared contract checked by shared/tools/sync-shared.mjs.
set -euo pipefail
ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$ios_dir/.." && pwd)"

config_id="$(cd "$root" && node -e "console.log(require('./shared/config/app.json').platforms.ios.bundleId)")"
yml_id="$(sed -n 's/^bundleID: *//p' "$ios_dir/xtool.yml")"
if [[ "$config_id" != "$yml_id" ]]; then
  echo "x xtool.yml bundleID ($yml_id) != shared/config/app.json ios.bundleId ($config_id)" >&2
  exit 1
fi

for dir in $(sed -n 's/^  - \(\.\.\/shared\/.*\)$/\1/p' "$ios_dir/xtool.yml"); do
  [[ -d "$ios_dir/$dir" ]] || { echo "x xtool.yml resource missing: $dir" >&2; exit 1; }
done

# /ios must never hold its own copy of a shared file.
if find "$ios_dir" -path "$ios_dir/.build" -prune -o \( -name '*.ttf' -o -name 'app.json' -o -name 'tokens.json' -o -name 'ar.json' -o -name 'en.json' \) -print | grep -q .; then
  echo "x a shared file was copied into /ios; reference ../shared instead" >&2
  exit 1
fi

(cd "$root" && node shared/tools/sync-shared.mjs --check)
echo "ios: shared links OK"
