from pathlib import Path
import re

builder = Path('.github/build-and-release.sh')
script = builder.read_text()

script = script.replace(
    'Keeps amenity-level Executive Pick toggles, advanced font controls, entity decoding, map-link-only amenities, and bulk stop photo crop tools. Removes Featured Locations cards and SVG map stars.',
    'Keeps amenity-level Executive Pick toggles, multi-stop amenity assignments, entity decoding, map-link-only amenities, mobile stop headers, and bulk stop photo crop tools. Removes Advanced Settings, font controls, Featured Locations cards, and SVG map stars.'
)
script = script.replace(
    '- Adds font controls for inheriting the theme font or using Arial, plus adjustable base font size.\n',
    ''
)
script = script.replace(
    '- Adds Featured Amenity toggles so selected amenities sort first and show as Executive Picks.\n',
    '- Adds Featured Amenity toggles so selected amenities sort first and show as Executive Picks.\n- Adds multi-select streetcar stop assignment so one amenity can appear under more than one nearby stop.\n'
)

# Remove the frontend font-control CSS from the generated feature CSS block.
script = re.sub(
    r"/\* KC Streetcar Guide featured cards and font controls \*/\n\.kcsg-guide \{.*?\n\}\n\n\.kcsg-guide \.kcsg-results \.kcsg-card \.kcsg-card-header h4,.*?\n\}\n\n\.kcsg-guide \.kcsg-card\.is-featured",
    "/* KC Streetcar Guide featured cards */\n.kcsg-guide .kcsg-card.is-featured",
    script,
    flags=re.S,
)
script = script.replace(
    "if 'KC Streetcar Guide featured cards and font controls' not in css_content:",
    "if 'KC Streetcar Guide featured cards' not in css_content:"
)
script = script.replace(
    '# Frontend CSS for featured cards and font controls.',
    '# Frontend CSS for featured cards.'
)

