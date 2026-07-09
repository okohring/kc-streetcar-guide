#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Missing release version."
  exit 1
fi

TAG="v${VERSION#v}"
DOWNLOAD_URL="https://github.com/okohring/kc-streetcar-guide/releases/download/${TAG}/kc-streetcar-guide.zip"
CHANGELOG="Locks category result header typography against themes, keeps Google Maps links with a waypoint icon, and adds a separate optional website URL field that uses the external-link icon."

perl -0pi -e "s/Version:\s*[0-9.]+/Version: $VERSION/" kc-streetcar-guide.php
perl -0pi -e "s/const VERSION = '[^']+';/const VERSION = '$VERSION';/" kc-streetcar-guide.php

python3 - <<'PY'
from pathlib import Path
import re

php = Path('kc-streetcar-guide.php')
content = php.read_text()
content = content.replace("        add_filter('upgrader_post_install', array($this, 'rename_release_folder'), 10, 3);\n", "")
content = re.sub(r"\n    public function rename_release_folder\(\$response, \$hook_extra, \$result\) \{.*?\n    \}\n", "\n", content, flags=re.S)

category_columns_old = """    public function category_columns($columns) {
        $new_columns = array();

        foreach ($columns as $key => $label) {
"""
category_columns_new = """    public function category_columns($columns) {
        unset($columns['slug'], $columns['description']);

        $new_columns = array();

        foreach ($columns as $key => $label) {
"""
if category_columns_old in content:
    content = content.replace(category_columns_old, category_columns_new, 1)

admin_styles_old = """    public function admin_styles($hook) {
        global $post_type;

        $is_amenity_screen = ($post_type === self::CPT);
        $is_stop_photo_page = isset($_GET['page']) && sanitize_key(wp_unslash($_GET['page'])) === 'kcsg-stop-photos';

        if (!$is_amenity_screen && !$is_stop_photo_page) {
            return;
        }
"""
admin_styles_new = """    public function admin_styles($hook) {
        global $post_type, $taxonomy;

        $current_taxonomy = $taxonomy ? $taxonomy : (isset($_GET['taxonomy']) ? sanitize_key(wp_unslash($_GET['taxonomy'])) : '');
        $is_amenity_screen = ($post_type === self::CPT);
        $is_category_screen = ($current_taxonomy === self::TAX);
        $is_stop_photo_page = isset($_GET['page']) && sanitize_key(wp_unslash($_GET['page'])) === 'kcsg-stop-photos';

        if (!$is_amenity_screen && !$is_category_screen && !$is_stop_photo_page) {
            return;
        }
"""
if admin_styles_old in content:
    content = content.replace(admin_styles_old, admin_styles_new, 1)

admin_css_anchor = """        wp_add_inline_style('wp-admin', '
            .kcsg-admin-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 18px; }
"""
admin_css_replacement = """        wp_add_inline_style('wp-admin', '
            body.taxonomy-kcsg_category .term-slug-wrap,
            body.taxonomy-kcsg_category .term-description-wrap,
            body.taxonomy-kcsg_category .column-slug,
            body.taxonomy-kcsg_category .column-description { display: none !important; }
            .kcsg-admin-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 18px; }
"""
if admin_css_anchor in content:
    content = content.replace(admin_css_anchor, admin_css_replacement, 1)

meta_url_old = """        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
"""
meta_url_new = """        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $website_url = get_post_meta($post->ID, '_kcsg_website_url', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
"""
if meta_url_old in content:
    content = content.replace(meta_url_old, meta_url_new, 1)

url_field_old = """            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://example.com" />
            </p>
"""
url_field_new = """            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('Google Maps URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://www.google.com/maps/search/?api=1&query=..." />
            </p>

            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_website_url"><strong><?php esc_html_e('Website URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_website_url" id="kcsg_website_url" value="<?php echo esc_url($website_url); ?>" placeholder="https://www.example.org/" />
            </p>
"""
if url_field_old in content:
    content = content.replace(url_field_old, url_field_new, 1)

save_url_old = """            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => isset($_POST['kcsg_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_url'])) : '',
        );
"""
save_url_new = """            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => isset($_POST['kcsg_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_url'])) : '',
            '_kcsg_website_url' => isset($_POST['kcsg_website_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_website_url'])) : '',
        );
"""
if save_url_old in content:
    content = content.replace(save_url_old, save_url_new, 1)

data_url_old = """                'description' => get_post_meta($post->ID, '_kcsg_description', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
            );
"""
data_url_new = """                'description' => get_post_meta($post->ID, '_kcsg_description', true),
                'mapUrl' => get_post_meta($post->ID, '_kcsg_url', true),
                'websiteUrl' => get_post_meta($post->ID, '_kcsg_website_url', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
            );
"""
if data_url_old in content:
    content = content.replace(data_url_old, data_url_new, 1)

php.write_text(content)

