#!/bin/sh
set -eu

project_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
output_dir="${1:-$project_dir}"
mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/snd-build.XXXXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcodebuild -quiet -project "$project_dir/Snd.xcodeproj" -scheme Snd \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$build_dir/DerivedData" ARCHS="arm64 x86_64" build

mkdir "$build_dir/workflow"
cp "$project_dir/Alfred/info.plist" "$build_dir/workflow/info.plist"
sips -Z 256 "$project_dir/Snd/Resources/Snd-icon.png" --out "$build_dir/workflow/icon.png" >/dev/null
ditto --norsrc "$build_dir/DerivedData/Build/Products/Release/Snd.app" "$build_dir/workflow/Snd.app"
ditto --norsrc -c -k "$build_dir/workflow" "$build_dir/Snd.alfredworkflow"
mv "$build_dir/Snd.alfredworkflow" "$output_dir/Snd.alfredworkflow"
