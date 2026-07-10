#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Missing release version."
  exit 1
fi

TAG="v${VERSION#v}"
DOWNLOAD_URL="https://github.com/okohring/kc-streetcar-guide/releases/download/${TAG}/kc-streetcar-guide.zip"
CHANGELOG="Keeps amenity-level Executive Pick toggles, advanced font controls, entity decoding, map-link-only amenities, and bulk stop photo crop tools. Removes Featured Locations cards and SVG map stars."

perl -0pi -e "s/Version:\s*[^\n]+/Version: $VERSION/" kc-streetcar-guide.php
perl -0pi -e "s/const VERSION = '[^']+';/const VERSION = '$VERSION';/" kc-streetcar-guide.php

python3 - <<'PY'
from pathlib import Path
import re

php = Path('kc-streetcar-guide.php')
content = php.read_text()

# Keep the release updater safe.
content = content.replace("        add_filter('upgrader_post_install', array($this, 'rename_release_folder'), 10, 3);\n", "")
content = re.sub(r"\n    public function rename_release_folder\(\$response, \$hook_extra, \$result\) \{.*?\n    \}\n", "\n", content, flags=re.S)

# Add hooks for cropped stop headers and Advanced Settings.
hook_replacements = {
    "        add_action('init', array($this, 'register_content_types'));\n": "        add_action('after_setup_theme', array($this, 'register_image_sizes'));\n        add_action('init', array($this, 'register_content_types'));\n",
    "        add_action('admin_menu', array($this, 'add_stop_photos_page'));\n": "        add_action('admin_menu', array($this, 'add_stop_photos_page'));\n        add_action('admin_menu', array($this, 'add_advanced_settings_page'));\n",
    "        add_action('admin_post_kcsg_save_stop_photos', array($this, 'save_stop_photos'));\n": "        add_action('admin_post_kcsg_save_stop_photos', array($this, 'save_stop_photos'));\n        add_action('admin_post_kcsg_save_advanced_settings', array($this, 'save_advanced_settings'));\n",
}
for old, new in hook_replacements.items():
    if old in content and new not in content:
        content = content.replace(old, new, 1)

