#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Missing release version."
  exit 1
fi

TAG="v${VERSION#v}"
DOWNLOAD_URL="https://github.com/okohring/kc-streetcar-guide/releases/download/${TAG}/kc-streetcar-guide.zip"
CHANGELOG="Simplifies amenity location fields to Google Maps links only, removes hotel and walk/drive time fields, and keeps bulk stop photo crop tools."

perl -0pi -e "s/Version:\s*[0-9.]+/Version: $VERSION/" kc-streetcar-guide.php
perl -0pi -e "s/const VERSION = '[^']+';/const VERSION = '$VERSION';/" kc-streetcar-guide.php

python3 - <<'PY'
from pathlib import Path
import re

php = Path('kc-streetcar-guide.php')
content = php.read_text()

# Keep the release updater safe.
content = content.replace("        add_filter('upgrader_post_install', array($this, 'rename_release_folder'), 10, 3);\n", "")
content = re.sub(r"\n    public function rename_release_folder\(\$response, \$hook_extra, \$result\) \{.*?\n    \}\n", "\n", content, flags=re.S)

# Add image-size hook for cropped stop headers.
constructor_additions = {
    "        add_action('init', array($this, 'register_content_types'));\n": "        add_action('after_setup_theme', array($this, 'register_image_sizes'));\n        add_action('init', array($this, 'register_content_types'));\n",
}
for old, new in constructor_additions.items():
    if old in content and new not in content:
        content = content.replace(old, new, 1)

helpers = r'''
    public function register_image_sizes() {
        add_image_size('kcsg_stop_header', 1040, 520, true);
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
'''
if 'function extract_google_maps_coordinates' not in content:
    anchor = "\n    public function register_content_types() {"
    content = content.replace(anchor, helpers + anchor, 1)

# Hide default taxonomy slug/description noise in release admin.
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

