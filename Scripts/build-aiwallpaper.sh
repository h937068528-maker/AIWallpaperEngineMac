#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
derived_data_directory="${project_directory}/build/AIWallpaperDerivedData"
source_application="${derived_data_directory}/Build/Products/Release/AIWallpaperEngineMac.app"
install_destination="/Applications/AIWallpaperEngineMac.app"
configuration_file="${project_directory}/Configurations/AIWallpaperEngineMac.xcconfig"
output_directory="${project_directory:h:h}/outputs"
introduction_file="${project_directory}/Distribution/安装与功能介绍.txt"
third_party_notices_file="${project_directory}/ThirdPartyNotices.md"
web_bridge_document="${project_directory}/Distribution/WebWallpaperBridge.md"

xcodebuild \
  -project "${project_directory}/LiveWallpaper.xcodeproj" \
  -scheme LiveWallpaper \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "${derived_data_directory}" \
  -xcconfig "${configuration_file}" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${source_application}" ]]; then
  print -u2 "Build product not found: ${source_application}"
  exit 1
fi

marketing_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${source_application}/Contents/Info.plist")
package_directory="${project_directory}/build/AIWallpaperPackage-${marketing_version}"
packaged_application="${package_directory}/AIWallpaperEngineMac.app"
dmg_path="${output_directory}/AIWallpaperEngineMac-${marketing_version}-Full-GPU-Particles-arm64.dmg"

mkdir -p "${package_directory}"
if [[ -e "${packaged_application}" ]]; then
  print -u2 "Packaged application already exists: ${packaged_application}"
  print -u2 "Remove it explicitly before rebuilding."
  exit 1
fi

ditto "${source_application}" "${packaged_application}"
if [[ ! -f "${introduction_file}" ]]; then
  print -u2 "Installation introduction not found: ${introduction_file}"
  exit 1
fi
ditto "${introduction_file}" "${package_directory}/安装与功能介绍.txt"
if [[ ! -f "${third_party_notices_file}" ]]; then
  print -u2 "Third-party notices not found: ${third_party_notices_file}"
  exit 1
fi
ditto "${third_party_notices_file}" "${package_directory}/ThirdPartyNotices.md"
if [[ ! -f "${web_bridge_document}" ]]; then
  print -u2 "Web wallpaper bridge document not found: ${web_bridge_document}"
  exit 1
fi
ditto "${web_bridge_document}" "${package_directory}/WebWallpaperBridge.md"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleName AIWallpaperEngineMac" \
  "${packaged_application}/Contents/Info.plist"
codesign --force --deep --sign - "${packaged_application}"
codesign --verify --deep --strict "${packaged_application}"

ln -s /Applications "${package_directory}/Applications"
mkdir -p "${output_directory}"
if [[ -e "${dmg_path}" ]]; then
  print -u2 "Disk image already exists: ${dmg_path}"
  print -u2 "The existing installer was not overwritten."
  exit 1
fi
hdiutil create \
  -volname "AIWallpaperEngineMac ${marketing_version}" \
  -srcfolder "${package_directory}" \
  -ov \
  -format UDZO \
  "${dmg_path}"

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
  print "Created ${dmg_path}"
fi