final_php_cleanup = r'''
# Remove Advanced Settings/font controls and add multi-stop amenity assignment support.
content = content.replace("        add_action('admin_menu', array($this, 'add_advanced_settings_page'));\n", "")
content = content.replace("        add_action('admin_post_kcsg_save_advanced_settings', array($this, 'save_advanced_settings'));\n", "")
content = re.sub(r"\n    public static function get_font_settings\(\) \{.*?\n    public static function ensure_stop_header_crop\(", "\n    public static function ensure_stop_header_crop(", content, flags=re.S)
content = re.sub(r"\n    public function add_advanced_settings_page\(\) \{.*?\n    public function save_advanced_settings\(\) \{.*?\n    \}\n", "\n", content, flags=re.S)
content = content.replace("        $is_advanced_settings_page = ($current_page === 'kcsg-advanced-settings');\n", "")
content = content.replace(" && !$is_advanced_settings_page", "")
content = content.replace("            'fontSettings' => self::get_font_settings(),\n", "")
content = content.replace("        $font_settings = self::get_font_settings();\n        $guide_font_class = 'kcsg-font-' . $font_settings['mode'];\n        $guide_font_style = self::get_guide_font_style();\n\n", "")
content = content.replace('        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide <?php echo esc_attr($guide_font_class); ?>" style="<?php echo esc_attr($guide_font_style); ?>" data-kcsg-guide>\n', '        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide" data-kcsg-guide>\n')

content = content.replace(
    "        $featured = get_post_meta($post->ID, '_kcsg_featured', true);\n        $current_terms = get_the_terms($post->ID, self::TAX);\n",
    "        $featured = get_post_meta($post->ID, '_kcsg_featured', true);\n        $saved_stops = get_post_meta($post->ID, '_kcsg_stops', true);\n        $selected_stops = is_array($saved_stops) ? array_values(array_intersect(array_map('sanitize_key', $saved_stops), array_keys(self::stops()))) : array();\n        if (!$selected_stops && $stop) {\n            $selected_stops = array($stop);\n        }\n        $current_terms = get_the_terms($post->ID, self::TAX);\n"
)
content = re.sub(
    r"\n            <p class=\"kcsg-admin-field kcsg-admin-field-stop\">\n.*?\n            </p>\n\n            <p class=\"kcsg-admin-field kcsg-admin-field-category\">",
    """
            <p class=\"kcsg-admin-field kcsg-admin-field-stop\">
                <label for=\"kcsg_stops\"><strong><?php esc_html_e('Streetcar Stops', 'kc-streetcar-guide'); ?></strong></label>
                <select name=\"kcsg_stops[]\" id=\"kcsg_stops\" multiple size=\"6\">
                    <?php foreach (self::stops() as $stop_id => $stop_label) : ?>
                        <option value=\"<?php echo esc_attr($stop_id); ?>\" <?php selected(in_array($stop_id, $selected_stops, true)); ?>><?php echo esc_html($stop_label); ?></option>
                    <?php endforeach; ?>
                </select>
                <span class=\"description\"><?php esc_html_e('Choose every stop that works for this amenity. Hold Ctrl/Command to select more than one.', 'kc-streetcar-guide'); ?></span>
            </p>

            <p class=\"kcsg-admin-field kcsg-admin-field-category\">""",
    content,
    count=1,
    flags=re.S,
)
content = content.replace(
    "            .kcsg-admin-field input[type=checkbox], .kcsg-stop-photo-tools input[type=checkbox] { appearance: checkbox !important; -webkit-appearance: checkbox !important; width: 16px !important; min-width: 16px !important; max-width: 16px !important; height: 16px !important; min-height: 16px !important; max-height: 16px !important; margin: 0 6px 0 0 !important; padding: 0 !important; vertical-align: middle !important; }",
    "            .kcsg-admin-field input[type=checkbox], .kcsg-stop-photo-tools input[type=checkbox] { appearance: checkbox !important; -webkit-appearance: checkbox !important; width: 16px !important; min-width: 16px !important; max-width: 16px !important; height: 16px !important; min-height: 16px !important; max-height: 16px !important; margin: 0 6px 0 0 !important; padding: 0 !important; vertical-align: middle !important; }\n            .kcsg-admin-field-stop select[multiple] { min-height: 138px !important; }"
)
content = re.sub(
    r"        \$allowed_stops = array_keys\(self::stops\(\)\);\n        \$stop = isset\(\$_POST\['kcsg_stop'\]\).*?\n\n        \$location = self::sanitize_location_payload\(",
    """        $allowed_stops = array_keys(self::stops());
        $incoming_stops = isset($_POST['kcsg_stops']) && is_array($_POST['kcsg_stops']) ? wp_unslash($_POST['kcsg_stops']) : array();
        $incoming_stops = array_map('sanitize_key', $incoming_stops);
        $stops = array_values(array_intersect($incoming_stops, $allowed_stops));
        if (!$stops && isset($_POST['kcsg_stop'])) {
            $legacy_stop = sanitize_key(wp_unslash($_POST['kcsg_stop']));
            if (in_array($legacy_stop, $allowed_stops, true)) {
                $stops = array($legacy_stop);
            }
        }
        $stop = !empty($stops) ? $stops[0] : '';

        $location = self::sanitize_location_payload(""",
    content,
    count=1,
    flags=re.S,
)
content = content.replace(
    "        foreach ($fields as $key => $value) {\n            if ($value === '') {\n                delete_post_meta($post_id, $key);\n            } else {\n                update_post_meta($post_id, $key, $value);\n            }\n        }\n\n        $category_slug = isset($_POST['kcsg_category']) ? sanitize_title(wp_unslash($_POST['kcsg_category'])) : '';\n",
    "        foreach ($fields as $key => $value) {\n            if ($value === '') {\n                delete_post_meta($post_id, $key);\n            } else {\n                update_post_meta($post_id, $key, $value);\n            }\n        }\n\n        if (!empty($stops)) {\n            update_post_meta($post_id, '_kcsg_stops', $stops);\n        } else {\n            delete_post_meta($post_id, '_kcsg_stops');\n        }\n\n        $category_slug = isset($_POST['kcsg_category']) ? sanitize_title(wp_unslash($_POST['kcsg_category'])) : '';\n"
)
content = re.sub(
    r"\n        if \(\$column === 'kcsg_stop'\) \{.*?\n        \}\n\n        if \(\$column === 'kcsg_featured'\)",
    """
        if ($column === 'kcsg_stop') {
            $stop_ids = get_post_meta($post_id, '_kcsg_stops', true);
            if (!is_array($stop_ids)) {
                $stop_ids = array();
            }
            $legacy_stop = get_post_meta($post_id, '_kcsg_stop', true);
            if (!$stop_ids && $legacy_stop) {
                $stop_ids = array($legacy_stop);
            }
            $available_stops = self::stops();
            $labels = array();
            foreach ($stop_ids as $stop_id) {
                if (isset($available_stops[$stop_id])) {
                    $labels[] = $available_stops[$stop_id];
                }
            }
            echo $labels ? esc_html(implode(', ', $labels)) : esc_html__('—', 'kc-streetcar-guide');
        }

        if ($column === 'kcsg_featured')""",
    content,
    count=1,
    flags=re.S,
)
content = content.replace(
    "            $stop_id = get_post_meta($post->ID, '_kcsg_stop', true);\n            $amenities[] = array(\n                'id' => $post->ID,\n                'name' => self::decode_plain_text(get_the_title($post)),\n                'stop' => $stop_id,\n                'stopLabel' => isset($stops[$stop_id]) ? $stops[$stop_id] : '',\n",
    """            $stop_id = get_post_meta($post->ID, '_kcsg_stop', true);
            $stop_ids = get_post_meta($post->ID, '_kcsg_stops', true);
            $stop_ids = is_array($stop_ids) ? $stop_ids : array();
            $stop_ids = array_values(array_unique(array_intersect(array_map('sanitize_key', $stop_ids), array_keys($stops))));
            if (!$stop_ids && $stop_id && isset($stops[$stop_id])) {
                $stop_ids = array($stop_id);
            }
            $primary_stop_id = !empty($stop_ids) ? $stop_ids[0] : $stop_id;
            $stop_labels = array();
            foreach ($stop_ids as $amenity_stop_id) {
                if (isset($stops[$amenity_stop_id])) {
                    $stop_labels[] = $stops[$amenity_stop_id];
                }
            }
            $amenities[] = array(
                'id' => $post->ID,
                'name' => self::decode_plain_text(get_the_title($post)),
                'stop' => $primary_stop_id,
                'stops' => $stop_ids,
                'stopLabel' => $stop_labels ? implode(', ', $stop_labels) : (isset($stops[$primary_stop_id]) ? $stops[$primary_stop_id] : ''),
                'stopLabels' => $stop_labels,
"""
)
'''

