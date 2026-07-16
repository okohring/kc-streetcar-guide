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

python3 - "$PACKAGE_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
php_path = root / 'kc-streetcar-guide.php'
js_path = root / 'assets/kcsg-frontend.js'
readme_path = root / 'README.md'
php = php_path.read_text()


def method_span(text, name):
    match = re.search(r'\n    public (?:static )?function\s+' + re.escape(name) + r'\s*\(', text)
    if not match:
        return None
    start = match.start() + 1
    brace = text.find('{', match.end())
    if brace < 0:
        raise RuntimeError(f'Opening brace not found for {name}')
    depth = 0
    quote = None
    escaped = False
    i = brace
    while i < len(text):
        ch = text[i]
        if quote:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
        else:
            if ch in "'\"":
                quote = ch
            elif ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    end = i + 1
                    while end < len(text) and text[end] in '\r\n':
                        end += 1
                    return start, end
        i += 1
    raise RuntimeError(f'Closing brace not found for {name}')


def replace_method(text, old_name, block):
    span = method_span(text, old_name)
    if not span:
        raise RuntimeError(f'Method not found: {old_name}')
    return text[:span[0]] + block.rstrip() + '\n\n' + text[span[1]:]


featured_method = r'''    public static function get_featured_label() {
        $label = sanitize_text_field((string) get_option(self::FEATURED_LABEL_OPTION, ''));
        return $label !== '' ? $label : __('Executive Pick', 'kc-streetcar-guide');
    }'''

tools_method = r'''    public function render_amenities_screen_tools() {
        $screen = function_exists('get_current_screen') ? get_current_screen() : null;
        if (!$screen || $screen->id !== 'edit-' . self::CPT) {
            return;
        }

        $shortcode = '[kc_streetcar_guide title="Explore Kansas City" intro="Choose a category or click a streetcar stop."]';
        $featured_label = self::get_featured_label();
        ?>
        <div class="notice kcsg-guide-tools">
            <div class="kcsg-guide-tools__shortcode">
                <strong><?php esc_html_e('Explore KC shortcode', 'kc-streetcar-guide'); ?></strong>
                <code><?php echo esc_html($shortcode); ?></code>
            </div>

            <?php if (current_user_can('manage_options')) : ?>
                <form class="kcsg-guide-tools__form" method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                    <input type="hidden" name="action" value="kcsg_save_guide_settings" />
                    <?php wp_nonce_field('kcsg_guide_settings_nonce', 'kcsg_guide_settings_nonce'); ?>
                    <label for="kcsg_featured_label"><strong><?php esc_html_e('Featured label', 'kc-streetcar-guide'); ?></strong></label>
                    <input type="text" id="kcsg_featured_label" name="kcsg_featured_label" value="<?php echo esc_attr($featured_label); ?>" maxlength="60" />
                    <?php submit_button(__('Save Label', 'kc-streetcar-guide'), 'secondary', 'submit', false); ?>
                </form>
            <?php endif; ?>
        </div>

        <?php if (isset($_GET['kcsg_settings_updated']) && sanitize_text_field(wp_unslash($_GET['kcsg_settings_updated'])) === '1') : ?>
            <div class="notice notice-success is-dismissible"><p><?php esc_html_e('Featured label saved.', 'kc-streetcar-guide'); ?></p></div>
        <?php endif; ?>
        <?php
    }'''

save_method = r'''    public function save_guide_settings() {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('You do not have permission to edit guide settings.', 'kc-streetcar-guide'));
        }

        if (!isset($_POST['kcsg_guide_settings_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['kcsg_guide_settings_nonce'])), 'kcsg_guide_settings_nonce')) {
            wp_die(esc_html__('Security check failed.', 'kc-streetcar-guide'));
        }

        $label = isset($_POST['kcsg_featured_label']) ? sanitize_text_field(wp_unslash($_POST['kcsg_featured_label'])) : '';
        $label = function_exists('mb_substr') ? mb_substr($label, 0, 60) : substr($label, 0, 60);

        if ($label === '' || strcasecmp($label, 'Executive Pick') === 0) {
            delete_option(self::FEATURED_LABEL_OPTION);
        } else {
            update_option(self::FEATURED_LABEL_OPTION, $label, false);
        }

        wp_safe_redirect(add_query_arg(array(
            'post_type' => self::CPT,
            'kcsg_settings_updated' => '1',
        ), admin_url('edit.php')));
        exit;
    }'''

