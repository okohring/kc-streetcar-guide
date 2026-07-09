(function () {
  var FIREBASE_BASE = 'https://kiosk-6e6b4.firebaseio.com';
  var ARRIVAL_CACHE_MS = 30000;

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
      stopCategory: 'all',
      stop: null,
      mode: 'all'
    };

    var arrivalsCache = {};
    var arrivalsRequestId = 0;
    var arrivalRefreshTimer = null;

    var buttons = Array.prototype.slice.call(guide.querySelectorAll('[data-kcsg-category]'));
    var resetRow = guide.querySelector('.kcsg-reset-row');
    var categoryKey = guide.querySelector('.kcsg-category-key');
    var stopSelect = null;
    var stopCategoryKey = null;
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
      stopCategoryKey = guide.querySelector('[data-kcsg-stop-category-key]');
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

      stopCategoryKey = document.createElement('div');
      stopCategoryKey.className = 'kcsg-stop-category-key';
      stopCategoryKey.setAttribute('data-kcsg-stop-category-key', '');
      stopCategoryKey.hidden = true;
      controls.parentNode.insertBefore(stopCategoryKey, controls.nextSibling);
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

    function currentStopCategories(stopId) {
      var seen = {};
      (data.amenities || []).forEach(function (amenity) {
        if (amenity.stop !== stopId) return;
        (amenity.categories || []).forEach(function (category) {
          if (category.slug) {
            seen[category.slug] = true;
          }
        });
      });

      return (data.categories || []).filter(function (category) {
        return !!seen[category.slug];
      });
    }

    function currentFilteredAmenities() {
      var amenities = data.amenities || [];

      if (state.mode === 'stop' && state.stop) {
        var stopAmenities = amenities.filter(function (amenity) {
          return amenity.stop === state.stop;
        });

        if (state.stopCategory && state.stopCategory !== 'all') {
          return stopAmenities.filter(function (amenity) {
            return amenityMatchesCategory(amenity, state.stopCategory);
          });
        }

        return stopAmenities;
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

    function parseTrackerCodes(trackerUrl) {
      if (!trackerUrl) return [];

      var path = '';
      try {
        path = new URL(trackerUrl, window.location.href).pathname || '';
      } catch (error) {
        return [];
      }

      path = path.replace(/^\/+|\/+$/g, '').split('/')[0].toLowerCase();
      path = path.replace(/[^a-z0-9]/g, '');

      if (!path) return [];

      var codes = [];
      for (var i = 0; i < path.length; i += 3) {
        var code = path.slice(i, i + 3);
        if (code.length === 3) {
          codes.push(code);
        }
      }

      return codes;
    }

    function firebaseGet(path) {
      return fetch(FIREBASE_BASE + '/' + path.replace(/^\/+/, '') + '.json', {
        credentials: 'omit',
        cache: 'no-store'
      }).then(function (response) {
        if (!response.ok) {
          throw new Error('Firebase request failed');
        }
        return response.json();
      });
    }

    function friendlyDirection(raw) {
      var direction = String(raw || '').replace(/^To\s+/i, '').trim();
      if (/riverfront/i.test(direction)) {
        return 'Riverfront (Northbound)';
      }
      if (/umkc/i.test(direction)) {
        return 'UMKC (Southbound)';
      }
      return direction;
    }

    function normalizeArrival(prediction, stopDefinition) {
      if (!prediction || prediction.cancelled) return null;

      var rawCountdown = prediction.countdown ? String(prediction.countdown).trim() : '';
      var minutes = Number.isFinite(Number(prediction.min)) ? Number(prediction.min) : null;
      var seconds = Number.isFinite(Number(prediction.sec)) ? Number(prediction.sec) : null;
      var soon = /^due$/i.test(rawCountdown) || (minutes !== null && minutes <= 2) || (seconds !== null && seconds <= 120);
      var label = '';

      if (soon) {
        label = 'Arriving soon';
      } else if (rawCountdown && /min/i.test(rawCountdown)) {
        label = rawCountdown;
      } else if (minutes !== null) {
        label = minutes + ' min';
      } else if (rawCountdown) {
        label = rawCountdown;
      }

      if (!label) return null;

      return {
        label: label,
        minutes: minutes,
        soon: soon,
        direction: friendlyDirection(prediction.headsign || (stopDefinition && stopDefinition.direction) || ''),
        vehicleId: prediction.vehicleId || ''
      };
    }

    function fetchArrivalForCode(code) {
      return firebaseGet('stops/' + encodeURIComponent(code)).then(function (stopDefinition) {
        if (!stopDefinition || !stopDefinition.stop_id || typeof stopDefinition.direction_id === 'undefined') {
          return null;
        }

        return firebaseGet(
          'byStop/' + encodeURIComponent(stopDefinition.stop_id) + '/predictions/' + encodeURIComponent(stopDefinition.direction_id)
        ).then(function (predictions) {
          if (!Array.isArray(predictions)) return null;

          for (var i = 0; i < predictions.length; i += 1) {
            var arrival = normalizeArrival(predictions[i], stopDefinition);
            if (arrival) {
              return arrival;
            }
          }

          return null;
        });
      }).catch(function () {
        return null;
      });
    }

    function setLiveArrivalStatus(stopId, payload) {
      var liveNode = stopFeature ? stopFeature.querySelector('[data-kcsg-live-arrivals]') : null;
      if (!liveNode || liveNode.getAttribute('data-kcsg-live-stop') !== stopId) return;

      var statusNode = liveNode.querySelector('[data-kcsg-live-status]');
      if (!statusNode) return;

      if (!payload || !payload.ok || !payload.arrivals || !payload.arrivals.length) {
        statusNode.innerHTML = '';
        statusNode.hidden = true;
        liveNode.classList.remove('has-arrivals');
        liveNode.classList.add('has-fallback');
        return;
      }

      statusNode.innerHTML = payload.arrivals.map(function (arrival) {
        return '' +
          '<span class="kcsg-live-row">' +
            '<span class="kcsg-live-direction">' + esc(arrival.direction || 'Streetcar') + ':</span>' +
            '<span class="kcsg-live-time">' + esc(arrival.label || 'Live arrivals') + '</span>' +
          '</span>';
      }).join('');
      statusNode.hidden = false;
      liveNode.classList.add('has-arrivals');
      liveNode.classList.remove('has-fallback');
    }

    function loadArrivals(stopId, force) {
      var liveNode = stopFeature ? stopFeature.querySelector('[data-kcsg-live-arrivals]') : null;
      var trackerUrl = trackerForStop(stopId);
      var codes = parseTrackerCodes(trackerUrl);
      var cached = arrivalsCache[stopId];
      var now = Date.now();

      if (!liveNode || !trackerUrl || !codes.length) return;

      if (!force && cached && cached.expires > now) {
        setLiveArrivalStatus(stopId, cached.payload);
        return;
      }

      var requestId = ++arrivalsRequestId;
      var statusNode = liveNode.querySelector('[data-kcsg-live-status]');
      if (statusNode && !cached) {
        statusNode.textContent = 'Checking live times…';
        statusNode.hidden = false;
      }

      Promise.all(codes.map(fetchArrivalForCode)).then(function (arrivalResults) {
        if (requestId !== arrivalsRequestId) return;

        var seenDirections = {};
        var arrivals = arrivalResults.filter(function (arrival) {
          if (!arrival || !arrival.direction) return false;
          if (seenDirections[arrival.direction]) return false;
          seenDirections[arrival.direction] = true;
          return true;
        });

        var payload = {
          ok: arrivals.length > 0,
          stop: stopId,
          stopLabel: stopLabel(stopId),
          trackerUrl: trackerUrl,
          arrivals: arrivals,
          updatedAt: new Date().toISOString()
        };

        arrivalsCache[stopId] = {
          expires: Date.now() + ARRIVAL_CACHE_MS,
          payload: payload
        };

        setLiveArrivalStatus(stopId, payload);
      }).catch(function () {
        if (requestId !== arrivalsRequestId) return;

        var fallback = {
          ok: false,
          stop: stopId,
          stopLabel: stopLabel(stopId),
          trackerUrl: trackerUrl,
          arrivals: [],
          updatedAt: new Date().toISOString()
        };

        arrivalsCache[stopId] = {
          expires: Date.now() + ARRIVAL_CACHE_MS,
          payload: fallback
        };

        setLiveArrivalStatus(stopId, fallback);
      });
    }

    function setArrivalRefresh(stopId) {
      if (arrivalRefreshTimer) {
        window.clearInterval(arrivalRefreshTimer);
        arrivalRefreshTimer = null;
      }

      if (!stopId || !trackerForStop(stopId)) return;

      arrivalRefreshTimer = window.setInterval(function () {
        if (state.mode === 'stop' && state.stop === stopId) {
          loadArrivals(stopId, true);
        }
      }, ARRIVAL_CACHE_MS);
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
      setArrivalRefresh(null);
      if (!stopFeature) return;

      if (state.mode === 'stop' && state.stop) {
        var markup = selectedStopPhotoMarkup(state.stop);
        if (markup) {
          guide.classList.add('is-stop-with-photo');
          stopFeature.hidden = false;
          stopFeature.innerHTML = markup;
          loadArrivals(state.stop, false);
          setArrivalRefresh(state.stop);
          return;
        }
      }

      stopFeature.hidden = true;
      stopFeature.innerHTML = '';
    }

    function renderStopCategoryKey() {
      if (!stopCategoryKey) return;

      if (state.mode !== 'stop' || !state.stop) {
        stopCategoryKey.hidden = true;
        stopCategoryKey.innerHTML = '';
        return;
      }

      var categories = currentStopCategories(state.stop);
      if (!categories.length) {
        stopCategoryKey.hidden = true;
        stopCategoryKey.innerHTML = '';
        return;
      }

      var allActive = !state.stopCategory || state.stopCategory === 'all';
      var markup = '' +
        '<span class="kcsg-stop-category-label">Filter ' + esc(stopLabel(state.stop)) + '</span>' +
        '<div class="kcsg-stop-category-buttons">' +
          '<button type="button" class="kcsg-stop-category-button' + (allActive ? ' is-active' : '') + '" data-kcsg-stop-category="all">All</button>';

      categories.forEach(function (category) {
        var color = cssColor(category.color, '#008bd2');
        var active = state.stopCategory === category.slug;
        markup += '<button type="button" class="kcsg-stop-category-button' + (active ? ' is-active' : '') + '" data-kcsg-stop-category="' + esc(category.slug) + '" style="--kcsg-category-color:' + esc(color) + ';">' + esc(category.name) + '</button>';
      });

      markup += '</div>';
      stopCategoryKey.innerHTML = markup;
      stopCategoryKey.hidden = false;
      attachStopCategoryEvents();
    }

    function attachStopCategoryEvents() {
      if (!stopCategoryKey) return;

      Array.prototype.slice.call(stopCategoryKey.querySelectorAll('[data-kcsg-stop-category]')).forEach(function (button) {
        button.addEventListener('click', function () {
          state.stopCategory = button.getAttribute('data-kcsg-stop-category') || 'all';
          state.category = 'all';
          state.mode = 'stop';
          render();
        });
      });
    }

    function resetResultsScroll() {
      if (!resultsScroll) return;

      var apply = function () {
        var target = null;

        if (state.mode === 'category' && state.category !== 'all') {
          target = results ? results.querySelector('.kcsg-section-heading') : null;
        }

        if (!target) {
          target = results ? results.querySelector('.kcsg-card') : null;
        }

        var targetTop = 0;
        if (target) {
          targetTop = Math.max(0, target.offsetTop - resultsScroll.offsetTop);
        }

        resultsScroll.scrollTop = targetTop;
        resultsScroll.scrollLeft = 0;
      };

      apply();
      window.requestAnimationFrame(apply);
      window.setTimeout(apply, 60);
      window.setTimeout(apply, 250);
    }

    function chooseStop(stopId) {
      if (!stopId) return;
      state.stop = stopId;
      state.category = 'all';
      state.stopCategory = 'all';
      state.mode = 'stop';
      render();
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

    function categoryHeaderMarkup() {
      if (state.mode !== 'category' || !state.category || state.category === 'all') {
        return '';
      }

      return '' +
        '<div class="kcsg-section-heading">' +
          '<h3>' + esc(getCategoryLabel(state.category)) + '</h3>' +
        '</div>';
    }

    function render() {
      var filtered = currentFilteredAmenities();
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
        state.stopCategory = 'all';
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
        state.stopCategory = 'all';
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
