#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Missing release version."
  exit 1
fi

TAG="v${VERSION#v}"
DOWNLOAD_URL="https://github.com/okohring/kc-streetcar-guide/releases/download/${TAG}/kc-streetcar-guide.zip"
CHANGELOG="Simplifies category result headers to plain text, adds 60px top padding above the streetcar map, and keeps stop-specific category filters plus the horizontal overflow fixes."

perl -0pi -e "s/Version:\s*[0-9.]+/Version: $VERSION/" kc-streetcar-guide.php
perl -0pi -e "s/const VERSION = '[^']+';/const VERSION = '$VERSION';/" kc-streetcar-guide.php

python3 - <<'PY'
from pathlib import Path
import re

php = Path('kc-streetcar-guide.php')
content = php.read_text()
content = content.replace("        add_filter('upgrader_post_install', array($this, 'rename_release_folder'), 10, 3);\n", "")
content = re.sub(r"\n    public function rename_release_folder\(\$response, \$hook_extra, \$result\) \{.*?\n    \}\n", "\n", content, flags=re.S)
php.write_text(content)
PY

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

if ! grep -q "function buildControlBar" assets/kcsg-frontend.js; then
  echo "Stop dropdown behavior is missing from frontend JS."
  exit 1
fi

if ! grep -q "function resetResultsScroll" assets/kcsg-frontend.js; then
  echo "Amenities scroll reset behavior is missing from frontend JS."
  exit 1
fi

if ! grep -q "function renderStopCategoryKey" assets/kcsg-frontend.js; then
  echo "Stop-specific category filters are missing from frontend JS."
  exit 1
fi

if ! grep -q "function categoryHeaderMarkup" assets/kcsg-frontend.js; then
  echo "Category result headers are missing from frontend JS."
  exit 1
fi

if grep -q "All matching amenities along the streetcar route" assets/kcsg-frontend.js; then
  echo "Old category header description is still present."
  exit 1
fi

if ! grep -q "grid-template-columns: 400px minmax(0, 1fr)" assets/kcsg-frontend.css; then
  echo "400px map column CSS is missing."
  exit 1
fi

if ! grep -q "height: 900px !important" assets/kcsg-frontend.css; then
  echo "900px map SVG height is missing."
  exit 1
fi

if ! grep -q "padding-top: 60px !important" assets/kcsg-frontend.css; then
  echo "Streetcar map top padding is missing."
  exit 1
fi

if ! grep -q "kcsg-stop-feature:empty" assets/kcsg-frontend.css; then
  echo "Empty stop-feature spacing reset is missing."
  exit 1
fi

if ! grep -q "padding: 0 6px 0 0 !important" assets/kcsg-frontend.css; then
  echo "Results scroll spacing reset is missing."
  exit 1
fi

if ! grep -q "kcsg-stop-category-key" assets/kcsg-frontend.css; then
  echo "Stop category filter CSS is missing."
  exit 1
fi

if ! grep -q "kcsg-section-heading" assets/kcsg-frontend.css; then
  echo "Category heading CSS is missing."
  exit 1
fi

if ! grep -q "overflow-wrap: anywhere" assets/kcsg-frontend.css; then
  echo "Horizontal overflow wrapping fix is missing."
  exit 1
fi

if grep -q "compact screenshot-aligned layout correction" assets/kcsg-frontend.css; then
  echo "Old stacked correction CSS is still present."
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
- Simplifies category result headers to plain text only.
- Adds 60px top padding above the streetcar map/SVG.
- Keeps stop-specific category filter pills when viewing one streetcar stop.
- Keeps the horizontal overflow fixes for long category/card content.
- Keeps the safe release/update flow.
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
