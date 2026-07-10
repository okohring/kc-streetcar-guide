from pathlib import Path
import re

builder = Path('.github/build-and-release.sh')
script = builder.read_text()

script = script.replace(
    'Adds featured amenities, configurable featured locations, advanced font controls, entity decoding for titles, and keeps the map-link-only amenity workflow plus bulk stop photo crop tools.',
    'Keeps executive-pick amenity toggles, advanced font controls, entity decoding, map-link-only amenities, and bulk stop photo crop tools.'
)
script = script.replace(
    '- Adds Advanced Settings with configurable Featured Locations, including show/hide, label, assigned streetcar stop, Google Maps URL, and optional website URL.\n',
    ''
)

# Remove the generated Featured Locations helper functions. Font settings remain in Advanced Settings.
script = re.sub(
    r"\n    public static function default_featured_locations\(\) \{.*?\n    public static function get_font_settings\(\) \{",
    "\n    public static function get_font_settings() {",
    script,
    flags=re.S,
)

# Remove Featured Locations fields from the generated Advanced Settings page.
script = re.sub(
    r"\n        \$featured_locations = self::get_featured_locations\(\);\n        \$stops = self::stops\(\);\n        for \(\$i = count\(\$featured_locations\);.*?\n        \}\n",
    "\n",
    script,
    flags=re.S,
)
script = re.sub(
    r"\n                <section class=\"kcsg-advanced-card\">\n                    <h2><\?php esc_html_e\('Featured Locations'.*?\n                </section>\n",
    "\n",
    script,
    flags=re.S,
)
script = re.sub(
    r"\n        \$incoming_locations = isset\(\$_POST\['kcsg_featured_locations'\].*?update_option\('kcsg_featured_locations', \$locations, false\);\n",
    "\n",
    script,
    flags=re.S,
)

# Do not send Featured Locations data to the frontend.
script = script.replace("            'featuredLocations' => self::get_featured_locations(),\n", "")

# Keep admin checkboxes from inheriting full-width text input styling.
script = script.replace(
    "            .kcsg-admin-field input, .kcsg-admin-field select, .kcsg-admin-field textarea { width: 100%; max-width: 100%; }",
    "            .kcsg-admin-field input:not([type=checkbox]), .kcsg-admin-field select, .kcsg-admin-field textarea { width: 100%; max-width: 100%; }\n            .kcsg-admin-field input[type=checkbox], .kcsg-stop-photo-tools input[type=checkbox] { appearance: checkbox !important; -webkit-appearance: checkbox !important; width: 16px !important; min-width: 16px !important; max-width: 16px !important; height: 16px !important; min-height: 16px !important; max-height: 16px !important; margin: 0 6px 0 0 !important; padding: 0 !important; vertical-align: middle !important; }"
)

# Remove Featured Location card rendering from the generated frontend JS.
script = re.sub(
    r"\n    function currentFeaturedLocations\(\) \{.*?\n    \}\n\n    function cardTemplate",
    "\n    function cardTemplate",
    script,
    flags=re.S,
)
script = re.sub(
    r"\n    function featuredLocationTemplate\(location\) \{.*?\n    \}\n\n    function categoryHeaderMarkup",
    "\n\n    function categoryHeaderMarkup",
    script,
    flags=re.S,
)

render_block_def = """render_block = r'''    function render() {
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

    function attachResultHoverEvents'''"""
script = re.sub(
    r"render_block = r'''    function render\(\) \{.*?    function attachResultHoverEvents'''",
    render_block_def,
    script,
    flags=re.S,
)

builder.write_text(script)

# Remove inline SVG scripting/layers from the source before packaging.
svg = Path('assets/kc-streetcar-line.svg')
if svg.exists():
    svg_text = svg.read_text()
    svg_text = re.sub(r'\s*<script>\s*<!\[CDATA\[.*?\]\]>\s*</script>\s*', '\n', svg_text, flags=re.S)
    svg_text = re.sub(r'\s*<g id="kcsg-featured-map-locations"[^>]*>\s*</g>\s*', '\n', svg_text, flags=re.S)
    svg.write_text(svg_text)

print('Prepared simplified executive-pick release build.')