helpers = r'''
    public function register_image_sizes() {
        add_image_size('kcsg_stop_header', 1040, 520, true);
    }

    public static function decode_plain_text($value) {
        return html_entity_decode(wp_specialchars_decode((string) $value, ENT_QUOTES), ENT_QUOTES, 'UTF-8');
    }

    public static function normalize_coordinate_value($value, $type) {
        $value = trim((string) $value);
        if ($value === '' || !is_numeric($value)) {
            return '';
        }

        $number = (float) $value;
        if ($type === 'lat' && ($number < -90 || $number > 90)) {
            return '';
        }
        if ($type === 'lng' && ($number < -180 || $number > 180)) {
            return '';
        }

        return rtrim(rtrim(sprintf('%.7F', $number), '0'), '.');
    }

    public static function extract_google_maps_coordinates($url) {
        $url = trim((string) $url);
        if ($url === '') {
            return array('lat' => '', 'lng' => '');
        }

        $decoded = rawurldecode($url);
        $patterns = array(
            '/@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/',
            '/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/',
            '/[?&](?:q|query|ll|destination)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/',
            '#/(?:search|place)/(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)#',
        );

        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $decoded, $matches)) {
                return array(
                    'lat' => self::normalize_coordinate_value($matches[1], 'lat'),
                    'lng' => self::normalize_coordinate_value($matches[2], 'lng'),
                );
            }
        }

        return array('lat' => '', 'lng' => '');
    }

    public static function sanitize_location_payload($map_url, $lat = '', $lng = '') {
        $map_url = esc_url_raw(trim((string) $map_url));
        $lat = self::normalize_coordinate_value($lat, 'lat');
        $lng = self::normalize_coordinate_value($lng, 'lng');

        if ((!$lat || !$lng) && $map_url) {
            $extracted = self::extract_google_maps_coordinates($map_url);
            if (!$lat && !empty($extracted['lat'])) {
                $lat = $extracted['lat'];
            }
            if (!$lng && !empty($extracted['lng'])) {
                $lng = $extracted['lng'];
            }
        }

        return array(
            'map_url' => $map_url,
            'lat' => $lat,
            'lng' => $lng,
        );
    }

    public static function get_font_settings() {
        $settings = get_option('kcsg_font_settings', array());
        $settings = is_array($settings) ? $settings : array();
        $mode = isset($settings['mode']) ? sanitize_key($settings['mode']) : 'theme';
        if (!in_array($mode, array('theme', 'arial'), true)) {
            $mode = 'theme';
        }

        $size = isset($settings['size']) ? absint($settings['size']) : 14;
        $size = max(10, min(22, $size));

        return array(
            'mode' => $mode,
            'size' => $size,
        );
    }

    public static function get_guide_font_style() {
        $settings = self::get_font_settings();
        $family = $settings['mode'] === 'arial' ? 'Arial, Helvetica, sans-serif' : 'inherit';
        return '--kcsg-font-family:' . $family . ';--kcsg-base-font-size:' . $settings['size'] . 'px;';
    }

    public static function ensure_stop_header_crop($attachment_id, $delete_original = false) {
        $attachment_id = absint($attachment_id);
        if (!$attachment_id || !wp_attachment_is_image($attachment_id)) {
            return false;
        }

        $file = get_attached_file($attachment_id);
        if (!$file || !file_exists($file)) {
            return false;
        }

        if (!function_exists('wp_generate_attachment_metadata')) {
            require_once ABSPATH . 'wp-admin/includes/image.php';
        }

        $metadata = wp_get_attachment_metadata($attachment_id);
        if (!is_array($metadata) || empty($metadata['sizes']['kcsg_stop_header'])) {
            $metadata = wp_generate_attachment_metadata($attachment_id, $file);
            if (is_array($metadata)) {
                wp_update_attachment_metadata($attachment_id, $metadata);
            }
        }

        if ($delete_original && is_array($metadata) && !empty($metadata['sizes']['kcsg_stop_header']['file'])) {
            $crop_file = trailingslashit(dirname($file)) . $metadata['sizes']['kcsg_stop_header']['file'];
            $file_real = realpath($file);
            $crop_real = realpath($crop_file);
            if ($file_real && $crop_real && $file_real !== $crop_real && file_exists($file)) {
                @unlink($file);
            }
        }

        return true;
    }

    public function add_advanced_settings_page() {
        add_submenu_page(
            'edit.php?post_type=' . self::CPT,
            __('Advanced Settings', 'kc-streetcar-guide'),
            __('Advanced Settings', 'kc-streetcar-guide'),
            'manage_options',
            'kcsg-advanced-settings',
            array($this, 'render_advanced_settings_page')
        );
    }

    public function render_advanced_settings_page() {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('You do not have permission to edit advanced guide settings.', 'kc-streetcar-guide'));
        }

        $font_settings = self::get_font_settings();
        ?>
        <div class="wrap kcsg-advanced-settings-page">
            <h1><?php esc_html_e('Streetcar Advanced Settings', 'kc-streetcar-guide'); ?></h1>
            <?php if (isset($_GET['updated']) && $_GET['updated'] === '1') : ?>
                <div class="notice notice-success is-dismissible"><p><?php esc_html_e('Advanced settings saved.', 'kc-streetcar-guide'); ?></p></div>
            <?php endif; ?>
            <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                <input type="hidden" name="action" value="kcsg_save_advanced_settings" />
                <?php wp_nonce_field('kcsg_advanced_settings_nonce', 'kcsg_advanced_settings_nonce'); ?>

                <section class="kcsg-advanced-card">
                    <h2><?php esc_html_e('Font Settings', 'kc-streetcar-guide'); ?></h2>
                    <p class="kcsg-location-help"><?php esc_html_e('Use your theme font, or force the guide to use Arial. Size adjusts the guide base text size.', 'kc-streetcar-guide'); ?></p>
                    <div class="kcsg-location-grid">
                        <p>
                            <label for="kcsg_font_mode"><strong><?php esc_html_e('Font Source', 'kc-streetcar-guide'); ?></strong></label>
                            <select id="kcsg_font_mode" name="kcsg_font_settings[mode]">
                                <option value="theme" <?php selected($font_settings['mode'], 'theme'); ?>><?php esc_html_e('Inherit theme font', 'kc-streetcar-guide'); ?></option>
                                <option value="arial" <?php selected($font_settings['mode'], 'arial'); ?>><?php esc_html_e('Use Arial', 'kc-streetcar-guide'); ?></option>
                            </select>
                        </p>
                        <p>
                            <label for="kcsg_font_size"><strong><?php esc_html_e('Base Font Size', 'kc-streetcar-guide'); ?></strong></label>
                            <input type="number" id="kcsg_font_size" name="kcsg_font_settings[size]" min="10" max="22" value="<?php echo esc_attr($font_settings['size']); ?>" />
                        </p>
                    </div>
                </section>

                <?php submit_button(__('Save Advanced Settings', 'kc-streetcar-guide')); ?>
            </form>
        </div>
        <?php
    }

    public function save_advanced_settings() {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('You do not have permission to edit advanced guide settings.', 'kc-streetcar-guide'));
        }

        if (!isset($_POST['kcsg_advanced_settings_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['kcsg_advanced_settings_nonce'])), 'kcsg_advanced_settings_nonce')) {
            wp_die(esc_html__('Security check failed.', 'kc-streetcar-guide'));
        }

        $font_incoming = isset($_POST['kcsg_font_settings']) && is_array($_POST['kcsg_font_settings']) ? wp_unslash($_POST['kcsg_font_settings']) : array();
        $font_mode = isset($font_incoming['mode']) ? sanitize_key($font_incoming['mode']) : 'theme';
        if (!in_array($font_mode, array('theme', 'arial'), true)) {
            $font_mode = 'theme';
        }
        $font_size = isset($font_incoming['size']) ? absint($font_incoming['size']) : 14;
        $font_size = max(10, min(22, $font_size));
        update_option('kcsg_font_settings', array('mode' => $font_mode, 'size' => $font_size), false);

        wp_safe_redirect(add_query_arg(array(
            'post_type' => self::CPT,
            'page' => 'kcsg-advanced-settings',
            'updated' => '1',
        ), admin_url('edit.php')));
        exit;
    }
'''
if 'function register_image_sizes' not in content:
    content = content.replace("\n    public function register_content_types() {", helpers + "\n    public function register_content_types() {", 1)

