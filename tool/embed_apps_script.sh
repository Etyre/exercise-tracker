#!/usr/bin/env bash
# Regenerates lib/sync/apps_script_source.dart from apps_script/Code.gs
set -euo pipefail
cd "$(dirname "$0")/.."
{
  echo "// GENERATED from apps_script/Code.gs — edit that file, then run:"
  echo "//   bash tool/embed_apps_script.sh"
  echo "const String appsScriptSource = r'''"
  cat apps_script/Code.gs
  echo "''';"
} > lib/sync/apps_script_source.dart
echo "Updated lib/sync/apps_script_source.dart"
