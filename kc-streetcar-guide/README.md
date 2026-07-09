# KC Streetcar Guide

Interactive WordPress visitor guide for amenities near the KC Streetcar line.

## Install

1. Upload `kc-streetcar-guide.zip` in WordPress under Plugins → Add New → Upload Plugin.
2. Activate the plugin.
3. Go to Streetcar Guide → Amenities.
4. Add amenities and assign each one a category and streetcar stop.
5. Add this shortcode to a page:

```text
[kc_streetcar_guide]
```

Optional shortcode attributes:

```text
[kc_streetcar_guide title="Explore Kansas City" intro="Choose a category or click a streetcar stop."]
```

## Admin fields

- Name: WordPress post title
- Streetcar Stop: dropdown in Amenity Details
- Category: dropdown in Amenity Details
- Walk from Stop
- Walk from Hotel
- Drive from Hotel
- Description
- URL

## Front-end behavior

- Click a category to show all amenities in that category.
- Click a streetcar stop to show all amenities assigned to that stop.
- Click Reset or All to show everything again.

## Version 0.2.0 notes

- Moved Category into the Amenity Details box beside Streetcar Stop.
- Removed the default Categories sidebar box for a cleaner admin screen.
- Removed the front-end background, panel borders, and heavy spacing so the guide sits transparently inside a page.
- Removed stop-title/dot opacity lowering when a category is selected.
- Added one editable starter amenity per streetcar stop using the built-in categories.


## Version 0.3.0 notes

- Capped the streetcar SVG at 500px tall and scaled the whole map down, including stop dots and labels.
- Tightened the layout so cards stay compact and fit inside the available page width without horizontal scrolling.
- Added stronger transparent/no-border overrides for the plugin and common WordPress/visual-builder shortcode wrappers.
- Removed the mobile map scrolling container so the route stays fully visible instead of creating an internal scroll area.

## Version 0.5.0 notes

- Changed the streetcar SVG max height to 800px.
- Added admin-assignable category colors under Streetcar Guide → Categories.
- Category colors now apply to the front-end key, amenity card accents, and amenity category pills.
- Replaced the text website link with a compact square-arrow web link icon.
- Moved the Reset button below the visitor guide header.
- Amenity cards now highlight their matching streetcar stop on hover/focus.
- Hovering or focusing the streetcar stop name inside an amenity card also keeps the matching stop highlighted through the card focus state.
- Added stronger border/background reset rules for common WordPress and visual builder wrappers.


## 0.5.0
- Tightened guide spacing.
- Increased SVG stop label readability without increasing route height.


## Version 0.5.1 notes

- Tightened the header/control area again with smaller row gaps and more compact buttons.
- Added a 10px label offset from stop dots while preserving the larger outlined SVG label treatment.

## Version 0.5.2 notes

- Increased the small Crossroads landmark labels for The Abbott and Hotel Indigo while keeping them smaller than streetcar stop labels.

## Version 0.6.2 notes

- Reverted the streetcar SVG asset to the provided `kc_streetcar_line(1).svg` version.
- Added Streetcar Guide → Stop Photos, where admins can upload an optional neighborhood photo for each streetcar stop.
- When a stop is selected, its neighborhood photo appears above the amenity cards when a photo has been assigned.
- Clicking the streetcar stop name inside an amenity card now filters the guide to all amenities at that stop.
- Moved amenities into a scrollable results area so visitors can browse cards while keeping the streetcar map visible on desktop.


## 0.6.2
- Restored the latest Illustrator-exported streetcar SVG as the active map asset.
- Hardened SVG loading so the map keeps rendering even when the SVG has existing attributes.


## Version 0.6.3 notes

- Updated selected-stop photo display so the stop name overlays the image in the bottom-left corner instead of appearing as a pill.
- Added a 2px white stroke/text outline treatment to the stop name over the photo for legibility.
- Hid the duplicate results heading when a selected stop photo is displayed, so the image title becomes the visible stop header.


## Version 0.6.4 notes

- Lightened the stop photo overlay title weight.
- Reduced the stop photo overlay text stroke to 1px.
- Added an eased image zoom on hover/focus for selected stop photos.

## Version 0.6.5 notes

- Added invisible boxed hit areas around each streetcar stop, so hovering and clicking no longer require landing directly on the small dot or outlined text.
- Stop hover/click styling still highlights the dot and label, but the active target is now a friendlier rectangle around the full stop label area.


## Version 0.6.6 notes

- Replaced the stop photo title stroke treatment with a white bottom gradient overlay.
- Removed the text stroke/shadow from the stop photo title for a softer photo-card look.

## Version 0.7.1 notes

- Added default KC Streetcar live tracker URLs for every streetcar stop.
- Expanded Streetcar Guide → Stop Photos into Stop Photos & Trackers so admins can edit each stop-specific tracker URL.
- Added a WordPress REST proxy endpoint for stop arrivals with short caching.
- Selected stop photos now show a compact streetcar arrivals line and an external tracker icon in the photo overlay area.
- If the tracker page cannot be parsed directly because it is client-side rendered, the display gracefully falls back to the live tracker link instead of breaking the guide.


## 0.7.1
- Linked the Streetcar arrivals label directly to the live tracker when live countdown data is unavailable.
- Kept the arrivals/tracker header visible for selected stops even when no stop photo has been uploaded.

## Version 0.7.2 notes

- Added a GitHub release workflow for building `kc-streetcar-guide.zip` from the repository.
- Added a lightweight WordPress updater that checks the latest GitHub release and offers plugin updates inside WordPress.
- To publish an update: bump the plugin version in `kc-streetcar-guide.php`, commit to `main`, then run the GitHub Actions release workflow with the same version number.

## GitHub release workflow

This repository includes `.github/workflows/release.yml`.

To publish a new WordPress-updateable release:

1. Update the plugin header `Version:` in `kc-streetcar-guide.php`.
2. Update `KCSG_Plugin::VERSION` in the same file.
3. Commit and push to `main`.
4. Go to GitHub → Actions → Build and Release Plugin.
5. Run the workflow and enter the same version number, for example `0.7.2`.
6. GitHub will build `kc-streetcar-guide.zip`. The updater manifest points WordPress to the current hosted ZIP.
7. WordPress will detect the new release from Plugins → Updates.

For public repositories, no token is needed in WordPress. If this repository becomes private later, the updater will need a GitHub token setting added before WordPress can download private ZIPs.

## Manifest-based updates

WordPress checks `update.json` for the latest version and downloads `dist/kc-streetcar-guide.zip` when a newer version is available.