# Category admin cleanup.
content = content.replace("""    public function category_columns($columns) {
        $new_columns = array();

        foreach ($columns as $key => $label) {
""", """    public function category_columns($columns) {
        unset($columns['slug'], $columns['description']);

        $new_columns = array();

        foreach ($columns as $key => $label) {
""", 1)

# Admin styles and media script support.
content = content.replace("""    public function admin_styles($hook) {
        global $post_type;

        $is_amenity_screen = ($post_type === self::CPT);
        $is_stop_photo_page = isset($_GET['page']) && sanitize_key(wp_unslash($_GET['page'])) === 'kcsg-stop-photos';

        if (!$is_amenity_screen && !$is_stop_photo_page) {
            return;
        }
""", """    public function admin_styles($hook) {
        global $post_type, $taxonomy;

        $current_page = isset($_GET['page']) ? sanitize_key(wp_unslash($_GET['page'])) : '';
        $current_taxonomy = $taxonomy ? $taxonomy : (isset($_GET['taxonomy']) ? sanitize_key(wp_unslash($_GET['taxonomy'])) : '');
        $is_amenity_screen = ($post_type === self::CPT);
        $is_category_screen = ($current_taxonomy === self::TAX);
        $is_stop_photo_page = ($current_page === 'kcsg-stop-photos');
        $is_advanced_settings_page = ($current_page === 'kcsg-advanced-settings');

        if (!$is_amenity_screen && !$is_category_screen && !$is_stop_photo_page && !$is_advanced_settings_page) {
            return;
        }
""", 1)
content = content.replace("""        wp_add_inline_style('wp-admin', '
            .kcsg-admin-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 18px; }
""", """        wp_add_inline_style('wp-admin', '
            body.taxonomy-kcsg_category .term-slug-wrap,
            body.taxonomy-kcsg_category .term-description-wrap,
            body.taxonomy-kcsg_category .column-slug,
            body.taxonomy-kcsg_category .column-description { display: none !important; }
            .kcsg-admin-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 18px; }
            .kcsg-location-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px 14px; }
            .kcsg-stop-photo-tools,
            .kcsg-advanced-card { background: #fff; border: 1px solid #dcdcde; border-radius: 8px; padding: 14px; margin: 18px 0; max-width: 960px; }
            .kcsg-stop-photo-tools h2,
            .kcsg-advanced-card h2 { margin: 0 0 8px; font-size: 16px; }
            .kcsg-location-help { margin: 6px 0 12px; color: #646970; font-size: 12px; }
""", 1)
content = content.replace(
    ".kcsg-admin-field input, .kcsg-admin-field select, .kcsg-admin-field textarea { width: 100%; max-width: 100%; }",
    ".kcsg-admin-field input:not([type=checkbox]), .kcsg-admin-field select, .kcsg-admin-field textarea { width: 100%; max-width: 100%; }\n            .kcsg-admin-field input[type=checkbox], .kcsg-stop-photo-tools input[type=checkbox] { appearance: checkbox !important; -webkit-appearance: checkbox !important; width: 16px !important; min-width: 16px !important; max-width: 16px !important; height: 16px !important; min-height: 16px !important; max-height: 16px !important; margin: 0 6px 0 0 !important; padding: 0 !important; vertical-align: middle !important; }"
)

# Amenity edit fields: map link, website, featured only.
for line in (
    "        $walk_from_stop = get_post_meta($post->ID, '_kcsg_walk_from_stop', true);\n",
    "        $walk_from_hotel = get_post_meta($post->ID, '_kcsg_walk_from_hotel', true);\n",
    "        $drive_from_hotel = get_post_meta($post->ID, '_kcsg_drive_from_hotel', true);\n",
):
    content = content.replace(line, '')