# Admin screens, CSS, and media behavior.
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

        $current_page = isset($_GET['page']) ? sanitize_key(wp_unslash($_GET['page'])) : '';
        $current_taxonomy = $taxonomy ? $taxonomy : (isset($_GET['taxonomy']) ? sanitize_key(wp_unslash($_GET['taxonomy'])) : '');
        $is_amenity_screen = ($post_type === self::CPT);
        $is_category_screen = ($current_taxonomy === self::TAX);
        $is_stop_photo_page = ($current_page === 'kcsg-stop-photos');

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
            .kcsg-location-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px 14px; }
            .kcsg-stop-photo-tools { background: #fff; border: 1px solid #dcdcde; border-radius: 8px; padding: 14px; margin: 18px 0; max-width: 760px; }
            .kcsg-stop-photo-tools h2 { margin: 0 0 8px; font-size: 16px; }
            .kcsg-location-help { margin: 6px 0 0; color: #646970; font-size: 12px; }
"""
if admin_css_anchor in content:
    content = content.replace(admin_css_anchor, admin_css_replacement, 1)

# Amenity meta fields: map link and optional website only; remove walk/drive/hotel time fields.
for line in (
    "        $walk_from_stop = get_post_meta($post->ID, '_kcsg_walk_from_stop', true);\n",
    "        $walk_from_hotel = get_post_meta($post->ID, '_kcsg_walk_from_hotel', true);\n",
    "        $drive_from_hotel = get_post_meta($post->ID, '_kcsg_drive_from_hotel', true);\n",
):
    content = content.replace(line, '')

meta_url_old = """        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
"""
meta_url_new = """        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $website_url = get_post_meta($post->ID, '_kcsg_website_url', true);
        $map_lat = get_post_meta($post->ID, '_kcsg_map_lat', true);
        $map_lng = get_post_meta($post->ID, '_kcsg_map_lng', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
"""
if meta_url_old in content:
    content = content.replace(meta_url_old, meta_url_new, 1)

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

url_field_old = """            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://example.com" />
            </p>
"""
url_field_new = """            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('Google Maps URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://www.google.com/maps/place/.../@39.0997,-94.5786,..." />
                <span class="description"><?php esc_html_e('Paste the full Google Maps URL from your browser. If it includes coordinates, the plugin will save them for future use.', 'kc-streetcar-guide'); ?></span>
            </p>

            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_website_url"><strong><?php esc_html_e('Website URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_website_url" id="kcsg_website_url" value="<?php echo esc_url($website_url); ?>" placeholder="https://www.example.org/" />
            </p>

            <div class="kcsg-admin-field kcsg-admin-field-full kcsg-location-grid">
                <p class="kcsg-admin-field">
                    <label for="kcsg_map_lat"><strong><?php esc_html_e('Latitude', 'kc-streetcar-guide'); ?></strong></label>
                    <input type="text" name="kcsg_map_lat" id="kcsg_map_lat" value="<?php echo esc_attr($map_lat); ?>" placeholder="39.0997" />
                </p>
                <p class="kcsg-admin-field">
                    <label for="kcsg_map_lng"><strong><?php esc_html_e('Longitude', 'kc-streetcar-guide'); ?></strong></label>
                    <input type="text" name="kcsg_map_lng" id="kcsg_map_lng" value="<?php echo esc_attr($map_lng); ?>" placeholder="-94.5786" />
                </p>
            </div>
"""
if url_field_old in content:
    content = content.replace(url_field_old, url_field_new, 1)

save_setup_old = """        $allowed_stops = array_keys(self::stops());
        $stop = isset($_POST['kcsg_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_stop'])) : '';
        if (!in_array($stop, $allowed_stops, true)) {
            $stop = '';
        }

        $fields = array(
"""
save_setup_new = """        $allowed_stops = array_keys(self::stops());
        $stop = isset($_POST['kcsg_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_stop'])) : '';
        if (!in_array($stop, $allowed_stops, true)) {
            $stop = '';
        }

        $location = self::sanitize_location_payload(
            isset($_POST['kcsg_url']) ? wp_unslash($_POST['kcsg_url']) : '',
            isset($_POST['kcsg_map_lat']) ? wp_unslash($_POST['kcsg_map_lat']) : '',
            isset($_POST['kcsg_map_lng']) ? wp_unslash($_POST['kcsg_map_lng']) : ''
        );

        $fields = array(
"""
if save_setup_old in content:
    content = content.replace(save_setup_old, save_setup_new, 1)

save_fields_old = """            '_kcsg_stop' => $stop,
            '_kcsg_walk_from_stop' => isset($_POST['kcsg_walk_from_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_walk_from_stop'])) : '',
            '_kcsg_walk_from_hotel' => isset($_POST['kcsg_walk_from_hotel']) ? sanitize_text_field(wp_unslash($_POST['kcsg_walk_from_hotel'])) : '',
            '_kcsg_drive_from_hotel' => isset($_POST['kcsg_drive_from_hotel']) ? sanitize_text_field(wp_unslash($_POST['kcsg_drive_from_hotel'])) : '',
            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => isset($_POST['kcsg_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_url'])) : '',
        );
"""
save_fields_new = """            '_kcsg_stop' => $stop,
            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => $location['map_url'],
            '_kcsg_map_lat' => $location['lat'],
            '_kcsg_map_lng' => $location['lng'],
            '_kcsg_website_url' => isset($_POST['kcsg_website_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_website_url'])) : '',
        );

        delete_post_meta($post_id, '_kcsg_walk_from_stop');
        delete_post_meta($post_id, '_kcsg_walk_from_hotel');
        delete_post_meta($post_id, '_kcsg_drive_from_hotel');
"""
if save_fields_old in content:
    content = content.replace(save_fields_old, save_fields_new, 1)

# Admin list table: replace Times column with a simple Map column.
content = content.replace("                $new_columns['kcsg_times'] = __('Times', 'kc-streetcar-guide');", "                $new_columns['kcsg_map'] = __('Map', 'kc-streetcar-guide');")
content = re.sub(
    r"\n        if \(\$column === 'kcsg_times'\) \{.*?\n        \}\n    \}\n\n    public function register_rest_routes",
    """
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