if 'add multi-stop amenity assignment support.' not in script:
    script = script.replace('php.write_text(content)\n\n# Frontend JS.', final_php_cleanup + '\nphp.write_text(content)\n\n# Frontend JS.', 1)

multi_stop_js = r"""
# Support amenities assigned to multiple stops in frontend filtering/rendering.
multi_stop_helpers = r'''    function stopIdsForAmenity(amenity) {
      var ids = Array.isArray(amenity.stops) ? amenity.stops.filter(Boolean) : [];
      if (!ids.length && amenity.stop) {
        ids = [amenity.stop];
      }
      return ids;
    }

    function amenityMatchesStop(amenity, stopId) {
      return stopIdsForAmenity(amenity).indexOf(stopId) !== -1;
    }

    function stopLabelsForAmenity(amenity) {
      var labels = Array.isArray(amenity.stopLabels) ? amenity.stopLabels.filter(Boolean) : [];
      if (!labels.length) {
        labels = stopIdsForAmenity(amenity).map(function (stopId) {
          return data.stops && data.stops[stopId] ? data.stops[stopId] : '';
        }).filter(Boolean);
      }
      return labels.length ? labels.join(', ') : (amenity.stopLabel || 'Not assigned');
    }
'''
if 'function stopIdsForAmenity' not in js_content:
    js_content = js_content.replace('    function currentStopCategories(stopId) {', multi_stop_helpers + '\n    function currentStopCategories(stopId) {', 1)
js_content = js_content.replace('if (amenity.stop !== stopId) return;', 'if (!amenityMatchesStop(amenity, stopId)) return;')
js_content = js_content.replace('return amenity.stop === state.stop;', 'return amenityMatchesStop(amenity, state.stop);')
js_content = js_content.replace("var stopLabelText = amenity.stopLabel || 'Not assigned';", "var stopLabelText = stopLabelsForAmenity(amenity);")
"""

if 'Support amenities assigned to multiple stops in frontend filtering/rendering.' not in script:
    script = script.replace('js.write_text(js_content)\n\n# Frontend CSS', multi_stop_js + '\njs.write_text(js_content)\n\n# Frontend CSS', 1)

builder.write_text(script)
print('Prepared release build without Advanced Settings, with multi-stop amenities.')