content = content.replace("""        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
""", """        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $website_url = get_post_meta($post->ID, '_kcsg_website_url', true);
        $featured = get_post_meta($post->ID, '_kcsg_featured', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
""", 1)
for field in (
"""            <p class="kcsg-admin-field">
                <label for="kcsg_walk_from_stop"><strong><?php esc_html_e('Walk from Stop', 'kc-streetcar-guide'); ?></strong></label>
                <input type="text" name="kcsg_walk_from_stop" id="kcsg_walk_from_stop" value="<?php echo esc_attr($walk_from_stop); ?>" placeholder="4 min" />
            </p>

""",
"""            <p class="kcsg-admin-field">
                <label for="kcsg_walk_from_hotel"><strong><?php esc_html_e('Walk from Hotel', 'kc-streetcar-guide'); ?></strong></label>
                <input type="text" name="kcsg_walk_from_hotel" id="kcsg_walk_from_hotel" value="<?php echo esc_attr($walk_from_hotel); ?>" placeholder="12 min" />
            </p>

""",
"""            <p class="kcsg-admin-field">
                <label for="kcsg_drive_from_hotel"><strong><?php esc_html_e('Drive from Hotel', 'kc-streetcar-guide'); ?></strong></label>
                <input type="text" name="kcsg_drive_from_hotel" id="kcsg_drive_from_hotel" value="<?php echo esc_attr($drive_from_hotel); ?>" placeholder="5 min" />
            </p>

""",
):
    content = content.replace(field, '')
category_field = """            <p class="kcsg-admin-field kcsg-admin-field-category">
                <label for="kcsg_category"><strong><?php esc_html_e('Category', 'kc-streetcar-guide'); ?></strong></label>
                <select name="kcsg_category" id="kcsg_category">
                    <option value=""><?php esc_html_e('Select a category', 'kc-streetcar-guide'); ?></option>
                    <?php if (!is_wp_error($category_terms)) : ?>
                        <?php foreach ($category_terms as $category_term) : ?>
                            <option value="<?php echo esc_attr($category_term->slug); ?>" <?php selected($current_category, $category_term->slug); ?>><?php echo esc_html($category_term->name); ?></option>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </select>
            </p>

"""
featured_field = category_field + """            <p class="kcsg-admin-field">
                <label for="kcsg_featured"><strong><?php esc_html_e('Featured Amenity', 'kc-streetcar-guide'); ?></strong></label>
                <label><input type="checkbox" name="kcsg_featured" id="kcsg_featured" value="1" <?php checked($featured, '1'); ?> /> <?php esc_html_e('Show as an executive pick', 'kc-streetcar-guide'); ?></label>
            </p>

"""
content = content.replace(category_field, featured_field, 1)
content = content.replace("""            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://example.com" />
            </p>
""", """            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('Google Maps URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://www.google.com/maps/place/.../@39.0997,-94.5786,..." />
                <span class="description"><?php esc_html_e('Visitors can use this link for route, walking, or driving details.', 'kc-streetcar-guide'); ?></span>
            </p>

            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_website_url"><strong><?php esc_html_e('Website URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_website_url" id="kcsg_website_url" value="<?php echo esc_url($website_url); ?>" placeholder="https://www.example.org/" />
            </p>
""", 1)
content = content.replace("""        $allowed_stops = array_keys(self::stops());
        $stop = isset($_POST['kcsg_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_stop'])) : '';
        if (!in_array($stop, $allowed_stops, true)) {
            $stop = '';
        }

        $fields = array(
""", """        $allowed_stops = array_keys(self::stops());
        $stop = isset($_POST['kcsg_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_stop'])) : '';
        if (!in_array($stop, $allowed_stops, true)) {
            $stop = '';
        }

        $location = self::sanitize_location_payload(
            isset($_POST['kcsg_url']) ? wp_unslash($_POST['kcsg_url']) : '',
            '',
            ''
        );

        $fields = array(
""", 1)
content = content.replace("""            '_kcsg_stop' => $stop,
            '_kcsg_walk_from_stop' => isset($_POST['kcsg_walk_from_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_walk_from_stop'])) : '',
            '_kcsg_walk_from_hotel' => isset($_POST['kcsg_walk_from_hotel']) ? sanitize_text_field(wp_unslash($_POST['kcsg_walk_from_hotel'])) : '',
            '_kcsg_drive_from_hotel' => isset($_POST['kcsg_drive_from_hotel']) ? sanitize_text_field(wp_unslash($_POST['kcsg_drive_from_hotel'])) : '',
            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => isset($_POST['kcsg_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_url'])) : '',
        );
""", """            '_kcsg_stop' => $stop,
            '_kcsg_featured' => !empty($_POST['kcsg_featured']) ? '1' : '',
            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => $location['map_url'],
            '_kcsg_map_lat' => $location['lat'],
            '_kcsg_map_lng' => $location['lng'],
            '_kcsg_website_url' => isset($_POST['kcsg_website_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_website_url'])) : '',
        );

        delete_post_meta($post_id, '_kcsg_walk_from_stop');
        delete_post_meta($post_id, '_kcsg_walk_from_hotel');
        delete_post_meta($post_id, '_kcsg_drive_from_hotel');
""", 1)