# Stop photo frontend should use the dedicated cropped header size.
photo_url_old = """            $url = wp_get_attachment_image_url($attachment_id, 'large');
            if (!$url) {
                continue;
            }
"""
photo_url_new = """            self::ensure_stop_header_crop($attachment_id, false);
            $url = wp_get_attachment_image_url($attachment_id, 'kcsg_stop_header');
            if (!$url) {
                $url = wp_get_attachment_image_url($attachment_id, 'large');
            }
            if (!$url) {
                continue;
            }
"""
if photo_url_old in content:
    content = content.replace(photo_url_old, photo_url_new, 1)

# Stop Photos page gets bulk selection/crop/delete tools.
stop_page_vars_old = """        $photo_ids = self::get_stop_photo_ids();
        $tracker_urls = self::get_stop_tracker_urls();
        ?>
"""
stop_page_vars_new = """        $photo_ids = self::get_stop_photo_ids();
        $tracker_urls = self::get_stop_tracker_urls();
        $delete_original_after_crop = (bool) get_option('kcsg_delete_original_after_crop', false);
        ?>
"""
if stop_page_vars_old in content:
    content = content.replace(stop_page_vars_old, stop_page_vars_new, 1)

photo_grid_anchor = """                <div class="kcsg-stop-photo-grid">
"""
photo_tools_block = """                <section class="kcsg-stop-photo-tools">
                    <h2><?php esc_html_e('Bulk Stop Photo Tools', 'kc-streetcar-guide'); ?></h2>
                    <p class="kcsg-location-help"><?php esc_html_e('Select multiple images at once. The plugin will try to match filenames to stop names, then fill remaining empty stops in order. Stop header crops are generated at 1040×520.', 'kc-streetcar-guide'); ?></p>
                    <p>
                        <button type="button" class="button button-secondary" data-kcsg-mass-select-stop-photos><?php esc_html_e('Mass Select Stop Photos', 'kc-streetcar-guide'); ?></button>
                    </p>
                    <label>
                        <input type="checkbox" name="kcsg_delete_original_after_crop" value="1" <?php checked($delete_original_after_crop); ?> />
                        <?php esc_html_e('Delete original image file after creating the 1040×520 header crop', 'kc-streetcar-guide'); ?>
                    </label>
                </section>

                <div class="kcsg-stop-photo-grid">
"""
if photo_grid_anchor in content:
    content = content.replace(photo_grid_anchor, photo_tools_block, 1)

card_open_old = """                        <section class="kcsg-stop-photo-card" data-kcsg-stop-photo-card>
"""
card_open_new = """                        <section class="kcsg-stop-photo-card" data-kcsg-stop-photo-card data-kcsg-stop-id="<?php echo esc_attr($stop_id); ?>" data-kcsg-stop-label="<?php echo esc_attr($stop_label); ?>">
"""
if card_open_old in content:
    content = content.replace(card_open_old, card_open_new, 1)

image_preview_old = """                        $image_url = $attachment_id ? wp_get_attachment_image_url($attachment_id, 'medium') : '';
"""
image_preview_new = """                        $image_url = $attachment_id ? wp_get_attachment_image_url($attachment_id, 'kcsg_stop_header') : '';
                        if (!$image_url && $attachment_id) {
                            $image_url = wp_get_attachment_image_url($attachment_id, 'medium');
                        }
"""
if image_preview_old in content:
    content = content.replace(image_preview_old, image_preview_new, 1)

save_stop_incoming_old = """        $incoming = isset($_POST['kcsg_stop_photos']) && is_array($_POST['kcsg_stop_photos']) ? wp_unslash($_POST['kcsg_stop_photos']) : array();
        $incoming_trackers = isset($_POST['kcsg_stop_trackers']) && is_array($_POST['kcsg_stop_trackers']) ? wp_unslash($_POST['kcsg_stop_trackers']) : array();
        $saved = array();
"""
save_stop_incoming_new = """        $incoming = isset($_POST['kcsg_stop_photos']) && is_array($_POST['kcsg_stop_photos']) ? wp_unslash($_POST['kcsg_stop_photos']) : array();
        $incoming_trackers = isset($_POST['kcsg_stop_trackers']) && is_array($_POST['kcsg_stop_trackers']) ? wp_unslash($_POST['kcsg_stop_trackers']) : array();
        $delete_original_after_crop = !empty($_POST['kcsg_delete_original_after_crop']);
        $saved = array();
"""
if save_stop_incoming_old in content:
    content = content.replace(save_stop_incoming_old, save_stop_incoming_new, 1)

