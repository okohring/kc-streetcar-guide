#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Missing release version."
  exit 1
fi

TAG="v${VERSION#v}"
DOWNLOAD_URL="https://github.com/okohring/kc-streetcar-guide/releases/download/${TAG}/kc-streetcar-guide.zip"
CHANGELOG="Corrected the compact visitor guide layout to better match the provided mockup, including tighter header spacing, a capped guide width, a smaller map column, and a more compact stop photo/card stack."

perl -0pi -e "s/Version:\s*[0-9.]+/Version: $VERSION/" kc-streetcar-guide.php
perl -0pi -e "s/const VERSION = '[^']+';/const VERSION = '$VERSION';/" kc-streetcar-guide.php

python3 .github/build-release-patch.py
cat .github/layout-compact-correction.css >> assets/kcsg-frontend.css

if ! grep -q "Version: $VERSION" kc-streetcar-guide.php; then
  echo "Plugin header version does not match release version $VERSION."
  exit 1
fi

if ! grep -q "const VERSION = '$VERSION'" kc-streetcar-guide.php; then
  echo "KCSG_Plugin::VERSION does not match release version $VERSION."
  exit 1
fi

if grep -q "upgrader_post_install" kc-streetcar-guide.php; then
  echo "Unsafe post-install updater hook is still present."
  exit 1
fi

if ! grep -q "kcsg-stop-select" assets/kcsg-frontend.js; then
  echo "Stop select UI patch was not applied."
  exit 1
fi

if ! grep -q "visitor guide controls UI overhaul" assets/kcsg-frontend.css; then
  echo "UI overhaul CSS patch was not applied."
  exit 1
fi

if ! grep -q "compact screenshot-aligned layout correction" assets/kcsg-frontend.css; then
  echo "Compact layout correction CSS was not applied."
  exit 1
fi

rm -rf build
mkdir -p build/kc-streetcar-guide
rsync -av \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='build' \
  --exclude='.DS_Store' \
  ./ build/kc-streetcar-guide/

cd build
zip -r kc-streetcar-guide.zip kc-streetcar-guide
cd ..

NOTES=$(cat <<'NOTES'
- Corrected the compact visitor guide layout to better match the provided mockup.
- Tightened the header, intro text, and controls spacing.
- Capped the guide width so the layout does not stretch too wide.
- Reduced the map/content scale and tightened the stop photo/card stack.
- Kept the safe release/update flow.
NOTES
)

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" build/kc-streetcar-guide.zip --clobber
else
  gh release create "$TAG" build/kc-streetcar-guide.zip \
    --title "KC Streetcar Guide $VERSION" \
    --notes "KC Streetcar Guide $VERSION

$NOTES" \
    --target "$GITHUB_SHA" \
    --latest
fi

# Only after the ZIP has been successfully uploaded do we publish the update manifest.
cat > update.json <<EOF
{
  "name": "KC Streetcar Guide",
  "slug": "kc-streetcar-guide",
  "version": "$VERSION",
  "download_url": "$DOWNLOAD_URL",
  "details_url": "https://github.com/okohring/kc-streetcar-guide",
  "requires": "6.0",
  "tested": "6.6",
  "requires_php": "7.4",
  "description": "Interactive WordPress visitor guide for amenities near the KC Streetcar line.",
  "changelog": "$CHANGELOG"
}
EOF

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add update.json

if git diff --cached --quiet; then
  echo "update.json already points to $VERSION."
else
  git commit -m "Point update manifest to $VERSION release"
  git push origin "HEAD:${GITHUB_REF_NAME:-main}"
fi