# Admin list table.
content = content.replace("                $new_columns['kcsg_times'] = __('Times', 'kc-streetcar-guide');", "                $new_columns['kcsg_featured'] = __('Featured', 'kc-streetcar-guide');\n                $new_columns['kcsg_map'] = __('Map', 'kc-streetcar-guide');")
content = re.sub(
    r"\n        if \(\$column === 'kcsg_times'\) \{.*?\n        \}\n    \}\n\n    public function register_rest_routes",
    """
        if ($column === 'kcsg_featured') {
            echo get_post_meta($post_id, '_kcsg_featured', true) ? esc_html__('★ Executive pick', 'kc-streetcar-guide') : esc_html__('—', 'kc-streetcar-guide');
        }

        if ($column === 'kcsg_map') {
            $map_url = get_post_meta($post_id, '_kcsg_url', true);
            if ($map_url) {
                echo '<a href="' . esc_url($map_url) . '" target="_blank" rel="noopener noreferrer">' . esc_html__('Open map', 'kc-streetcar-guide') . '</a>';
            } else {
                echo esc_html__('—', 'kc-streetcar-guide');
            }
        }
    }

    public function register_rest_routes""",
    content,
    flags=re.S,
)

# Stop photo crop/mass select tools.
content = content.replace("""            $url = wp_get_attachment_image_url($attachment_id, 'large');
            if (!$url) {
                continue;
            }
""", """            self::ensure_stop_header_crop($attachment_id, false);
            $url = wp_get_attachment_image_url($attachment_id, 'kcsg_stop_header');
            if (!$url) {
                $url = wp_get_attachment_image_url($attachment_id, 'large');
            }
            if (!$url) {
                continue;
            }
""", 1)
content = content.replace("""        $photo_ids = self::get_stop_photo_ids();
        $tracker_urls = self::get_stop_tracker_urls();
        ?>
""", """        $photo_ids = self::get_stop_photo_ids();
        $tracker_urls = self::get_stop_tracker_urls();
        $delete_original_after_crop = (bool) get_option('kcsg_delete_original_after_crop', false);
        ?>
""", 1)
content = content.replace("""                <div class="kcsg-stop-photo-grid">
""", """                <section class="kcsg-stop-photo-tools">
                    <h2><?php esc_html_e('Bulk Stop Photo Tools', 'kc-streetcar-guide'); ?></h2>
                    <p class="kcsg-location-help"><?php esc_html_e('Select multiple images at once. The plugin will try to match filenames to stop names, then fill remaining empty stops in order. Stop header crops are generated at 1040×520.', 'kc-streetcar-guide'); ?></p>
                    <p><button type="button" class="button button-secondary" data-kcsg-mass-select-stop-photos><?php esc_html_e('Mass Select Stop Photos', 'kc-streetcar-guide'); ?></button></p>
                    <label><input type="checkbox" name="kcsg_delete_original_after_crop" value="1" <?php checked($delete_original_after_crop); ?> /> <?php esc_html_e('Delete original image file after creating the 1040×520 header crop', 'kc-streetcar-guide'); ?></label>
                </section>

                <div class="kcsg-stop-photo-grid">
""", 1)
content = content.replace("""                        <section class="kcsg-stop-photo-card" data-kcsg-stop-photo-card>
""", """                        <section class="kcsg-stop-photo-card" data-kcsg-stop-photo-card data-kcsg-stop-id="<?php echo esc_attr($stop_id); ?>" data-kcsg-stop-label="<?php echo esc_attr($stop_label); ?>">
""", 1)
content = content.replace("""                        $image_url = $attachment_id ? wp_get_attachment_image_url($attachment_id, 'medium') : '';
""", """                        $image_url = $attachment_id ? wp_get_attachment_image_url($attachment_id, 'kcsg_stop_header') : '';
                        if (!$image_url && $attachment_id) {
                            $image_url = wp_get_attachment_image_url($attachment_id, 'medium');
                        }
""", 1)
content = content.replace("""        $incoming = isset($_POST['kcsg_stop_photos']) && is_array($_POST['kcsg_stop_photos']) ? wp_unslash($_POST['kcsg_stop_photos']) : array();
        $incoming_trackers = isset($_POST['kcsg_stop_trackers']) && is_array($_POST['kcsg_stop_trackers']) ? wp_unslash($_POST['kcsg_stop_trackers']) : array();
        $saved = array();
""", """        $incoming = isset($_POST['kcsg_stop_photos']) && is_array($_POST['kcsg_stop_photos']) ? wp_unslash($_POST['kcsg_stop_photos']) : array();
        $incoming_trackers = isset($_POST['kcsg_stop_trackers']) && is_array($_POST['kcsg_stop_trackers']) ? wp_unslash($_POST['kcsg_stop_trackers']) : array();
        $delete_original_after_crop = !empty($_POST['kcsg_delete_original_after_crop']);
        $saved = array();
""", 1)
content = content.replace("""            if ($attachment_id) {
                $saved[$stop_id] = $attachment_id;
            }
""", """            if ($attachment_id) {
                self::ensure_stop_header_crop($attachment_id, $delete_original_after_crop);
                $saved[$stop_id] = $attachment_id;
            }
""", 1)
content = content.replace("""        update_option(self::STOP_PHOTO_OPTION, $saved, false);
        update_option(self::STOP_TRACKER_OPTION, $saved_trackers, false);
""", """        update_option(self::STOP_PHOTO_OPTION, $saved, false);
        update_option(self::STOP_TRACKER_OPTION, $saved_trackers, false);
        update_option('kcsg_delete_original_after_crop', $delete_original_after_crop ? 1 : 0, false);
""", 1)
script_marker = """                    $(document).on("click", "[data-kcsg-remove-stop-photo]", function(e) {
                        e.preventDefault();
                        var card = $(this).closest("[data-kcsg-stop-photo-card]");
                        card.find("[data-kcsg-stop-photo-input]").val("");
                        card.find("[data-kcsg-stop-photo-preview]").html("<span>No photo selected</span>");
                    });
"""
script_addition = script_marker + r'''

                    function kcsgNormalizePhotoName(value) {
                        return String(value || "").toLowerCase().replace(/\.[a-z0-9]+$/i, "").replace(/[^a-z0-9]+/g, "");
                    }

                    function kcsgSetStopPhoto(card, attachment) {
                        var input = card.find("[data-kcsg-stop-photo-input]");
                        var preview = card.find("[data-kcsg-stop-photo-preview]");
                        var imageUrl = attachment.sizes && attachment.sizes.kcsg_stop_header ? attachment.sizes.kcsg_stop_header.url : (attachment.sizes && attachment.sizes.medium ? attachment.sizes.medium.url : attachment.url);
                        input.val(attachment.id);
                        preview.html("<img src=\"" + imageUrl + "\" alt=\"\" />");
                    }

                    $(document).on("click", "[data-kcsg-mass-select-stop-photos]", function(e) {
                        e.preventDefault();
                        var frame = wp.media({
                            title: "Choose streetcar stop photos",
                            button: { text: "Use selected photos" },
                            library: { type: "image" },
                            multiple: true
                        });
                        frame.on("select", function() {
                            var attachments = frame.state().get("selection").toJSON();
                            var cards = $("[data-kcsg-stop-photo-card]");
                            var usedAttachmentIds = {};
                            cards.each(function() {
                                var card = $(this);
                                var stopName = kcsgNormalizePhotoName(card.data("kcsg-stop-label"));
                                var match = null;
                                attachments.some(function(attachment) {
                                    if (usedAttachmentIds[attachment.id]) return false;
                                    var candidate = kcsgNormalizePhotoName(attachment.filename || attachment.title || attachment.name || "");
                                    if (candidate.indexOf(stopName) !== -1 || stopName.indexOf(candidate) !== -1) {
                                        match = attachment;
                                        return true;
                                    }
                                    return false;
                                });
                                if (match) {
                                    usedAttachmentIds[match.id] = true;
                                    kcsgSetStopPhoto(card, match);
                                }
                            });
                            attachments.forEach(function(attachment) {
                                if (usedAttachmentIds[attachment.id]) return;
                                var emptyCard = cards.filter(function() { return !$(this).find("[data-kcsg-stop-photo-input]").val(); }).first();
                                if (emptyCard.length) {
                                    usedAttachmentIds[attachment.id] = true;
                                    kcsgSetStopPhoto(emptyCard, attachment);
                                }
                            });
                        });
                        frame.open();
                    });
'''
content = content.replace(script_marker, script_addition, 1)

