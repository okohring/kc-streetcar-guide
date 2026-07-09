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
