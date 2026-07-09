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
      placeholder.textContent = 'Select streetcar stop';
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
.kcsg-header h2 {
  margin-bottom: 0 !important;
}

.kcsg-header p {
  margin-top: 0 !important;
}

.kcsg-reset-row {
  display: none !important;
}

.kcsg-controls {
  display: grid !important;
  grid-template-columns: minmax(0, 1fr) minmax(220px, 300px);
  align-items: end;
  column-gap: 18px;
  row-gap: 10px;
  width: 100%;
  margin: 10px 0 12px !important;
  padding: 0 !important;
}

.kcsg-control-group {
  min-width: 0;
}

.kcsg-control-label {
  display: block;
  margin: 0 0 6px !important;
  padding: 0 !important;
  color: var(--kcsg-muted);
  font-size: 11px;
  font-weight: 850;
  line-height: 1;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.kcsg-category-key {
  align-items: center;
  margin: 0 !important;
}

.kcsg-category-key .kcsg-reset {
  appearance: none;
  border: 0 !important;
  border-radius: 0 !important;
  background: transparent !important;
  box-shadow: none !important;
  color: #d6422d !important;
  padding: 0 0 0 2px !important;
  font-size: 13px;
  font-weight: 800;
  line-height: 1;
  text-transform: lowercase;
  text-decoration: none !important;
}

.kcsg-category-key .kcsg-reset:hover,
.kcsg-category-key .kcsg-reset:focus-visible {
  background: transparent !important;
  border-color: transparent !important;
  color: #a82f20 !important;
  transform: none !important;
  text-decoration: underline !important;
  text-underline-offset: 3px;
  outline: 0;
}

.kcsg-stop-select {
  appearance: none;
  width: 100%;
  min-height: 36px;
  border: 1px solid var(--kcsg-line);
  border-radius: 12px;
  background-color: #ffffff;
  color: var(--kcsg-blue-dark);
  cursor: pointer;
  font: inherit;
  font-size: 14px;
  font-weight: 650;
  line-height: 1.2;
  padding: 8px 36px 8px 11px;
  box-shadow: 0 6px 14px rgba(9, 60, 87, 0.04);
}

.kcsg-stop-select:hover,
.kcsg-stop-select:focus-visible {
  border-color: var(--kcsg-blue);
  outline: 0;
}

.kcsg-layout {
  align-items: start !important;
  margin-top: 0 !important;
}

.kcsg-guide.is-stop-with-photo .kcsg-results-heading {
  display: none !important;
}

.kcsg-stop-photo {
  margin-top: 0 !important;
}

@media (max-width: 760px) {
  .kcsg-controls {
    grid-template-columns: 1fr;
  }
}
'''
    CSS_PATH.write_text(css)


patch_php()
patch_js()
patch_css()
print('Release patches applied.')
