from pathlib import Path
import re

builder = Path('.github/build-and-release.sh')
script = builder.read_text()

script = script.replace(
    'Keeps amenity-level Executive Pick toggles, advanced font controls, entity decoding, map-link-only amenities, and bulk stop photo crop tools. Removes Featured Locations cards and SVG map stars.',
    'Keeps amenity-level Executive Pick toggles, entity decoding, map-link-only amenities, mobile stop headers, and bulk stop photo crop tools. Removes Advanced Settings, font controls, Featured Locations cards, and SVG map stars.'
)
script = script.replace(
    '- Adds font controls for inheriting the theme font or using Arial, plus adjustable base font size.\n',
    ''
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

advanced_cleanup = r'''
# Remove Advanced Settings and font controls from the final release PHP.
content = content.replace("        add_action('admin_menu', array($this, 'add_advanced_settings_page'));\n", "")
content = content.replace("        add_action('admin_post_kcsg_save_advanced_settings', array($this, 'save_advanced_settings'));\n", "")
content = re.sub(r"\n    public static function get_font_settings\(\) \{.*?\n    public static function ensure_stop_header_crop\(", "\n    public static function ensure_stop_header_crop(", content, flags=re.S)
content = re.sub(r"\n    public function add_advanced_settings_page\(\) \{.*?\n    public function save_advanced_settings\(\) \{.*?\n    \}\n", "\n", content, flags=re.S)
content = content.replace("        $is_advanced_settings_page = ($current_page === 'kcsg-advanced-settings');\n", "")
content = content.replace(" && !$is_advanced_settings_page", "")
content = content.replace("            'fontSettings' => self::get_font_settings(),\n", "")
content = content.replace("        $font_settings = self::get_font_settings();\n        $guide_font_class = 'kcsg-font-' . $font_settings['mode'];\n        $guide_font_style = self::get_guide_font_style();\n\n", "")
content = content.replace('        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide <?php echo esc_attr($guide_font_class); ?>" style="<?php echo esc_attr($guide_font_style); ?>" data-kcsg-guide>\n', '        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide" data-kcsg-guide>\n')
'''

if 'Remove Advanced Settings and font controls from the final release PHP.' not in script:
    script = script.replace('php.write_text(content)\n\n# Frontend JS.', advanced_cleanup + '\nphp.write_text(content)\n\n# Frontend JS.', 1)

builder.write_text(script)
print('Prepared release build without Advanced Settings or font controls.')
