#!/usr/bin/env bash
# Keeps the image's default Xcode when it is new enough, else switches to the
# newest installed /Applications/Xcode*.app; fails below the minimum.
# The iOS 27.1 SDK is what makes the app native on iPhone Duo.
set -euo pipefail
minimum=27.1
at_least() { [[ "$(printf '%s\n%s\n' "$minimum" "$1" | sort -V | head -1)" == "$minimum" ]]; }
current=$(xcodebuild -version | awk 'NR==1{print $2}')
if ! at_least "$current"; then
  newest=''
  newest_version=0
  for app in /Applications/Xcode*.app; do
    [[ -d "$app" && ! -L "$app" ]] || continue
    v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null) || continue
    if [[ "$(printf '%s\n%s\n' "$newest_version" "$v" | sort -V | tail -1)" == "$v" ]]; then
      newest=$app
      newest_version=$v
    fi
  done
  echo "Default Xcode $current is older than $minimum; newest installed: ${newest:-none}"
  [[ -n "$newest" ]] && sudo xcode-select --switch "$newest/Contents/Developer"
fi
xcodebuild -version
xcodebuild -showsdks | grep -E 'iphone(os|simulator)'
current=$(xcodebuild -version | awk 'NR==1{print $2}')
at_least "$current" || { echo "::error::Usage needs Xcode $minimum or later, found $current"; exit 1; }
for sdk in iphoneos iphonesimulator; do
  version=$(xcrun --sdk "$sdk" --show-sdk-version)
  at_least "$version" || { echo "::error::Usage needs the $sdk $minimum SDK or later, found $version"; exit 1; }
done