if 'FEATURED_LABEL_OPTION' not in php:
    php = php.replace("    const STOP_TRACKER_OPTION = 'kcsg_stop_trackers';\n", "    const STOP_TRACKER_OPTION = 'kcsg_stop_trackers';\n    const FEATURED_LABEL_OPTION = 'kcsg_featured_label';\n", 1)

php = php.replace("        add_action('admin_menu', array($this, 'add_advanced_settings_page'));\n", '')
php = php.replace("        add_action('admin_post_kcsg_save_advanced_settings', array($this, 'save_advanced_settings'));\n", "        add_action('admin_post_kcsg_save_guide_settings', array($this, 'save_guide_settings'));\n", 1)
if "render_amenities_screen_tools" not in php:
    php = php.replace("        add_action('admin_post_kcsg_save_guide_settings', array($this, 'save_guide_settings'));\n", "        add_action('admin_post_kcsg_save_guide_settings', array($this, 'save_guide_settings'));\n        add_action('all_admin_notices', array($this, 'render_amenities_screen_tools'));\n", 1)

if 'public static function get_featured_label' not in php:
    first = method_span(php, 'get_font_settings')
    second = method_span(php, 'get_guide_font_style')
    if not first or not second:
        raise RuntimeError('Font methods were not found for replacement.')
    php = php[:first[0]] + featured_method + '\n\n' + php[second[1]:]

span = method_span(php, 'add_advanced_settings_page')
if span:
    php = php[:span[0]] + php[span[1]:]
if method_span(php, 'render_advanced_settings_page'):
    php = replace_method(php, 'render_advanced_settings_page', tools_method)
if method_span(php, 'save_advanced_settings'):
    php = replace_method(php, 'save_advanced_settings', save_method)

if '$featured_label = self::get_featured_label();' not in php:
    php = php.replace("        $featured = get_post_meta($post->ID, '_kcsg_featured', true);\n", "        $featured = get_post_meta($post->ID, '_kcsg_featured', true);\n        $featured_label = self::get_featured_label();\n", 1)

php = re.sub(
    r'<label><input type="checkbox" name="kcsg_featured" id="kcsg_featured" value="1" <\?php checked\(\$featured, \'1\'\); \?> /> <\?php esc_html_e\(\'Show as an executive pick\', \'kc-streetcar-guide\'\); \?></label>',
    '<label class="kcsg-featured-toggle"><input type="checkbox" name="kcsg_featured" id="kcsg_featured" value="1" <?php checked($featured, \'1\'); ?> /> <?php echo esc_html(sprintf(__(\'Show the “%s” badge\', \'kc-streetcar-guide\'), $featured_label)); ?></label>',
    php,
    count=1,
)

for phrase in (
    "                <span class=\"description\"><?php esc_html_e('Visitors can use this link for route, walking, or driving details.', 'kc-streetcar-guide'); ?></span>\n",
    "Use the Category field above to assign Coffee, Food, Drinks, Culture, Shopping, Walks, etc. Add or edit available categories under Streetcar Guide → Categories.",
):
    php = php.replace(phrase, '')

php = re.sub(r"\n\s*\$is_advanced_settings_page = \([^\n]+\);", '', php, count=1)
php = php.replace("        if (!$is_amenity_screen && !$is_category_screen && !$is_stop_photo_page && !$is_advanced_settings_page) {", "        if (!$is_amenity_screen && !$is_category_screen && !$is_stop_photo_page) {", 1)
php = php.replace("            .kcsg-stop-photo-tools,\n            .kcsg-advanced-card { background: #fff; border: 1px solid #dcdcde; border-radius: 8px; padding: 14px; margin: 18px 0; max-width: 960px; }\n            .kcsg-stop-photo-tools h2,\n            .kcsg-advanced-card h2 { margin: 0 0 8px; font-size: 16px; }", "            .kcsg-stop-photo-tools { background: #fff; border: 1px solid #dcdcde; border-radius: 8px; padding: 14px; margin: 18px 0; max-width: 960px; }\n            .kcsg-stop-photo-tools h2 { margin: 0 0 8px; font-size: 16px; }", 1)

