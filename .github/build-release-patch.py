from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PHP_PATH = ROOT / 'kc-streetcar-guide.php'
JS_PATH = ROOT / 'assets' / 'kcsg-frontend.js'
CSS_PATH = ROOT / 'assets' / 'kcsg-frontend.css'


def patch_php() -> None:
    content = PHP_PATH.read_text()
    content = content.replace("        add_filter('upgrader_post_install', array($this, 'rename_release_folder'), 10, 3);\n", "")
    content = re.sub(
        r"\n    public function rename_release_folder\(\$response, \$hook_extra, \$result\) \{.*?\n    \}\n",
        "\n",
        content,
        flags=re.S,
    )
    PHP_PATH.write_text(content)


def replace_once(content: str, old: str, new: str, label: str) -> str:
    if new in content:
        return content
    if old not in content:
        raise RuntimeError(f'Could not apply patch: {label}')
    return content.replace(old, new, 1)


def patch_js() -> None:
    js = JS_PATH.read_text()

    js = replace_once(
        js,
        "    var buttons = Array.prototype.slice.call(guide.querySelectorAll('[data-kcsg-category]'));\n"
        "    var resetButton = guide.querySelector('[data-kcsg-reset]');\n"
        "    var results = guide.querySelector('[data-kcsg-results]');",
        "    var buttons = Array.prototype.slice.call(guide.querySelectorAll('[data-kcsg-category]'));\n"
        "    var resetButton = guide.querySelector('[data-kcsg-reset]');\n"
        "    var categoryKey = guide.querySelector('.kcsg-category-key');\n"
        "    var resetRow = guide.querySelector('.kcsg-reset-row');\n"
        "    var stopSelect = null;\n"
        "    var results = guide.querySelector('[data-kcsg-results]');",
        'control variable setup',
    )

    if 'function buildControlBar()' not in js:
        build_control_bar = r'''
    function buildControlBar() {
      if (!categoryKey || categoryKey.closest('.kcsg-controls')) return;

      var controls = document.createElement('div');
      controls.className = 'kcsg-controls';

      var categoryGroup = document.createElement('div');
      categoryGroup.className = 'kcsg-control-group kcsg-control-group--categories';

      var categoryLabel = document.createElement('div');
      categoryLabel.className = 'kcsg-control-label';
      categoryLabel.textContent = 'Categories';

      categoryKey.parentNode.insertBefore(controls, categoryKey);
      controls.appendChild(categoryGroup);
      categoryGroup.appendChild(categoryLabel);
      categoryGroup.appendChild(categoryKey);

      if (resetButton) {
        resetButton.textContent = 'reset';
        categoryKey.appendChild(resetButton);
      }

      if (resetRow && resetRow.parentNode) {
        resetRow.parentNode.removeChild(resetRow);
      }

      var stopGroup = document.createElement('div');
      stopGroup.className = 'kcsg-control-group kcsg-control-group--stop';

      var selectId = 'kcsg-stop-select-' + Math.random().toString(36).slice(2, 9);
      var stopLabelNode = document.createElement('label');
      stopLabelNode.className = 'kcsg-control-label';
      stopLabelNode.setAttribute('for', selectId);
      stopLabelNode.textContent = 'Streetcar stop';

      stopSelect = document.createElement('select');
      stopSelect.className = 'kcsg-stop-select';
      stopSelect.setAttribute('id', selectId);
      stopSelect.setAttribute('data-kcsg-stop-select', '');

      var placeholder = document.createElement('option');
      placeholder.value = '';
      placeholder.textContent = 'Choose streetcar stop';
      stopSelect.appendChild(placeholder);

      Object.keys(data.stops || {}).forEach(function (stopId) {
        var option = document.createElement('option');
        option.value = stopId;
        option.textContent = data.stops[stopId];
        stopSelect.appendChild(option);
      });

      stopGroup.appendChild(stopLabelNode);
      stopGroup.appendChild(stopSelect);
      controls.appendChild(stopGroup);
    }
'''
        js = replace_once(
            js,
            "    function setActiveButton(slug) {",
            build_control_bar + "\n    function setActiveButton(slug) {",
            'build control bar function',
        )

    if 'function setStopSelect(stopId)' not in js:
        js = replace_once(
            js,
            "    function setActiveStop(stopId) {\n"
            "      stopGroups.forEach(function (group) {\n"
            "        var isActive = group.id === stopId;\n"
            "        group.classList.toggle('is-active', isActive);\n"
            "      });\n"
            "    }",
            "    function setActiveStop(stopId) {\n"
            "      stopGroups.forEach(function (group) {\n"
            "        var isActive = group.id === stopId;\n"
            "        group.classList.toggle('is-active', isActive);\n"
            "      });\n"
            "    }\n\n"
            "    function setStopSelect(stopId) {\n"
            "      if (!stopSelect) return;\n"
            "      stopSelect.value = stopId || '';\n"
            "    }",
            'stop select state sync',
        )

    js = replace_once(
        js,
        "      setActiveStop(state.stop);\n"
        "      updateStopMuting();",
        "      setActiveStop(state.stop);\n"
        "      setStopSelect(state.mode === 'stop' ? state.stop : '');\n"
        "      updateStopMuting();",
        'render stop select sync',
    )

    if 'buildControlBar();' not in js:
        js = replace_once(
            js,
            "    buttons.forEach(function (button) {\n"
            "      button.addEventListener('click', function () {",
            "    buildControlBar();\n\n"
            "    buttons.forEach(function (button) {\n"
            "      button.addEventListener('click', function () {",
            'build controls before binding controls',
        )

    if "stopSelect.addEventListener('change'" not in js:
        js = replace_once(
            js,
            "    if (resetButton) {\n"
            "      resetButton.addEventListener('click', function () {",
            "    if (stopSelect) {\n"
            "      stopSelect.addEventListener('change', function () {\n"
            "        var stopId = stopSelect.value;\n"
            "        if (stopId) {\n"
            "          chooseStop(stopId);\n"
            "          return;\n"
            "        }\n"
            "        state.category = 'all';\n"
            "        state.stop = null;\n"
            "        state.mode = 'all';\n"
            "        render();\n"
            "      });\n"
            "    }\n\n"
            "    if (resetButton) {\n"
            "      resetButton.addEventListener('click', function () {",
            'stop select change handler',
        )

    JS_PATH.write_text(js)


