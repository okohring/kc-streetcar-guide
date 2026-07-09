<?php
/**
 * Plugin Name: KC Streetcar Guide
 * Description: Interactive streetcar-line visitor guide with admin-manageable amenities, categories, stops, travel times, descriptions, and links.
 * Version: 0.7.2
 * Author: Olivia Kohring
 * Text Domain: kc-streetcar-guide
 */

if (!defined('ABSPATH')) {
    exit;
}

final class KCSG_Plugin {
    const VERSION = '0.7.2';
    const CPT = 'kcsg_amenity';
    const TAX = 'kcsg_category';
    const NONCE = 'kcsg_amenity_nonce';
    const STOP_PHOTO_OPTION = 'kcsg_stop_photos';
    const STOP_TRACKER_OPTION = 'kcsg_stop_trackers';
    const STOP_PHOTO_NONCE = 'kcsg_stop_photo_nonce';
    const ARRIVAL_CACHE_TTL = 45;

    private static $instance = null;

    public static function instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action('init', array($this, 'register_content_types'));
        add_action('add_meta_boxes', array($this, 'add_meta_boxes'));
        add_action('save_post_' . self::CPT, array($this, 'save_amenity_meta'));
        add_action('admin_enqueue_scripts', array($this, 'admin_styles'));
        add_action('admin_menu', array($this, 'add_stop_photos_page'));
        add_action('admin_post_kcsg_save_stop_photos', array($this, 'save_stop_photos'));
        add_action('rest_api_init', array($this, 'register_rest_routes'));
        add_action(self::TAX . '_add_form_fields', array($this, 'render_category_color_add_field'));
        add_action(self::TAX . '_edit_form_fields', array($this, 'render_category_color_edit_field'));
        add_action('created_' . self::TAX, array($this, 'save_category_color'));
        add_action('edited_' . self::TAX, array($this, 'save_category_color'));
        add_filter('manage_edit-' . self::TAX . '_columns', array($this, 'category_columns'));
        add_filter('manage_' . self::TAX . '_custom_column', array($this, 'category_column_content'), 10, 3);
        add_filter('manage_' . self::CPT . '_posts_columns', array($this, 'amenity_columns'));
        add_action('manage_' . self::CPT . '_posts_custom_column', array($this, 'amenity_column_content'), 10, 2);
        add_action('admin_init', array($this, 'maybe_seed_sample_amenities'));
        add_shortcode('kc_streetcar_guide', array($this, 'render_shortcode'));
    }

    public static function default_categories() {
        return array('Coffee', 'Food', 'Drinks', 'Culture', 'Shopping', 'Walks');
    }

    public static function default_category_colors() {
        return array(
            'coffee' => '#8a5a44',
            'food' => '#d36b2c',
            'drinks' => '#7b61ff',
            'culture' => '#008bd2',
            'shopping' => '#2f9e6d',
            'walks' => '#6c8f2f',
        );
    }

    public static function sanitize_hex_color_fallback($color, $fallback = '#008bd2') {
        $color = sanitize_hex_color($color);
        return $color ? $color : $fallback;
    }

    public static function category_color($term) {
        $colors = self::default_category_colors();
        $fallback = isset($colors[$term->slug]) ? $colors[$term->slug] : '#008bd2';
        $color = get_term_meta($term->term_id, '_kcsg_category_color', true);

        return self::sanitize_hex_color_fallback($color, $fallback);
    }

    public static function stops() {
        return array(
            'stop-riverfront' => 'Riverfront',
            'stop-river-market' => 'River Market',
            'stop-delaware' => 'Delaware',
            'stop-city-market' => 'City Market',
            'stop-north-loop' => 'North Loop',
            'stop-library' => 'Library',
            'stop-metro-center' => 'Metro Center',
            'stop-power--light' => 'Power & Light',
            'stop-kauffman-center' => 'Kauffman Center',
            'stop-crossroads' => 'Crossroads',
            'stop-union-station' => 'Union Station',
            'stop-wwi-museum--memorial' => 'WWI Museum & Memorial',
            'stop-union-hill' => 'Union Hill',
            'stop-armour' => 'Armour',
            'stop-westport' => 'Westport',
            'stop-southmoreland' => 'Southmoreland',
            'stop-art-museums' => 'Art Museums',
            'stop-plaza' => 'Plaza',
            'stop-umkc' => 'UMKC',
        );
    }

    public static function default_stop_tracker_urls() {
        return array(
            'stop-riverfront' => 'https://arrivals.kcstreetcar.org/rft',
            'stop-river-market' => 'https://arrivals.kcstreetcar.org/rmrrmn',
            'stop-delaware' => 'https://arrivals.kcstreetcar.org/rmw',
            'stop-city-market' => 'https://arrivals.kcstreetcar.org/cmk',
            'stop-north-loop' => 'https://arrivals.kcstreetcar.org/nlnnls',
            'stop-library' => 'https://arrivals.kcstreetcar.org/lbnlbs',
            'stop-metro-center' => 'https://arrivals.kcstreetcar.org/mcnmcs',
            'stop-power--light' => 'https://arrivals.kcstreetcar.org/plnpls',
            'stop-kauffman-center' => 'https://arrivals.kcstreetcar.org/kcnkcs',
            'stop-crossroads' => 'https://arrivals.kcstreetcar.org/crncrs',
            'stop-union-station' => 'https://arrivals.kcstreetcar.org/usnuss',
            'stop-wwi-museum--memorial' => 'https://arrivals.kcstreetcar.org/wwnwws',
            'stop-union-hill' => 'https://arrivals.kcstreetcar.org/uhnuhs',
            'stop-armour' => 'https://arrivals.kcstreetcar.org/arnars',
            'stop-westport' => 'https://arrivals.kcstreetcar.org/wpnwps',
            'stop-southmoreland' => 'https://arrivals.kcstreetcar.org/smnsms',
            'stop-art-museums' => 'https://arrivals.kcstreetcar.org/amnams',
            'stop-plaza' => 'https://arrivals.kcstreetcar.org/pznpzs',
            'stop-umkc' => 'https://arrivals.kcstreetcar.org/umn',
        );
    }

    public static function sanitize_tracker_url($url) {
        $url = esc_url_raw(trim((string) $url));
        if (!$url) {
            return '';
        }

        $parts = wp_parse_url($url);
        if (empty($parts['scheme']) || empty($parts['host'])) {
            return '';
        }

        if (strtolower($parts['scheme']) !== 'https') {
            return '';
        }

        if (strtolower($parts['host']) !== 'arrivals.kcstreetcar.org') {
            return '';
        }

        return $url;
    }

    public function register_content_types() {
        register_post_type(self::CPT, array(
            'labels' => array(
                'name' => __('Amenities', 'kc-streetcar-guide'),
                'singular_name' => __('Amenity', 'kc-streetcar-guide'),
                'add_new_item' => __('Add New Amenity', 'kc-streetcar-guide'),
                'edit_item' => __('Edit Amenity', 'kc-streetcar-guide'),
                'new_item' => __('New Amenity', 'kc-streetcar-guide'),
                'view_item' => __('View Amenity', 'kc-streetcar-guide'),
                'search_items' => __('Search Amenities', 'kc-streetcar-guide'),
                'not_found' => __('No amenities found', 'kc-streetcar-guide'),
                'menu_name' => __('Streetcar Guide', 'kc-streetcar-guide'),
            ),
            'public' => false,
            'show_ui' => true,
            'show_in_menu' => true,
            'menu_icon' => 'dashicons-location-alt',
            'supports' => array('title'),
            'has_archive' => false,
            'rewrite' => false,
            'show_in_rest' => true,
        ));

        register_taxonomy(self::TAX, self::CPT, array(
            'labels' => array(
                'name' => __('Categories', 'kc-streetcar-guide'),
                'singular_name' => __('Category', 'kc-streetcar-guide'),
                'search_items' => __('Search Categories', 'kc-streetcar-guide'),
                'all_items' => __('All Categories', 'kc-streetcar-guide'),
                'edit_item' => __('Edit Category', 'kc-streetcar-guide'),
                'update_item' => __('Update Category', 'kc-streetcar-guide'),
                'add_new_item' => __('Add New Category', 'kc-streetcar-guide'),
                'new_item_name' => __('New Category Name', 'kc-streetcar-guide'),
                'menu_name' => __('Categories', 'kc-streetcar-guide'),
            ),
            'hierarchical' => false,
            'show_ui' => true,
            'show_admin_column' => true,
            'show_in_rest' => true,
            'rewrite' => false,
        ));
    }

    public static function activate() {
        self::instance()->register_content_types();

        foreach (self::default_categories() as $term_name) {
            if (!term_exists($term_name, self::TAX)) {
                wp_insert_term($term_name, self::TAX);
            }
        }

        self::seed_default_category_colors();
        self::seed_default_stop_trackers();
        self::seed_sample_amenities();

        flush_rewrite_rules();
    }

    public static function deactivate() {
        flush_rewrite_rules();
    }

    public function add_meta_boxes() {
        add_meta_box(
            'kcsg_amenity_details',
            __('Amenity Details', 'kc-streetcar-guide'),
            array($this, 'render_meta_box'),
            self::CPT,
            'normal',
            'high'
        );

        remove_meta_box('tagsdiv-' . self::TAX, self::CPT, 'side');
        remove_meta_box(self::TAX . 'div', self::CPT, 'side');
    }

    public function render_meta_box($post) {
        wp_nonce_field(self::NONCE, self::NONCE);

        $stop = get_post_meta($post->ID, '_kcsg_stop', true);
        $walk_from_stop = get_post_meta($post->ID, '_kcsg_walk_from_stop', true);
        $walk_from_hotel = get_post_meta($post->ID, '_kcsg_walk_from_hotel', true);
        $drive_from_hotel = get_post_meta($post->ID, '_kcsg_drive_from_hotel', true);
        $description = get_post_meta($post->ID, '_kcsg_description', true);
        $url = get_post_meta($post->ID, '_kcsg_url', true);
        $current_terms = get_the_terms($post->ID, self::TAX);
        $current_category = (!is_wp_error($current_terms) && !empty($current_terms)) ? $current_terms[0]->slug : '';
        $category_terms = get_terms(array(
            'taxonomy' => self::TAX,
            'hide_empty' => false,
            'orderby' => 'name',
            'order' => 'ASC',
        ));
        ?>
        <div class="kcsg-admin-grid">
            <p class="kcsg-admin-field kcsg-admin-field-stop">
                <label for="kcsg_stop"><strong><?php esc_html_e('Streetcar Stop', 'kc-streetcar-guide'); ?></strong></label>
                <select name="kcsg_stop" id="kcsg_stop">
                    <option value=""><?php esc_html_e('Select a stop', 'kc-streetcar-guide'); ?></option>
                    <?php foreach (self::stops() as $stop_id => $stop_label) : ?>
                        <option value="<?php echo esc_attr($stop_id); ?>" <?php selected($stop, $stop_id); ?>><?php echo esc_html($stop_label); ?></option>
                    <?php endforeach; ?>
                </select>
            </p>

            <p class="kcsg-admin-field kcsg-admin-field-category">
                <label for="kcsg_category"><strong><?php esc_html_e('Category', 'kc-streetcar-guide'); ?></strong></label>
                <select name="kcsg_category" id="kcsg_category">
                    <option value=""><?php esc_html_e('Select a category', 'kc-streetcar-guide'); ?></option>
                    <?php if (!is_wp_error($category_terms)) : ?>
                        <?php foreach ($category_terms as $category_term) : ?>
                            <option value="<?php echo esc_attr($category_term->slug); ?>" <?php selected($current_category, $category_term->slug); ?>><?php echo esc_html($category_term->name); ?></option>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </select>
            </p>

            <p class="kcsg-admin-field">
                <label for="kcsg_walk_from_stop"><strong><?php esc_html_e('Walk from Stop', 'kc-streetcar-guide'); ?></strong></label>
                <input type="text" name="kcsg_walk_from_stop" id="kcsg_walk_from_stop" value="<?php echo esc_attr($walk_from_stop); ?>" placeholder="4 min" />
            </p>

            <p class="kcsg-admin-field">
                <label for="kcsg_walk_from_hotel"><strong><?php esc_html_e('Walk from Hotel', 'kc-streetcar-guide'); ?></strong></label>
                <input type="text" name="kcsg_walk_from_hotel" id="kcsg_walk_from_hotel" value="<?php echo esc_attr($walk_from_hotel); ?>" placeholder="12 min" />
            </p>

            <p class="kcsg-admin-field">
                <label for="kcsg_drive_from_hotel"><strong><?php esc_html_e('Drive from Hotel', 'kc-streetcar-guide'); ?></strong></label>
                <input type="text" name="kcsg_drive_from_hotel" id="kcsg_drive_from_hotel" value="<?php echo esc_attr($drive_from_hotel); ?>" placeholder="5 min" />
            </p>

            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_description"><strong><?php esc_html_e('Description', 'kc-streetcar-guide'); ?></strong></label>
                <textarea name="kcsg_description" id="kcsg_description" rows="4" placeholder="Good for a quick coffee, client meeting, or visitor-friendly KC stop."><?php echo esc_textarea($description); ?></textarea>
            </p>

            <p class="kcsg-admin-field kcsg-admin-field-full">
                <label for="kcsg_url"><strong><?php esc_html_e('URL', 'kc-streetcar-guide'); ?></strong></label>
                <input type="url" name="kcsg_url" id="kcsg_url" value="<?php echo esc_url($url); ?>" placeholder="https://example.com" />
            </p>
        </div>
        <p class="description">
            <?php esc_html_e('Use the Category field above to assign Coffee, Food, Drinks, Culture, Shopping, Walks, etc. Add or edit available categories under Streetcar Guide → Categories.', 'kc-streetcar-guide'); ?>
        </p>
        <?php
    }

    public function save_amenity_meta($post_id) {
        if (!isset($_POST[self::NONCE]) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST[self::NONCE])), self::NONCE)) {
            return;
        }

        if (defined('DOING_AUTOSAVE') && DOING_AUTOSAVE) {
            return;
        }

        if (!current_user_can('edit_post', $post_id)) {
            return;
        }

        $allowed_stops = array_keys(self::stops());
        $stop = isset($_POST['kcsg_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_stop'])) : '';
        if (!in_array($stop, $allowed_stops, true)) {
            $stop = '';
        }

        $fields = array(
            '_kcsg_stop' => $stop,
            '_kcsg_walk_from_stop' => isset($_POST['kcsg_walk_from_stop']) ? sanitize_text_field(wp_unslash($_POST['kcsg_walk_from_stop'])) : '',
            '_kcsg_walk_from_hotel' => isset($_POST['kcsg_walk_from_hotel']) ? sanitize_text_field(wp_unslash($_POST['kcsg_walk_from_hotel'])) : '',
            '_kcsg_drive_from_hotel' => isset($_POST['kcsg_drive_from_hotel']) ? sanitize_text_field(wp_unslash($_POST['kcsg_drive_from_hotel'])) : '',
            '_kcsg_description' => isset($_POST['kcsg_description']) ? sanitize_textarea_field(wp_unslash($_POST['kcsg_description'])) : '',
            '_kcsg_url' => isset($_POST['kcsg_url']) ? esc_url_raw(wp_unslash($_POST['kcsg_url'])) : '',
        );

        foreach ($fields as $key => $value) {
            if ($value === '') {
                delete_post_meta($post_id, $key);
            } else {
                update_post_meta($post_id, $key, $value);
            }
        }

        $category_slug = isset($_POST['kcsg_category']) ? sanitize_title(wp_unslash($_POST['kcsg_category'])) : '';
        if ($category_slug) {
            $term = get_term_by('slug', $category_slug, self::TAX);
            if ($term && !is_wp_error($term)) {
                wp_set_object_terms($post_id, array((int) $term->term_id), self::TAX, false);
            }
        } else {
            wp_set_object_terms($post_id, array(), self::TAX, false);
        }
    }


    public static function seed_default_stop_trackers() {
        $defaults = self::default_stop_tracker_urls();
        $existing = get_option(self::STOP_TRACKER_OPTION, array());
        $existing = is_array($existing) ? $existing : array();
        $changed = false;

        foreach ($defaults as $stop_id => $url) {
            if (empty($existing[$stop_id])) {
                $existing[$stop_id] = $url;
                $changed = true;
            }
        }

        if ($changed || !get_option(self::STOP_TRACKER_OPTION, false)) {
            update_option(self::STOP_TRACKER_OPTION, $existing, false);
        }
    }

    public static function seed_default_category_colors() {
        $colors = self::default_category_colors();

        foreach ($colors as $slug => $color) {
            $term = get_term_by('slug', $slug, self::TAX);
            if ($term && !is_wp_error($term) && !get_term_meta($term->term_id, '_kcsg_category_color', true)) {
                update_term_meta($term->term_id, '_kcsg_category_color', self::sanitize_hex_color_fallback($color));
            }
        }
    }

    public function render_category_color_add_field() {
        ?>
        <div class="form-field term-kcsg-color-wrap">
            <label for="kcsg_category_color"><?php esc_html_e('Category Color', 'kc-streetcar-guide'); ?></label>
            <input type="color" name="kcsg_category_color" id="kcsg_category_color" value="#008bd2" />
            <p><?php esc_html_e('Used for the front-end category key, amenity pills, and card accents.', 'kc-streetcar-guide'); ?></p>
        </div>
        <?php
    }

    public function render_category_color_edit_field($term) {
        $color = self::category_color($term);
        ?>
        <tr class="form-field term-kcsg-color-wrap">
            <th scope="row"><label for="kcsg_category_color"><?php esc_html_e('Category Color', 'kc-streetcar-guide'); ?></label></th>
            <td>
                <input type="color" name="kcsg_category_color" id="kcsg_category_color" value="<?php echo esc_attr($color); ?>" />
                <p class="description"><?php esc_html_e('Used for the front-end category key, amenity pills, and card accents.', 'kc-streetcar-guide'); ?></p>
            </td>
        </tr>
        <?php
    }

    public function save_category_color($term_id) {
        if (!isset($_POST['kcsg_category_color'])) {
            return;
        }

        $color = self::sanitize_hex_color_fallback(wp_unslash($_POST['kcsg_category_color']));
        update_term_meta($term_id, '_kcsg_category_color', $color);
    }

    public function category_columns($columns) {
        $new_columns = array();

        foreach ($columns as $key => $label) {
            $new_columns[$key] = $label;
            if ($key === 'name') {
                $new_columns['kcsg_color'] = __('Color', 'kc-streetcar-guide');
            }
        }

        return $new_columns;
    }

    public function category_column_content($content, $column_name, $term_id) {
        if ($column_name !== 'kcsg_color') {
            return $content;
        }

        $term = get_term($term_id, self::TAX);
        $color = ($term && !is_wp_error($term)) ? self::category_color($term) : '#008bd2';

        return '<span style="display:inline-block;width:22px;height:22px;border-radius:999px;background:' . esc_attr($color) . ';border:1px solid #ccd0d4;vertical-align:middle;"></span> <code>' . esc_html($color) . '</code>';
    }

    public function add_stop_photos_page() {
        add_submenu_page(
            'edit.php?post_type=' . self::CPT,
            __('Streetcar Stop Photos & Trackers', 'kc-streetcar-guide'),
            __('Stop Photos', 'kc-streetcar-guide'),
            'manage_options',
            'kcsg-stop-photos',
            array($this, 'render_stop_photos_page')
        );
    }

    public static function get_stop_photo_ids() {
        $photo_ids = get_option(self::STOP_PHOTO_OPTION, array());
        return is_array($photo_ids) ? $photo_ids : array();
    }

    public static function get_stop_photo_data() {
        $photo_ids = self::get_stop_photo_ids();
        $photos = array();

        foreach (self::stops() as $stop_id => $stop_label) {
            $attachment_id = isset($photo_ids[$stop_id]) ? absint($photo_ids[$stop_id]) : 0;
            if (!$attachment_id) {
                continue;
            }

            $url = wp_get_attachment_image_url($attachment_id, 'large');
            if (!$url) {
                continue;
            }

            $photos[$stop_id] = array(
                'id' => $attachment_id,
                'url' => esc_url_raw($url),
                'alt' => get_post_meta($attachment_id, '_wp_attachment_image_alt', true),
                'caption' => $stop_label,
            );
        }

        return $photos;
    }

    public static function get_stop_tracker_urls() {
        self::seed_default_stop_trackers();
        $defaults = self::default_stop_tracker_urls();
        $saved = get_option(self::STOP_TRACKER_OPTION, array());
        $saved = is_array($saved) ? $saved : array();
        $urls = array();

        foreach (self::stops() as $stop_id => $stop_label) {
            $url = isset($saved[$stop_id]) ? self::sanitize_tracker_url($saved[$stop_id]) : '';
            if (!$url && isset($defaults[$stop_id])) {
                $url = self::sanitize_tracker_url($defaults[$stop_id]);
            }
            if ($url) {
                $urls[$stop_id] = $url;
            }
        }

        return $urls;
    }

    public static function get_stop_tracker_data() {
        $urls = self::get_stop_tracker_urls();
        $data = array();

        foreach ($urls as $stop_id => $url) {
            $data[$stop_id] = array(
                'url' => $url,
            );
        }

        return $data;
    }

    public function render_stop_photos_page() {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('You do not have permission to edit stop photos.', 'kc-streetcar-guide'));
        }

        $photo_ids = self::get_stop_photo_ids();
        $tracker_urls = self::get_stop_tracker_urls();
        ?>
        <div class="wrap kcsg-stop-photos-page">
            <h1><?php esc_html_e('Streetcar Stop Photos & Trackers', 'kc-streetcar-guide'); ?></h1>
            <?php if (isset($_GET['updated']) && $_GET['updated'] === '1') : ?>
                <div class="notice notice-success is-dismissible"><p><?php esc_html_e('Stop photos and tracker URLs saved.', 'kc-streetcar-guide'); ?></p></div>
            <?php endif; ?>
            <p><?php esc_html_e('Upload an optional neighborhood photo for each stop and manage the stop-specific live tracker URL used on the front end.', 'kc-streetcar-guide'); ?></p>

            <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                <input type="hidden" name="action" value="kcsg_save_stop_photos" />
                <?php wp_nonce_field(self::STOP_PHOTO_NONCE, self::STOP_PHOTO_NONCE); ?>

                <div class="kcsg-stop-photo-grid">
                    <?php foreach (self::stops() as $stop_id => $stop_label) :
                        $attachment_id = isset($photo_ids[$stop_id]) ? absint($photo_ids[$stop_id]) : 0;
                        $image_url = $attachment_id ? wp_get_attachment_image_url($attachment_id, 'medium') : '';
                        ?>
                        <section class="kcsg-stop-photo-card" data-kcsg-stop-photo-card>
                            <h2><?php echo esc_html($stop_label); ?></h2>
                            <div class="kcsg-stop-photo-preview" data-kcsg-stop-photo-preview>
                                <?php if ($image_url) : ?>
                                    <img src="<?php echo esc_url($image_url); ?>" alt="" />
                                <?php else : ?>
                                    <span><?php esc_html_e('No photo selected', 'kc-streetcar-guide'); ?></span>
                                <?php endif; ?>
                            </div>
                            <input type="hidden" name="kcsg_stop_photos[<?php echo esc_attr($stop_id); ?>]" value="<?php echo esc_attr($attachment_id); ?>" data-kcsg-stop-photo-input />
                            <div class="kcsg-stop-photo-actions">
                                <button type="button" class="button" data-kcsg-select-stop-photo><?php esc_html_e('Choose Photo', 'kc-streetcar-guide'); ?></button>
                                <button type="button" class="button" data-kcsg-remove-stop-photo><?php esc_html_e('Remove', 'kc-streetcar-guide'); ?></button>
                            </div>
                            <label class="kcsg-stop-tracker-field">
                                <span><?php esc_html_e('Live tracker URL', 'kc-streetcar-guide'); ?></span>
                                <input type="url" name="kcsg_stop_trackers[<?php echo esc_attr($stop_id); ?>]" value="<?php echo esc_url(isset($tracker_urls[$stop_id]) ? $tracker_urls[$stop_id] : ''); ?>" placeholder="https://arrivals.kcstreetcar.org/..." />
                            </label>
                        </section>
                    <?php endforeach; ?>
                </div>

                <?php submit_button(__('Save Stop Photos', 'kc-streetcar-guide')); ?>
            </form>
        </div>
        <?php
    }

    public function save_stop_photos() {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('You do not have permission to edit stop photos.', 'kc-streetcar-guide'));
        }

        if (!isset($_POST[self::STOP_PHOTO_NONCE]) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST[self::STOP_PHOTO_NONCE])), self::STOP_PHOTO_NONCE)) {
            wp_die(esc_html__('Security check failed.', 'kc-streetcar-guide'));
        }

        $allowed_stops = array_keys(self::stops());
        $incoming = isset($_POST['kcsg_stop_photos']) && is_array($_POST['kcsg_stop_photos']) ? wp_unslash($_POST['kcsg_stop_photos']) : array();
        $incoming_trackers = isset($_POST['kcsg_stop_trackers']) && is_array($_POST['kcsg_stop_trackers']) ? wp_unslash($_POST['kcsg_stop_trackers']) : array();
        $saved = array();
        $saved_trackers = array();

        foreach ($allowed_stops as $stop_id) {
            $attachment_id = isset($incoming[$stop_id]) ? absint($incoming[$stop_id]) : 0;
            if ($attachment_id) {
                $saved[$stop_id] = $attachment_id;
            }

            $tracker_url = isset($incoming_trackers[$stop_id]) ? self::sanitize_tracker_url($incoming_trackers[$stop_id]) : '';
            if ($tracker_url) {
                $saved_trackers[$stop_id] = $tracker_url;
            }
        }

        update_option(self::STOP_PHOTO_OPTION, $saved, false);
        update_option(self::STOP_TRACKER_OPTION, $saved_trackers, false);
        wp_safe_redirect(add_query_arg(array(
            'post_type' => self::CPT,
            'page' => 'kcsg-stop-photos',
            'updated' => '1',
        ), admin_url('edit.php')));
        exit;
    }

    public function admin_styles($hook) {
        global $post_type;

        $is_amenity_screen = ($post_type === self::CPT);
        $is_stop_photo_page = isset($_GET['page']) && sanitize_key(wp_unslash($_GET['page'])) === 'kcsg-stop-photos';

        if (!$is_amenity_screen && !$is_stop_photo_page) {
            return;
        }

        if ($is_stop_photo_page) {
            wp_enqueue_media();
        }

        wp_add_inline_style('wp-admin', '
            .kcsg-admin-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 18px; }
            .kcsg-admin-field { margin: 0; }
            .kcsg-admin-field-stop { grid-column: span 2; }
            .kcsg-admin-field-category { grid-column: span 1; }
            .kcsg-admin-field-full { grid-column: 1 / -1; }
            .kcsg-admin-field label { display: block; margin-bottom: 6px; }
            .kcsg-admin-field input, .kcsg-admin-field select, .kcsg-admin-field textarea { width: 100%; max-width: 100%; }
            .kcsg-stop-photo-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-top: 20px; }
            .kcsg-stop-photo-card { background: #fff; border: 1px solid #dcdcde; border-radius: 8px; padding: 14px; }
            .kcsg-stop-photo-card h2 { margin: 0 0 10px; font-size: 15px; }
            .kcsg-stop-photo-preview { display: grid; place-items: center; min-height: 128px; border: 1px dashed #c3c4c7; border-radius: 6px; background: #f6f7f7; color: #646970; overflow: hidden; }
            .kcsg-stop-photo-preview img { display: block; width: 100%; height: 150px; object-fit: cover; }
            .kcsg-stop-photo-actions { display: flex; gap: 8px; margin-top: 10px; }
            .kcsg-stop-tracker-field { display: block; margin-top: 12px; }
            .kcsg-stop-tracker-field span { display: block; font-weight: 600; margin-bottom: 5px; }
            .kcsg-stop-tracker-field input { width: 100%; max-width: 100%; }
            @media (max-width: 900px) { .kcsg-admin-grid { grid-template-columns: 1fr; } .kcsg-admin-field-stop, .kcsg-admin-field-category { grid-column: 1 / -1; } }
        ');

        if ($is_stop_photo_page) {
            wp_add_inline_script('media-editor', '
                jQuery(function($) {
                    $(document).on("click", "[data-kcsg-select-stop-photo]", function(e) {
                        e.preventDefault();
                        var card = $(this).closest("[data-kcsg-stop-photo-card]");
                        var input = card.find("[data-kcsg-stop-photo-input]");
                        var preview = card.find("[data-kcsg-stop-photo-preview]");
                        var frame = wp.media({
                            title: "Choose streetcar stop photo",
                            button: { text: "Use this photo" },
                            library: { type: "image" },
                            multiple: false
                        });
                        frame.on("select", function() {
                            var attachment = frame.state().get("selection").first().toJSON();
                            var imageUrl = attachment.sizes && attachment.sizes.medium ? attachment.sizes.medium.url : attachment.url;
                            input.val(attachment.id);
                            preview.html("<img src=\"" + imageUrl + "\" alt=\"\" />");
                        });
                        frame.open();
                    });

                    $(document).on("click", "[data-kcsg-remove-stop-photo]", function(e) {
                        e.preventDefault();
                        var card = $(this).closest("[data-kcsg-stop-photo-card]");
                        card.find("[data-kcsg-stop-photo-input]").val("");
                        card.find("[data-kcsg-stop-photo-preview]").html("<span>No photo selected</span>");
                    });
                });
            ');
        }
    }

    public function maybe_seed_sample_amenities() {
        if (get_option('kcsg_sample_amenities_seeded')) {
            return;
        }

        self::seed_sample_amenities();
    }

    public static function seed_sample_amenities() {
        foreach (self::default_categories() as $term_name) {
            if (!term_exists($term_name, self::TAX)) {
                wp_insert_term($term_name, self::TAX);
            }
        }

        self::seed_default_category_colors();

        $samples = self::sample_amenities();

        foreach ($samples as $sample) {
            $existing = new WP_Query(array(
                'post_type' => self::CPT,
                'post_status' => array('publish', 'draft', 'pending', 'private'),
                'posts_per_page' => 1,
                'no_found_rows' => true,
                'meta_query' => array(
                    array(
                        'key' => '_kcsg_stop',
                        'value' => $sample['stop'],
                    ),
                ),
            ));

            if ($existing->have_posts()) {
                continue;
            }

            $post_id = wp_insert_post(array(
                'post_type' => self::CPT,
                'post_status' => 'publish',
                'post_title' => $sample['name'],
            ));

            if (!$post_id || is_wp_error($post_id)) {
                continue;
            }

            update_post_meta($post_id, '_kcsg_stop', $sample['stop']);
            update_post_meta($post_id, '_kcsg_walk_from_stop', $sample['walk_from_stop']);
            update_post_meta($post_id, '_kcsg_walk_from_hotel', $sample['walk_from_hotel']);
            update_post_meta($post_id, '_kcsg_drive_from_hotel', $sample['drive_from_hotel']);
            update_post_meta($post_id, '_kcsg_description', $sample['description']);

            if (!empty($sample['url'])) {
                update_post_meta($post_id, '_kcsg_url', esc_url_raw($sample['url']));
            }

            $term = get_term_by('name', $sample['category'], self::TAX);
            if ($term && !is_wp_error($term)) {
                wp_set_object_terms($post_id, array((int) $term->term_id), self::TAX, false);
            }
        }

        update_option('kcsg_sample_amenities_seeded', 1, false);
    }

    public static function sample_amenities() {
        $map_url_base = 'https://www.google.com/maps/search/?api=1&query=';
        $samples = array(
            array('name' => 'KC Current Stadium', 'stop' => 'stop-riverfront', 'category' => 'Culture', 'walk_from_stop' => '5 min', 'walk_from_hotel' => '28 min', 'drive_from_hotel' => '8 min', 'description' => 'A riverfront sports and entertainment landmark for visitors exploring the north end of the streetcar line.'),
            array('name' => 'River Market Coffee Stop', 'stop' => 'stop-river-market', 'category' => 'Coffee', 'walk_from_stop' => '3 min', 'walk_from_hotel' => '16 min', 'drive_from_hotel' => '6 min', 'description' => 'A convenient coffee option for guests starting the day around River Market.'),
            array('name' => 'Delaware Street Shops', 'stop' => 'stop-delaware', 'category' => 'Shopping', 'walk_from_stop' => '4 min', 'walk_from_hotel' => '15 min', 'drive_from_hotel' => '5 min', 'description' => 'A simple shopping and strolling suggestion near the River Market loop.'),
            array('name' => 'City Market Dining', 'stop' => 'stop-city-market', 'category' => 'Food', 'walk_from_stop' => '2 min', 'walk_from_hotel' => '17 min', 'drive_from_hotel' => '6 min', 'description' => 'Good for casual visitor-friendly food near the historic City Market area.'),
            array('name' => 'North Loop Coffee Break', 'stop' => 'stop-north-loop', 'category' => 'Coffee', 'walk_from_stop' => '4 min', 'walk_from_hotel' => '10 min', 'drive_from_hotel' => '4 min', 'description' => 'A quick downtown coffee stop between River Market and the central business district.'),
            array('name' => 'Kansas City Public Library', 'stop' => 'stop-library', 'category' => 'Culture', 'walk_from_stop' => '2 min', 'walk_from_hotel' => '9 min', 'drive_from_hotel' => '4 min', 'description' => 'An easy cultural stop for architecture, reading rooms, and a polished downtown visit.'),
            array('name' => 'Made in KC Cafe', 'stop' => 'stop-metro-center', 'category' => 'Coffee', 'walk_from_stop' => '2 min', 'walk_from_hotel' => '6 min', 'drive_from_hotel' => '3 min', 'description' => 'A central downtown option for coffee, light conversation, and nearby meetings.'),
            array('name' => 'Power & Light Dining', 'stop' => 'stop-power--light', 'category' => 'Food', 'walk_from_stop' => '3 min', 'walk_from_hotel' => '8 min', 'drive_from_hotel' => '4 min', 'description' => 'A convenient cluster for dinner, drinks, or a casual group stop downtown.'),
            array('name' => 'Kauffman Center Visit', 'stop' => 'stop-kauffman-center', 'category' => 'Culture', 'walk_from_stop' => '3 min', 'walk_from_hotel' => '12 min', 'drive_from_hotel' => '5 min', 'description' => 'A signature performing arts destination and strong recommendation for executive visitors.'),
            array('name' => 'Messenger Coffee', 'stop' => 'stop-crossroads', 'category' => 'Coffee', 'walk_from_stop' => '4 min', 'walk_from_hotel' => '20 min', 'drive_from_hotel' => '6 min', 'description' => 'A polished Crossroads coffee stop that works well for casual meetings or a break between events.'),
            array('name' => 'Union Station', 'stop' => 'stop-union-station', 'category' => 'Culture', 'walk_from_stop' => '1 min', 'walk_from_hotel' => '30 min', 'drive_from_hotel' => '7 min', 'description' => 'A classic KC destination with exhibits, architecture, and easy visitor appeal.'),
            array('name' => 'National WWI Museum and Memorial', 'stop' => 'stop-wwi-museum--memorial', 'category' => 'Culture', 'walk_from_stop' => '6 min', 'walk_from_hotel' => '34 min', 'drive_from_hotel' => '8 min', 'description' => 'A memorable cultural stop with skyline views and a strong sense of place.'),
            array('name' => 'Union Hill Neighborhood Walk', 'stop' => 'stop-union-hill', 'category' => 'Walks', 'walk_from_stop' => '2 min', 'walk_from_hotel' => '38 min', 'drive_from_hotel' => '9 min', 'description' => 'A relaxed neighborhood walk option near the midtown extension of the line.'),
            array('name' => 'Martini Corner Dinner', 'stop' => 'stop-armour', 'category' => 'Food', 'walk_from_stop' => '8 min', 'walk_from_hotel' => '45 min', 'drive_from_hotel' => '10 min', 'description' => 'A casual dining district option near Armour and Union Hill.'),
            array('name' => 'Westport Evening Stop', 'stop' => 'stop-westport', 'category' => 'Drinks', 'walk_from_stop' => '6 min', 'walk_from_hotel' => '55 min', 'drive_from_hotel' => '12 min', 'description' => 'A lively evening option for visitors looking for a less formal KC neighborhood stop.'),
            array('name' => 'Southmoreland Stroll', 'stop' => 'stop-southmoreland', 'category' => 'Walks', 'walk_from_stop' => '3 min', 'walk_from_hotel' => '60 min', 'drive_from_hotel' => '13 min', 'description' => 'A calmer walking suggestion near museums, historic homes, and the Plaza area.'),
            array('name' => 'Kemper Museum of Contemporary Art', 'stop' => 'stop-art-museums', 'category' => 'Culture', 'walk_from_stop' => '3 min', 'walk_from_hotel' => '65 min', 'drive_from_hotel' => '14 min', 'description' => 'A compact and visitor-friendly art stop near the museum district.'),
            array('name' => 'Country Club Plaza Shopping', 'stop' => 'stop-plaza', 'category' => 'Shopping', 'walk_from_stop' => '4 min', 'walk_from_hotel' => '70 min', 'drive_from_hotel' => '15 min', 'description' => 'A signature shopping and dining district with an easy visitor-friendly route from the streetcar.'),
            array('name' => 'UMKC Campus Walk', 'stop' => 'stop-umkc', 'category' => 'Walks', 'walk_from_stop' => '3 min', 'walk_from_hotel' => '80 min', 'drive_from_hotel' => '16 min', 'description' => 'A simple south-end walking suggestion near campus and nearby cultural destinations.'),
        );

        return array_map(function($sample) use ($map_url_base) {
            $sample['url'] = $map_url_base . rawurlencode($sample['name'] . ' Kansas City MO');
            return $sample;
        }, $samples);
    }

    public function amenity_columns($columns) {
        $new_columns = array();
        foreach ($columns as $key => $label) {
            $new_columns[$key] = $label;
            if ($key === 'title') {
                $new_columns['kcsg_stop'] = __('Streetcar Stop', 'kc-streetcar-guide');
                $new_columns['kcsg_times'] = __('Times', 'kc-streetcar-guide');
            }
        }
        return $new_columns;
    }

    public function amenity_column_content($column, $post_id) {
        if ($column === 'kcsg_stop') {
            $stop_id = get_post_meta($post_id, '_kcsg_stop', true);
            $stops = self::stops();
            echo esc_html(isset($stops[$stop_id]) ? $stops[$stop_id] : '—');
        }

        if ($column === 'kcsg_times') {
            $walk_stop = get_post_meta($post_id, '_kcsg_walk_from_stop', true);
            $walk_hotel = get_post_meta($post_id, '_kcsg_walk_from_hotel', true);
            $drive_hotel = get_post_meta($post_id, '_kcsg_drive_from_hotel', true);
            $parts = array();
            if ($walk_stop) {
                $parts[] = sprintf(__('Stop walk: %s', 'kc-streetcar-guide'), $walk_stop);
            }
            if ($walk_hotel) {
                $parts[] = sprintf(__('Hotel walk: %s', 'kc-streetcar-guide'), $walk_hotel);
            }
            if ($drive_hotel) {
                $parts[] = sprintf(__('Hotel drive: %s', 'kc-streetcar-guide'), $drive_hotel);
            }
            echo $parts ? esc_html(implode(' | ', $parts)) : esc_html__('—', 'kc-streetcar-guide');
        }
    }

    public function register_rest_routes() {
        register_rest_route('kcsg/v1', '/arrivals/(?P<stop_id>[a-z0-9\-]+)', array(
            'methods' => 'GET',
            'callback' => array($this, 'rest_get_arrivals'),
            'permission_callback' => '__return_true',
            'args' => array(
                'stop_id' => array(
                    'required' => true,
                    'sanitize_callback' => 'sanitize_key',
                ),
            ),
        ));
    }

    public function rest_get_arrivals(WP_REST_Request $request) {
        $stop_id = sanitize_key($request->get_param('stop_id'));
        $stops = self::stops();

        if (!isset($stops[$stop_id])) {
            return new WP_Error('kcsg_bad_stop', __('Unknown streetcar stop.', 'kc-streetcar-guide'), array('status' => 404));
        }

        $tracker_urls = self::get_stop_tracker_urls();
        $tracker_url = isset($tracker_urls[$stop_id]) ? self::sanitize_tracker_url($tracker_urls[$stop_id]) : '';

        if (!$tracker_url) {
            return rest_ensure_response(array(
                'ok' => false,
                'stop' => $stop_id,
                'stopLabel' => $stops[$stop_id],
                'arrivals' => array(),
                'message' => __('No live tracker URL is assigned for this stop.', 'kc-streetcar-guide'),
            ));
        }

        $cache_key = 'kcsg_arrivals_' . md5($stop_id . '|' . $tracker_url);
        $cached = get_transient($cache_key);
        if (is_array($cached)) {
            return rest_ensure_response($cached);
        }

        $payload = array(
            'ok' => false,
            'stop' => $stop_id,
            'stopLabel' => $stops[$stop_id],
            'trackerUrl' => $tracker_url,
            'arrivals' => array(),
            'updatedAt' => current_time('c'),
            'message' => __('Live arrivals are unavailable right now.', 'kc-streetcar-guide'),
        );

        $response = wp_remote_get($tracker_url, array(
            'timeout' => 6,
            'redirection' => 3,
            'headers' => array(
                'Accept' => 'text/html,application/json;q=0.9,*/*;q=0.8',
                'User-Agent' => 'KC Streetcar Guide/' . self::VERSION . '; ' . home_url('/'),
            ),
        ));

        if (is_wp_error($response)) {
            $payload['message'] = $response->get_error_message();
            set_transient($cache_key, $payload, self::ARRIVAL_CACHE_TTL);
            return rest_ensure_response($payload);
        }

        $status = wp_remote_retrieve_response_code($response);
        $body = wp_remote_retrieve_body($response);

        if ($status < 200 || $status >= 300 || !$body) {
            $payload['message'] = __('The live tracker did not return arrival data.', 'kc-streetcar-guide');
            set_transient($cache_key, $payload, self::ARRIVAL_CACHE_TTL);
            return rest_ensure_response($payload);
        }

        $parsed = self::parse_arrivals_body($body);
        $payload = array_merge($payload, $parsed);
        $payload['updatedAt'] = current_time('c');

        set_transient($cache_key, $payload, self::ARRIVAL_CACHE_TTL);
        return rest_ensure_response($payload);
    }

    private static function parse_arrivals_body($body) {
        $body = trim((string) $body);
        $arrivals = array();

        if ($body === '') {
            return array(
                'ok' => false,
                'arrivals' => array(),
                'message' => __('No arrival body was returned.', 'kc-streetcar-guide'),
            );
        }

        $json = json_decode($body, true);
        if (json_last_error() === JSON_ERROR_NONE && is_array($json)) {
            $arrivals = self::extract_arrivals_from_json($json);
            return array(
                'ok' => !empty($arrivals),
                'arrivals' => $arrivals,
                'message' => !empty($arrivals) ? '' : __('No arrival predictions were found in the tracker response.', 'kc-streetcar-guide'),
            );
        }

        if (strpos($body, '{{') !== false && strpos($body, 'countdownNumber') !== false) {
            return array(
                'ok' => false,
                'arrivals' => array(),
                'message' => __('This tracker page is rendered client-side, so the plugin could not read a countdown directly yet.', 'kc-streetcar-guide'),
                'needsEndpoint' => true,
            );
        }

        $text = html_entity_decode(wp_strip_all_tags($body), ENT_QUOTES, 'UTF-8');
        $text = preg_replace('/\s+/', ' ', $text);

        if (preg_match_all('/\b(Arriving Soon|Departing Soon|\d{1,2}\s*min)\b/i', $text, $matches)) {
            foreach ($matches[1] as $raw) {
                $raw = trim($raw);
                $arrival = array(
                    'label' => $raw,
                    'minutes' => null,
                    'soon' => (bool) preg_match('/soon/i', $raw),
                    'direction' => '',
                );

                if (preg_match('/(\d{1,2})\s*min/i', $raw, $minute_match)) {
                    $arrival['minutes'] = absint($minute_match[1]);
                    $arrival['label'] = $arrival['minutes'] . ' min';
                }

                $arrivals[] = $arrival;
            }
        }

        if (!empty($arrivals) && preg_match('/\b(Northbound|Southbound|Toward\s+[^|•,]+|To\s+[^|•,]+)\b/i', $text, $direction_match)) {
            $arrivals[0]['direction'] = trim($direction_match[1]);
        }

        return array(
            'ok' => !empty($arrivals),
            'arrivals' => array_slice($arrivals, 0, 3),
            'message' => !empty($arrivals) ? '' : __('No arrival predictions were found in the tracker response.', 'kc-streetcar-guide'),
        );
    }

    private static function extract_arrivals_from_json($value) {
        $arrivals = array();

        $walk = function($node) use (&$walk, &$arrivals) {
            if (!is_array($node) || count($arrivals) >= 3) {
                return;
            }

            $keys = array_change_key_case(array_keys($node), CASE_LOWER);
            $key_lookup = array_combine($keys, array_keys($node));
            $minute_key = null;

            foreach (array('minutes', 'minute', 'countdown', 'countdownnumber', 'walk_time') as $candidate) {
                if (isset($key_lookup[$candidate])) {
                    $minute_key = $key_lookup[$candidate];
                    break;
                }
            }

            $label_key = null;
            foreach (array('label', 'prediction', 'predtime', 'schedtime') as $candidate) {
                if (isset($key_lookup[$candidate])) {
                    $label_key = $key_lookup[$candidate];
                    break;
                }
            }

            if ($minute_key !== null || $label_key !== null) {
                $minutes = $minute_key !== null && is_numeric($node[$minute_key]) ? absint($node[$minute_key]) : null;
                $label = $label_key !== null ? sanitize_text_field((string) $node[$label_key]) : '';
                if ($minutes !== null || $label !== '') {
                    $direction = isset($key_lookup['direction']) ? sanitize_text_field((string) $node[$key_lookup['direction']]) : '';
                    $arrivals[] = array(
                        'label' => $minutes !== null ? $minutes . ' min' : $label,
                        'minutes' => $minutes,
                        'soon' => $minutes === 0 || (bool) preg_match('/soon/i', $label),
                        'direction' => $direction,
                    );
                }
            }

            foreach ($node as $child) {
                if (is_array($child)) {
                    $walk($child);
                }
            }
        };

        $walk($value);
        return array_slice($arrivals, 0, 3);
    }

    private function get_svg_markup() {
        $svg_path = plugin_dir_path(__FILE__) . 'assets/kc-streetcar-line.svg';

        if (!file_exists($svg_path)) {
            return '<p>' . esc_html__('Streetcar SVG not found.', 'kc-streetcar-guide') . '</p>';
        }

        $svg = file_get_contents($svg_path);

        if (!$svg) {
            return '<p>' . esc_html__('Streetcar SVG could not be loaded.', 'kc-streetcar-guide') . '</p>';
        }

        $svg = preg_replace("/^\xEF\xBB\xBF/", '', $svg);
        $svg = preg_replace("/<\?xml[^>]*\?>\s*/i", '', $svg);

        if (preg_match("/<svg\b[^>]*class=[\"']([^\"']*)[\"']/i", $svg)) {
            $svg = preg_replace("/(<svg\b[^>]*class=[\"'])([^\"']*)([\"'])/i", '$1$2 kcsg-map-svg$3', $svg, 1);
        } else {
            $svg = preg_replace("/<svg\b/i", '<svg class="kcsg-map-svg"', $svg, 1);
        }

        if (!preg_match("/<svg\b[^>]*role=[\"']/i", $svg)) {
            $svg = preg_replace("/<svg\b/i", '<svg role="img"', $svg, 1);
        }

        if (!preg_match("/<svg\b[^>]*(aria-label|aria-labelledby)=[\"']/i", $svg)) {
            $svg = preg_replace("/<svg\b/i", '<svg aria-label="Kansas City streetcar line"', $svg, 1);
        }

        return $svg;
    }

    private function get_amenities_data() {
        $query = new WP_Query(array(
            'post_type' => self::CPT,
            'post_status' => 'publish',
            'posts_per_page' => -1,
            'orderby' => 'title',
            'order' => 'ASC',
            'no_found_rows' => true,
        ));

        $stops = self::stops();
        $amenities = array();

        foreach ($query->posts as $post) {
            $terms = get_the_terms($post->ID, self::TAX);
            $categories = array();

            if (!is_wp_error($terms) && !empty($terms)) {
                foreach ($terms as $term) {
                    $categories[] = array(
                        'slug' => $term->slug,
                        'name' => $term->name,
                        'color' => self::category_color($term),
                    );
                }
            }

            $stop_id = get_post_meta($post->ID, '_kcsg_stop', true);
            $amenities[] = array(
                'id' => $post->ID,
                'name' => get_the_title($post),
                'stop' => $stop_id,
                'stopLabel' => isset($stops[$stop_id]) ? $stops[$stop_id] : '',
                'categories' => $categories,
                'walkFromStop' => get_post_meta($post->ID, '_kcsg_walk_from_stop', true),
                'walkFromHotel' => get_post_meta($post->ID, '_kcsg_walk_from_hotel', true),
                'driveFromHotel' => get_post_meta($post->ID, '_kcsg_drive_from_hotel', true),
                'description' => get_post_meta($post->ID, '_kcsg_description', true),
                'url' => get_post_meta($post->ID, '_kcsg_url', true),
            );
        }

        return $amenities;
    }

    private function get_category_data() {
        $terms = get_terms(array(
            'taxonomy' => self::TAX,
            'hide_empty' => false,
            'orderby' => 'name',
            'order' => 'ASC',
        ));

        if (is_wp_error($terms)) {
            return array();
        }

        return array_map(function($term) {
            return array(
                'slug' => $term->slug,
                'name' => $term->name,
                'color' => self::category_color($term),
            );
        }, $terms);
    }

    public function render_shortcode($atts) {
        $atts = shortcode_atts(array(
            'title' => 'KC Streetcar Visitor Guide',
            'intro' => 'Choose a category or click a streetcar stop to find nearby amenities.',
        ), $atts, 'kc_streetcar_guide');

        wp_enqueue_style(
            'kcsg-frontend',
            plugin_dir_url(__FILE__) . 'assets/kcsg-frontend.css',
            array(),
            self::VERSION
        );

        wp_enqueue_script(
            'kcsg-frontend',
            plugin_dir_url(__FILE__) . 'assets/kcsg-frontend.js',
            array(),
            self::VERSION,
            true
        );

        $instance_id = 'kcsg-' . wp_rand(1000, 999999);
        $data = array(
            'amenities' => $this->get_amenities_data(),
            'categories' => $this->get_category_data(),
            'stops' => self::stops(),
            'stopPhotos' => self::get_stop_photo_data(),
            'stopTrackers' => self::get_stop_tracker_data(),
            'arrivalsEndpoint' => esc_url_raw(rest_url('kcsg/v1/arrivals')),
        );

        ob_start();
        ?>
        <section id="<?php echo esc_attr($instance_id); ?>" class="kcsg-guide" data-kcsg-guide>
            <div class="kcsg-header">
                <h2><?php echo esc_html($atts['title']); ?></h2>
                <p><?php echo esc_html($atts['intro']); ?></p>
            </div>

            <div class="kcsg-reset-row">
                <button type="button" class="kcsg-reset" data-kcsg-reset><?php esc_html_e('Reset', 'kc-streetcar-guide'); ?></button>
            </div>

            <div class="kcsg-category-key" aria-label="Amenity categories">
                <button type="button" class="kcsg-category-button is-active" data-kcsg-category="all"><?php esc_html_e('All', 'kc-streetcar-guide'); ?></button>
                <?php foreach ($data['categories'] as $category) : ?>
                    <button type="button" class="kcsg-category-button" data-kcsg-category="<?php echo esc_attr($category['slug']); ?>" style="--kcsg-category-color: <?php echo esc_attr($category['color']); ?>;"><?php echo esc_html($category['name']); ?></button>
                <?php endforeach; ?>
            </div>

            <div class="kcsg-layout">
                <div class="kcsg-map-panel">
                    <?php echo $this->get_svg_markup(); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
                </div>

                <div class="kcsg-results-panel" aria-live="polite">
                    <div class="kcsg-results-scroll" data-kcsg-results-scroll>
                        <div class="kcsg-stop-feature" data-kcsg-stop-feature hidden></div>
                        <div class="kcsg-results" data-kcsg-results></div>
                    </div>
                </div>
            </div>

            <script type="application/json" data-kcsg-data><?php echo wp_json_encode($data); ?></script>
        </section>
        <?php
        return ob_get_clean();
    }
}


final class KCSG_GitHub_Updater {
    const MANIFEST_URL = 'https://raw.githubusercontent.com/okohring/kc-streetcar-guide/main/update.json';
    const CACHE_KEY = 'kcsg_github_update_manifest';
    const CACHE_TTL = 600;

    private $plugin_basename;

    public function __construct($plugin_file) {
        $this->plugin_basename = plugin_basename($plugin_file);

        add_filter('pre_set_site_transient_update_plugins', array($this, 'check_for_update'));
        add_filter('plugins_api', array($this, 'plugin_info'), 20, 3);
        add_filter('upgrader_post_install', array($this, 'rename_release_folder'), 10, 3);
    }

    private function get_manifest($force = false) {
        if (!$force) {
            $cached = get_site_transient(self::CACHE_KEY);
            if (is_array($cached)) {
                return $cached;
            }
        }

        $response = wp_remote_get(self::MANIFEST_URL, array(
            'timeout' => 12,
            'headers' => array(
                'Accept' => 'application/json',
                'User-Agent' => 'KC-Streetcar-Guide-WordPress-Updater',
            ),
        ));

        if (is_wp_error($response)) {
            return null;
        }

        $code = wp_remote_retrieve_response_code($response);
        if ($code < 200 || $code >= 300) {
            return null;
        }

        $manifest = json_decode(wp_remote_retrieve_body($response), true);
        if (!is_array($manifest) || empty($manifest['version']) || empty($manifest['download_url'])) {
            return null;
        }

        $manifest['version'] = ltrim(trim((string) $manifest['version']), 'vV');
        $manifest['download_url'] = esc_url_raw($manifest['download_url']);
        $manifest['details_url'] = !empty($manifest['details_url']) ? esc_url_raw($manifest['details_url']) : 'https://github.com/okohring/kc-streetcar-guide';

        set_site_transient(self::CACHE_KEY, $manifest, self::CACHE_TTL);

        return $manifest;
    }

    public function check_for_update($transient) {
        if (empty($transient) || !is_object($transient) || empty($transient->checked)) {
            return $transient;
        }

        $manifest = $this->get_manifest();
        if (!$manifest || empty($manifest['version']) || empty($manifest['download_url'])) {
            return $transient;
        }

        if (version_compare($manifest['version'], KCSG_Plugin::VERSION, '<=')) {
            return $transient;
        }

        $update = new stdClass();
        $update->id = $manifest['details_url'];
        $update->slug = dirname($this->plugin_basename);
        $update->plugin = $this->plugin_basename;
        $update->new_version = $manifest['version'];
        $update->url = $manifest['details_url'];
        $update->package = $manifest['download_url'];
        $update->tested = !empty($manifest['tested']) ? $manifest['tested'] : '';

        $transient->response[$this->plugin_basename] = $update;

        return $transient;
    }

    public function plugin_info($result, $action, $args) {
        if ($action !== 'plugin_information' || empty($args->slug) || $args->slug !== dirname($this->plugin_basename)) {
            return $result;
        }

        $manifest = $this->get_manifest(true);
        if (!$manifest) {
            return $result;
        }

        $info = new stdClass();
        $info->name = !empty($manifest['name']) ? $manifest['name'] : 'KC Streetcar Guide';
        $info->slug = dirname($this->plugin_basename);
        $info->version = !empty($manifest['version']) ? $manifest['version'] : KCSG_Plugin::VERSION;
        $info->author = '<a href="https://github.com/okohring">Olivia Kohring</a>';
        $info->homepage = !empty($manifest['details_url']) ? $manifest['details_url'] : 'https://github.com/okohring/kc-streetcar-guide';
        $info->download_link = !empty($manifest['download_url']) ? $manifest['download_url'] : '';
        $info->requires = !empty($manifest['requires']) ? $manifest['requires'] : '6.0';
        $info->tested = !empty($manifest['tested']) ? $manifest['tested'] : '';
        $info->requires_php = !empty($manifest['requires_php']) ? $manifest['requires_php'] : '7.4';
        $info->sections = array(
            'description' => !empty($manifest['description']) ? wp_kses_post(wpautop($manifest['description'])) : 'Interactive visitor guide for amenities near the KC Streetcar line.',
            'changelog' => !empty($manifest['changelog']) ? wp_kses_post(wpautop($manifest['changelog'])) : 'See GitHub for changelog notes.',
        );

        return $info;
    }

    public function rename_release_folder($response, $hook_extra, $result) {
        global $wp_filesystem;

        if (empty($hook_extra['plugin']) || $hook_extra['plugin'] !== $this->plugin_basename) {
            return $response;
        }

        if (empty($result['destination']) || empty($result['source']) || empty($wp_filesystem)) {
            return $response;
        }

        $proper_destination = trailingslashit(WP_PLUGIN_DIR) . dirname($this->plugin_basename);
        $source = untrailingslashit($result['source']);

        if ($source === $proper_destination) {
            return $response;
        }

        if ($wp_filesystem->exists($proper_destination)) {
            $wp_filesystem->delete($proper_destination, true);
        }

        $wp_filesystem->move($source, $proper_destination, true);
        $result['destination'] = $proper_destination;
        $result['destination_name'] = dirname($this->plugin_basename);

        return $result;
    }
}

register_activation_hook(__FILE__, array('KCSG_Plugin', 'activate'));
register_deactivation_hook(__FILE__, array('KCSG_Plugin', 'deactivate'));
KCSG_Plugin::instance();
new KCSG_GitHub_Updater(__FILE__);
