#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/dist/Keymote.app"

cd "$project_dir"
swift build -c release
rm -rf "$output_dir"
mkdir -p "$output_dir/Contents/MacOS" "$output_dir/Contents/Resources"
cp ".build/release/Keymote" "$output_dir/Contents/MacOS/Keymote"
cp "Resources/Info.plist" "$output_dir/Contents/Info.plist"
cp "Resources/Keymote.icns" "$output_dir/Contents/Resources/Keymote.icns"
signing_identity="${KEYMOTE_SIGNING_IDENTITY:-${SRI_VIBE_SIGNING_IDENTITY:-}}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1)"
fi
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$output_dir"
  echo "Applied ad-hoc signature (local development)."
else
  if [[ -z "$signing_identity" ]]; then
    codesign --force --sign - "$output_dir"
    echo "Applied ad-hoc signature (no local signing identity found)."
  else
    codesign --force --sign "$signing_identity" "$output_dir"
    echo "Applied stable local signature: $signing_identity"
  fi
fi
codesign --verify --deep --strict "$output_dir"
echo "Built $output_dir"
