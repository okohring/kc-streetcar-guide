(function () {
  function ready(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  function esc(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function cssColor(value, fallback) {
    var color = String(value || '').trim();
    return /^#[0-9a-fA-F]{6}$/.test(color) ? color : (fallback || '#008bd2');
  }

  function firstCategory(amenity) {
    if (!amenity.categories || !amenity.categories.length) {
      return null;
    }
    return amenity.categories[0];
  }

  function amenityMatchesCategory(amenity, categorySlug) {
    if (!categorySlug || categorySlug === 'all') {
      return true;
    }
    return (amenity.categories || []).some(function (category) {
      return category.slug === categorySlug;
    });
  }

  function initGuide(guide) {
    var dataNode = guide.querySelector('[data-kcsg-data]');
    if (!dataNode) return;

    var data;
    try {
      data = JSON.parse(dataNode.textContent || '{}');
    } catch (error) {
      return;
    }

    var state = {
      category: 'all',
      stop: null,
      mode: 'all'
    };

    var arrivalsCache = {};
    var arrivalsRequestId = 0;

    var buttons = Array.prototype.slice.call(guide.querySelectorAll('[data-kcsg-category]'));
    var resetRow = guide.querySelector('.kcsg-reset-row');
    var categoryKey = guide.querySelector('.kcsg-category-key');
    var stopSelect = null;
    var results = guide.querySelector('[data-kcsg-results]');
    var resultsScroll = guide.querySelector('[data-kcsg-results-scroll]');
    var stopFeature = guide.querySelector('[data-kcsg-stop-feature]');
    var title = guide.querySelector('[data-kcsg-results-title]');
    var count = guide.querySelector('[data-kcsg-results-count]');
    var stopGroups = Array.prototype.slice.call(guide.querySelectorAll('.kcsg-map-svg #stops > g[id]'));

    function getCategoryLabel(slug) {
      if (slug === 'all') return 'All amenities';
      var category = (data.categories || []).find(function (item) {
        return item.slug === slug;
      });
      return category ? category.name : 'Amenities';
    }

    function buildControlBar() {
      if (!categoryKey || categoryKey.closest('.kcsg-controls')) return;

      var controls = document.createElement('div');
      controls.className = 'kcsg-controls';

      var categoryGroup = document.createElement('div');
      categoryGroup.className = 'kcsg-control-group kcsg-control-group--categories';

      categoryKey.parentNode.insertBefore(controls, categoryKey);
      controls.appendChild(categoryGroup);
      categoryGroup.appendChild(categoryKey);

      if (resetRow && resetRow.parentNode) {
        resetRow.parentNode.removeChild(resetRow);
      }

      var stopGroup = document.createElement('div');
      stopGroup.className = 'kcsg-control-group kcsg-control-group--stop';

      var selectId = 'kcsg-stop-select-' + Math.random().toString(36).slice(2, 9);
      var stopLabelNode = document.createElement('label');
      stopLabelNode.className = 'screen-reader-text kcsg-control-label';
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

    function setActiveButton(slug) {
      buttons.forEach(function (button) {
        button.classList.toggle('is-active', button.getAttribute('data-kcsg-category') === slug);
      });
    }

    function setActiveStop(stopId) {
      stopGroups.forEach(function (group) {
        group.classList.toggle('is-active', group.id === stopId);
      });
    }

    function setStopSelect(stopId) {
      if (!stopSelect) return;
      stopSelect.value = stopId || '';
    }

    function setHoverStop(stopId, active) {
      if (!stopId) return;
      stopGroups.forEach(function (group) {
        if (group.id === stopId) {
          group.classList.toggle('is-hovered', !!active);
        }
      });
    }

    function buildStopHitAreas() {
      var svg = guide.querySelector('.kcsg-map-svg');
      if (!svg || !stopGroups.length) return;

      stopGroups.forEach(function (group) {
        var previousHitArea = group.querySelector('.kcsg-stop-hitarea');
        if (previousHitArea) {
          previousHitArea.remove();
        }

        var bbox;
        try {
          bbox = group.getBBox();
        } catch (error) {
          return;
        }

        if (!bbox || !bbox.width || !bbox.height) return;

        var padX = 7;
        var padY = 5;
        var hitArea = document.createElementNS('http://www.w3.org/2000/svg', 'rect');

        hitArea.setAttribute('class', 'kcsg-stop-hitarea');
        hitArea.setAttribute('x', bbox.x - padX);
        hitArea.setAttribute('y', bbox.y - padY);
        hitArea.setAttribute('width', bbox.width + (padX * 2));
        hitArea.setAttribute('height', bbox.height + (padY * 2));
        hitArea.setAttribute('rx', '4');
        hitArea.setAttribute('ry', '4');
        hitArea.setAttribute('aria-hidden', 'true');
        hitArea.setAttribute('focusable', 'false');

        group.insertBefore(hitArea, group.firstChild);
      });
    }

    function updateStopMuting() {
      stopGroups.forEach(function (group) {
        group.classList.remove('is-muted');
      });
    }

    function currentFilteredAmenities() {
      var amenities = data.amenities || [];

      if (state.mode === 'stop' && state.stop) {
        return amenities.filter(function (amenity) {
          return amenity.stop === state.stop;
        });
      }

      if (state.mode === 'category') {
        return amenities.filter(function (amenity) {
          return amenityMatchesCategory(amenity, state.category);
        });
      }

      return amenities;
    }

    function stopLabel(stopId) {
      return (data.stops && data.stops[stopId]) ? data.stops[stopId] : 'Selected stop';
    }

    function trackerForStop(stopId) {
      return (data.stopTrackers && data.stopTrackers[stopId] && data.stopTrackers[stopId].url) ? data.stopTrackers[stopId].url : '';
    }

    function arrivalsEndpoint(stopId) {
      if (!data.arrivalsEndpoint || !stopId) return '';
      return String(data.arrivalsEndpoint).replace(/\/$/, '') + '/' + encodeURIComponent(stopId);
    }

    function arrivalStatusText(payload) {
      if (!payload || !payload.ok || !payload.arrivals || !payload.arrivals.length) {
        return '';
      }

      var first = payload.arrivals[0];
      var status = '';

      if (first.soon) {
        status = first.label || 'Arriving soon';
      } else if (typeof first.minutes === 'number') {
        status = 'Next: ' + first.minutes + ' min';
      } else {
        status = first.label || 'Live arrivals';
      }

      if (first.direction) {
        status += ' • ' + first.direction;
      }

      return status;
    }

    function setLiveArrivalStatus(stopId, payload) {
      var liveNode = stopFeature ? stopFeature.querySelector('[data-kcsg-live-arrivals]') : null;
      if (!liveNode || liveNode.getAttribute('data-kcsg-live-stop') !== stopId) return;

      var statusNode = liveNode.querySelector('[data-kcsg-live-status]');
      if (!statusNode) return;

      var text = arrivalStatusText(payload);
      statusNode.textContent = text;
      statusNode.hidden = !text;
      liveNode.classList.toggle('has-arrivals', !!(payload && payload.ok));
      liveNode.classList.toggle('has-fallback', !(payload && payload.ok));
    }

    function loadArrivals(stopId) {
      var liveNode = stopFeature ? stopFeature.querySelector('[data-kcsg-live-arrivals]') : null;
      var endpoint = arrivalsEndpoint(stopId);

      if (!liveNode || !endpoint) return;

      if (arrivalsCache[stopId]) {
        setLiveArrivalStatus(stopId, arrivalsCache[stopId]);
        return;
      }

      var requestId = ++arrivalsRequestId;
      var statusNode = liveNode.querySelector('[data-kcsg-live-status]');
      if (statusNode) {
        statusNode.textContent = 'Checking live times…';
      }

      fetch(endpoint, { credentials: 'same-origin' })
        .then(function (response) {
          if (!response.ok) throw new Error('Arrival request failed');
          return response.json();
        })
        .then(function (payload) {
          if (requestId !== arrivalsRequestId) return;
          arrivalsCache[stopId] = payload;
          setLiveArrivalStatus(stopId, payload);
        })
        .catch(function () {
          if (requestId !== arrivalsRequestId) return;
          var fallback = { ok: false, arrivals: [] };
          arrivalsCache[stopId] = fallback;
          setLiveArrivalStatus(stopId, fallback);
        });
    }

    function selectedStopPhotoMarkup(stopId) {
      if (!stopId) {
        return '';
      }

      var photo = (data.stopPhotos && data.stopPhotos[stopId]) ? data.stopPhotos[stopId] : null;
      var trackerUrl = trackerForStop(stopId);

      if (!photo && !trackerUrl) {
        return '';
      }

      var liveMarkup = trackerUrl ? '' +
        '<div class="kcsg-live-arrivals" data-kcsg-live-arrivals data-kcsg-live-stop="' + esc(stopId) + '">' +
          '<a class="kcsg-live-kicker" href="' + esc(trackerUrl) + '" target="_blank" rel="noopener noreferrer" aria-label="Open live arrivals for ' + esc(stopLabel(stopId)) + '">Streetcar arrivals</a>' +
          '<span class="kcsg-live-status" data-kcsg-live-status>Checking live times…</span>' +
        '</div>' : '';
      var liveClass = trackerUrl ? ' has-live-arrivals' : '';

      if (photo) {
        var alt = photo.alt || (stopLabel(stopId) + ' neighborhood');
        return '' +
          '<figure class="kcsg-stop-photo' + liveClass + '">' +
            '<img src="' + esc(photo.url) + '" alt="' + esc(alt) + '" loading="lazy" />' +
            '<figcaption>' + esc(stopLabel(stopId)) + '</figcaption>' +
            liveMarkup +
          '</figure>';
      }

      return '' +
        '<figure class="kcsg-stop-photo kcsg-stop-photo--placeholder' + liveClass + '">' +
          '<figcaption>' + esc(stopLabel(stopId)) + '</figcaption>' +
          liveMarkup +
        '</figure>';
    }

    function updateStopFeature() {
      guide.classList.remove('is-stop-with-photo');
      if (!stopFeature) return;

      if (state.mode === 'stop' && state.stop) {
        var markup = selectedStopPhotoMarkup(state.stop);
        if (markup) {
          guide.classList.add('is-stop-with-photo');
          stopFeature.hidden = false;
          stopFeature.innerHTML = markup;
          loadArrivals(state.stop);
          return;
        }
      }

      stopFeature.hidden = true;
      stopFeature.innerHTML = '';
    }

    function chooseStop(stopId) {
      if (!stopId) return;
      state.stop = stopId;
      state.category = 'all';
      state.mode = 'stop';
      render();
      if (resultsScroll) {
        resultsScroll.scrollTop = 0;
      }
    }

    function cardTemplate(amenity) {
      var category = firstCategory(amenity);
      var categoryColor = cssColor(category && category.color, '#008bd2');
      var categoryMarkup = category ? '<span class="kcsg-category-pill" style="--kcsg-category-color:' + esc(categoryColor) + ';">' + esc(category.name) + '</span>' : '';
      var urlMarkup = amenity.url ? '<a class="kcsg-link" href="' + esc(amenity.url) + '" target="_blank" rel="noopener noreferrer" aria-label="Open website for ' + esc(amenity.name) + '"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M14 3h7v7h-2V6.41l-9.29 9.3-1.42-1.42 9.3-9.29H14V3Z"></path><path d="M5 5h6v2H7v10h10v-4h2v6H5V5Z"></path></svg></a>' : '';
      var descriptionMarkup = amenity.description ? '<p class="kcsg-description">' + esc(amenity.description) + '</p>' : '';
      var stopLabelText = amenity.stopLabel || 'Not assigned';

      return '' +
        '<article class="kcsg-card" data-kcsg-card-stop="' + esc(amenity.stop || '') + '" style="--kcsg-category-color:' + esc(categoryColor) + ';">' +
          '<div class="kcsg-card-header">' +
            '<h4>' + esc(amenity.name) + '</h4>' +
            '<div class="kcsg-card-actions">' + categoryMarkup + urlMarkup + '</div>' +
          '</div>' +
          '<div class="kcsg-meta">' +
            '<span class="kcsg-stop-meta"><strong>Streetcar stop</strong><button type="button" class="kcsg-stop-name" data-kcsg-card-stop="' + esc(amenity.stop || '') + '">' + esc(stopLabelText) + '</button></span>' +
            '<span><strong>Walk from stop</strong>' + esc(amenity.walkFromStop || '—') + '</span>' +
            '<span><strong>Walk from hotel</strong>' + esc(amenity.walkFromHotel || '—') + '</span>' +
            '<span><strong>Drive from hotel</strong>' + esc(amenity.driveFromHotel || '—') + '</span>' +
          '</div>' +
          descriptionMarkup +
        '</article>';
    }

    function render() {
      var filtered = currentFilteredAmenities();
      setActiveButton(state.mode === 'category' ? state.category : 'all');
      setActiveStop(state.stop);
      setStopSelect(state.mode === 'stop' ? state.stop : '');
      updateStopMuting();
      updateStopFeature();

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

      if (!filtered.length) {
        results.innerHTML = '<div class="kcsg-empty">No amenities match this selection yet.</div>';
        return;
      }

      results.innerHTML = filtered.map(cardTemplate).join('');
      attachResultHoverEvents();
    }

    function attachResultHoverEvents() {
      Array.prototype.slice.call(results.querySelectorAll('.kcsg-card[data-kcsg-card-stop]')).forEach(function (node) {
        var stopId = node.getAttribute('data-kcsg-card-stop');
        if (!stopId) return;

        node.addEventListener('mouseenter', function () {
          setHoverStop(stopId, true);
        });

        node.addEventListener('mouseleave', function () {
          setHoverStop(stopId, false);
        });

        node.addEventListener('focusin', function () {
          setHoverStop(stopId, true);
        });

        node.addEventListener('focusout', function () {
          setHoverStop(stopId, false);
        });
      });

      Array.prototype.slice.call(results.querySelectorAll('.kcsg-stop-name[data-kcsg-card-stop]')).forEach(function (button) {
        var stopId = button.getAttribute('data-kcsg-card-stop');
        if (!stopId) return;

        button.addEventListener('click', function () {
          chooseStop(stopId);
        });

        button.addEventListener('mouseenter', function () {
          setHoverStop(stopId, true);
        });

        button.addEventListener('mouseleave', function () {
          setHoverStop(stopId, false);
        });
      });
    }

    buildControlBar();
    buildStopHitAreas();

    buttons.forEach(function (button) {
      button.addEventListener('click', function () {
        var category = button.getAttribute('data-kcsg-category') || 'all';
        state.category = category;
        state.stop = null;
        state.mode = category === 'all' ? 'all' : 'category';
        render();
      });
    });

    if (stopSelect) {
      stopSelect.addEventListener('change', function () {
        var stopId = stopSelect.value;
        if (stopId) {
          chooseStop(stopId);
          return;
        }
        state.category = 'all';
        state.stop = null;
        state.mode = 'all';
        render();
      });
    }

    stopGroups.forEach(function (group) {
      group.setAttribute('role', 'button');
      group.setAttribute('tabindex', '0');
      group.setAttribute('aria-label', 'Show amenities near ' + ((data.stops && data.stops[group.id]) || group.id));

      group.addEventListener('click', function () {
        chooseStop(group.id);
      });

      group.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          group.click();
        }
      });
    });

    render();
  }

  ready(function () {
    Array.prototype.slice.call(document.querySelectorAll('[data-kcsg-guide]')).forEach(initGuide);
  });
})();