attachment_save_old = """            if ($attachment_id) {
                $saved[$stop_id] = $attachment_id;
            }
"""
attachment_save_new = """            if ($attachment_id) {
                self::ensure_stop_header_crop($attachment_id, $delete_original_after_crop);
                $saved[$stop_id] = $attachment_id;
            }
"""
if attachment_save_old in content:
    content = content.replace(attachment_save_old, attachment_save_new, 1)

update_options_old = """        update_option(self::STOP_PHOTO_OPTION, $saved, false);
        update_option(self::STOP_TRACKER_OPTION, $saved_trackers, false);
"""
update_options_new = """        update_option(self::STOP_PHOTO_OPTION, $saved, false);
        update_option(self::STOP_TRACKER_OPTION, $saved_trackers, false);
        update_option('kcsg_delete_original_after_crop', $delete_original_after_crop ? 1 : 0, false);
"""
if update_options_old in content:
    content = content.replace(update_options_old, update_options_new, 1)

# Frontend data gets map fields and no travel-time fields.
data_block_old = """                'walkFromStop' => get_post_meta($post->ID, '_kcsg_walk_from_stop', true),
                'walkFromHotel' => get_post_meta($post->ID, '_kcsg_walk_from_hotel', true),
                'driveFromHotel' => get_post_meta($post->ID, '_kcsg_drive_from_hotel', true),
                'description' => get_post_meta($post->ID, '_kcsg_description', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
            );
"""
data_block_new = """                'description' => get_post_meta($post->ID, '_kcsg_description', true),
                'mapUrl' => get_post_meta($post->ID, '_kcsg_url', true),
                'websiteUrl' => get_post_meta($post->ID, '_kcsg_website_url', true),
                'mapLat' => get_post_meta($post->ID, '_kcsg_map_lat', true),
                'mapLng' => get_post_meta($post->ID, '_kcsg_map_lng', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
            );
"""
if data_block_old in content:
    content = content.replace(data_block_old, data_block_new, 1)

# Add mass select behavior to the existing stop photo media script.
script_marker = """                    $(document).on("click", "[data-kcsg-remove-stop-photo]", function(e) {
                        e.preventDefault();
                        var card = $(this).closest("[data-kcsg-stop-photo-card]");
                        card.find("[data-kcsg-stop-photo-input]").val("");
                        card.find("[data-kcsg-stop-photo-preview]").html("<span>No photo selected</span>");
                    });
"""
script_addition = script_marker + """

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
                                var emptyCard = cards.filter(function() {
                                    return !$(this).find("[data-kcsg-stop-photo-input]").val();
                                }).first();
                                if (emptyCard.length) {
                                    usedAttachmentIds[attachment.id] = true;
                                    kcsgSetStopPhoto(emptyCard, attachment);
                                }
                            });
                        });
                        frame.open();
                    });
"""
if script_marker in content and 'data-kcsg-mass-select-stop-photos' not in content:
    content = content.replace(script_marker, script_addition, 1)

php.write_text(content)

# Frontend card rendering: map pin link + optional website link, and no walk/drive time rows.
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

old_meta = """          '<div class="kcsg-meta">' +
            '<span class="kcsg-stop-meta"><strong>Streetcar stop</strong><button type="button" class="kcsg-stop-name" data-kcsg-card-stop="' + esc(amenity.stop || '') + '">' + esc(stopLabelText) + '</button></span>' +
            '<span><strong>Walk from stop</strong>' + esc(amenity.walkFromStop || '—') + '</span>' +
            '<span><strong>Walk from hotel</strong>' + esc(amenity.walkFromHotel || '—') + '</span>' +
            '<span><strong>Drive from hotel</strong>' + esc(amenity.driveFromHotel || '—') + '</span>' +
          '</div>' +
"""
new_meta = """          '<div class="kcsg-meta kcsg-meta--single">' +
            '<span class="kcsg-stop-meta"><strong>Streetcar stop</strong><button type="button" class="kcsg-stop-name" data-kcsg-card-stop="' + esc(amenity.stop || '') + '">' + esc(stopLabelText) + '</button></span>' +
          '</div>' +
"""
if old_meta in js_content:
    js_content = js_content.replace(old_meta, new_meta, 1)

