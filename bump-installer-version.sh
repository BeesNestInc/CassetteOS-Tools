#!/bin/bash
# 複数のスクリプトのバージョン表記を一括更新する半自動スクリプト
# 対象: update.sh, install.sh, uninstall.sh
# 使い方: bump-installer-version.sh v0.0.3

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 v<version>"
  exit 1
fi

VERSION="$1"
FILES=("update.sh" "install.sh" "uninstall.sh")

# チェック：バージョン形式 vX.Y.Z
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in format vX.Y.Z (e.g., v0.0.3)"
  exit 1
fi

echo "🔧 Updating scripts to version $VERSION ..."

for FILE in "${FILES[@]}"; do
  if [ ! -f "$FILE" ]; then
    echo "⚠️  Skipping $FILE (not found)"
    continue
  fi

  echo "📄 Updating $FILE..."

  # 1. ヘッダーの Script vX.Y.Z を書き換え
  sed -i -E "s/(CassetteOS (Update|Installer|Uninstaller) Script) v[0-9]+\.[0-9]+\.[0-9]+/\1 ${VERSION}/" "$FILE"

  # 2. wget/curl の固定バージョンURLを書き換え
  sed -i -E "s|(releases/download/)v[0-9]+\.[0-9]+\.[0-9]+(/\w*\.sh)|\1${VERSION}\2|g" "$FILE"

  # 3. readonly の CASSETTEOS_VERSION を書き換え
  sed -i -E "s/^readonly CASSETTEOS_VERSION=\"v[0-9]+\.[0-9]+\.[0-9]+\"/readonly CASSETTEOS_VERSION=\"${VERSION}\"/" "$FILE"

done

echo "✅ All done. Updated version to $VERSION"