js = Path('assets/kcsg-frontend.js')
js_content = js.read_text()
old_url_markup = """      var urlMarkup = amenity.url ? '<a class="kcsg-link" href="' + esc(amenity.url) + '" target="_blank" rel="noopener noreferrer" aria-label="Open website for ' + esc(amenity.name) + '"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M14 3h7v7h-2V6.41l-9.29 9.3-1.42-1.42 9.3-9.29H14V3Z"></path><path d="M5 5h6v2H7v10h10v-4h2v6H5V5Z"></path></svg></a>' : '';
"""
new_url_markup = """      var mapUrl = amenity.mapUrl || amenity.url || '';
      var websiteUrl = amenity.websiteUrl || '';
      var websiteUrlMarkup = websiteUrl ? '<a class="kcsg-link kcsg-link--website" href="' + esc(websiteUrl) + '" target="_blank" rel="noopener noreferrer" aria-label="Open website for ' + esc(amenity.name) + '"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M14 3h7v7h-2V6.41l-9.29 9.3-1.42-1.42 9.3-9.29H14V3Z"></path><path d="M5 5h6v2H7v10h10v-4h2v6H5V5Z"></path></svg></a>' : '';
      var mapUrlMarkup = mapUrl ? '<a class="kcsg-link kcsg-link--map" href="' + esc(mapUrl) + '" target="_blank" rel="noopener noreferrer" aria-label="Open Google Maps for ' + esc(amenity.name) + '"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M12 2a7 7 0 0 0-7 7c0 5.25 7 13 7 13s7-7.75 7-13a7 7 0 0 0-7-7Zm0 9.5A2.5 2.5 0 1 1 12 6a2.5 2.5 0 0 1 0 5.5Z"></path></svg></a>' : '';
"""
if old_url_markup in js_content:
    js_content = js_content.replace(old_url_markup, new_url_markup, 1)

old_actions = """            '<div class="kcsg-card-actions">' + categoryMarkup + urlMarkup + '</div>' +
"""
new_actions = """            '<div class="kcsg-card-actions">' + categoryMarkup + websiteUrlMarkup + mapUrlMarkup + '</div>' +
"""
if old_actions in js_content:
    js_content = js_content.replace(old_actions, new_actions, 1)

js.write_text(js_content)
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

if ! grep -q "unset(\$columns\['slug'\], \$columns\['description'\])" kc-streetcar-guide.php; then
  echo "Category slug/description columns are still visible."
  exit 1
fi

if ! grep -q "is_category_screen" kc-streetcar-guide.php; then
  echo "Category admin screen detection is missing."
  exit 1
fi

if ! grep -q "term-slug-wrap" kc-streetcar-guide.php; then
  echo "Category slug field hiding CSS is missing."
  exit 1
fi

if ! grep -q "term-description-wrap" kc-streetcar-guide.php; then
  echo "Category description field hiding CSS is missing."
  exit 1
fi

if ! grep -q "Google Maps URL" kc-streetcar-guide.php; then
  echo "Google Maps URL admin field label is missing."
  exit 1
fi

if ! grep -q "Website URL" kc-streetcar-guide.php; then
  echo "Website URL admin field label is missing."
  exit 1
fi

if ! grep -q "_kcsg_website_url" kc-streetcar-guide.php; then
  echo "Website URL post meta field is missing."
  exit 1
fi

if ! grep -q "'mapUrl'" kc-streetcar-guide.php; then
  echo "Map URL frontend data field is missing."
  exit 1
fi

if ! grep -q "'websiteUrl'" kc-streetcar-guide.php; then
  echo "Website URL frontend data field is missing."
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

if ! grep -q "kcsg-link--map" assets/kcsg-frontend.js; then
  echo "Google Maps waypoint link is missing from frontend JS."
  exit 1
fi

if ! grep -q "kcsg-link--website" assets/kcsg-frontend.js; then
  echo "Website external link is missing from frontend JS."
  exit 1
fi

if ! grep -q "Open Google Maps" assets/kcsg-frontend.js; then
  echo "Google Maps link label is missing from frontend JS."
  exit 1
fi

if ! grep -q "kiosk-6e6b4.firebaseio.com" assets/kcsg-frontend.js; then
  echo "Firebase arrivals endpoint is missing from frontend JS."
  exit 1
fi

if ! grep -q "Riverfront (Northbound)" assets/kcsg-frontend.js; then
  echo "Riverfront direction label is missing from frontend JS."
  exit 1
fi

if ! grep -q "UMKC (Southbound)" assets/kcsg-frontend.js; then
  echo "UMKC direction label is missing from frontend JS."
  exit 1
fi

if ! grep -q "ARRIVAL_CACHE_MS = 30000" assets/kcsg-frontend.js; then
  echo "30-second arrivals refresh/cache timing is missing from frontend JS."
  exit 1
fi