if '.kcsg-guide-tools {' not in php:
    marker = "            .kcsg-stop-photo-tools h2 { margin: 0 0 8px; font-size: 16px; }\n"
    addition = marker + "            .kcsg-guide-tools { display: flex; align-items: center; justify-content: space-between; gap: 18px; padding: 14px 16px; margin: 12px 0 18px; border-left-color: #008bd2; }\n            .kcsg-guide-tools__shortcode { display: grid; gap: 6px; min-width: 0; }\n            .kcsg-guide-tools__shortcode code { display: block; max-width: 100%; padding: 6px 8px; white-space: normal; overflow-wrap: anywhere; }\n            .kcsg-guide-tools__form { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }\n            .kcsg-guide-tools__form input[type=text] { width: 210px; }\n"
    php = php.replace(marker, addition, 1)

php = re.sub(
    r'^\s*\.kcsg-admin-field input\[type=checkbox\][^\n]*$',
    "            .kcsg-featured-toggle { display: flex !important; align-items: center; gap: 6px; margin: 0 !important; }\n            .kcsg-admin-field input[type=checkbox], .kcsg-featured-toggle input[type=checkbox] { width: 1rem !important; min-width: 1rem !important; height: 1rem !important; max-width: 1rem !important; margin: 0 !important; flex: 0 0 1rem; }",
    php,
    count=1,
    flags=re.M,
)
php = php.replace("@media (max-width: 900px) { .kcsg-admin-grid { grid-template-columns: 1fr; } .kcsg-admin-field-stop, .kcsg-admin-field-category { grid-column: 1 / -1; } }", "@media (max-width: 900px) { .kcsg-admin-grid { grid-template-columns: 1fr; } .kcsg-admin-field-stop, .kcsg-admin-field-category { grid-column: 1 / -1; } .kcsg-guide-tools { align-items: flex-start; flex-direction: column; } }", 1)

php = php.replace("esc_html__('★ Executive pick', 'kc-streetcar-guide')", "esc_html('★ ' . self::get_featured_label())", 1)
php = php.replace("            'fontSettings' => self::get_font_settings(),", "            'featuredLabel' => self::get_featured_label(),", 1)
php = re.sub(r"\n\s*\$font_settings = self::get_font_settings\(\);\n\s*\$guide_font_class = [^\n]+;\n\s*\$guide_font_style = [^\n]+;", '', php, count=1)
php = re.sub(r'<section id="<\?php echo esc_attr\(\$instance_id\); \?>" class="kcsg-guide[^\"]*"(?: style="[^"]*")? data-kcsg-guide>', '<section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide" data-kcsg-guide>', php, count=1)

php_path.write_text(php)

js = js_path.read_text()
if "var featuredLabel = String(data.featuredLabel" not in js:
    js = js.replace("      var featuredMarkup = amenity.featured ? '<span class=\"kcsg-featured-badge\">★ Executive Pick</span>' : '';", "      var featuredLabel = String(data.featuredLabel || 'Executive Pick');\n      var featuredMarkup = amenity.featured ? '<span class=\"kcsg-featured-badge\">★ ' + esc(featuredLabel) + '</span>' : '';", 1)
js_path.write_text(js)

readme = readme_path.read_text()
readme = re.sub(r"5\. Add this shortcode to a page:\n\n```text\n\[kc_streetcar_guide\]\n```\n\nOptional shortcode attributes:\n", "5. Copy the shortcode shown at the top of Streetcar Guide → Amenities and add it to a page:\n\n", readme, count=1)
if 'The featured badge label can also be customized' not in readme:
    readme = readme.replace('```\n\n## Admin fields', '```\n\nThe featured badge label can also be customized from the Amenities screen. “Executive Pick” remains the default.\n\n## Admin fields', 1)
for line in ('- Walk from Stop\n', '- Walk from Hotel\n', '- Drive from Hotel\n'):
    readme = readme.replace(line, '')
readme_path.write_text(readme)
PY

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

for required in 'Explore KC shortcode' 'FEATURED_LABEL_OPTION' 'featuredLabel' 'kcsg-featured-toggle'; do
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
