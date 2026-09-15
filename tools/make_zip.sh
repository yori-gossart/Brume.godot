#!/usr/bin/env bash
# Build the importable archive for the Godot Editor for Android.
#
# Godot imports a ZIP whose project.godot is either at the root or one
# directory down. This produces the second shape, so the extracted folder is
# named rather than dumping files loose.
#
# Deliberately excluded: .godot/ (the import cache — several tens of MB, and
# regenerated on first open), .git/, and the build output itself.
set -euo pipefail

NAME="nomadsland-godot-0.2.1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
STAGE="$OUT/$NAME"

rm -rf "$STAGE" "$OUT/$NAME.zip"
mkdir -p "$STAGE"

# Everything the project needs, and nothing else.
for item in project.godot icon.svg README.md .gitignore \
            scenes scripts shaders assets docs tools tests; do
    [ -e "$ROOT/$item" ] && cp -R "$ROOT/$item" "$STAGE/"
done

# Belt and braces: no caches, no VCS, no OS droppings.
find "$STAGE" -name '.godot' -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -name '.git*' -maxdepth 2 -not -name '.gitignore' -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true
find "$STAGE" -name 'Thumbs.db' -delete 2>/dev/null || true
find "$STAGE" -name '*~' -delete 2>/dev/null || true

( cd "$OUT" && zip -q -r -9 "$NAME.zip" "$NAME" )
rm -rf "$STAGE"

echo "built  $OUT/$NAME.zip"
echo "size   $(du -h "$OUT/$NAME.zip" | cut -f1)"
echo "files  $(unzip -l "$OUT/$NAME.zip" | tail -1 | awk '{print $2}')"
