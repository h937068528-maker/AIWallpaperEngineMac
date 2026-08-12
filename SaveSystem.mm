/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include "SaveSystem.h"
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <unistd.h>

static std::string configPath() {
  return std::string(NSHomeDirectory().fileSystemRepresentation) +
         "/Library/Preferences/AIWallpaperEngineMac.yaml";
}

// ------------------------
// YAML Conversion
// ------------------------
namespace YAML {

template <> struct convert<Display> {
  static Node encode(const Display &d) {
    Node node;
    node["uuid"] = d.uuid;
    node["screen"] = d.screen;
    node["video"] = d.videoPath;
    node["frame"] = d.framePath;
    node["daemon"] = (int)d.daemon;
    return node;
  }

  static bool decode(const Node &node, Display &d) {
    try {
      d.uuid = node["uuid"] ? node["uuid"].as<std::string>() : "";
      d.videoPath =
          node["video"] ? node["video"].as<std::string>() : "";
      d.framePath =
          node["frame"] ? node["frame"].as<std::string>() : "";
    } catch (const YAML::Exception &) {
      return false;
    }

    // Display IDs and process IDs are runtime-only values. Restoring a stale
    // daemon PID can target an unrelated process, and malformed legacy values
    // must never prevent the app from launching.
    d.screen = kCGNullDirectDisplay;
    d.daemon = 0;
    return !d.uuid.empty();
  }
};

} // namespace YAML

// ------------------------
// Save
// ------------------------
void SaveSystem::Save(const std::list<Display> &displays) {
  YAML::Node root;

  for (const auto &d : displays)
    root["displays"].push_back(d);

  const std::string destination = configPath();
  const std::string backup = destination + ".backup";
  std::error_code backupError;
  if (std::filesystem::exists(destination) &&
      !std::filesystem::exists(backup)) {
    std::filesystem::copy_file(
        destination, backup,
        std::filesystem::copy_options::none, backupError);
  }
  const std::string temporary =
      destination + "." + std::to_string(getpid()) + ".tmp";
  std::ofstream out(temporary, std::ios::trunc);
  if (!out) {
    return;
  }
  out << root;
  out.flush();
  if (!out.good()) {
    out.close();
    std::remove(temporary.c_str());
    return;
  }
  out.close();

  if (std::rename(temporary.c_str(), destination.c_str()) != 0) {
    std::remove(temporary.c_str());
  }
}

// ------------------------
// Load
// ------------------------
std::list<Display> SaveSystem::Load() {
  std::list<Display> result;

  const auto path = configPath();
  if (!std::filesystem::exists(path))
    return result;

  YAML::Node root;
  try {
    root = YAML::LoadFile(path);
  } catch (const YAML::Exception &error) {
    NSLog(@"Unable to read display session file: %s", error.what());
    return result;
  }

  if (!root["displays"])
    return result;

  for (auto node : root["displays"]) {
    Display d{};
    if (!YAML::convert<Display>::decode(node, d))
      continue;
    d.screen = DisplayIDFromUUID(d.uuid);
    result.push_back(d);
  }

  return result;
}