if ! grep -q "Arriving soon" assets/kcsg-frontend.js; then
  echo "Visitor-friendly arriving-soon wording is missing from frontend JS."
  exit 1
fi

if ! grep -q "KC Streetcar Guide theme shield" assets/kcsg-theme-shield.css; then
  echo "Scoped frontend theme shield source file is missing."
  exit 1
fi

if ! grep -q "font-family: system-ui" assets/kcsg-theme-shield.css; then
  echo "Theme shield typography baseline is missing."
  exit 1
fi

if ! grep -q "appearance: none" assets/kcsg-theme-shield.css; then
  echo "Theme shield button/select reset is missing."
  exit 1
fi

if ! grep -q "KC Streetcar Guide final theme overrides" assets/kcsg-theme-overrides.css; then
  echo "Final theme override source file is missing."
  exit 1
fi

if ! grep -q "all: unset" assets/kcsg-theme-overrides.css; then
  echo "Final amenity heading reset is missing."
  exit 1
fi

if ! grep -q "article.kcsg-card h4" assets/kcsg-theme-overrides.css; then
  echo "Final amenity heading selector is missing."
  exit 1
fi

if ! grep -q "kcsg-section-heading h3" assets/kcsg-theme-overrides.css; then
  echo "Final category heading reset is missing."
  exit 1
fi

if ! grep -q "KC Streetcar Guide layout lock" assets/kcsg-layout-lock.css; then
  echo "Desktop layout lock source file is missing."
  exit 1
fi

if ! grep -q -- "--kcsg-card-standard-width: 520px" assets/kcsg-layout-lock.css; then
  echo "Standard 520px card/header width is missing."
  exit 1
fi

if ! grep -q -- "--kcsg-map-standard-width: 400px" assets/kcsg-layout-lock.css; then
  echo "Standard 400px map width is missing."
  exit 1
fi

if ! grep -q "KC Streetcar Guide stop header photo height" assets/kcsg-stop-header-height.css; then
  echo "Stop header height override source file is missing."
  exit 1
fi

if ! grep -q "height: 260px" assets/kcsg-stop-header-height.css; then
  echo "260px stop header height is missing."
  exit 1
fi

if ! grep -q "rgba(255, 255, 255, 1)" assets/kcsg-stop-header-height.css; then
  echo "Strong stop header legibility gradient is missing."
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

if grep -q "padding-top: 60px !important" assets/kcsg-frontend.css; then
  echo "Streetcar map top padding should not be present."
  exit 1
fi

if grep -q "width: 480px" assets/kcsg-frontend.css; then
  echo "Fixed 480px stop photo/header width should not be present."
  exit 1
fi

if ! grep -q "kcsg-live-row" assets/kcsg-frontend.css; then
  echo "Live arrival row CSS is missing."
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

cat build/kc-streetcar-guide/assets/kcsg-theme-shield.css build/kc-streetcar-guide/assets/kcsg-frontend.css build/kc-streetcar-guide/assets/kcsg-theme-overrides.css build/kc-streetcar-guide/assets/kcsg-layout-lock.css build/kc-streetcar-guide/assets/kcsg-stop-header-height.css > build/kc-streetcar-guide/assets/kcsg-frontend.merged.css
mv build/kc-streetcar-guide/assets/kcsg-frontend.merged.css build/kc-streetcar-guide/assets/kcsg-frontend.css

if ! grep -q "KC Streetcar Guide theme shield" build/kc-streetcar-guide/assets/kcsg-frontend.css; then
  echo "Theme shield was not merged into release CSS."
  exit 1
fi

if ! grep -q "KC Streetcar Guide final theme overrides" build/kc-streetcar-guide/assets/kcsg-frontend.css; then
  echo "Final theme overrides were not merged into release CSS."
  exit 1
fi

if ! grep -q "kcsg-section-heading h3" build/kc-streetcar-guide/assets/kcsg-frontend.css; then
  echo "Category heading override was not merged into release CSS."
  exit 1
fi

if ! grep -q "KC Streetcar Guide layout lock" build/kc-streetcar-guide/assets/kcsg-frontend.css; then
  echo "Desktop layout lock was not merged into release CSS."
  exit 1
fi

if ! grep -q "KC Streetcar Guide stop header photo height" build/kc-streetcar-guide/assets/kcsg-frontend.css; then
  echo "Stop header height override was not merged into release CSS."
  exit 1
fi

cd build
zip -r kc-streetcar-guide.zip kc-streetcar-guide
cd ..

NOTES=$(cat <<'NOTES'
- Locks category result header typography against aggressive theme heading styles.
- Keeps Google Maps links on amenity cards and changes their icon to a waypoint/map-pin symbol.
- Adds a separate optional Website URL field for amenities; when present, it uses the external-link box-arrow icon.
- Keeps the 260px readable stop headers, 520px desktop card/header width lock, hidden category slug/description fields, theme shielding, Firebase-backed live arrivals, and safe release/update flow.
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