def patch_css() -> None:
    css = CSS_PATH.read_text()
    if 'visitor guide controls UI overhaul' in css:
        return

    css += r'''

/* Release tweak: hide the redundant external-link icon in the stop photo tracker header. */
.kcsg-stop-photo .kcsg-live-link {
  display: none !important;
}

/* Release tweak: add a crisp white border around stop photos. */
.kcsg-stop-photo {
  border: 2px solid #ffffff !important;
}

/* Release tweak: visitor guide controls UI overhaul. */
.kcsg-guide {
  gap: 2px !important;
  row-gap: 2px !important;
}

.kcsg-header h2 {
  margin: 0 !important;
  font-size: clamp(18px, 2vw, 22px) !important;
  line-height: 1.05 !important;
}

.kcsg-header p {
  margin: 0 !important;
  font-size: 11px !important;
  line-height: 1.15 !important;
}

.kcsg-reset-row {
  display: none !important;
}

.kcsg-controls {
  display: grid !important;
  grid-template-columns: minmax(0, 1fr) minmax(145px, 162px);
  align-items: center;
  column-gap: 16px;
  row-gap: 6px;
  width: 100%;
  margin: 8px 0 10px !important;
  padding: 0 !important;
}

.kcsg-control-group {
  min-width: 0;
}

.kcsg-control-label {
  display: none !important;
}

.kcsg-category-key {
  align-items: center;
  gap: 4px !important;
  margin: 0 !important;
  padding: 0 !important;
}

.kcsg-category-button {
  padding: 5px 8px !important;
  font-size: 11px !important;
  font-weight: 800 !important;
}

.kcsg-category-key .kcsg-reset {
  display: none !important;
}

.kcsg-stop-select {
  appearance: auto;
  width: 100%;
  min-height: 23px;
  border: 1px solid #cbd7df;
  border-radius: 0;
  background-color: #ffffff;
  color: var(--kcsg-ink);
  cursor: pointer;
  font: inherit;
  font-size: 10px;
  font-weight: 700;
  line-height: 1.1;
  padding: 3px 6px;
  box-shadow: none;
}

.kcsg-stop-select:hover,
.kcsg-stop-select:focus-visible {
  border-color: var(--kcsg-blue);
  outline: 0;
}

.kcsg-layout {
  grid-template-columns: minmax(105px, 138px) minmax(0, 1fr) !important;
  gap: 12px !important;
  align-items: start !important;
  margin-top: 0 !important;
}

.kcsg-map-panel {
  justify-content: center !important;
  max-height: 430px !important;
  top: 0 !important;
}

.kcsg-map-svg {
  height: 430px !important;
  max-height: 430px !important;
}

.kcsg-results-scroll {
  max-height: 430px !important;
  padding-right: 0 !important;
}

.kcsg-guide.is-stop-with-photo .kcsg-results-heading {
  display: none !important;
}

.kcsg-stop-photo {
  margin: 0 0 10px !important;
  border-radius: 10px !important;
}

.kcsg-stop-photo img {
  height: clamp(120px, 22vw, 150px) !important;
}

.kcsg-stop-photo figcaption {
  left: 10px !important;
  bottom: 10px !important;
  font-size: clamp(20px, 2.5vw, 28px) !important;
}

.kcsg-stop-photo.has-live-arrivals figcaption {
  bottom: 34px !important;
}

.kcsg-live-arrivals {
  left: 10px !important;
  right: 10px !important;
  bottom: 9px !important;
}

.kcsg-live-kicker {
  font-size: 8px !important;
}

.kcsg-results {
  gap: 10px !important;
}

.kcsg-card {
  border-radius: 10px !important;
  padding: 10px !important;
  box-shadow: 0 7px 16px rgba(9, 60, 87, 0.05) !important;
}

.kcsg-card-header {
  margin-bottom: 7px !important;
}

.kcsg-card h4 {
  font-size: 13px !important;
  line-height: 1.15 !important;
}

.kcsg-category-pill {
  font-size: 9px !important;
  padding: 4px 6px !important;
}

.kcsg-link {
  width: 22px !important;
  height: 22px !important;
}

.kcsg-link svg {
  width: 13px !important;
  height: 13px !important;
}

.kcsg-meta {
  gap: 5px !important;
  margin: 7px 0 !important;
}

.kcsg-meta span {
  border-radius: 7px !important;
  padding: 5px 6px !important;
  font-size: 10px !important;
  line-height: 1.18 !important;
}

.kcsg-meta strong {
  font-size: 9px !important;
  margin-bottom: 1px !important;
}

.kcsg-description {
  margin-top: 6px !important;
  font-size: 10px !important;
  line-height: 1.35 !important;
}

@media (max-width: 760px) {
  .kcsg-controls {
    grid-template-columns: 1fr;
  }

  .kcsg-layout {
    grid-template-columns: 1fr !important;
  }

  .kcsg-map-panel,
  .kcsg-map-svg {
    max-height: 520px !important;
  }

  .kcsg-map-svg {
    height: min(520px, 76vh) !important;
  }

  .kcsg-results-scroll {
    max-height: none !important;
  }
}
'''
    CSS_PATH.write_text(css)


patch_php()
patch_js()
patch_css()
print('Release patches applied.')