js.write_text(js_content)
PY

# Release build validations.
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

for required in \
  "register_image_sizes" \
  "add_image_size('kcsg_stop_header', 1040, 520, true)" \
  "extract_google_maps_coordinates" \
  "sanitize_location_payload" \
  "ensure_stop_header_crop" \
  "Bulk Stop Photo Tools" \
  "kcsg_delete_original_after_crop" \
  "Google Maps URL" \
  "_kcsg_map_lat" \
  "_kcsg_map_lng" \
  "'mapUrl'"; do
  if ! grep -q "$required" kc-streetcar-guide.php; then
    echo "Required release PHP feature missing: $required"
    exit 1
  fi
done

for removed in \
  "Hotel Location" \
  "Guide Settings" \
  "Walk from Stop" \
  "Walk from Hotel" \
  "Drive from Hotel" \
  "kcsg_guide_settings" \
  "estimate_walk_time" \
  "estimate_drive_time"; do
  if grep -q "$removed" kc-streetcar-guide.php; then
    echo "Removed location/time feature is still present in release PHP: $removed"
    exit 1
  fi
done

if ! grep -q "unset(\$columns\['slug'\], \$columns\['description'\])" kc-streetcar-guide.php; then
  echo "Category slug/description columns are still visible."
  exit 1
fi

if ! grep -q "is_category_screen" kc-streetcar-guide.php; then
  echo "Category admin screen detection is missing."
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

for removed in \
  "Walk from stop" \
  "Walk from hotel" \
  "Drive from hotel"; do
  if grep -q "$removed" assets/kcsg-frontend.js; then
    echo "Removed time row still renders on frontend: $removed"
    exit 1
  fi
done

for required in \
  "function buildControlBar" \
  "function resetResultsScroll" \
  "function renderStopCategoryKey" \
  "function categoryHeaderMarkup" \
  "kiosk-6e6b4.firebaseio.com" \
  "Riverfront (Northbound)" \
  "UMKC (Southbound)" \
  "ARRIVAL_CACHE_MS = 30000" \
  "Arriving soon"; do
  if ! grep -q "$required" assets/kcsg-frontend.js; then
    echo "Required frontend behavior missing: $required"
    exit 1
  fi
done

for required in \
  "KC Streetcar Guide theme shield" \
  "KC Streetcar Guide final theme overrides" \
  "kcsg-section-heading h3" \
  "KC Streetcar Guide layout lock" \
  "--kcsg-card-standard-width: 520px" \
  "KC Streetcar Guide stop header photo height" \
  "height: 260px" \
  "kcsg-stop-photo--placeholder figcaption"; do
  if ! grep -q -- "$required" assets/*.css; then
    echo "Required CSS feature missing: $required"
    exit 1
  fi
done

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

for required in \
  "KC Streetcar Guide theme shield" \
  "KC Streetcar Guide final theme overrides" \
  "KC Streetcar Guide layout lock" \
  "KC Streetcar Guide stop header photo height"; do
  if ! grep -q "$required" build/kc-streetcar-guide/assets/kcsg-frontend.css; then
    echo "Merged release CSS missing: $required"
    exit 1
  fi
done

cd build
zip -r kc-streetcar-guide.zip kc-streetcar-guide
cd ..

NOTES=$(cat <<'NOTES'
- Removes hotel location settings and all walk/drive time fields from the amenity workflow.
- Keeps the Google Maps URL as the place where visitors can get route/walk/drive information.
- Keeps saved map coordinates when a full Google Maps URL includes them, but does not calculate or display travel times.
- Keeps the waypoint Google Maps icon and optional website URL on amenity cards.
- Adds/keeps bulk stop-photo selection, 1040×520 hard-cropped stop header images, and optional original-file deletion after crop generation.
- Keeps the responsive amenity column fix, text-only no-photo stop headers, category header lock, theme shielding, Firebase-backed live arrivals, and safe release/update flow.
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
