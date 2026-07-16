#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Missing release version."
  exit 1
fi

VERSION="${VERSION#v}"
TAG="v${VERSION}"
PACKAGE_DIR="build/kc-streetcar-guide"
ZIP_FILE="build/kc-streetcar-guide.zip"
CHANGELOG="Removes Advanced Settings and nonworking font controls, adds the Explore KC shortcode and customizable featured badge label to the Amenities screen, cleans up amenity help text, and fixes the unchecked featured checkbox display."

if [ ! -d "$PACKAGE_DIR" ]; then
  echo "The release package directory does not exist: $PACKAGE_DIR"
  exit 1
fi

if ! grep -q "FEATURED_LABEL_OPTION" "$PACKAGE_DIR/kc-streetcar-guide.php"; then
  echo "Applying Explore KC release fixes."
  PATCH_FILE="$(mktemp)"
  printf '%s' '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' | base64 --decode | gzip --decompress > "$PATCH_FILE"
  (
    cd "$PACKAGE_DIR"
    patch -p1 --forward --batch < "$PATCH_FILE"
  )
  rm -f "$PATCH_FILE"
else
  echo "Explore KC release fixes are already present."
fi

cat > update.json <<JSON
{
  "name": "KC Streetcar Guide",
  "slug": "kc-streetcar-guide",
  "version": "$VERSION",
  "download_url": "https://github.com/okohring/kc-streetcar-guide/releases/download/$TAG/kc-streetcar-guide.zip",
  "details_url": "https://github.com/okohring/kc-streetcar-guide",
  "requires": "6.0",
  "tested": "6.6",
  "requires_php": "7.4",
  "description": "Interactive WordPress visitor guide for amenities near the KC Streetcar line.",
  "changelog": "$CHANGELOG"
}
JSON
cp update.json "$PACKAGE_DIR/update.json"

if grep -q "Advanced Settings\|kcsg_font_settings\|Visitors can use this link for route" "$PACKAGE_DIR/kc-streetcar-guide.php"; then
  echo "Removed settings or help text are still present in the release package."
  exit 1
fi

for required in \
  'Explore KC shortcode' \
  'FEATURED_LABEL_OPTION' \
  'featuredLabel' \
  'kcsg-featured-toggle'; do
  if ! grep -q "$required" "$PACKAGE_DIR/kc-streetcar-guide.php" "$PACKAGE_DIR/assets/kcsg-frontend.js"; then
    echo "Required release marker is missing: $required"
    exit 1
  fi
done

php -l "$PACKAGE_DIR/kc-streetcar-guide.php"
node --check "$PACKAGE_DIR/assets/kcsg-frontend.js"

rm -f "$ZIP_FILE"
(
  cd build
  zip -qr kc-streetcar-guide.zip kc-streetcar-guide
)

gh release upload "$TAG" "$ZIP_FILE" --clobber

NOTES_FILE="$(mktemp)"
cat > "$NOTES_FILE" <<NOTES
KC Streetcar Guide $VERSION

- Removes the Advanced Settings menu and nonworking font controls.
- Shows the full Explore Kansas City shortcode on the Amenities screen.
- Removes the requested amenity helper text.
- Makes the Executive Pick badge label customizable while keeping it as the default.
- Fixes the unchecked featured checkbox display.
NOTES
gh release edit "$TAG" --title "KC Streetcar Guide $VERSION" --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add update.json
if git diff --cached --quiet; then
  echo "update.json already points to $VERSION."
else
  git commit -m "Finalize $VERSION release manifest"
  git push origin "HEAD:${GITHUB_REF_NAME:-main}"
fi