# Frontend data and shortcode font wrapper.
content = content.replace("'name' => get_the_title($post),", "'name' => self::decode_plain_text(get_the_title($post)),")
content = content.replace("""                'walkFromStop' => get_post_meta($post->ID, '_kcsg_walk_from_stop', true),
                'walkFromHotel' => get_post_meta($post->ID, '_kcsg_walk_from_hotel', true),
                'driveFromHotel' => get_post_meta($post->ID, '_kcsg_drive_from_hotel', true),
                'description' => get_post_meta($post->ID, '_kcsg_description', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
""", """                'featured' => get_post_meta($post->ID, '_kcsg_featured', true) === '1',
                'description' => self::decode_plain_text(get_post_meta($post->ID, '_kcsg_description', true)),
                'mapUrl' => get_post_meta($post->ID, '_kcsg_url', true),
                'websiteUrl' => get_post_meta($post->ID, '_kcsg_website_url', true),
                'mapLat' => get_post_meta($post->ID, '_kcsg_map_lat', true),
                'mapLng' => get_post_meta($post->ID, '_kcsg_map_lng', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
""", 1)
content = content.replace("""            'stopTrackers' => self::get_stop_tracker_data(),
            'arrivalsEndpoint' => esc_url_raw(rest_url('kcsg/v1/arrivals')),
        );

        ob_start();
""", """            'stopTrackers' => self::get_stop_tracker_data(),
            'fontSettings' => self::get_font_settings(),
            'arrivalsEndpoint' => esc_url_raw(rest_url('kcsg/v1/arrivals')),
        );
        $font_settings = self::get_font_settings();
        $guide_font_class = 'kcsg-font-' . $font_settings['mode'];
        $guide_font_style = self::get_guide_font_style();

        ob_start();
""", 1)
content = content.replace("""        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide" data-kcsg-guide>
""", """        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide <?php echo esc_attr($guide_font_class); ?>" style="<?php echo esc_attr($guide_font_style); ?>" data-kcsg-guide>
""", 1)

