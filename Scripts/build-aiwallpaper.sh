#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
derived_data_directory="${project_directory}/build/AIWallpaperDerivedData"
source_application="${derived_data_directory}/Build/Products/Release/LiveWallpaper.app"
package_directory="${project_directory}/build/AIWallpaperPackage"
packaged_application="${package_directory}/AIWallpaperEngineMac.app"
install_destination="/Applications/AIWallpaperEngineMac.app"
configuration_file="${project_directory}/Configurations/AIWallpaperEngineMac.xcconfig"

xcodebuild \
  -project "${project_directory}/LiveWallpaper.xcodeproj" \
  -scheme LiveWallpaper \
  -configuration Release \
  -derivedDataPath "${derived_data_directory}" \
  -xcconfig "${configuration_file}" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${source_application}" ]]; then
  print -u2 "Build product not found: ${source_application}"
  exit 1
fi

mkdir -p "${package_directory}"
if [[ -e "${packaged_application}" ]]; then
  print -u2 "Packaged application already exists: ${packaged_application}"
  print -u2 "Remove it explicitly before rebuilding."
  exit 1
fi

ditto "${source_application}" "${packaged_application}"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleName AIWallpaperEngineMac" \
  "${packaged_application}/Contents/Info.plist"
codesign --force --deep --sign - "${packaged_application}"
codesign --verify --deep --strict "${packaged_application}"

if [[ "${1:-}" == "--install" ]]; then
  if [[ -e "${install_destination}" ]]; then
    print -u2 "Install destination already exists: ${install_destination}"
    print -u2 "The existing application was not overwritten."
    exit 1
  fi

  ditto "${packaged_application}" "${install_destination}"
  codesign --verify --deep --strict "${install_destination}"
  print "Installed ${install_destination}"
else
  print "Built ${packaged_application}"
fi