php.write_text(content)

# Frontend JS.
js = Path('assets/kcsg-frontend.js')
js_content = js.read_text()
old_esc = """  function esc(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
"""
new_esc = """  function decodeEntities(value) {
    var textarea = document.createElement('textarea');
    textarea.innerHTML = String(value || '');
    return textarea.value;
  }

  function esc(value) {
    return decodeEntities(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
"""
js_content = js_content.replace(old_esc, new_esc, 1)
card_block = r'''    function actionLinksMarkup(name, mapUrl, websiteUrl) {
      var websiteUrlMarkup = websiteUrl ? '<a class="kcsg-link kcsg-link--website" href="' + esc(websiteUrl) + '" target="_blank" rel="noopener noreferrer" aria-label="Open website for ' + esc(name) + '"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M14 3h7v7h-2V6.41l-9.29 9.3-1.42-1.42 9.3-9.29H14V3Z"></path><path d="M5 5h6v2H7v10h10v-4h2v6H5V5Z"></path></svg></a>' : '';
      var mapUrlMarkup = mapUrl ? '<a class="kcsg-link kcsg-link--map" href="' + esc(mapUrl) + '" target="_blank" rel="noopener noreferrer" aria-label="Open Google Maps for ' + esc(name) + '"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M12 2a7 7 0 0 0-7 7c0 5.25 7 13 7 13s7-7.75 7-13a7 7 0 0 0-7-7Zm0 9.5A2.5 2.5 0 1 1 12 6a2.5 2.5 0 0 1 0 5.5Z"></path></svg></a>' : '';
      return websiteUrlMarkup + mapUrlMarkup;
    }

    function sortFeaturedFirst(items) {
      return items.slice().sort(function (a, b) {
        var featuredDiff = (b.featured ? 1 : 0) - (a.featured ? 1 : 0);
        if (featuredDiff) return featuredDiff;
        return String(a.name || '').localeCompare(String(b.name || ''));
      });
    }

    function cardTemplate(amenity) {
      var category = firstCategory(amenity);
      var categoryColor = cssColor(category && category.color, '#008bd2');
      var featuredMarkup = amenity.featured ? '<span class="kcsg-featured-badge">★ Executive Pick</span>' : '';
      var categoryMarkup = category ? '<span class="kcsg-category-pill" style="--kcsg-category-color:' + esc(categoryColor) + ';">' + esc(category.name) + '</span>' : '';
      var mapUrl = amenity.mapUrl || amenity.url || '';
      var websiteUrl = amenity.websiteUrl || '';
      var descriptionMarkup = amenity.description ? '<p class="kcsg-description">' + esc(amenity.description) + '</p>' : '';
      var stopLabelText = amenity.stopLabel || 'Not assigned';
      var featuredClass = amenity.featured ? ' is-featured' : '';

      return '' +
        '<article class="kcsg-card' + featuredClass + '" data-kcsg-card-stop="' + esc(amenity.stop || '') + '" style="--kcsg-category-color:' + esc(categoryColor) + ';">' +
          '<div class="kcsg-card-header">' +
            '<h4>' + esc(amenity.name) + '</h4>' +
            '<div class="kcsg-card-actions">' + featuredMarkup + categoryMarkup + actionLinksMarkup(amenity.name, mapUrl, websiteUrl) + '</div>' +
          '</div>' +
          '<div class="kcsg-meta kcsg-meta--single">' +
            '<span class="kcsg-stop-meta"><strong>Streetcar stop</strong><button type="button" class="kcsg-stop-name" data-kcsg-card-stop="' + esc(amenity.stop || '') + '">' + esc(stopLabelText) + '</button></span>' +
          '</div>' +
          descriptionMarkup +
        '</article>';
    }

    function categoryHeaderMarkup'''
js_content = re.sub(r"    function cardTemplate\(amenity\) \{.*?\n    \}\n\n    function categoryHeaderMarkup", card_block, js_content, flags=re.S)
render_block = r'''    function render() {
      var filtered = sortFeaturedFirst(currentFilteredAmenities());
      setActiveButton(state.mode === 'category' ? state.category : 'all');
      setActiveStop(state.stop);
      setStopSelect(state.mode === 'stop' ? state.stop : '');
      updateStopMuting();
      updateStopFeature();
      renderStopCategoryKey();

      if (title) {
        if (state.mode === 'stop' && state.stop) {
          title.textContent = stopLabel(state.stop);
        } else if (state.mode === 'category') {
          title.textContent = getCategoryLabel(state.category);
        } else {
          title.textContent = 'All amenities';
        }
      }

      if (count) {
        count.textContent = filtered.length === 1 ? '1 result' : filtered.length + ' results';
      }

      var headerMarkup = categoryHeaderMarkup();

      if (!filtered.length) {
        results.innerHTML = headerMarkup + '<div class="kcsg-empty">No amenities match this selection yet.</div>';
        resetResultsScroll();
        return;
      }

      results.innerHTML = headerMarkup + filtered.map(cardTemplate).join('');
      attachResultHoverEvents();
      resetResultsScroll();
    }

    function attachResultHoverEvents'''
js_content = re.sub(r"    function render\(\) \{.*?\n    \}\n\n    function attachResultHoverEvents", render_block, js_content, flags=re.S)
js.write_text(js_content)

# Frontend CSS for featured cards and font controls.
css = Path('assets/kcsg-theme-overrides.css')
css_content = css.read_text()
feature_css = r'''

/* KC Streetcar Guide featured cards and font controls */
.kcsg-guide {
  font-family: var(--kcsg-font-family, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif) !important;
  font-size: var(--kcsg-base-font-size, 14px) !important;
}

.kcsg-guide .kcsg-results .kcsg-card .kcsg-card-header h4,
.kcsg-guide .kcsg-results .kcsg-card h4,
.kcsg-guide article.kcsg-card h4,
.kcsg-guide .kcsg-section-heading h3,
.kcsg-guide .kcsg-results .kcsg-section-heading h3 {
  font-family: var(--kcsg-font-family, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif) !important;
}

.kcsg-guide .kcsg-card.is-featured {
  border-left-width: 6px !important;
  box-shadow: 0 18px 42px rgba(0, 0, 0, 0.08) !important;
}

.kcsg-guide .kcsg-featured-badge {
  display: inline-flex !important;
  align-items: center !important;
  border: 1px solid rgba(240, 165, 0, 0.32) !important;
  border-radius: 999px !important;
  padding: 5px 9px !important;
  color: #6f4f00 !important;
  background: rgba(240, 165, 0, 0.12) !important;
  font-size: 11px !important;
  font-weight: 650 !important;
  line-height: 1 !important;
  white-space: nowrap !important;
}
'''
if 'KC Streetcar Guide featured cards and font controls' not in css_content:
    css.write_text(css_content + feature_css)

# Remove dynamic/inline SVG featured-location code and old hardcoded hotel/venue star labels from the release.
svg = Path('assets/kc-streetcar-line.svg')
svg_content = svg.read_text()
svg_content = re.sub(r'\s*<script>\s*<!\[CDATA\[.*?\]\]>\s*</script>\s*', '\n', svg_content, flags=re.S)
svg_content = re.sub(r'\s*<g id="kcsg-featured-map-locations"[^>]*>\s*</g>\s*', '\n', svg_content, flags=re.S)
svg_content = re.sub(r'\n\s*<g>\s*<text class="st1"[^>]*>\s*<tspan[^>]*>The Abbott</tspan>\s*</text>.*?</g>\s*', '\n', svg_content, flags=re.S)
svg_content = re.sub(r'\n\s*<g>\s*<text class="st1"[^>]*>\s*<tspan[^>]*>Hotel Indigo</tspan>\s*</text>.*?</g>\s*', '\n', svg_content, flags=re.S)
svg.write_text(svg_content)
PY

# Minimal safety checks only.
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

cd build
zip -r kc-streetcar-guide.zip kc-streetcar-guide
cd ..

NOTES=$(cat <<'NOTES'
- Keeps amenity-level Featured Amenity toggles so selected amenities sort first and show as Executive Picks.
- Removes Featured Locations cards and map stars entirely.
- Keeps Advanced Settings for font source and base font size only.
- Fixes encoded ampersands/apostrophes in titles and descriptions before rendering.
- Keeps the Google Maps link-only amenity workflow with no hotel or walk/drive time fields.
- Keeps bulk stop-photo selection, 1040×520 hard-cropped stop header images, optional original-file deletion, responsive amenity column fixes, text-only no-photo stop headers, theme shielding, and live arrivals.
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
