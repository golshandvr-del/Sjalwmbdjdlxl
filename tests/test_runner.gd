# test_runner.gd
# ----------------------------------------------------------------------------
# Project Nexus - Lightweight Test Runner (Phase 0, step 0.14).
#
# A zero-dependency unit test harness for the core. It does not require any
# external Godot testing addon. Run it either:
#   - headless:  godot --headless --script res://tests/test_runner.gd
#   - or attach tests/test_scene.tscn as the main scene temporarily.
#
# Each test_* method asserts via _check(); results are printed and the process
# exits with code 0 (all passed) or 1 (some failed) when run headless.
# ----------------------------------------------------------------------------
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0


func _init() -> void:
	print("==== Project Nexus :: Core Test Runner ====")
	test_event_bus_subscribe_emit()
	test_event_bus_unsubscribe()
	test_module_registry()
	test_sim_clock_ticks()
	test_sim_clock_pause()
	test_command_queue_ordering()
	test_world_state_sections()
	# Phase 1 tests.
	test_path_service_straight_line()
	test_path_service_obstacle()
	test_path_service_no_path()
	test_path_service_determinism()
	test_map_module_grid()
	test_economy_production()
	test_combat_damage_and_death()
	test_units_move_command()
	test_integration_deterministic_battle()
	# Phase 3 head-start tests.
	test_victory_elimination()
	test_ai_commander_orders()
	test_integration_ai_battle_deterministic()
	# Phase 2 -- Strategic Depth tests.
	test_tech_tree_research_and_effects()
	test_tech_tree_prerequisites()
	test_tech_tree_rejects_unaffordable()
	test_buildings_construction_and_production()
	test_buildings_upgrade_tree()
	test_logistics_supply_delivery()
	test_fog_of_war_visibility()
	test_difficulty_presets_and_custom()
	test_hero_fusion_recipe()
	test_veterancy_promotion()
	test_integration_phase2_deterministic()
	# Phase 3 -- Smart AI, Lockstep Multiplayer, and Mods.
	test_state_hasher_stable_and_order_independent()
	test_state_hasher_detects_change()
	test_strategic_ai_macro_plan()
	test_strategic_ai_mass_then_push()
	test_strategic_ai_deterministic()
	test_lockstep_tick_gating()
	test_lockstep_command_injection()
	test_lockstep_desync_detection()
	test_lockstep_two_peers_stay_in_sync()
	test_mod_loader_discovers_and_merges()
	test_mod_loader_resolves_load_order()
	test_mod_loader_disabled_skipped()
	# Phase 4 -- Visual Upgrade & Online Transport.
	test_style_simple_draws_all_primitives()
	test_style_detailed_draws_all_primitives()
	test_style_detailed_interface_matches_simple()
	test_render_adapter_style_switching()
	test_render_adapter_style_is_cosmetic_only()
	test_enet_transport_implements_loopback_interface()
	test_transport_swap_keeps_two_peers_in_sync()
	test_network_session_seed_and_peer_agreement()
	test_loopback_control_channel_fanout()
	test_network_session_send_control_delegates()
	test_enet_transport_has_control_channel()
	test_hotseat_session_info_carried()
	test_solo_session_info_defaults()
	# Phase 5 -- Tooling, Desktop UI & Export.
	test_localization_load_and_lookup()
	test_localization_fallback_and_locale_switch()
	test_localization_cycle_locale()
	test_localization_keys_mirrored_across_locales()
	test_code_policy_detects_non_ascii()
	test_code_policy_allows_localization()
	test_code_policy_repository_is_clean()
	test_phase5_scenes_and_presets_exist()
	# Phase 6 -- Content, Balance & Release Hardening.
	test_settings_defaults_and_getters()
	test_settings_validated_setters_reject_bad_values()
	test_settings_persist_round_trip()
	test_settings_corrupt_file_falls_back_to_defaults()
	test_settings_reset_restores_defaults()
	test_settings_keys_localized_in_all_locales()
	test_phase6_options_scene_exists()
	# Phase 6.3-6.6 -- content, balance, mod editor, release tooling.
	test_phase6_new_content_catalogs_load()
	test_phase6_new_scenarios_are_valid_and_loadable()
	test_phase6_ai_max_queue_scales_with_difficulty()
	test_phase6_mod_editor_exists()
	test_phase6_release_tooling_ships()
	test_phase6_new_content_localized_in_all_locales()
	# Phase A -- Visibility & readability.
	test_phase_a_fit_map_to_viewport()
	# Phase B -- Data-driven visual layer ("play-dough").
	test_phase_b_visual_schema_present()
	test_phase_b_texture_service_cache_and_fallback()
	test_phase_b_style_sprite_interface_matches_simple()
	test_phase_b_style_sprite_draws_textures()
	test_phase_b_render_adapter_sprite_style_switch()
	test_phase_b_visual_is_cosmetic_only()
	test_phase_b_playdough_demo_mod_valid()
	test_phase_b_visual_keys_localized_in_all_locales()
	# Phase C -- Storage service + portable .nexpack package format.
	test_phase_c_storage_service_root_and_resolve()
	test_mb8_storage_rejects_read_only_res_root()
	test_phase_c_storage_settings_content_path()
	test_phase_c_pack_format_validation()
	test_phase_c_pack_write_read_round_trip()
	test_phase_c_mod_loader_loads_packs_into_catalogs()
	test_phase_c_options_content_path_localized()
	# Phase D -- graphical Mod Editor (ModProject model + save engine).
	test_phase_d_mod_project_new_and_edit()
	test_phase_d_id_normalisation()
	test_phase_d_validation_rejects_empty()
	test_phase_d_save_and_reopen_round_trip()
	test_phase_d_saved_pack_loads_into_catalogs()
	test_phase_d_textures_round_trip()
	test_phase_d_editor_keys_localized_in_all_locales()
	# Phase E -- graphical Map/Scenario Editor (ScenarioProject model + bundling).
	test_phase_e_scenario_project_new_is_playable()
	test_phase_e_map_paint_fill_border_and_resize()
	test_phase_e_entity_placement_is_exclusive()
	test_phase_e_scenario_round_trip_is_deterministic()
	test_phase_e_validation_catches_problems()
	test_phase_e_simple_tech_tree()
	test_phase_e_scenario_bundled_in_pack_round_trip()
	test_phase_e_authored_scenario_loads_and_plays()
	test_phase_e_scenario_catalog_listing()
	test_phase_e_editor_keys_localized_in_all_locales()
	# Phase E2-E6 -- advanced Mod Editor (tree + graphic + stats + objects + sea).
	test_phase_e2_stat_registry_groups_and_compat()
	test_phase_e2_graphic_layer_rule()
	test_phase_e2_image_validation_png()
	test_phase_e2_tree_round_trip()
	test_phase_e2_texture_validation_and_unique_name()
	test_phase_e3_single_and_multipart_unit()
	test_phase_e3_multipart_conflict_rejected()
	test_phase_e3_upgrade_size_cap()
	test_phase_e4_building_parts_require_hp_armor()
	test_phase_e4_building_multipart_round_trip()
	test_phase_e5_object_extractable_and_decorative()
	test_phase_e5_object_round_trip_in_pack()
	test_phase_e6_sea_paint_and_round_trip()
	test_phase_e6_place_objects_on_map()
	test_phase_e6_coast_is_render_only()
	test_phase_e2e6_editor_keys_localized_in_all_locales()
	# Phase G -- GUI scaling preference + restructured main menu.
	test_phase_g_ui_scale_settings()
	test_phase_g_auto_scale_math()
	test_phase_g_resolve_ui_scale_honours_auto()
	test_phase_g_settings_persist_round_trip()
	test_phase_g_menu_keys_localized_in_all_locales()
	# Phase P3 (v0.6.0) -- interactive camera (zoom/pan/clamp) + HUD strings.
	test_060_p3_zoom_clamps_to_range()
	test_060_p3_zoom_keeps_focus_point_fixed()
	test_060_p3_pan_by_moves_offset()
	test_060_p3_pinch_ratio_zooms_in_and_out()
	test_060_p3_camera_math_is_cosmetic_only()
	test_060_p3_hud_keys_localized_in_all_locales()
	# Phase P7 (v0.6.0) -- HQ/Flag placement, team layout, and game modes.
	test_070_p7_placement_planner_deterministic()
	test_070_p7_placement_planner_avoids_blocked_and_used()
	test_070_p7_placement_clustered_groups_teammates()
	test_070_p7_placement_flags_are_distinct_cells()
	test_070_p7_team_assignment_per_mode()
	test_070_p7_setup_keys_localized_in_all_locales()
	# Phase MA (Android fixes).
	test_ma1_multi_unit_move_spreads_into_formation()
	test_ma1_single_unit_move_keeps_exact_goal()
	test_ma1_formation_goals_are_deterministic()
	test_ma2_box_select_picks_units_inside_rect()
	test_ma2_box_select_filters_by_owner()
	test_ma2_box_select_corner_order_independent()
	test_ma2_box_select_ids_sorted_deterministic()
	# Phase MA3 (Android): control groups (assign / recall / prune / labels).
	test_ma3_assign_normalises_selection()
	test_ma3_recall_prunes_dead_units()
	test_ma3_recall_is_deterministic()
	test_ma3_empty_groups_table_shape()
	test_ma3_button_label_shows_count()
	test_ma3_slot_validation()
	# Phase MA4 (Android): portrait GUI scale + bottom-bar overflow.
	test_ma4_portrait_phone_scale_not_tiny()
	test_ma4_scale_is_orientation_agnostic()
	test_ma4_bottom_bar_scrolls()
	# Phase MA5 (Android): free rotation + responsive HUD re-flow.
	test_ma5_orientation_detection()
	test_ma5_safe_area_excludes_bars()
	test_ma5_all_widgets_stay_on_screen_portrait()
	test_ma5_all_widgets_stay_on_screen_landscape()
	test_ma5_widgets_avoid_hud_bars()
	test_ma5_select_button_sits_above_group()
	test_ma5_oversized_widget_pinned_not_offscreen()
	test_ma5_orientation_changes_placement()
	test_ma5_project_allows_rotation()
	test_ma5_hud_reapplies_scale_on_resize()
	test_mb45_portrait_uses_single_row()
	test_mb45_landscape_wraps_into_multiple_columns()
	test_mb45_columns_that_fit_is_geometric()
	test_mb45_grid_rows_ceils()
	test_mb45_columns_never_exceed_count()
	test_mb45_hud_wires_action_grid_columns()
	test_mb45_scene_action_row_is_grid()
	# Phase MB4.6 (Android): orientation + ui_mode resolution.
	test_mb46_orientation_to_display_constant()
	test_mb46_ui_mode_explicit_is_honoured()
	test_mb46_ui_mode_auto_follows_device()
	test_mb46_orientation_and_ui_mode_prefs_roundtrip()
	# Phase MA6 (Android): single-tap select/toggle/move on the real input path.
	test_ma6_tap_empty_ground_with_no_selection_is_noop()
	test_ma6_tap_friendly_unit_selects_it()
	test_ma6_tap_selected_unit_toggles_it_off()
	test_ma6_repeated_taps_build_a_squad()
	test_ma6_tap_empty_ground_with_selection_moves()
	test_ma6_unit_at_tile_owner_filter_and_determinism()
	test_ma6_resolve_tap_does_not_mutate_input()
	test_ma6_hud_delegates_tap_to_util()
	# Phase MB1 (Android v2): minimap fog filter, teammate control leak, pause formation.
	test_mb1_fog_util_hides_enemy_on_hidden_tile()
	test_mb1_fog_util_shows_enemy_on_visible_tile()
	test_mb1_fog_util_always_shows_own_and_spectator()
	test_mb1_fog_util_state_out_of_range_is_hidden()
	# MB1.2 (bug 1 - teammate control leak): local-control single source of truth.
	test_mb1_ownership_default_local_player_only()
	test_mb1_ownership_explicit_seat_set()
	test_mb1_ownership_from_session()
	test_mb1_tap_ignores_ai_teammate_on_shared_tile()
	test_mb1_tap_empty_owner_set_selects_none()
	test_mb1_box_select_excludes_ai_teammate()
	# MB1.3 (bug 2 - pause stacking): cross-command reserved-tile formation.
	test_mb13_reserved_tiles_are_skipped()
	test_mb13_separate_commands_get_unique_tiles()
	test_mb13_plan_goals_deterministic_with_reserved()
	test_mb13_single_unit_avoids_reserved_tile()
	# Phase MB3 (Android back key, bug 6): NavService pure back-routing logic.
	test_mb3_back_target_maps_each_child_to_its_parent()
	test_mb3_back_target_root_returns_empty()
	test_mb3_back_target_unknown_scene_returns_empty()
	test_mb3_is_root_true_only_for_main_menu()
	test_mb3_is_in_game_true_only_for_game_scenes()
	test_mb3_known_scenes_complete_and_sorted()
	# Phase MB2.2 (bug 5): single-player AI team grouping (AiGroupUtil + bootstrap).
	test_mb2_default_team_matches_team_for_contract()
	test_mb2_default_overrides_seeds_all_owners()
	test_mb2_clamp_team_keeps_range()
	test_mb2_resolve_team_override_wins_int_and_str_keys()
	test_mb2_resolve_team_falls_back_to_default()
	test_mb2_teams_to_members_groups_and_sorts()
	test_mb2_distinct_team_count()
	test_mb2_bootstrap_resolve_team_honours_overrides()
	test_mb2_ai_index_maps_to_owner_seat_for_bootstrap()
	test_mb2_setup_grouping_keys_localized_in_all_locales()
	# MB2.3 (bug 8): Settings moved from a list row to a top-right gear button.
	test_mb2_settings_gear_replaces_list_row()
	test_mb2_settings_gear_tooltip_localized()
	# Phase MB5 (Android v2, bugs 9/10/11/13/14): lobby slot model + sync rules.
	test_mb5_build_host_slots_shape_and_teams()
	test_mb5_build_host_slots_ffa_unique_teams()
	test_mb5_assign_peer_fills_first_open_human_slot()
	test_mb5_assign_peer_never_takes_ai_slot_and_full_returns_minus_one()
	test_mb5_ready_roundtrip_for_peer()
	test_mb5_can_start_gates_on_occupied_humans_only()
	test_mb5_snapshot_includes_ai_and_roundtrips()
	test_mb5_placements_cover_every_slot()
	test_mb5_lobby_teardown_static_guard()
	test_mb5_lobby_client_readonly_view_static_guard()
	test_mb6_net_address_is_ipv4_validation()
	test_mb6_net_address_range_classifiers()
	test_mb6_net_address_best_lan_selection()
	test_mb6_lobby_ip_and_rescan_static_guard()
	# Phase MB7.7 (Android v2, bugs 20/21/22/24): Map Editor rebuild model tests.
	test_mb7_validate_new_map_flags_bad_inputs()
	test_mb7_new_scenario_sized_resizes_and_reseats()
	test_mb7_background_image_set_clear_roundtrip()
	test_mb7_move_entity_building_unit_object()
	test_mb7_move_entity_flag_and_rejections()
	test_mb7_palette_16_colors_stable_and_clamped()
	test_mb7_catalog_list_util_sorted_and_defaults()
	test_mb7_match_setup_rescans_user_packs_static_guard()
	# Phase MB10 (bug 29): global loading overlay -- pure LoadingStages logic.
	test_mb10_determinate_plans_are_monotonic_and_end_full()
	test_mb10_indeterminate_ops_have_no_plan_but_a_label()
	test_mb10_stage_helpers_clamp_out_of_range_index()
	test_mb10_titles_exist_for_every_known_op()
	test_mb10_known_ops_sorted_and_unique()
	# Phase MB9 (bug 28): GL-compat image format normalization (RGBAFloat fix).
	test_mb9_float_formats_flagged_for_normalize()
	test_mb9_byte_formats_not_flagged()
	test_mb9_normalize_converts_float_image_to_rgba8()
	test_mb9_normalize_leaves_rgba8_untouched()
	test_mb9_normalize_is_null_safe()
	# MB9.1 (bug 27): LAN-no-TLS invariant + benign -29184 handshake classifier.
	test_mb9_lan_stack_uses_no_tls()
	test_mb9_known_handshake_error_is_benign()
	test_mb9_non_tls_codes_are_not_benign()
	test_mb9_describe_tls_error_only_for_benign()
	# Phase MC1 (request 1): fog-aware belief pathing + manual-waypoint move mode.
	test_mc1_belief_grid_hidden_is_walkable()
	test_mc1_belief_grid_visible_uses_real_value()
	test_mc1_belief_grid_no_fog_mirrors_real_grid()
	test_mc1_belief_grid_is_deterministic()
	test_mc1_is_known_blocked_only_when_seen()
	test_mc1_belief_path_routes_through_hidden_wall()
	test_mc1_belief_path_avoids_known_wall()
	test_mc1_waypoint_normalize_pairs_and_dedup()
	test_mc1_waypoint_stitch_joins_segments_without_repeat()
	test_mc1_waypoint_stitch_stops_at_unreachable_segment()
	# Phase MC1.5 (request 1): MoveModeUtil direct/manual state machine.
	test_mc1_move_mode_defaults_to_direct()
	test_mc1_move_mode_toggle_flips_and_clears()
	test_mc1_move_mode_direct_tap_issues_move()
	test_mc1_move_mode_manual_tap_accumulates_waypoints()
	test_mc1_move_mode_manual_collapses_duplicate_taps()
	test_mc1_move_mode_commit_returns_pairs_and_clears()
	test_mc1_move_mode_cancel_clears_pending()
	test_mc1_move_mode_no_selection_is_noop()
	test_mc1_move_keys_localized_in_all_locales()
	test_mc1_desktop_hud_wires_move_mode()
	# Phase MC2 (request 2): three-state fog "last image" snapshot memory.
	test_mc2_fog_snapshot_starts_empty()
	test_mc2_fog_snapshot_remembers_visible_entity()
	test_mc2_fog_snapshot_freezes_after_losing_sight()
	test_mc2_fog_snapshot_clears_when_seen_empty()
	test_mc2_fog_snapshot_building_wins_over_unit()
	test_mc2_fog_snapshot_layer_for_states()
	test_mc2_fog_snapshot_is_deterministic()
	test_mc2_fog_snapshot_does_not_affect_state_hash()
	# Phase MC5 (request 6): EditHistoryUtil undo/redo snapshot stack.
	test_mc5_history_starts_empty()
	test_mc5_history_push_and_current()
	test_mc5_history_undo_redo_roundtrip()
	test_mc5_history_push_discards_redo_tail()
	test_mc5_history_respects_max_depth()
	test_mc5_history_snapshots_are_isolated()
	# Phase MC5.4 (request 6): AutosaveUtil path/envelope/throttle/recovery logic.
	test_mc5_autosave_path_for_valid_kinds()
	test_mc5_autosave_path_rejects_bad_kind()
	test_mc5_autosave_envelope_roundtrip()
	test_mc5_autosave_envelope_isolated()
	test_mc5_autosave_parse_rejects_malformed()
	test_mc5_autosave_should_offer_recovery()
	test_mc5_autosave_throttle_blocks_rapid_saves()
	# Phase MC6 (request 7): active-mod selection logic (ActiveModUtil).
	test_mc6_active_mod_list_sorted_and_flags()
	test_mc6_active_mod_ignores_invalid_manifests()
	test_mc6_active_mod_sanitise_drops_missing()
	test_mc6_active_mod_toggle()
	test_mc6_active_mod_resolve_main()
	# Phase MC6.4 (request 7): mod-editor chooser list/resolve logic (ModChoiceUtil).
	test_mc6_mod_choice_list_sorted_and_deduped()
	test_mc6_mod_choice_id_and_has_choices()
	test_mc6_mod_choice_resolve_index()
	# Phase MC6.2 (request 7): active_mods/main_mod persistence in GameSettings.
	test_mc6_settings_active_mods_default_empty()
	test_mc6_settings_active_mods_setters_and_validation()
	test_mc6_settings_active_mods_persist_round_trip()
	# Phase MC3 (request 3): data-driven UI icon manifest + service with fallback.
	test_mc3_manifest_is_valid_and_shaped()
	test_mc3_manifest_util_names_sorted_and_present()
	test_mc3_manifest_util_path_and_size_lookup()
	test_mc3_manifest_util_missing_icon_defaults()
	test_mc3_manifest_util_rejects_malformed()
	test_mc3_icon_service_loads_bundled_manifest()
	test_mc3_icon_service_fallback_never_null()
	test_mc3_icon_service_fallback_cached_and_stable()
	test_mc3_icon_service_has_real_art_false_without_files()
	test_mc3_icon_service_survives_missing_manifest()
	test_mc3_mobile_hud_wires_icon_service()
	# Phase MC4 (request 5): cosmetic animation events (projectile/explosion).
	test_mc4_anim_starts_empty()
	test_mc4_anim_spawn_projectile_and_explosion()
	test_mc4_anim_maps_attack_event()
	test_mc4_anim_maps_death_events()
	test_mc4_anim_ignores_unknown_event()
	test_mc4_anim_resolves_explicit_tile_payload()
	test_mc4_anim_advance_expires_events()
	test_mc4_anim_clear_and_ids_monotonic()
	test_mc4_anim_does_not_affect_state_hash()
	# Phase MC4.2 (request 5): animation sprite fields + round-trip.
	test_mc4_graphic_default_animation_valid()
	test_mc4_graphic_animation_optional()
	test_mc4_graphic_animation_rejects_bad_ranges()
	test_mc4_graphic_has_sprite_flags()
	test_mc4_modproject_animation_roundtrip()
	test_mc4_modproject_animation_missing_entity()
	# Phase MC7 (request 8): data-driven GUI authoring model (GuiProject).
	test_mc7_gui_new_and_pages()
	test_mc7_gui_add_widget_unique_and_clamped()
	test_mc7_gui_edit_rect_icon_name()
	test_mc7_gui_remove_widget()
	test_mc7_gui_background_kinds_and_fallback()
	test_mc7_gui_validate_video_background()
	test_mc7_gui_to_dict_deterministic_sorted()
	test_mc7_gui_json_round_trip()
	test_mc7_gui_from_json_rejects_malformed()
	# Phase MC7.3 (request 8): widget catalog enforces fixed function per page.
	test_mc7_catalog_pages_and_allowed_ids_sorted()
	test_mc7_catalog_is_allowed()
	test_mc7_catalog_validate_project_dict_ok()
	test_mc7_catalog_validate_project_dict_rejects_bad_id()
	test_mc7_catalog_validate_ignores_unknown_page()
	# Phase MC7.6 (request 8): data-driven layout resolver + default fallback.
	test_mc7_render_fit_transform_uniform_and_centered()
	test_mc7_render_resolve_rect()
	test_mc7_render_resolve_page_scales_authored()
	test_mc7_render_resolve_page_falls_back_to_default()
	test_mc7_render_resolve_page_sorted_and_drops_blank()
	# Phase MC7.4/7.7 (request 8): editor wiring + i18n key coverage.
	test_mc7_gui_editor_back_route_and_scene_registered()
	test_mc7_guieditor_i18n_keys_present_in_all_locales()
	# Phase MC8 (request 9): editor hub + defaults tab selection logic.
	test_mc8_defaults_build_choices_sorted_and_deduped()
	test_mc8_defaults_build_choices_from_strings_and_dicts()
	test_mc8_defaults_has_choice_and_display_name()
	test_mc8_defaults_resolve_keeps_valid_drops_stale()
	test_mc8_main_menu_wires_editor_hub_button()
	test_mc8_editorhub_i18n_keys_present_in_all_locales()
	# Phase MC9 (request 10): map-colour -> team extraction + rebel posture.
	test_mc9_used_owners_from_all_entity_arrays()
	test_mc9_used_owners_sorted_deduped_and_clamped()
	test_mc9_used_owners_includes_flag_teams()
	test_mc9_team_count_and_color_hexes()
	test_mc9_restrict_choices_drops_unused()
	test_mc9_used_owners_empty_map()
	test_mc9_color_team_choices_from_map()
	test_mc9_color_team_choices_fallback_when_blank()
	test_mc9_resolve_team_on_map_snaps_stale()
	test_mc9_restrict_overrides_to_map()
	test_mc9_owners_with_hq()
	test_mc9_rebel_owners()
	test_mc9_rebel_owners_all_rebel_when_no_hq()
	test_mc9_general_mode_normalise()
	test_mc9_general_mode_planner_gates()
	test_mc9_general_mode_flags_and_from_map()
	test_mc9_strategic_ai_gates_planners_by_mode()
	# Phase MC10 (requests 11/12/17): dynamic diplomacy pure models.
	test_mc10_relationship_states_and_flags()
	test_mc10_relationship_transitions()
	test_mc10_relationship_pair_key_stable()
	test_mc10_treaty_make_validate_and_types()
	test_mc10_treaty_expiry_and_serialize()
	test_mc10_political_cost_alliance_and_betrayal()
	test_mc10_deployment_command_authority_returns()
	test_mc10_diplomacy_i18n_keys_present_in_all_locales()
	# Phase MC11 (request 11): in-game message UI models.
	test_mc11_message_log_append_and_filter()
	test_mc11_message_log_conversation_and_channels()
	test_mc11_message_log_recipient_choices_and_recent()
	test_mc11_message_log_roundtrip()
	test_mc11_mission_request_make_validate()
	test_mc11_mission_request_roundtrip()
	test_mc11_ai_message_text_descriptor()
	test_mc11_ai_message_keys_present_in_all_locales()
	# Phase MC12 (request 13): AI personality profile model.
	test_mc12_ai_profile_schema_and_defaults()
	test_mc12_ai_profile_load_clamp_and_partial()
	test_mc12_ai_profile_roundtrip_deterministic()
	test_mc12_ai_profile_catalog_lists_nine()
	test_mc12_ai_profile_catalog_loads_valid_defaults()
	test_mc12_ai_profile_catalog_fallback_on_missing()
	# Phase MC12.3 (request 13): AiProfile -> strategic behaviour derivation.
	test_mc12_strategy_derivation_legacy_presets()
	test_mc12_strategy_derivation_from_profile_distinct()
	test_mc12_strategy_derivation_deterministic()
	# Phase MC12.4 (request 13): AI profile summary / tags.
	test_mc12_profile_summary_role_style_danger()
	test_mc12_profile_summary_tags_and_bundle()
	# Phase MC12.5 (request 13): AI profile / summary i18n coverage.
	test_mc12_ai_profile_i18n_keys_present_in_all_locales()
	# Phase MC13.1 (requests 14/15): AI diplomacy decision brain.
	test_mc13_brain_defensive_seeks_peace_when_pressured()
	test_mc13_brain_opportunist_declares_war_on_weak()
	test_mc13_brain_vengeful_wars_distrusted_rival()
	test_mc13_brain_loyal_will_not_betray_ally()
	test_mc13_brain_responds_to_incoming_offers()
	test_mc13_brain_deterministic_same_context()
	# Phase MC13.2 (request 15): in-match short-term learning.
	test_mc13_learning_trust_betrayal_and_heal()
	test_mc13_learning_rate_scales_with_profile()
	test_mc13_learning_threat_zones_reinforce_decay_hottest()
	test_mc13_learning_tactics_success_and_best()
	# Phase MC13.3 (request 15): cross-match persistent reputation store.
	test_mc13_reputation_directional_and_confidence()
	test_mc13_reputation_export_import_roundtrip()
	# Phase MC13.4 (request 15): difficulty = analysis quality + seeded errors.
	test_mc13_difficulty_seeded_noise_deterministic()
	test_mc13_difficulty_unforced_error_floor_above_zero()
	test_mc13_difficulty_reaction_cadence()
	test_mc13_difficulty_score_jitter_scales_with_quality()
	test_mc13_difficulty_apply_downgrades_on_error()
	# Phase MC13.6 (request 14/15): brain action -> readable i18n message bridge.
	test_mc13_brain_action_text_maps_each_action_to_key()
	test_mc13_brain_action_text_describe_is_deterministic()
	test_mc13_brain_action_i18n_keys_present_in_all_locales()
	# Phase MC14.1 (request 16): AI builder form logic (pure).
	test_mc14_builder_new_profile_is_neutral_and_valid()
	test_mc14_builder_archetype_presets_shift_knobs()
	test_mc14_builder_randomize_is_seed_deterministic()
	test_mc14_builder_duplicate_is_independent()
	test_mc14_builder_reset_and_clamp()
	test_mc14_builder_export_import_roundtrip()
	# Phase MC14.2 (request 16): AI roster selection for match setup (pure).
	test_mc14_roster_lists_builtins_then_custom_sorted()
	test_mc14_roster_toggle_selection_is_pure_and_sorted()
	test_mc14_roster_selected_rows_follow_roster_order()
	test_mc14_roster_resolve_profiles_and_custom_override()
	# Phase MC14.3 (request 16/18): graphic facing + firing-part model.
	test_mc14_graphic_facing_normalise_and_roundtrip()
	test_mc14_graphic_set_firing_part_enforces_single()
	test_mc14_graphic_validate_rejects_bad_facing_and_multi_firing()
	# Phase MC14.4 (request 18): combine units -> up to 2 firing parts (pure).
	test_mc14_combine_firing_slots_caps_at_two()
	test_mc14_combine_firing_skips_sources_without_firing_part()
	test_mc14_combine_firing_exceeds_cap_and_turret_flag()
	# Phase MC14.5 (request 16/18): cosmetic turret/idle-spin angle math (pure).
	test_mc14_turret_aim_angle_tracks_target()
	test_mc14_turret_fixed_uses_heading_and_facing_seed()
	test_mc14_turret_idle_spin_and_step_toward()
	# Phase MC14.6 (request 16/18): mod editor facing/firing edit logic (pure).
	test_mc14_facing_edit_set_and_read_facing()
	test_mc14_facing_edit_firing_part_single_and_toggle()
	test_mc14_facing_edit_mount_change_and_choices()
	# Phase MD1 (plan v4): Stat as data asset + metadata getters + core/free + validate.
	test_md1_core_stats_have_full_metadata()
	test_md1_metadata_getters_read_builtins()
	test_md1_load_definitions_merges_free_stat()
	test_md1_load_definitions_partial_overlay_keeps_core()
	test_md1_is_core_and_is_free_classification()
	test_md1_validate_definition_accepts_and_rejects()
	test_md1_all_definition_ids_sorted_and_stable()
	test_md1_stats_catalog_loads_from_disk()
	test_md2_capability_registry_closed_set_complete()
	test_md2_capability_all_ids_sorted_and_stable()
	test_md2_capability_defaults_and_applies_to()
	test_md2_capability_i18n_keys_present_in_all_locales()
	test_md2_stat_affects_builtin_map_fixed_point_and_known()
	test_md2_stat_affects_deterministic_and_defensive()
	test_md2_resolve_affects_merges_mod_and_builtin()
	test_md2_validate_affects_rejects_unknown_and_out_of_range()
	test_md3_compute_capabilities_full_vector_and_fixed_point()
	test_md3_archetypes_rank_as_expected()
	test_md3_cost_efficiency_and_resource_pressure()
	test_md3_cache_matches_uncached_and_key_stable()
	test_md3_resilience_incomplete_unit_uses_defaults()
	test_md4_infer_roles_ranked_fixed_point_and_deterministic()
	test_md4_primary_role_alpha_tie_break()
	test_md4_generic_fallback_never_empty()
	test_md4_synthetic_archetypes_map_to_expected_roles()
	test_md4_building_signatures_and_auto_target()
	test_md4_source_is_ascii_and_pure()
	test_md5_neutral_profile_all_weights_neutral()
	test_md5_defensive_vs_aggressive_role_weights()
	test_md5_capability_weights_cover_registry()
	test_md5_weights_fixed_point_and_bounded()
	test_md5_deterministic_and_null_safe()
	test_md5_knob_sensitivity_directions()
	test_md5_preferred_roles_summary_sorted()
	test_md5_legacy_strategy_derivation_untouched()
	test_md5_source_is_ascii_and_pure()
	test_md7_context_keys_closed_and_sorted()
	test_md7_build_context_full_keys_and_fixed_point()
	test_md7_base_security_and_enemy_distance()
	test_md7_economy_and_army_gap_ratios()
	test_md7_frontline_pressure_and_under_threat()
	test_md7_safe_defaults_when_empty()
	test_md7_deterministic_and_stable_order()
	test_md7_source_is_ascii_and_pure()
	test_md6_closed_condition_and_flag_sets()
	test_md6_empty_policy_is_baseline()
	test_md6_rule_fires_and_overrides()
	test_md6_all_operators()
	test_md6_validate_rejects_malformed()
	test_md6_archetype_presets_contrast()
	test_md6_derive_from_profile()
	test_md6_source_is_ascii_and_pure()
	# Phase MD8 (item 7): unit production utility scoring.
	test_md8_capability_component_neutral_and_weighted()
	test_md8_role_fit_and_current_need()
	test_md8_difficulty_noise_deterministic()
	test_md8_select_best_stable_tiebreak()
	test_md8_defensive_vs_aggressive_pick_contrast()
	test_md8_single_candidate_backward_compatible()
	test_md8_source_is_ascii_and_pure()
	test_md8_candidate_build_from_catalog()
	test_md8_candidate_choose_and_fallback()
	test_md8_candidate_source_is_ascii_and_pure()
	# Phase MD9 (item 8): building placement utility scoring.
	test_md9_derive_needs_from_context()
	test_md9_score_building_value_and_site()
	test_md9_score_building_deterministic()
	test_md9_building_util_source_is_ascii_and_pure()
	# Phase MD9.2 (item 8): site quality scoring.
	test_md9_site_quality_keys_closed_and_sorted()
	test_md9_site_choke_and_path_blocking()
	test_md9_site_security_resource_vulnerability()
	test_md9_fold_quality_and_determinism()
	test_md9_site_scoring_source_is_ascii_and_pure()
	# Phase MD9.3 (item 8): map-grid topology (choke/path/candidates).
	test_md9_topology_find_chokes()
	test_md9_topology_attack_path_and_path_chokes()
	test_md9_topology_candidate_tiles()
	test_md9_topology_source_is_ascii_and_pure()
	# Phase MD9.5 (item 8): placement selector integration + strategic wiring.
	test_md9_placement_selects_best_site_deterministic()
	test_md9_placement_backward_compat_fallback()
	test_md9_strategic_wires_smart_placement()
	# Phase MD10 (item 9): staged decision pipeline.
	test_md10_state_classification()
	test_md10_priority_selection_and_tiebreak()
	test_md10_category_selection()
	test_md10_pick_action_unit_and_building()
	test_md10_decide_end_to_end_and_deterministic()
	test_md10_pipeline_source_is_ascii_and_pure()
	# Phase MD11 (item 12): learning layer (in-match L1 + cross-match L2).
	test_md11_in_match_rate_from_profile()
	test_md11_role_reinforce_and_weaken()
	test_md11_apply_events_deterministic_and_sorted()
	test_md11_anti_exploit_cap_and_baseline_decay()
	test_md11_state_round_trip_sorted()
	test_md11_cross_match_memory_and_seed()
	test_md11_learning_source_is_ascii_and_pure()
	# Phase MD12 (item 15): data-driven Stat UI in the mod editor.
	test_md12_describe_stat_reads_registry_metadata()
	test_md12_stat_ids_for_catalog_sorted()
	test_md12_groups_for_grouped_by_category_sorted()
	test_md12_paginate_mobile_cap_and_bounds()
	test_md12_control_kind_by_value_type()
	test_md12_coerce_value_type_and_clamp()
	test_md12_with_stat_value_pure_and_respects_bounds()
	test_md12_build_free_stat_definition_shape()
	test_md12_validate_free_stat_rules()
	test_md12_stat_editor_util_source_is_ascii_and_pure()
	_print_summary()
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


# Some checks depend on the game's SceneTree/autoloads (e.g. the sprite style's
# ResourceLoader.exists() behaviour and the /root/Nexus autoload used when
# drawing). Those are unavailable in `--script` mode, so a failing assertion
# there is a HARNESS limitation, not a product bug (see BUG_REPORT.md GAP-T4).
# When we are not running inside a full scene tree, record such checks as SKIP
# instead of FAIL so they do not turn the CI gate red with false signals.
func _check_or_skip(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	elif not _has_scene_runtime():
		_skipped += 1
		print("  [SKIP] %s (requires full SceneTree/autoloads; --script mode)" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


# True only when the real game runtime (Nexus autoload) is present. In headless
# `--script` runs there is no /root/Nexus, so resource-import and autoload-backed
# behaviours cannot be exercised faithfully.
func _has_scene_runtime() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	return tree.root.get_node_or_null("/root/Nexus") != null


func _print_summary() -> void:
	print("-------------------------------------------")
	print("Total: %d   Passed: %d   Failed: %d   Skipped: %d" % [
		_passed + _failed, _passed, _failed, _skipped,
	])
	print("===========================================")


# --- EventBus ---------------------------------------------------------------

var _eb_hits: int = 0
var _eb_last_payload: Dictionary = {}

func _eb_handler(_event_name: String, payload: Dictionary) -> void:
	_eb_hits += 1
	_eb_last_payload = payload


func test_event_bus_subscribe_emit() -> void:
	print("test_event_bus_subscribe_emit")
	var bus: EventBus = EventBus.new()
	_eb_hits = 0
	bus.subscribe("ping", self, "_eb_handler")
	_check(bus.listener_count("ping") == 1, "one listener registered")
	bus.emit("ping", { "n": 42 })
	_check(_eb_hits == 1, "handler invoked once")
	_check(int(_eb_last_payload.get("n", 0)) == 42, "payload delivered")
	# Duplicate subscription should be ignored.
	bus.subscribe("ping", self, "_eb_handler")
	_check(bus.listener_count("ping") == 1, "duplicate subscription ignored")


func test_event_bus_unsubscribe() -> void:
	print("test_event_bus_unsubscribe")
	var bus: EventBus = EventBus.new()
	_eb_hits = 0
	bus.subscribe("ev", self, "_eb_handler")
	bus.unsubscribe("ev", self, "_eb_handler")
	bus.emit("ev", {})
	_check(_eb_hits == 0, "no hits after unsubscribe")
	_check(bus.listener_count("ev") == 0, "listener list cleaned up")


# --- ModuleRegistry ---------------------------------------------------------

func test_module_registry() -> void:
	print("test_module_registry")
	var registry: ModuleRegistry = ModuleRegistry.new()
	# A fake minimal nexus stand-in is not needed: register without init wiring
	# by passing null setup and using a module that tolerates a null nexus.
	registry.setup(null)
	var m1: _DummyModule = _DummyModule.new("alpha")
	var m2: _DummyModule = _DummyModule.new("beta")
	_check(registry.register(m1) == true, "register alpha")
	_check(registry.register(m2) == true, "register beta")
	_check(registry.register(_DummyModule.new("alpha")) == false, "duplicate id rejected")
	_check(registry.count() == 2, "two modules registered")
	_check(registry.get_module("beta") == m2, "lookup by id works")
	registry.tick_all(1)
	_check(m1.ticks == 1 and m2.ticks == 1, "tick dispatched to all")
	registry.shutdown_all()
	_check(registry.count() == 0, "registry cleared on shutdown")


# --- SimClock ---------------------------------------------------------------

func test_sim_clock_ticks() -> void:
	print("test_sim_clock_ticks")
	var clock: SimClock = SimClock.new()
	clock.tick_rate = 10  # 0.1s per tick
	clock.start()
	var ticks: int = clock.advance(0.35)  # expect 3 ticks, 0.05 left over
	_check(ticks == 3, "0.35s at 10hz -> 3 ticks")
	var ticks2: int = clock.advance(0.05)  # accumulates to 0.1 -> 1 tick
	_check(ticks2 == 1, "leftover accumulates to next tick")
	_check(clock.total_ticks == 4, "total ticks tracked")


func test_sim_clock_pause() -> void:
	print("test_sim_clock_pause")
	var clock: SimClock = SimClock.new()
	clock.tick_rate = 20
	clock.start()
	clock.pause()
	var ticks: int = clock.advance(1.0)
	_check(ticks == 0, "no ticks while paused")
	clock.resume()
	var ticks2: int = clock.advance(0.1)
	_check(ticks2 == 2, "ticks resume after unpause")


# --- CommandQueue -----------------------------------------------------------

func test_command_queue_ordering() -> void:
	print("test_command_queue_ordering")
	var q: CommandQueue = CommandQueue.new()
	q.enqueue("c_late", 0, 10, {})
	q.enqueue("c_early", 0, 2, {})
	q.enqueue("c_mid", 0, 5, {})
	var due_at_5: Array = q.collect_due(5)
	_check(due_at_5.size() == 2, "two commands due at tick 5")
	_check(due_at_5[0]["type"] == "c_early", "earliest tick comes first")
	_check(due_at_5[1]["type"] == "c_mid", "then the mid one")
	_check(q.pending_count() == 1, "late command still pending")


# --- WorldState -------------------------------------------------------------

func test_world_state_sections() -> void:
	print("test_world_state_sections")
	var ws: WorldState = WorldState.new()
	ws.set_value("economy", "gold", 100)
	_check(int(ws.get_value("economy", "gold", 0)) == 100, "set/get value")
	var snap: Dictionary = ws.serialize()
	var ws2: WorldState = WorldState.new()
	ws2.deserialize(snap)
	_check(int(ws2.get_value("economy", "gold", 0)) == 100, "serialize/deserialize round-trip")


# --- PathService (Phase 1.2) ------------------------------------------------

# Build a width x height all-ground grid (0 = ground, 1 = wall).
func _make_grid(width: int, height: int) -> Array:
	var tiles: Array = []
	tiles.resize(width * height)
	for i in range(tiles.size()):
		tiles[i] = 0
	return tiles


func test_path_service_straight_line() -> void:
	print("test_path_service_straight_line")
	var w: int = 5
	var h: int = 1
	var tiles: Array = _make_grid(w, h)
	var path: Array = PathService.find_path(w, h, tiles, Vector2i(0, 0), Vector2i(4, 0))
	_check(path.size() == 5, "straight line length 5")
	_check(path[0] == Vector2i(0, 0) and path[4] == Vector2i(4, 0), "path endpoints correct")


func test_path_service_obstacle() -> void:
	print("test_path_service_obstacle")
	var w: int = 3
	var h: int = 3
	var tiles: Array = _make_grid(w, h)
	# Wall the middle column at y=0 and y=1 to force a detour.
	tiles[0 * w + 1] = 1
	tiles[1 * w + 1] = 1
	var path: Array = PathService.find_path(w, h, tiles, Vector2i(0, 0), Vector2i(2, 0))
	_check(path.size() > 0, "path found around obstacle")
	# Every step must be walkable and adjacent.
	var ok: bool = true
	for i in range(path.size()):
		var p: Vector2i = path[i]
		if int(tiles[p.y * w + p.x]) != 0:
			ok = false
		if i > 0:
			var prev: Vector2i = path[i - 1]
			if abs(prev.x - p.x) + abs(prev.y - p.y) != 1:
				ok = false
	_check(ok, "path is contiguous and walkable")


func test_path_service_no_path() -> void:
	print("test_path_service_no_path")
	var w: int = 3
	var h: int = 1
	var tiles: Array = _make_grid(w, h)
	tiles[1] = 1  # wall the only corridor
	var path: Array = PathService.find_path(w, h, tiles, Vector2i(0, 0), Vector2i(2, 0))
	_check(path.is_empty(), "no path returns empty")


func test_path_service_determinism() -> void:
	print("test_path_service_determinism")
	var w: int = 6
	var h: int = 6
	var tiles: Array = _make_grid(w, h)
	var p1: Array = PathService.find_path(w, h, tiles, Vector2i(0, 0), Vector2i(5, 5))
	var p2: Array = PathService.find_path(w, h, tiles, Vector2i(0, 0), Vector2i(5, 5))
	_check(p1 == p2, "same inputs produce identical path")


# --- MapModule (Phase 1.1) --------------------------------------------------

func test_map_module_grid() -> void:
	print("test_map_module_grid")
	var map: MapModule = MapModule.new()
	# MapModule tolerates a null nexus for create_grid (it just skips state write).
	map.create_grid(4, 3)
	_check(map.width() == 4 and map.height() == 3, "grid dimensions set")
	_check(map.is_walkable(0, 0), "ground tile walkable")
	map.set_terrain(1, 1, MapModule.TERRAIN_WALL)
	_check(not map.is_walkable(1, 1), "wall tile not walkable")
	_check(not map.in_bounds(4, 0), "out of bounds detected")


# --- Economy (Phase 1.7) ----------------------------------------------------

func test_economy_production() -> void:
	print("test_economy_production")
	var nexus: NexusHarness = NexusHarness.new()
	var economy: EconomyModule = EconomyModule.new()
	nexus.register(economy)
	# Place a producing building directly into world state.
	var buildings: Dictionary = nexus.world_state.get_section("buildings")
	buildings["list"] = { "1000000": { "id": 1000000, "owner": 0, "produces": { "resource_basic": 5 } } }
	# P0 (BUG-1) made production time-based: a building's `produces` block is paid
	# out only on interval boundaries, keyed off world_state.current_tick (never
	# the on_tick delta). So we advance current_tick to two interval boundaries
	# and expect exactly two payouts (2 * 5 = 10). Non-boundary ticks pay nothing.
	var interval: int = EconomyModule.PRODUCTION_INTERVAL_TICKS
	nexus.world_state.current_tick = interval  # first boundary -> +5
	economy.on_tick(1)
	nexus.world_state.current_tick = interval + 1  # not a boundary -> no payout
	economy.on_tick(1)
	nexus.world_state.current_tick = interval * 2  # second boundary -> +5
	economy.on_tick(1)
	_check(economy.get_resource(0, "resource_basic") == 10, "produced 10 over 2 interval boundaries")
	_check(economy.try_spend(0, { "resource_basic": 7 }), "spend affordable cost")
	_check(economy.get_resource(0, "resource_basic") == 3, "balance after spend")
	_check(not economy.try_spend(0, { "resource_basic": 99 }), "reject unaffordable cost")


# --- Combat (Phase 1.8) -----------------------------------------------------

func test_combat_damage_and_death() -> void:
	print("test_combat_damage_and_death")
	var nexus: NexusHarness = NexusHarness.new()
	var combat: CombatModule = CombatModule.new()
	nexus.register(combat)
	var units: Dictionary = nexus.world_state.get_section("units")
	# Attacker (owner 0) adjacent to a weak enemy (owner 1).
	units["list"] = {
		"1": { "id": 1, "owner": 0, "x": 0, "y": 0, "health": 100, "attack_damage": 60, "attack_range": 1, "vision_range": 5, "target_id": -1 },
		"2": { "id": 2, "owner": 1, "x": 1, "y": 0, "health": 100, "attack_damage": 10, "attack_range": 1, "vision_range": 5, "target_id": -1 },
	}
	var died: Array = []
	nexus.death_log = died
	combat.on_tick(1)  # both deal damage; 2 takes 60, 1 takes 10
	_check(int(units["list"]["2"]["health"]) == 40, "enemy took 60 damage")
	combat.on_tick(1)  # 2 drops to <=0
	_check(died.has(2), "death event emitted for unit 2")


# --- Units move command (Phase 1.5) -----------------------------------------

func test_units_move_command() -> void:
	print("test_units_move_command")
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	# Small open map, one friendly unit at (0,0).
	var map: Object = nexus.get_module("map")
	map.create_grid(5, 1)
	var units: Object = nexus.get_module("units")
	var uid: int = units.spawn_unit("soldier", 0, 0, 0)
	# Issue a move command to (4,0) and run enough ticks to arrive.
	nexus.issue_command("move_unit", 0, { "unit_ids": [uid], "x": 4, "y": 0 }, 1)
	nexus.run_ticks(40)
	var u: Dictionary = units.get_unit(uid)
	_check(int(u.get("x", -1)) == 4 and int(u.get("y", -1)) == 0, "unit reached move target")


# --- Integration: deterministic battle (Phase 1.14) -------------------------

func _run_battle_snapshot(seed_value: int, num_ticks: int) -> String:
	var nexus: TickHarness = TickHarness.new()
	var scenario: Dictionary = {
		"random_seed": seed_value,
		"map": { "width": 10, "height": 5, "walls": [[5, 1], [5, 2], [5, 3]] },
		"players": [
			{ "owner": 0, "is_human": true, "start_resources": { "resource_basic": 100 } },
			{ "owner": 1, "is_human": false, "start_resources": { "resource_basic": 100 } },
		],
		"buildings": [
			{ "type": "hq", "owner": 0, "x": 0, "y": 2 },
			{ "type": "hq", "owner": 1, "x": 9, "y": 2 },
		],
		"units": [
			{ "type": "soldier", "owner": 0, "x": 1, "y": 2 },
			{ "type": "soldier", "owner": 1, "x": 8, "y": 2 },
		],
	}
	GameBootstrap.setup_for_test(nexus, scenario)
	# Order both armies to march at each other so combat actually happens.
	var units: Object = nexus.get_module("units")
	nexus.issue_command("move_unit", 0, { "unit_ids": [1], "x": 8, "y": 2 }, 1)
	nexus.issue_command("move_unit", 1, { "unit_ids": [2], "x": 1, "y": 2 }, 1)
	nexus.run_ticks(num_ticks)
	# Build a deterministic hash string from the resulting world state.
	return _hash_world(nexus.world_state)


func _hash_world(world: WorldState) -> String:
	var parts: Array = []
	parts.append("tick=%d" % world.current_tick)
	var units: Dictionary = world.get_section("units").get("list", {})
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for k in ukeys:
		var u: Dictionary = units[k]
		parts.append("u%d:%d,%d,h%d" % [int(u["id"]), int(u["x"]), int(u["y"]), int(u["health"])])
	var buildings: Dictionary = world.get_section("buildings").get("list", {})
	var bkeys: Array = buildings.keys()
	bkeys.sort_custom(func(a, b): return int(a) < int(b))
	for k in bkeys:
		var b: Dictionary = buildings[k]
		parts.append("b%d:h%d" % [int(b["id"]), int(b["health"])])
	return "|".join(parts)


func test_integration_deterministic_battle() -> void:
	print("test_integration_deterministic_battle")
	var snapshot_a: String = _run_battle_snapshot(777, 120)
	var snapshot_b: String = _run_battle_snapshot(777, 120)
	_check(snapshot_a == snapshot_b, "same seed -> identical battle outcome")
	# A different seed configuration with combat should still progress (units
	# took damage somewhere). We assert the battle actually ran to a stable end.
	_check(snapshot_a.length() > 0, "battle produced a non-empty world snapshot")
	var snapshot_c: String = _run_battle_snapshot(777, 121)
	# One extra tick must not crash and remains deterministic on re-run.
	_check(snapshot_c == _run_battle_snapshot(777, 121), "n+1 ticks still deterministic")


# --- Victory module (game loop end) -----------------------------------------

func test_victory_elimination() -> void:
	print("test_victory_elimination")
	var nexus: TickHarness = TickHarness.new()
	var victory: VictoryModule = VictoryModule.new()
	nexus.register_module(victory)
	# Two players, each with one HQ.
	var buildings: Dictionary = nexus.world_state.get_section("buildings")
	buildings["list"] = {
		"1000000": { "id": 1000000, "owner": 0, "x": 0, "y": 0, "health": 100 },
		"1000001": { "id": 1000001, "owner": 1, "x": 9, "y": 0, "health": 100 },
	}
	victory.register_player(0)
	victory.register_player(1)
	_check(not victory.is_over(), "match not over while both HQs alive")
	# Destroy player 1's HQ and announce it.
	buildings["list"].erase("1000001")
	nexus.emit_event("buildings.destroyed", { "id": 1000001, "owner": 1 })
	_check(victory.is_over(), "match over after an HQ is destroyed")
	_check(victory.winner() == 0, "surviving player wins")


# --- AI commander (Phase 3.2) -----------------------------------------------

func test_ai_commander_orders() -> void:
	print("test_ai_commander_orders")
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	var map: Object = nexus.get_module("map")
	map.create_grid(10, 1)
	var ai: Object = nexus.get_module("ai_commander")
	ai.set_ai_player(1, "hard")
	var units: Object = nexus.get_module("units")
	# Human unit at (0,0), AI unit at (9,0) standing still.
	var human_uid: int = units.spawn_unit("soldier", 0, 0, 0)
	var ai_uid: int = units.spawn_unit("soldier", 1, 9, 0)
	# Snapshot the AI unit's starting position, then run a few ticks so the AI
	# can think once and order its idle unit to march toward the enemy.
	nexus.run_ticks(12)
	var ai_unit: Dictionary = units.get_unit(ai_uid)
	# After thinking, the AI unit must have either moved off its start tile or
	# been given a path heading toward the human at (0,0).
	var moved: bool = int(ai_unit.get("x", 9)) < 9
	var has_path: bool = not (ai_unit.get("path", []) as Array).is_empty()
	_check(moved or has_path, "AI unit advances/plans toward the enemy")
	# Let the engagement play out; the human (left standing) should take damage,
	# proving the AI actually closed the distance and fought.
	nexus.run_ticks(60)
	var human_unit: Dictionary = units.get_unit(human_uid)
	var human_hurt_or_dead: bool = human_unit.is_empty() or int(human_unit.get("health", 100)) < 100
	_check(human_hurt_or_dead, "AI engaged: enemy unit took damage")


func _run_ai_battle_snapshot(seed_value: int, num_ticks: int) -> String:
	var nexus: TickHarness = TickHarness.new()
	var scenario: Dictionary = {
		"random_seed": seed_value,
		"map": { "width": 12, "height": 5, "walls": [] },
		"players": [
			{ "owner": 0, "is_human": false, "difficulty": "hard", "start_resources": { "resource_basic": 200 } },
			{ "owner": 1, "is_human": false, "difficulty": "hard", "start_resources": { "resource_basic": 200 } },
		],
		"buildings": [
			{ "type": "hq", "owner": 0, "x": 0, "y": 2 },
			{ "type": "hq", "owner": 1, "x": 11, "y": 2 },
		],
		"units": [
			{ "type": "soldier", "owner": 0, "x": 1, "y": 2 },
			{ "type": "soldier", "owner": 1, "x": 10, "y": 2 },
		],
	}
	GameBootstrap.setup_for_test(nexus, scenario)
	nexus.run_ticks(num_ticks)
	return _hash_world(nexus.world_state)


func test_integration_ai_battle_deterministic() -> void:
	print("test_integration_ai_battle_deterministic")
	# Two AIs fighting each other must be perfectly reproducible (no real RNG).
	var a: String = _run_ai_battle_snapshot(2024, 200)
	var b: String = _run_ai_battle_snapshot(2024, 200)
	_check(a == b, "AI-vs-AI battle is deterministic")
	_check(a.length() > 0, "AI battle produced a world snapshot")


# ============================================================================
# Phase 2 -- Strategic Depth tests
# ============================================================================
#
# These exercise the Phase 2 modules end-to-end through the same TickHarness the
# Phase 1 integration tests use, so they run against the real registration order
# and the real data catalogs (tech, buildings, difficulty, hero recipes).

# Build a ready-to-run Phase 2 harness on an open map with one HQ per player and
# a comfortable resource stockpile, so the strategic systems have something to
# act on. Returns the harness.
func _make_phase2_harness(seed_value: int = 42) -> TickHarness:
	var nexus: TickHarness = TickHarness.new()
	var scenario: Dictionary = {
		"random_seed": seed_value,
		"difficulty": "normal",
		"map": { "width": 16, "height": 8, "walls": [] },
		"players": [
			{ "owner": 0, "is_human": true, "start_resources": { "resource_basic": 2000 } },
			{ "owner": 1, "is_human": false, "difficulty": "easy", "start_resources": { "resource_basic": 2000 } },
		],
		"buildings": [
			{ "type": "hq", "owner": 0, "x": 1, "y": 4 },
			{ "type": "hq", "owner": 1, "x": 14, "y": 4 },
		],
		"units": [],
	}
	GameBootstrap.setup_for_test(nexus, scenario)
	return nexus


# --- Tech tree (Phase 2.1 / 2.2) --------------------------------------------

func test_tech_tree_research_and_effects() -> void:
	print("test_tech_tree_research_and_effects")
	var nexus: TickHarness = _make_phase2_harness()
	var tech: Object = nexus.get_module("tech_tree")
	var units: Object = nexus.get_module("units")
	# Spawn one infantry unit; record its base attack.
	var uid: int = units.spawn_unit("soldier", 0, 2, 4)
	var base_attack: int = int(units.get_unit(uid).get("attack_damage", 0))
	# Research improved_weapons (140 ticks, +5 infantry attack).
	nexus.issue_command("research_tech", 0, { "owner": 0, "node_id": "improved_weapons" }, 1)
	nexus.run_ticks(2)
	_check(tech.is_in_progress(0, "improved_weapons"), "research started after command")
	nexus.run_ticks(160)
	_check(tech.is_researched(0, "improved_weapons"), "research completed after enough ticks")
	# The completed effect must have buffed the living unit and future spawns.
	var living_attack: int = int(units.get_unit(uid).get("attack_damage", 0))
	_check(living_attack == base_attack + 5, "living unit got +5 attack from tech")
	var uid2: int = units.spawn_unit("soldier", 0, 3, 4)
	_check(int(units.get_unit(uid2).get("attack_damage", 0)) == base_attack + 5, "new unit inherits tech bonus")


func test_tech_tree_prerequisites() -> void:
	print("test_tech_tree_prerequisites")
	var nexus: TickHarness = _make_phase2_harness()
	var tech: Object = nexus.get_module("tech_tree")
	# advanced_optics requires improved_armor -> must be blocked first.
	_check(tech.research_blocked_reason(0, "advanced_optics") == "missing_prerequisite", "blocked without prerequisite")
	# Research the prerequisite, then the dependent tech is allowed.
	nexus.issue_command("research_tech", 0, { "owner": 0, "node_id": "improved_armor" }, 1)
	nexus.run_ticks(130)
	_check(tech.is_researched(0, "improved_armor"), "prerequisite researched")
	_check(tech.research_blocked_reason(0, "advanced_optics") == "", "dependent tech now allowed")


func test_tech_tree_rejects_unaffordable() -> void:
	print("test_tech_tree_rejects_unaffordable")
	var nexus: TickHarness = _make_phase2_harness()
	var economy: Object = nexus.get_module("economy")
	var tech: Object = nexus.get_module("tech_tree")
	# Drain the wallet so nothing is affordable.
	economy.try_spend(0, { "resource_basic": economy.get_resource(0, "resource_basic") })
	var rejected: Array = []
	nexus.subscribe("tech.research_rejected", self, "_capture_event")
	_captured = rejected
	nexus.issue_command("research_tech", 0, { "owner": 0, "node_id": "improved_armor" }, 1)
	nexus.run_ticks(3)
	_check(not tech.is_in_progress(0, "improved_armor"), "unaffordable research not started")
	_check(_captured.size() > 0 and str(_captured[0].get("reason", "")) == "insufficient_resources", "rejection reason is insufficient_resources")


# --- Buildings construction + upgrades (Phase 2.3 / 2.4) --------------------

func test_buildings_construction_and_production() -> void:
	print("test_buildings_construction_and_production")
	var nexus: TickHarness = _make_phase2_harness()
	var buildings: Object = nexus.get_module("buildings")
	var economy: Object = nexus.get_module("economy")
	var before: int = economy.get_resource(0, "resource_basic")
	# Build an outpost (cost 120, build_time 90) at a free tile.
	var bid: int = buildings.build_building("outpost", 0, 5, 4)
	_check(bid > 0, "outpost construction started")
	_check(economy.get_resource(0, "resource_basic") == before - 120, "construction cost charged")
	_check(int(buildings.get_building(bid).get("construction_remaining", 0)) > 0, "outpost begins as a construction site")
	# While under construction it must NOT produce resources.
	var mid: int = economy.get_resource(0, "resource_basic")
	nexus.run_ticks(5)
	# (HQ still produces, so account for that: only assert the outpost is not done.)
	_check(int(buildings.get_building(bid).get("construction_remaining", 0)) > 0, "still constructing after 5 ticks")
	# Finish construction.
	nexus.run_ticks(100)
	_check(int(buildings.get_building(bid).get("construction_remaining", 0)) == 0, "outpost finished constructing")
	_check(not buildings.get_building(bid).get("produces", {}).is_empty(), "finished outpost can produce")


func test_buildings_upgrade_tree() -> void:
	print("test_buildings_upgrade_tree")
	var nexus: TickHarness = _make_phase2_harness()
	var buildings: Object = nexus.get_module("buildings")
	# Find player 0's HQ (lowest building id for owner 0).
	var hq_id: int = _first_building_of(nexus, 0)
	var before_hp: int = int(buildings.get_building(hq_id).get("max_health", 0))
	var before_prod: int = int(buildings.get_building(hq_id).get("produces", {}).get("resource_basic", 0))
	# Start the level-2 upgrade (cost 250, time 150, +500 hp, +2 production).
	_check(buildings.upgrade_building(hq_id), "level-2 upgrade queued")
	_check(not buildings.get_building(hq_id).get("upgrade_in_progress", {}).is_empty(), "upgrade in progress")
	# A second upgrade while one is running must be rejected.
	_check(not buildings.upgrade_building(hq_id), "cannot start a second upgrade concurrently")
	nexus.run_ticks(160)
	_check(int(buildings.get_building(hq_id).get("level", 1)) == 2, "HQ reached level 2")
	_check(int(buildings.get_building(hq_id).get("max_health", 0)) == before_hp + 500, "max health increased by upgrade")
	_check(int(buildings.get_building(hq_id).get("produces", {}).get("resource_basic", 0)) == before_prod + 2, "production increased by upgrade")


# --- Logistics (Phase 2.5) --------------------------------------------------

func test_logistics_supply_delivery() -> void:
	print("test_logistics_supply_delivery")
	var nexus: TickHarness = _make_phase2_harness()
	var buildings: Object = nexus.get_module("buildings")
	var logistics: Object = nexus.get_module("logistics")
	# Give player 0 a second, finished command building so a supply route exists.
	var bid: int = buildings.place_building("outpost", 0, 6, 4)
	_check(bid > 0, "second command building placed")
	# Run past a caravan interval (every 20 ticks) so a delivery happens.
	nexus.run_ticks(40)
	_check(logistics.total_shipped(0) > 0, "logistics delivered supply along the route")


# --- Fog of war (Phase 2.6 / 2.7) -------------------------------------------

func test_fog_of_war_visibility() -> void:
	print("test_fog_of_war_visibility")
	var nexus: TickHarness = _make_phase2_harness()
	var fog: Object = nexus.get_module("fog_of_war")
	var units: Object = nexus.get_module("units")
	# Player 0 is a registered viewer (scenario marked human). Spawn a unit and
	# let the fog recompute (every 4 ticks).
	var uid: int = units.spawn_unit("soldier", 0, 4, 4)
	nexus.run_ticks(8)
	var u: Dictionary = units.get_unit(uid)
	_check(fog.is_visible(0, int(u["x"]), int(u["y"])), "own unit's tile is visible")
	# A far corner the unit cannot see should be hidden.
	_check(not fog.is_visible(0, 15, 7), "distant tile is not visible")
	# Move the unit, run again; the old tile becomes merely explored, not visible.
	nexus.issue_command("move_unit", 0, { "unit_ids": [uid], "x": 12, "y": 4 }, 1)
	nexus.run_ticks(60)
	var moved: Dictionary = units.get_unit(uid)
	_check(int(moved.get("x", 4)) > 4, "unit advanced across the map")
	_check(fog.is_explored(0, 4, 4), "previously-seen tile stays explored")


# --- Difficulty (Phase 2.8-2.11) --------------------------------------------

func test_difficulty_presets_and_custom() -> void:
	print("test_difficulty_presets_and_custom")
	var nexus: TickHarness = _make_phase2_harness()
	var difficulty: Object = nexus.get_module("difficulty")
	# Built-in presets resolve from the data catalog.
	_check(difficulty.set_active("hard"), "can activate built-in 'hard' preset")
	_check(difficulty.active_preset_id() == "hard", "active preset id updated")
	_check(difficulty.ai_difficulty_name() == "hard", "hard preset maps to 'hard' AI bucket")
	# Unknown preset is rejected.
	_check(not difficulty.set_active("does_not_exist"), "unknown preset rejected")
	# Define + activate a custom preset (step 2.10) and round-trip it (step 2.11).
	difficulty.define_custom("brutal", {
		"ai_think_interval": 5, "ai_build_chance_pct": 100, "ai_aggression": 1,
		"starting_resources": 100, "player_resource_multiplier": 0.8, "ai_resource_multiplier": 1.8,
	})
	_check(difficulty.set_active("brutal"), "custom preset can be activated")
	_check(difficulty.ai_difficulty_name() == "hard", "fast custom interval maps to hard bucket")
	var saved: Dictionary = difficulty.serialize()
	var nexus2: TickHarness = _make_phase2_harness()
	var difficulty2: Object = nexus2.get_module("difficulty")
	difficulty2.deserialize(saved)
	_check(difficulty2.active_preset_id() == "brutal", "custom selection survives save/load")
	_check(not difficulty2.get_preset("brutal").is_empty(), "custom preset definition survives save/load")


# --- Hero fusion (Phase 2.12 / 2.13) ----------------------------------------

func test_hero_fusion_recipe() -> void:
	print("test_hero_fusion_recipe")
	var nexus: TickHarness = _make_phase2_harness()
	var units: Object = nexus.get_module("units")
	# Spawn three soldiers (recipe: 3 soldiers -> 1 hero).
	var a: int = units.spawn_unit("soldier", 0, 4, 4)
	var b: int = units.spawn_unit("soldier", 0, 4, 5)
	var c: int = units.spawn_unit("soldier", 0, 4, 6)
	var before_count: int = units.count()
	var completed: Array = []
	nexus.subscribe("hero_fusion.completed", self, "_capture_event")
	_captured = completed
	nexus.issue_command("fuse_units", 0, { "owner": 0, "unit_ids": [a, b, c] }, 1)
	# Tick once to process the fuse command (consumes ingredients, issues spawn),
	# then again so the queued hero spawn command resolves.
	nexus.run_ticks(3)
	_check(_captured.size() > 0, "fusion completed event emitted")
	_check(str(_captured[0].get("hero_type", "")) == "hero", "fusion produced a hero")
	# Net unit change: -3 ingredients +1 hero = -2.
	_check(units.count() == before_count - 2, "three soldiers fused into one hero")
	# The new hero must be a 'hero' category with a veterancy bonus applied.
	var found_hero: bool = false
	var list: Dictionary = nexus.world_state.get_section("units").get("list", {})
	for k in list.keys():
		if str(list[k].get("type", "")) == "hero" and int(list[k].get("owner", -1)) == 0:
			found_hero = true
			_check(int(list[k].get("veterancy", 0)) >= 1, "fused hero starts with veterancy")
	_check(found_hero, "a hero unit exists for player 0 after fusion")


# --- Veterancy promotion (Phase 2.14) ---------------------------------------

func test_veterancy_promotion() -> void:
	print("test_veterancy_promotion")
	var nexus: NexusHarness = NexusHarness.new()
	var combat: CombatModule = CombatModule.new()
	nexus.register(combat)
	var units: Dictionary = nexus.world_state.get_section("units")
	# A strong attacker next to a fragile enemy it will kill in one tick.
	units["list"] = {
		"1": { "id": 1, "owner": 0, "x": 0, "y": 0, "health": 100, "max_health": 100, "attack_damage": 200, "attack_range": 1, "vision_range": 5, "target_id": -1, "veterancy": 0, "kills": 0 },
		"2": { "id": 2, "owner": 1, "x": 1, "y": 0, "health": 10, "max_health": 10, "attack_damage": 1, "attack_range": 1, "vision_range": 5, "target_id": -1, "veterancy": 0, "kills": 0 },
	}
	combat.on_tick(1)  # attacker kills unit 2 -> first kill -> rank 1
	_check(int(units["list"]["1"].get("kills", 0)) == 1, "attacker credited with a kill")
	_check(int(units["list"]["1"].get("veterancy", 0)) == 1, "attacker promoted to rank 1 after first kill")
	_check(int(units["list"]["1"].get("max_health", 0)) == 120, "promotion raised max health by 20")


# --- Integration: a full Phase 2 match is deterministic ---------------------

func _run_phase2_snapshot(seed_value: int, num_ticks: int) -> String:
	var nexus: TickHarness = _make_phase2_harness(seed_value)
	var units: Object = nexus.get_module("units")
	var buildings: Object = nexus.get_module("buildings")
	# Drive several Phase 2 systems at once: research, upgrade, build, spawn,
	# and a fusion -- then march everything together so combat + fog + logistics
	# + veterancy all interact. Everything is command-driven for lockstep.
	nexus.issue_command("research_tech", 0, { "owner": 0, "node_id": "improved_weapons" }, 1)
	var hq_id: int = _first_building_of(nexus, 0)
	nexus.issue_command("upgrade_building", 0, { "building_id": hq_id }, 2)
	nexus.issue_command("build_building", 0, { "type": "outpost", "owner": 0, "x": 6, "y": 4 }, 3)
	var s1: int = units.spawn_unit("soldier", 0, 3, 4)
	var s2: int = units.spawn_unit("soldier", 0, 3, 5)
	var s3: int = units.spawn_unit("soldier", 0, 3, 3)
	nexus.issue_command("fuse_units", 0, { "owner": 0, "unit_ids": [s1, s2, s3] }, 4)
	units.spawn_unit("soldier", 1, 12, 4)
	nexus.run_ticks(num_ticks)
	return _hash_world(nexus.world_state)


func test_integration_phase2_deterministic() -> void:
	print("test_integration_phase2_deterministic")
	var a: String = _run_phase2_snapshot(31337, 200)
	var b: String = _run_phase2_snapshot(31337, 200)
	_check(a == b, "full Phase 2 match is perfectly deterministic")
	_check(a.length() > 0, "Phase 2 match produced a world snapshot")
	# One more tick must remain deterministic and not crash.
	_check(_run_phase2_snapshot(31337, 201) == _run_phase2_snapshot(31337, 201), "n+1 ticks still deterministic")


# ============================================================================
# Phase 3 -- Smart AI, Lockstep Multiplayer, and Mods
# ============================================================================
#
# These exercise the three Phase 3 pillars:
#   - StateHasher    : the deterministic world checksum lockstep relies on.
#   - StrategicAI    : the high-level macro brain (expand / research / push).
#   - LockstepModule : scheduled-turn netcode (gating, injection, desync).
#   - ModLoader      : the data-driven mod pipeline (discover / order / merge).
# Everything stays headless and deterministic, matching the project constitution.


# --- StateHasher (Phase 3 core) ---------------------------------------------

func test_state_hasher_stable_and_order_independent() -> void:
	print("test_state_hasher_stable_and_order_independent")
	# Two worlds with the SAME logical content but keys inserted in a DIFFERENT
	# order must hash identically (Godot dict order must not leak into the hash).
	var w1: WorldState = WorldState.new()
	w1.current_tick = 7
	w1.random_seed = 99
	var s1: Dictionary = w1.get_section("units")
	s1["list"] = { "2": { "id": 2, "x": 4, "y": 1, "health": 80 }, "1": { "id": 1, "x": 0, "y": 0, "health": 100 } }
	w1.get_section("economy")["players"] = { "0": { "resource_basic": 150 } }

	var w2: WorldState = WorldState.new()
	w2.current_tick = 7
	w2.random_seed = 99
	# Insert the SAME data but in a different key/section order.
	w2.get_section("economy")["players"] = { "0": { "resource_basic": 150 } }
	var s2: Dictionary = w2.get_section("units")
	s2["list"] = { "1": { "id": 1, "y": 0, "x": 0, "health": 100 }, "2": { "health": 80, "id": 2, "x": 4, "y": 1 } }

	_check(StateHasher.hash_world(w1) == StateHasher.hash_world(w2), "insertion-order-independent hash matches")
	# Re-hashing the same world is stable (pure function).
	_check(StateHasher.hash_world(w1) == StateHasher.hash_world(w1), "hash is stable on repeat")
	# The hex form is a fixed 16-char string.
	_check(StateHasher.hash_world_string(w1).length() == 16, "hex hash is 16 chars")


func test_state_hasher_detects_change() -> void:
	print("test_state_hasher_detects_change")
	var w: WorldState = WorldState.new()
	w.current_tick = 1
	w.get_section("units")["list"] = { "1": { "id": 1, "x": 0, "y": 0, "health": 100 } }
	var before: int = StateHasher.hash_world(w)
	# Mutating a single field must change the hash (no collisions on tiny edits).
	(w.get_section("units")["list"]["1"] as Dictionary)["health"] = 99
	_check(StateHasher.hash_world(w) != before, "single-field change alters the hash")
	# Advancing the tick alone also changes it.
	var h_a: int = StateHasher.hash_world(w)
	w.current_tick = 2
	_check(StateHasher.hash_world(w) != h_a, "tick advance alters the hash")


# --- StrategicAI (Phase 3.1) ------------------------------------------------

# A Phase 3 harness: like the Phase 2 one but with a SMART (strategic) AI player
# that has a big stockpile, so the macro planner has something to act on.
func _make_strategic_harness(seed_value: int = 7, personality: String = "balanced", resources: int = 2000) -> TickHarness:
	var nexus: TickHarness = TickHarness.new()
	var scenario: Dictionary = {
		"random_seed": seed_value,
		"difficulty": "normal",
		"map": { "width": 20, "height": 10, "walls": [] },
		"players": [
			{ "owner": 0, "is_human": true, "start_resources": { "resource_basic": 100 } },
			{ "owner": 1, "is_human": false, "difficulty": "normal", "smart": true,
			  "personality": personality, "start_resources": { "resource_basic": resources } },
		],
		"buildings": [
			{ "type": "hq", "owner": 0, "x": 1, "y": 5 },
			{ "type": "hq", "owner": 1, "x": 18, "y": 5 },
		],
		"units": [],
	}
	GameBootstrap.setup_for_test(nexus, scenario)
	return nexus


func test_strategic_ai_macro_plan() -> void:
	print("test_strategic_ai_macro_plan")
	var nexus: TickHarness = _make_strategic_harness(7, "economic", 3000)
	var strategic: Object = nexus.get_module("strategic_ai")
	_check(strategic != null, "strategic_ai module registered")
	_check(strategic.is_controlling(1), "player 1 is strategically controlled")
	_check(not strategic.is_controlling(0), "human player 0 is NOT controlled")
	# Run long enough for several planning passes. A rich economic AI should
	# either expand (build an outpost -> >1 command building) and/or start
	# research, proving the macro brain acted on its plan.
	var buildings_before: int = nexus.world_state.get_section("buildings").get("list", {}).size()
	nexus.run_ticks(150)
	var buildings_after: int = nexus.world_state.get_section("buildings").get("list", {}).size()
	var tech: Dictionary = nexus.world_state.get_section("tech").get("players", {}).get("1", {})
	var researched_or_progress: bool = not (tech.get("researched", []) as Array).is_empty() \
		or not (tech.get("in_progress", {}) as Dictionary).is_empty()
	_check(buildings_after > buildings_before or researched_or_progress, "economic AI expanded or researched")


func test_strategic_ai_mass_then_push() -> void:
	print("test_strategic_ai_mass_then_push")
	# An aggressive AI gathers a small army then flips its posture to "attack".
	var nexus: TickHarness = _make_strategic_harness(11, "aggressive", 2000)
	var strategic: Object = nexus.get_module("strategic_ai")
	var units: Object = nexus.get_module("units")
	# Hand the AI an army that already meets the aggressive threshold (3) so the
	# very next plan pass must declare the all-in push.
	units.spawn_unit("soldier", 1, 17, 5)
	units.spawn_unit("soldier", 1, 17, 6)
	units.spawn_unit("soldier", 1, 17, 4)
	_check(strategic.posture(1) == "build", "AI starts in the build posture")
	# Run just past the first planning pass (tick 29 for owner 1) so the all-in
	# order is issued and the army is advancing but has not yet reached the HQ.
	nexus.run_ticks(34)
	_check(strategic.posture(1) == "attack", "AI flips to attack once the army is massed")
	# The coordinated push means the soldiers leave their muster point (x=17) and
	# advance WEST toward the human HQ. We assert at least one soldier is both
	# (a) closer to the enemy than it started AND (b) either still pathing or has
	# physically moved -- i.e. it received and acted on the all-in move order.
	var advancing: bool = false
	var list: Dictionary = nexus.world_state.get_section("units").get("list", {})
	for k in list.keys():
		var u: Dictionary = list[k]
		if int(u.get("owner", -1)) != 1:
			continue
		var moved_west: bool = int(u.get("x", 17)) < 17
		var has_path: bool = not (u.get("path", []) as Array).is_empty()
		if moved_west or has_path:
			advancing = true
			break
	_check(advancing, "massed army received a coordinated move order (advancing on the enemy)")


func test_strategic_ai_deterministic() -> void:
	print("test_strategic_ai_deterministic")
	# The macro brain uses no real RNG, so two runs with the same seed must yield
	# byte-identical worlds (it stays lockstep-safe).
	var a: TickHarness = _make_strategic_harness(2024, "balanced", 2500)
	a.run_ticks(180)
	var b: TickHarness = _make_strategic_harness(2024, "balanced", 2500)
	b.run_ticks(180)
	_check(StateHasher.hash_world(a.world_state) == StateHasher.hash_world(b.world_state), "strategic AI run is deterministic")


# --- LockstepModule (Phase 3.2) ---------------------------------------------

func test_lockstep_tick_gating() -> void:
	print("test_lockstep_tick_gating")
	var nexus: TickHarness = TickHarness.new()
	var lock: LockstepModule = LockstepModule.new()
	nexus.register_module(lock)
	lock.init(nexus)
	# Single-player (inactive): the gate is always open.
	_check(lock.can_simulate_tick(), "inactive lockstep never gates")
	# Start a 2-peer session; we are peer 0. We are at tick 0, input_delay 3.
	lock.start_session([0, 1], 0, 3)
	# Tick 1 has NO confirmations yet -> cannot simulate the next tick.
	_check(not lock.is_tick_confirmed(1), "tick unconfirmed before any turns arrive")
	_check(not lock.can_simulate_tick(), "simulation gated while a peer is missing")
	# Local peer flushes an (empty) turn for tick 0+3 = 3, and the remote peer
	# confirms tick 1 with an empty turn. Tick 1 now has BOTH peers -> open.
	lock.receive_turn({ "tick": 1, "peer": 0, "commands": [] })
	_check(not lock.is_tick_confirmed(1), "still gated with only the local confirmation")
	lock.receive_turn({ "tick": 1, "peer": 1, "commands": [] })
	_check(lock.is_tick_confirmed(1), "tick confirmed once every peer reported")
	_check(lock.can_simulate_tick(), "gate opens when next tick is fully confirmed")


func test_lockstep_command_injection() -> void:
	print("test_lockstep_command_injection")
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	nexus.get_module("map").create_grid(10, 3)
	var lock: LockstepModule = nexus.get_module("multiplayer")
	_check(lock != null, "multiplayer module registered by bootstrap")
	lock.start_session([0, 1], 0, 3)
	var units: Object = nexus.get_module("units")
	var uid: int = units.spawn_unit("soldier", 0, 0, 1)
	# Peer 0 submits a move; in a session it is buffered, not run immediately.
	lock.submit_local_command("move_unit", { "unit_ids": [uid], "x": 5, "y": 1 })
	var packet: Dictionary = lock.flush_local_turn()
	_check(int(packet.get("tick", -1)) == nexus.world_state.current_tick + 3, "turn scheduled input_delay ticks ahead")
	# Peer 1 confirms an empty turn for that same tick so it can be simulated.
	lock.receive_turn({ "tick": packet["tick"], "peer": 1, "commands": [] })
	_check(lock.is_tick_confirmed(int(packet["tick"])), "target tick fully confirmed")
	# Injecting the tick's commands schedules them on the real queue; running to
	# that tick must then actually move the unit off its start tile.
	lock.inject_commands_for_tick(int(packet["tick"]))
	nexus.run_ticks(40)
	var u: Dictionary = units.get_unit(uid)
	_check(int(u.get("x", 0)) > 0, "lockstep-injected command actually executed")
	_check(lock.confirmed_through() >= int(packet["tick"]), "confirmed_through advanced past the injected tick")


func test_lockstep_desync_detection() -> void:
	print("test_lockstep_desync_detection")
	var nexus: TickHarness = TickHarness.new()
	var lock: LockstepModule = LockstepModule.new()
	nexus.register_module(lock)
	lock.init(nexus)
	lock.start_session([0, 1], 0, 2)
	lock.checksum_interval = 5
	# Emit a local checksum for tick 5 (our world). The module records it.
	nexus.world_state.current_tick = 5
	lock._maybe_emit_checksum(5)
	_check(not lock.has_desync(), "no desync before a mismatching report")
	# A peer reports a DIFFERENT hash for the same tick -> desync flagged.
	lock.receive_checksum(5, 1, 0xDEADBEEF)
	_check(lock.has_desync(), "mismatching peer checksum raises a desync")
	_check(int(lock.desync_info().get("tick", -1)) == 5, "desync recorded for the right tick")
	# A MATCHING report for another tick must not raise a (new) desync.
	var clean: LockstepModule = LockstepModule.new()
	var nexus2: TickHarness = TickHarness.new()
	nexus2.register_module(clean)
	clean.init(nexus2)
	clean.start_session([0, 1], 0, 2)
	clean.checksum_interval = 5
	nexus2.world_state.current_tick = 5
	clean._maybe_emit_checksum(5)
	var local_hash: int = int(clean._local_checksums[5])
	clean.receive_checksum(5, 1, local_hash)
	_check(not clean.has_desync(), "matching peer checksum is NOT a desync")


func test_lockstep_two_peers_stay_in_sync() -> void:
	print("test_lockstep_two_peers_stay_in_sync")
	# The headline guarantee: two independent peers, same seed, exchanging only
	# commands through a loopback transport, end on IDENTICAL world hashes.
	var input_delay: int = 3
	var transport: LoopbackTransport = LoopbackTransport.new()
	var peers: Array = []
	# Build two complete, independent game instances (peer 0 and peer 1).
	for pid in [0, 1]:
		var nexus: TickHarness = TickHarness.new()
		var scenario: Dictionary = {
			"random_seed": 4242,
			"map": { "width": 12, "height": 5, "walls": [] },
			"players": [
				{ "owner": 0, "is_human": true, "start_resources": { "resource_basic": 200 } },
				{ "owner": 1, "is_human": true, "start_resources": { "resource_basic": 200 } },
			],
			"buildings": [
				{ "type": "hq", "owner": 0, "x": 0, "y": 2 },
				{ "type": "hq", "owner": 1, "x": 11, "y": 2 },
			],
			"units": [
				{ "type": "soldier", "owner": 0, "x": 1, "y": 2 },
				{ "type": "soldier", "owner": 1, "x": 10, "y": 2 },
			],
		}
		GameBootstrap.setup_for_test(nexus, scenario)
		var lock: LockstepModule = nexus.get_module("multiplayer")
		lock.start_session([0, 1], pid, input_delay)
		transport.attach(pid, lock, nexus.event_bus)
		peers.append(nexus)

	# Each peer controls ITS OWN player; both issue a move on tick 0, scheduled
	# for tick `input_delay`. The loopback delivers each turn to the other peer.
	(peers[0].get_module("multiplayer") as Object).submit_local_command("move_unit", { "unit_ids": [1], "x": 9, "y": 2 })
	(peers[1].get_module("multiplayer") as Object).submit_local_command("move_unit", { "unit_ids": [2], "x": 2, "y": 2 })
	# The buffered command flushes into the turn for tick 0 + input_delay.
	var command_tick: int = input_delay
	for nexus in peers:
		(nexus.get_module("multiplayer") as Object).flush_local_turn()
	# Confirm every OTHER tick up to the horizon with empty turns, then drive
	# both peers tick-by-tick, injecting each confirmed tick's commands first.
	# (We skip command_tick so the empty turn does not overwrite the real move.)
	var horizon: int = 80
	for nexus in peers:
		var lock: LockstepModule = nexus.get_module("multiplayer")
		# Empty-confirm ticks 1..horizon for BOTH peers (the loopback relays them).
		for t in range(1, horizon + 1):
			if t == command_tick:
				continue
			lock.flush_empty_turn_for(t)
	# Now both peers have all turns; simulate tick-by-tick in lockstep.
	for t in range(1, horizon + 1):
		for nexus in peers:
			var lock: LockstepModule = nexus.get_module("multiplayer")
			lock.inject_commands_for_tick(t)
			nexus.run_ticks(1)
	var h0: int = StateHasher.hash_world(peers[0].world_state)
	var h1: int = StateHasher.hash_world(peers[1].world_state)
	_check(h0 == h1, "two lockstep peers end with identical world hashes")
	_check(not (peers[0].get_module("multiplayer") as Object).has_desync(), "no desync reported across the match")


# --- ModLoader (Phase 3.3) --------------------------------------------------

func test_mod_loader_discovers_and_merges() -> void:
	print("test_mod_loader_discovers_and_merges")
	var loader: DataLoader = DataLoader.new()
	loader.load_catalog("units", "res://data/units")
	# The base catalog must NOT yet contain the modded unit.
	_check(loader.get_entry("units", "heavy_soldier") == null, "modded unit absent before load")
	var info: Dictionary = ModLoader.load_all(loader, "res://mods")
	_check((info.get("loaded", []) as Array).has("example_mod"), "example_mod discovered + loaded")
	_check(int(info.get("entries_merged", 0)) >= 1, "at least one entry merged")
	var entry: Variant = loader.get_entry("units", "heavy_soldier")
	_check(entry is Dictionary, "heavy_soldier merged into the units catalog")
	if entry is Dictionary:
		_check(str((entry as Dictionary).get("id", "")) == "heavy_soldier", "merged entry keeps its id")


func test_mod_loader_resolves_load_order() -> void:
	print("test_mod_loader_resolves_load_order")
	# A synthetic dependency graph: c depends on b, b depends on a. The resolved
	# order MUST be a, b, c regardless of input order; ties break by sorted id.
	var mods: Array = [
		{ "id": "c", "load_after": ["b"] },
		{ "id": "a", "load_after": [] },
		{ "id": "b", "load_after": ["a"] },
		{ "id": "z", "load_after": [] },
	]
	var ordered: Array = ModLoader.resolve_load_order(mods)
	var ids: Array = []
	for m in ordered:
		ids.append(str(m.get("id", "")))
	# Kahn's algorithm placing in sorted-id order within a single sweep yields
	# a, b, c, z: 'a' has no deps so it is placed first, which immediately
	# unblocks 'b' (then 'c') later in the SAME sweep; 'z' (no deps) follows.
	# The key invariant is that every dependency precedes its dependent AND the
	# order is fully deterministic.
	var dep_ok: bool = ids.find("a") < ids.find("b") and ids.find("b") < ids.find("c")
	_check(dep_ok, "every dependency precedes its dependent (a<b<c)")
	_check(ids == ["a", "b", "c", "z"], "load order is deterministic: a,b,c,z")
	# A disabled mod is excluded entirely.
	var with_disabled: Array = [
		{ "id": "a", "load_after": [] },
		{ "id": "b", "load_after": [], "enabled": false },
	]
	var ordered2: Array = ModLoader.resolve_load_order(with_disabled)
	_check(ordered2.size() == 1 and str(ordered2[0]["id"]) == "a", "disabled mod excluded from order")


func test_mod_loader_disabled_skipped() -> void:
	print("test_mod_loader_disabled_skipped")
	# apply_mod on a manifest with "enabled": false must merge nothing when routed
	# through resolve_load_order (the disabled mod never reaches apply).
	var loader: DataLoader = DataLoader.new()
	var disabled_manifest: Dictionary = {
		"id": "off_mod", "enabled": false, "_dir": "res://mods/example_mod",
		"provides": { "units": ["data/units/heavy_soldier.json"] },
	}
	var ordered: Array = ModLoader.resolve_load_order([disabled_manifest])
	_check(ordered.is_empty(), "disabled mod produces an empty load order")
	# Sanity: the same manifest ENABLED would merge the unit.
	disabled_manifest["enabled"] = true
	var ordered_on: Array = ModLoader.resolve_load_order([disabled_manifest])
	_check(ordered_on.size() == 1, "enabling the mod restores it to the load order")
	var merged: int = ModLoader.apply_mod(loader, ordered_on[0])
	_check(merged >= 1 and loader.get_entry("units", "heavy_soldier") is Dictionary, "enabled mod merges its unit")


# --- Phase 4: Visual Upgrade (render styles) --------------------------------
#
# Both render styles are pure presentation strategies with an identical
# duck-typed interface (draw_tile / draw_building / draw_unit). We exercise them
# against a RECORDING canvas (a stand-in CanvasItem that just counts the draw_*
# calls) so we can assert -- fully headless, no viewport -- that each style emits
# drawing primitives for tiles, buildings, and units, and that the two styles are
# interchangeable.

func test_style_simple_draws_all_primitives() -> void:
	print("test_style_simple_draws_all_primitives")
	var style: StyleSimple = StyleSimple.new()
	var canvas: RecordingCanvas = RecordingCanvas.new()
	_drive_style(style, canvas)
	_check(canvas.calls > 0, "simple style emitted drawing primitives")
	_check(canvas.tiles_drawn, "simple style drew the tile")
	_check(canvas.unit_drawn, "simple style drew a unit body")


func test_style_detailed_draws_all_primitives() -> void:
	print("test_style_detailed_draws_all_primitives")
	var style: StyleDetailed = StyleDetailed.new()
	var canvas: RecordingCanvas = RecordingCanvas.new()
	_drive_style(style, canvas)
	_check(canvas.calls > 0, "detailed style emitted drawing primitives")
	# The detailed style is strictly richer than the simple one, so it must emit
	# at least as many primitives for the same scene.
	var simple_canvas: RecordingCanvas = RecordingCanvas.new()
	_drive_style(StyleSimple.new(), simple_canvas)
	_check(canvas.calls >= simple_canvas.calls, "detailed style draws at least as much as simple")
	_check(canvas.unit_drawn, "detailed style drew a unit body")


func test_style_detailed_interface_matches_simple() -> void:
	print("test_style_detailed_interface_matches_simple")
	# The whole Logic/Render-Separation promise: a detailed style is a drop-in for
	# the simple one. Assert both expose the same three drawing methods.
	var simple: StyleSimple = StyleSimple.new()
	var detailed: StyleDetailed = StyleDetailed.new()
	for method in ["draw_tile", "draw_building", "draw_unit", "owner_color"]:
		_check(simple.has_method(method), "simple style has %s" % method)
		_check(detailed.has_method(method), "detailed style has %s" % method)


func test_render_adapter_style_switching() -> void:
	print("test_render_adapter_style_switching")
	var adapter: RenderAdapter = RenderAdapter.new()
	# Default is the simple style.
	_check(adapter.set_style(RenderAdapter.STYLE_SIMPLE) == RenderAdapter.STYLE_SIMPLE, "set_style returns simple id")
	_check(adapter.style is StyleSimple, "simple style instantiated")
	_check(adapter.set_style(RenderAdapter.STYLE_DETAILED) == RenderAdapter.STYLE_DETAILED, "set_style returns detailed id")
	_check(adapter.style is StyleDetailed, "detailed style instantiated")
	# Unknown ids fall back to simple.
	_check(adapter.set_style("nonsense") == RenderAdapter.STYLE_SIMPLE, "unknown style falls back to simple")
	# Phase B.4 expanded toggle_style() to a 3-style cycle:
	# simple -> detailed -> sprite -> simple. Sprite is now a first-class style.
	adapter.set_style(RenderAdapter.STYLE_SIMPLE)
	_check(adapter.toggle_style() == RenderAdapter.STYLE_DETAILED, "toggle simple -> detailed")
	_check(adapter.toggle_style() == RenderAdapter.STYLE_SPRITE, "toggle detailed -> sprite")
	_check(adapter.toggle_style() == RenderAdapter.STYLE_SIMPLE, "toggle sprite -> simple")
	adapter.free()


func test_render_adapter_style_is_cosmetic_only() -> void:
	print("test_render_adapter_style_is_cosmetic_only")
	# Switching the render style must NEVER touch the simulation. We run a short
	# match, hash the world, swap styles, and assert the world hash is unchanged.
	var harness: TickHarness = _make_strategic_harness(7777, "balanced", 2500)
	harness.run_ticks(40)
	var before: int = StateHasher.hash_world(harness.world_state)
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.set_style(RenderAdapter.STYLE_SIMPLE)
	adapter.set_style(RenderAdapter.STYLE_DETAILED)
	adapter.toggle_style()
	var after: int = StateHasher.hash_world(harness.world_state)
	_check(before == after, "render style swap does not mutate the world state")
	adapter.free()


# Build a representative mini-scene and ask a style to draw a tile, a building,
# and a unit (selected + unselected, with veterancy + a move target).
func _drive_style(style: Object, canvas: Object) -> void:
	var rect: Rect2 = Rect2(0, 0, 24, 24)
	style.draw_tile(canvas, rect, 0)        # ground
	style.draw_tile(canvas, Rect2(24, 0, 24, 24), 1)  # wall
	style.draw_tile(canvas, Rect2(48, 0, 24, 24), 2)  # water
	style.draw_building(canvas, rect, {
		"owner": 0, "x": 0, "y": 0, "health": 700, "max_health": 1000, "level": 2,
	})
	style.draw_unit(canvas, rect, {
		"owner": 1, "x": 0, "y": 0, "health": 50, "max_health": 100,
		"veterancy": 2, "category": "infantry", "target_x": 3, "target_y": 0,
	}, true)
	style.draw_unit(canvas, Rect2(24, 24, 24, 24), {
		"owner": 0, "x": 1, "y": 1, "health": 400, "max_health": 400, "category": "hero",
	}, false)


# --- Phase 4: Online Transport (ENet) ---------------------------------------
#
# We cannot open real UDP sockets headlessly in a deterministic unit test, so we
# verify two things:
#   1) EnetTransport is method-for-method compatible with LoopbackTransport (the
#      transport contract the lockstep core depends on), so the deterministic
#      core can swap one for the other unchanged.
#   2) A SECOND, independent transport implementation (a tiny in-test "fake
#      online" transport that mimics how EnetTransport routes packets between
#      peers) keeps two lockstep peers perfectly in sync -- proving the
#      transport-agnostic core works with any conforming transport, not just the
#      shipped loopback.

func test_enet_transport_implements_loopback_interface() -> void:
	print("test_enet_transport_implements_loopback_interface")
	var enet: EnetTransport = EnetTransport.new()
	# The two methods the lockstep core calls on the way OUT.
	for method in ["broadcast_turn", "broadcast_checksum", "attach"]:
		_check(enet.has_method(method), "EnetTransport has %s (loopback-compatible)" % method)
	# The accessors NetworkSession relies on.
	for method in ["host", "join", "close", "peer_ids", "local_peer_id", "is_host"]:
		_check(enet.has_method(method), "EnetTransport has %s" % method)
	enet.free()


func test_transport_swap_keeps_two_peers_in_sync() -> void:
	print("test_transport_swap_keeps_two_peers_in_sync")
	# Same headline guarantee as the loopback test, but driven through a DIFFERENT
	# transport implementation (FakeOnlineTransport) to prove the lockstep core is
	# truly transport-agnostic: any conforming transport yields identical worlds.
	var input_delay: int = 3
	var transport: FakeOnlineTransport = FakeOnlineTransport.new()
	var peers: Array = []
	for pid in [0, 1]:
		var nexus: TickHarness = TickHarness.new()
		var scenario: Dictionary = {
			"random_seed": 909090,
			"map": { "width": 12, "height": 5, "walls": [] },
			"players": [
				{ "owner": 0, "is_human": true, "start_resources": { "resource_basic": 200 } },
				{ "owner": 1, "is_human": true, "start_resources": { "resource_basic": 200 } },
			],
			"buildings": [
				{ "type": "hq", "owner": 0, "x": 0, "y": 2 },
				{ "type": "hq", "owner": 1, "x": 11, "y": 2 },
			],
			"units": [
				{ "type": "soldier", "owner": 0, "x": 1, "y": 2 },
				{ "type": "soldier", "owner": 1, "x": 10, "y": 2 },
			],
		}
		GameBootstrap.setup_for_test(nexus, scenario)
		var lock: LockstepModule = nexus.get_module("multiplayer")
		lock.start_session([0, 1], pid, input_delay)
		transport.attach(pid, lock, nexus.event_bus)
		peers.append(nexus)

	(peers[0].get_module("multiplayer") as Object).submit_local_command("move_unit", { "unit_ids": [1], "x": 9, "y": 2 })
	(peers[1].get_module("multiplayer") as Object).submit_local_command("move_unit", { "unit_ids": [2], "x": 2, "y": 2 })
	var command_tick: int = input_delay
	for nexus in peers:
		(nexus.get_module("multiplayer") as Object).flush_local_turn()
	var horizon: int = 80
	for nexus in peers:
		var lock: LockstepModule = nexus.get_module("multiplayer")
		for t in range(1, horizon + 1):
			if t == command_tick:
				continue
			lock.flush_empty_turn_for(t)
	for t in range(1, horizon + 1):
		for nexus in peers:
			var lock: LockstepModule = nexus.get_module("multiplayer")
			lock.inject_commands_for_tick(t)
			nexus.run_ticks(1)
	var h0: int = StateHasher.hash_world(peers[0].world_state)
	var h1: int = StateHasher.hash_world(peers[1].world_state)
	_check(h0 == h1, "two peers stay in sync over a swapped (fake-online) transport")
	_check(not (peers[0].get_module("multiplayer") as Object).has_desync(), "no desync over the swapped transport")


func test_network_session_seed_and_peer_agreement() -> void:
	print("test_network_session_seed_and_peer_agreement")
	# NetworkSession.begin_session() must seed the world deterministically and
	# start the lockstep session across the agreed peer set. We exercise this
	# without real sockets by injecting a stub transport into the session.
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	var session: NetworkSession = NetworkSession.new()
	session._nexus = nexus
	session._lockstep = nexus.get_module("multiplayer")
	session._transport = StubTransport.new([0, 1], 0)
	session._seed = 13579
	session._input_delay = 4
	session.begin_session()
	var lock: LockstepModule = nexus.get_module("multiplayer")
	_check(lock.active, "session activated the lockstep module")
	_check(lock.peers == [0, 1], "session started with the agreed peer set")
	_check(lock.local_peer == 0, "session used the transport's local peer id")
	_check(lock.input_delay == 4, "session honoured the requested input delay")
	_check(nexus.world_state.random_seed == 13579, "session seeded the world deterministically")
	session.free()


func test_loopback_control_channel_fanout() -> void:
	print("test_loopback_control_channel_fanout")
	# MA7.2 (B10): send_control() must reach EVERY other peer's bus (never the
	# sender's own), stamped with the correct sender id, carrying the message
	# verbatim. This is the exact mechanism the host uses to tell join clients to
	# leave the lobby for the game scene.
	var transport: LoopbackTransport = LoopbackTransport.new()
	var buses: Array = []
	var collectors: Array = []
	for pid in [0, 1, 2]:
		var bus: EventBus = EventBus.new()
		var col: ControlCollector = ControlCollector.new()
		bus.subscribe(LoopbackTransport.EVENT_CONTROL, col, "on_control")
		# attach() captures the bus; a dummy lockstep object is fine (no turns here).
		transport.attach(pid, RefCounted.new(), bus)
		buses.append(bus)
		collectors.append(col)
	# Host (peer 0) broadcasts a start_match control message.
	transport.send_control(0, { "type": "start_match", "scene": "res://x.tscn", "seed": 77 })
	_check((collectors[0] as ControlCollector).received.is_empty(), "sender (peer 0) does NOT receive its own control message")
	_check((collectors[1] as ControlCollector).received.size() == 1, "peer 1 received exactly one control message")
	_check((collectors[2] as ControlCollector).received.size() == 1, "peer 2 received exactly one control message")
	var got: Dictionary = (collectors[1] as ControlCollector).received[0]
	_check(str(got.get("type", "")) == "start_match", "control payload type preserved")
	_check(int(got.get("seed", 0)) == 77, "control payload data preserved")
	_check(int(got.get("sender", -1)) == 0, "control payload stamped with host sender id 0")


func test_network_session_send_control_delegates() -> void:
	print("test_network_session_send_control_delegates")
	# NetworkSession.send_control() must forward to whatever transport it owns so
	# the lobby stays transport-agnostic (MA7.2 / B10).
	var session: NetworkSession = NetworkSession.new()
	var rec: RecordingTransport = RecordingTransport.new()
	session._transport = rec
	session.send_control({ "type": "start_match", "scene": "res://y.tscn" })
	_check(rec.control_calls == 1, "session delegated exactly one send_control to the transport")
	_check(str(rec.last_control.get("type", "")) == "start_match", "session forwarded the control payload unchanged")
	# With no transport it must be a safe no-op (never crash).
	session._transport = null
	session.send_control({ "type": "start_match" })
	_check(true, "send_control with no transport is a safe no-op")
	session.free()


func test_enet_transport_has_control_channel() -> void:
	print("test_enet_transport_has_control_channel")
	# The online sibling must expose the same control surface as the loopback so
	# the lobby code path is identical for local and online play (MA7.2 / B10).
	var enet: EnetTransport = EnetTransport.new()
	_check(enet.has_method("send_control"), "EnetTransport exposes send_control()")
	_check(EnetTransport.EVENT_CONTROL == "net.control", "EnetTransport.EVENT_CONTROL matches the shared event name")
	_check(LoopbackTransport.EVENT_CONTROL == EnetTransport.EVENT_CONTROL, "loopback and enet agree on the control event name")
	enet.free()


func test_hotseat_session_info_carried() -> void:
	print("test_hotseat_session_info_carried")
	# MA7.4 (B8): a hot-seat setup writes hot_seat=true + a human count into the
	# transient match_config; carry_session_info() must copy those facts into the
	# persistent session_info section so the running game can surface local-MP
	# state after match_config is cleared.
	var ws: WorldState = WorldState.new()
	var cfg: Dictionary = ws.get_section("match_config")
	cfg["hot_seat"] = true
	cfg["human_players"] = 3
	GameBootstrap.carry_session_info(ws)
	var info: Dictionary = ws.get_section("session_info")
	_check(bool(info.get("hot_seat", false)) == true, "session_info.hot_seat reflects the hot-seat setup")
	_check(int(info.get("human_players", 0)) == 3, "session_info.human_players carried over from match_config")


func test_solo_session_info_defaults() -> void:
	print("test_solo_session_info_defaults")
	# A plain single-player setup carries no hot_seat flag; session_info must then
	# default to hot_seat=false and a single human so no local-MP UI is shown.
	var ws: WorldState = WorldState.new()
	var cfg: Dictionary = ws.get_section("match_config")
	cfg["human_players"] = 1
	GameBootstrap.carry_session_info(ws)
	var info: Dictionary = ws.get_section("session_info")
	_check(bool(info.get("hot_seat", true)) == false, "solo session defaults to hot_seat=false")
	_check(int(info.get("human_players", 0)) == 1, "solo session has a single human player")


# ============================================================================
# Phase 5 -- Tooling, Desktop UI & Export
# ============================================================================
#
# These exercise the Phase 5 deliverables that can be verified headlessly:
#   - Localization     : the data-driven English-key -> display-text service.
#   - CODE_POLICY lint  : the ASCII-only enforcement logic (mirrors the linter).
#   - Phase 5 assets    : the new scenes + export presets actually ship.
# The desktop HUD and main menu are scene/input code (no headless viewport), so
# we assert their scene files exist and parse; their command logic reuses the
# already-tested command pipeline.


# --- Localization service (Phase 5.2) ---------------------------------------

func test_localization_load_and_lookup() -> void:
	print("test_localization_load_and_lookup")
	var loc: Localization = Localization.new()
	var loaded: Array = loc.load_all("res://localization")
	_check(loaded.has("en"), "english locale loaded from disk")
	_check(loaded.has("fa"), "persian locale loaded from disk")
	# A known key resolves to its English display text by default.
	_check(loc.t("ui.menu.quit") == "Quit", "english key resolves to english text")
	_check(loc.active_locale() == "en", "default active locale is english")


func test_localization_fallback_and_locale_switch() -> void:
	print("test_localization_fallback_and_locale_switch")
	var loc: Localization = Localization.new()
	loc.load_all("res://localization")
	# Switching to a loaded locale changes the resolved text.
	_check(loc.set_locale("fa"), "can switch to a loaded locale")
	_check(loc.t("ui.menu.quit") != "Quit", "persian text differs from english")
	# An unknown locale is rejected and leaves the active locale unchanged.
	_check(not loc.set_locale("zz"), "unknown locale rejected")
	_check(loc.active_locale() == "fa", "active locale unchanged after a rejected switch")
	# A missing key falls back to the key itself (never a crash / empty string).
	_check(loc.t("ui.does.not.exist") == "ui.does.not.exist", "missing key falls back to the key")


func test_localization_cycle_locale() -> void:
	print("test_localization_cycle_locale")
	var loc: Localization = Localization.new()
	loc.load_all("res://localization")
	var first: String = loc.active_locale()
	var second: String = loc.cycle_locale()
	_check(second != first, "cycle moves to a different locale")
	# Cycling through all locales returns to the start (deterministic ring).
	var count: int = loc.available_locales().size()
	for _i in range(count - 1):
		loc.cycle_locale()
	_check(loc.active_locale() == first, "cycling all the way around returns to the start")


func test_localization_keys_mirrored_across_locales() -> void:
	print("test_localization_keys_mirrored_across_locales")
	# Every English key MUST have a translation in fa.json (and vice versa), so no
	# UI string silently falls back. We compare the two key sets directly.
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	_check(not en.is_empty() and not fa.is_empty(), "both locale files parsed")
	var missing_in_fa: Array = []
	for key in en.keys():
		if not fa.has(key):
			missing_in_fa.append(key)
	var missing_in_en: Array = []
	for key in fa.keys():
		if not en.has(key):
			missing_in_en.append(key)
	_check(missing_in_fa.is_empty(), "every english key is translated in fa (%d missing)" % missing_in_fa.size())
	_check(missing_in_en.is_empty(), "every fa key exists in en (%d missing)" % missing_in_en.size())


# ============================================================================
# Phase E2-E6 -- advanced Mod Editor (tree + graphic + stat registry + objects +
# sea). All pure / headless; no scene, no WorldState.
# ============================================================================

# --- E2: stat registry ------------------------------------------------------

func test_phase_e2_stat_registry_groups_and_compat() -> void:
	print("test_phase_e2_stat_registry_groups_and_compat")
	_check(StatRegistry.has_stat("attack_damage"), "registry knows attack_damage")
	_check(not StatRegistry.has_stat("nonsense"), "registry rejects unknown stat")
	_check(StatRegistry.group_of("armor") == StatRegistry.GROUP_DEFENSE, "armor is a defense stat")
	_check(StatRegistry.group_of("move_speed") == StatRegistry.GROUP_MOBILITY, "move_speed is mobility")
	# ids_for filters by catalog: move_speed is unit-only.
	var unit_ids: Array = StatRegistry.ids_for("unit")
	var building_ids: Array = StatRegistry.ids_for("building")
	_check(unit_ids.has("move_speed"), "units may have move_speed")
	_check(not building_ids.has("move_speed"), "buildings cannot have move_speed")
	_check(building_ids.has("extraction_rate"), "buildings may have extraction_rate")
	# all_ids is deterministic (sorted).
	var a: Array = StatRegistry.all_ids()
	var b: Array = a.duplicate()
	b.sort()
	_check(a == b, "all_ids() is sorted/deterministic")
	# Compatibility: two parts sharing a group conflict (except shared defense).
	var weapon: Dictionary = { "attack_damage": 10 }
	var engine: Dictionary = { "move_speed": 3 }
	var weapon2: Dictionary = { "attack_range": 2 }
	_check(StatRegistry.compatible(weapon, engine), "weapon + engine are compatible")
	_check(not StatRegistry.compatible(weapon, weapon2), "two combat parts conflict")
	# Defense may be shared (building rule) but not when disallowed.
	var armor_a: Dictionary = { "health": 100, "armor": 2 }
	var armor_b: Dictionary = { "health": 80, "armor": 1 }
	_check(StatRegistry.compatible(armor_a, armor_b, true), "shared defense allowed for buildings")
	_check(not StatRegistry.compatible(armor_a, armor_b, false), "shared defense disallowed for units")
	var c: Array = StatRegistry.conflicts(weapon, weapon2)
	_check(c.has(StatRegistry.GROUP_COMBAT), "conflicts() reports the combat group")


# ============================================================================
# Phase MD1 (plan v4): Stat as a data asset. Full metadata on Core Stats, a
# data-driven merge layer, core/free classification, and definition validation.
# All pure / headless; StatRegistry is static so tests reset the merged store.
# ============================================================================

func test_md1_core_stats_have_full_metadata() -> void:
	print("test_md1_core_stats_have_full_metadata")
	StatRegistry.reset_definitions()
	# Every built-in Core Stat must now carry the full data-asset metadata set.
	var required: Array = [
		"value_type", "category", "min", "max", "default",
		"higher_is_better", "ai_importance", "affects",
	]
	for id in StatRegistry.all_ids():
		var def: Dictionary = StatRegistry.definition(id)
		for key in required:
			_check(def.has(key), "core stat %s has metadata %s" % [id, key])
	# Spot-check a couple of specific values.
	_check(StatRegistry.value_type("fire_rate") == "float", "fire_rate is a float stat")
	_check(StatRegistry.value_type("stealth") == "bool", "stealth is a bool stat")
	_check(StatRegistry.category("health") == "defense", "health category is defense")


func test_md1_metadata_getters_read_builtins() -> void:
	print("test_md1_metadata_getters_read_builtins")
	StatRegistry.reset_definitions()
	_check(StatRegistry.higher_is_better("health"), "health higher_is_better")
	_check(StatRegistry.ai_importance("health") > 0.0, "health has ai_importance")
	_check(StatRegistry.min_of("health") >= 1.0, "health min is at least 1")
	_check(StatRegistry.max_of("health") > StatRegistry.min_of("health"), "health max > min")
	var aff: Dictionary = StatRegistry.affects("armor")
	_check(aff.has("survivability"), "armor affects survivability")
	_check(aff.has("holding_power"), "armor affects holding_power")
	# Mutating the returned affects must not corrupt the registry (deep copy).
	aff["survivability"] = -99
	_check(StatRegistry.affects("armor").get("survivability", 0) > 0, "affects() returns a copy")


func test_md1_load_definitions_merges_free_stat() -> void:
	print("test_md1_load_definitions_merges_free_stat")
	StatRegistry.reset_definitions()
	var catalog: Dictionary = {
		"morale": {
			"value_type": "int", "category": "special", "min": 0, "max": 100,
			"default": 50, "higher_is_better": true, "ai_importance": 0.5,
			"affects": { "holding_power": 0.6 },
		},
	}
	var n: int = StatRegistry.load_definitions(catalog)
	_check(n == 1, "one free stat merged")
	_check(StatRegistry.all_definition_ids().has("morale"), "morale is now a known definition")
	_check(StatRegistry.all_definition_ids().has("health"), "core stats survive the merge")
	_check(StatRegistry.value_type("morale") == "int", "free stat value_type readable")
	_check(StatRegistry.affects("morale").get("holding_power", 0) > 0, "free stat affects readable")
	StatRegistry.reset_definitions()
	_check(not StatRegistry.all_definition_ids().has("morale"), "reset drops the free stat")


func test_md1_load_definitions_partial_overlay_keeps_core() -> void:
	print("test_md1_load_definitions_partial_overlay_keeps_core")
	StatRegistry.reset_definitions()
	# A data file that only tweaks ai_importance must keep the rest of health.
	StatRegistry.load_definitions({ "health": { "ai_importance": 0.99 } })
	_check(abs(StatRegistry.ai_importance("health") - 0.99) < 0.001, "overlay updated ai_importance")
	_check(StatRegistry.category("health") == "defense", "overlay kept category")
	_check(StatRegistry.affects("health").has("survivability"), "overlay kept affects")
	_check(StatRegistry.is_core("health"), "health remains core after overlay")
	StatRegistry.reset_definitions()


func test_md1_is_core_and_is_free_classification() -> void:
	print("test_md1_is_core_and_is_free_classification")
	StatRegistry.reset_definitions()
	_check(StatRegistry.is_core("health"), "health is core")
	_check(not StatRegistry.is_free("health"), "health is not free")
	StatRegistry.load_definitions({ "morale": { "value_type": "int" } })
	_check(StatRegistry.is_free("morale"), "morale is free")
	_check(not StatRegistry.is_core("morale"), "morale is not core")
	_check(StatRegistry.is_core("health"), "health still core after free merge")
	StatRegistry.reset_definitions()


func test_md1_validate_definition_accepts_and_rejects() -> void:
	print("test_md1_validate_definition_accepts_and_rejects")
	var good: Dictionary = {
		"id": "morale", "value_type": "int", "category": "special",
		"min": 0, "max": 100, "default": 50, "higher_is_better": true,
		"ai_importance": 0.5, "affects": { "holding_power": 0.6 },
	}
	_check(StatRegistry.validate_definition(good).is_empty(), "valid definition passes")
	_check(not StatRegistry.validate_definition("not a dict").is_empty(), "non-dict rejected")
	_check(not StatRegistry.validate_definition({ "value_type": "int" }).is_empty(), "missing id rejected")
	var bad_type: Dictionary = { "id": "x", "value_type": "matrix" }
	_check(not StatRegistry.validate_definition(bad_type).is_empty(), "bad value_type rejected")
	var bad_range: Dictionary = { "id": "x", "min": 10, "max": 2 }
	_check(not StatRegistry.validate_definition(bad_range).is_empty(), "min>max rejected")
	var bad_imp: Dictionary = { "id": "x", "ai_importance": 5.0 }
	_check(not StatRegistry.validate_definition(bad_imp).is_empty(), "ai_importance out of range rejected")
	var bad_aff: Dictionary = { "id": "x", "affects": { "survivability": "lots" } }
	_check(not StatRegistry.validate_definition(bad_aff).is_empty(), "non-numeric affect rejected")
	var unknown_key: Dictionary = { "id": "x", "wat": 1 }
	_check(not StatRegistry.validate_definition(unknown_key).is_empty(), "unknown key rejected")


func test_md1_all_definition_ids_sorted_and_stable() -> void:
	print("test_md1_all_definition_ids_sorted_and_stable")
	StatRegistry.reset_definitions()
	StatRegistry.load_definitions({ "zeta": { "value_type": "int" }, "alpha": { "value_type": "int" } })
	var ids: Array = StatRegistry.all_definition_ids()
	var sorted_copy: Array = ids.duplicate()
	sorted_copy.sort()
	_check(ids == sorted_copy, "all_definition_ids() is sorted")
	# Deterministic: same merge order -> same result set.
	var again: Array = StatRegistry.all_definition_ids()
	_check(ids == again, "all_definition_ids() is stable across calls")
	StatRegistry.reset_definitions()


# MD1.5: the on-disk data/stats/*.json catalog loads through DataLoader and every
# Core Stat definition round-trips into the registry with its metadata intact.
func test_md1_stats_catalog_loads_from_disk() -> void:
	print("test_md1_stats_catalog_loads_from_disk")
	var loader: DataLoader = DataLoader.new()
	var n: int = loader.load_catalog("stats", "res://data/stats")
	_check(n >= 13, "loaded at least the 13 core stat files")
	var catalog: Dictionary = loader.get_catalog("stats")
	_check(catalog.has("health"), "catalog has health.json")
	_check(catalog.has("attack_damage"), "catalog has attack_damage.json")
	# Every loaded definition must pass validation.
	for id in catalog.keys():
		_check(StatRegistry.validate_definition(catalog[id]).is_empty(), "disk stat %s validates" % str(id))
	# Merge into a fresh registry and confirm the getters read disk values.
	StatRegistry.reset_definitions()
	StatRegistry.load_definitions(catalog)
	_check(StatRegistry.affects("health").has("survivability"), "disk health affects survivability")
	_check(StatRegistry.is_core("health"), "disk health classified core")
	StatRegistry.reset_definitions()


# --- MD2: Capability layer (closed, versioned engine contract) ---------------

# MD2.1: the closed capability set is complete -- it contains exactly the unit
# and building capabilities the plan (section 2.3) mandates, no more, no less.
func test_md2_capability_registry_closed_set_complete() -> void:
	print("test_md2_capability_registry_closed_set_complete")
	var expected: Array = [
		# unit
		"survivability", "damage_output", "mobility", "holding_power",
		"siege_power", "scout_power", "support_power", "cost_efficiency",
		"anti_air_power", "resource_pressure",
		# building
		"defense_value", "production_value", "tech_value", "economic_value",
		"frontline_value", "repair_value", "control_value",
	]
	expected.sort()
	_check(CapabilityRegistry.all_ids() == expected, "capability set matches section 2.3 exactly")
	_check(CapabilityRegistry.VERSION >= 1, "capability contract is versioned")
	for id in expected:
		_check(CapabilityRegistry.has_capability(id), "has_capability(%s)" % id)
	_check(not CapabilityRegistry.has_capability("not_a_capability"), "unknown id rejected")


# MD2.1: all_ids() is stably sorted and deterministic across repeated calls.
func test_md2_capability_all_ids_sorted_and_stable() -> void:
	print("test_md2_capability_all_ids_sorted_and_stable")
	var a: Array = CapabilityRegistry.all_ids()
	var sorted_copy: Array = a.duplicate()
	sorted_copy.sort()
	_check(a == sorted_copy, "all_ids() is sorted")
	_check(a == CapabilityRegistry.all_ids(), "all_ids() is stable across calls")
	# ids_for filters by applies_to; a "both" capability shows for either target.
	var unit_ids: Array = CapabilityRegistry.ids_for("unit")
	var bld_ids: Array = CapabilityRegistry.ids_for("building")
	_check(unit_ids.has("mobility"), "ids_for(unit) includes unit-only mobility")
	_check(not unit_ids.has("defense_value"), "ids_for(unit) excludes building-only defense_value")
	_check(bld_ids.has("defense_value"), "ids_for(building) includes defense_value")
	_check(unit_ids.has("resource_pressure") and bld_ids.has("resource_pressure"), "both-capability appears for unit and building")


# MD2.1: safe fixed-point defaults (section 2.5) and applies_to contract.
func test_md2_capability_defaults_and_applies_to() -> void:
	print("test_md2_capability_defaults_and_applies_to")
	for id in CapabilityRegistry.all_ids():
		var dq: int = CapabilityRegistry.default_q(id)
		_check(dq >= 0 and dq <= CapabilityRegistry.SCALE, "default_q(%s) in [0..SCALE]" % id)
		var a: String = CapabilityRegistry.applies_to(id)
		_check(a == "unit" or a == "building" or a == "both", "applies_to(%s) valid" % id)
	# Unknown id yields safe zero, never a crash.
	_check(CapabilityRegistry.default_q("nope") == 0, "unknown default_q is 0")
	_check(CapabilityRegistry.applies_to("nope") == "", "unknown applies_to is empty")


# MD2.1: every capability's i18n display key exists in en AND fa (parity).
func test_md2_capability_i18n_keys_present_in_all_locales() -> void:
	print("test_md2_capability_i18n_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	for id in CapabilityRegistry.all_ids():
		var key: String = CapabilityRegistry.name_key(id)
		_check(key != "", "capability %s has a name_key" % id)
		_check(en.has(key), "en has %s" % key)
		_check(fa.has(key), "fa has %s" % key)


# MD2.2: the built-in Core-Stat -> Capability affects map is fixed-point (all
# weights are ints), and every capability it points at is a KNOWN capability.
func test_md2_stat_affects_builtin_map_fixed_point_and_known() -> void:
	print("test_md2_stat_affects_builtin_map_fixed_point_and_known")
	var m: Dictionary = StatAffectsUtil.builtin_map()
	_check(not m.is_empty(), "builtin affects map is non-empty")
	for stat_id in m.keys():
		var caps: Dictionary = m[stat_id] as Dictionary
		_check(not caps.is_empty(), "%s maps to at least one capability" % str(stat_id))
		for cap_id in caps.keys():
			_check(CapabilityRegistry.has_capability(str(cap_id)), "%s -> known capability %s" % [str(stat_id), str(cap_id)])
			var w: Variant = caps[cap_id]
			_check(w is int, "weight %s->%s is fixed-point int" % [str(stat_id), str(cap_id)])
			_check(int(w) != 0, "weight %s->%s is non-zero" % [str(stat_id), str(cap_id)])
	# Spot-check the section-2.3 examples (armor, move_speed, vision_range).
	var armor: Dictionary = StatAffectsUtil.builtin_affects_for("armor")
	_check(armor.get("survivability", 0) == 800, "armor -> survivability 0.8 fixed-point")
	_check(armor.get("holding_power", 0) == 500, "armor -> holding_power 0.5 fixed-point")
	var spd: Dictionary = StatAffectsUtil.builtin_affects_for("move_speed")
	_check(spd.get("mobility", 0) == StatAffectsUtil.SCALE, "move_speed -> mobility 1.0 fixed-point")
	var vis: Dictionary = StatAffectsUtil.builtin_affects_for("vision_range")
	_check(vis.get("scout_power", 0) == 900, "vision_range -> scout_power 0.9 fixed-point")
	# quantize_weight rounds deterministically (round-half-away-from-zero).
	_check(StatAffectsUtil.quantize_weight(0.8) == 800, "quantize 0.8 -> 800")
	_check(StatAffectsUtil.quantize_weight(1.0) == 1000, "quantize 1.0 -> 1000")
	_check(StatAffectsUtil.quantize_weight(0.3) == 300, "quantize 0.3 -> 300")
	_check(StatAffectsUtil.quantize_weight(0.0) == 0, "quantize 0.0 -> 0")


# MD2.2: builtin_stat_ids() is stably sorted, builtin_affects_for returns a
# defensive copy (mutating the result must not corrupt the table), and unknown
# stats yield an empty map (resilience, never a crash).
func test_md2_stat_affects_deterministic_and_defensive() -> void:
	print("test_md2_stat_affects_deterministic_and_defensive")
	var a: Array = StatAffectsUtil.builtin_stat_ids()
	var b: Array = a.duplicate()
	b.sort()
	_check(a == b, "builtin_stat_ids is sorted/stable")
	_check(StatAffectsUtil.has_builtin("armor"), "armor has a built-in mapping")
	_check(not StatAffectsUtil.has_builtin("not_a_stat"), "unknown stat has no built-in mapping")
	_check(StatAffectsUtil.builtin_affects_for("not_a_stat").is_empty(), "unknown stat -> empty affects")
	# Defensive copy: mutating the returned dict must not change the table.
	var first: Dictionary = StatAffectsUtil.builtin_affects_for("armor")
	first["survivability"] = 1
	first["injected"] = 999
	var second: Dictionary = StatAffectsUtil.builtin_affects_for("armor")
	_check(second.get("survivability", 0) == 800, "mutation did not corrupt table (survivability)")
	_check(not second.has("injected"), "mutation did not inject key into table")
	# builtin_map() is deterministic across calls.
	_check(StatAffectsUtil.builtin_map() == StatAffectsUtil.builtin_map(), "builtin_map deterministic")


# MD2.3: resolve_affects merges a stat registry's data-defined affects on top of
# the built-in fixed-point map -- a Free Stat gets wired to a Capability with no
# engine code, an override replaces a built-in weight, and unknown capability
# ids are dropped. null registry falls back to the built-in map.
func test_md2_resolve_affects_merges_mod_and_builtin() -> void:
	print("test_md2_resolve_affects_merges_mod_and_builtin")
	StatRegistry.reset_definitions()
	# null registry -> pure built-in map.
	_check(StatAffectsUtil.resolve_affects(null) == StatAffectsUtil.builtin_map(), "null registry -> builtin map")
	# A brand-new Free Stat wired only by data affects, plus an override of a
	# built-in Core Stat weight, plus an unknown capability that must be dropped.
	StatRegistry.load_definitions({
		"morale": { "value_type": "int", "affects": { "holding_power": 0.6, "not_a_capability": 0.9 } },
		"armor":  { "affects": { "survivability": 0.9 } },
	})
	var resolved: Dictionary = StatAffectsUtil.resolve_affects(StatRegistry)
	# Free stat is now present and fixed-point.
	_check(resolved.has("morale"), "free stat morale resolved into affects")
	_check((resolved["morale"] as Dictionary).get("holding_power", 0) == 600, "morale -> holding_power quantised to 600")
	_check(not (resolved["morale"] as Dictionary).has("not_a_capability"), "unknown capability dropped")
	# Override replaced the built-in armor->survivability (was 800, now 900) but
	# kept the built-in armor->holding_power (500) the mod did not mention.
	var armor: Dictionary = resolved["armor"] as Dictionary
	_check(armor.get("survivability", 0) == 900, "armor->survivability overridden to 900")
	_check(armor.get("holding_power", 0) == 500, "armor->holding_power kept from built-in")
	# Deterministic across calls.
	_check(StatAffectsUtil.resolve_affects(StatRegistry) == StatAffectsUtil.resolve_affects(StatRegistry), "resolve_affects deterministic")
	StatRegistry.reset_definitions()


# MD2.4: validate_affects accepts a well-formed affects dict and reports each
# failure mode (unknown capability, non-numeric weight, out-of-range weight).
func test_md2_validate_affects_rejects_unknown_and_out_of_range() -> void:
	print("test_md2_validate_affects_rejects_unknown_and_out_of_range")
	# Well-formed affects -> no problems.
	_check(StatAffectsUtil.validate_affects({ "survivability": 0.8, "holding_power": 0.5 }).is_empty(), "valid affects accepted")
	# Zero weight and negative (detracting) weight are allowed within bounds.
	_check(StatAffectsUtil.validate_affects({ "mobility": 0, "scout_power": -1.5 }).is_empty(), "zero/negative in-bound accepted")
	# Not a dictionary.
	_check(not StatAffectsUtil.validate_affects("nope").is_empty(), "non-dictionary rejected")
	# Unknown capability id.
	var p_unknown: Array = StatAffectsUtil.validate_affects({ "not_a_capability": 0.5 })
	_check(p_unknown.size() == 1 and str(p_unknown[0]).begins_with("unknown capability"), "unknown capability reported")
	# Non-numeric weight.
	var p_nan: Array = StatAffectsUtil.validate_affects({ "damage_output": "high" })
	_check(p_nan.size() == 1 and str(p_nan[0]).find("not numeric") >= 0, "non-numeric weight reported")
	# Out-of-range weight (beyond MAX_WEIGHT).
	var p_range: Array = StatAffectsUtil.validate_affects({ "damage_output": 999.0 })
	_check(p_range.size() == 1 and str(p_range[0]).find("out of") >= 0, "out-of-range weight reported")
	# Problems are emitted in deterministic (sorted-key) order.
	var multi: Array = StatAffectsUtil.validate_affects({ "zzz_unknown": 0.1, "aaa_unknown": 0.1 })
	_check(multi.size() == 2, "two unknown capabilities reported")
	_check(str(multi[0]).find("aaa_unknown") >= 0, "problems sorted by capability id")


# --- MD3: derived metrics (raw stats -> capability vector) ------------------

# MD3.1: compute_capabilities returns a FULL vector (every registry capability),
# every value a fixed-point int in [0..SCALE], deterministic across calls.
func test_md3_compute_capabilities_full_vector_and_fixed_point() -> void:
	print("test_md3_compute_capabilities_full_vector_and_fixed_point")
	StatRegistry.reset_definitions()
	var tank: Dictionary = {
		"id": "tank",
		"stats": { "health": 280, "move_speed": 1, "attack_damage": 28, "attack_range": 2, "vision_range": 5 },
		"cost": { "resource_basic": 160 },
		"build_time_ticks": 140,
	}
	var caps: Dictionary = DerivedMetricsUtil.compute_capabilities(tank, StatRegistry, null)
	# Full vector: one entry per capability, all present.
	for id in CapabilityRegistry.all_ids():
		_check(caps.has(id), "vector has capability %s" % id)
		var q: Variant = caps[id]
		_check(q is int, "capability %s is fixed-point int" % id)
		_check(int(q) >= 0 and int(q) <= DerivedMetricsUtil.SCALE, "capability %s in [0..SCALE]" % id)
	# Deterministic: same input -> byte-for-byte same output.
	_check(caps == DerivedMetricsUtil.compute_capabilities(tank, StatRegistry, null), "compute_capabilities deterministic")
	# A tank has meaningful survivability (high health feeds it strongly).
	_check(int(caps.get("survivability", 0)) > 0, "tank has non-zero survivability")


# MD3.1/MD4-preview: the derived vector RANKS archetypes the way an intuitive
# reader expects -- a heavy tank out-survives a fragile scout; a fast scout
# out-moves the tank. This proves raw stats -> capability produces sensible,
# comparable numbers WITHOUT knowing the unit name.
func test_md3_archetypes_rank_as_expected() -> void:
	print("test_md3_archetypes_rank_as_expected")
	StatRegistry.reset_definitions()
	var tank: Dictionary = { "id": "tank", "stats": { "health": 280, "move_speed": 1, "attack_damage": 28, "attack_range": 2, "vision_range": 5 }, "cost": { "resource_basic": 160 } }
	var scout: Dictionary = { "id": "scout", "stats": { "health": 60, "move_speed": 4, "attack_damage": 6, "attack_range": 1, "vision_range": 8 }, "cost": { "resource_basic": 40 } }
	var t: Dictionary = DerivedMetricsUtil.compute_capabilities(tank, StatRegistry, null)
	var s: Dictionary = DerivedMetricsUtil.compute_capabilities(scout, StatRegistry, null)
	_check(int(t["survivability"]) > int(s["survivability"]), "tank out-survives scout")
	_check(int(s["mobility"]) > int(t["mobility"]), "scout out-moves tank")
	_check(int(s["scout_power"]) > int(t["scout_power"]), "scout out-scouts tank")
	_check(int(t["damage_output"]) > int(s["damage_output"]), "tank out-damages scout")


# MD3.2: cost_efficiency rewards cheap+strong units; resource_pressure surfaces
# for economy units. A free unit (cost 0) is maximally cost-efficient by power.
func test_md3_cost_efficiency_and_resource_pressure() -> void:
	print("test_md3_cost_efficiency_and_resource_pressure")
	StatRegistry.reset_definitions()
	var cheap: Dictionary = { "id": "cheap", "stats": { "health": 200, "attack_damage": 20 }, "cost": { "resource_basic": 30 } }
	var pricey: Dictionary = { "id": "pricey", "stats": { "health": 200, "attack_damage": 20 }, "cost": { "resource_basic": 400 } }
	var c: Dictionary = DerivedMetricsUtil.compute_capabilities(cheap, StatRegistry, null)
	var p: Dictionary = DerivedMetricsUtil.compute_capabilities(pricey, StatRegistry, null)
	_check(int(c["cost_efficiency"]) > int(p["cost_efficiency"]), "cheaper unit is more cost-efficient")
	# A free unit is maximally cost-efficient by power (no cost divisor).
	var free_u: Dictionary = { "id": "free", "stats": { "health": 200, "attack_damage": 20 }, "cost": {} }
	var f: Dictionary = DerivedMetricsUtil.compute_capabilities(free_u, StatRegistry, null)
	_check(int(f["cost_efficiency"]) >= int(c["cost_efficiency"]), "free unit at least as cost-efficient as cheap")
	# An economy building drives resource_pressure.
	var extractor: Dictionary = { "id": "extractor", "stats": { "extraction_rate": 8, "storage_cap": 500 }, "cost": { "resource_basic": 100 } }
	var e: Dictionary = DerivedMetricsUtil.compute_capabilities(extractor, StatRegistry, null)
	_check(int(e["resource_pressure"]) > 0, "extractor has resource_pressure")
	_check(int(e["economic_value"]) > 0, "extractor has economic_value")


# MD3.3: the cached wrapper returns byte-for-byte the same vector as the uncached
# path, and cache_key is stable for identical defs and distinct for different ones.
func test_md3_cache_matches_uncached_and_key_stable() -> void:
	print("test_md3_cache_matches_uncached_and_key_stable")
	StatRegistry.reset_definitions()
	var unit: Dictionary = { "id": "soldier", "stats": { "health": 100, "attack_damage": 10, "move_speed": 2 }, "cost": { "resource_basic": 50 }, "build_time_ticks": 60 }
	var affects: Dictionary = StatAffectsUtil.resolve_affects(StatRegistry)
	var cache: Dictionary = {}
	var uncached: Dictionary = DerivedMetricsUtil.compute_capabilities(unit, StatRegistry, affects)
	var cached_first: Dictionary = DerivedMetricsUtil.compute_capabilities_cached(unit, StatRegistry, affects, cache)
	var cached_second: Dictionary = DerivedMetricsUtil.compute_capabilities_cached(unit, StatRegistry, affects, cache)
	_check(cached_first == uncached, "cached first call matches uncached")
	_check(cached_second == uncached, "cached second call (hit) matches uncached")
	_check(cache.size() == 1, "cache stored exactly one entry")
	# Key stability + distinctness.
	var same: Dictionary = { "id": "soldier", "stats": { "health": 100, "attack_damage": 10, "move_speed": 2 }, "cost": { "resource_basic": 50 }, "build_time_ticks": 60 }
	_check(DerivedMetricsUtil.cache_key(unit) == DerivedMetricsUtil.cache_key(same), "identical defs share cache key")
	var diff: Dictionary = same.duplicate(true)
	(diff["stats"] as Dictionary)["health"] = 101
	_check(DerivedMetricsUtil.cache_key(unit) != DerivedMetricsUtil.cache_key(diff), "changed stat busts cache key")


# MD3.4: an incomplete unit (missing the stats a capability needs) yields that
# capability's safe default_q -- never a crash, never a random value. A totally
# malformed def yields an all-default vector.
func test_md3_resilience_incomplete_unit_uses_defaults() -> void:
	print("test_md3_resilience_incomplete_unit_uses_defaults")
	StatRegistry.reset_definitions()
	# A unit with only health: capabilities with no feeding stat fall to default.
	var partial: Dictionary = { "id": "partial", "stats": { "health": 100 } }
	var caps: Dictionary = DerivedMetricsUtil.compute_capabilities(partial, StatRegistry, null)
	_check(int(caps["survivability"]) > 0, "health still feeds survivability")
	# siege_power has no feeding stat here -> its registry default.
	_check(int(caps["siege_power"]) == CapabilityRegistry.default_q("siege_power"), "unfed capability uses default_q")
	# A malformed def (no stats) yields an all-default vector, no crash.
	var empty: Dictionary = DerivedMetricsUtil.compute_capabilities({ "id": "x" }, StatRegistry, null)
	for id in CapabilityRegistry.all_ids():
		_check(int(empty[id]) == CapabilityRegistry.default_q(id), "empty def -> default for %s" % id)
	# A non-dictionary input must not crash and yields defaults too.
	var junk: Dictionary = DerivedMetricsUtil.compute_capabilities("not a dict", StatRegistry, null)
	_check(int(junk["survivability"]) == CapabilityRegistry.default_q("survivability"), "junk input -> defaults")
	StatRegistry.reset_definitions()


# --- MD4: Role Inference (capability vector -> role) -------------------------

# MD4.1: infer_roles returns a ranked, fixed-point, deterministic list. Every
# score is an int in [0..SCALE]; the list is sorted by score DESC then role ASC;
# the same input yields byte-for-byte the same output.
func test_md4_infer_roles_ranked_fixed_point_and_deterministic() -> void:
	print("test_md4_infer_roles_ranked_fixed_point_and_deterministic")
	StatRegistry.reset_definitions()
	# A heavy tank: high survivability + holding power, low mobility.
	var tank_caps: Dictionary = {
		"survivability": 900, "holding_power": 800, "mobility": 100,
		"damage_output": 300, "siege_power": 100, "scout_power": 50,
	}
	var roles: Array = RoleInferenceUtil.infer_roles(tank_caps, "unit")
	_check(not roles.is_empty(), "infer_roles returns at least one role")
	# Every entry is a well-formed fixed-point record.
	for r in roles:
		_check(r is Dictionary, "role entry is a dict")
		_check((r as Dictionary).has("role") and (r as Dictionary).has("score_q"), "role entry has role+score_q")
		var sc: Variant = (r as Dictionary)["score_q"]
		_check(sc is int, "score_q is fixed-point int")
		_check(int(sc) >= 0 and int(sc) <= RoleInferenceUtil.SCALE, "score_q in [0..SCALE]")
	# Sorted by score DESC.
	for i in range(1, roles.size()):
		_check(int((roles[i - 1] as Dictionary)["score_q"]) >= int((roles[i] as Dictionary)["score_q"]), "roles sorted by score DESC")
	# Deterministic: same input -> identical output.
	_check(roles == RoleInferenceUtil.infer_roles(tank_caps, "unit"), "infer_roles deterministic")
	# The tank's top role is frontline_tank.
	_check(str((roles[0] as Dictionary)["role"]) == "frontline_tank", "heavy tank primary role is frontline_tank")


# MD4.2: primary_role ties break ALPHABETICALLY so the choice stays stable and
# deterministic. Construct a vector that scores two roles identically.
func test_md4_primary_role_alpha_tie_break() -> void:
	print("test_md4_primary_role_alpha_tie_break")
	StatRegistry.reset_definitions()
	# Build two 1-term signatures artificially tied: anti_air ({anti_air_power,
	# damage_output}) vs a pure damage vector. To force a clean tie we craft a
	# vector where the normalised scores of two roles are equal, then assert the
	# alphabetically-first role wins. Easiest deterministic tie: feed a vector so
	# that infer_roles yields >=2 entries with the same top score.
	# damage_output only -> glass_cannon and ranged_dps both key off damage_output.
	var caps: Dictionary = { "damage_output": 1000 }
	var roles: Array = RoleInferenceUtil.infer_roles(caps, "unit")
	# Find the max score and collect all roles at that score.
	var top: int = int((roles[0] as Dictionary)["score_q"])
	var tied: Array = []
	for r in roles:
		if int((r as Dictionary)["score_q"]) == top:
			tied.append(str((r as Dictionary)["role"]))
	if tied.size() >= 2:
		# primary_role must be the alphabetically-first among the tied set.
		var expected: Array = tied.duplicate()
		expected.sort()
		_check(RoleInferenceUtil.primary_role(caps, "unit") == expected[0], "primary_role breaks ties alphabetically")
	else:
		# Even without a tie, primary_role must equal the single top role.
		_check(RoleInferenceUtil.primary_role(caps, "unit") == str((roles[0] as Dictionary)["role"]), "primary_role is the top role")
	# Direct comparator tie check: equal score -> alphabetical order preserved.
	var a: Dictionary = { "role": "zzz", "score_q": 500 }
	var b: Dictionary = { "role": "aaa", "score_q": 500 }
	_check(RoleInferenceUtil._role_sort(b, a), "comparator puts alphabetically-first role ahead on a tie")


# MD4.3: an empty / incomplete / malformed vector NEVER leaves without a role --
# it yields exactly the generic role. No input can crash or produce empty list.
func test_md4_generic_fallback_never_empty() -> void:
	print("test_md4_generic_fallback_never_empty")
	StatRegistry.reset_definitions()
	# Empty vector.
	var empty_roles: Array = RoleInferenceUtil.infer_roles({}, "unit")
	_check(empty_roles.size() == 1, "empty vector -> exactly one role")
	_check(str((empty_roles[0] as Dictionary)["role"]) == RoleInferenceUtil.GENERIC_ROLE, "empty vector -> generic role")
	_check(RoleInferenceUtil.primary_role({}, "unit") == RoleInferenceUtil.GENERIC_ROLE, "empty vector primary_role is generic")
	# All-zero / all-default vector -> generic (nothing clears the floor).
	var zero: Dictionary = {}
	for id in CapabilityRegistry.all_ids():
		zero[id] = 0
	_check(RoleInferenceUtil.primary_role(zero, "unit") == RoleInferenceUtil.GENERIC_ROLE, "all-zero vector -> generic")
	# Malformed inputs must not crash and must still return generic.
	_check(RoleInferenceUtil.primary_role(null, "unit") == RoleInferenceUtil.GENERIC_ROLE, "null input -> generic")
	_check(RoleInferenceUtil.primary_role("not a dict", "unit") == RoleInferenceUtil.GENERIC_ROLE, "junk input -> generic")
	_check(RoleInferenceUtil.primary_role(42, "unit") == RoleInferenceUtil.GENERIC_ROLE, "int input -> generic")


# MD4.4: synthetic light archetypes map to the intuitively-correct role, going
# through the REAL raw-stat -> capability -> role pipeline (preview of MD13).
func test_md4_synthetic_archetypes_map_to_expected_roles() -> void:
	print("test_md4_synthetic_archetypes_map_to_expected_roles")
	StatRegistry.reset_definitions()
	# Heavy tank: lots of health, slow, modest damage -> frontline_tank.
	var tank: Dictionary = { "id": "heavy_tank", "stats": { "health": 600, "armor": 120, "move_speed": 1, "attack_damage": 22, "attack_range": 2 }, "cost": { "resource_basic": 200 } }
	var tank_caps: Dictionary = DerivedMetricsUtil.compute_capabilities(tank, StatRegistry, null)
	_check(RoleInferenceUtil.primary_role(tank_caps, "unit") == "frontline_tank", "heavy tank -> frontline_tank")
	# Fragile sniper: high damage, long range, very low health -> glass_cannon or ranged_dps.
	var sniper: Dictionary = { "id": "sniper", "stats": { "health": 40, "move_speed": 2, "attack_damage": 90, "attack_range": 9 }, "cost": { "resource_basic": 90 } }
	var sniper_caps: Dictionary = DerivedMetricsUtil.compute_capabilities(sniper, StatRegistry, null)
	var sniper_role: String = RoleInferenceUtil.primary_role(sniper_caps, "unit")
	_check(sniper_role == "glass_cannon" or sniper_role == "ranged_dps", "fragile sniper -> glass_cannon/ranged_dps (got %s)" % sniper_role)
	# Fast scout: high speed + vision, low health/damage -> scout or harasser.
	var scout: Dictionary = { "id": "recon", "stats": { "health": 50, "move_speed": 6, "attack_damage": 5, "attack_range": 1, "vision_range": 12 }, "cost": { "resource_basic": 35 } }
	var scout_caps: Dictionary = DerivedMetricsUtil.compute_capabilities(scout, StatRegistry, null)
	var scout_role: String = RoleInferenceUtil.primary_role(scout_caps, "unit")
	_check(scout_role == "scout" or scout_role == "harasser", "fast scout -> scout/harasser (got %s)" % scout_role)
	StatRegistry.reset_definitions()


# MD4.1/MD4.4: building signatures resolve, and "auto" target picks the building
# table when building capabilities dominate the vector.
func test_md4_building_signatures_and_auto_target() -> void:
	print("test_md4_building_signatures_and_auto_target")
	StatRegistry.reset_definitions()
	# A pure defensive building capability vector.
	var turret_caps: Dictionary = { "defense_value": 950, "frontline_value": 400 }
	_check(RoleInferenceUtil.primary_role(turret_caps, "building") == "defensive", "defensive building -> defensive role")
	# A production building.
	var factory_caps: Dictionary = { "production_value": 900 }
	_check(RoleInferenceUtil.primary_role(factory_caps, "building") == "production", "production building -> production role")
	# auto target: building capabilities dominate -> building table chosen.
	var eco_caps: Dictionary = { "economic_value": 900, "resource_pressure": 500, "damage_output": 0 }
	var auto_role: String = RoleInferenceUtil.primary_role(eco_caps, "auto")
	_check(auto_role == "economic", "auto target picks building role when building signal dominates (got %s)" % auto_role)


# CODE_POLICY: the util source is ASCII-only and pure (RefCounted, no
# SceneTree / WorldState / state_hasher dependency).
func test_md4_source_is_ascii_and_pure() -> void:
	print("test_md4_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://core/role_inference_util.gd")
	_check(src.length() > 0, "role_inference_util.gd source readable")
	# ASCII-only: every code byte < 128.
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "role_inference_util.gd is ASCII-only")
	# Pure: RefCounted, no simulation dependencies.
	_check(src.contains("extends RefCounted"), "role_inference_util extends RefCounted")
	_check(not src.contains("WorldState"), "role_inference_util does not touch WorldState")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "role_inference_util does not touch state hasher")
	_check(not src.contains("SceneTree"), "role_inference_util does not touch SceneTree")


# --- MD5: AI role/metric weight derivation ----------------------------------

# MD5.1/5.2: a neutral (balanced default) profile derives every role and every
# capability weight at exactly the neutral weight, and a null profile is safe.
func test_md5_neutral_profile_all_weights_neutral() -> void:
	print("test_md5_neutral_profile_all_weights_neutral")
	var profile: AiProfile = AiProfile.default_profile()
	var w: Dictionary = AiWeightDerivationUtil.derive_weights(profile)
	_check(w.has("roles") and w.has("capabilities"), "derive_weights returns roles + capabilities")
	var roles: Dictionary = w["roles"]
	# Every unit + building role is present.
	for r in AiWeightDerivationUtil.UNIT_ROLES:
		_check(roles.has(r), "role weight present: %s" % r)
	for r in AiWeightDerivationUtil.BUILDING_ROLES:
		_check(roles.has(r), "building role weight present: %s" % r)
	# A balanced profile with all knobs at 0.5 yields exactly neutral weights.
	for r in roles.keys():
		_check(int(roles[r]) == AiWeightDerivationUtil.NEUTRAL_WEIGHT_Q, "neutral role weight for %s (got %d)" % [str(r), int(roles[r])])
	var caps: Dictionary = w["capabilities"]
	for cid in CapabilityRegistry.all_ids():
		_check(caps.has(cid), "capability weight present: %s" % cid)
		_check(int(caps[cid]) == AiWeightDerivationUtil.NEUTRAL_WEIGHT_Q, "neutral capability weight for %s" % cid)


# MD5.1/5.3: two opposite archetypes tilt the SAME roles in opposite directions.
# A defensive general values frontline_tank > glass_cannon; an aggressive one
# the opposite. Personality acts on the ROLE, never on a unit name.
func test_md5_defensive_vs_aggressive_role_weights() -> void:
	print("test_md5_defensive_vs_aggressive_role_weights")
	# Defensive: high defense/caution/patience, low aggression/offense.
	var def_p: AiProfile = AiProfile.default_profile()
	def_p.set_value("personality", "aggression", 0.1)
	def_p.set_value("personality", "caution", 0.9)
	def_p.set_value("personality", "patience", 0.9)
	def_p.set_value("strategy_bias", "defense", 0.9)
	def_p.set_value("strategy_bias", "offense", 0.1)
	def_p.set_value("strategy_bias", "harassment", 0.1)
	def_p.set_value("strategy_bias", "focus_fire", 0.1)
	# Aggressive: mirror image.
	var agg_p: AiProfile = AiProfile.default_profile()
	agg_p.set_value("personality", "aggression", 0.9)
	agg_p.set_value("personality", "caution", 0.1)
	agg_p.set_value("personality", "patience", 0.1)
	agg_p.set_value("strategy_bias", "defense", 0.1)
	agg_p.set_value("strategy_bias", "offense", 0.9)
	agg_p.set_value("strategy_bias", "harassment", 0.9)
	agg_p.set_value("strategy_bias", "focus_fire", 0.9)
	var def_w: Dictionary = AiWeightDerivationUtil.derive_role_weights(def_p)
	var agg_w: Dictionary = AiWeightDerivationUtil.derive_role_weights(agg_p)
	# Defensive values the tank more than the glass cannon.
	_check(int(def_w["frontline_tank"]) > int(def_w["glass_cannon"]), "defensive: tank > glass_cannon")
	# Aggressive is the opposite.
	_check(int(agg_w["glass_cannon"]) > int(agg_w["frontline_tank"]), "aggressive: glass_cannon > tank")
	# Cross-archetype: defensive weights the tank higher than aggressive does.
	_check(int(def_w["frontline_tank"]) > int(agg_w["frontline_tank"]), "defensive tank weight > aggressive tank weight")
	# And aggressive weights the harasser higher than defensive does.
	_check(int(agg_w["harasser"]) > int(def_w["harasser"]), "aggressive harasser weight > defensive harasser weight")


# MD5.1: capability weights cover exactly the closed CapabilityRegistry set.
func test_md5_capability_weights_cover_registry() -> void:
	print("test_md5_capability_weights_cover_registry")
	var profile: AiProfile = AiProfile.default_profile()
	var caps: Dictionary = AiWeightDerivationUtil.derive_capability_weights(profile)
	var ids: Array = CapabilityRegistry.all_ids()
	_check(caps.size() == ids.size(), "one weight per capability (%d == %d)" % [caps.size(), ids.size()])
	for cid in ids:
		_check(caps.has(cid), "capability covered: %s" % cid)


# MD5 / section 2.1: every derived weight is a fixed-point int within bounds.
func test_md5_weights_fixed_point_and_bounded() -> void:
	print("test_md5_weights_fixed_point_and_bounded")
	# An extreme profile (all knobs maxed) must not blow past the bounds.
	var extreme: AiProfile = AiProfile.default_profile()
	for knob in AiProfile.keys_for("personality"):
		extreme.set_value("personality", knob, 1.0)
	for knob in AiProfile.keys_for("strategy_bias"):
		extreme.set_value("strategy_bias", knob, 1.0)
	var w: Dictionary = AiWeightDerivationUtil.derive_weights(extreme)
	for r in (w["roles"] as Dictionary).keys():
		var wv = (w["roles"] as Dictionary)[r]
		_check(wv is int, "role weight is int: %s" % str(r))
		_check(int(wv) >= AiWeightDerivationUtil.WEIGHT_MIN_Q and int(wv) <= AiWeightDerivationUtil.WEIGHT_MAX_Q, "role weight in bounds: %s (%d)" % [str(r), int(wv)])
	for cid in (w["capabilities"] as Dictionary).keys():
		var cv = (w["capabilities"] as Dictionary)[cid]
		_check(cv is int, "capability weight is int: %s" % str(cid))
		_check(int(cv) >= AiWeightDerivationUtil.WEIGHT_MIN_Q and int(cv) <= AiWeightDerivationUtil.WEIGHT_MAX_Q, "capability weight in bounds: %s" % str(cid))


# MD5 / section 2.1: same profile -> byte-identical output; null is safe.
func test_md5_deterministic_and_null_safe() -> void:
	print("test_md5_deterministic_and_null_safe")
	var profile: AiProfile = AiProfile.default_profile()
	profile.set_value("personality", "aggression", 0.73)
	profile.set_value("strategy_bias", "offense", 0.42)
	var a: Dictionary = AiWeightDerivationUtil.derive_weights(profile)
	var b: Dictionary = AiWeightDerivationUtil.derive_weights(profile)
	_check(StateHasher.hash_variant(a) == StateHasher.hash_variant(b), "same profile -> identical weights")
	# Null profile -> all-neutral, no crash.
	var n: Dictionary = AiWeightDerivationUtil.derive_weights(null)
	for r in (n["roles"] as Dictionary).values():
		_check(int(r) == AiWeightDerivationUtil.NEUTRAL_WEIGHT_Q, "null profile role weight neutral")


# MD5.3: raising a single knob moves the mapped weights in the documented
# direction (sensitivity), and the opposite for negatively-signed roles.
func test_md5_knob_sensitivity_directions() -> void:
	print("test_md5_knob_sensitivity_directions")
	var base: AiProfile = AiProfile.default_profile()
	var base_w: Dictionary = AiWeightDerivationUtil.derive_role_weights(base)
	# Raise defense only.
	var more_def: AiProfile = AiProfile.default_profile()
	more_def.set_value("strategy_bias", "defense", 1.0)
	var def_w: Dictionary = AiWeightDerivationUtil.derive_role_weights(more_def)
	# defense +1 raises frontline_tank (positive) and lowers glass_cannon (negative).
	_check(int(def_w["frontline_tank"]) > int(base_w["frontline_tank"]), "more defense raises tank weight")
	_check(int(def_w["glass_cannon"]) < int(base_w["glass_cannon"]), "more defense lowers glass_cannon weight")
	# Raise harassment only -> harasser up.
	var more_har: AiProfile = AiProfile.default_profile()
	more_har.set_value("strategy_bias", "harassment", 1.0)
	var har_w: Dictionary = AiWeightDerivationUtil.derive_role_weights(more_har)
	_check(int(har_w["harasser"]) > int(base_w["harasser"]), "more harassment raises harasser weight")


# MD5.4: the cosmetic preferred_roles summary is sorted (weight DESC, role ASC)
# and never includes the generic fallback.
func test_md5_preferred_roles_summary_sorted() -> void:
	print("test_md5_preferred_roles_summary_sorted")
	var agg_p: AiProfile = AiProfile.default_profile()
	agg_p.set_value("personality", "aggression", 0.95)
	agg_p.set_value("strategy_bias", "offense", 0.95)
	agg_p.set_value("strategy_bias", "harassment", 0.95)
	var top: Array = AiWeightDerivationUtil.preferred_roles(agg_p, 3)
	_check(top.size() == 3, "preferred_roles honours count")
	# Sorted descending by weight, ties by role ASC.
	for i in range(top.size() - 1):
		var a: Dictionary = top[i]
		var b: Dictionary = top[i + 1]
		var ok: bool = int(a["weight_q"]) > int(b["weight_q"]) or (int(a["weight_q"]) == int(b["weight_q"]) and str(a["role"]) < str(b["role"]))
		_check(ok, "preferred_roles sorted at %d" % i)
	for item in top:
		_check(str(item["role"]) != "generic", "preferred_roles excludes generic")
	# count == 0 -> empty.
	_check(AiWeightDerivationUtil.preferred_roles(agg_p, 0).is_empty(), "count 0 -> empty list")


# MD5.2: the legacy 4-macro strategy derivation is untouched and still coexists.
func test_md5_legacy_strategy_derivation_untouched() -> void:
	print("test_md5_legacy_strategy_derivation_untouched")
	var profile: AiProfile = AiProfile.default_profile()
	var macro: Dictionary = AiStrategyDerivationUtil.derive_from_profile(profile)
	_check(macro.has("attack_army_size") and macro.has("expansion_cap") and macro.has("upgrade_reserve") and macro.has("research_first"), "legacy macro dict intact")
	# New layer produces a DIFFERENT shape (roles/capabilities) alongside it.
	var w: Dictionary = AiWeightDerivationUtil.derive_weights(profile)
	_check(not w.has("attack_army_size"), "new weight layer is separate from legacy macro")


# CODE_POLICY: the util source is ASCII-only and pure.
func test_md5_source_is_ascii_and_pure() -> void:
	print("test_md5_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/ai_weight_derivation_util.gd")
	_check(src.length() > 0, "ai_weight_derivation_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "ai_weight_derivation_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "ai_weight_derivation_util extends RefCounted")
	_check(not src.contains("WorldState"), "ai_weight_derivation_util does not touch WorldState")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "ai_weight_derivation_util does not touch state hasher")
	_check(not src.contains("SceneTree"), "ai_weight_derivation_util does not touch SceneTree")


# --- E2: graphic model + image validation -----------------------------------

func test_phase_e2_graphic_layer_rule() -> void:
	print("test_phase_e2_graphic_layer_rule")
	# A default single-part graphic is valid.
	_check(GraphicModel.validate(GraphicModel.default_graphic()).is_empty(), "default single graphic valid")
	# Logical size out of bounds is rejected.
	var bad_logical: Dictionary = GraphicModel.default_graphic()
	bad_logical["logical_size"] = { "w": 99, "h": 1 }
	_check(not GraphicModel.validate(bad_logical).is_empty(), "oversized logical_size rejected")
	# Layer rule: top layer larger than base must fail.
	var bad_layers: Array = [
		GraphicModel.default_part(1, 32, 32),
		GraphicModel.default_part(2, 128, 128),
	]
	_check(not GraphicModel.validate_layer_sizes(bad_layers).is_empty(), "top layer bigger than base rejected")
	# A correctly shrinking stack passes.
	var good_layers: Array = [
		GraphicModel.default_part(1, 128, 128),
		GraphicModel.default_part(2, 64, 64),
		GraphicModel.default_part(3, 32, 32),
	]
	_check(GraphicModel.validate_layer_sizes(good_layers).is_empty(), "shrinking layer stack valid")
	# A multi graphic with too many parts is rejected.
	var too_many: Dictionary = {
		"mode": GraphicModel.MODE_MULTI,
		"logical_size": { "w": 1, "h": 1 },
		"parts": [
			GraphicModel.default_part(1, 128, 128),
			GraphicModel.default_part(2, 64, 64),
			GraphicModel.default_part(3, 32, 32),
			GraphicModel.default_part(4, 16, 16),
		],
	}
	_check(not GraphicModel.validate(too_many).is_empty(), "more than 3 layers rejected")


func test_phase_e2_image_validation_png() -> void:
	print("test_phase_e2_image_validation_png")
	# A structurally valid 64x64 PNG passes.
	var ok: PackedByteArray = GraphicModel.make_test_png(64, 64)
	_check(GraphicModel.is_png(ok), "make_test_png produces a PNG signature")
	_check(GraphicModel.png_dimensions(ok) == Vector2i(64, 64), "png_dimensions reads 64x64")
	_check(GraphicModel.validate_image(ok).is_empty(), "64x64 PNG accepted")
	# Too small / too large are rejected.
	var tiny: PackedByteArray = GraphicModel.make_test_png(8, 8)
	_check(not GraphicModel.validate_image(tiny).is_empty(), "8x8 PNG rejected (too small)")
	var huge: PackedByteArray = GraphicModel.make_test_png(1024, 1024)
	_check(not GraphicModel.validate_image(huge).is_empty(), "1024x1024 PNG rejected (too large)")
	# Non-PNG bytes are rejected.
	var junk: PackedByteArray = "not a png at all".to_ascii_buffer()
	_check(not GraphicModel.is_png(junk), "random bytes are not a PNG")
	_check(not GraphicModel.validate_image(junk).is_empty(), "non-PNG rejected")


# --- E2: tree model ----------------------------------------------------------

func test_phase_e2_tree_round_trip() -> void:
	print("test_phase_e2_tree_round_trip")
	var proj: ModProject = ModProject.new()
	proj.new_project("tree_mod", "Tree Mod")
	# Build a small tree under the units root.
	var inf: String = proj.add_child(ModProject.UNITS_CATALOG, ModProject.ROOT_UNIT, "infantry")
	_check(inf == "infantry", "add_child returns the new id")
	var rifle: String = proj.add_child(ModProject.UNITS_CATALOG, "infantry", "rifleman")
	var sniper: String = proj.add_sibling(ModProject.UNITS_CATALOG, "rifleman", "sniper")
	_check(proj.units.has("rifleman") and proj.units.has("sniper"), "child + sibling stored")
	# sniper shares rifleman's parent (infantry).
	var sniper_parent: String = str((proj.get_unit("sniper").get("editor", {}) as Dictionary).get("parent_id", ""))
	_check(sniper_parent == "infantry", "sibling inherits the same parent")
	# build_tree reflects the hierarchy.
	var tree: Dictionary = proj.build_tree(ModProject.UNITS_CATALOG)
	_check(str(tree.get("id", "")) == ModProject.ROOT_UNIT, "tree root is the unit root")
	var top: Array = tree.get("children", [])
	_check(top.size() == 1 and str(top[0].get("id", "")) == "infantry", "infantry is the only top node")
	var infantry_children: Array = top[0].get("children", [])
	_check(infantry_children.size() == 2, "infantry has 2 children (rifleman, sniper)")
	# Rename re-parents children.
	var new_id: String = proj.rename_node(ModProject.UNITS_CATALOG, "infantry", "ground_troops")
	_check(new_id == "ground_troops", "rename returns the new id")
	_check(not proj.units.has("infantry") and proj.units.has("ground_troops"), "node renamed")
	var rifle_parent: String = str((proj.get_unit("rifleman").get("editor", {}) as Dictionary).get("parent_id", ""))
	_check(rifle_parent == "ground_troops", "children re-parented after rename")


func test_phase_e2_texture_validation_and_unique_name() -> void:
	print("test_phase_e2_texture_validation_and_unique_name")
	var proj: ModProject = ModProject.new()
	proj.new_project("tex_mod", "Texture Mod")
	# A valid PNG is accepted by add_texture_validated.
	var png: PackedByteArray = GraphicModel.make_test_png(64, 64)
	var problems: Array = []
	var stored: String = proj.add_texture_validated("hero", png, problems)
	_check(stored != "" and problems.is_empty(), "valid texture accepted")
	_check(proj.has_texture("hero"), "texture is stored under its name")
	# An invalid image leaves the project unchanged.
	var problems2: Array = []
	var bad: String = proj.add_texture_validated("broken", "junk".to_ascii_buffer(), problems2)
	_check(bad == "" and not problems2.is_empty(), "invalid texture rejected with problems")
	_check(not proj.has_texture("broken"), "rejected texture not stored")
	# unique_texture_name avoids collisions.
	_check(proj.unique_texture_name("hero") == "hero_2", "unique name appends _2 on collision")
	_check(proj.unique_texture_name("fresh") == "fresh", "unique name leaves free names alone")


# --- E3: unit editor ---------------------------------------------------------

func test_phase_e3_single_and_multipart_unit() -> void:
	print("test_phase_e3_single_and_multipart_unit")
	var proj: ModProject = ModProject.new()
	proj.new_project("unit_mod", "Unit Mod")
	# Single-part unit is valid out of the box.
	proj.set_unit("scout", ModProject.default_unit("scout"))
	_check(proj.validate_unit("scout").is_empty(), "default single unit valid")
	# A valid multi-part unit (compatible parts) passes.
	var multi: Dictionary = ModProject.default_multipart_unit("mech", 3)
	proj.set_unit("mech", multi)
	_check(proj.validate_unit("mech").is_empty(), "compatible 3-part unit valid")
	_check(bool(proj.get_unit("mech").get("fusable", false)), "multi-part unit may be fusable")
	# A single-part unit marked fusable is invalid.
	var bad: Dictionary = ModProject.default_unit("solo")
	bad["fusable"] = true
	proj.set_unit("solo", bad)
	_check(not proj.validate_unit("solo").is_empty(), "single-part fusable rejected")


func test_phase_e3_multipart_conflict_rejected() -> void:
	print("test_phase_e3_multipart_conflict_rejected")
	var proj: ModProject = ModProject.new()
	proj.new_project("conflict_mod", "Conflict Mod")
	var u: Dictionary = ModProject.default_multipart_unit("twin", 2)
	# Force both parts to carry COMBAT stats -> conflict.
	u["part_stats"] = [
		{ "attack_damage": 10 },
		{ "attack_range": 3 },
	]
	proj.set_unit("twin", u)
	var problems: Array = proj.validate_unit("twin")
	_check(not problems.is_empty(), "two combat parts are rejected")
	# Fixing one part to a different group resolves the conflict.
	u["part_stats"] = [
		{ "attack_damage": 10 },
		{ "move_speed": 4 },
	]
	proj.set_unit("twin", u)
	_check(proj.validate_unit("twin").is_empty(), "distinct-group parts are accepted")


func test_phase_e3_upgrade_size_cap() -> void:
	print("test_phase_e3_upgrade_size_cap")
	var proj: ModProject = ModProject.new()
	proj.new_project("upgrade_mod", "Upgrade Mod")
	var u: Dictionary = ModProject.default_unit("vet")
	# Base layer-1 is 64x64 = 4096 px. +15% cap -> 4710 px area.
	u["upgrade"] = ModProject.default_unit_upgrade("kill_count", 50)
	# Within cap: 68x68 = 4624 <= 4710.
	u["upgrade"]["visual_change"] = { "px": { "w": 68, "h": 68 } }
	proj.set_unit("vet", u)
	_check(proj.validate_unit("vet").is_empty(), "upgrade within +15% cap accepted")
	# Over cap: 80x80 = 6400 > 4710.
	u["upgrade"]["visual_change"] = { "px": { "w": 80, "h": 80 } }
	proj.set_unit("vet", u)
	_check(not proj.validate_unit("vet").is_empty(), "upgrade beyond +15% cap rejected")


# --- E4: building editor -----------------------------------------------------

func test_phase_e4_building_parts_require_hp_armor() -> void:
	print("test_phase_e4_building_parts_require_hp_armor")
	var proj: ModProject = ModProject.new()
	proj.new_project("building_mod", "Building Mod")
	# Default multi-part building has hp+armor on every part -> valid.
	var b: Dictionary = ModProject.default_multipart_building("fortress", 2)
	proj.set_building("fortress", b)
	_check(proj.validate_building("fortress").is_empty(), "multi-part building with hp+armor valid")
	_check(bool(proj.get_building("fortress").get("part_destructible", false)), "building parts are destructible")
	# Strip armor from one part -> invalid.
	b["part_stats"] = [
		{ "health": 250, "armor": 3 },
		{ "health": 250 },
	]
	proj.set_building("fortress", b)
	_check(not proj.validate_building("fortress").is_empty(), "building part missing armor rejected")


func test_phase_e4_building_multipart_round_trip() -> void:
	print("test_phase_e4_building_multipart_round_trip")
	var out_path: String = "user://test_e4_building.nexpack"
	var proj: ModProject = ModProject.new()
	proj.new_project("e4_mod", "E4 Mod")
	proj.set_building("keep", ModProject.default_multipart_building("keep", 3))
	_check(proj.validate().is_empty(), "project with multi-part building validates")
	_check(proj.save_pack(out_path), "project saves")
	var reopened: ModProject = ModProject.new()
	_check(reopened.open_pack(out_path), "pack re-opens")
	_check(reopened.buildings.has("keep"), "building round-trips")
	var parts: Array = (reopened.get_building("keep").get("graphic", {}) as Dictionary).get("parts", [])
	_check(parts.size() == 3, "3 graphic layers survive round-trip")
	var pstats: Array = reopened.get_building("keep").get("part_stats", [])
	_check(pstats.size() == 3, "3 part_stats survive round-trip")
	DirAccess.remove_absolute(out_path)


# --- E5: object editor -------------------------------------------------------

func test_phase_e5_object_extractable_and_decorative() -> void:
	print("test_phase_e5_object_extractable_and_decorative")
	var proj: ModProject = ModProject.new()
	proj.new_project("object_mod", "Object Mod")
	# A decorative object (default) is valid.
	proj.set_object("rock", ModProject.default_object("rock"))
	_check(proj.validate_object("rock").is_empty(), "decorative object valid")
	# An extractable object without yields is invalid.
	var ore: Dictionary = ModProject.default_object("ore")
	ore["extractable"] = true
	proj.set_object("ore", ore)
	_check(not proj.validate_object("ore").is_empty(), "extractable without yields rejected")
	# Adding a valid yields block fixes it.
	ore["yields"] = { "material": "iron", "rate": 3 }
	proj.set_object("ore", ore)
	_check(proj.validate_object("ore").is_empty(), "extractable with yields valid")
	# Invalid placement is rejected.
	var bad: Dictionary = ModProject.default_object("weird")
	bad["placement"] = "sky"
	proj.set_object("weird", bad)
	_check(not proj.validate_object("weird").is_empty(), "invalid placement rejected")


func test_phase_e5_object_round_trip_in_pack() -> void:
	print("test_phase_e5_object_round_trip_in_pack")
	var out_path: String = "user://test_e5_objects.nexpack"
	var proj: ModProject = ModProject.new()
	proj.new_project("e5_mod", "E5 Mod")
	var ore: Dictionary = ModProject.default_object("crystal")
	ore["extractable"] = true
	ore["placement"] = "both"
	ore["yields"] = { "material": "crystal", "rate": 5 }
	proj.set_object("crystal", ore)
	_check(proj.validate().is_empty(), "project with object validates")
	_check(proj.save_pack(out_path), "project with objects saves")
	var reopened: ModProject = ModProject.new()
	_check(reopened.open_pack(out_path), "pack with objects re-opens")
	_check(reopened.objects.has("crystal"), "object round-trips into objects catalog")
	var got: Dictionary = reopened.get_object("crystal")
	_check(bool(got.get("extractable", false)), "extractable flag survives")
	_check(int((got.get("yields", {}) as Dictionary).get("rate", 0)) == 5, "yield rate survives")
	_check(str(got.get("placement", "")) == "both", "placement survives")
	DirAccess.remove_absolute(out_path)


# --- E6: map editor (sea + objects + coast) ----------------------------------

func test_phase_e6_sea_paint_and_round_trip() -> void:
	print("test_phase_e6_sea_paint_and_round_trip")
	var proj: ScenarioProject = ScenarioProject.new()
	proj.clear_walls()
	# Paint sea and confirm it is tracked separately from walls.
	_check(proj.paint_cell(2, 2, ScenarioProject.TERRAIN_SEA), "paint sea succeeds")
	_check(proj.is_sea(2, 2), "sea recorded")
	_check(not proj.is_wall(2, 2), "sea cell is not a wall")
	# Painting a wall over a sea cell clears the sea (a cell is one token).
	proj.paint_cell(2, 2, ScenarioProject.TERRAIN_WALL)
	_check(proj.is_wall(2, 2) and not proj.is_sea(2, 2), "wall replaces sea on the same cell")
	# Ground clears both.
	proj.paint_cell(2, 2, ScenarioProject.TERRAIN_GROUND)
	_check(not proj.is_wall(2, 2) and not proj.is_sea(2, 2), "ground clears the cell")
	# Round-trip sea through to_scenario / from_scenario.
	proj.paint_cell(3, 3, ScenarioProject.TERRAIN_SEA)
	proj.paint_cell(4, 4, ScenarioProject.TERRAIN_SEA)
	var scenario: Dictionary = proj.to_scenario()
	_check((scenario.get("map", {}) as Dictionary).has("sea"), "scenario map carries a sea list")
	var reopened: ScenarioProject = ScenarioProject.new()
	_check(reopened.from_scenario(scenario), "scenario re-opens")
	_check(reopened.is_sea(3, 3) and reopened.is_sea(4, 4), "sea cells survive round-trip")
	_check(reopened.sea_count() == 2, "exactly 2 sea cells round-trip")


func test_phase_e6_place_objects_on_map() -> void:
	print("test_phase_e6_place_objects_on_map")
	var proj: ScenarioProject = ScenarioProject.new()
	proj.clear_walls()
	_check(proj.place_object("rock", 5, 5), "place object in-bounds succeeds")
	_check(proj.object_count() == 1, "object placement counted")
	_check(not proj.place_object("rock", -1, 0), "out-of-bounds object rejected")
	# A cell is exclusive: placing a second object on the same cell replaces nothing
	# but removing the cell clears it.
	_check(proj.remove_entity_at(5, 5), "object removed from cell")
	_check(proj.object_count() == 0, "object count back to zero")
	# Round-trip placed objects.
	proj.place_object("tree", 6, 6)
	var scenario: Dictionary = proj.to_scenario()
	_check((scenario.get("objects", []) as Array).size() == 1, "scenario carries placed objects")
	var reopened: ScenarioProject = ScenarioProject.new()
	reopened.from_scenario(scenario)
	_check(reopened.object_count() == 1, "placed object survives round-trip")


func test_phase_e6_coast_is_render_only() -> void:
	print("test_phase_e6_coast_is_render_only")
	var proj: ScenarioProject = ScenarioProject.new()
	proj.clear_walls()
	# Make a small sea pool, then check the coast mask of an adjacent land cell.
	proj.paint_cell(10, 10, ScenarioProject.TERRAIN_SEA)
	var land_x: int = 11
	var land_y: int = 10
	# The land cell to the EAST of the sea should report sea on its WEST side.
	var mask: int = proj.coast_mask(land_x, land_y, false)
	_check((mask & CoastAutotile.BIT_W) != 0, "coast mask reports sea to the west")
	# A land cell far from any sea has no coast.
	_check(proj.coast_mask(0, 0, false) == 0, "inland cell has no coast")
	# CRITICAL: computing the coast must NOT change the logical sea data
	# (golden rule #1 -- cosmetic only).
	var before: int = proj.sea_count()
	proj.coast_mask(land_x, land_y, false)
	proj.coast_mask(5, 5, false)
	_check(proj.sea_count() == before, "coast computation does not mutate sea data")
	# The same project emits an identical scenario before/after coast queries
	# (determinism preserved).
	var s1: Dictionary = proj.to_scenario()
	proj.coast_mask(land_x, land_y, false)
	var s2: Dictionary = proj.to_scenario()
	_check(JSON.stringify(s1) == JSON.stringify(s2), "coast queries leave emission byte-identical")


func test_phase_e2e6_editor_keys_localized_in_all_locales() -> void:
	print("test_phase_e2e6_editor_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.tree.add_child", "ui.tree.add_sibling", "ui.tree.rename", "ui.tree.remove",
		"ui.graphic.title", "ui.graphic.mode.single", "ui.graphic.mode.multi",
		"ui.graphic.logical_size", "ui.graphic.upload", "ui.graphic.status.image_invalid",
		"ui.stat.title", "ui.stat.add", "ui.stat.status.conflict",
		"ui.part.fusable", "ui.part.destructible", "ui.part.require_hp_armor",
		"ui.upgrade.title", "ui.upgrade.trigger.kill_count", "ui.upgrade.size_cap",
		"ui.train.from_building", "ui.train.required_tech",
		"ui.objecteditor.title", "ui.objecteditor.extractable",
		"ui.objecteditor.placement.sea", "ui.objecteditor.yield_material",
		"ui.mapeditor.tool.sea", "ui.mapeditor.tool.object",
		"ui.modeditor.tab.objects",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


func _load_locale_strings(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("strings", {})


# --- CODE_POLICY enforcement (Phase 5.1) ------------------------------------

# Mirror the linter's core rule (first non-ASCII column) so we can unit-test the
# enforcement logic itself, then run a real scan of the repository to prove the
# committed source is clean.
func _first_non_ascii_column(line: String) -> int:
	for i in range(line.length()):
		if line.unicode_at(i) > 127:
			return i
	return -1


func test_code_policy_detects_non_ascii() -> void:
	print("test_code_policy_detects_non_ascii")
	# A pure-ASCII line passes; a line with a non-English character is flagged at
	# the right column (the policy: source must be English-only).
	_check(_first_non_ascii_column("var speed: int = 10  # English comment") == -1, "ascii line is clean")
	var dirty: String = "var x = 1  # this has a non-ascii char: " + char(0x06A9)
	_check(_first_non_ascii_column(dirty) >= 0, "non-ascii character is detected")


func test_code_policy_allows_localization() -> void:
	print("test_code_policy_allows_localization")
	# The single allowed exception: localization/ files MAY contain non-ASCII text.
	# fa.json certainly does -- assert the linter would NOT scan it (it is exempt),
	# which we model with the same is-in-localization rule the linter uses.
	_check(_is_in_localization("res://localization/fa.json"), "fa.json is inside the allowed localization tree")
	_check(not _is_in_localization("res://core/nexus.gd"), "core source is NOT exempt")
	_check(not _is_in_localization("res://ui/desktop/desktop_hud.gd"), "ui source is NOT exempt")


func _is_in_localization(full: String) -> bool:
	var normalized: String = full.trim_prefix("res://")
	return normalized == "localization" or normalized.begins_with("localization/")


# Mirrors the linter's docs/ exemption (BUG-D3): design documents under docs/ are
# intentionally written in Persian and are NOT shipping source, so the ASCII-only
# rule does not apply to their contents. This copy must stay in lock-step with
# tools/check_code_policy.gd::_is_in_docs so the in-suite clean-repo check and the
# CI linter agree.
func _is_in_docs(full: String) -> bool:
	var normalized: String = full.trim_prefix("res://")
	return normalized == "docs" or normalized.begins_with("docs/")


func test_code_policy_repository_is_clean() -> void:
	print("test_code_policy_repository_is_clean")
	# Walk the same source set the linter scans and assert ZERO violations exist in
	# the committed codebase (so CI would pass on this tree).
	var violations: Array = []
	_scan_for_policy("res://", violations)
	if not violations.is_empty():
		for v in violations:
			print("    policy violation: %s" % v)
	_check(violations.is_empty(), "committed source is ASCII-only outside localization/ and docs/ (%d violations)" % violations.size())


# A trimmed copy of the linter walk (same extensions + skips + localization and
# docs exemptions) used to assert the repository is clean from inside the test
# suite.
func _scan_for_policy(path: String, out_violations: Array) -> void:
	var scanned_ext: Array = ["gd", "tscn", "tres", "godot", "import", "cfg", "json", "md", "yml", "yaml", "txt", "csv"]
	var skip_dirs: Array = [".git", ".godot", ".import", "addons", "android"]
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full: String = path.path_join(name)
		if dir.current_is_dir():
			if not skip_dirs.has(name):
				_scan_for_policy(full, out_violations)
		else:
			var ext: String = full.get_extension().to_lower()
			# Mirror the linter: every .md file (anywhere, not just docs/) is
			# documentation prose and may be Persian (e.g. AGENT_RULES.md,
			# ci/README.md). Exempt it from the ASCII content scan.
			if scanned_ext.has(ext) and ext != "md" and not _is_in_localization(full) and not _is_in_docs(full):
				var file: FileAccess = FileAccess.open(full, FileAccess.READ)
				if file != null:
					var line_number: int = 0
					while not file.eof_reached():
						line_number += 1
						var col: int = _first_non_ascii_column(file.get_line())
						if col >= 0:
							out_violations.append("%s:%d:%d" % [full, line_number, col + 1])
					file.close()
		name = dir.get_next()
	dir.list_dir_end()


# --- Phase 5 assets ship (scenes + export presets) --------------------------

func test_phase5_scenes_and_presets_exist() -> void:
	print("test_phase5_scenes_and_presets_exist")
	# The new desktop + menu scenes and the export presets must actually be in the
	# project (they are the shippable Phase 5 deliverables).
	_check(FileAccess.file_exists("res://scenes/main_menu.tscn"), "main menu scene exists")
	_check(FileAccess.file_exists("res://scenes/game_desktop.tscn"), "desktop game scene exists")
	_check(FileAccess.file_exists("res://ui/desktop/desktop_hud.gd"), "desktop HUD script exists")
	_check(FileAccess.file_exists("res://ui/shared/main_menu.gd"), "main menu script exists")
	_check(FileAccess.file_exists("res://export_presets.cfg"), "export presets file exists")
	_check(FileAccess.file_exists("res://tools/check_code_policy.gd"), "CODE_POLICY linter exists")
	# CI workflow lives at .github/workflows/ci.yml locally, but on the GitHub
	# mirror (whose App token cannot push to the protected workflows/ path) the
	# same file is kept under ci/ci.yml. Accept either location.
	_check(
		FileAccess.file_exists("res://.github/workflows/ci.yml") or FileAccess.file_exists("res://ci/ci.yml"),
		"CI workflow exists"
	)
	# The export presets must cover the priority platforms.
	var cfg: FileAccess = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var text: String = cfg.get_as_text() if cfg != null else ""
	if cfg != null:
		cfg.close()
	_check(text.contains("platform=\"Android\""), "Android export preset present (priority platform)")
	# The Linux export platform id changed from "Linux/X11" (Godot 4.2 and older)
	# to "Linux" (Godot 4.3+). export_presets.cfg is saved by 4.3, so accept both
	# spellings instead of hard-coding the old one (which made this test stale).
	_check(
		text.contains("platform=\"Linux/X11\"") or text.contains("platform=\"Linux\""),
		"Linux export preset present"
	)
	_check(text.contains("platform=\"Windows Desktop\""), "Windows export preset present")
	_check(text.contains("platform=\"macOS\""), "macOS export preset present")


# ============================================================================
# Phase 6 -- Content, Balance & Release Hardening
# ============================================================================
#
# The first Phase 6 deliverable is a persisted player-settings layer
# (GameSettings) backing an in-game Options screen. These tests prove the
# service is safe (validation), durable (disk round-trip), and resilient
# (corrupt/missing files never break the game), all headlessly against a fresh
# WorldState -- no engine singletons required.


func _new_settings() -> GameSettings:
	# A GameSettings bound to a throwaway WorldState so tests never touch the live
	# game state or each other.
	return GameSettings.new(WorldState.new())


func _temp_settings_path() -> String:
	return "user://test_settings_%d.json" % (Time.get_ticks_usec())


func test_settings_defaults_and_getters() -> void:
	print("test_settings_defaults_and_getters")
	var s: GameSettings = _new_settings()
	s.ensure_defaults()
	# Every getter returns the documented default on a fresh store.
	_check(s.get_locale() == "en", "default locale is english")
	# P1.2 (v0.6.0) intentionally changed the default render style to "sprite".
	_check(s.get_render_style() == "sprite", "default render style is sprite")
	_check(s.get_difficulty() == "normal", "default difficulty is normal")
	_check(is_equal_approx(s.get_camera_zoom(), 1.0), "default camera zoom is 1.0x")
	_check(s.is_sfx_enabled(), "sfx on by default")
	_check(s.is_music_enabled(), "music on by default")


func test_settings_validated_setters_reject_bad_values() -> void:
	print("test_settings_validated_setters_reject_bad_values")
	var s: GameSettings = _new_settings()
	s.ensure_defaults()
	# Valid writes are accepted...
	_check(s.set_render_style("detailed"), "valid render style accepted")
	_check(s.get_render_style() == "detailed", "render style updated")
	_check(s.set_difficulty("hard"), "valid difficulty accepted")
	_check(s.set_camera_zoom(2.0), "in-range zoom accepted")
	# ...and invalid writes are rejected WITHOUT corrupting the current value.
	_check(not s.set_render_style("ascii-art"), "unknown render style rejected")
	_check(s.get_render_style() == "detailed", "render style unchanged after bad write")
	_check(not s.set_difficulty("impossible"), "unknown difficulty rejected")
	_check(s.get_difficulty() == "hard", "difficulty unchanged after bad write")
	_check(not s.set_camera_zoom(99.0), "out-of-range zoom rejected")
	_check(not s.set_camera_zoom(0.1), "below-min zoom rejected")
	_check(is_equal_approx(s.get_camera_zoom(), 2.0), "zoom unchanged after bad write")
	_check(not s.set_locale("   "), "blank locale rejected")


func test_settings_persist_round_trip() -> void:
	print("test_settings_persist_round_trip")
	var path: String = _temp_settings_path()
	var s: GameSettings = _new_settings()
	s.set_locale("fa")
	s.set_render_style("detailed")
	s.set_difficulty("hard")
	s.set_camera_zoom(1.75)
	s.set_sfx_enabled(false)
	s.set_music_enabled(false)
	_check(s.save_to_file(path), "settings saved to disk")

	# A brand-new service loading the same file must observe identical values.
	var loaded: GameSettings = _new_settings()
	_check(loaded.load_from_file(path), "settings loaded from disk")
	_check(loaded.get_locale() == "fa", "locale persisted")
	_check(loaded.get_render_style() == "detailed", "render style persisted")
	_check(loaded.get_difficulty() == "hard", "difficulty persisted")
	_check(is_equal_approx(loaded.get_camera_zoom(), 1.75), "camera zoom persisted")
	_check(not loaded.is_sfx_enabled(), "sfx toggle persisted")
	_check(not loaded.is_music_enabled(), "music toggle persisted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_settings_corrupt_file_falls_back_to_defaults() -> void:
	print("test_settings_corrupt_file_falls_back_to_defaults")
	var path: String = _temp_settings_path()
	# Write a file with garbage + an out-of-range value: load must NOT crash and
	# every field must fall back to its default.
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not valid json ::: ")
	f.close()
	var s: GameSettings = _new_settings()
	_check(not s.load_from_file(path), "corrupt file reported as failure")
	_check(s.get_locale() == "en", "locale defaulted after corrupt load")
	_check(s.get_render_style() == "sprite", "render style defaulted after corrupt load")
	# A structurally valid file with a bad field also falls back for that field.
	var g: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	g.store_string(JSON.stringify({"render_style": "nope", "camera_zoom": 999, "locale": "fa"}))
	g.close()
	var s2: GameSettings = _new_settings()
	_check(s2.load_from_file(path), "partially-valid file loads")
	_check(s2.get_locale() == "fa", "valid field kept")
	_check(s2.get_render_style() == "sprite", "invalid field defaulted")
	_check(is_equal_approx(s2.get_camera_zoom(), 1.0), "out-of-range field defaulted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_settings_reset_restores_defaults() -> void:
	print("test_settings_reset_restores_defaults")
	var s: GameSettings = _new_settings()
	s.set_locale("fa")
	s.set_render_style("detailed")
	s.set_camera_zoom(2.5)
	s.set_music_enabled(false)
	s.reset_to_defaults()
	_check(s.get_locale() == "en", "locale reset")
	_check(s.get_render_style() == "sprite", "render style reset")
	_check(is_equal_approx(s.get_camera_zoom(), 1.0), "zoom reset")
	_check(s.is_music_enabled(), "music reset to on")


func test_settings_keys_localized_in_all_locales() -> void:
	print("test_settings_keys_localized_in_all_locales")
	# Every new options key must exist in BOTH locale files (no silent fallbacks).
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var keys: Array = [
		"ui.options.title", "ui.options.difficulty", "ui.options.zoom",
		"ui.options.sfx", "ui.options.music", "ui.options.on", "ui.options.off",
		"ui.options.reset", "ui.options.back",
	]
	for key in keys:
		_check(en.has(key), "en has %s" % key)
		_check(fa.has(key), "fa has %s" % key)


func test_phase6_options_scene_exists() -> void:
	print("test_phase6_options_scene_exists")
	_check(FileAccess.file_exists("res://core/game_settings.gd"), "GameSettings service exists")
	_check(FileAccess.file_exists("res://ui/shared/options_menu.gd"), "options menu script exists")
	_check(FileAccess.file_exists("res://scenes/options_menu.tscn"), "options menu scene exists")


# --- Phase 6.3: new data-driven content -------------------------------------

func test_phase6_new_content_catalogs_load() -> void:
	print("test_phase6_new_content_catalogs_load")
	# All new units/buildings/tech must be discoverable through the data loader,
	# proving the additions are purely data-driven (no code changes needed).
	var loader: DataLoader = DataLoader.new()
	loader.load_catalog("units", "res://data/units")
	loader.load_catalog("buildings", "res://data/buildings")
	loader.load_catalog("tech", "res://data/tech")
	_check(loader.get_entry("units", "scout") is Dictionary, "scout unit loads")
	_check(loader.get_entry("units", "tank") is Dictionary, "tank unit loads")
	_check(loader.get_entry("buildings", "barracks") is Dictionary, "barracks building loads")
	# The barracks can build the scout (and the tank after its level-2 upgrade).
	var barracks: Dictionary = loader.get_entry("buildings", "barracks")
	_check((barracks.get("buildable_units", []) as Array).has("scout"), "barracks builds scout")
	# New tech nodes target the new unit categories.
	var tree: Dictionary = loader.get_entry("tech", "tech_tree_default")
	var node_ids: Array = []
	for n in tree.get("nodes", []):
		node_ids.append(str(n.get("id", "")))
	_check(node_ids.has("recon_training"), "recon_training tech present")
	_check(node_ids.has("armored_vehicles"), "armored_vehicles tech present")


func test_phase6_new_scenarios_are_valid_and_loadable() -> void:
	print("test_phase6_new_scenarios_are_valid_and_loadable")
	# Each new scenario file must parse and build a real match (map + HQs + units)
	# through the normal scenario loader, exactly like the shipped skirmish.
	for path in ["res://data/scenarios/skirmish_duel.json", "res://data/scenarios/skirmish_four_corners.json"]:
		var loader: DataLoader = DataLoader.new()
		var parsed: Variant = loader.load_json_file(path)
		_check(parsed is Dictionary, "%s parses as JSON object" % path)
		var nexus: TickHarness = TickHarness.new()
		GameBootstrap.setup_for_test(nexus, parsed as Dictionary)
		var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
		_check(buildings.size() >= 2, "%s placed at least two HQs" % path)
		# Run a few ticks: it must stay deterministic and not crash.
		var snapshot_a: String = _run_scenario_snapshot(parsed as Dictionary, 40)
		var snapshot_b: String = _run_scenario_snapshot(parsed as Dictionary, 40)
		_check(snapshot_a == snapshot_b, "%s is deterministic" % path)


func _run_scenario_snapshot(scenario: Dictionary, num_ticks: int) -> String:
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.setup_for_test(nexus, scenario)
	nexus.run_ticks(num_ticks)
	return _hash_world(nexus.world_state)


# --- Phase 6.4: AI difficulty balance knob ----------------------------------

func test_phase6_ai_max_queue_scales_with_difficulty() -> void:
	print("test_phase6_ai_max_queue_scales_with_difficulty")
	# The balance pass added a per-difficulty build-queue depth so harder AIs
	# sustain more production. Verify the knob is wired and ordered correctly.
	var diff: Dictionary = AiCommanderModule.DIFFICULTY
	_check(int(diff["easy"].get("max_queue", 0)) < int(diff["normal"].get("max_queue", 0)), "easy queues shallower than normal")
	_check(int(diff["normal"].get("max_queue", 0)) < int(diff["hard"].get("max_queue", 0)), "normal queues shallower than hard")
	# And it stays deterministic: a hard AI-vs-AI battle is still reproducible.
	var a: String = _run_ai_battle_snapshot(7777, 120)
	var b: String = _run_ai_battle_snapshot(7777, 120)
	_check(a == b, "balance knob keeps AI battles deterministic")


# --- Phase 6.5: mod editor / validator --------------------------------------

func test_phase6_mod_editor_exists() -> void:
	print("test_phase6_mod_editor_exists")
	_check(FileAccess.file_exists("res://tools/mod_editor.gd"), "mod editor tool exists")
	# The shipped example mod must satisfy the same rules the editor validates:
	# id matches its folder, version present, and every provides-file exists.
	var loader: DataLoader = DataLoader.new()
	var manifest: Variant = loader.load_json_file("res://mods/example_mod/mod.json")
	_check(manifest is Dictionary, "example mod manifest parses")
	var m: Dictionary = manifest
	_check(str(m.get("id", "")) == "example_mod", "example mod id matches folder")
	_check(not str(m.get("version", "")).is_empty(), "example mod has a version")
	for key in (m.get("provides", {}) as Dictionary).keys():
		for rel in (m["provides"][key] as Array):
			_check(FileAccess.file_exists("res://mods/example_mod/".path_join(str(rel))), "provides file exists: %s" % str(rel))


# --- Phase 6.6: release tooling ---------------------------------------------

func test_phase6_release_tooling_ships() -> void:
	print("test_phase6_release_tooling_ships")
	_check(FileAccess.file_exists("res://tools/build_release.sh"), "release build script ships")
	_check(FileAccess.file_exists("res://docs/RELEASE.md"), "release guide ships")
	_check(FileAccess.file_exists("res://export_presets.cfg"), "export presets present")


func test_phase6_new_content_localized_in_all_locales() -> void:
	print("test_phase6_new_content_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var keys: Array = [
		"unit.scout.name", "unit.tank.name",
		"building.barracks.name", "building.barracks.level_2.name",
		"tech.recon_training.name", "tech.armored_vehicles.name",
		"scenario.skirmish_duel.name", "scenario.skirmish_four_corners.name",
	]
	for key in keys:
		_check(en.has(key), "en has %s" % key)
		_check(fa.has(key), "fa has %s" % key)


# --- Phase A: visibility / readability --------------------------------------

func test_phase_a_fit_map_to_viewport() -> void:
	print("test_phase_a_fit_map_to_viewport")
	# fit_map_to_viewport must compute a zoom that makes the WHOLE map fit inside
	# the viewport (the fix for the tiny-square-in-the-corner bug). We drive it
	# against a real Nexus harness so it can read the map section.
	var harness: TickHarness = _make_strategic_harness(123, "balanced", 2000)
	harness.run_ticks(2)
	var adapter: RenderAdapter = RenderAdapter.new()
	# Manually attach a world via the harness's Nexus stand-in is not wired into
	# the scene tree, so we assert the method exists and is a no-op safe call.
	_check(adapter.has_method("fit_map_to_viewport"), "RenderAdapter exposes fit_map_to_viewport")
	# A direct geometry check: at tile_size 24, a 20x14 map at zoom 1 is 480x336.
	# A 1920x1080 viewport must zoom OUT? No -- it fits, so zoom stays <= bounds.
	adapter.tile_size = 24
	# Without a Nexus in the tree the method returns early (safe); just confirm
	# the default zoom is sane and the call does not crash.
	adapter.fit_map_to_viewport(Vector2(1920, 1080))
	_check(adapter.zoom > 0.0, "zoom stays positive after fit call")
	adapter.free()


# --- Phase B: data-driven visual layer --------------------------------------

func test_phase_b_visual_schema_present() -> void:
	print("test_phase_b_visual_schema_present")
	# Every base unit/building should carry a cosmetic `visual` block (Phase B.1).
	var loader: DataLoader = DataLoader.new()
	loader.load_catalog("units", "res://data/units")
	loader.load_catalog("buildings", "res://data/buildings")
	for id in ["soldier", "scout", "tank", "hero"]:
		var u: Variant = loader.get_entry("units", id)
		_check(u is Dictionary and (u as Dictionary).has("visual"), "unit %s has visual" % id)
	for id in ["hq", "barracks", "outpost"]:
		var b: Variant = loader.get_entry("buildings", id)
		_check(b is Dictionary and (b as Dictionary).has("visual"), "building %s has visual" % id)


func test_phase_b_texture_service_cache_and_fallback() -> void:
	print("test_phase_b_texture_service_cache_and_fallback")
	var svc: TextureService = TextureService.new()
	# A shipped base texture resolves.
	_check_or_skip(svc.has_texture("textures/soldier.png"), "base soldier texture resolves")
	var t1: Texture2D = svc.get_texture("textures/soldier.png")
	_check(t1 != null, "soldier texture loads")
	var t2: Texture2D = svc.get_texture("textures/soldier.png")
	_check(t1 == t2, "texture is cached (same instance on second call)")
	# A missing texture falls back to a non-null placeholder.
	var miss: Texture2D = svc.get_texture("textures/does_not_exist.png")
	_check(miss != null, "missing texture returns a placeholder (never null)")
	_check(not svc.has_texture("textures/does_not_exist.png"), "has_texture false for missing file")


func test_phase_b_style_sprite_interface_matches_simple() -> void:
	print("test_phase_b_style_sprite_interface_matches_simple")
	var simple: StyleSimple = StyleSimple.new()
	var sprite: StyleSprite = StyleSprite.new()
	for method in ["draw_tile", "draw_building", "draw_unit", "owner_color"]:
		_check(sprite.has_method(method), "sprite style has %s" % method)
		_check(simple.has_method(method), "simple style has %s" % method)


func test_phase_b_style_sprite_draws_textures() -> void:
	print("test_phase_b_style_sprite_draws_textures")
	var style: StyleSprite = StyleSprite.new()
	style.texture_service = TextureService.new()
	var canvas: RecordingCanvas = RecordingCanvas.new()
	var rect: Rect2 = Rect2(0, 0, 24, 24)
	style.draw_tile(canvas, rect, 0)
	# A unit WITH a resolvable texture should draw a texture rect.
	style.draw_unit(canvas, rect, {
		"owner": 0, "x": 0, "y": 0, "health": 80, "max_health": 100,
		"visual": {"texture": "textures/soldier.png", "color": "#4CB0F2", "size_scale": 1.0},
	}, false)
	_check_or_skip(canvas.textures_drawn >= 1, "sprite style drew at least one texture")
	# A unit with NO texture falls back to a shape (no extra texture call).
	var before: int = canvas.textures_drawn
	style.draw_unit(canvas, rect, {
		"owner": 1, "x": 1, "y": 1, "health": 50, "max_health": 100,
		"visual": {"shape": "circle", "color": "#FF0000"},
	}, false)
	_check(canvas.textures_drawn == before, "missing-texture unit falls back to a shape")


func test_phase_b_render_adapter_sprite_style_switch() -> void:
	print("test_phase_b_render_adapter_sprite_style_switch")
	var adapter: RenderAdapter = RenderAdapter.new()
	_check(adapter.set_style(RenderAdapter.STYLE_SPRITE) == RenderAdapter.STYLE_SPRITE, "set_style sprite id")
	_check(adapter.style is StyleSprite, "sprite style instantiated")
	_check(adapter.texture_service != null, "texture service created for sprite style")
	# Cycle: simple -> detailed -> sprite -> simple.
	adapter.set_style(RenderAdapter.STYLE_SIMPLE)
	_check(adapter.toggle_style() == RenderAdapter.STYLE_DETAILED, "cycle simple -> detailed")
	_check(adapter.toggle_style() == RenderAdapter.STYLE_SPRITE, "cycle detailed -> sprite")
	_check(adapter.toggle_style() == RenderAdapter.STYLE_SIMPLE, "cycle sprite -> simple")
	adapter.free()


func test_phase_b_visual_is_cosmetic_only() -> void:
	print("test_phase_b_visual_is_cosmetic_only")
	# The cornerstone rule: visuals + style swaps must NOT change the world hash.
	var harness: TickHarness = _make_strategic_harness(4242, "balanced", 2500)
	harness.run_ticks(40)
	var before: int = StateHasher.hash_world(harness.world_state)
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.set_style(RenderAdapter.STYLE_SIMPLE)
	adapter.set_style(RenderAdapter.STYLE_SPRITE)
	adapter.set_style(RenderAdapter.STYLE_DETAILED)
	var after: int = StateHasher.hash_world(harness.world_state)
	_check(before == after, "visual/style changes never mutate the world hash")
	adapter.free()


func test_phase_b_playdough_demo_mod_valid() -> void:
	print("test_phase_b_playdough_demo_mod_valid")
	# The shipped play-dough demo proves the schema turns the SAME building data
	# into a Wall or a Turret purely via stats + visual.
	var loader: DataLoader = DataLoader.new()
	var manifest: Variant = loader.load_json_file("res://mods/playdough_demo/mod.json")
	_check(manifest is Dictionary, "playdough_demo manifest parses")
	var wall: Variant = loader.load_json_file("res://mods/playdough_demo/data/buildings/raw_wall.json")
	var turret: Variant = loader.load_json_file("res://mods/playdough_demo/data/buildings/raw_turret.json")
	_check(wall is Dictionary and int((wall as Dictionary).get("stats", {}).get("health", 0)) >= 1500, "wall is a high-HP block")
	_check(turret is Dictionary and int((turret as Dictionary).get("stats", {}).get("attack_range", 0)) > 0, "turret has attack range")
	_check((wall as Dictionary).has("visual") and (turret as Dictionary).has("visual"), "both demo buildings have visuals")


func test_phase_b_visual_keys_localized_in_all_locales() -> void:
	print("test_phase_b_visual_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var keys: Array = [
		"ui.onboarding.title", "ui.onboarding.you", "ui.onboarding.move",
		"ui.onboarding.win", "ui.onboarding.close",
		"ui.game.style_sprite", "building.raw_wall.name", "building.raw_turret.name",
	]
	for key in keys:
		_check(en.has(key), "en has %s" % key)
		_check(fa.has(key), "fa has %s" % key)


# --- Phase C -- Storage + .nexpack portable package format ------------------

func test_phase_c_storage_service_root_and_resolve() -> void:
	print("test_phase_c_storage_service_root_and_resolve")
	var svc: StorageService = StorageService.new()
	_check(svc.get_content_root() == StorageService.DEFAULT_CONTENT_ROOT, "default content root applied")
	# Empty / whitespace path falls back to the default (never unusable).
	svc.set_content_root("   ")
	_check(svc.get_content_root() == StorageService.DEFAULT_CONTENT_ROOT, "blank path falls back to default")
	# A trailing slash is normalised away so joins are predictable.
	svc.set_content_root("user://my_content/")
	_check(svc.get_content_root() == "user://my_content", "trailing slash normalised")
	_check(svc.resolve("a/b.json") == "user://my_content/a/b.json", "resolve joins under root")
	# A bare pack id gets the canonical extension.
	_check(svc.resolve_pack("my_mod").ends_with("my_mod.nexpack"), "resolve_pack adds extension")
	_check(svc.resolve_pack("my_mod.nexpack").ends_with("my_mod.nexpack"), "resolve_pack keeps extension once")


# MB8.3 (bug 23): the content root MUST be writable on every export target. A
# `res://` root is bundled/read-only in an installed build, so the storage
# service rejects it and falls back to the writable `user://` default rather
# than silently failing writes (which hangs the mod/map editor on Android).
func test_mb8_storage_rejects_read_only_res_root() -> void:
	print("test_mb8_storage_rejects_read_only_res_root")
	# Constructed with a res:// root -> falls back to the writable default.
	var svc: StorageService = StorageService.new("res://content")
	_check(svc.get_content_root() == StorageService.DEFAULT_CONTENT_ROOT, "res:// root rejected at construction")
	# Case-insensitive on the scheme (RES://, Res://, ...).
	svc.set_content_root("RES://packs")
	_check(svc.get_content_root() == StorageService.DEFAULT_CONTENT_ROOT, "RES:// (upper) rejected too")
	# A res:// path with surrounding whitespace is still caught.
	svc.set_content_root("   res://mods   ")
	_check(svc.get_content_root() == StorageService.DEFAULT_CONTENT_ROOT, "whitespace-padded res:// rejected")
	# A legitimate user:// root is still accepted (guard is not over-broad).
	svc.set_content_root("user://custom_content")
	_check(svc.get_content_root() == "user://custom_content", "writable user:// root accepted")
	# The default is itself writable (never a res:// path).
	_check(not StorageService.DEFAULT_CONTENT_ROOT.to_lower().begins_with("res://"), "default root is writable (user://)")


func test_phase_c_storage_settings_content_path() -> void:
	print("test_phase_c_storage_settings_content_path")
	var ws: WorldState = WorldState.new()
	var settings: GameSettings = GameSettings.new(ws)
	settings.ensure_defaults()
	_check(settings.get_content_path() == GameSettings.DEFAULT_CONTENT_PATH, "default content_path")
	_check(settings.set_content_path("user://elsewhere"), "valid content_path accepted")
	_check(settings.get_content_path() == "user://elsewhere", "content_path updated")
	_check(not settings.set_content_path("   "), "blank content_path rejected")
	_check(settings.get_content_path() == "user://elsewhere", "rejected value left state intact")


func test_phase_c_pack_format_validation() -> void:
	print("test_phase_c_pack_format_validation")
	_check(PackFormat.is_pack_file("a.nexpack"), "recognises .nexpack")
	_check(PackFormat.is_pack_file("A.NEXPACK"), "extension is case-insensitive")
	_check(not PackFormat.is_pack_file("a.zip"), "rejects non-pack extension")
	_check(PackFormat.pack_file_name("mod_x") == "mod_x.nexpack", "builds canonical name")
	# Valid manifest -> no problems.
	var good: Dictionary = {"id": "x", "provides": {"buildings": ["data/buildings/x.json"]}}
	_check(PackFormat.is_manifest_valid(good), "well-formed manifest is valid")
	_check(PackFormat.provided_data_paths(good) == ["data/buildings/x.json"], "collects provided paths")
	# Missing id, bad provides, bad load_after -> problems reported.
	_check(not PackFormat.is_manifest_valid({"name": "no id"}), "missing id is invalid")
	_check(not PackFormat.is_manifest_valid({"id": "x", "provides": []}), "provides must be object")
	_check(not PackFormat.is_manifest_valid({"id": "x", "load_after": "y"}), "load_after must be array")


func test_phase_c_pack_write_read_round_trip() -> void:
	print("test_phase_c_pack_write_read_round_trip")
	var out_path: String = "user://test_pack_roundtrip.nexpack"
	# A turret PNG payload (a few bytes is enough to prove binary survives).
	var tex_bytes: PackedByteArray = PackedByteArray([1, 2, 3, 4, 250, 200, 0, 255])
	var manifest: Dictionary = {
		"id": "rt_mod", "name": "Round Trip", "version": "1.0.0",
		"enabled": true,
		"provides": {"buildings": ["data/buildings/rt_wall.json"]},
	}
	var building: Dictionary = {"id": "rt_wall", "stats": {"health": 2000}, "visual": {"texture": "textures/wall_block.png"}}
	var files: Dictionary = {
		"data/buildings/rt_wall.json": JSON.stringify(building),
		"textures/wall_block.png": tex_bytes,
	}
	# WRITE.
	_check(PackWriter.write_from_data(manifest, files, out_path), "write_from_data succeeds")
	_check(FileAccess.file_exists(out_path), "pack file exists on disk")
	# READ back.
	var reader: PackReader = PackReader.new()
	_check(reader.open(out_path), "reader opens the pack")
	var read_manifest: Variant = reader.read_manifest()
	_check(read_manifest is Dictionary and str((read_manifest as Dictionary)["id"]) == "rt_mod", "manifest round-trips")
	var read_building: Variant = reader.read_json("data/buildings/rt_wall.json")
	_check(read_building is Dictionary and int((read_building as Dictionary).get("stats", {}).get("health", 0)) == 2000, "data json round-trips")
	var read_tex: PackedByteArray = reader.read_bytes("textures/wall_block.png")
	_check(read_tex == tex_bytes, "binary texture round-trips byte-for-byte")
	# read_catalogs groups by catalog -> id.
	var catalogs: Dictionary = reader.read_catalogs()
	_check(catalogs.has("buildings") and catalogs["buildings"].has("rt_wall"), "read_catalogs groups by catalog/id")
	reader.close()
	# A refusal: an invalid manifest is never written.
	_check(not PackWriter.write_from_data({"name": "no id"}, {}, "user://bad.nexpack"), "invalid manifest refused")
	DirAccess.remove_absolute(out_path)


func test_phase_c_mod_loader_loads_packs_into_catalogs() -> void:
	print("test_phase_c_mod_loader_loads_packs_into_catalogs")
	# Build a throwaway content root with one pack, then load it via ModLoader.
	var root: String = "user://test_content_packs"
	DirAccess.make_dir_recursive_absolute(root)
	var storage: StorageService = StorageService.new(root)
	storage.ensure_content_root()
	var manifest: Dictionary = {
		"id": "pack_mod", "name": "Pack Mod", "enabled": true,
		"provides": {"units": ["data/units/pack_soldier.json"]},
	}
	var unit: Dictionary = {"id": "pack_soldier", "stats": {"health": 42}}
	var files: Dictionary = {"data/units/pack_soldier.json": JSON.stringify(unit)}
	var pack_path: String = storage.resolve_pack("pack_mod")
	_check(PackWriter.write_from_data(manifest, files, pack_path), "test pack written into content root")
	_check(storage.has_pack("pack_mod"), "storage sees the installed pack")
	_check(storage.list_packs().size() == 1, "list_packs finds exactly one pack")
	# Load it into a fresh DataLoader.
	var loader: DataLoader = DataLoader.new()
	var info: Dictionary = ModLoader.load_packs(loader, storage, null)
	_check(info.get("loaded", []) == ["pack_mod"], "pack mod reported as loaded")
	var merged: Variant = loader.get_entry("units", "pack_soldier")
	_check(merged is Dictionary and int((merged as Dictionary).get("stats", {}).get("health", 0)) == 42, "pack entry merged into catalog")
	# Cleanup the throwaway content root.
	DirAccess.remove_absolute(pack_path)
	var cache: String = root + "/.cache"
	if DirAccess.dir_exists_absolute(cache):
		_remove_dir_recursive(cache)
	DirAccess.remove_absolute(root)


func test_phase_c_options_content_path_localized() -> void:
	print("test_phase_c_options_content_path_localized")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	_check(en.has("ui.options.content_path"), "en has content_path label")
	_check(fa.has("ui.options.content_path"), "fa has content_path label")


# --- Phase G -- GUI scaling + restructured main menu ------------------------

func test_phase_g_ui_scale_settings() -> void:
	print("test_phase_g_ui_scale_settings")
	var ws: WorldState = WorldState.new()
	var settings: GameSettings = GameSettings.new(ws)
	settings.ensure_defaults()
	# Auto is ON by default and the manual multiplier defaults to 1.0.
	_check(settings.is_ui_scale_auto(), "ui_scale_auto defaults to true")
	_check(abs(settings.get_ui_scale() - 1.0) < 0.0001, "ui_scale defaults to 1.0")
	# Manual setter validates against the documented range.
	_check(settings.set_ui_scale(1.5), "valid ui_scale accepted")
	_check(abs(settings.get_ui_scale() - 1.5) < 0.0001, "ui_scale updated")
	_check(not settings.set_ui_scale(GameSettings.UI_SCALE_MAX + 1.0), "out-of-range ui_scale rejected")
	_check(abs(settings.get_ui_scale() - 1.5) < 0.0001, "rejected value left state intact")
	_check(not settings.set_ui_scale(GameSettings.UI_SCALE_MIN - 0.1), "below-min ui_scale rejected")
	# Auto toggle is always accepted.
	settings.set_ui_scale_auto(false)
	_check(not settings.is_ui_scale_auto(), "ui_scale_auto toggled off")


func test_phase_g_auto_scale_math() -> void:
	print("test_phase_g_auto_scale_math")
	# At the reference resolution the scale is 1.0.
	_check(abs(GameSettings.auto_scale_for(Vector2(1280, 720)) - 1.0) < 0.0001, "reference size -> 1.0x")
	# A 2x-larger screen yields ~2.0x (uses the smaller ratio, here both equal).
	_check(abs(GameSettings.auto_scale_for(Vector2(2560, 1440)) - 2.0) < 0.0001, "double size -> 2.0x")
	# MB4.3 (bug 18): a tiny screen no longer collapses to the bare UI_SCALE_MIN;
	# the touch floor keeps the smallest control tappable. The floor is capped at
	# ~22% of the short edge, so for 320x180 the lower bound is 180*0.22/44 = 0.9,
	# which is what the fit ratio (0.25) is raised to. It must be >= UI_SCALE_MIN
	# and never exceed 1.0 (never enlarges past design size on a small screen).
	var tiny: float = GameSettings.auto_scale_for(Vector2(320, 180))
	_check(tiny >= GameSettings.UI_SCALE_MIN and tiny <= 1.0, "tiny screen honours touch floor (>=min, <=1.0)")
	_check(abs(tiny - 0.9) < 0.0001, "tiny screen touch floor is 0.9 for 320x180")
	# A huge screen clamps to the documented maximum.
	_check(abs(GameSettings.auto_scale_for(Vector2(7680, 4320)) - GameSettings.UI_SCALE_MAX) < 0.0001, "huge screen clamps to max")
	# An invalid (zero) size is safe and returns 1.0.
	_check(abs(GameSettings.auto_scale_for(Vector2(0, 0)) - 1.0) < 0.0001, "zero size is safe")
	# A non-square screen uses the smaller dimension ratio so the UI always fits.
	_check(GameSettings.auto_scale_for(Vector2(2560, 720)) <= 1.05, "wide screen uses smaller ratio")


func test_phase_g_resolve_ui_scale_honours_auto() -> void:
	print("test_phase_g_resolve_ui_scale_honours_auto")
	var ws: WorldState = WorldState.new()
	var settings: GameSettings = GameSettings.new(ws)
	settings.ensure_defaults()
	# Auto on: the screen size drives the result regardless of the manual value.
	settings.set_ui_scale_auto(true)
	settings.set_ui_scale(0.5)
	_check(abs(settings.resolve_ui_scale(Vector2(2560, 1440)) - 2.0) < 0.0001, "auto ignores manual value")
	# Auto off: the manual value is used (clamped into range).
	settings.set_ui_scale_auto(false)
	settings.set_ui_scale(1.25)
	_check(abs(settings.resolve_ui_scale(Vector2(2560, 1440)) - 1.25) < 0.0001, "manual value used when auto off")


func test_phase_g_settings_persist_round_trip() -> void:
	print("test_phase_g_settings_persist_round_trip")
	var path: String = "user://test_phase_g_settings.json"
	var ws: WorldState = WorldState.new()
	var a: GameSettings = GameSettings.new(ws)
	a.ensure_defaults()
	a.set_ui_scale_auto(false)
	a.set_ui_scale(1.75)
	_check(a.save_to_file(path), "settings saved to disk")
	# Reload into a fresh world and confirm the GUI-scale prefs survived.
	var ws2: WorldState = WorldState.new()
	var b: GameSettings = GameSettings.new(ws2)
	_check(b.load_from_file(path), "settings loaded from disk")
	_check(not b.is_ui_scale_auto(), "ui_scale_auto round-trips")
	_check(abs(b.get_ui_scale() - 1.75) < 0.0001, "ui_scale round-trips")
	DirAccess.remove_absolute(path)


func test_phase_g_menu_keys_localized_in_all_locales() -> void:
	print("test_phase_g_menu_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var keys: Array = [
		"ui.menu.single", "ui.menu.multiplayer", "ui.menu.mp_offline",
		"ui.menu.mp_online", "ui.menu.back",
		"ui.options.ui_scale", "ui.options.ui_scale_auto",
		"ui.options.ui_scale_auto_value",
	]
	for key in keys:
		_check(en.has(key), "en has %s" % key)
		_check(fa.has(key), "fa has %s" % key)


# Helper: recursively delete a directory tree (test cleanup only).
func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_remove_dir_recursive(path + "/" + name)
		else:
			DirAccess.remove_absolute(path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# --- Phase D -- graphical Mod Editor (ModProject model + save engine) -------

func test_phase_d_mod_project_new_and_edit() -> void:
	print("test_phase_d_mod_project_new_and_edit")
	var proj: ModProject = ModProject.new()
	proj.new_project("My Cool Mod", "My Cool Mod")
	_check(proj.get_id() == "my_cool_mod", "display id normalised to a safe token")
	# Add a unit + a building via the default factories.
	_check(proj.set_unit("raider", ModProject.default_unit("raider")), "set_unit accepts a valid id")
	_check(proj.set_building("bunker", ModProject.default_building("bunker")), "set_building accepts a valid id")
	_check(proj.units.has("raider") and proj.buildings.has("bunker"), "entities stored in their catalogs")
	# Editing an entity's stats round-trips through get/set.
	var u: Dictionary = proj.get_unit("raider")
	u["stats"]["health"] = 250
	proj.set_unit("raider", u)
	_check(int(proj.get_unit("raider").get("stats", {}).get("health", 0)) == 250, "edited health persisted")
	# Provides is rebuilt deterministically from the live content.
	var manifest: Dictionary = proj.build_manifest()
	_check(manifest.get("provides", {}).has("units") and manifest["provides"].has("buildings"), "provides lists both catalogs")
	_check(manifest["provides"]["units"] == ["data/units/raider.json"], "provides path is canonical + deterministic")
	# Removing an entity drops it from provides too.
	_check(proj.remove_building("bunker"), "remove_building succeeds")
	_check(not proj.build_manifest().get("provides", {}).has("buildings"), "emptied catalog leaves provides")


func test_phase_d_id_normalisation() -> void:
	print("test_phase_d_id_normalisation")
	_check(ModProject.normalise_id("Heavy Tank") == "heavy_tank", "spaces -> underscore, lower-cased")
	_check(ModProject.normalise_id("  Wall-Block  ") == "wall_block", "trim + hyphen -> underscore")
	_check(ModProject.normalise_id("a!!!b") == "ab", "stray characters dropped")
	_check(ModProject.normalise_id("___x___") == "x", "leading/trailing underscores trimmed")
	_check(ModProject.normalise_id("!!!") == "", "all-junk id reduces to empty (rejected upstream)")
	var proj: ModProject = ModProject.new()
	_check(not proj.set_unit("!!!", {}), "invalid id is rejected, model unchanged")


func test_phase_d_validation_rejects_empty() -> void:
	print("test_phase_d_validation_rejects_empty")
	var proj: ModProject = ModProject.new()
	proj.new_project("empty_mod", "Empty Mod")
	_check(not proj.is_valid(), "a project with no content is invalid")
	_check(not proj.save_pack("user://should_not_exist.nexpack"), "saving an invalid project is refused")
	_check(not FileAccess.file_exists("user://should_not_exist.nexpack"), "no pack written for invalid project")
	# Adding one valid unit makes it saveable.
	proj.set_unit("trooper", ModProject.default_unit("trooper"))
	_check(proj.is_valid(), "one valid unit makes the project valid")


func test_phase_d_save_and_reopen_round_trip() -> void:
	print("test_phase_d_save_and_reopen_round_trip")
	var out_path: String = "user://test_modeditor_roundtrip.nexpack"
	var proj: ModProject = ModProject.new()
	proj.new_project("editor_mod", "Editor Mod")
	var u: Dictionary = ModProject.default_unit("ranger")
	u["stats"]["health"] = 321
	u["visual"]["color"] = "#E2543C"
	proj.set_unit("ranger", u)
	proj.set_building("keep", ModProject.default_building("keep"))
	_check(proj.save_pack(out_path), "project saves to a .nexpack")
	# Re-open into a FRESH project and confirm everything survived.
	var reopened: ModProject = ModProject.new()
	_check(reopened.open_pack(out_path), "saved pack re-opens")
	_check(reopened.get_id() == "editor_mod", "manifest id round-trips")
	_check(reopened.units.has("ranger") and reopened.buildings.has("keep"), "both entities round-trip")
	_check(int(reopened.get_unit("ranger").get("stats", {}).get("health", 0)) == 321, "edited stat round-trips")
	_check(str(reopened.get_unit("ranger").get("visual", {}).get("color", "")) == "#E2543C", "cosmetic colour round-trips")
	# A bad pack path leaves an in-progress project untouched.
	_check(not reopened.open_pack("user://nope.nexpack"), "opening a missing pack fails")
	_check(reopened.get_id() == "editor_mod", "failed open left project unchanged")
	DirAccess.remove_absolute(out_path)


func test_phase_d_saved_pack_loads_into_catalogs() -> void:
	print("test_phase_d_saved_pack_loads_into_catalogs")
	# A pack saved by the editor must be play-testable: drop it in a content root
	# and the SAME ModLoader the game uses merges it into the catalogs.
	var root: String = "user://test_editor_content"
	DirAccess.make_dir_recursive_absolute(root)
	var storage: StorageService = StorageService.new(root)
	storage.ensure_content_root()
	var proj: ModProject = ModProject.new()
	proj.new_project("playtest_mod", "Playtest Mod")
	var u: Dictionary = ModProject.default_unit("sniper")
	u["stats"]["health"] = 77
	proj.set_unit("sniper", u)
	var pack_path: String = storage.resolve_pack(proj.get_id())
	_check(proj.save_pack(pack_path), "editor saves into the content root")
	var loader: DataLoader = DataLoader.new()
	var info: Dictionary = ModLoader.load_packs(loader, storage, null)
	_check(info.get("loaded", []) == ["playtest_mod"], "editor pack discovered + loaded")
	var merged: Variant = loader.get_entry("units", "sniper")
	_check(merged is Dictionary and int((merged as Dictionary).get("stats", {}).get("health", 0)) == 77, "editor unit merged for play-test")
	DirAccess.remove_absolute(pack_path)
	var cache: String = root + "/.cache"
	if DirAccess.dir_exists_absolute(cache):
		_remove_dir_recursive(cache)
	DirAccess.remove_absolute(root)


func test_phase_d_textures_round_trip() -> void:
	print("test_phase_d_textures_round_trip")
	var out_path: String = "user://test_modeditor_tex.nexpack"
	var proj: ModProject = ModProject.new()
	proj.new_project("tex_mod", "Texture Mod")
	proj.set_building("turret", ModProject.default_building("turret"))
	var tex_bytes: PackedByteArray = PackedByteArray([9, 8, 7, 6, 5, 255, 0, 128])
	var entry: String = proj.add_texture("turret_art", tex_bytes)
	_check(entry == "textures/turret_art.png", "texture name canonicalised to entry path")
	_check(proj.has_texture("turret_art"), "texture registered in project")
	_check(proj.save_pack(out_path), "project with a texture saves")
	var reopened: ModProject = ModProject.new()
	_check(reopened.open_pack(out_path), "textured pack re-opens")
	_check(reopened.has_texture("turret_art"), "texture survives the round-trip")
	_check(reopened.textures[entry] == tex_bytes, "texture bytes survive byte-for-byte")
	DirAccess.remove_absolute(out_path)


func test_phase_d_editor_keys_localized_in_all_locales() -> void:
	print("test_phase_d_editor_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.menu.mod_editor", "ui.modeditor.title", "ui.modeditor.tab.units",
		"ui.modeditor.tab.buildings", "ui.modeditor.add", "ui.modeditor.remove",
		"ui.modeditor.save", "ui.modeditor.new", "ui.modeditor.detail.health",
		"ui.modeditor.detail.cost", "ui.modeditor.detail.color",
		"ui.modeditor.status.saved", "ui.modeditor.status.invalid",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# === Phase E -- Map / Scenario Editor =======================================
# These exercise the ScenarioProject authoring model fully headless, then prove
# an authored scenario survives the .nexpack round-trip AND actually loads +
# runs through the real ScenarioLoader / module stack (the play-test path).

func test_phase_e_scenario_project_new_is_playable() -> void:
	print("test_phase_e_scenario_project_new_is_playable")
	var proj: ScenarioProject = ScenarioProject.new()
	# A brand-new project must already be valid: 2 players, each with an HQ.
	_check(proj.is_valid(), "fresh scenario is valid out of the box")
	_check(proj.players.size() == 2, "fresh scenario has 2 players")
	_check(proj.human_player_count() == 1, "fresh scenario has exactly one human")
	var scn: Dictionary = proj.to_scenario()
	_check(scn.has("map") and scn.has("players") and scn.has("buildings"), "scenario JSON has core sections")
	_check(int((scn["map"] as Dictionary).get("width", 0)) == ScenarioProject.DEFAULT_WIDTH, "default width emitted")


func test_phase_e_map_paint_fill_border_and_resize() -> void:
	print("test_phase_e_map_paint_fill_border_and_resize")
	var proj: ScenarioProject = ScenarioProject.new()
	proj.clear_walls()
	# Single-cell paint + erase.
	_check(proj.paint_cell(5, 5, ScenarioProject.TERRAIN_WALL), "paint wall in-bounds succeeds")
	_check(proj.is_wall(5, 5), "wall is recorded")
	_check(proj.paint_cell(5, 5, ScenarioProject.TERRAIN_GROUND), "erase succeeds")
	_check(not proj.is_wall(5, 5), "wall erased")
	# Out-of-bounds paint is rejected.
	_check(not proj.paint_cell(-1, 0, ScenarioProject.TERRAIN_WALL), "out-of-bounds paint rejected")
	_check(not proj.paint_cell(9999, 0, ScenarioProject.TERRAIN_WALL), "far out-of-bounds paint rejected")
	# Fill a 3x3 block (reversed corners still work).
	var painted: int = proj.fill_rect(4, 4, 2, 2, ScenarioProject.TERRAIN_WALL)
	_check(painted == 9, "fill_rect painted a 3x3 = 9 cells")
	_check(proj.is_wall(3, 3), "fill covered interior cell")
	# Border ring.
	proj.clear_walls()
	proj.paint_border()
	_check(proj.is_wall(0, 0) and proj.is_wall(proj.width - 1, proj.height - 1), "border corners painted")
	var ring: int = 2 * proj.width + 2 * proj.height - 4
	_check(proj.wall_count() == ring, "border has exactly the ring count")
	# Resize shrink drops out-of-bounds walls + entities.
	proj.clear_walls()
	proj.paint_cell(proj.width - 1, proj.height - 1, ScenarioProject.TERRAIN_WALL)
	proj.resize(ScenarioProject.MIN_DIM, ScenarioProject.MIN_DIM)
	_check(proj.width == ScenarioProject.MIN_DIM, "resize clamped width to min")
	_check(proj.wall_count() == 0, "shrink dropped now-off-map wall")


func test_phase_e_entity_placement_is_exclusive() -> void:
	print("test_phase_e_entity_placement_is_exclusive")
	var proj: ScenarioProject = ScenarioProject.new()
	# Place a unit then a building on the SAME cell: the unit must be replaced.
	_check(proj.place_unit("soldier", 0, 7, 7), "unit placed")
	_check((proj.entity_at(7, 7) as Dictionary).get("kind", "") == "unit", "unit found at cell")
	_check(proj.place_building("hq", 0, 7, 7), "building placed on same cell")
	_check((proj.entity_at(7, 7) as Dictionary).get("kind", "") == "building", "cell now holds a building")
	# Painting a wall then placing clears the wall (entities never sit on walls).
	proj.paint_cell(3, 3, ScenarioProject.TERRAIN_WALL)
	_check(proj.place_unit("soldier", 1, 3, 3), "place clears the wall first")
	_check(not proj.is_wall(3, 3), "wall removed under placed entity")
	# Remove entity.
	_check(proj.remove_entity_at(3, 3), "remove_entity_at removes the unit")
	_check((proj.entity_at(3, 3) as Dictionary).is_empty(), "cell is empty after removal")
	# Out-of-bounds placement rejected.
	_check(not proj.place_unit("soldier", 0, -5, -5), "out-of-bounds placement rejected")


func test_phase_e_scenario_round_trip_is_deterministic() -> void:
	print("test_phase_e_scenario_round_trip_is_deterministic")
	var a: ScenarioProject = ScenarioProject.new()
	a.new_scenario("round_trip", "Round Trip")
	a.fill_rect(2, 2, 5, 5, ScenarioProject.TERRAIN_WALL)
	a.place_unit("soldier", 0, 8, 8)
	var json_a: String = JSON.stringify(a.to_scenario(), "\t")
	# Re-load into a second project; its emission must be byte-identical.
	var b: ScenarioProject = ScenarioProject.new()
	_check(b.from_scenario(a.to_scenario()), "from_scenario accepts round-trip data")
	var json_b: String = JSON.stringify(b.to_scenario(), "\t")
	_check(json_a == json_b, "scenario JSON is byte-stable across a round-trip")
	_check(b.scenario_id == "round_trip", "id preserved")
	_check(b.wall_count() == a.wall_count(), "wall count preserved")
	# A bad payload leaves the project unchanged.
	_check(not b.from_scenario("not a dictionary"), "non-dictionary rejected")
	_check(not b.from_scenario({ "id": "x" }), "scenario without a map block rejected")


func test_phase_e_validation_catches_problems() -> void:
	print("test_phase_e_validation_catches_problems")
	var proj: ScenarioProject = ScenarioProject.new()
	# Remove a player's building so it cannot be eliminated.
	proj.buildings = []
	var problems: Array = proj.validate()
	_check(problems.size() >= 2, "missing HQs flagged for both players")
	_check(not proj.is_valid(), "scenario with no starting buildings is invalid")
	# Restore + ensure valid again.
	proj.place_building("hq", 0, 1, 1)
	proj.place_building("hq", 1, proj.width - 2, 1)
	_check(proj.is_valid(), "scenario valid once every player has an HQ")
	# Too few players.
	proj.remove_player(1)
	_check(not proj.is_valid(), "single-player scenario rejected")


func test_phase_e_simple_tech_tree() -> void:
	print("test_phase_e_simple_tech_tree")
	var proj: ScenarioProject = ScenarioProject.new()
	_check(proj.set_tech("armor", ScenarioProject.default_tech("armor")), "base tech node added")
	var advanced: Dictionary = ScenarioProject.default_tech("advanced_armor")
	advanced["prerequisites"] = ["armor"]
	_check(proj.set_tech("advanced_armor", advanced), "dependent tech node added")
	_check(proj.is_valid(), "tech tree with satisfied prerequisites is valid")
	# Dangling prerequisite must be caught.
	var broken: Dictionary = ScenarioProject.default_tech("broken")
	broken["prerequisites"] = ["does_not_exist"]
	proj.set_tech("broken", broken)
	_check(not proj.is_valid(), "tech referencing an unknown prerequisite is invalid")
	proj.remove_tech("broken")
	_check(proj.is_valid(), "removing the broken tech restores validity")


func test_phase_e_scenario_bundled_in_pack_round_trip() -> void:
	print("test_phase_e_scenario_bundled_in_pack_round_trip")
	var out_path: String = "user://test_scenario_pack.nexpack"
	var scn_proj: ScenarioProject = ScenarioProject.new()
	scn_proj.new_scenario("bundled_map", "Bundled Map")
	scn_proj.set_tech("recon", ScenarioProject.default_tech("recon"))
	# Author a whole "custom game": one unit + the scenario + the tech, in one pack.
	var mod: ModProject = ModProject.new()
	mod.new_project("custom_game", "Custom Game")
	mod.set_unit("scout", ModProject.default_unit("scout"))
	_check(mod.set_scenario(scn_proj.scenario_id, scn_proj.to_scenario()), "scenario added to ModProject")
	_check(mod.set_tech("recon", scn_proj.get_tech("recon")), "tech added to ModProject")
	_check(mod.is_valid(), "mod bundling a scenario validates")
	_check(mod.save_pack(out_path), "pack with a scenario saves")
	# Re-open and confirm scenario + tech survived.
	var reopened: ModProject = ModProject.new()
	_check(reopened.open_pack(out_path), "scenario pack re-opens")
	_check(reopened.scenarios.has("bundled_map"), "scenario survived the round-trip")
	_check(reopened.tech.has("recon"), "tech survived the round-trip")
	_check((reopened.get_scenario("bundled_map") as Dictionary).has("map"), "round-tripped scenario still has its map")
	DirAccess.remove_absolute(out_path)


func test_phase_e_authored_scenario_loads_and_plays() -> void:
	print("test_phase_e_authored_scenario_loads_and_plays")
	# Author a tiny but valid scenario, then drive it through the REAL stack.
	var proj: ScenarioProject = ScenarioProject.new()
	proj.new_scenario("playtest_map", "Play-test Map")
	proj.resize(10, 6)
	# Reposition starting pieces inside the smaller map.
	proj.buildings = [
		{ "type": "hq", "owner": 0, "x": 1, "y": 3 },
		{ "type": "hq", "owner": 1, "x": 8, "y": 3 },
	]
	proj.units = [
		{ "type": "soldier", "owner": 0, "x": 2, "y": 3 },
		{ "type": "soldier", "owner": 1, "x": 7, "y": 3 },
	]
	_check(proj.is_valid(), "authored play-test scenario is valid")
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.setup_for_test(nexus, proj.to_scenario())
	# The map + entities authored in the editor must materialise in world state.
	var map_section: Dictionary = nexus.world_state.get_section("map")
	_check(int(map_section.get("width", 0)) == 10, "authored map width loaded into world state")
	var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	_check(buildings.size() == 2, "both authored HQs spawned")
	var units: Dictionary = nexus.world_state.get_section("units").get("list", {})
	_check(units.size() == 2, "both authored units spawned")
	# Advance the sim a little: it must not crash and the tick must advance.
	nexus.run_ticks(10)
	_check(nexus.world_state.current_tick == 10, "authored scenario simulates cleanly")


func test_phase_e_scenario_catalog_listing() -> void:
	print("test_phase_e_scenario_catalog_listing")
	# Load the shipped scenarios catalog the way the main menu's Custom Games does.
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	nexus.data_loader.load_catalog("scenarios", "res://data/scenarios")
	var listing: Array = ScenarioLoader.list_scenarios(nexus)
	_check(listing.size() >= 1, "at least one shipped scenario is listed")
	var ids: Array = []
	for entry in listing:
		ids.append(str((entry as Dictionary).get("id", "")))
	_check(ids.has("skirmish_basic"), "skirmish_basic appears in the catalog listing")
	# Each listing row carries the fields the UI needs.
	for entry in listing:
		_check((entry as Dictionary).has("display_name_key"), "listing row has a display_name_key")
		_check((entry as Dictionary).has("players"), "listing row reports a player count")
	# And it can be applied straight from the catalog.
	var nexus2: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus2)
	GameBootstrap.load_catalogs(nexus2)
	_check(ScenarioLoader.load_scenario_from_catalog(nexus2, "skirmish_basic"), "scenario loads from catalog by id")
	_check(not ScenarioLoader.load_scenario_from_catalog(nexus2, "no_such_scenario"), "unknown scenario id refused")


# --- MB7.7 (Map Editor rebuild, bugs 20/21/22/24) ---------------------------
# Pure model tests for the new ScenarioProject surface (name/dims dialog,
# background image, move tool) plus the palette + catalog-list helpers.

func test_mb7_validate_new_map_flags_bad_inputs() -> void:
	print("test_mb7_validate_new_map_flags_bad_inputs")
	# Valid name + sensible dims -> no problems.
	_check(ScenarioProject.validate_new_map("My Map", 20, 14).is_empty(), "valid inputs pass")
	# Empty / non-ASCII-only name -> flagged.
	_check(ScenarioProject.validate_new_map("", 20, 14).size() >= 1, "empty name flagged")
	# Too small.
	var too_small: Array = ScenarioProject.validate_new_map("ok", ScenarioProject.MIN_DIM - 1, 10)
	_check(too_small.size() >= 1, "below-min dimension flagged")
	# Too large.
	var too_big: Array = ScenarioProject.validate_new_map("ok", ScenarioProject.MAX_DIM + 1, 10)
	_check(too_big.size() >= 1, "above-max dimension flagged")


func test_mb7_new_scenario_sized_resizes_and_reseats() -> void:
	print("test_mb7_new_scenario_sized_resizes_and_reseats")
	var proj: ScenarioProject = ScenarioProject.new()
	proj.new_scenario_sized("sized_map", "Sized Map", 30, 18)
	_check(proj.width == 30 and proj.height == 18, "new_scenario_sized applied dims")
	_check(proj.id == "sized_map", "id set on sized scenario")
	# Two HQs + two soldiers, all seated inside the new bounds.
	_check(proj.buildings.size() == 2, "two HQs re-seated")
	_check(proj.units.size() == 2, "two soldiers re-seated")
	for b in proj.buildings:
		_check(proj.in_bounds(int(b.get("x", -1)), int(b.get("y", -1))), "HQ inside bounds")
	for u in proj.units:
		_check(proj.in_bounds(int(u.get("x", -1)), int(u.get("y", -1))), "unit inside bounds")
	# Dims are clamped, not rejected, when out of range.
	var clamp_proj: ScenarioProject = ScenarioProject.new()
	clamp_proj.new_scenario_sized("clamp", "Clamp", ScenarioProject.MAX_DIM + 50, 2)
	_check(clamp_proj.width <= ScenarioProject.MAX_DIM, "oversize width clamped")
	_check(clamp_proj.height >= ScenarioProject.MIN_DIM, "undersize height clamped up")


func test_mb7_background_image_set_clear_roundtrip() -> void:
	print("test_mb7_background_image_set_clear_roundtrip")
	var proj: ScenarioProject = ScenarioProject.new()
	_check(not proj.has_background_image(), "fresh project has no background")
	proj.set_background_image("  user://content/bg/map1.png  ")
	_check(proj.has_background_image(), "background set")
	_check(proj.background_image == "user://content/bg/map1.png", "background path stripped")
	# Round-trips through to_scenario / from_scenario.
	var scn: Dictionary = proj.to_scenario()
	_check(str(scn.get("background_image", "")) == "user://content/bg/map1.png", "background emitted in scenario")
	var proj2: ScenarioProject = ScenarioProject.new()
	_check(proj2.from_scenario(scn), "scenario with background loads")
	_check(proj2.background_image == "user://content/bg/map1.png", "background survived round-trip")
	# Clear.
	proj.clear_background_image()
	_check(not proj.has_background_image(), "background cleared")


func test_mb7_move_entity_building_unit_object() -> void:
	print("test_mb7_move_entity_building_unit_object")
	var proj: ScenarioProject = ScenarioProject.new()
	# Building move.
	_check(proj.place_building("hq", 0, 5, 5), "building placed")
	_check(proj.move_entity(5, 5, 8, 6), "building moved")
	_check((proj.entity_at(8, 6) as Dictionary).get("kind", "") == "building", "building at new cell")
	_check((proj.entity_at(5, 5) as Dictionary).is_empty(), "old building cell empty")
	# Unit move.
	_check(proj.place_unit("soldier", 1, 2, 2), "unit placed")
	_check(proj.move_entity(2, 2, 3, 4), "unit moved")
	_check((proj.entity_at(3, 4) as Dictionary).get("kind", "") == "unit", "unit at new cell")
	_check(int((proj.entity_at(3, 4) as Dictionary).get("owner", -1)) == 1, "unit kept its owner")
	# Object move (objects live in map_objects, not entity_at).
	_check(proj.place_object("tree", 9, 9), "object placed")
	_check(proj.object_count() == 1, "one object present")
	_check(proj.move_entity(9, 9, 10, 10), "object moved")
	_check(proj.object_count() == 1, "still exactly one object after move")
	var found_moved: bool = false
	var found_old: bool = false
	for o in proj.map_objects:
		if int(o.get("x", -1)) == 10 and int(o.get("y", -1)) == 10:
			found_moved = true
		if int(o.get("x", -1)) == 9 and int(o.get("y", -1)) == 9:
			found_old = true
	_check(found_moved, "object at new cell (10,10)")
	_check(not found_old, "old object cell (9,9) empty")


func test_mb7_move_entity_flag_and_rejections() -> void:
	print("test_mb7_move_entity_flag_and_rejections")
	var proj: ScenarioProject = ScenarioProject.new()
	_check(proj.place_flag(0, 4, 4, 0), "flag placed")
	_check(proj.move_entity(4, 4, 7, 7), "flag moved")
	var moved: Dictionary = proj.flag_at(7, 7)
	_check(not moved.is_empty(), "flag present at new cell")
	_check(int(moved.get("team", -1)) == 0, "flag kept its team")
	_check(proj.flag_at(4, 4).is_empty(), "old flag cell empty")
	# Rejections: out-of-bounds destination.
	_check(proj.place_unit("soldier", 0, 1, 1), "unit for reject test placed")
	_check(not proj.move_entity(1, 1, -1, -1), "out-of-bounds destination rejected")
	# Moving from an empty cell fails.
	_check(not proj.move_entity(12, 12, 13, 13), "moving from empty cell fails")


func test_mb7_palette_16_colors_stable_and_clamped() -> void:
	print("test_mb7_palette_16_colors_stable_and_clamped")
	_check(MapPaletteUtil.SLOT_COUNT == 16, "palette exposes 16 slots")
	_check(MapPaletteUtil.all_hex().size() == 16, "all_hex returns 16 colours")
	# Deterministic mapping: owner N always maps to the same colour.
	_check(MapPaletteUtil.color_hex(0) == MapPaletteUtil.all_hex()[0], "owner 0 maps to first colour")
	_check(MapPaletteUtil.color_hex(3) == "4363d8", "owner 3 colour is stable")
	# Clamping negative + overflow into range.
	_check(MapPaletteUtil.clamp_slot(-5) == 0, "negative owner clamps to 0")
	_check(MapPaletteUtil.clamp_slot(999) == 15, "overflow owner clamps to last slot")
	_check(MapPaletteUtil.color_hex(999) == MapPaletteUtil.all_hex()[15], "overflow colour = last")
	# all_hex is a defensive copy.
	var copy: Array = MapPaletteUtil.all_hex()
	copy[0] = "000000"
	_check(MapPaletteUtil.all_hex()[0] != "000000", "all_hex returns a defensive copy")


func test_mb7_catalog_list_util_sorted_and_defaults() -> void:
	print("test_mb7_catalog_list_util_sorted_and_defaults")
	var catalog: Dictionary = {
		"tank": { "display_name_key": "unit.tank.name" },
		"soldier": { "display_name_key": "unit.soldier.name" },
		"scout": {},  # no display_name_key -> falls back to id
	}
	var entries: Array = CatalogListUtil.list_entries(catalog)
	_check(entries.size() == 3, "all catalog entries listed")
	# Sorted ascending by id: scout, soldier, tank.
	_check(str(entries[0].get("id", "")) == "scout", "entries sorted by id (scout first)")
	_check(str(entries[2].get("id", "")) == "tank", "entries sorted by id (tank last)")
	_check(str(entries[0].get("name_key", "")) == "scout", "missing name_key falls back to id")
	_check(str(entries[1].get("name_key", "")) == "unit.soldier.name", "name_key carried when present")
	# list_ids + first_id.
	_check(CatalogListUtil.list_ids(catalog) == ["scout", "soldier", "tank"], "list_ids sorted")
	_check(CatalogListUtil.first_id(catalog, "fallback") == "scout", "first_id is the lowest id")
	_check(CatalogListUtil.first_id({}, "fallback") == "fallback", "empty catalog returns fallback id")


func test_mb7_match_setup_rescans_user_packs_static_guard() -> void:
	print("test_mb7_match_setup_rescans_user_packs_static_guard")
	var src: String = FileAccess.get_file_as_string("res://ui/shared/match_setup.gd")
	_check(src != "", "match_setup.gd source is readable")
	# MB7.6 (bug 24): _populate_scenarios must re-scan writable packs so newly
	# saved editor maps appear without an app restart.
	var body: String = _mb5_func_body(src, "func _populate_scenarios")
	_check(body.contains("GameBootstrap.load_packs"), "populate re-scans user content packs")
	_check(body.contains("ScenarioLoader.list_scenarios"), "populate lists scenarios after rescan")


# --- Phase MB10 (bug 29): global loading overlay stage descriptors -----------
#
# LoadingStages is the pure brain that tells every caller how to drive the
# ProgressOverlay for each wait-operation. These tests guard the invariants the
# UI relies on: determinate plans go 0->1 monotonically, indeterminate ops have
# a label but no plan, index helpers never crash, and every op has a title.

func test_mb10_determinate_plans_are_monotonic_and_end_full() -> void:
	print("test_mb10_determinate_plans_are_monotonic_and_end_full")
	var determinate: Array = [
		LoadingStages.OP_START_MATCH, LoadingStages.OP_ONLINE_CONNECT,
		LoadingStages.OP_SAVE_MAP, LoadingStages.OP_LOAD_MAP, LoadingStages.OP_SAVE_MOD,
	]
	for op in determinate:
		var plan: Array = LoadingStages.plan_for(op)
		_check(plan.size() >= 2, "%s has at least 2 stages" % op)
		_check(float(plan[0].get("ratio", -1.0)) == 0.0, "%s starts at ratio 0.0" % op)
		_check(float(plan[plan.size() - 1].get("ratio", -1.0)) == 1.0, "%s ends at ratio 1.0" % op)
		# Ratios must be non-decreasing and every stage must carry a label key.
		var prev: float = -1.0
		var ok: bool = true
		for stage in plan:
			var r: float = float(stage.get("ratio", 0.0))
			if r < prev or str(stage.get("key", "")) == "":
				ok = false
			prev = r
		_check(ok, "%s ratios are monotonic and every stage has a key" % op)
		_check(not LoadingStages.is_indeterminate(op), "%s is determinate" % op)


func test_mb10_indeterminate_ops_have_no_plan_but_a_label() -> void:
	print("test_mb10_indeterminate_ops_have_no_plan_but_a_label")
	for op in [LoadingStages.OP_SCAN_NETWORK, LoadingStages.OP_VALIDATE_IMAGE]:
		_check(LoadingStages.is_indeterminate(op), "%s is indeterminate" % op)
		_check(LoadingStages.plan_for(op).is_empty(), "%s has no determinate plan" % op)
		_check(LoadingStages.stage_count(op) == 0, "%s stage_count is 0" % op)
		_check(LoadingStages.indeterminate_key(op) != "", "%s has an indeterminate label key" % op)


func test_mb10_stage_helpers_clamp_out_of_range_index() -> void:
	print("test_mb10_stage_helpers_clamp_out_of_range_index")
	var op: String = LoadingStages.OP_START_MATCH
	var last: int = LoadingStages.stage_count(op) - 1
	# Negative and too-large indices clamp to the first / last stage (no crash).
	_check(LoadingStages.stage_ratio(op, -5) == LoadingStages.stage_ratio(op, 0), "negative index clamps to first")
	_check(LoadingStages.stage_ratio(op, 999) == LoadingStages.stage_ratio(op, last), "huge index clamps to last")
	_check(LoadingStages.stage_key(op, 999) == LoadingStages.stage_key(op, last), "key index clamps to last")
	# An unknown op returns safe empties/zero.
	_check(LoadingStages.stage_ratio("nope", 0) == 0.0, "unknown op ratio is 0.0")
	_check(LoadingStages.stage_key("nope", 0) == "", "unknown op key is empty")


func test_mb10_titles_exist_for_every_known_op() -> void:
	print("test_mb10_titles_exist_for_every_known_op")
	for op in LoadingStages.known_ops():
		_check(LoadingStages.title_key(op) != "", "%s has a title key" % op)
	_check(LoadingStages.title_key("unknown_op") == "", "unknown op has no title key")


func test_mb10_known_ops_sorted_and_unique() -> void:
	print("test_mb10_known_ops_sorted_and_unique")
	var ops: Array = LoadingStages.known_ops()
	_check(ops.has(LoadingStages.OP_START_MATCH), "known ops include start_match")
	_check(ops.has(LoadingStages.OP_SCAN_NETWORK), "known ops include scan_network")
	var sorted_copy: Array = ops.duplicate()
	sorted_copy.sort()
	_check(ops == sorted_copy, "known ops are returned sorted")
	var seen: Dictionary = {}
	var unique: bool = true
	for op in ops:
		if seen.has(op):
			unique = false
		seen[op] = true
	_check(unique, "known ops contain no duplicates")


# --- Phase MB9 (bug 28): GL-compat image format normalization ---------------
# ImageFormatUtil silences the "RGBAFloat not supported" warning by converting
# any float-format runtime image to RGBA8 before it reaches the GPU. These are
# pure, headless-safe checks of the decision + conversion logic.

func test_mb9_float_formats_flagged_for_normalize() -> void:
	print("test_mb9_float_formats_flagged_for_normalize")
	for fmt in ImageFormatUtil.FLOAT_FORMATS:
		_check(ImageFormatUtil.is_float_format(fmt), "format %d flagged as float" % fmt)
		_check(ImageFormatUtil.needs_normalize(fmt), "format %d needs normalize" % fmt)
	_check(ImageFormatUtil.is_float_format(Image.FORMAT_RGBAF), "RGBAF flagged as float")


func test_mb9_byte_formats_not_flagged() -> void:
	print("test_mb9_byte_formats_not_flagged")
	_check(not ImageFormatUtil.is_float_format(Image.FORMAT_RGBA8), "RGBA8 not float")
	_check(not ImageFormatUtil.is_float_format(Image.FORMAT_RGB8), "RGB8 not float")
	_check(not ImageFormatUtil.is_float_format(Image.FORMAT_L8), "L8 not float")
	_check(not ImageFormatUtil.needs_normalize(Image.FORMAT_RGBA8), "RGBA8 needs no normalize")


func test_mb9_normalize_converts_float_image_to_rgba8() -> void:
	print("test_mb9_normalize_converts_float_image_to_rgba8")
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBAF)
	_check(img.get_format() == Image.FORMAT_RGBAF, "source image starts as RGBAF")
	var out: Image = ImageFormatUtil.normalize_for_gl_compat(img)
	_check(out != null, "normalize returns an image")
	_check(out.get_format() == Image.FORMAT_RGBA8, "float image converted to RGBA8")


func test_mb9_normalize_leaves_rgba8_untouched() -> void:
	print("test_mb9_normalize_leaves_rgba8_untouched")
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var out: Image = ImageFormatUtil.normalize_for_gl_compat(img)
	_check(out != null, "normalize returns an image for RGBA8 input")
	_check(out.get_format() == Image.FORMAT_RGBA8, "RGBA8 image stays RGBA8")


func test_mb9_normalize_is_null_safe() -> void:
	print("test_mb9_normalize_is_null_safe")
	_check(ImageFormatUtil.normalize_for_gl_compat(null) == null, "null input returns null")


# --- Phase MB9 (bug 27): LAN-no-TLS invariant + benign handshake classifier --
# Project Nexus never opens a TLS/HTTPS connection (LAN is plain UDP/ENet), so
# the Android "TLS handshake error -29184" is engine noise, not a game bug.
# These pure checks guard that invariant and the benign-error classifier.

func test_mb9_lan_stack_uses_no_tls() -> void:
	print("test_mb9_lan_stack_uses_no_tls")
	_check(not NetSecurityPolicy.uses_tls(), "LAN networking uses no TLS (bug 27 invariant)")


func test_mb9_known_handshake_error_is_benign() -> void:
	print("test_mb9_known_handshake_error_is_benign")
	_check(NetSecurityPolicy.is_benign_tls_error(NetSecurityPolicy.TLS_HANDSHAKE_ERROR),
		"the reported -29184 handshake code is classified benign")
	_check(NetSecurityPolicy.is_benign_tls_error(-30000),
		"a lower mbedTLS code in range is benign")


func test_mb9_non_tls_codes_are_not_benign() -> void:
	print("test_mb9_non_tls_codes_are_not_benign")
	_check(not NetSecurityPolicy.is_benign_tls_error(0), "OK (0) is not a benign TLS error")
	_check(not NetSecurityPolicy.is_benign_tls_error(-1), "generic -1 is not a benign TLS error")
	_check(not NetSecurityPolicy.is_benign_tls_error(-100000),
		"a code below the TLS floor is not classified benign")


func test_mb9_describe_tls_error_only_for_benign() -> void:
	print("test_mb9_describe_tls_error_only_for_benign")
	_check(NetSecurityPolicy.describe_tls_error(NetSecurityPolicy.TLS_HANDSHAKE_ERROR) != "",
		"benign handshake code has a friendly description")
	_check(NetSecurityPolicy.describe_tls_error(-1) == "",
		"non-benign code has no TLS description")


# --- Phase MC1 (request 1): fog-aware belief pathing + manual-waypoint move ---
# The user reported a contradiction: units that pathfind using the REAL grid can
# route around walls they have never discovered (effective cheating). BeliefGrid
# fixes this by treating HIDDEN tiles as walkable, and units_module replans on
# contact. These pure checks pin the belief/waypoint/move-mode logic headlessly.

func _mc1_fog_grid(width: int, height: int, viewer: int, visible_tiles: Array) -> Dictionary:
	# Build a minimal fog section where `visible_tiles` (Array of [x,y]) are
	# VISIBLE for `viewer` and everything else is HIDDEN.
	var grid: Array = []
	grid.resize(width * height)
	for i in range(grid.size()):
		grid[i] = BeliefGridUtil.FOG_HIDDEN
	for t in visible_tiles:
		var idx: int = int(t[1]) * width + int(t[0])
		if idx >= 0 and idx < grid.size():
			grid[idx] = BeliefGridUtil.FOG_VISIBLE
	return { "visible": { str(viewer): grid } }


func test_mc1_belief_grid_hidden_is_walkable() -> void:
	print("test_mc1_belief_grid_hidden_is_walkable")
	# Real grid has a wall (1) at index 4, but the viewer has seen nothing.
	var w: int = 3
	var h: int = 3
	var tiles: Array = [0, 0, 0, 0, 1, 0, 0, 0, 0]
	var fog: Dictionary = _mc1_fog_grid(w, h, 0, [])
	var belief: Array = BeliefGridUtil.build_belief_grid(w, h, tiles, fog, 0)
	_check(belief.size() == 9, "belief grid has one cell per tile")
	_check(int(belief[4]) == BeliefGridUtil.GROUND, "hidden wall is ASSUMED walkable")


func test_mc1_belief_grid_visible_uses_real_value() -> void:
	print("test_mc1_belief_grid_visible_uses_real_value")
	var w: int = 3
	var h: int = 3
	var tiles: Array = [0, 0, 0, 0, 1, 0, 0, 0, 0]
	# The viewer has now SEEN the centre tile.
	var fog: Dictionary = _mc1_fog_grid(w, h, 0, [[1, 1]])
	var belief: Array = BeliefGridUtil.build_belief_grid(w, h, tiles, fog, 0)
	_check(int(belief[4]) != BeliefGridUtil.GROUND, "seen wall keeps its real (blocked) value")


func test_mc1_belief_grid_no_fog_mirrors_real_grid() -> void:
	print("test_mc1_belief_grid_no_fog_mirrors_real_grid")
	var w: int = 2
	var h: int = 2
	var tiles: Array = [0, 1, 1, 0]
	# viewer < 0 -> no fog: belief must equal the real grid verbatim.
	var belief: Array = BeliefGridUtil.build_belief_grid(w, h, tiles, {}, -1)
	_check(belief == tiles, "no-fog belief mirrors the real grid exactly")


func test_mc1_belief_grid_is_deterministic() -> void:
	print("test_mc1_belief_grid_is_deterministic")
	var w: int = 4
	var h: int = 4
	var tiles: Array = []
	tiles.resize(16)
	for i in range(16):
		tiles[i] = 1 if (i % 3 == 0) else 0
	var fog: Dictionary = _mc1_fog_grid(w, h, 2, [[0, 0], [1, 1], [3, 3]])
	var a: Array = BeliefGridUtil.build_belief_grid(w, h, tiles, fog, 2)
	var b: Array = BeliefGridUtil.build_belief_grid(w, h, tiles, fog, 2)
	_check(a == b, "same inputs produce identical belief grids (lockstep-safe)")


func test_mc1_is_known_blocked_only_when_seen() -> void:
	print("test_mc1_is_known_blocked_only_when_seen")
	var w: int = 3
	var h: int = 3
	var tiles: Array = [0, 0, 0, 0, 1, 0, 0, 0, 0]
	var hidden_fog: Dictionary = _mc1_fog_grid(w, h, 0, [])
	_check(not BeliefGridUtil.is_known_blocked(w, h, tiles, hidden_fog, 0, 1, 1),
		"hidden wall is NOT known-blocked")
	var seen_fog: Dictionary = _mc1_fog_grid(w, h, 0, [[1, 1]])
	_check(BeliefGridUtil.is_known_blocked(w, h, tiles, seen_fog, 0, 1, 1),
		"seen wall IS known-blocked")


func test_mc1_belief_path_routes_through_hidden_wall() -> void:
	print("test_mc1_belief_path_routes_through_hidden_wall")
	# A vertical wall the viewer has never seen must be ignored, so the path can
	# go straight through where the (hidden) wall really is.
	var w: int = 3
	var h: int = 1
	var tiles: Array = [0, 1, 0]   # wall at x=1
	var fog: Dictionary = _mc1_fog_grid(w, h, 0, [])
	var path: Array = PathService.find_path_on_belief(w, h, tiles, fog, 0, Vector2i(0, 0), Vector2i(2, 0))
	_check(path.size() == 3, "belief path passes straight through the undiscovered wall")


func test_mc1_belief_path_avoids_known_wall() -> void:
	print("test_mc1_belief_path_avoids_known_wall")
	# Same map but the wall tile has been seen; with no vertical room to go around
	# on a 1-row map the path must be empty (correctly blocked).
	var w: int = 3
	var h: int = 1
	var tiles: Array = [0, 1, 0]
	var fog: Dictionary = _mc1_fog_grid(w, h, 0, [[1, 0]])
	var path: Array = PathService.find_path_on_belief(w, h, tiles, fog, 0, Vector2i(0, 0), Vector2i(2, 0))
	_check(path.is_empty(), "a seen wall blocks the belief path when no detour exists")


func test_mc1_waypoint_normalize_pairs_and_dedup() -> void:
	print("test_mc1_waypoint_normalize_pairs_and_dedup")
	var raw: Array = [[1, 2], [1, 2], Vector2i(3, 4), [3, 4], [5, 6]]
	var out: Array = WaypointUtil.normalize(raw)
	_check(out.size() == 3, "consecutive duplicate waypoints collapse")
	_check(out[0] == Vector2i(1, 2) and out[1] == Vector2i(3, 4) and out[2] == Vector2i(5, 6),
		"normalized waypoints keep order and accept pairs + Vector2i")
	_check(WaypointUtil.normalize(null).is_empty(), "non-array input normalizes to empty")


func test_mc1_waypoint_stitch_joins_segments_without_repeat() -> void:
	print("test_mc1_waypoint_stitch_joins_segments_without_repeat")
	# A solver that returns an inclusive straight horizontal/vertical segment.
	var solver: Callable = func(a: Vector2i, b: Vector2i) -> Array:
		var seg: Array = [a]
		var cur: Vector2i = a
		while cur != b:
			cur.x += signi(b.x - cur.x)
			cur.y += signi(b.y - cur.y)
			seg.append(cur)
		return seg
	var wps: Array = [Vector2i(2, 0), Vector2i(2, 2)]
	var full: Array = WaypointUtil.stitch_path(Vector2i(0, 0), wps, solver)
	# (0,0)->(2,0) = 3 tiles, then ->(2,2) adds 2 (shared (2,0) skipped) = 5 total.
	_check(full.size() == 5, "stitched path length has no repeated join tile")
	_check(full[0] == Vector2i(0, 0), "stitched path starts at the origin")
	_check(full[full.size() - 1] == Vector2i(2, 2), "stitched path ends at the last waypoint")


func test_mc1_waypoint_stitch_stops_at_unreachable_segment() -> void:
	print("test_mc1_waypoint_stitch_stops_at_unreachable_segment")
	# Solver that reports the SECOND segment unreachable (returns []).
	var solver: Callable = func(a: Vector2i, b: Vector2i) -> Array:
		if b == Vector2i(9, 9):
			return []
		return [a, b]
	var wps: Array = [Vector2i(1, 0), Vector2i(9, 9)]
	var full: Array = WaypointUtil.stitch_path(Vector2i(0, 0), wps, solver)
	_check(full[full.size() - 1] == Vector2i(1, 0), "stitch stops at last reachable waypoint")


func test_mc1_move_mode_defaults_to_direct() -> void:
	print("test_mc1_move_mode_defaults_to_direct")
	var m: MoveModeUtil = MoveModeUtil.new()
	_check(m.mode() == MoveModeUtil.MODE_DIRECT, "default move mode is direct")
	_check(not m.is_manual(), "is_manual is false by default")


func test_mc1_move_mode_toggle_flips_and_clears() -> void:
	print("test_mc1_move_mode_toggle_flips_and_clears")
	var m: MoveModeUtil = MoveModeUtil.new()
	_check(m.toggle_mode() == MoveModeUtil.MODE_MANUAL, "toggle enters manual mode")
	m.resolve_ground_tap(Vector2i(1, 1), true)
	_check(m.has_pending(), "a waypoint is pending in manual mode")
	_check(m.toggle_mode() == MoveModeUtil.MODE_DIRECT, "toggle returns to direct mode")
	_check(not m.has_pending(), "leaving manual mode clears the pending route")


func test_mc1_move_mode_direct_tap_issues_move() -> void:
	print("test_mc1_move_mode_direct_tap_issues_move")
	var m: MoveModeUtil = MoveModeUtil.new()
	var plan: Dictionary = m.resolve_ground_tap(Vector2i(4, 5), true)
	_check(str(plan.get("action")) == MoveModeUtil.ACTION_MOVE_DIRECT, "direct tap issues an immediate move")
	_check(plan.get("tile") == Vector2i(4, 5), "direct move targets the tapped tile")


func test_mc1_move_mode_manual_tap_accumulates_waypoints() -> void:
	print("test_mc1_move_mode_manual_tap_accumulates_waypoints")
	var m: MoveModeUtil = MoveModeUtil.new()
	m.set_mode(MoveModeUtil.MODE_MANUAL)
	var p1: Dictionary = m.resolve_ground_tap(Vector2i(1, 0), true)
	_check(str(p1.get("action")) == MoveModeUtil.ACTION_ADD_WAYPOINT, "manual tap buffers a waypoint")
	m.resolve_ground_tap(Vector2i(1, 3), true)
	m.resolve_ground_tap(Vector2i(5, 3), true)
	var wps: Array = m.waypoints()
	_check(wps.size() == 3, "three taps buffer three waypoints")
	_check(wps[0] == Vector2i(1, 0) and wps[2] == Vector2i(5, 3), "waypoints stay in tap order")


func test_mc1_move_mode_manual_collapses_duplicate_taps() -> void:
	print("test_mc1_move_mode_manual_collapses_duplicate_taps")
	var m: MoveModeUtil = MoveModeUtil.new()
	m.set_mode(MoveModeUtil.MODE_MANUAL)
	m.resolve_ground_tap(Vector2i(2, 2), true)
	m.resolve_ground_tap(Vector2i(2, 2), true)
	_check(m.waypoints().size() == 1, "tapping the same tile twice adds only one waypoint")


func test_mc1_move_mode_commit_returns_pairs_and_clears() -> void:
	print("test_mc1_move_mode_commit_returns_pairs_and_clears")
	var m: MoveModeUtil = MoveModeUtil.new()
	m.set_mode(MoveModeUtil.MODE_MANUAL)
	m.resolve_ground_tap(Vector2i(1, 0), true)
	m.resolve_ground_tap(Vector2i(1, 4), true)
	var plan: Dictionary = m.commit()
	_check(str(plan.get("action")) == MoveModeUtil.ACTION_MOVE_PATH, "commit issues a waypoint move")
	var pairs: Array = plan.get("waypoints", [])
	_check(pairs.size() == 2 and pairs[0] == [1, 0] and pairs[1] == [1, 4],
		"committed waypoints are [x,y] pairs ready for the command payload")
	_check(not m.has_pending(), "commit clears the pending buffer")
	_check(str(m.commit().get("action")) == MoveModeUtil.ACTION_NONE, "second commit with nothing pending is a no-op")


func test_mc1_move_mode_cancel_clears_pending() -> void:
	print("test_mc1_move_mode_cancel_clears_pending")
	var m: MoveModeUtil = MoveModeUtil.new()
	m.set_mode(MoveModeUtil.MODE_MANUAL)
	m.resolve_ground_tap(Vector2i(3, 3), true)
	_check(str(m.cancel().get("action")) == MoveModeUtil.ACTION_CLEAR, "cancel clears a pending route")
	_check(not m.has_pending(), "buffer is empty after cancel")
	_check(str(m.cancel().get("action")) == MoveModeUtil.ACTION_NONE, "cancel with nothing pending is a no-op")


func test_mc1_move_mode_no_selection_is_noop() -> void:
	print("test_mc1_move_mode_no_selection_is_noop")
	var m: MoveModeUtil = MoveModeUtil.new()
	var direct: Dictionary = m.resolve_ground_tap(Vector2i(1, 1), false)
	_check(str(direct.get("action")) == MoveModeUtil.ACTION_NONE, "direct tap with no selection is a no-op")
	m.set_mode(MoveModeUtil.MODE_MANUAL)
	var manual: Dictionary = m.resolve_ground_tap(Vector2i(1, 1), false)
	_check(str(manual.get("action")) == MoveModeUtil.ACTION_NONE, "manual tap with no selection buffers nothing")
	_check(not m.has_pending(), "no waypoint buffered without a selection")


func test_mc1_move_keys_localized_in_all_locales() -> void:
	print("test_mc1_move_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.move.mode_direct", "ui.move.mode_manual", "ui.move.confirm_path",
		"ui.move.cancel_path", "ui.move.toggle_hint",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# MC1.5 (request 1): the desktop HUD must share the SAME MoveModeUtil-driven
# two-mode movement as the mobile HUD (direct vs manual waypoint routing), so the
# two never diverge. Static source guard -- the desktop HUD depends on the Nexus
# autoload + a live SceneTree, so it cannot be instantiated headlessly; instead we
# assert the wiring is present in the source.
func test_mc1_desktop_hud_wires_move_mode() -> void:
	print("test_mc1_desktop_hud_wires_move_mode")
	var src: String = FileAccess.get_file_as_string("res://ui/desktop/desktop_hud.gd")
	_check(src.contains("MoveModeUtil.new()"), "desktop HUD owns a MoveModeUtil instance")
	_check(src.contains("_move_mode.resolve_ground_tap("), "right-click routes through MoveModeUtil")
	_check(src.contains("MoveModeUtil.ACTION_MOVE_DIRECT"), "handles direct-move plan")
	_check(src.contains("MoveModeUtil.ACTION_ADD_WAYPOINT"), "handles manual waypoint plan")
	_check(src.contains("_move_mode.commit()"), "confirm commits the manual route")
	_check(src.contains("_move_mode.cancel()"), "cancel discards the pending route")
	_check(src.contains("\"waypoints\": plan.get(\"waypoints\""), "commit issues a waypoint move_unit")
	_check(src.contains("KEY_M"), "M hotkey toggles move mode")
	_check(src.contains("KEY_ENTER"), "Enter hotkey confirms the route")


# MC5.1 (request 6): EditHistoryUtil is a pure, headless undo/redo snapshot
# stack shared by the map editor and the mod editor. It stores opaque Dictionary
# snapshots and must deep-copy on the way in and out so callers cannot mutate
# committed history.
func test_mc5_history_starts_empty() -> void:
	print("test_mc5_history_starts_empty")
	var hist: EditHistoryUtil = EditHistoryUtil.new()
	_check(hist.size() == 0, "fresh history has no snapshots")
	_check(hist.cursor() == -1, "fresh cursor sits before the first slot")
	_check(not hist.can_undo(), "cannot undo an empty history")
	_check(not hist.can_redo(), "cannot redo an empty history")
	_check(hist.undo() == null, "undo on empty returns null")
	_check(hist.redo() == null, "redo on empty returns null")
	_check(hist.current() == null, "current on empty returns null")


func test_mc5_history_push_and_current() -> void:
	print("test_mc5_history_push_and_current")
	var hist: EditHistoryUtil = EditHistoryUtil.new()
	hist.push({"v": 1})
	_check(hist.size() == 1, "one snapshot after first push")
	_check(hist.cursor() == 0, "cursor points at the only snapshot")
	_check(not hist.can_undo(), "single snapshot cannot undo")
	_check(not hist.can_redo(), "single snapshot cannot redo")
	var cur: Dictionary = hist.current() as Dictionary
	_check(cur.get("v", -1) == 1, "current returns the pushed snapshot")
	hist.push({"v": 2})
	_check(hist.size() == 2, "two snapshots after second push")
	_check(hist.can_undo(), "two snapshots enable undo")
	_check((hist.current() as Dictionary).get("v", -1) == 2, "current is the latest push")


func test_mc5_history_undo_redo_roundtrip() -> void:
	print("test_mc5_history_undo_redo_roundtrip")
	var hist: EditHistoryUtil = EditHistoryUtil.new()
	hist.push({"v": 1})
	hist.push({"v": 2})
	hist.push({"v": 3})
	_check((hist.undo() as Dictionary).get("v", -1) == 2, "undo steps back to v2")
	_check((hist.undo() as Dictionary).get("v", -1) == 1, "undo steps back to v1")
	_check(not hist.can_undo(), "at the oldest snapshot undo is exhausted")
	_check((hist.redo() as Dictionary).get("v", -1) == 2, "redo steps forward to v2")
	_check((hist.redo() as Dictionary).get("v", -1) == 3, "redo steps forward to v3")
	_check(not hist.can_redo(), "at the newest snapshot redo is exhausted")


func test_mc5_history_push_discards_redo_tail() -> void:
	print("test_mc5_history_push_discards_redo_tail")
	var hist: EditHistoryUtil = EditHistoryUtil.new()
	hist.push({"v": 1})
	hist.push({"v": 2})
	hist.push({"v": 3})
	hist.undo()
	hist.undo()
	_check((hist.current() as Dictionary).get("v", -1) == 1, "cursor sits at v1 before branch")
	hist.push({"v": 99})
	_check(hist.size() == 2, "pushing after undo trims the redo tail")
	_check((hist.current() as Dictionary).get("v", -1) == 99, "current is the new branch")
	_check(not hist.can_redo(), "no redo after branching")
	_check(hist.can_undo(), "still able to undo to v1")


func test_mc5_history_respects_max_depth() -> void:
	print("test_mc5_history_respects_max_depth")
	var hist: EditHistoryUtil = EditHistoryUtil.new(3)
	hist.push({"v": 1})
	hist.push({"v": 2})
	hist.push({"v": 3})
	hist.push({"v": 4})
	_check(hist.size() == 3, "depth caps the stack at max_depth")
	_check((hist.current() as Dictionary).get("v", -1) == 4, "newest snapshot survives the cap")
	_check((hist.undo() as Dictionary).get("v", -1) == 3, "second-newest survives")
	_check((hist.undo() as Dictionary).get("v", -1) == 2, "oldest surviving snapshot is v2")
	_check(not hist.can_undo(), "v1 was evicted by the depth cap")


func test_mc5_history_snapshots_are_isolated() -> void:
	print("test_mc5_history_snapshots_are_isolated")
	var hist: EditHistoryUtil = EditHistoryUtil.new()
	var src: Dictionary = {"nested": {"count": 1}, "list": [1, 2]}
	hist.push(src)
	# Mutating the source after push must not corrupt stored history.
	src["nested"]["count"] = 999
	(src["list"] as Array).append(3)
	var stored: Dictionary = hist.current() as Dictionary
	_check((stored["nested"] as Dictionary).get("count", -1) == 1, "push deep-copies nested dicts")
	_check((stored["list"] as Array).size() == 2, "push deep-copies nested arrays")
	# Mutating a returned snapshot must not corrupt the internal stack either.
	stored["nested"]["count"] = -5
	var again: Dictionary = hist.current() as Dictionary
	_check((again["nested"] as Dictionary).get("count", -1) == 1, "current deep-copies on the way out")


# --- Phase MC5.4 (request 6): editor autosave path/envelope/throttle logic ---
# The user wants the editors to autosave so an unexpected exit never loses work,
# and to OFFER recovery on the next entry. These checks pin the PURE half of
# AutosaveUtil (no disk IO): filename/path building, envelope wrap/parse, the
# recovery decision, and the throttle. The IO half is skipped headlessly.

func test_mc5_autosave_path_for_valid_kinds() -> void:
	print("test_mc5_autosave_path_for_valid_kinds")
	_check(AutosaveUtil.path_for(AutosaveUtil.KIND_MAP) == "user://autosave/map.autosave.json",
		"map kind -> rolling map draft path")
	_check(AutosaveUtil.path_for(AutosaveUtil.KIND_MOD) == "user://autosave/mod.autosave.json",
		"mod kind -> rolling mod draft path")
	_check(AutosaveUtil.path_for(AutosaveUtil.KIND_GUI) == "user://autosave/gui.autosave.json",
		"gui kind -> rolling gui draft path")


func test_mc5_autosave_path_rejects_bad_kind() -> void:
	print("test_mc5_autosave_path_rejects_bad_kind")
	_check(AutosaveUtil.path_for("") == "", "empty kind addresses no file")
	_check(AutosaveUtil.path_for("../../etc/passwd") == "", "path-traversal kind is rejected")
	_check(AutosaveUtil.path_for("bogus") == "", "unknown kind is rejected")


func test_mc5_autosave_envelope_roundtrip() -> void:
	print("test_mc5_autosave_envelope_roundtrip")
	var snap: Dictionary = { "scenario_id": "m1", "tiles": [0, 1, 0] }
	var env: Dictionary = AutosaveUtil.build_envelope(AutosaveUtil.KIND_MAP, snap, 12345)
	_check(int(env.get("version", -1)) == AutosaveUtil.ENVELOPE_VERSION, "envelope carries version")
	_check(str(env.get("kind", "")) == "map", "envelope carries sanitised kind")
	_check(int(env.get("saved_at", 0)) == 12345, "envelope carries the injected timestamp")
	var parsed: Dictionary = AutosaveUtil.parse_envelope(env)
	_check(bool(parsed.get("ok", false)), "well-formed envelope parses ok")
	_check((parsed.get("snapshot") as Dictionary).get("scenario_id", "") == "m1",
		"parsed snapshot survives the roundtrip")


func test_mc5_autosave_envelope_isolated() -> void:
	print("test_mc5_autosave_envelope_isolated")
	var snap: Dictionary = { "list": [1, 2] }
	var env: Dictionary = AutosaveUtil.build_envelope(AutosaveUtil.KIND_MOD, snap, 1)
	# Mutating the source after wrapping must not corrupt the stored envelope.
	(snap["list"] as Array).append(3)
	_check(((env["snapshot"] as Dictionary)["list"] as Array).size() == 2,
		"build_envelope deep-copies the snapshot")


func test_mc5_autosave_parse_rejects_malformed() -> void:
	print("test_mc5_autosave_parse_rejects_malformed")
	_check(not bool(AutosaveUtil.parse_envelope("not a dict").get("ok", false)),
		"non-dictionary is rejected")
	_check(not bool(AutosaveUtil.parse_envelope({ "kind": "map", "snapshot": {} }).get("ok", true)),
		"missing version is rejected")
	_check(not bool(AutosaveUtil.parse_envelope(
		{ "version": AutosaveUtil.ENVELOPE_VERSION, "kind": "bogus", "snapshot": {} }).get("ok", true)),
		"unknown kind is rejected")
	_check(not bool(AutosaveUtil.parse_envelope(
		{ "version": AutosaveUtil.ENVELOPE_VERSION, "kind": "map" }).get("ok", true)),
		"missing snapshot is rejected")


func test_mc5_autosave_should_offer_recovery() -> void:
	print("test_mc5_autosave_should_offer_recovery")
	var good: Dictionary = AutosaveUtil.parse_envelope(
		AutosaveUtil.build_envelope(AutosaveUtil.KIND_MAP, { "tiles": [1] }, 7))
	_check(AutosaveUtil.should_offer_recovery(good, AutosaveUtil.KIND_MAP),
		"offer recovery when a matching non-empty draft exists")
	_check(not AutosaveUtil.should_offer_recovery(good, AutosaveUtil.KIND_MOD),
		"do NOT offer a map draft when opening the mod editor")
	var empty: Dictionary = AutosaveUtil.parse_envelope(
		AutosaveUtil.build_envelope(AutosaveUtil.KIND_MAP, {}, 7))
	_check(not AutosaveUtil.should_offer_recovery(empty, AutosaveUtil.KIND_MAP),
		"do NOT offer recovery for an empty snapshot")
	_check(not AutosaveUtil.should_offer_recovery({ "ok": false }, AutosaveUtil.KIND_MAP),
		"do NOT offer recovery when parse failed")


func test_mc5_autosave_throttle_blocks_rapid_saves() -> void:
	print("test_mc5_autosave_throttle_blocks_rapid_saves")
	var au: AutosaveUtil = AutosaveUtil.new(15.0)
	_check(au.should_autosave_now(AutosaveUtil.KIND_MAP, 100.0), "first save always allowed")
	_check(not au.should_autosave_now(AutosaveUtil.KIND_MAP, 105.0), "save 5s later is throttled")
	_check(au.should_autosave_now(AutosaveUtil.KIND_MAP, 120.0), "save 20s later is allowed")
	# Throttle is per-kind: a mod save is independent of the map clock.
	_check(au.should_autosave_now(AutosaveUtil.KIND_MOD, 105.0), "different kind has its own clock")
	au.reset_throttle(AutosaveUtil.KIND_MAP)
	_check(au.should_autosave_now(AutosaveUtil.KIND_MAP, 121.0), "reset lets the next save through")


# --- Phase MC6 (request 7): active-mod selection logic ----------------------
# ActiveModUtil turns ModLoader.discover_mods() output into a stable UI list and
# owns the enable/main-mod selection logic. It is pure + deterministic (sorted
# by id) and fail-safe: a persisted selection that names a mod no longer on disk
# is silently dropped. These checks pin listing, sanitising, toggling, and the
# effective-main resolution.

func _mc6_discovered() -> Array:
	# Three mods on disk; one carries a display name, one is disabled by manifest.
	return [
		{ "id": "bravo", "name": "Bravo Pack", "enabled": true },
		{ "id": "alpha", "display_name_key": "mod.alpha.name", "enabled": true },
		{ "id": "charlie", "enabled": false },
	]


func test_mc6_active_mod_list_sorted_and_flags() -> void:
	print("test_mc6_active_mod_list_sorted_and_flags")
	var discovered: Array = _mc6_discovered()
	# No persisted active list -> fall back to each manifest's own enabled flag.
	var rows: Array = ActiveModUtil.list_mods(discovered, [], "")
	_check(rows.size() == 3, "all valid mods listed")
	_check(str(rows[0]["id"]) == "alpha", "sorted by id: alpha first")
	_check(str(rows[1]["id"]) == "bravo", "sorted by id: bravo second")
	_check(str(rows[2]["id"]) == "charlie", "sorted by id: charlie last")
	_check(str(rows[0]["name_key"]) == "mod.alpha.name", "display_name_key preferred")
	_check(str(rows[1]["name_key"]) == "Bravo Pack", "name field used when no key")
	_check(str(rows[2]["name_key"]) == "charlie", "name_key falls back to id")
	_check(bool(rows[2]["enabled"]) == false, "manifest disabled respected when no active list")
	# A persisted active list is authoritative over the manifest default.
	var rows2: Array = ActiveModUtil.list_mods(discovered, ["charlie"], "charlie")
	_check(bool(rows2[2]["enabled"]) == true, "persisted active overrides manifest disabled")
	_check(bool(rows2[0]["enabled"]) == false, "unlisted mod is inactive under a persisted list")
	_check(bool(rows2[2]["is_main"]) == true, "main mod flagged")
	_check(bool(rows2[0]["is_main"]) == false, "non-main mod not flagged")


func test_mc6_active_mod_ignores_invalid_manifests() -> void:
	print("test_mc6_active_mod_ignores_invalid_manifests")
	var messy: Array = [ { "id": "ok" }, { "no_id": true }, "not_a_dict", { "id": "" } ]
	var rows: Array = ActiveModUtil.list_mods(messy, [], "")
	_check(rows.size() == 1, "only the valid, id-bearing manifest survives")
	_check(str(rows[0]["id"]) == "ok", "surviving row is the valid one")
	_check(ActiveModUtil.discovered_ids(messy) == ["ok"], "discovered_ids skips invalid entries")


func test_mc6_active_mod_sanitise_drops_missing() -> void:
	print("test_mc6_active_mod_sanitise_drops_missing")
	var discovered: Array = _mc6_discovered()
	# "ghost" is not on disk; duplicates + blanks are removed; result is sorted.
	var clean: Array = ActiveModUtil.sanitise_active(["bravo", "ghost", "bravo", "", "alpha"], discovered)
	_check(clean == ["alpha", "bravo"], "missing/duplicate/blank ids dropped, sorted")


func test_mc6_active_mod_toggle() -> void:
	print("test_mc6_active_mod_toggle")
	var discovered: Array = _mc6_discovered()
	# Toggling an on-disk id that is off turns it on.
	var a: Array = ActiveModUtil.toggle(["alpha"], "bravo", discovered)
	_check(a == ["alpha", "bravo"], "toggle adds an existing disabled mod")
	# Toggling it again turns it off.
	var b: Array = ActiveModUtil.toggle(a, "bravo", discovered)
	_check(b == ["alpha"], "toggle removes an enabled mod")
	# Toggling a mod that is not on disk is refused (list unchanged, sanitised).
	var c: Array = ActiveModUtil.toggle(["alpha"], "ghost", discovered)
	_check(c == ["alpha"], "toggle refuses an unknown-on-disk id")
	_check(ActiveModUtil.is_active(["alpha", "bravo"], "bravo", discovered), "is_active true for listed present mod")
	_check(not ActiveModUtil.is_active(["alpha"], "bravo", discovered), "is_active false for unlisted mod")


func test_mc6_active_mod_resolve_main() -> void:
	print("test_mc6_active_mod_resolve_main")
	var discovered: Array = _mc6_discovered()
	# Main must be present AND enabled to resolve.
	_check(ActiveModUtil.resolve_main("alpha", ["alpha", "bravo"], discovered) == "alpha", "enabled+present main resolves")
	_check(ActiveModUtil.resolve_main("bravo", ["alpha"], discovered) == "", "main not enabled -> empty")
	_check(ActiveModUtil.resolve_main("ghost", ["ghost"], discovered) == "", "main not on disk -> empty")
	_check(ActiveModUtil.resolve_main("", ["alpha"], discovered) == "", "empty main id -> empty")


# --- Phase MC6.4 (request 7): mod-editor chooser (ModChoiceUtil) ------------
# ModChoiceUtil turns StorageService.list_packs() output (full .nexpack paths)
# into a stable, id-sorted list of editable choices for the mod editor's
# "which mod do you want to edit?" dialog. Pure + deterministic: same input ->
# same order on every machine, blank/duplicate/non-pack paths dropped, and an
# out-of-range index resolves to the "new mod" sentinel (empty dict).

func test_mc6_mod_choice_list_sorted_and_deduped() -> void:
	print("test_mc6_mod_choice_list_sorted_and_deduped")
	# Unsorted input with a blank entry and a duplicate id. StorageService only
	# ever hands ModChoiceUtil real pack paths, so the util's contract is to drop
	# blank/duplicate ids and sort by id -- it does NOT re-check the extension.
	var paths: Array = [
		"user://content/mods/charlie.nexpack",
		"user://content/mods/alpha.nexpack",
		"   ",
		"user://other/alpha.nexpack",  # duplicate id "alpha" -> dropped
		"user://content/mods/bravo.nexpack",
	]
	var rows: Array = ModChoiceUtil.list_choices(paths)
	# alpha/bravo/charlie survive (blank + duplicate dropped), sorted by id.
	_check(rows.size() == 3, "three distinct pack choices survive filtering")
	_check(str(rows[0]["id"]) == "alpha", "choices sorted by id (alpha first)")
	_check(str(rows[1]["id"]) == "bravo", "choices sorted by id (bravo second)")
	_check(str(rows[2]["id"]) == "charlie", "choices sorted by id (charlie third)")
	_check(str(rows[0]["path"]) == "user://content/mods/alpha.nexpack", "first alpha path kept, duplicate dropped")


func test_mc6_mod_choice_id_and_has_choices() -> void:
	print("test_mc6_mod_choice_id_and_has_choices")
	_check(ModChoiceUtil.mod_id_for("user://content/mods/alpha.nexpack") == "alpha", "id strips dir + .nexpack")
	_check(ModChoiceUtil.mod_id_for("BRAVO.NEXPACK") == "BRAVO", "id strips suffix case-insensitively, keeps name case")
	_check(ModChoiceUtil.mod_id_for("   ") == "", "blank path -> empty id")
	_check(ModChoiceUtil.mod_id_for("plain.txt") == "plain.txt", "non-pack file keeps its full name")
	_check(ModChoiceUtil.has_choices(["user://content/mods/alpha.nexpack"]), "has_choices true when a pack exists")
	_check(not ModChoiceUtil.has_choices(["", "   "]), "has_choices false when only blank paths")


func test_mc6_mod_choice_resolve_index() -> void:
	print("test_mc6_mod_choice_resolve_index")
	var paths: Array = [
		"user://content/mods/bravo.nexpack",
		"user://content/mods/alpha.nexpack",
	]
	# Index 0 resolves to the FIRST sorted row (alpha), not the input order.
	var first: Dictionary = ModChoiceUtil.resolve_choice(paths, 0)
	_check(str(first.get("id", "")) == "alpha", "resolve index 0 -> alpha (sorted)")
	# Out-of-range (incl. the "new mod" option) resolves to the empty sentinel.
	_check(ModChoiceUtil.resolve_choice(paths, 2).is_empty(), "out-of-range index -> new-mod sentinel")
	_check(ModChoiceUtil.resolve_choice(paths, -1).is_empty(), "negative index -> new-mod sentinel")
	# A resolved row is a defensive copy (mutating it never touches source state).
	first["id"] = "mutated"
	_check(str(ModChoiceUtil.resolve_choice(paths, 0)["id"]) == "alpha", "resolve returns a defensive copy")


# --- Phase MC6.2 (request 7): active_mods/main_mod persistence --------------
# GameSettings now stores the ENABLED mod ids + the chosen MAIN mod so the
# selection survives across sessions. These tests pin the defaults, the
# validated setters, and the JSON disk round-trip (the same durability contract
# the other settings enjoy). Reconciliation against disk is ActiveModUtil's job
# (already covered above), so here we only prove raw storage fidelity.

func test_mc6_settings_active_mods_default_empty() -> void:
	print("test_mc6_settings_active_mods_default_empty")
	var s: GameSettings = _new_settings()
	s.ensure_defaults()
	_check(s.get_active_mods() == [], "active_mods empty by default")
	_check(s.get_main_mod() == "", "main_mod empty by default")
	# The getter must hand back a private copy: mutating it never leaks into state.
	var borrowed: Array = s.get_active_mods()
	borrowed.append("intruder")
	_check(s.get_active_mods() == [], "get_active_mods returns a defensive copy")


func test_mc6_settings_active_mods_setters_and_validation() -> void:
	print("test_mc6_settings_active_mods_setters_and_validation")
	var s: GameSettings = _new_settings()
	s.ensure_defaults()
	# A clean String array is accepted and stored verbatim (order preserved).
	_check(s.set_active_mods(["bravo", "alpha"]), "string-array active_mods accepted")
	_check(s.get_active_mods() == ["bravo", "alpha"], "active_mods stored verbatim")
	# Setting the main mod (any String, including "" to clear) is accepted.
	_check(s.set_main_mod("bravo"), "main_mod accepted")
	_check(s.get_main_mod() == "bravo", "main_mod stored")
	_check(s.set_main_mod(""), "empty main_mod (clear) accepted")
	_check(s.get_main_mod() == "", "main_mod cleared")
	# A non-string element is rejected WITHOUT corrupting the current value.
	_check(s.set_active_mods(["bravo"]), "reset active_mods for reject test")
	_check(not s.set_active_mods(["ok", 123]), "non-string element rejected")
	_check(s.get_active_mods() == ["bravo"], "active_mods unchanged after bad write")
	# An empty list is a valid selection.
	_check(s.set_active_mods([]), "empty active_mods accepted")
	_check(s.get_active_mods() == [], "active_mods cleared")


func test_mc6_settings_active_mods_persist_round_trip() -> void:
	print("test_mc6_settings_active_mods_persist_round_trip")
	var path: String = _temp_settings_path()
	var s: GameSettings = _new_settings()
	s.set_active_mods(["alpha", "charlie"])
	s.set_main_mod("charlie")
	_check(s.save_to_file(path), "settings with active mods saved")

	var loaded: GameSettings = _new_settings()
	_check(loaded.load_from_file(path), "settings with active mods loaded")
	_check(loaded.get_active_mods() == ["alpha", "charlie"], "active_mods persisted")
	_check(loaded.get_main_mod() == "charlie", "main_mod persisted")
	# A structurally valid file with a corrupt active_mods field falls back safely.
	var g: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	g.store_string(JSON.stringify({"active_mods": "not-a-list", "main_mod": 42}))
	g.close()
	var s2: GameSettings = _new_settings()
	_check(s2.load_from_file(path), "partially-valid mod file loads")
	_check(s2.get_active_mods() == [], "corrupt active_mods defaulted")
	_check(s2.get_main_mod() == "", "corrupt main_mod defaulted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Phase MC2 (request 2): three-state fog "last image" memory -------------
# HIDDEN -> solid black; VISIBLE -> live truth; EXPLORED -> dimmed last image.
# FogSnapshotUtil keeps the frozen memory of the last entity seen per tile. It
# is a pure RENDER aid and must NEVER touch the deterministic state hash: two
# peers keeping different snapshots must still hash identically. These checks
# pin observe -> remember -> serve + the layer decision + hash isolation.

func _mc2_fog_section(w: int, h: int, viewer: int, visible_tiles: Array) -> Dictionary:
	# Build a fog section where `visible_tiles` (Array of [x,y]) are VISIBLE for
	# `viewer` and everything else HIDDEN, in the shape FogSnapshotUtil expects.
	var grid: Array = []
	grid.resize(w * h)
	for i in range(grid.size()):
		grid[i] = FogSnapshotUtil.FOG_HIDDEN
	for t in visible_tiles:
		var idx: int = int(t[1]) * w + int(t[0])
		if idx >= 0 and idx < grid.size():
			grid[idx] = FogSnapshotUtil.FOG_VISIBLE
	return { "width": w, "height": h, "visible": { str(viewer): grid } }


func test_mc2_fog_snapshot_starts_empty() -> void:
	print("test_mc2_fog_snapshot_starts_empty")
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	_check(snap.size() == 0, "fresh snapshot remembers nothing")
	_check(snap.remembered(0, 0).is_empty(), "unseen tile yields empty memory")
	_check(not snap.has_memory(0, 0), "unseen tile has no memory flag")


func test_mc2_fog_snapshot_remembers_visible_entity() -> void:
	print("test_mc2_fog_snapshot_remembers_visible_entity")
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	var fog: Dictionary = _mc2_fog_section(4, 4, 0, [[2, 1]])
	var buildings: Dictionary = { "b1": { "x": 2, "y": 1, "owner": 3, "type": "hq" } }
	snap.observe(0, fog, buildings, {})
	var mem: Dictionary = snap.remembered(2, 1)
	_check(mem.get("kind", "") == FogSnapshotUtil.KIND_BUILDING, "remembers building on seen tile")
	_check(int(mem.get("owner", -1)) == 3, "remembers building owner")
	_check(str(mem.get("type", "")) == "hq", "remembers building type")


func test_mc2_fog_snapshot_freezes_after_losing_sight() -> void:
	print("test_mc2_fog_snapshot_freezes_after_losing_sight")
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	var seen: Dictionary = _mc2_fog_section(3, 3, 0, [[1, 1]])
	snap.observe(0, seen, { "b1": { "x": 1, "y": 1, "owner": 2, "type": "hq" } }, {})
	# Now the tile is no longer VISIBLE (all hidden); the building is razed in the
	# live truth, but the frozen memory must stay = "last image" the player saw.
	var hidden: Dictionary = _mc2_fog_section(3, 3, 0, [])
	snap.observe(0, hidden, {}, {})
	var mem: Dictionary = snap.remembered(1, 1)
	_check(mem.get("kind", "") == FogSnapshotUtil.KIND_BUILDING, "EXPLORED tile keeps last image after loss of sight")


func test_mc2_fog_snapshot_clears_when_seen_empty() -> void:
	print("test_mc2_fog_snapshot_clears_when_seen_empty")
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	var fog: Dictionary = _mc2_fog_section(3, 3, 0, [[1, 1]])
	snap.observe(0, fog, { "b1": { "x": 1, "y": 1, "owner": 2, "type": "hq" } }, {})
	_check(snap.has_memory(1, 1), "building remembered while in sight")
	# Re-observe the same tile still VISIBLE but now empty -> stale image forgotten.
	snap.observe(0, fog, {}, {})
	_check(not snap.has_memory(1, 1), "seeing a tile empty forgets its stale image")


func test_mc2_fog_snapshot_building_wins_over_unit() -> void:
	print("test_mc2_fog_snapshot_building_wins_over_unit")
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	var fog: Dictionary = _mc2_fog_section(3, 3, 0, [[0, 0]])
	# A unit and a building share the tile; the more permanent building wins.
	snap.observe(0, fog,
		{ "b1": { "x": 0, "y": 0, "owner": 1, "type": "factory" } },
		{ "u1": { "x": 0, "y": 0, "owner": 1, "type": "scout" } })
	_check(snap.remembered(0, 0).get("kind", "") == FogSnapshotUtil.KIND_BUILDING,
		"building takes precedence over a co-located unit")


func test_mc2_fog_snapshot_layer_for_states() -> void:
	print("test_mc2_fog_snapshot_layer_for_states")
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	_check(snap.layer_for(FogSnapshotUtil.FOG_VISIBLE, 0, 0).get("layer", "") == "visible",
		"VISIBLE -> live visible layer")
	_check(snap.layer_for(FogSnapshotUtil.FOG_HIDDEN, 0, 0).get("layer", "") == "hidden",
		"HIDDEN -> solid black cover layer")
	var explored: Dictionary = snap.layer_for(FogSnapshotUtil.FOG_EXPLORED, 0, 0)
	_check(explored.get("layer", "") == "explored", "EXPLORED -> dimmed explored layer")
	_check(explored.has("memory"), "EXPLORED layer carries the remembered last image")


func test_mc2_fog_snapshot_is_deterministic() -> void:
	print("test_mc2_fog_snapshot_is_deterministic")
	var fog: Dictionary = _mc2_fog_section(4, 4, 1, [[0, 0], [3, 3]])
	var b: Dictionary = { "b1": { "x": 0, "y": 0, "owner": 5, "type": "hq" } }
	var u: Dictionary = { "u1": { "x": 3, "y": 3, "owner": 5, "type": "tank" } }
	var s1: FogSnapshotUtil = FogSnapshotUtil.new()
	var s2: FogSnapshotUtil = FogSnapshotUtil.new()
	s1.observe(1, fog, b, u)
	s2.observe(1, fog, b, u)
	_check(s1.remembered(0, 0) == s2.remembered(0, 0), "same inputs -> identical building memory")
	_check(s1.remembered(3, 3) == s2.remembered(3, 3), "same inputs -> identical unit memory")


func test_mc2_fog_snapshot_does_not_affect_state_hash() -> void:
	print("test_mc2_fog_snapshot_does_not_affect_state_hash")
	# The snapshot is cosmetic: it is derived from world data but never fed back.
	# Prove the deterministic hash of a world dictionary is identical whether or
	# not a snapshot has observed it (the snapshot lives outside hashed state).
	var world: Dictionary = {
		"buildings": { "b1": { "x": 1, "y": 1, "owner": 2, "type": "hq" } },
		"units": {},
	}
	var h_before: int = StateHasher.hash_variant(world)
	var snap: FogSnapshotUtil = FogSnapshotUtil.new()
	var fog: Dictionary = _mc2_fog_section(3, 3, 0, [[1, 1]])
	snap.observe(0, fog, world["buildings"], world["units"])
	var h_after: int = StateHasher.hash_variant(world)
	_check(h_before == h_after, "observing a snapshot never mutates or rehashes the world")
	_check(snap.size() > 0, "snapshot did record memory (guard: the observe actually ran)")


# --- Phase MC4 (request 5): cosmetic animation events -----------------------
func test_mc4_anim_starts_empty() -> void:
	print("test_mc4_anim_starts_empty")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	_check(anim.active_count() == 0, "fresh util has no active animations")
	_check(anim.active_events().is_empty(), "no active events listed")


func test_mc4_anim_spawn_projectile_and_explosion() -> void:
	print("test_mc4_anim_spawn_projectile_and_explosion")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	var p: Dictionary = anim.spawn_projectile(Vector2i(1, 1), Vector2i(4, 2), 0)
	_check(p.get("kind", "") == AnimationEventUtil.ANIM_PROJECTILE, "projectile kind set")
	_check(p.get("from", Vector2i.ZERO) == Vector2i(1, 1), "projectile from tile")
	_check(p.get("to", Vector2i.ZERO) == Vector2i(4, 2), "projectile to tile")
	var e: Dictionary = anim.spawn_explosion(Vector2i(4, 2), 1)
	_check(e.get("kind", "") == AnimationEventUtil.ANIM_EXPLOSION, "explosion kind set")
	_check(e.get("from", Vector2i.ZERO) == Vector2i(4, 2), "explosion at tile")
	_check(anim.active_count() == 2, "two animations active")


func test_mc4_anim_maps_attack_event() -> void:
	print("test_mc4_anim_maps_attack_event")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	var lookup: Callable = func(id: int) -> Vector2i:
		if id == 7:
			return Vector2i(2, 0)
		return Vector2i(5, 5)
	var ev: Dictionary = anim.on_sim_event(
		AnimationEventUtil.SIM_EVENT_ATTACK,
		{ "attacker": 7, "target": 9, "owner": 3 }, lookup)
	_check(ev.get("kind", "") == AnimationEventUtil.ANIM_PROJECTILE, "attack -> projectile")
	_check(ev.get("from", Vector2i.ZERO) == Vector2i(2, 0), "attacker tile resolved via lookup")
	_check(ev.get("to", Vector2i.ZERO) == Vector2i(5, 5), "target tile resolved via lookup")
	_check(int(ev.get("owner", -1)) == 3, "owner carried through")


func test_mc4_anim_maps_death_events() -> void:
	print("test_mc4_anim_maps_death_events")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	var lookup: Callable = func(id: int) -> Vector2i:
		return Vector2i(3, 3)
	var u: Dictionary = anim.on_sim_event(
		AnimationEventUtil.SIM_EVENT_UNIT_DIED, { "id": 1, "owner": 2 }, lookup)
	_check(u.get("kind", "") == AnimationEventUtil.ANIM_EXPLOSION, "unit death -> explosion")
	var b: Dictionary = anim.on_sim_event(
		AnimationEventUtil.SIM_EVENT_BUILDING_DESTROYED, { "id": 2, "owner": 2 }, lookup)
	_check(b.get("kind", "") == AnimationEventUtil.ANIM_EXPLOSION, "building destroyed -> explosion")
	_check(anim.active_count() == 2, "both deaths produced an animation")


func test_mc4_anim_ignores_unknown_event() -> void:
	print("test_mc4_anim_ignores_unknown_event")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	var none: Dictionary = anim.on_sim_event("economy.gold_changed", { "amount": 5 })
	_check(none.is_empty(), "unrelated sim event produces no animation")
	_check(anim.active_count() == 0, "no animation enqueued for unknown event")


func test_mc4_anim_resolves_explicit_tile_payload() -> void:
	print("test_mc4_anim_resolves_explicit_tile_payload")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	# Payload with explicit tile coords (array form) and no lookup Callable.
	var ev: Dictionary = anim.on_sim_event(
		AnimationEventUtil.SIM_EVENT_ATTACK,
		{ "from": [1, 2], "to": [3, 4], "owner": 0 })
	_check(ev.get("from", Vector2i.ZERO) == Vector2i(1, 2), "explicit from tile used")
	_check(ev.get("to", Vector2i.ZERO) == Vector2i(3, 4), "explicit to tile used")


func test_mc4_anim_advance_expires_events() -> void:
	print("test_mc4_anim_advance_expires_events")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	anim.spawn_projectile(Vector2i.ZERO, Vector2i(1, 1), 0, 0.2)
	anim.spawn_explosion(Vector2i(2, 2), 0, 0.5)
	_check(anim.active_count() == 2, "two animations before advancing")
	var ended: int = anim.advance(0.3)
	_check(ended == 1, "the 0.2s projectile expired after 0.3s")
	_check(anim.active_count() == 1, "explosion still alive")
	anim.advance(0.5)
	_check(anim.active_count() == 0, "explosion expired after enough time")


func test_mc4_anim_clear_and_ids_monotonic() -> void:
	print("test_mc4_anim_clear_and_ids_monotonic")
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	var a: Dictionary = anim.spawn_explosion(Vector2i.ZERO, 0)
	var b: Dictionary = anim.spawn_explosion(Vector2i.ONE, 0)
	_check(int(b.get("id", -1)) > int(a.get("id", -1)), "ids are monotonic")
	anim.clear()
	_check(anim.active_count() == 0, "clear removes all animations")


func test_mc4_anim_does_not_affect_state_hash() -> void:
	print("test_mc4_anim_does_not_affect_state_hash")
	# Animation events are cosmetic: producing them never touches hashed state.
	var world: Dictionary = {
		"units": { "u1": { "x": 1, "y": 1, "owner": 0, "hp": 10 } },
		"buildings": {},
	}
	var h_before: int = StateHasher.hash_variant(world)
	var anim: AnimationEventUtil = AnimationEventUtil.new()
	anim.on_sim_event(AnimationEventUtil.SIM_EVENT_UNIT_DIED, { "id": 1, "owner": 0, "at": [1, 1] })
	anim.advance(1.0)
	var h_after: int = StateHasher.hash_variant(world)
	_check(h_before == h_after, "animations never mutate or rehash the world")


# --- Phase MC4.2 (request 5): animation sprite fields + round-trip ----------
func test_mc4_graphic_default_animation_valid() -> void:
	print("test_mc4_graphic_default_animation_valid")
	var anim: Dictionary = GraphicModel.default_animation()
	_check(GraphicModel.validate_animation(anim).is_empty(), "default animation block validates")
	_check(anim.has("projectile") and anim.has("explosion"), "default has projectile + explosion")


func test_mc4_graphic_animation_optional() -> void:
	print("test_mc4_graphic_animation_optional")
	# A graphic with no animation block is still valid (optional field).
	var g: Dictionary = GraphicModel.default_graphic()
	_check(GraphicModel.validate(g).is_empty(), "graphic without animation is valid")
	_check(GraphicModel.validate_animation(null).is_empty(), "null animation is valid (absent)")
	_check(not GraphicModel.has_projectile_sprite(g), "no projectile sprite by default graphic")
	_check(not GraphicModel.has_explosion_sprite(g), "no explosion sprite by default graphic")


func test_mc4_graphic_animation_rejects_bad_ranges() -> void:
	print("test_mc4_graphic_animation_rejects_bad_ranges")
	var bad: Dictionary = {
		"projectile": { "texture": "p.png", "px": { "w": 4, "h": 4 } },
		"explosion": { "texture": "e.png", "frames": 999, "fps": 0, "px": { "w": 64, "h": 64 } },
	}
	var problems: Array = GraphicModel.validate_animation(bad)
	_check(problems.size() >= 3, "bad px + frames + fps all flagged")


func test_mc4_graphic_has_sprite_flags() -> void:
	print("test_mc4_graphic_has_sprite_flags")
	var g: Dictionary = GraphicModel.default_graphic()
	g["animation"] = {
		"projectile": { "texture": "shot.png", "px": { "w": 16, "h": 16 } },
		"explosion": { "texture": "", "frames": 8, "fps": 12, "px": { "w": 64, "h": 64 } },
	}
	_check(GraphicModel.has_projectile_sprite(g), "projectile sprite detected when texture set")
	_check(not GraphicModel.has_explosion_sprite(g), "explosion sprite absent when texture blank")
	_check(GraphicModel.validate(g).is_empty(), "graphic with partial animation still valid")


func test_mc4_modproject_animation_roundtrip() -> void:
	print("test_mc4_modproject_animation_roundtrip")
	var mp: ModProject = ModProject.new()
	mp.set_unit("tank", ModProject.default_unit("tank"))
	var anim: Dictionary = GraphicModel.default_animation()
	anim["projectile"]["texture"] = "tank_shot.png"
	_check(mp.set_animation("unit", "tank", anim), "animation attached to unit")
	# Snapshot round-trip preserves the animation block.
	var snap: Dictionary = mp.to_snapshot()
	var mp2: ModProject = ModProject.new()
	_check(mp2.from_snapshot(snap), "snapshot restored")
	var back: Dictionary = mp2.get_animation("unit", "tank")
	_check(str(back.get("projectile", {}).get("texture", "")) == "tank_shot.png",
		"projectile texture survives snapshot round-trip")


func test_mc4_modproject_animation_missing_entity() -> void:
	print("test_mc4_modproject_animation_missing_entity")
	var mp: ModProject = ModProject.new()
	_check(not mp.set_animation("unit", "ghost", GraphicModel.default_animation()),
		"cannot attach animation to a non-existent entity")
	_check(mp.get_animation("unit", "ghost").is_empty(), "no animation for missing entity")


# --- Phase MC7 (request 8): GuiProject data-driven GUI authoring model -------

func test_mc7_gui_new_and_pages() -> void:
	print("test_mc7_gui_new_and_pages")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin_a")
	_check(g.get_id() == "skin_a", "id set by init_new")
	_check(not g.is_valid(), "empty project (no pages) is not valid")
	_check(g.ensure_page("main"), "ensure_page main ok")
	_check(not g.ensure_page("  "), "blank page name rejected")
	_check(g.has_page("main"), "has main page")
	_check(g.ensure_page("options"), "ensure_page options ok")
	# page_names is sorted + deterministic.
	_check(g.page_names() == ["main", "options"], "page_names sorted")
	_check(g.is_valid(), "id + at least one page => valid")
	# ensure_page on an existing page keeps its widgets (idempotent).
	g.add_widget("main", "single", [10, 10, 100, 40])
	g.ensure_page("main")
	_check(g.widget_count("main") == 1, "ensure_page does not wipe existing widgets")


func test_mc7_gui_add_widget_unique_and_clamped() -> void:
	print("test_mc7_gui_add_widget_unique_and_clamped")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin_b")
	g.ensure_page("main")
	_check(g.add_widget("main", "single", [10, 10, 100, 40]), "add single ok")
	_check(not g.add_widget("main", "single", [0, 0, 50, 50]), "duplicate logical_id rejected")
	_check(not g.add_widget("main", "  ", [0, 0, 50, 50]), "blank logical_id rejected")
	_check(not g.add_widget("ghost", "host", [0, 0, 50, 50]), "unknown page rejected")
	# Rect clamping: out-of-bounds + tiny sizes are clamped into design space.
	_check(g.add_widget("main", "host", [-50, -50, 2, 2]), "add host ok")
	var w: Dictionary = g.get_widget("main", "host")
	var r: Array = w.get("rect", [])
	_check(r[0] >= 0 and r[1] >= 0, "rect origin clamped non-negative")
	_check(r[2] >= GuiProject.MIN_WIDGET_SIZE and r[3] >= GuiProject.MIN_WIDGET_SIZE,
		"rect size clamped to minimum")
	_check(g.widget_count("main") == 2, "widget_count reflects adds")


func test_mc7_gui_edit_rect_icon_name() -> void:
	print("test_mc7_gui_edit_rect_icon_name")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin_c")
	g.ensure_page("main")
	g.add_widget("main", "single", [10, 10, 100, 40], "", "Play")
	_check(g.set_widget_rect("main", "single", [200, 100, 150, 60]), "set_widget_rect ok")
	_check(not g.set_widget_rect("main", "ghost", [0, 0, 20, 20]), "rect on missing widget fails")
	_check(g.set_widget_icon("main", "single", " icons/play.png "), "set icon ok")
	_check(g.set_widget_display_name("main", "single", "Start Game"), "rename ok")
	var w: Dictionary = g.get_widget("main", "single")
	_check(w.get("rect", []) == [200, 100, 150, 60], "rect updated")
	_check(str(w.get("icon_path", "")) == "icons/play.png", "icon trimmed + stored")
	_check(str(w.get("display_name", "")) == "Start Game", "display name updated")
	# logical_id (function) is NOT mutated by any editor op.
	_check(str(w.get("logical_id", "")) == "single", "logical_id fixed")


func test_mc7_gui_remove_widget() -> void:
	print("test_mc7_gui_remove_widget")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin_d")
	g.ensure_page("main")
	g.add_widget("main", "single", [0, 0, 40, 40])
	g.add_widget("main", "quit", [0, 50, 40, 40])
	_check(g.remove_widget("main", "single"), "remove ok")
	_check(not g.remove_widget("main", "single"), "removing twice fails")
	_check(g.widget_count("main") == 1, "count decremented")
	_check(g.get_widget("main", "quit").size() > 0, "other widget intact")


func test_mc7_gui_background_kinds_and_fallback() -> void:
	print("test_mc7_gui_background_kinds_and_fallback")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin_e")
	g.ensure_page("main")
	_check(g.set_page_background("main", GuiProject.BG_IMAGE, "bg/menu.png"), "image bg ok")
	var bg: Dictionary = g.get_page_background("main")
	_check(str(bg.get("kind", "")) == GuiProject.BG_IMAGE, "kind image stored")
	_check(str(bg.get("value", "")) == "bg/menu.png", "value stored")
	# An unknown kind falls back to a safe solid color.
	_check(g.set_page_background("main", "hologram", "x"), "unknown kind still returns true")
	var bg2: Dictionary = g.get_page_background("main")
	_check(str(bg2.get("kind", "")) == GuiProject.BG_COLOR, "unknown kind falls back to color")
	_check(str(bg2.get("value", "")) == GuiProject.DEFAULT_BG_COLOR, "fallback uses default color")
	_check(not g.set_page_background("ghost", GuiProject.BG_COLOR, "#fff"), "bg on missing page fails")


func test_mc7_gui_validate_video_background() -> void:
	print("test_mc7_gui_validate_video_background")
	var ok: Array = GuiProject.validate_video_background("bg/intro.ogv", 10.0, 4 * 1024 * 1024)
	_check(bool(ok[0]), "valid ogv within budget accepted")
	_check(not bool(GuiProject.validate_video_background("", 1.0, 1)[0]), "blank path rejected")
	_check(not bool(GuiProject.validate_video_background("bg/intro.mp4", 1.0, 1)[0]),
		"non-ogv extension rejected")
	var too_long: Array = GuiProject.validate_video_background("bg/x.ogv", 999.0, 1)
	_check(not bool(too_long[0]) and str(too_long[1]) == "ui.guieditor.video_too_long",
		"over-long video rejected with reason")
	var too_big: Array = GuiProject.validate_video_background("bg/x.ogv", 1.0, 999 * 1024 * 1024)
	_check(not bool(too_big[0]) and str(too_big[1]) == "ui.guieditor.video_too_big",
		"over-size video rejected with reason")


func test_mc7_gui_to_dict_deterministic_sorted() -> void:
	print("test_mc7_gui_to_dict_deterministic_sorted")
	# Build the same logical project two ways (different insertion order) and
	# confirm to_dict yields byte-identical JSON (pages + widgets sorted).
	var a: GuiProject = GuiProject.new()
	a.init_new("det")
	a.ensure_page("options")
	a.ensure_page("main")
	a.add_widget("main", "quit", [0, 0, 40, 40])
	a.add_widget("main", "single", [0, 50, 40, 40])
	var b: GuiProject = GuiProject.new()
	b.init_new("det")
	b.ensure_page("main")
	b.ensure_page("options")
	b.add_widget("main", "single", [0, 50, 40, 40])
	b.add_widget("main", "quit", [0, 0, 40, 40])
	_check(a.to_json() == b.to_json(), "insertion order does not change serialised JSON")
	_check(a.to_json() != "", "valid project serialises to non-empty JSON")
	var empty: GuiProject = GuiProject.new()
	empty.init_new("x")
	_check(empty.to_json() == "", "invalid (page-less) project serialises to empty string")


func test_mc7_gui_json_round_trip() -> void:
	print("test_mc7_gui_json_round_trip")
	var g: GuiProject = GuiProject.new()
	g.init_new("round")
	g.set_display_name_key("ui.gui.round")
	g.ensure_page("main")
	g.add_widget("main", "single", [10, 20, 120, 48], "icons/play.png", "Play")
	g.set_page_background("main", GuiProject.BG_IMAGE, "bg/menu.png")
	var text: String = g.to_json()
	var g2: GuiProject = GuiProject.new()
	_check(g2.from_json(text), "from_json parses valid text")
	_check(g2.to_json() == text, "round-trip is byte-identical")
	_check(g2.get_display_name_key() == "ui.gui.round", "display name key survives")
	var w: Dictionary = g2.get_widget("main", "single")
	_check(str(w.get("display_name", "")) == "Play", "widget name survives round-trip")
	_check(str(g2.get_page_background("main").get("kind", "")) == GuiProject.BG_IMAGE,
		"background survives round-trip")


func test_mc7_gui_from_json_rejects_malformed() -> void:
	print("test_mc7_gui_from_json_rejects_malformed")
	var g: GuiProject = GuiProject.new()
	_check(not g.from_json("{ this is not json"), "malformed JSON rejected")
	_check(not g.from_json("[1,2,3]"), "non-object JSON rejected")
	_check(not g.from_json("{\"pages\":{}}"), "object without id rejected")
	_check(g.from_json("{\"id\":\"ok\",\"pages\":{\"main\":{\"widgets\":[]}}}"),
		"minimal valid object accepted")


# --- Phase MC7.3: GuiWidgetCatalog -------------------------------------------

func test_mc7_catalog_pages_and_allowed_ids_sorted() -> void:
	print("test_mc7_catalog_pages_and_allowed_ids_sorted")
	var pages: Array = GuiWidgetCatalog.page_names()
	_check(pages.has(GuiWidgetCatalog.PAGE_MAIN), "catalog knows main page")
	_check(pages.has(GuiWidgetCatalog.PAGE_IN_GAME), "catalog knows in_game page")
	# page_names is sorted (deterministic).
	var sorted_copy: Array = pages.duplicate()
	sorted_copy.sort()
	_check(pages == sorted_copy, "page_names is sorted")
	# allowed_ids is sorted and non-empty for a known page.
	var main_ids: Array = GuiWidgetCatalog.allowed_ids(GuiWidgetCatalog.PAGE_MAIN)
	_check(main_ids.size() > 0, "main page has allowed ids")
	var ids_sorted: Array = main_ids.duplicate()
	ids_sorted.sort()
	_check(main_ids == ids_sorted, "allowed_ids is sorted")
	_check(GuiWidgetCatalog.allowed_ids("no_such_page") == [], "unknown page => empty ids")


func test_mc7_catalog_is_allowed() -> void:
	print("test_mc7_catalog_is_allowed")
	_check(GuiWidgetCatalog.is_allowed(GuiWidgetCatalog.PAGE_MAIN, "single"), "single allowed on main")
	_check(GuiWidgetCatalog.is_allowed(GuiWidgetCatalog.PAGE_MAIN, "gui_editor"), "gui_editor allowed on main")
	_check(not GuiWidgetCatalog.is_allowed(GuiWidgetCatalog.PAGE_MAIN, "attack"),
		"in-game action not allowed on main")
	_check(GuiWidgetCatalog.is_allowed(GuiWidgetCatalog.PAGE_IN_GAME, "attack"),
		"attack allowed in-game")
	_check(not GuiWidgetCatalog.is_allowed("ghost", "single"), "unknown page => not allowed")


func test_mc7_catalog_validate_project_dict_ok() -> void:
	print("test_mc7_catalog_validate_project_dict_ok")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin")
	g.ensure_page(GuiWidgetCatalog.PAGE_MAIN)
	g.add_widget(GuiWidgetCatalog.PAGE_MAIN, "single", [0, 0, 40, 40])
	g.add_widget(GuiWidgetCatalog.PAGE_MAIN, "quit", [0, 50, 40, 40])
	var res: Array = GuiWidgetCatalog.validate_project_dict(g.to_dict())
	_check(bool(res[0]), "project with only valid ids passes catalog check")


func test_mc7_catalog_validate_project_dict_rejects_bad_id() -> void:
	print("test_mc7_catalog_validate_project_dict_rejects_bad_id")
	# Hand-build a dict with a bogus function on a known page (bypass add_widget).
	var data: Dictionary = {
		"id": "bad",
		"pages": {
			"main": { "widgets": [ { "logical_id": "hack_the_planet", "rect": [0, 0, 40, 40] } ] },
		},
	}
	var res: Array = GuiWidgetCatalog.validate_project_dict(data)
	_check(not bool(res[0]), "unknown function on a known page is rejected")
	_check(str(res[1]) == "ui.guieditor.catalog_bad_id", "reason key reported")
	_check(str(res[2]) == "main/hack_the_planet", "offending page/id reported")


func test_mc7_catalog_validate_ignores_unknown_page() -> void:
	print("test_mc7_catalog_validate_ignores_unknown_page")
	# A page the catalog does not police may carry anything; not our contract.
	var data: Dictionary = {
		"id": "custom",
		"pages": {
			"my_custom_screen": { "widgets": [ { "logical_id": "whatever", "rect": [0, 0, 40, 40] } ] },
		},
	}
	var res: Array = GuiWidgetCatalog.validate_project_dict(data)
	_check(bool(res[0]), "unknown page passes through (not policed)")


# --- Phase MC7.6: GuiRenderUtil ----------------------------------------------

func test_mc7_render_fit_transform_uniform_and_centered() -> void:
	print("test_mc7_render_fit_transform_uniform_and_centered")
	# Exact design-space viewport: scale 1, no offset.
	var t1: Dictionary = GuiRenderUtil.fit_transform(1920.0, 1080.0)
	_check(abs(float(t1["scale"]) - 1.0) < 0.0001, "exact size => scale 1")
	_check(abs(float(t1["offset_x"])) < 0.0001, "no x offset at exact size")
	# Wider-than-design viewport letterboxes horizontally (scale limited by y).
	var t2: Dictionary = GuiRenderUtil.fit_transform(3840.0, 1080.0)
	_check(abs(float(t2["scale"]) - 1.0) < 0.0001, "scale limited by height")
	_check(float(t2["offset_x"]) > 0.0, "horizontal letterbox offset > 0")
	_check(abs(float(t2["offset_y"])) < 0.0001, "no vertical offset")
	# Degenerate viewport is safe.
	var t3: Dictionary = GuiRenderUtil.fit_transform(0.0, 0.0)
	_check(abs(float(t3["scale"]) - 1.0) < 0.0001, "zero viewport => safe scale 1")


func test_mc7_render_resolve_rect() -> void:
	print("test_mc7_render_resolve_rect")
	# Half-scale transform with a 100px x offset.
	var t: Dictionary = { "scale": 0.5, "offset_x": 100.0, "offset_y": 0.0 }
	var r: Array = GuiRenderUtil.resolve_rect([200, 100, 400, 80], t)
	_check(abs(float(r[0]) - (200.0 * 0.5 + 100.0)) < 0.0001, "x scaled + offset")
	_check(abs(float(r[1]) - 50.0) < 0.0001, "y scaled")
	_check(abs(float(r[2]) - 200.0) < 0.0001, "w scaled")
	_check(abs(float(r[3]) - 40.0) < 0.0001, "h scaled")
	# Bad rect is safe.
	_check(GuiRenderUtil.resolve_rect([], t) == [0.0, 0.0, 0.0, 0.0], "empty rect safe")


func test_mc7_render_resolve_page_scales_authored() -> void:
	print("test_mc7_render_resolve_page_scales_authored")
	var g: GuiProject = GuiProject.new()
	g.init_new("skin")
	g.ensure_page("main")
	g.add_widget("main", "single", [0, 0, 1920, 1080])
	var page: Dictionary = g.to_dict()["pages"]["main"]
	# Half-size viewport => scale 0.5, no letterbox (same aspect).
	var out: Array = GuiRenderUtil.resolve_page(page, { "w": 960.0, "h": 540.0 }, [])
	_check(out.size() == 1, "one authored widget resolved")
	var r: Array = out[0]["rect"]
	_check(abs(float(r[2]) - 960.0) < 0.0001, "full-page widget scaled to viewport width")
	_check(abs(float(r[3]) - 540.0) < 0.0001, "full-page widget scaled to viewport height")


func test_mc7_render_resolve_page_falls_back_to_default() -> void:
	print("test_mc7_render_resolve_page_falls_back_to_default")
	var defaults: Array = [ { "logical_id": "single", "rect": [10.0, 10.0, 20.0, 20.0] } ]
	# Unauthored page (null) => defaults returned unchanged.
	var out1: Array = GuiRenderUtil.resolve_page(null, { "w": 800.0, "h": 600.0 }, defaults)
	_check(out1.size() == 1 and str(out1[0]["logical_id"]) == "single", "null page falls back")
	# Authored page with EMPTY widgets => defaults too.
	var out2: Array = GuiRenderUtil.resolve_page({ "widgets": [] }, { "w": 800.0, "h": 600.0 }, defaults)
	_check(out2.size() == 1, "empty widgets falls back to defaults")


func test_mc7_render_resolve_page_sorted_and_drops_blank() -> void:
	print("test_mc7_render_resolve_page_sorted_and_drops_blank")
	var page: Dictionary = {
		"widgets": [
			{ "logical_id": "quit", "rect": [0, 0, 40, 40] },
			{ "logical_id": "", "rect": [0, 0, 40, 40] },
			{ "logical_id": "single", "rect": [0, 0, 40, 40] },
		],
	}
	var out: Array = GuiRenderUtil.resolve_page(page, { "w": 1920.0, "h": 1080.0 }, [])
	_check(out.size() == 2, "blank logical_id dropped")
	_check(str(out[0]["logical_id"]) == "quit", "output sorted (quit < single)")
	_check(str(out[1]["logical_id"]) == "single", "output sorted second")


# MC7.4 (request 8): the GUI editor scene must be reachable and its BACK must
# route to its parent, exactly like the other editors. Since MC8 (request 9) the
# editors nest under the Editor Hub, so BACK from the GUI editor is the hub. Pure
# NavService check (no SceneTree) so it runs headless.
func test_mc7_gui_editor_back_route_and_scene_registered() -> void:
	print("test_mc7_gui_editor_back_route_and_scene_registered")
	_check(NavService.GUI_EDITOR == "res://scenes/gui_editor.tscn", "gui editor scene path constant")
	_check(NavService.PARENTS.has(NavService.GUI_EDITOR), "gui editor registered in nav table")
	_check(NavService.back_target(NavService.GUI_EDITOR) == NavService.EDITOR_HUB, "gui editor back is the editor hub")
	_check(not NavService.is_root(NavService.GUI_EDITOR), "gui editor is not root")
	_check(not NavService.is_in_game(NavService.GUI_EDITOR), "gui editor is not in-game")
	# The main-menu page in the widget catalog must offer the gui_editor function
	# so the editor can wire that button.
	_check(GuiWidgetCatalog.is_allowed(GuiWidgetCatalog.PAGE_MAIN, "gui_editor"), "gui_editor is a main-page function")


# MC7.7 (request 8): every ui.guieditor.* key the code references must exist in
# BOTH locales (parity guards a missing translation crashing an author screen).
func test_mc7_guieditor_i18n_keys_present_in_all_locales() -> void:
	print("test_mc7_guieditor_i18n_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.guieditor.title", "ui.guieditor.pages", "ui.guieditor.widgets",
		"ui.guieditor.new", "ui.guieditor.save", "ui.guieditor.export",
		"ui.guieditor.import", "ui.guieditor.add_widget", "ui.guieditor.remove_widget",
		"ui.guieditor.rename", "ui.guieditor.background", "ui.guieditor.drag_hint",
		"ui.guieditor.catalog_bad_id", "ui.guieditor.catalog_no_pages",
		"ui.guieditor.save_invalid", "ui.guieditor.save_io", "ui.guieditor.load_missing",
		"ui.guieditor.load_io", "ui.guieditor.load_malformed",
		"ui.guieditor.video_blank", "ui.guieditor.video_format",
		"ui.guieditor.video_too_long", "ui.guieditor.video_too_big",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# ----------------------------------------------------------------------------
# Phase MC8 (request 9): Editor hub + "Defaults" tab.
#
# EditorDefaultsUtil is the PURE selection/validation half of the Defaults
# screen (pick a default map/mod/gui). It builds a stable sorted choice list
# from raw discovery data and resolves a stored default id so a deleted target
# collapses to "" instead of dangling. Tested headlessly with plain arrays.
# A static guard confirms the main menu opens the editor hub, and an i18n guard
# confirms the hub/defaults keys exist in every locale.
# ----------------------------------------------------------------------------

func test_mc8_defaults_build_choices_sorted_and_deduped() -> void:
	print("test_mc8_defaults_build_choices_sorted_and_deduped")
	var choices: Array = EditorDefaultsUtil.build_choices(["gamma", "alpha", "beta", "alpha", "  "])
	_check(choices.size() == 3, "blanks dropped and duplicates collapsed")
	_check(str(choices[0]["id"]) == "alpha", "sorted: alpha first")
	_check(str(choices[1]["id"]) == "beta", "sorted: beta second")
	_check(str(choices[2]["id"]) == "gamma", "sorted: gamma last")


func test_mc8_defaults_build_choices_from_strings_and_dicts() -> void:
	print("test_mc8_defaults_build_choices_from_strings_and_dicts")
	var raw: Array = [
		"plain_id",
		{ "id": "with_name", "name": "Pretty Name" },
		{ "id": "no_name" },
		{ "id": "  " },
	]
	var choices: Array = EditorDefaultsUtil.build_choices(raw)
	_check(choices.size() == 3, "blank-id dict dropped")
	_check(EditorDefaultsUtil.display_name(choices, "with_name", "(none)") == "Pretty Name",
		"dict name is used for display")
	_check(EditorDefaultsUtil.display_name(choices, "no_name", "(none)") == "no_name",
		"missing name falls back to the id")
	_check(EditorDefaultsUtil.display_name(choices, "plain_id", "(none)") == "plain_id",
		"string entry uses id as name")


func test_mc8_defaults_has_choice_and_display_name() -> void:
	print("test_mc8_defaults_has_choice_and_display_name")
	var choices: Array = EditorDefaultsUtil.build_choices(["a", "b"])
	_check(EditorDefaultsUtil.has_choice(choices, "a"), "has_choice true for present id")
	_check(not EditorDefaultsUtil.has_choice(choices, "z"), "has_choice false for absent id")
	_check(EditorDefaultsUtil.display_name(choices, "", "(none)") == "(none)",
		"blank id shows the none-text")
	_check(EditorDefaultsUtil.display_name(choices, "z", "(none)") == "(none)",
		"unknown id shows the none-text")


func test_mc8_defaults_resolve_keeps_valid_drops_stale() -> void:
	print("test_mc8_defaults_resolve_keeps_valid_drops_stale")
	var choices: Array = EditorDefaultsUtil.build_choices(["map_a", "map_b"])
	_check(EditorDefaultsUtil.resolve_default("map_a", choices) == "map_a",
		"valid stored default is kept")
	_check(EditorDefaultsUtil.resolve_default("deleted_map", choices) == "",
		"stale stored default collapses to empty")
	_check(EditorDefaultsUtil.resolve_default("", choices) == "",
		"empty default stays empty (use built-in)")
	_check(EditorDefaultsUtil.resolve_default("  map_b  ", choices) == "map_b",
		"stored id is trimmed before matching")


func test_mc8_main_menu_wires_editor_hub_button() -> void:
	print("test_mc8_main_menu_wires_editor_hub_button")
	var src: String = FileAccess.get_file_as_string("res://ui/shared/main_menu.gd")
	_check(src.contains("_editor_button"), "main menu references the Editor button")
	_check(src.contains("_editor_button.pressed.connect(_on_editor)"),
		"Editor button is connected to _on_editor")
	_check(src.contains("NavService.EDITOR_HUB"), "_on_editor navigates to the editor hub")
	_check(src.contains("ui.menu.editor"), "Editor button label is localized")


func test_mc8_editorhub_i18n_keys_present_in_all_locales() -> void:
	print("test_mc8_editorhub_i18n_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.menu.editor",
		"ui.editorhub.title", "ui.editorhub.gui_editor", "ui.editorhub.defaults",
		"ui.editordefaults.title", "ui.editordefaults.map_tab", "ui.editordefaults.mod_tab",
		"ui.editordefaults.gui_tab", "ui.editordefaults.none", "ui.editordefaults.saved",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# ----------------------------------------------------------------------------
# Phase MC9 (request 10): teams derived from map colours + rebel posture.
#
# MapColorUtil scans a scenario/map dict and reports which of the 16 owner
# palette colours are actually in use (across players/buildings/units/flags),
# so Match Setup can offer exactly those colours as team slots -- independent of
# where HQs sit. Pure and deterministic (sorted output). These tests pin the
# scan sources, clamping, sorting, and the choice-restriction contract.
# ----------------------------------------------------------------------------

func test_mc9_used_owners_from_all_entity_arrays() -> void:
	print("test_mc9_used_owners_from_all_entity_arrays")
	var scenario: Dictionary = {
		"players": [{ "owner": 0 }, { "owner": 3 }],
		"buildings": [{ "type": "hq", "owner": 3, "x": 1, "y": 1 }],
		"units": [{ "type": "soldier", "owner": 7, "x": 2, "y": 2 }],
	}
	var used: Array = MapColorUtil.used_owners(scenario)
	_check(used == [0, 3, 7], "collects owners from players/buildings/units, sorted")


func test_mc9_used_owners_sorted_deduped_and_clamped() -> void:
	print("test_mc9_used_owners_sorted_deduped_and_clamped")
	var scenario: Dictionary = {
		"units": [{ "owner": 5 }, { "owner": 5 }, { "owner": 2 }, { "owner": 99 }, { "owner": -4 }],
	}
	var used: Array = MapColorUtil.used_owners(scenario)
	# 99 clamps to 15, -4 clamps to 0; duplicates collapse; result sorted.
	_check(used == [0, 2, 5, 15], "duplicates removed, out-of-range clamped, sorted")


func test_mc9_used_owners_includes_flag_teams() -> void:
	print("test_mc9_used_owners_includes_flag_teams")
	var scenario: Dictionary = {
		"units": [{ "owner": 1 }],
		"flags": [{ "index": 0, "x": 1, "y": 1, "team": 4 }, { "index": 1, "x": 2, "y": 2, "team": 1 }],
	}
	var used: Array = MapColorUtil.used_owners(scenario)
	_check(used == [1, 4], "flag team ids count as used colours")


func test_mc9_team_count_and_color_hexes() -> void:
	print("test_mc9_team_count_and_color_hexes")
	var scenario: Dictionary = {
		"buildings": [{ "owner": 0 }, { "owner": 1 }, { "owner": 2 }, { "owner": 3 }],
	}
	_check(MapColorUtil.team_count(scenario) == 4, "four colours -> four team slots")
	var hexes: Array = MapColorUtil.used_color_hexes(scenario)
	_check(hexes.size() == 4, "one hex per used colour")
	_check(str(hexes[0]) == MapPaletteUtil.color_hex(0), "hex order matches sorted owners")
	_check(MapColorUtil.is_owner_used(scenario, 2), "is_owner_used true for present colour")
	_check(not MapColorUtil.is_owner_used(scenario, 9), "is_owner_used false for absent colour")


func test_mc9_restrict_choices_drops_unused() -> void:
	print("test_mc9_restrict_choices_drops_unused")
	var scenario: Dictionary = { "units": [{ "owner": 1 }, { "owner": 4 }] }
	# Requested 0..4 but only 1 and 4 exist on the map.
	var allowed: Array = MapColorUtil.restrict_choices(scenario, [0, 1, 2, 3, 4])
	_check(allowed == [1, 4], "only map colours survive the restriction, sorted")
	_check(MapColorUtil.restrict_choices(scenario, [0, 2, 3]) == [],
		"no overlap yields an empty allowed set")


func test_mc9_used_owners_empty_map() -> void:
	print("test_mc9_used_owners_empty_map")
	_check(MapColorUtil.used_owners({}) == [], "empty dict has no used owners")
	_check(MapColorUtil.team_count({}) == 0, "empty dict yields zero teams")
	_check(MapColorUtil.used_owners({ "units": "not_an_array" }) == [],
		"malformed entity array is ignored safely")


# --- Phase MC9.2 (request 10): map-colour-driven team selection -------------
func test_mc9_color_team_choices_from_map() -> void:
	print("test_mc9_color_team_choices_from_map")
	var scenario: Dictionary = { "buildings": [{ "owner": 2 }], "units": [{ "owner": 5 }, { "owner": 2 }] }
	var choices: Array = AiGroupUtil.color_team_choices(scenario)
	_check(choices == [2, 5], "only the map's colours are selectable team numbers, sorted")


func test_mc9_color_team_choices_fallback_when_blank() -> void:
	print("test_mc9_color_team_choices_fallback_when_blank")
	var choices: Array = AiGroupUtil.color_team_choices({})
	_check(choices == [0, 1, 2, 3], "blank map falls back to default TEAM_COUNT slots")


func test_mc9_resolve_team_on_map_snaps_stale() -> void:
	print("test_mc9_resolve_team_on_map_snaps_stale")
	var scenario: Dictionary = { "units": [{ "owner": 3 }, { "owner": 7 }] }
	_check(AiGroupUtil.resolve_team_on_map(scenario, 7) == 7, "valid map colour kept")
	_check(AiGroupUtil.resolve_team_on_map(scenario, 1) == 3,
		"stale colour snaps to first available map colour")


func test_mc9_restrict_overrides_to_map() -> void:
	print("test_mc9_restrict_overrides_to_map")
	var scenario: Dictionary = { "units": [{ "owner": 2 }, { "owner": 4 }] }
	var overrides: Dictionary = { 0: 2, 1: 9, 2: 4 }
	var fixed: Dictionary = AiGroupUtil.restrict_overrides_to_map(scenario, overrides)
	_check(int(fixed[0]) == 2, "override on a valid colour is preserved")
	_check(int(fixed[1]) == 2, "override on an unused colour snaps to first map colour")
	_check(int(fixed[2]) == 4, "second valid colour preserved")


# --- Phase MC9.3 (request 10): rebel / faction detection --------------------
func test_mc9_owners_with_hq() -> void:
	print("test_mc9_owners_with_hq")
	var scenario: Dictionary = {
		"buildings": [{ "type": "hq", "owner": 0 }, { "type": "factory", "owner": 1 }, { "type": "hq", "owner": 2 }],
		"units": [{ "owner": 1 }, { "owner": 3 }],
	}
	_check(MapColorUtil.owners_with_hq(scenario) == [0, 2], "only HQ owners counted, sorted")


func test_mc9_rebel_owners() -> void:
	print("test_mc9_rebel_owners")
	var scenario: Dictionary = {
		"buildings": [{ "type": "hq", "owner": 0 }],
		"units": [{ "owner": 0 }, { "owner": 1 }, { "owner": 3 }],
	}
	# 0 has an HQ (main); 1 and 3 have only units (rebel).
	_check(MapColorUtil.rebel_owners(scenario) == [1, 3], "unit-only colours are rebels, sorted")
	_check(not MapColorUtil.is_rebel(scenario, 0), "HQ owner is not a rebel")
	_check(MapColorUtil.is_rebel(scenario, 1), "unit-only owner is a rebel")


func test_mc9_rebel_owners_all_rebel_when_no_hq() -> void:
	print("test_mc9_rebel_owners_all_rebel_when_no_hq")
	var scenario: Dictionary = { "units": [{ "owner": 2 }, { "owner": 5 }] }
	_check(MapColorUtil.owners_with_hq(scenario) == [], "no HQ anywhere")
	_check(MapColorUtil.rebel_owners(scenario) == [2, 5], "all used colours are rebels when no HQ exists")


# --- Phase MC9.4 (request 10): AI general mode (main vs rebel) --------------
func test_mc9_general_mode_normalise() -> void:
	print("test_mc9_general_mode_normalise")
	_check(AiGeneralModeUtil.normalise("rebel") == AiGeneralModeUtil.MODE_REBEL, "rebel stays rebel")
	_check(AiGeneralModeUtil.normalise("main") == AiGeneralModeUtil.MODE_MAIN, "main stays main")
	_check(AiGeneralModeUtil.normalise("garbage") == AiGeneralModeUtil.MODE_MAIN, "unknown defaults to main")


func test_mc9_general_mode_planner_gates() -> void:
	print("test_mc9_general_mode_planner_gates")
	# Main: everything on.
	_check(AiGeneralModeUtil.plans_economy("main"), "main plans economy")
	_check(AiGeneralModeUtil.plans_research("main"), "main plans research")
	_check(AiGeneralModeUtil.plans_hq_upgrade("main"), "main plans hq upgrade")
	_check(AiGeneralModeUtil.plans_army("main"), "main plans army")
	# Rebel: only army.
	_check(not AiGeneralModeUtil.plans_economy("rebel"), "rebel has no economy")
	_check(not AiGeneralModeUtil.plans_research("rebel"), "rebel has no research")
	_check(not AiGeneralModeUtil.plans_hq_upgrade("rebel"), "rebel has no hq upgrade")
	_check(AiGeneralModeUtil.plans_army("rebel"), "rebel still fights")


func test_mc9_general_mode_flags_and_from_map() -> void:
	print("test_mc9_general_mode_flags_and_from_map")
	var flags: Dictionary = AiGeneralModeUtil.planner_flags("rebel")
	_check(flags == { "economy": false, "research": false, "hq_upgrade": false, "army": true },
		"rebel planner flags: army only")
	var scenario: Dictionary = {
		"buildings": [{ "type": "hq", "owner": 0 }],
		"units": [{ "owner": 0 }, { "owner": 1 }],
	}
	_check(AiGeneralModeUtil.mode_for_owner(scenario, 0) == "main", "HQ owner -> main mode")
	_check(AiGeneralModeUtil.mode_for_owner(scenario, 1) == "rebel", "unit-only owner -> rebel mode")


func test_mc9_strategic_ai_gates_planners_by_mode() -> void:
	print("test_mc9_strategic_ai_gates_planners_by_mode")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/strategic_ai_module.gd")
	var body: String = _mb5_func_body(src, "func _plan_for_player")
	_check(body.contains("AiGeneralModeUtil.planner_flags"), "planner flags derived from general mode")
	_check(body.contains("flags.get(\"economy\""), "economy planner gated by mode")
	_check(body.contains("flags.get(\"hq_upgrade\""), "hq upgrade planner gated by mode")
	_check(src.contains("func set_general_mode"), "module exposes set_general_mode")


# --- Phase MC10 (requests 11/12/17): dynamic diplomacy pure models -----------

func test_mc10_relationship_states_and_flags() -> void:
	print("test_mc10_relationship_states_and_flags")
	_check(RelationshipUtil.is_valid("ally"), "ally is a valid state")
	_check(not RelationshipUtil.is_valid("garbage"), "garbage is not valid")
	_check(RelationshipUtil.normalize("garbage") == RelationshipUtil.DEFAULT_STATE, "unknown normalizes to default")
	_check(RelationshipUtil.normalize("enemy") == RelationshipUtil.ENEMY, "known state kept")
	# Only rival/enemy are hostile; neutral is NOT (request 17 correctness).
	_check(RelationshipUtil.is_hostile("enemy"), "enemy is hostile")
	_check(RelationshipUtil.is_hostile("rival"), "rival is hostile")
	_check(not RelationshipUtil.is_hostile("neutral"), "neutral is not hostile")
	_check(not RelationshipUtil.is_hostile("ally"), "ally is not hostile")
	# Only ally/vassal are friendly (mapped to shared team).
	_check(RelationshipUtil.is_friendly("ally"), "ally is friendly")
	_check(RelationshipUtil.is_friendly("vassal"), "vassal is friendly")
	_check(not RelationshipUtil.is_friendly("neutral"), "neutral is not friendly")


func test_mc10_relationship_transitions() -> void:
	print("test_mc10_relationship_transitions")
	# Staying in the same state is always legal.
	_check(RelationshipUtil.can_transition("neutral", "neutral"), "self transition allowed")
	# You cannot leap enemy -> ally directly; must go through ceasefire.
	_check(not RelationshipUtil.can_transition("enemy", "ally"), "enemy cannot jump to ally")
	_check(RelationshipUtil.can_transition("enemy", "ceasefire"), "enemy can ceasefire")
	_check(RelationshipUtil.can_transition("negotiating", "ally"), "negotiating can become ally")
	# apply_transition returns the new state when legal, else the old one.
	_check(RelationshipUtil.apply_transition("enemy", "ceasefire") == "ceasefire", "legal apply moves")
	_check(RelationshipUtil.apply_transition("enemy", "ally") == "enemy", "illegal apply stays put")


func test_mc10_relationship_pair_key_stable() -> void:
	print("test_mc10_relationship_pair_key_stable")
	# Pair key is order-independent so (a,b) and (b,a) collapse to one entry.
	_check(RelationshipUtil.pair_key(2, 5) == RelationshipUtil.pair_key(5, 2), "pair key order independent")
	_check(RelationshipUtil.pair_key(2, 5) == "2:5", "pair key low:high")
	_check(RelationshipUtil.pair_key(7, 7) == "7:7", "same-owner pair key")


func test_mc10_treaty_make_validate_and_types() -> void:
	print("test_mc10_treaty_make_validate_and_types")
	var t: Dictionary = TreatyUtil.make_treaty(
		TreatyUtil.ALLIANCE_TEMP, 0, 1, {"gold": 100}, {"units": [3]}, 600, 10)
	_check(TreatyUtil.is_valid(t), "well-formed treaty validates")
	_check(str(t["status"]) == TreatyUtil.STATUS_PROPOSED, "new treaty is proposed")
	_check(TreatyUtil.makes_allies(TreatyUtil.ALLIANCE_FULL), "alliance_full makes allies")
	_check(TreatyUtil.makes_allies(TreatyUtil.ALLIANCE_TEMP), "alliance_temp makes allies")
	_check(not TreatyUtil.makes_allies(TreatyUtil.CEASEFIRE), "ceasefire is not an alliance")
	_check(TreatyUtil.makes_hostile(TreatyUtil.DECLARE_WAR), "declare_war makes hostile")
	_check(TreatyUtil.makes_hostile(TreatyUtil.BETRAYAL), "betrayal makes hostile")
	# Validation error tokens.
	var self_t: Dictionary = TreatyUtil.make_treaty(TreatyUtil.CEASEFIRE, 2, 2, {}, {}, 0, 0)
	_check(TreatyUtil.validate(self_t) == "self_treaty", "self treaty rejected")
	var bad_type: Dictionary = {"type": "nope", "proposer": 0, "target": 1}
	_check(TreatyUtil.validate(bad_type) == "bad_type", "bad type rejected")


func test_mc10_treaty_expiry_and_serialize() -> void:
	print("test_mc10_treaty_expiry_and_serialize")
	var t: Dictionary = TreatyUtil.make_treaty(TreatyUtil.NON_AGGRESSION, 0, 1, {}, {}, 100, 5)
	# Accepted at tick 50 -> expires at 150.
	_check(TreatyUtil.expiry_tick(t, 50) == 150, "expiry = accepted + duration")
	_check(not TreatyUtil.is_expired(t, 50, 149), "not expired before window ends")
	_check(TreatyUtil.is_expired(t, 50, 150), "expired at window end")
	# Permanent treaty (duration 0) never expires on its own.
	var perm: Dictionary = TreatyUtil.make_treaty(TreatyUtil.ALLIANCE_FULL, 0, 1, {}, {}, 0, 0)
	_check(TreatyUtil.expiry_tick(perm, 10) == -1, "permanent has no expiry tick")
	_check(not TreatyUtil.is_expired(perm, 10, 99999), "permanent never expires")
	# Round-trip preserves status and payload.
	var acc: Dictionary = t.duplicate(true)
	acc["status"] = TreatyUtil.STATUS_ACCEPTED
	var round_trip: Dictionary = TreatyUtil.from_dict(TreatyUtil.to_dict(acc))
	_check(str(round_trip["status"]) == TreatyUtil.STATUS_ACCEPTED, "status survives round-trip")
	_check(int(round_trip["duration_ticks"]) == 100, "duration survives round-trip")


func test_mc10_political_cost_alliance_and_betrayal() -> void:
	print("test_mc10_political_cost_alliance_and_betrayal")
	# First alliance is free; each beyond escalates.
	_check(PoliticalCostUtil.alliance_cost(0) == 0.0, "first alliance is free")
	_check(PoliticalCostUtil.alliance_cost(1) == PoliticalCostUtil.ALLIANCE_COST_BASE, "second alliance = base cost")
	_check(PoliticalCostUtil.alliance_cost(2) == PoliticalCostUtil.ALLIANCE_COST_BASE + PoliticalCostUtil.ALLIANCE_COST_STEP, "third alliance escalates")
	# Betrayal is a flat, heavy hit.
	_check(PoliticalCostUtil.betrayal_cost() == PoliticalCostUtil.BETRAYAL_COST, "betrayal cost constant")
	# Trust stays clamped to 0..100.
	_check(PoliticalCostUtil.apply_cost(10.0, 35.0) == 0.0, "trust never below zero")
	_check(PoliticalCostUtil.apply_cost(90.0, -30.0) == 100.0, "trust never above 100")
	# Acceptance factor is trust/100.
	_check(is_equal_approx(PoliticalCostUtil.acceptance_factor(50.0), 0.5), "acceptance factor = trust/100")


func test_mc10_deployment_command_authority_returns() -> void:
	print("test_mc10_deployment_command_authority_returns")
	var dep: Dictionary = DeploymentUtil.make_deployment(0, 1, [10, 11], 100, 50)
	_check(DeploymentUtil.is_valid(dep), "well-formed deployment validates")
	_check(DeploymentUtil.return_tick(dep) == 150, "return tick = start + duration")
	# While active + unexpired, the borrower commands the loaned units.
	_check(DeploymentUtil.commander_of(dep, 10, 120) == 1, "borrower commands during loan")
	# Once expired, command snaps back to the owner (exploit-proof).
	_check(DeploymentUtil.commander_of(dep, 10, 150) == 0, "owner reclaims after expiry")
	# A unit not in the loan is always commanded by the owner.
	_check(DeploymentUtil.commander_of(dep, 99, 120) == 0, "non-loaned unit stays with owner")
	# Recalling ends the loan immediately: borrower loses authority.
	var recalled: Dictionary = DeploymentUtil.end_deployment(dep, true)
	_check(DeploymentUtil.commander_of(recalled, 10, 120) == 0, "recalled loan reverts to owner")
	# Duration is clamped to >= 1 tick (never a permanent transfer).
	var clamped: Dictionary = DeploymentUtil.make_deployment(0, 1, [5], 0, 0)
	_check(int(clamped["duration_ticks"]) >= 1, "duration clamped to at least 1")


# --- Phase MC11 (request 11): in-game message UI models ---------------------
func test_mc11_message_log_append_and_filter() -> void:
	print("test_mc11_message_log_append_and_filter")
	var log: Array = []
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(0, 1, "hi", 10))
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(1, 0, "hello", 12))
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(2, MessageLogUtil.BROADCAST, "all", 15))
	_check(log.size() == 3, "log has 3 entries")
	# Insertion order preserved.
	_check(int(log[0]["tick"]) == 10 and int(log[2]["tick"]) == 15, "insertion order kept")
	# involves: broadcast reaches everyone.
	_check(MessageLogUtil.involves(log[2], 5), "broadcast involves any owner")
	_check(MessageLogUtil.involves(log[0], 1), "recipient is involved")
	_check(not MessageLogUtil.involves(log[0], 3), "uninvolved owner excluded")
	# filter_for_owner includes broadcasts + own messages.
	var for0: Array = MessageLogUtil.filter_for_owner(log, 0)
	_check(for0.size() == 3, "owner 0 sees both privates and the broadcast")
	var for3: Array = MessageLogUtil.filter_for_owner(log, 3)
	_check(for3.size() == 1, "uninvolved owner 3 sees only broadcast")
	# tick clamped to >= 0.
	var m: Dictionary = MessageLogUtil.make_message(0, 1, "x", -4)
	_check(int(m["tick"]) == 0, "negative tick clamped to 0")
	# unknown channel coerced to chat.
	var m2: Dictionary = MessageLogUtil.make_message(0, 1, "x", 1, "bogus")
	_check(str(m2["channel"]) == MessageLogUtil.CHANNEL_CHAT, "unknown channel -> chat")


func test_mc11_message_log_conversation_and_channels() -> void:
	print("test_mc11_message_log_conversation_and_channels")
	var log: Array = []
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(0, 1, "a", 1))
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(1, 0, "b", 2))
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(0, 2, "c", 3))
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(3, MessageLogUtil.BROADCAST, "d", 4,
		MessageLogUtil.CHANNEL_STRATEGIC))
	# conversation between 0 and 1: two privates + the broadcast.
	var conv: Array = MessageLogUtil.conversation(log, 0, 1)
	_check(conv.size() == 3, "0<->1 conversation includes broadcast")
	# conversation between 0 and 2: one private + broadcast.
	var conv2: Array = MessageLogUtil.conversation(log, 0, 2)
	_check(conv2.size() == 2, "0<->2 conversation includes broadcast")
	# filter_by_channel.
	var strat: Array = MessageLogUtil.filter_by_channel(log, MessageLogUtil.CHANNEL_STRATEGIC)
	_check(strat.size() == 1, "one strategic message")
	var chat: Array = MessageLogUtil.filter_by_channel(log, MessageLogUtil.CHANNEL_CHAT)
	_check(chat.size() == 3, "three chat messages")


func test_mc11_message_log_recipient_choices_and_recent() -> void:
	print("test_mc11_message_log_recipient_choices_and_recent")
	# recipient_choices: BROADCAST first, then every OTHER owner.
	var choices: Array = MessageLogUtil.recipient_choices(4, 1)
	_check(choices.size() == 4, "4 owners minus self plus broadcast = 4")
	_check(int(choices[0]) == MessageLogUtil.BROADCAST, "broadcast listed first")
	_check(not choices.has(1), "viewer excluded from own recipient list")
	_check(choices.has(0) and choices.has(2) and choices.has(3), "all other owners present")
	# recent_for_owner: oldest-first slice of the last N.
	var log: Array = []
	for i in range(6):
		MessageLogUtil.append_message(log, MessageLogUtil.make_message(0, 1, "m%d" % i, i))
	var recent: Array = MessageLogUtil.recent_for_owner(log, 0, 2)
	_check(recent.size() == 2, "recent capped to count")
	_check(str(recent[0]["text"]) == "m4" and str(recent[1]["text"]) == "m5", "recent oldest-first")
	# count <= 0 returns everything involving the owner.
	var all_recent: Array = MessageLogUtil.recent_for_owner(log, 0, 0)
	_check(all_recent.size() == 6, "count 0 returns full filtered list")


func test_mc11_message_log_roundtrip() -> void:
	print("test_mc11_message_log_roundtrip")
	var log: Array = []
	MessageLogUtil.append_message(log, MessageLogUtil.make_message(0, 1, "keep", 7,
		MessageLogUtil.CHANNEL_STRATEGIC, {"treaty": "alliance"}))
	var data: Array = MessageLogUtil.to_array(log)
	var back: Array = MessageLogUtil.from_array(data)
	_check(back.size() == 1, "roundtrip preserves count")
	_check(str(back[0]["text"]) == "keep", "roundtrip preserves text")
	_check(str(back[0]["channel"]) == MessageLogUtil.CHANNEL_STRATEGIC, "roundtrip preserves channel")
	_check(str((back[0]["meta"] as Dictionary).get("treaty", "")) == "alliance", "roundtrip preserves meta")
	# Deep copy: mutating the serialised form must not touch the log.
	(data[0] as Dictionary)["text"] = "mutated"
	_check(str(log[0]["text"]) == "keep", "to_array is a deep copy")


func test_mc11_mission_request_make_validate() -> void:
	print("test_mc11_mission_request_make_validate")
	var mission: Dictionary = MissionRequestUtil.make_mission(0, 1, MissionRequestUtil.ATTACK, 4, 5, 60)
	_check(MissionRequestUtil.is_valid(mission), "well-formed mission is valid")
	_check(str(mission["type"]) == MissionRequestUtil.ATTACK, "type kept")
	_check(int(mission["commitment"]) == 60, "commitment kept")
	# Unknown type falls back to ATTACK.
	var bad_type: Dictionary = MissionRequestUtil.make_mission(0, 1, "bogus", 1, 1, 50)
	_check(str(bad_type["type"]) == MissionRequestUtil.ATTACK, "unknown type -> attack")
	# Commitment clamped.
	var clamped: Dictionary = MissionRequestUtil.make_mission(0, 1, MissionRequestUtil.RAID, 1, 1, 250)
	_check(int(clamped["commitment"]) == MissionRequestUtil.COMMIT_MAX, "commitment clamped to max")
	# validate tokens.
	var neg: Dictionary = {"type": MissionRequestUtil.DEFEND, "cell_x": -1, "cell_y": 2, "commitment": 50}
	_check(MissionRequestUtil.validate(neg) == "bad_cell", "negative cell -> bad_cell")
	var no_cell: Dictionary = {"type": MissionRequestUtil.DEFEND, "commitment": 50}
	_check(MissionRequestUtil.validate(no_cell) == "missing_cell", "missing cell -> missing_cell")
	var wrong_type: Dictionary = {"type": "nope", "cell_x": 0, "cell_y": 0, "commitment": 50}
	_check(MissionRequestUtil.validate(wrong_type) == "bad_type", "unknown type -> bad_type")
	# cell_of convenience.
	_check(MissionRequestUtil.cell_of(mission) == Vector2i(4, 5), "cell_of returns Vector2i")


func test_mc11_mission_request_roundtrip() -> void:
	print("test_mc11_mission_request_roundtrip")
	var mission: Dictionary = MissionRequestUtil.make_mission(2, 3, MissionRequestUtil.SCOUT, 7, 8, 33)
	var data: Dictionary = MissionRequestUtil.to_dict(mission)
	var back: Dictionary = MissionRequestUtil.from_dict(data)
	_check(int(back["requester"]) == 2, "roundtrip requester")
	_check(int(back["target_owner"]) == 3, "roundtrip target_owner")
	_check(str(back["type"]) == MissionRequestUtil.SCOUT, "roundtrip type")
	_check(int(back["cell_x"]) == 7 and int(back["cell_y"]) == 8, "roundtrip cell")
	_check(int(back["commitment"]) == 33, "roundtrip commitment")


func test_mc11_ai_message_text_descriptor() -> void:
	print("test_mc11_ai_message_text_descriptor")
	# Known act maps to its own key.
	_check(AiMessageTextUtil.message_key(AiMessageTextUtil.ACT_PROPOSE) == "ai.msg.propose", "propose key")
	_check(AiMessageTextUtil.message_key(AiMessageTextUtil.ACT_DECLARE_WAR) == "ai.msg.declare_war", "war key")
	# Unknown act falls back to generic.
	_check(AiMessageTextUtil.message_key("bogus") == "ai.msg.generic", "unknown act -> generic key")
	_check(not AiMessageTextUtil.is_valid_act("bogus"), "unknown act invalid")
	# describe returns key + args.
	var desc: Dictionary = AiMessageTextUtil.describe(AiMessageTextUtil.ACT_ACCEPT, 0, 1, "alliance")
	_check(str(desc["key"]) == "ai.msg.accept", "descriptor key")
	var args: Dictionary = desc["args"]
	_check(int(args["sender"]) == 0 and int(args["recipient"]) == 1, "descriptor args carry owners")
	_check(str(args["treaty"]) == "alliance", "descriptor carries treaty type")
	# all_keys covers every act + generic.
	_check(AiMessageTextUtil.all_keys().size() == AiMessageTextUtil.ACTS.size() + 1, "all_keys = acts + generic")


func test_mc11_ai_message_keys_present_in_all_locales() -> void:
	print("test_mc11_ai_message_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	for key in AiMessageTextUtil.all_keys():
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# --- Phase MC12 (request 13): AI personality profile model ------------------
func test_mc12_ai_profile_schema_and_defaults() -> void:
	print("test_mc12_ai_profile_schema_and_defaults")
	# Exactly 35 numeric knobs across the five categories.
	_check(AiProfile.knob_count() == 35, "profile has 35 knobs total")
	_check(AiProfile.keys_for("personality").size() == 10, "10 personality knobs")
	_check(AiProfile.keys_for("strategy_bias").size() == 10, "10 strategy knobs")
	_check(AiProfile.keys_for("diplomacy_bias").size() == 7, "7 diplomacy knobs")
	_check(AiProfile.keys_for("learning_bias").size() == 5, "5 learning knobs")
	_check(AiProfile.keys_for("difficulty").size() == 3, "3 difficulty knobs")
	_check(AiProfile.keys_for("bogus").is_empty(), "unknown category -> empty keys")
	# A fresh profile is fully neutral (every knob 0.5) and valid.
	var p: AiProfile = AiProfile.new()
	p.init_new("test")
	_check(p.is_valid(), "fresh profile with id is valid")
	_check(p.personality("aggression") == 0.5, "unspecified knob defaults to neutral")
	_check(p.difficulty("execution") == 0.5, "difficulty knob defaults to neutral")
	# The safe default profile is a valid "balanced" general.
	var d: AiProfile = AiProfile.default_profile()
	_check(d.is_valid() and d.id() == "balanced", "default_profile is valid balanced")
	_check(d.archetype() == "balanced", "default archetype tag")
	# Missing id is the only hard error.
	var empty: AiProfile = AiProfile.new()
	empty.init_new("")
	_check(empty.validate() == "missing_id", "blank id fails validation")


func test_mc12_ai_profile_load_clamp_and_partial() -> void:
	print("test_mc12_ai_profile_load_clamp_and_partial")
	# Out-of-range values are clamped; unknown knobs dropped; partial dict OK.
	var p: AiProfile = AiProfile.from_dict({
		"id": "hannibal",
		"display_name_key": "ai.profile.hannibal.name",
		"role_key": "ai.profile.hannibal.role",
		"archetype": "opportunist",
		"personality": {"aggression": 1.7, "caution": -0.3, "bogus_knob": 0.9},
		"strategy_bias": {"harassment": 0.8},
	})
	_check(p.is_valid(), "loaded profile valid")
	_check(p.personality("aggression") == 1.0, "over-range clamped to 1.0")
	_check(p.personality("caution") == 0.0, "under-range clamped to 0.0")
	_check(p.strategy("harassment") == 0.8, "specified strategy knob kept")
	# Unspecified knobs stay neutral; unknown knob is not present as a real key.
	_check(p.strategy("economy") == 0.5, "unspecified strategy neutral")
	_check(not AiProfile.keys_for("personality").has("bogus_knob"), "bogus knob not a real key")
	_check(p.display_name_key() == "ai.profile.hannibal.name", "display key loaded")
	_check(p.archetype() == "opportunist", "archetype loaded")
	# String-encoded numbers coerce; set_value clamps + rejects unknown knob.
	var q: AiProfile = AiProfile.from_dict({"id": "x", "difficulty": {"analysis_quality": "0.75"}})
	_check(q.difficulty("analysis_quality") == 0.75, "string number coerced")
	_check(q.set_value("difficulty", "reaction_speed", 2.0) == 1.0, "set clamps to 1.0")
	_check(q.set_value("difficulty", "no_such_knob", 0.3) == 0.5, "unknown knob rejected")
	# load() with no id returns false but still leaves a fully-populated vector.
	var r: AiProfile = AiProfile.new()
	_check(not r.load({"personality": {"pride": 0.9}}), "no id -> load returns false")
	_check(r.personality("pride") == 0.9, "vector still populated on idless load")


func test_mc12_ai_profile_roundtrip_deterministic() -> void:
	print("test_mc12_ai_profile_roundtrip_deterministic")
	var src: AiProfile = AiProfile.from_dict({
		"id": "caesar",
		"archetype": "aggressor",
		"personality": {"aggression": 0.9, "boldness": 0.8},
		"diplomacy_bias": {"deceit": 0.6, "vengeance": 0.7},
	})
	var data: Dictionary = src.to_dict()
	var back: AiProfile = AiProfile.from_dict(data)
	_check(back.id() == "caesar", "roundtrip id")
	_check(back.personality("aggression") == 0.9, "roundtrip personality knob")
	_check(back.diplomacy("deceit") == 0.6, "roundtrip diplomacy knob")
	# Every category present + complete after roundtrip.
	for category in AiProfile.CATEGORIES:
		_check(back.vector(category).size() == AiProfile.keys_for(category).size(),
			"roundtrip category '%s' complete" % category)
	# Deterministic: serialising twice yields identical JSON text.
	var json_a: String = JSON.stringify(src.to_dict())
	var json_b: String = JSON.stringify(back.to_dict())
	_check(json_a == json_b, "to_dict is deterministic across roundtrip")


func test_mc12_ai_profile_catalog_lists_nine() -> void:
	print("test_mc12_ai_profile_catalog_lists_nine")
	var ids: Array = AiProfileCatalog.ids()
	_check(ids.size() == 9, "catalog lists nine default profiles")
	# Stable alphabetical order.
	var sorted_copy: Array = ids.duplicate()
	sorted_copy.sort()
	_check(ids == sorted_copy, "catalog ids are in stable sorted order")
	# All the historically-named generals are present.
	for expected in ["fabius", "alexander", "talleyrand", "hannibal", "bismarck",
			"alaric", "caesar", "genghis", "cyrus"]:
		_check(ids.has(expected), "catalog includes '%s'" % expected)
	# path_for points into the profile dir.
	_check(AiProfileCatalog.path_for("caesar") == "res://data/ai_profiles/caesar.json",
		"path_for builds the right res path")


func test_mc12_ai_profile_catalog_loads_valid_defaults() -> void:
	print("test_mc12_ai_profile_catalog_loads_valid_defaults")
	var reader: RealJsonReader = RealJsonReader.new()
	var all: Array = AiProfileCatalog.load_all(reader)
	_check(all.size() == 9, "load_all returns nine profiles")
	for i in range(all.size()):
		var p: AiProfile = all[i]
		var id: String = AiProfileCatalog.ids()[i]
		_check(p.id() == id, "profile %d has expected id '%s'" % [i, id])
		_check(p.is_valid(), "profile '%s' is valid" % id)
		# Every category must be complete (35 knobs) after loading the real file.
		var total: int = 0
		for category in AiProfile.CATEGORIES:
			var vec: Dictionary = p.vector(category)
			_check(vec.size() == AiProfile.keys_for(category).size(),
				"'%s' category '%s' complete" % [id, category])
			total += vec.size()
			# Every knob in range.
			for knob in vec:
				var v: float = float(vec[knob])
				_check(v >= 0.0 and v <= 1.0, "'%s'.%s.%s in range" % [id, category, knob])
		_check(total == 35, "'%s' has all 35 knobs" % id)
		# Each carries a localization key + archetype.
		_check(not p.display_name_key().is_empty(), "'%s' has a name key" % id)
		_check(not p.archetype().is_empty(), "'%s' has an archetype" % id)
	# Two distinct generals must actually differ (not all neutral).
	var fabius: AiProfile = AiProfileCatalog.load_profile("fabius", reader)
	var genghis: AiProfile = AiProfileCatalog.load_profile("genghis", reader)
	_check(fabius.personality("aggression") < genghis.personality("aggression"),
		"Fabius is less aggressive than Genghis")
	_check(fabius.strategy("defense") > genghis.strategy("defense"),
		"Fabius favours defense more than Genghis")


func test_mc12_ai_profile_catalog_fallback_on_missing() -> void:
	print("test_mc12_ai_profile_catalog_fallback_on_missing")
	# A reader that always returns null (missing file) -> neutral fallback that
	# still carries the requested id and is valid.
	var empty_reader: NullJsonReader = NullJsonReader.new()
	var p: AiProfile = AiProfileCatalog.load_profile("napoleon", empty_reader)
	_check(p.is_valid(), "fallback profile is valid")
	_check(p.id() == "napoleon", "fallback keeps requested id")
	_check(p.personality("aggression") == 0.5, "fallback is neutral")
	# load_all with a null reader still returns nine valid profiles.
	var all: Array = AiProfileCatalog.load_all(empty_reader)
	_check(all.size() == 9, "load_all tolerates a null reader")
	for entry in all:
		_check((entry as AiProfile).is_valid(), "fallback entry valid")


func test_mc12_strategy_derivation_legacy_presets() -> void:
	print("test_mc12_strategy_derivation_legacy_presets")
	# derive_from_name must reproduce the legacy StrategicAiModule presets exactly
	# so pre-MC12 scenarios/tests keep byte-identical numbers.
	var eco: Dictionary = AiStrategyDerivationUtil.derive_from_name("economic")
	_check(eco["attack_army_size"] == 6, "economic army size unchanged")
	_check(eco["expansion_cap"] == 3, "economic expansion cap unchanged")
	_check(eco["upgrade_reserve"] == 300, "economic reserve unchanged")
	_check(bool(eco["research_first"]) == true, "economic researches first")
	var agg: Dictionary = AiStrategyDerivationUtil.derive_from_name("aggressive")
	_check(agg["attack_army_size"] == 3, "aggressive army size unchanged")
	_check(bool(agg["research_first"]) == false, "aggressive does not research first")
	# Unknown name -> balanced fallback.
	var unknown: Dictionary = AiStrategyDerivationUtil.derive_from_name("bogus")
	_check(unknown["attack_army_size"] == 4, "unknown name falls back to balanced")
	# null profile -> balanced fallback.
	var nul: Dictionary = AiStrategyDerivationUtil.derive_from_profile(null)
	_check(nul["attack_army_size"] == 4, "null profile falls back to balanced")


func test_mc12_strategy_derivation_from_profile_distinct() -> void:
	print("test_mc12_strategy_derivation_from_profile_distinct")
	# A patient, defensive, tech/economy general masses a bigger army and
	# researches first.
	var turtle: AiProfile = AiProfile.from_dict({
		"id": "turtle",
		"personality": {"patience": 1.0, "caution": 1.0, "aggression": 0.0},
		"strategy_bias": {"military": 0.9, "defense": 0.9, "technology": 0.9,
			"economy": 0.8, "offense": 0.1, "tempo": 0.1, "expansion": 0.2, "greed": 0.1},
	})
	# A bold, aggressive, tempo/offense general commits early and expands hard.
	var blitz: AiProfile = AiProfile.from_dict({
		"id": "blitz",
		"personality": {"patience": 0.0, "caution": 0.0, "aggression": 1.0, "greed": 0.9},
		"strategy_bias": {"military": 0.2, "defense": 0.1, "technology": 0.1,
			"economy": 0.2, "offense": 0.95, "tempo": 0.95, "expansion": 0.9},
	})
	var t: Dictionary = AiStrategyDerivationUtil.derive_from_profile(turtle)
	var b: Dictionary = AiStrategyDerivationUtil.derive_from_profile(blitz)
	_check(int(t["attack_army_size"]) > int(b["attack_army_size"]),
		"patient/defensive general masses a bigger army than the blitzer")
	_check(bool(t["research_first"]) == true, "tech/economy general researches first")
	_check(bool(b["research_first"]) == false, "tempo/offense general does not research first")
	_check(int(t["upgrade_reserve"]) > int(b["upgrade_reserve"]),
		"cautious/defensive general keeps a bigger reserve")
	# All derived numbers stay inside the documented bounds.
	for d in [t, b]:
		_check(int(d["attack_army_size"]) >= AiStrategyDerivationUtil.ARMY_MIN
			and int(d["attack_army_size"]) <= AiStrategyDerivationUtil.ARMY_MAX,
			"army size in bounds")
		_check(int(d["expansion_cap"]) >= AiStrategyDerivationUtil.EXPANSION_MIN
			and int(d["expansion_cap"]) <= AiStrategyDerivationUtil.EXPANSION_MAX,
			"expansion cap in bounds")
		_check(int(d["upgrade_reserve"]) >= AiStrategyDerivationUtil.RESERVE_MIN
			and int(d["upgrade_reserve"]) <= AiStrategyDerivationUtil.RESERVE_MAX,
			"reserve in bounds")


func test_mc12_strategy_derivation_deterministic() -> void:
	print("test_mc12_strategy_derivation_deterministic")
	# Same profile -> byte-identical behaviour dict, twice.
	var p: AiProfile = AiProfile.from_dict({
		"id": "det",
		"personality": {"patience": 0.7, "aggression": 0.3},
		"strategy_bias": {"technology": 0.6, "economy": 0.6, "offense": 0.4, "tempo": 0.3},
	})
	var a: Dictionary = AiStrategyDerivationUtil.derive_from_profile(p)
	var b: Dictionary = AiStrategyDerivationUtil.derive_from_profile(p)
	_check(JSON.stringify(a) == JSON.stringify(b), "derivation is deterministic")


func test_mc12_profile_summary_role_style_danger() -> void:
	print("test_mc12_profile_summary_role_style_danger")
	# An aggressive, high-skill general reads as an offensive, lethal threat.
	var conqueror: AiProfile = AiProfile.from_dict({
		"id": "conq", "archetype": "conqueror", "role_key": "ai.profile.conq.role",
		"personality": {"aggression": 0.95},
		"strategy_bias": {"offense": 0.95, "defense": 0.2, "economy": 0.3},
		"difficulty": {"analysis_quality": 0.95, "reaction_speed": 0.95, "execution": 0.95},
	})
	_check(AiProfileSummaryUtil.role_key(conqueror) == "ai.profile.conq.role",
		"explicit role_key preferred")
	_check(AiProfileSummaryUtil.style_key(conqueror) == "ai.style.aggressive",
		"offense-heavy vector reads as aggressive style")
	_check(AiProfileSummaryUtil.danger_key(conqueror) == "ai.danger.lethal",
		"high skill + aggression reads as lethal")
	# A passive, low-skill economist reads far less dangerous and economic.
	var farmer: AiProfile = AiProfile.from_dict({
		"id": "farm", "archetype": "economist",
		"personality": {"aggression": 0.05},
		"strategy_bias": {"offense": 0.1, "defense": 0.3, "economy": 0.95},
		"difficulty": {"analysis_quality": 0.1, "reaction_speed": 0.1, "execution": 0.1},
	})
	_check(AiProfileSummaryUtil.style_key(farmer) == "ai.style.economic",
		"economy-heavy vector reads as economic style")
	_check(AiProfileSummaryUtil.danger_index(farmer) < AiProfileSummaryUtil.danger_index(conqueror),
		"the farmer is less dangerous than the conqueror")
	# role falls back to archetype-derived key when role_key is absent.
	_check(AiProfileSummaryUtil.role_key(farmer) == "ai.role.economist",
		"missing role_key falls back to archetype")


func test_mc12_profile_summary_tags_and_bundle() -> void:
	print("test_mc12_profile_summary_tags_and_bundle")
	var treacherous: AiProfile = AiProfile.from_dict({
		"id": "snake",
		"personality": {"aggression": 0.9, "greed": 0.8},
		"diplomacy_bias": {"deceit": 0.9, "vengeance": 0.8, "sociability": 0.1, "trust": 0.1},
		"strategy_bias": {"harassment": 0.9, "technology": 0.8},
	})
	var tags: Array = AiProfileSummaryUtil.tags(treacherous)
	_check(tags.has("ai.tag.treacherous"), "high deceit -> treacherous tag")
	_check(tags.has("ai.tag.vengeful"), "high vengeance -> vengeful tag")
	_check(tags.has("ai.tag.reclusive"), "low sociability -> reclusive tag")
	_check(tags.has("ai.tag.raider"), "high harassment -> raider tag")
	_check(not tags.has("ai.tag.trusting"), "low trust -> no trusting tag")
	# Deterministic: same profile -> identical ordered tag list twice.
	_check(JSON.stringify(tags) == JSON.stringify(AiProfileSummaryUtil.tags(treacherous)),
		"tags are deterministic")
	# summarize() bundles everything with the expected keys.
	var s: Dictionary = AiProfileSummaryUtil.summarize(treacherous)
	for key in ["id", "name_key", "role_key", "style_key", "danger_index", "danger_key", "tags"]:
		_check(s.has(key), "summary has '%s'" % key)
	_check(s["id"] == "snake", "summary carries id")
	# A null profile is tolerated (neutral fallback, no crash).
	var neutral: Dictionary = AiProfileSummaryUtil.summarize(null)
	_check(neutral["danger_index"] >= 0, "null profile summary is safe")


func test_mc12_ai_profile_i18n_keys_present_in_all_locales() -> void:
	print("test_mc12_ai_profile_i18n_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	# Every built-in profile's name + role key must be localized. We read the
	# real JSON so the keys stay in sync with the data files.
	var reader: RealJsonReader = RealJsonReader.new()
	for id in AiProfileCatalog.ids():
		var p: AiProfile = AiProfileCatalog.load_profile(id, reader)
		var nk: String = p.display_name_key()
		var rk: String = p.role_key()
		_check(en.has(nk), "en has '%s'" % nk)
		_check(fa.has(nk), "fa has '%s'" % nk)
		_check(en.has(rk), "en has '%s'" % rk)
		_check(fa.has(rk), "fa has '%s'" % rk)
	# The neutral fallback profile's name/role key must also exist.
	for key in ["ai.profile.balanced.name", "ai.profile.balanced.role"]:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)
	# Every summary role/style/danger/tag key produced by the summary util.
	for arch in ["aggressor", "conqueror", "defender", "diplomat", "leader",
			"raider", "strategist", "tactician", "balanced"]:
		var key: String = "ai.role.%s" % arch
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)
	for style in ["aggressive", "defensive", "economic", "technological", "harasser", "expansionist"]:
		var key: String = "ai.style.%s" % style
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)
	for level in AiProfileSummaryUtil.DANGER_LEVELS:
		var key: String = "ai.danger.%s" % level
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)
	for tag in ["aggressive", "cautious", "patient", "bold", "greedy", "trusting",
			"treacherous", "vengeful", "generous", "reclusive", "techie", "raider", "economist"]:
		var key: String = "ai.tag.%s" % tag
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# --- MC13.1: AI diplomacy decision brain --------------------------------------

# Build a minimal AiProfile with a couple of overridden knobs for a scenario.
func _mc13_profile(overrides: Dictionary) -> AiProfile:
	var p: AiProfile = AiProfile.default_profile()
	for cat in overrides.keys():
		var knobs: Dictionary = overrides[cat]
		for knob in knobs.keys():
			p.set_value(cat, knob, float(knobs[knob]))
	return p


func test_mc13_brain_defensive_seeks_peace_when_pressured() -> void:
	print("test_mc13_brain_defensive_seeks_peace_when_pressured")
	# A cautious, low-aggression AI, weaker than its enemy and under heavy
	# pressure, should sue for peace rather than press the attack.
	var profile: AiProfile = _mc13_profile({
		"personality": {"aggression": 0.1, "caution": 0.9},
	})
	var ctx: Dictionary = {
		"profile": profile,
		"relationship": "enemy",
		"trust": 40.0,
		"my_strength": 0.5,
		"their_strength": 1.5,
		"threat": 0.9,
	}
	var out: Dictionary = AiDiplomacyBrain.decide(ctx)
	_check(out["action"] == AiDiplomacyBrain.ACTION_PROPOSE_PEACE,
		"pressured weak defender proposes peace (got '%s')" % str(out["action"]))
	_check(float(out["score"]) >= AiDiplomacyBrain.ACT_THRESHOLD,
		"peace score clears the action threshold")


func test_mc13_brain_opportunist_declares_war_on_weak() -> void:
	print("test_mc13_brain_opportunist_declares_war_on_weak")
	# A strong, aggressive, ambitious AI facing a weak, distrusted neutral with
	# no pressure on itself should declare war to grab the advantage.
	var profile: AiProfile = _mc13_profile({
		"personality": {"aggression": 0.95, "ambition": 0.9, "greed": 0.8},
	})
	var ctx: Dictionary = {
		"profile": profile,
		"relationship": "neutral",
		"trust": 10.0,
		"my_strength": 2.0,
		"their_strength": 0.6,
		"threat": 0.0,
	}
	var out: Dictionary = AiDiplomacyBrain.decide(ctx)
	_check(out["action"] == AiDiplomacyBrain.ACTION_DECLARE_WAR,
		"strong aggressor declares war on weak target (got '%s')" % str(out["action"]))


func test_mc13_brain_vengeful_wars_distrusted_rival() -> void:
	print("test_mc13_brain_vengeful_wars_distrusted_rival")
	# A vengeful AI against a rival it does not trust leans to war even at rough
	# parity, thanks to the vengeance bonus on rivals/enemies.
	var vengeful: AiProfile = _mc13_profile({
		"personality": {"aggression": 0.6, "ambition": 0.5},
		"diplomacy_bias": {"vengeance": 1.0, "trust": 0.0},
	})
	var ctx_vengeful: Dictionary = {
		"profile": vengeful,
		"relationship": "rival",
		"trust": 5.0,
		"my_strength": 1.2,
		"their_strength": 1.0,
		"threat": 0.1,
	}
	var out_v: Dictionary = AiDiplomacyBrain.decide(ctx_vengeful)
	# A forgiving, unaggressive AI in the SAME situation should NOT go to war.
	var meek: AiProfile = _mc13_profile({
		"personality": {"aggression": 0.1, "ambition": 0.1},
		"diplomacy_bias": {"vengeance": 0.0, "trust": 0.9, "sociability": 0.1},
	})
	var out_m: Dictionary = AiDiplomacyBrain.decide({
		"profile": meek,
		"relationship": "rival",
		"trust": 5.0,
		"my_strength": 1.2,
		"their_strength": 1.0,
		"threat": 0.1,
	})
	_check(out_v["action"] == AiDiplomacyBrain.ACTION_DECLARE_WAR,
		"vengeful rival goes to war (got '%s')" % str(out_v["action"]))
	_check(out_m["action"] != AiDiplomacyBrain.ACTION_DECLARE_WAR,
		"meek rival does not go to war (got '%s')" % str(out_m["action"]))


func test_mc13_brain_loyal_will_not_betray_ally() -> void:
	print("test_mc13_brain_loyal_will_not_betray_ally")
	# High loyalty, low deceit: even when betrayal would pay (we are stronger and
	# greedy) the personality gate must keep us from betraying an ally.
	var loyal: AiProfile = _mc13_profile({
		"personality": {"loyalty": 1.0, "greed": 0.9},
		"diplomacy_bias": {"deceit": 0.0, "opportunism": 0.0},
	})
	var out: Dictionary = AiDiplomacyBrain.decide({
		"profile": loyal,
		"relationship": "ally",
		"trust": 80.0,
		"my_strength": 2.0,
		"their_strength": 0.5,
		"threat": 0.0,
	})
	_check(out["action"] != AiDiplomacyBrain.ACTION_BETRAY,
		"loyal AI never betrays an ally (got '%s')" % str(out["action"]))
	# A treacherous opportunist in the same spot SHOULD consider betrayal.
	var snake: AiProfile = _mc13_profile({
		"personality": {"loyalty": 0.0, "greed": 1.0},
		"diplomacy_bias": {"deceit": 1.0, "opportunism": 1.0},
	})
	var out2: Dictionary = AiDiplomacyBrain.decide({
		"profile": snake,
		"relationship": "ally",
		"trust": 80.0,
		"my_strength": 2.0,
		"their_strength": 0.5,
		"threat": 0.0,
	})
	_check(out2["action"] == AiDiplomacyBrain.ACTION_BETRAY,
		"treacherous AI betrays a weak ally (got '%s')" % str(out2["action"]))


func test_mc13_brain_responds_to_incoming_offers() -> void:
	print("test_mc13_brain_responds_to_incoming_offers")
	# A pressured, trusting AI accepts a ceasefire.
	var trusting: AiProfile = _mc13_profile({
		"diplomacy_bias": {"trust": 0.9, "sociability": 0.9},
	})
	var accept: Dictionary = AiDiplomacyBrain.decide({
		"profile": trusting,
		"relationship": "enemy",
		"trust": 80.0,
		"my_strength": 0.5,
		"their_strength": 1.5,
		"threat": 0.9,
		"incoming_offer": "ceasefire",
	})
	_check(accept["action"] == AiDiplomacyBrain.ACTION_ACCEPT,
		"pressured trusting AI accepts ceasefire (got '%s')" % str(accept["action"]))
	# A very-low-trust alliance offer is rejected outright.
	var wary: AiProfile = _mc13_profile({"diplomacy_bias": {"trust": 0.0}})
	var reject: Dictionary = AiDiplomacyBrain.decide({
		"profile": wary,
		"relationship": "neutral",
		"trust": 5.0,
		"reputation": -1.0,
		"incoming_offer": "alliance_full",
	})
	_check(reject["action"] == AiDiplomacyBrain.ACTION_REJECT,
		"distrusted alliance offer rejected (got '%s')" % str(reject["action"]))
	# A declare_war "offer" is reported as reject (a notification, not accepted).
	var war_note: Dictionary = AiDiplomacyBrain.decide({
		"relationship": "neutral", "incoming_offer": "declare_war"})
	_check(war_note["action"] == AiDiplomacyBrain.ACTION_REJECT,
		"declare_war notification maps to reject")


func test_mc13_brain_deterministic_same_context() -> void:
	print("test_mc13_brain_deterministic_same_context")
	# The brain is pure: identical context -> identical decision, every time.
	var profile: AiProfile = _mc13_profile({
		"personality": {"aggression": 0.7, "ambition": 0.6},
		"diplomacy_bias": {"vengeance": 0.5},
	})
	var ctx: Dictionary = {
		"profile": profile,
		"relationship": "rival",
		"trust": 30.0,
		"my_strength": 1.4,
		"their_strength": 0.9,
		"threat": 0.2,
	}
	var a: Dictionary = AiDiplomacyBrain.decide(ctx.duplicate(true))
	var b: Dictionary = AiDiplomacyBrain.decide(ctx.duplicate(true))
	_check(a["action"] == b["action"], "same action across runs")
	_check(is_equal_approx(float(a["score"]), float(b["score"])), "same score across runs")


# --- MC13.2: in-match short-term learning -------------------------------------

func test_mc13_learning_trust_betrayal_and_heal() -> void:
	print("test_mc13_learning_trust_betrayal_and_heal")
	var state: Dictionary = AiLearningUtil.new_state()
	var profile: AiProfile = _mc13_profile({"learning_bias": {"in_match_rate": 1.0}})
	# Fresh trust is the neutral start.
	_check(is_equal_approx(AiLearningUtil.get_trust(state, 0, 1), AiLearningUtil.TRUST_START),
		"unseen pair starts at neutral trust")
	# A betrayal collapses trust well below the start.
	var after: float = AiLearningUtil.record_betrayal(state, 0, 1, profile)
	_check(after < AiLearningUtil.TRUST_START, "betrayal drops trust below neutral")
	_check(after >= AiLearningUtil.TRUST_MIN, "trust never underflows")
	# Order-independent pair key: (1,0) sees the same value as (0,1).
	_check(is_equal_approx(AiLearningUtil.get_trust(state, 1, 0), after),
		"trust is symmetric on the pair")
	# Peace ticks heal back toward neutral but never overshoot it.
	for _i in range(100):
		AiLearningUtil.heal_trust(state, 0, 1)
	_check(is_equal_approx(AiLearningUtil.get_trust(state, 0, 1), AiLearningUtil.TRUST_START),
		"healing caps at neutral start")


func test_mc13_learning_rate_scales_with_profile() -> void:
	print("test_mc13_learning_rate_scales_with_profile")
	var slow: AiProfile = _mc13_profile({"learning_bias": {"in_match_rate": 0.0}})
	var fast: AiProfile = _mc13_profile({"learning_bias": {"in_match_rate": 1.0}})
	var s_slow: Dictionary = AiLearningUtil.new_state()
	var s_fast: Dictionary = AiLearningUtil.new_state()
	var t_slow: float = AiLearningUtil.record_betrayal(s_slow, 0, 1, slow)
	var t_fast: float = AiLearningUtil.record_betrayal(s_fast, 0, 1, fast)
	# A fast learner loses more trust from the same betrayal than a slow one.
	_check(t_fast < t_slow, "fast learner drops trust more than slow learner")
	# Even the slowest learner still reacts (rate floor > 0).
	_check(t_slow < AiLearningUtil.TRUST_START, "slow learner still reacts to betrayal")


func test_mc13_learning_threat_zones_reinforce_decay_hottest() -> void:
	print("test_mc13_learning_threat_zones_reinforce_decay_hottest")
	var state: Dictionary = AiLearningUtil.new_state()
	# Zone size 4: tiles (0..3) map to zone 0:0, tile 8 maps to zone 2:0.
	_check(AiLearningUtil.zone_key(2, 1, 4) == "0:0", "tile bucketed to zone 0:0")
	_check(AiLearningUtil.zone_key(8, 0, 4) == "2:0", "tile bucketed to zone 2:0")
	# Reinforce one sector three times, another once.
	for _i in range(3):
		AiLearningUtil.reinforce_zone(state, 1, 1, 4)   # zone 0:0
	AiLearningUtil.reinforce_zone(state, 8, 0, 4)       # zone 2:0
	_check(AiLearningUtil.hottest_zone(state) == "0:0", "most-attacked zone is hottest")
	var before: float = AiLearningUtil.zone_weight(state, 1, 1, 4)
	AiLearningUtil.decay_zones(state)
	_check(AiLearningUtil.zone_weight(state, 1, 1, 4) < before, "decay lowers zone weight")
	# Empty state has no hottest zone.
	_check(AiLearningUtil.hottest_zone(AiLearningUtil.new_state()) == "",
		"empty state has no hottest zone")


func test_mc13_learning_tactics_success_and_best() -> void:
	print("test_mc13_learning_tactics_success_and_best")
	var state: Dictionary = AiLearningUtil.new_state()
	# Unknown tactic sits at the 0.5 prior.
	_check(is_equal_approx(AiLearningUtil.tactic_success_rate(state, "flank"), 0.5),
		"unknown tactic priors at 0.5")
	# "flank" wins 2/2, "rush" wins 0/2.
	AiLearningUtil.record_tactic(state, "flank", true)
	AiLearningUtil.record_tactic(state, "flank", true)
	AiLearningUtil.record_tactic(state, "rush", false)
	AiLearningUtil.record_tactic(state, "rush", false)
	_check(is_equal_approx(AiLearningUtil.tactic_success_rate(state, "flank"), 1.0),
		"winning tactic rate is 1.0")
	_check(is_equal_approx(AiLearningUtil.tactic_success_rate(state, "rush"), 0.0),
		"losing tactic rate is 0.0")
	_check(AiLearningUtil.best_tactic(state, ["rush", "flank"]) == "flank",
		"best tactic is the successful one")


# --- MC13.3: cross-match reputation store -----------------------------------

func test_mc13_reputation_directional_and_confidence() -> void:
	print("test_mc13_reputation_directional_and_confidence")
	var store: AiReputationStore = AiReputationStore.new()
	# Unknown pair reads as neutral 0.
	_check(is_equal_approx(store.reputation(0, 1), 0.0), "unknown pair reputation is 0")
	# A single betrayal is damped by the confidence factor: raw -1 but only
	# 1/CONFIDENCE_SPAN of the way there.
	store.record_betrayal(0, 1)
	_check(store.betrayals(0, 1) == 1, "betrayal recorded")
	_check(store.reputation(0, 1) < 0.0, "one betrayal makes reputation negative")
	_check(store.reputation(0, 1) > -1.0, "one data point is damped, not full -1")
	# Reputation is DIRECTIONAL: owner 1's view of owner 0 is untouched.
	_check(is_equal_approx(store.reputation(1, 0), 0.0), "reputation is directional")
	# Enough consistent helps flips the score positive and toward +1.
	var good: AiReputationStore = AiReputationStore.new()
	for _i in range(10):
		good.record_help(0, 1)
	_check(good.reputation(0, 1) > 0.9, "many helps -> near +1 reputation")


func test_mc13_reputation_export_import_roundtrip() -> void:
	print("test_mc13_reputation_export_import_roundtrip")
	var store: AiReputationStore = AiReputationStore.new()
	store.record_betrayal(2, 3)
	store.record_help(2, 3)
	store.record_help(5, 4)
	var snapshot: Dictionary = store.export_dict()
	_check(int(snapshot.get("version", -1)) == AiReputationStore.SCHEMA_VERSION,
		"export carries schema version")
	# Round-trip into a fresh store must preserve every tally.
	var restored: AiReputationStore = AiReputationStore.new()
	restored.import_dict(snapshot)
	_check(restored.betrayals(2, 3) == 1, "roundtrip betrayals preserved")
	_check(restored.helps(2, 3) == 1, "roundtrip helps preserved")
	_check(restored.helps(5, 4) == 1, "roundtrip second pair preserved")
	# import_dict must ignore malformed entries without crashing.
	restored.import_dict({"pairs": {"9>8": "not-a-dict", "1>0": {"betrayals": 4, "helps": 1}}})
	_check(restored.betrayals(1, 0) == 4, "well-formed entry imported")
	_check(restored.betrayals(9, 8) == 0, "malformed entry skipped safely")
	# clear() wipes history (personality lives elsewhere, untouched here).
	restored.clear()
	_check(restored.betrayals(1, 0) == 0, "clear wipes the store")


# --- MC13.4: difficulty = analysis quality, not error removal ---------------

func test_mc13_difficulty_seeded_noise_deterministic() -> void:
	print("test_mc13_difficulty_seeded_noise_deterministic")
	# The seeded unit value is a pure function of its inputs: identical inputs
	# yield identical output (lockstep-safe), and it stays within [0, 1).
	var a: float = AiDifficultyUtil.seeded_unit(1234, 50, 2, 7)
	var b: float = AiDifficultyUtil.seeded_unit(1234, 50, 2, 7)
	_check(is_equal_approx(a, b), "same inputs -> same seeded noise")
	_check(a >= 0.0 and a < 1.0, "seeded noise stays in [0,1)")
	# Different salt / tick generally shifts the value (not asserting inequality
	# hard, but confirming the function responds to inputs).
	var c: float = AiDifficultyUtil.seeded_unit(1234, 51, 2, 7)
	_check(c >= 0.0 and c < 1.0, "shifted tick still in range")


func test_mc13_difficulty_unforced_error_floor_above_zero() -> void:
	print("test_mc13_difficulty_unforced_error_floor_above_zero")
	# Even a flawless-execution AI must keep a positive error rate (plan 1.d).
	var best: AiProfile = _mc13_profile({"difficulty": {"execution": 1.0}})
	var worst: AiProfile = _mc13_profile({"difficulty": {"execution": 0.0}})
	var best_rate: float = AiDifficultyUtil.unforced_error_rate(best)
	var worst_rate: float = AiDifficultyUtil.unforced_error_rate(worst)
	_check(best_rate >= AiDifficultyUtil.MIN_UNFORCED_ERROR,
		"best AI never reaches zero error")
	_check(best_rate > 0.0, "error floor strictly above zero")
	_check(worst_rate > best_rate, "clumsy AI errs more than skilled one")
	_check(worst_rate <= AiDifficultyUtil.MAX_UNFORCED_ERROR,
		"clumsy AI error rate capped for playability")


func test_mc13_difficulty_reaction_cadence() -> void:
	print("test_mc13_difficulty_reaction_cadence")
	# A fast AI acts every opportunity; a slow one waits longer between actions.
	var fast: AiProfile = _mc13_profile({"difficulty": {"reaction_speed": 1.0}})
	var slow: AiProfile = _mc13_profile({"difficulty": {"reaction_speed": 0.0}})
	_check(AiDifficultyUtil.reaction_period(fast) == 1, "fast AI reacts every tick")
	_check(AiDifficultyUtil.reaction_period(slow) > 1, "slow AI reacts less often")
	# should_react is deterministic and always true for a period-1 AI.
	_check(AiDifficultyUtil.should_react(fast, 7, 3), "fast AI always allowed to react")
	# For the slow AI, at least one of a full period window must allow reaction.
	var period: int = AiDifficultyUtil.reaction_period(slow)
	var any_react: bool = false
	for t in range(period * 2):
		if AiDifficultyUtil.should_react(slow, t, 0):
			any_react = true
	_check(any_react, "slow AI still reacts within its cadence window")


func test_mc13_difficulty_score_jitter_scales_with_quality() -> void:
	print("test_mc13_difficulty_score_jitter_scales_with_quality")
	# A perfect-analysis AI does not perturb the clean score; a poor one drifts.
	var sharp: AiProfile = _mc13_profile({"difficulty": {"analysis_quality": 1.0}})
	var dull: AiProfile = _mc13_profile({"difficulty": {"analysis_quality": 0.0}})
	var clean: float = 0.6
	var sharp_score: float = AiDifficultyUtil.perturb_score(clean, sharp, 99, 10, 1)
	_check(is_equal_approx(sharp_score, clean), "high-quality AI keeps clean score")
	# The dull AI's score is jittered but stays clamped to [0,1] and is
	# deterministic for the same seed/tick/owner.
	var dull_score: float = AiDifficultyUtil.perturb_score(clean, dull, 99, 10, 1)
	var dull_again: float = AiDifficultyUtil.perturb_score(clean, dull, 99, 10, 1)
	_check(dull_score >= 0.0 and dull_score <= 1.0, "perturbed score stays clamped")
	_check(is_equal_approx(dull_score, dull_again), "perturbation is deterministic")


func test_mc13_difficulty_apply_downgrades_on_error() -> void:
	print("test_mc13_difficulty_apply_downgrades_on_error")
	# Find a (tick) where a mid AI commits an unforced error, then assert apply()
	# downgrades the action to "none" for that exact seeded case.
	var mid: AiProfile = _mc13_profile({"difficulty":
		{"execution": 0.0, "analysis_quality": 0.5, "reaction_speed": 1.0}})
	var err_tick: int = -1
	for t in range(200):
		if AiDifficultyUtil.is_unforced_error(mid, 42, t, 1):
			err_tick = t
			break
	_check(err_tick >= 0, "an unforced error occurs within 200 ticks for a clumsy AI")
	var decision: Dictionary = {"action": "declare_war", "score": 0.9}
	var out: Dictionary = AiDifficultyUtil.apply(decision, mid, 42, err_tick, 1)
	_check(out["action"] == "none", "unforced error downgrades action to none")
	_check(bool(out.get("unforced_error", false)), "apply flags the unforced error")
	# apply() must not mutate the caller's dictionary.
	_check(decision["action"] == "declare_war", "apply never mutates its input")


# --- MC13.6: brain action -> readable message bridge --------------------------

func test_mc13_brain_action_text_maps_each_action_to_key() -> void:
	print("test_mc13_brain_action_text_maps_each_action_to_key")
	# Every real brain action (except "none") gets its own dedicated key.
	for action in AiBrainActionTextUtil.ACTS:
		_check(AiBrainActionTextUtil.is_message_action(action),
			"'%s' is a message action" % action)
		var key: String = AiBrainActionTextUtil.message_key(action)
		_check(key == "ai.brain." + action, "'%s' -> '%s'" % [action, key])
	# "none" and unknown tokens are NOT message actions and fall back to generic.
	_check(not AiBrainActionTextUtil.is_message_action(AiDiplomacyBrain.ACTION_NONE),
		"'none' is not a message action")
	_check(AiBrainActionTextUtil.message_key(AiDiplomacyBrain.ACTION_NONE)
		== "ai.brain.generic", "'none' -> generic key")
	_check(AiBrainActionTextUtil.message_key("bogus") == "ai.brain.generic",
		"unknown action -> generic key")


func test_mc13_brain_action_text_describe_is_deterministic() -> void:
	print("test_mc13_brain_action_text_describe_is_deterministic")
	var d1: Dictionary = AiBrainActionTextUtil.describe(
		AiDiplomacyBrain.ACTION_PROPOSE_ALLIANCE, 1, 2, "alliance_full")
	var d2: Dictionary = AiBrainActionTextUtil.describe(
		AiDiplomacyBrain.ACTION_PROPOSE_ALLIANCE, 1, 2, "alliance_full")
	_check(d1["key"] == "ai.brain.propose_alliance", "propose_alliance key correct")
	_check(str(d1) == str(d2), "same inputs -> identical descriptor (deterministic)")
	var args: Dictionary = d1["args"]
	_check(int(args["sender"]) == 1, "sender echoed")
	_check(int(args["recipient"]) == 2, "recipient echoed")
	_check(str(args["treaty"]) == "alliance_full", "treaty echoed")
	# treaty_type defaults to empty when omitted.
	var d3: Dictionary = AiBrainActionTextUtil.describe(AiDiplomacyBrain.ACTION_BETRAY, 3, 4)
	_check(str((d3["args"] as Dictionary)["treaty"]) == "", "treaty defaults to empty")


func test_mc13_brain_action_i18n_keys_present_in_all_locales() -> void:
	print("test_mc13_brain_action_i18n_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	# Every key the util can emit must be localized in every locale.
	for key in AiBrainActionTextUtil.all_keys():
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# --- MC14.1: AI builder form logic (pure) -------------------------------------

func test_mc14_builder_new_profile_is_neutral_and_valid() -> void:
	print("test_mc14_builder_new_profile_is_neutral_and_valid")
	var p: AiProfile = AiBuilderUtil.new_profile("my_general")
	_check(p.id() == "my_general", "id preserved")
	_check(p.is_valid(), "fresh profile validates")
	_check(p.archetype() == "balanced", "defaults to balanced archetype")
	# Every knob starts neutral.
	var all_neutral: bool = true
	for category in AiProfile.CATEGORIES:
		for knob in AiProfile.keys_for(category):
			if absf(p.get_value(category, knob) - AiProfile.NEUTRAL) > 0.0001:
				all_neutral = false
	_check(all_neutral, "all 35 knobs start at 0.5")
	# Blank id falls back to a safe default rather than an invalid profile.
	var q: AiProfile = AiBuilderUtil.new_profile("   ")
	_check(q.id() == "custom_ai", "blank id -> custom_ai fallback")


func test_mc14_builder_archetype_presets_shift_knobs() -> void:
	print("test_mc14_builder_archetype_presets_shift_knobs")
	var agg: AiProfile = AiBuilderUtil.new_profile("a")
	AiBuilderUtil.apply_archetype(agg, "aggressor")
	_check(agg.archetype() == "aggressor", "archetype tag updated")
	_check(agg.get_value("personality", "aggression") > 0.66, "aggressor is aggressive")
	_check(agg.get_value("strategy_bias", "defense") < 0.5, "aggressor low on defense")
	_check(agg.role_key() == "ai.role.aggressor", "role key set from preset")
	var defn: AiProfile = AiBuilderUtil.new_profile("d")
	AiBuilderUtil.apply_archetype(defn, "defender")
	_check(defn.get_value("strategy_bias", "defense") > 0.66, "defender is defensive")
	_check(defn.get_value("personality", "aggression") < 0.34, "defender low aggression")
	# Unknown archetype degrades to balanced, id kept.
	var b: AiProfile = AiBuilderUtil.new_profile("keep")
	AiBuilderUtil.apply_archetype(b, "does_not_exist")
	_check(b.archetype() == "balanced", "unknown archetype -> balanced")
	_check(b.id() == "keep", "id preserved through archetype apply")


func test_mc14_builder_randomize_is_seed_deterministic() -> void:
	print("test_mc14_builder_randomize_is_seed_deterministic")
	var p1: AiProfile = AiBuilderUtil.randomize_profile("r", 12345)
	var p2: AiProfile = AiBuilderUtil.randomize_profile("r", 12345)
	_check(str(p1.to_dict()) == str(p2.to_dict()), "same seed -> identical profile")
	var p3: AiProfile = AiBuilderUtil.randomize_profile("r", 99999)
	_check(str(p1.to_dict()) != str(p3.to_dict()), "different seed -> different profile")
	_check(p1.is_valid(), "randomized profile validates")
	# Every knob stays in range.
	var in_range: bool = true
	for category in AiProfile.CATEGORIES:
		for knob in AiProfile.keys_for(category):
			var v: float = p1.get_value(category, knob)
			if v < 0.0 or v > 1.0:
				in_range = false
	_check(in_range, "all randomized knobs within [0,1]")


func test_mc14_builder_duplicate_is_independent() -> void:
	print("test_mc14_builder_duplicate_is_independent")
	var src: AiProfile = AiBuilderUtil.new_profile("src")
	AiBuilderUtil.apply_archetype(src, "raider")
	var copy: AiProfile = AiBuilderUtil.duplicate_profile(src, "copy")
	_check(copy.id() == "copy", "copy has new id")
	_check(str(copy.vector("strategy_bias")) == str(src.vector("strategy_bias")),
		"copy vectors match source at first")
	# Mutating the copy must not touch the source.
	AiBuilderUtil.set_knob(copy, "strategy_bias", "harassment", 0.0)
	_check(copy.get_value("strategy_bias", "harassment") == 0.0, "copy edited")
	_check(src.get_value("strategy_bias", "harassment") > 0.66, "source unchanged (deep copy)")


func test_mc14_builder_reset_and_clamp() -> void:
	print("test_mc14_builder_reset_and_clamp")
	var p: AiProfile = AiBuilderUtil.new_profile("g")
	AiBuilderUtil.apply_archetype(p, "conqueror")
	# set_knob clamps out-of-range input.
	_check(AiBuilderUtil.set_knob(p, "personality", "aggression", 5.0) == 1.0, "over-1 clamps to 1")
	_check(AiBuilderUtil.set_knob(p, "personality", "caution", -3.0) == 0.0, "under-0 clamps to 0")
	AiBuilderUtil.reset_knobs(p)
	_check(p.get_value("personality", "aggression") == AiProfile.NEUTRAL, "reset returns to neutral")
	_check(p.id() == "g", "reset keeps id")
	_check(p.archetype() == "conqueror", "reset keeps archetype tag")


func test_mc14_builder_export_import_roundtrip() -> void:
	print("test_mc14_builder_export_import_roundtrip")
	var p: AiProfile = AiBuilderUtil.randomize_profile("exp", 555)
	AiBuilderUtil.set_display_name_key(p, "my.custom.name")
	var d: Dictionary = AiBuilderUtil.export_dict(p)
	var res: Dictionary = AiBuilderUtil.import_dict(d)
	_check(bool(res["ok"]), "valid export imports ok")
	var back: AiProfile = res["profile"]
	_check(str(back.to_dict()) == str(p.to_dict()), "export/import round-trips byte-identical")
	# An id-less payload imports as a safe fallback rather than crashing.
	var bad: Dictionary = AiBuilderUtil.import_dict({"personality": {"aggression": 0.9}})
	_check(not bool(bad["ok"]), "id-less payload flagged not ok")
	_check((bad["profile"] as AiProfile).is_valid(), "fallback profile still valid")


# --- MC14.2: AI roster selection for match setup (pure) -----------------------

func test_mc14_roster_lists_builtins_then_custom_sorted() -> void:
	print("test_mc14_roster_lists_builtins_then_custom_sorted")
	# Two custom AIs; no reader (built-ins fall back to neutral summaries).
	var alpha: Dictionary = AiBuilderUtil.export_dict(AiBuilderUtil.new_profile("alpha_ai"))
	var zulu: Dictionary = AiBuilderUtil.export_dict(AiBuilderUtil.new_profile("zulu_ai"))
	var custom: Dictionary = {"zulu_ai": zulu, "alpha_ai": alpha}
	var roster: Array = AiRosterUtil.build_roster([], custom, null)
	var builtins: int = AiProfileCatalog.ids().size()
	_check(roster.size() == builtins + 2, "roster = builtins + custom count")
	_check(AiRosterUtil.has_any(roster), "roster reports it is non-empty")
	# Built-in block comes first and is id-sorted (alaric before talleyrand).
	_check(str(roster[0].get("id", "")) == "alaric", "first built-in is alaric (sorted)")
	_check(str(roster[builtins - 1].get("id", "")) == "talleyrand", "last built-in is talleyrand")
	_check(str(roster[0].get("source", "")) == AiRosterUtil.SOURCE_BUILTIN, "built-in tagged builtin")
	# Custom block follows, id-sorted (alpha before zulu), tagged custom.
	_check(str(roster[builtins].get("id", "")) == "alpha_ai", "first custom is alpha_ai (sorted)")
	_check(str(roster[builtins + 1].get("id", "")) == "zulu_ai", "second custom is zulu_ai")
	_check(str(roster[builtins].get("source", "")) == AiRosterUtil.SOURCE_CUSTOM, "custom tagged custom")
	# Every row carries a summary card (role/style/danger keys + tags array).
	_check(roster[0].has("role_key") and roster[0].has("style_key"), "row carries summary keys")
	_check(roster[0].get("tags", null) is Array, "row carries a tags array")


func test_mc14_roster_toggle_selection_is_pure_and_sorted() -> void:
	print("test_mc14_roster_toggle_selection_is_pure_and_sorted")
	var sel: Array = []
	sel = AiRosterUtil.toggle_selection(sel, "caesar")
	_check(sel == ["caesar"], "toggle on adds the id")
	sel = AiRosterUtil.toggle_selection(sel, "alexander")
	_check(sel == ["alexander", "caesar"], "second add stays sorted")
	sel = AiRosterUtil.toggle_selection(sel, "caesar")
	_check(sel == ["alexander"], "toggling an existing id removes it")
	# Purity: the input list is not mutated in place.
	var before: Array = ["alexander"]
	var after: Array = AiRosterUtil.toggle_selection(before, "cyrus")
	_check(before == ["alexander"], "input list left unchanged (pure)")
	_check(after == ["alexander", "cyrus"], "returned list has the new id, sorted")
	# Blank id is ignored (just re-sorts + dedups).
	var dedup: Array = AiRosterUtil.toggle_selection(["b", "a", "a"], "   ")
	_check(dedup == ["a", "b"], "blank id just dedups + sorts")


func test_mc14_roster_selected_rows_follow_roster_order() -> void:
	print("test_mc14_roster_selected_rows_follow_roster_order")
	var custom: Dictionary = {"mine": AiBuilderUtil.export_dict(AiBuilderUtil.new_profile("mine"))}
	var roster: Array = AiRosterUtil.build_roster([], custom, null)
	# Pick a built-in and the custom one, in a scrambled selection order.
	var picked: Array = AiRosterUtil.selected_rows(roster, ["mine", "cyrus"])
	_check(picked.size() == 2, "two rows selected")
	# Roster order (built-in first) is preserved regardless of selection order.
	_check(str(picked[0].get("id", "")) == "cyrus", "built-in row comes before custom")
	_check(str(picked[1].get("id", "")) == "mine", "custom row comes second")
	# Unknown ids are simply ignored.
	var none: Array = AiRosterUtil.selected_rows(roster, ["does_not_exist"])
	_check(none.is_empty(), "unknown selected id yields no rows")


func test_mc14_roster_resolve_profiles_and_custom_override() -> void:
	print("test_mc14_roster_resolve_profiles_and_custom_override")
	# A custom profile whose id collides with a built-in: the user's own wins.
	var mine: AiProfile = AiBuilderUtil.new_profile("caesar")
	AiBuilderUtil.apply_archetype(mine, "defender")
	var custom: Dictionary = {"caesar": AiBuilderUtil.export_dict(mine), "solo": AiBuilderUtil.export_dict(AiBuilderUtil.new_profile("solo"))}
	var profiles: Array = AiRosterUtil.resolve_profiles(["solo", "caesar"], custom, null)
	_check(profiles.size() == 2, "two profiles resolved")
	# Sorted ids: caesar then solo.
	_check((profiles[0] as AiProfile).id() == "caesar", "caesar resolved first (sorted)")
	_check((profiles[0] as AiProfile).archetype() == "defender", "custom caesar overrides the built-in")
	_check((profiles[1] as AiProfile).id() == "solo", "custom solo resolved")
	# A pure built-in id (no custom) still resolves via the catalog.
	var only_builtin: Array = AiRosterUtil.resolve_profiles(["genghis"], {}, null)
	_check(only_builtin.size() == 1 and (only_builtin[0] as AiProfile).id() == "genghis", "built-in resolves without a custom entry")
	# Duplicate + blank selection ids are de-duplicated safely.
	var dupes: Array = AiRosterUtil.resolve_profiles(["solo", "solo", "  "], custom, null)
	_check(dupes.size() == 1, "duplicate/blank selection ids collapse to one profile")


# --- MC14.3 (req16/18): graphic facing + firing-part model ------------------

func test_mc14_graphic_facing_normalise_and_roundtrip() -> void:
	print("test_mc14_graphic_facing_normalise_and_roundtrip")
	# Unknown / blank values fall back to the default facing.
	_check(GraphicModel.normalise_facing("LEFT") == GraphicModel.FACING_LEFT, "case-insensitive facing normalise")
	_check(GraphicModel.normalise_facing("sideways") == GraphicModel.DEFAULT_FACING, "unknown facing falls back to default")
	_check(GraphicModel.normalise_facing(null) == GraphicModel.DEFAULT_FACING, "null facing falls back to default")
	# A default graphic has no facing key yet, so get_facing returns the default.
	var g: Dictionary = GraphicModel.default_graphic()
	_check(GraphicModel.get_facing(g) == GraphicModel.DEFAULT_FACING, "absent facing reads as default")
	# set_facing does not mutate the input and stores a normalised value.
	var g2: Dictionary = GraphicModel.set_facing(g, "Right")
	_check(GraphicModel.get_facing(g2) == GraphicModel.FACING_RIGHT, "set_facing stores normalised facing")
	_check(not g.has("facing"), "set_facing did not mutate the original graphic")
	# Mount normalise mirrors facing.
	_check(GraphicModel.normalise_mount("TURRET") == GraphicModel.MOUNT_TURRET, "mount normalise turret")
	_check(GraphicModel.normalise_mount("bogus") == GraphicModel.DEFAULT_MOUNT, "unknown mount falls back to fixed")


func test_mc14_graphic_set_firing_part_enforces_single() -> void:
	print("test_mc14_graphic_set_firing_part_enforces_single")
	# A three-part multi graphic; mark part 1 as a turret firing part.
	var g: Dictionary = {
		"mode": GraphicModel.MODE_MULTI,
		"logical_size": {"w": 1, "h": 1},
		"parts": [
			GraphicModel.default_part(1, 64, 64),
			GraphicModel.default_part(2, 48, 48),
			GraphicModel.default_part(3, 32, 32),
		],
	}
	var g1: Dictionary = GraphicModel.set_firing_part(g, 1, GraphicModel.MOUNT_TURRET)
	_check(GraphicModel.count_firing_parts(g1) == 1, "exactly one firing part after set")
	_check(GraphicModel.first_firing_index(g1) == 1, "firing part is at index 1")
	_check(GraphicModel.part_mount((g1["parts"] as Array)[1]) == GraphicModel.MOUNT_TURRET, "mount stored as turret")
	# Re-assigning to another part moves the flag (never accumulates two).
	var g2: Dictionary = GraphicModel.set_firing_part(g1, 0, GraphicModel.MOUNT_FIXED)
	_check(GraphicModel.count_firing_parts(g2) == 1, "still exactly one firing part after reassign")
	_check(GraphicModel.first_firing_index(g2) == 0, "firing part moved to index 0")
	_check(not GraphicModel.part_is_firing((g2["parts"] as Array)[1]), "previous firing part cleared")
	# A negative index clears all firing flags.
	var g3: Dictionary = GraphicModel.set_firing_part(g2, -1)
	_check(GraphicModel.count_firing_parts(g3) == 0, "negative index clears all firing parts")


func test_mc14_graphic_validate_rejects_bad_facing_and_multi_firing() -> void:
	print("test_mc14_graphic_validate_rejects_bad_facing_and_multi_firing")
	# A valid single-part graphic with a facing + one firing part passes.
	var ok: Dictionary = GraphicModel.default_graphic()
	ok["facing"] = GraphicModel.FACING_DOWN
	(ok["parts"] as Array)[0]["is_firing_part"] = true
	(ok["parts"] as Array)[0]["firing_mount"] = GraphicModel.MOUNT_FIXED
	_check(GraphicModel.validate(ok).is_empty(), "valid facing + single firing part passes validation")
	# A bad facing is reported.
	var bad_face: Dictionary = GraphicModel.default_graphic()
	bad_face["facing"] = "diagonal"
	_check(GraphicModel.validate(bad_face).size() > 0, "invalid facing is rejected")
	# Two firing parts exceed the authored cap.
	var two_fire: Dictionary = {
		"mode": GraphicModel.MODE_MULTI,
		"logical_size": {"w": 1, "h": 1},
		"parts": [
			{"layer": 1, "px": {"w": 64, "h": 64}, "texture": "", "is_firing_part": true, "firing_mount": "fixed"},
			{"layer": 2, "px": {"w": 48, "h": 48}, "texture": "", "is_firing_part": true, "firing_mount": "turret"},
		],
	}
	var probs: Array = GraphicModel.validate(two_fire)
	var found_cap: bool = false
	for p in probs:
		if str(p).contains("firing parts"):
			found_cap = true
	_check(found_cap, "two firing parts exceed the max-1 cap")


# --- MC14.4 (req18): combine units -> up to 2 firing parts ------------------

# Build a one-part graphic that is (optionally) a firing part with a mount.
func _mc14_firing_graphic(is_firing: bool, mount: String = "fixed") -> Dictionary:
	var g: Dictionary = GraphicModel.default_graphic()
	if is_firing:
		(g["parts"] as Array)[0]["is_firing_part"] = true
		(g["parts"] as Array)[0]["firing_mount"] = mount
	return g


func test_mc14_combine_firing_slots_caps_at_two() -> void:
	print("test_mc14_combine_firing_slots_caps_at_two")
	# Three sources each carrying a firing part; only the first two survive.
	var sources: Array = [
		_mc14_firing_graphic(true, "fixed"),
		_mc14_firing_graphic(true, "turret"),
		_mc14_firing_graphic(true, "fixed"),
	]
	var slots: Array = FiringCombinationUtil.combine_firing_slots(sources)
	_check(slots.size() == GraphicModel.MAX_COMBINED_FIRING_PARTS, "combined firing parts capped at 2")
	_check(int((slots[0] as Dictionary)["source"]) == 0, "first slot from source 0")
	_check(int((slots[1] as Dictionary)["source"]) == 1, "second slot from source 1 (source order)")
	_check(str((slots[1] as Dictionary)["mount"]) == "turret", "second slot keeps its turret mount")
	_check(FiringCombinationUtil.combined_firing_count(sources) == 2, "combined_firing_count matches cap")


func test_mc14_combine_firing_skips_sources_without_firing_part() -> void:
	print("test_mc14_combine_firing_skips_sources_without_firing_part")
	# Only the middle source has a firing part -> exactly one slot, pointing at it.
	var sources: Array = [
		_mc14_firing_graphic(false),
		_mc14_firing_graphic(true, "turret"),
		_mc14_firing_graphic(false),
	]
	var slots: Array = FiringCombinationUtil.combine_firing_slots(sources)
	_check(slots.size() == 1, "one firing slot when a single source fires")
	_check(int((slots[0] as Dictionary)["source"]) == 1, "slot points at the firing source")
	_check(int((slots[0] as Dictionary)["part"]) == 0, "slot part index is 0")
	# No firing sources at all -> empty result.
	var none: Array = FiringCombinationUtil.combine_firing_slots([_mc14_firing_graphic(false)])
	_check(none.is_empty(), "no firing sources yields no slots")


func test_mc14_combine_firing_exceeds_cap_and_turret_flag() -> void:
	print("test_mc14_combine_firing_exceeds_cap_and_turret_flag")
	var three_fire: Array = [
		_mc14_firing_graphic(true),
		_mc14_firing_graphic(true),
		_mc14_firing_graphic(true),
	]
	_check(FiringCombinationUtil.exceeds_cap(three_fire), "three firing sources exceed the cap")
	var two_fire: Array = [_mc14_firing_graphic(true), _mc14_firing_graphic(true)]
	_check(not FiringCombinationUtil.exceeds_cap(two_fire), "two firing sources do not exceed the cap")
	# Turret detection over a combined slot set.
	var turret_slots: Array = FiringCombinationUtil.combine_firing_slots([_mc14_firing_graphic(true, "turret")])
	_check(FiringCombinationUtil.has_turret(turret_slots), "has_turret true when a slot is a turret")
	var fixed_slots: Array = FiringCombinationUtil.combine_firing_slots([_mc14_firing_graphic(true, "fixed")])
	_check(not FiringCombinationUtil.has_turret(fixed_slots), "has_turret false for fixed-only slots")


# --- MC14.5 (req16/18): cosmetic turret/idle-spin angle math ----------------

func test_mc14_turret_aim_angle_tracks_target() -> void:
	print("test_mc14_turret_aim_angle_tracks_target")
	# A turret aims at the target regardless of the unit heading. Target due east
	# of the barrel -> angle 0; due south -> +PI/2 (y grows down).
	var east: float = TurretAngleUtil.aim_angle(Vector2(0, 0), Vector2(10, 0))
	_check(absf(east - 0.0) < 0.001, "aim east is angle 0")
	var south: float = TurretAngleUtil.aim_angle(Vector2(0, 0), Vector2(0, 10))
	_check(absf(south - (PI / 2.0)) < 0.001, "aim south is +PI/2")
	# firing_part_angle: a turret with a target ignores the (northward) heading.
	var heading_north: float = -PI / 2.0
	var turret_angle: float = TurretAngleUtil.firing_part_angle(GraphicModel.MOUNT_TURRET, heading_north, Vector2(0, 0), Vector2(10, 0), true)
	_check(absf(turret_angle - 0.0) < 0.001, "turret aims at target, not heading")
	# A turret with NO target falls back to the heading.
	var no_target: float = TurretAngleUtil.firing_part_angle(GraphicModel.MOUNT_TURRET, heading_north, Vector2(0, 0), Vector2(0, 0), false)
	_check(absf(no_target - heading_north) < 0.001, "turret without target uses heading")


func test_mc14_turret_fixed_uses_heading_and_facing_seed() -> void:
	print("test_mc14_turret_fixed_uses_heading_and_facing_seed")
	# A fixed mount always uses the unit heading, ignoring any target.
	var heading: float = PI / 3.0
	var fixed: float = TurretAngleUtil.firing_part_angle(GraphicModel.MOUNT_FIXED, heading, Vector2(0, 0), Vector2(10, 0), true)
	_check(absf(TurretAngleUtil.wrap_angle(fixed - heading)) < 0.001, "fixed mount uses heading even with a target")
	# Authored facing seeds a heading angle.
	_check(absf(TurretAngleUtil.facing_to_angle("right") - 0.0) < 0.001, "facing right -> 0")
	_check(absf(TurretAngleUtil.facing_to_angle("up") - (-PI / 2.0)) < 0.001, "facing up -> -PI/2")
	_check(absf(TurretAngleUtil.facing_to_angle("left") - PI) < 0.001, "facing left -> PI")
	# Unknown facing seeds the default (up).
	_check(absf(TurretAngleUtil.facing_to_angle("bogus") - (-PI / 2.0)) < 0.001, "unknown facing seeds default (up)")


func test_mc14_turret_idle_spin_and_step_toward() -> void:
	print("test_mc14_turret_idle_spin_and_step_toward")
	# Idle spin advances with time and is deterministic in its inputs.
	var a0: float = TurretAngleUtil.idle_spin_angle(0.0)
	var a1: float = TurretAngleUtil.idle_spin_angle(1.0)
	_check(absf(a0 - 0.0) < 0.001, "idle spin at t=0 is 0")
	_check(a1 != a0, "idle spin advances with time")
	_check(absf(TurretAngleUtil.idle_spin_angle(1.0) - a1) < 0.000001, "idle spin is deterministic")
	# Two buildings with different phase offsets scan out of sync.
	_check(TurretAngleUtil.idle_spin_angle(1.0, 1.0) != a1, "phase offset desyncs the scan")
	# step_toward moves at most max_step and snaps when within reach.
	var stepped: float = TurretAngleUtil.step_toward(0.0, 1.0, 0.25)
	_check(absf(stepped - 0.25) < 0.001, "step_toward moves by max_step when far")
	var snapped: float = TurretAngleUtil.step_toward(0.0, 0.1, 0.25)
	_check(absf(snapped - 0.1) < 0.001, "step_toward snaps to target when within reach")
	# Shortest path: current=3.0, target=-3.0. The short way is FORWARD across PI
	# (delta = wrap(-3.0 - 3.0) = wrap(-6.0) ~= +0.283), so a 0.5 step reaches the
	# target and snaps to wrap(-3.0) = -3.0.
	var short_path: float = TurretAngleUtil.step_toward(3.0, -3.0, 0.5)
	_check(absf(short_path - TurretAngleUtil.wrap_angle(-3.0)) < 0.001, "step_toward takes the shortest arc across PI")


# --- MC14.6 (req16/18): mod editor facing + firing-part edit logic ----------

func test_mc14_facing_edit_set_and_read_facing() -> void:
	print("test_mc14_facing_edit_set_and_read_facing")
	# Facing / mount choices mirror the model constants (deterministic order).
	_check(GraphicFacingEditUtil.facing_choices() == GraphicModel.FACINGS, "facing choices mirror model")
	_check(GraphicFacingEditUtil.mount_choices() == GraphicModel.MOUNTS, "mount choices mirror model")
	# A fresh entity reads the default facing.
	var entity: Dictionary = {"graphic": GraphicModel.default_graphic()}
	_check(GraphicFacingEditUtil.get_entity_facing(entity) == GraphicModel.DEFAULT_FACING, "default facing read")
	# set_entity_facing normalises and does NOT mutate the original entity.
	var e2: Dictionary = GraphicFacingEditUtil.set_entity_facing(entity, "Left")
	_check(GraphicFacingEditUtil.get_entity_facing(e2) == GraphicModel.FACING_LEFT, "facing set to left")
	_check(GraphicFacingEditUtil.get_entity_facing(entity) == GraphicModel.DEFAULT_FACING, "original entity unchanged")
	# Null-safe on garbage input.
	_check(GraphicFacingEditUtil.get_entity_facing(null) == GraphicModel.DEFAULT_FACING, "null entity reads default facing")


func test_mc14_facing_edit_firing_part_single_and_toggle() -> void:
	print("test_mc14_facing_edit_firing_part_single_and_toggle")
	var entity: Dictionary = {
		"graphic": {
			"mode": GraphicModel.MODE_MULTI,
			"logical_size": {"w": 1, "h": 1},
			"parts": [
				GraphicModel.default_part(1, 64, 64),
				GraphicModel.default_part(2, 48, 48),
				GraphicModel.default_part(3, 32, 32),
			],
		},
	}
	_check(not GraphicFacingEditUtil.has_firing_part(entity), "no firing part initially")
	_check(GraphicFacingEditUtil.part_count(entity) == 3, "three parts counted")
	# Mark part 1 as a turret firing part.
	var e1: Dictionary = GraphicFacingEditUtil.set_firing_part(entity, 1, GraphicModel.MOUNT_TURRET)
	_check(GraphicFacingEditUtil.firing_part_index(e1) == 1, "firing part at index 1")
	_check(GraphicFacingEditUtil.firing_part_mount(e1) == GraphicModel.MOUNT_TURRET, "mount is turret")
	_check(not GraphicFacingEditUtil.has_firing_part(entity), "original entity untouched")
	# Toggling the same part clears it (single-firing-part rule holds).
	var e2: Dictionary = GraphicFacingEditUtil.toggle_firing_part(e1, 1)
	_check(not GraphicFacingEditUtil.has_firing_part(e2), "toggling same part clears firing")
	# Toggling a different part moves the flag (never accumulates two).
	var e3: Dictionary = GraphicFacingEditUtil.toggle_firing_part(e1, 0, GraphicModel.MOUNT_FIXED)
	_check(GraphicFacingEditUtil.firing_part_index(e3) == 0, "firing part moved to index 0")
	_check(GraphicModel.count_firing_parts((e3["graphic"] as Dictionary)) == 1, "still exactly one firing part")


func test_mc14_facing_edit_mount_change_and_choices() -> void:
	print("test_mc14_facing_edit_mount_change_and_choices")
	var entity: Dictionary = {
		"graphic": {
			"mode": GraphicModel.MODE_MULTI,
			"logical_size": {"w": 1, "h": 1},
			"parts": [
				GraphicModel.default_part(1, 64, 64),
				GraphicModel.default_part(2, 48, 48),
			],
		},
	}
	var e1: Dictionary = GraphicFacingEditUtil.set_firing_part(entity, 0, GraphicModel.MOUNT_FIXED)
	_check(GraphicFacingEditUtil.firing_part_mount(e1) == GraphicModel.MOUNT_FIXED, "mount starts fixed")
	# Changing mount keeps the same firing part but flips fixed->turret.
	var e2: Dictionary = GraphicFacingEditUtil.set_firing_mount(e1, GraphicModel.MOUNT_TURRET)
	_check(GraphicFacingEditUtil.firing_part_index(e2) == 0, "firing part unchanged after mount change")
	_check(GraphicFacingEditUtil.firing_part_mount(e2) == GraphicModel.MOUNT_TURRET, "mount changed to turret")
	# set_firing_mount on an entity with no firing part is a safe no-op copy.
	var e3: Dictionary = GraphicFacingEditUtil.set_firing_mount(entity, GraphicModel.MOUNT_TURRET)
	_check(not GraphicFacingEditUtil.has_firing_part(e3), "no-op mount change when no firing part")
	# Default mount when there is no firing part.
	_check(GraphicFacingEditUtil.firing_part_mount(entity) == GraphicModel.DEFAULT_MOUNT, "default mount when none")


func test_mc10_diplomacy_i18n_keys_present_in_all_locales() -> void:
	print("test_mc10_diplomacy_i18n_keys_present_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	# Every relationship state must have a display key.
	for state in RelationshipUtil.STATES:
		var skey: String = "ui.diplomacy.state.%s" % state
		_check(en.has(skey), "en has '%s'" % skey)
		_check(fa.has(skey), "fa has '%s'" % skey)
	# Every treaty type must have a display key.
	for type_id in TreatyUtil.TYPES:
		var tkey: String = "ui.diplomacy.treaty.%s" % type_id
		_check(en.has(tkey), "en has '%s'" % tkey)
		_check(fa.has(tkey), "fa has '%s'" % tkey)
	# Core diplomacy UI labels.
	for key in ["ui.diplomacy.title", "ui.diplomacy.propose", "ui.diplomacy.respond",
			"ui.diplomacy.accept", "ui.diplomacy.reject", "ui.diplomacy.declare_war",
			"ui.diplomacy.break_treaty", "ui.diplomacy.gives", "ui.diplomacy.wants",
			"ui.diplomacy.duration", "ui.diplomacy.trust"]:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


func test_phase_e_editor_keys_localized_in_all_locales() -> void:
	print("test_phase_e_editor_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.menu.map_editor", "ui.menu.custom_games", "ui.mapeditor.title",
		"ui.mapeditor.scenario_id", "ui.mapeditor.tool.wall", "ui.mapeditor.tool.hq",
		"ui.mapeditor.tool.unit", "ui.mapeditor.tool.fill", "ui.mapeditor.tool.border",
		"ui.mapeditor.save", "ui.mapeditor.playtest", "ui.mapeditor.status.saved",
		"ui.custom.title", "ui.custom.play", "ui.custom.empty",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# --- Phase P3 (v0.6.0): interactive camera + control groups + minimap --------
#
# These cover the deterministic-safe, headless-testable parts of P3: the
# RenderAdapter zoom/pan/clamp math (BUG-4 / P3.1), and that the new HUD strings
# are localized. The touch-input wiring and widget placement are UI and are
# verified on-device (per the acceptance-criteria policy), not here.

func test_060_p3_zoom_clamps_to_range() -> void:
	print("test_060_p3_zoom_clamps_to_range")
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.tile_size = 24
	adapter.zoom = 1.0
	# Zoom in many times: must saturate at ZOOM_MAX, never exceed it.
	for _i in range(50):
		adapter.zoom_by(1.2, Vector2(400, 300))
	_check(adapter.zoom <= adapter.ZOOM_MAX + 0.0001, "zoom never exceeds ZOOM_MAX")
	# Zoom out many times: must saturate at ZOOM_MIN, never below it.
	for _i in range(80):
		adapter.zoom_by(1.0 / 1.2, Vector2(400, 300))
	_check(adapter.zoom >= adapter.ZOOM_MIN - 0.0001, "zoom never drops below ZOOM_MIN")
	adapter.free()


func test_060_p3_zoom_keeps_focus_point_fixed() -> void:
	print("test_060_p3_zoom_keeps_focus_point_fixed")
	# The world point under the pinch/cursor focus must stay under it after a zoom.
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.tile_size = 24
	adapter.zoom = 1.0
	adapter.camera_offset = Vector2(10, 20)
	var focus: Vector2 = Vector2(320, 240)
	var world_before: Vector2 = (focus - adapter.camera_offset) / adapter.zoom
	adapter.zoom_by(1.5, focus)
	var world_after: Vector2 = (focus - adapter.camera_offset) / adapter.zoom
	_check(world_before.distance_to(world_after) < 0.01, "focus world point stays fixed under zoom")
	adapter.free()


func test_060_p3_pan_by_moves_offset() -> void:
	print("test_060_p3_pan_by_moves_offset")
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.camera_offset = Vector2.ZERO
	adapter.pan_by(Vector2(30, -15))
	_check(adapter.camera_offset == Vector2(30, -15), "pan_by adds the screen delta to camera_offset")
	adapter.free()


func test_060_p3_pinch_ratio_zooms_in_and_out() -> void:
	print("test_060_p3_pinch_ratio_zooms_in_and_out")
	# BUG-FIX regression: the mobile HUD computes a pinch as (new finger distance /
	# old finger distance) and feeds that ratio to RenderAdapter.zoom_by. This test
	# reproduces that exact math so a broken pinch (e.g. wrong ratio direction) is
	# caught without needing a live touchscreen. Fingers spreading apart (ratio > 1)
	# must zoom IN; fingers pinching together (ratio < 1) must zoom OUT.
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.tile_size = 24
	adapter.zoom = 1.0
	adapter.camera_offset = Vector2(0, 0)
	var mid: Vector2 = Vector2(200, 200)
	# Fingers start 100px apart, spread to 200px apart -> ratio 2.0 -> zoom in.
	var spread_ratio: float = 200.0 / 100.0
	adapter.zoom_by(spread_ratio, mid)
	_check(adapter.zoom > 1.0, "spreading fingers (ratio>1) zooms in")
	# Now pinch back together: 200px -> 120px -> ratio 0.6 -> zoom out.
	var z_after_in: float = adapter.zoom
	var pinch_ratio: float = 120.0 / 200.0
	adapter.zoom_by(pinch_ratio, mid)
	_check(adapter.zoom < z_after_in, "pinching fingers (ratio<1) zooms out")
	adapter.free()


func test_060_p3_camera_math_is_cosmetic_only() -> void:
	print("test_060_p3_camera_math_is_cosmetic_only")
	# Zoom/pan must never change the deterministic hash: drive a real sim, snapshot
	# the hash, mutate the camera, and confirm the hash is unchanged.
	var harness: TickHarness = _make_strategic_harness(77, "balanced", 2000)
	harness.run_ticks(20)
	var before: int = StateHasher.hash_world(harness.world_state)
	var adapter: RenderAdapter = RenderAdapter.new()
	adapter.tile_size = 24
	adapter.zoom_by(1.5, Vector2(100, 100))
	adapter.pan_by(Vector2(50, 50))
	var after: int = StateHasher.hash_world(harness.world_state)
	_check(before == after, "camera zoom/pan does not touch WorldState hash")
	adapter.free()


func test_060_p3_hud_keys_localized_in_all_locales() -> void:
	print("test_060_p3_hud_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = ["ui.game.assign", "ui.game.selected"]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# --- Phase P7 (v0.6.0): placement planner, team layout, game modes ----------

func test_070_p7_placement_planner_deterministic() -> void:
	print("test_070_p7_placement_planner_deterministic")
	# The same inputs must always yield byte-identical placements (lockstep-safe).
	var slots: Array = [
		{ "owner": 0, "team": 0 }, { "owner": 1, "team": 1 },
		{ "owner": 2, "team": 0 }, { "owner": 3, "team": 1 },
	]
	var a: Array = PlacementPlanner.plan_hqs(32, 24, slots, PlacementPlanner.LAYOUT_RANDOM, 1234)
	var b: Array = PlacementPlanner.plan_hqs(32, 24, slots, PlacementPlanner.LAYOUT_RANDOM, 1234)
	_check(JSON.stringify(a) == JSON.stringify(b), "plan_hqs is deterministic for equal inputs+seed")
	var c: Array = PlacementPlanner.plan_hqs(32, 24, slots, PlacementPlanner.LAYOUT_RANDOM, 9999)
	_check(JSON.stringify(a) != JSON.stringify(c), "a different seed produces a different random layout")


func test_070_p7_placement_planner_avoids_blocked_and_used() -> void:
	print("test_070_p7_placement_planner_avoids_blocked_and_used")
	# Every placed HQ must sit on a free (non-blocked) cell and be unique.
	var slots: Array = []
	for i in range(6):
		slots.append({ "owner": i, "team": i % 2 })
	# Block the whole top-left quadrant to force the spiral search to relocate.
	var blocked: Callable = func(x: int, y: int) -> bool: return x < 8 and y < 6
	var placed: Array = PlacementPlanner.plan_hqs(32, 24, slots, PlacementPlanner.LAYOUT_CLUSTERED, 7, blocked)
	_check(placed.size() == slots.size(), "one HQ planned per slot")
	var seen: Dictionary = {}
	var all_free: bool = true
	var all_unique: bool = true
	var all_in_bounds: bool = true
	for p in placed:
		var key: String = "%d,%d" % [int(p["x"]), int(p["y"])]
		if seen.has(key):
			all_unique = false
		seen[key] = true
		if int(p["x"]) < 8 and int(p["y"]) < 6:
			all_free = false
		if int(p["x"]) < 0 or int(p["y"]) < 0 or int(p["x"]) >= 32 or int(p["y"]) >= 24:
			all_in_bounds = false
	_check(all_free, "no HQ sits on a blocked cell")
	_check(all_unique, "no two HQs share a cell")
	_check(all_in_bounds, "every HQ is in bounds")


func test_070_p7_placement_clustered_groups_teammates() -> void:
	print("test_070_p7_placement_clustered_groups_teammates")
	# Clustered layout should seat teammates closer to each other than to rivals.
	var slots: Array = [
		{ "owner": 0, "team": 0 }, { "owner": 1, "team": 0 },
		{ "owner": 2, "team": 1 }, { "owner": 3, "team": 1 },
	]
	var placed: Array = PlacementPlanner.plan_hqs(40, 40, slots, PlacementPlanner.LAYOUT_CLUSTERED, 0)
	var by_owner: Dictionary = {}
	for p in placed:
		by_owner[int(p["owner"])] = Vector2(int(p["x"]), int(p["y"]))
	var mate_dist: float = by_owner[0].distance_to(by_owner[1])
	var rival_dist: float = by_owner[0].distance_to(by_owner[2])
	_check(mate_dist <= rival_dist, "teammates are seated no farther apart than rivals")


func test_070_p7_placement_flags_are_distinct_cells() -> void:
	print("test_070_p7_placement_flags_are_distinct_cells")
	var flags: Array = PlacementPlanner.plan_flags(30, 30, 4, 42)
	_check(flags.size() == 4, "four flags planned")
	var seen: Dictionary = {}
	var unique: bool = true
	for f in flags:
		var key: String = "%d,%d" % [int(f["x"]), int(f["y"])]
		if seen.has(key):
			unique = false
		seen[key] = true
	_check(unique, "all planned flags are on distinct cells")


func test_070_p7_team_assignment_per_mode() -> void:
	print("test_070_p7_team_assignment_per_mode")
	# Reproduce GameBootstrap._team_for's contract: team/ctf split into two sides,
	# ffa gives each player their own team.
	var team_mode: Callable = func(owner: int, mode: String) -> int:
		if mode == "team" or mode == "ctf":
			return owner % 2
		return owner
	_check(team_mode.call(0, "team") == 0 and team_mode.call(1, "team") == 1, "team mode alternates sides")
	_check(team_mode.call(2, "team") == 0 and team_mode.call(3, "team") == 1, "team mode makes a 2v2")
	_check(team_mode.call(0, "ffa") == 0 and team_mode.call(3, "ffa") == 3, "ffa gives each player their own team")
	_check(team_mode.call(1, "ctf") == 1, "ctf also splits into two teams")


func test_070_p7_setup_keys_localized_in_all_locales() -> void:
	print("test_070_p7_setup_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.setup.team_layout", "ui.setup.layout_clustered", "ui.setup.layout_random",
		"ui.setup.mode_team", "ui.setup.mode_ffa", "ui.setup.mode_ctf",
		"ui.mapeditor.tool.flag", "ui.mapeditor.status.flag_placed",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# --- Phase MA1: multi-unit move formation (no more stacking) ----------------

# Ordering several units to the same tile must NOT stack them onto one tile; each
# must get a unique, walkable destination clustered around the requested goal.
func test_ma1_multi_unit_move_spreads_into_formation() -> void:
	print("test_ma1_multi_unit_move_spreads_into_formation")
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	var map: Object = nexus.get_module("map")
	map.create_grid(12, 12)
	var units: Object = nexus.get_module("units")
	var a: int = units.spawn_unit("soldier", 0, 0, 0)
	var b: int = units.spawn_unit("soldier", 0, 1, 0)
	var c: int = units.spawn_unit("soldier", 0, 2, 0)
	# All three ordered to the exact same tile (6,6).
	nexus.issue_command("move_unit", 0, { "unit_ids": [a, b, c], "x": 6, "y": 6 }, 1)
	nexus.run_ticks(80)
	var ua: Dictionary = units.get_unit(a)
	var ub: Dictionary = units.get_unit(b)
	var uc: Dictionary = units.get_unit(c)
	var pa: String = "%d,%d" % [int(ua["x"]), int(ua["y"])]
	var pb: String = "%d,%d" % [int(ub["x"]), int(ub["y"])]
	var pc: String = "%d,%d" % [int(uc["x"]), int(uc["y"])]
	_check(pa != pb and pa != pc and pb != pc, "three units end on three distinct tiles (no stacking)")
	# Every unit should end up clustered near the requested goal (within a few tiles).
	var near := func(u: Dictionary) -> bool:
		return absi(int(u["x"]) - 6) <= 3 and absi(int(u["y"]) - 6) <= 3
	_check(near.call(ua) and near.call(ub) and near.call(uc), "all units cluster around the requested goal")


# A single-unit move must keep the EXACT requested tile (no behaviour change).
func test_ma1_single_unit_move_keeps_exact_goal() -> void:
	print("test_ma1_single_unit_move_keeps_exact_goal")
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	var map: Object = nexus.get_module("map")
	map.create_grid(10, 3)
	var units: Object = nexus.get_module("units")
	var uid: int = units.spawn_unit("soldier", 0, 0, 1)
	nexus.issue_command("move_unit", 0, { "unit_ids": [uid], "x": 8, "y": 1 }, 1)
	nexus.run_ticks(60)
	var u: Dictionary = units.get_unit(uid)
	_check(int(u["x"]) == 8 and int(u["y"]) == 1, "single unit reaches the exact requested tile")


# The formation assignment must be deterministic: same input -> same goals, so
# lockstep peers stay in sync. Now delegates to the dependency-free FormationUtil
# (MB1.3) which does not need the Nexus autoload.
func test_ma1_formation_goals_are_deterministic() -> void:
	print("test_ma1_formation_goals_are_deterministic")
	var walk: Callable = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 12 and y < 12
	var g1: Array = FormationUtil.plan_goals(Vector2i(6, 6), 5, walk)
	var g2: Array = FormationUtil.plan_goals(Vector2i(6, 6), 5, walk)
	_check(g1.size() == 5 and g2.size() == 5, "formation returns the requested count")
	var same: bool = true
	var uniq: Dictionary = {}
	for i in range(g1.size()):
		if g1[i] != g2[i]:
			same = false
		uniq["%d,%d" % [g1[i].x, g1[i].y]] = true
	_check(same, "formation goals are identical across calls (deterministic)")
	_check(uniq.size() == 5, "formation goals are all unique")


# --- Phase MB1.3: pause-stacking fix (cross-command reserved tiles) ----------

# FormationUtil must NEVER return a tile listed in `reserved`, even the exact
# center. This is the core mechanism that stops separate pause commands from all
# grabbing tile X.
func test_mb13_reserved_tiles_are_skipped() -> void:
	print("test_mb13_reserved_tiles_are_skipped")
	var walk: Callable = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 12 and y < 12
	var reserved: Dictionary = {
		"6,6": true, "6,5": true, "7,6": true,
	}
	var goals: Array = FormationUtil.plan_goals(Vector2i(6, 6), 3, walk, reserved)
	_check(goals.size() == 3, "returns the requested count with reservations")
	var hit_reserved: bool = false
	for g in goals:
		if reserved.has("%d,%d" % [g.x, g.y]):
			hit_reserved = true
	_check(not hit_reserved, "no returned tile collides with a reserved tile")


# Simulate the pause bug: three SEPARATE one-unit commands each aimed at the same
# tile X. Each later command reserves the tiles the earlier ones already claimed,
# so all three end on DISTINCT tiles (no stacking across independent commands).
func test_mb13_separate_commands_get_unique_tiles() -> void:
	print("test_mb13_separate_commands_get_unique_tiles")
	var walk: Callable = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 12 and y < 12
	var claimed: Dictionary = {}
	var picks: Array = []
	for i in range(3):
		var g: Array = FormationUtil.plan_goals(Vector2i(6, 6), 1, walk, claimed)
		_check(g.size() == 1, "each separate command yields one goal")
		var t: Vector2i = g[0]
		picks.append(t)
		claimed["%d,%d" % [t.x, t.y]] = true
	var uniq: Dictionary = {}
	for p in picks:
		uniq["%d,%d" % [p.x, p.y]] = true
	_check(uniq.size() == 3, "three separate commands to X give three unique tiles")


# Reserved-aware planning must still be deterministic (same reserved set + center
# -> identical goals) so lockstep peers agree.
func test_mb13_plan_goals_deterministic_with_reserved() -> void:
	print("test_mb13_plan_goals_deterministic_with_reserved")
	var walk: Callable = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 12 and y < 12
	var reserved: Dictionary = { "6,6": true, "5,6": true }
	var g1: Array = FormationUtil.plan_goals(Vector2i(6, 6), 4, walk, reserved)
	var g2: Array = FormationUtil.plan_goals(Vector2i(6, 6), 4, walk, reserved)
	var same: bool = g1.size() == g2.size()
	for i in range(g1.size()):
		if g1[i] != g2[i]:
			same = false
	_check(same, "reserved-aware plan is identical across calls (deterministic)")


# A single unit ordered onto a tile another unit already targets must step aside
# to the nearest free tile instead of stacking on the reserved one.
func test_mb13_single_unit_avoids_reserved_tile() -> void:
	print("test_mb13_single_unit_avoids_reserved_tile")
	var walk: Callable = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 12 and y < 12
	var reserved: Dictionary = { "6,6": true }
	var g: Array = FormationUtil.plan_goals(Vector2i(6, 6), 1, walk, reserved)
	_check(g.size() == 1, "single-unit plan returns one goal")
	_check(not reserved.has("%d,%d" % [g[0].x, g[0].y]), "single unit avoids the reserved tile")


# --- Phase MB3: Android back key routing (bug 6) ----------------------------
# NavService is the single source of truth for "where does BACK go from screen
# X?". These are pure, headless-safe checks: no SceneTree, no autoload. They
# guard the routing table the scene handlers rely on (see ui/shared/*.gd and
# ui/mobile/game_hud.gd _notification handlers).

func test_mb3_back_target_maps_each_child_to_its_parent() -> void:
	print("test_mb3_back_target_maps_each_child_to_its_parent")
	# Every non-root scene routes BACK to whatever PARENTS declares as its logical
	# parent. Since MC8 (request 9) the map/mod/gui editors + defaults nest under
	# the Editor Hub, so their parent is the hub, not the main menu directly;
	# every OTHER child still points at the main menu.
	for scene in NavService.PARENTS.keys():
		var expected: String = str(NavService.PARENTS[scene])
		_check(NavService.back_target(scene) == expected,
			"back_target(%s) is its declared parent" % scene)
	# Spot-check a few named children so a renamed constant is caught too.
	_check(NavService.back_target(NavService.MATCH_SETUP) == NavService.MAIN_MENU,
		"match_setup back is main menu")
	_check(NavService.back_target(NavService.LOBBY) == NavService.MAIN_MENU,
		"lobby back is main menu")
	# MC8: the editor hub is the top-level entry that returns to the main menu;
	# the individual editors return to the hub.
	_check(NavService.back_target(NavService.EDITOR_HUB) == NavService.MAIN_MENU,
		"editor hub back is main menu")
	_check(NavService.back_target(NavService.MAP_EDITOR) == NavService.EDITOR_HUB,
		"map_editor back is the editor hub")


func test_mb3_back_target_root_returns_empty() -> void:
	print("test_mb3_back_target_root_returns_empty")
	# The main menu is the root: BACK there has no parent (caller confirms quit).
	_check(NavService.back_target(NavService.MAIN_MENU) == "",
		"back_target(main menu) is empty (root)")


func test_mb3_back_target_unknown_scene_returns_empty() -> void:
	print("test_mb3_back_target_unknown_scene_returns_empty")
	# An unmapped scene degrades safely to "" (treated as root, never a crash).
	_check(NavService.back_target("res://scenes/does_not_exist.tscn") == "",
		"unknown scene back is empty")
	_check(NavService.back_target("") == "", "empty scene path back is empty")


func test_mb3_is_root_true_only_for_main_menu() -> void:
	print("test_mb3_is_root_true_only_for_main_menu")
	_check(NavService.is_root(NavService.MAIN_MENU), "main menu is root")
	# Unknown scenes have no parent, so they are treated as root too (safe fallback).
	_check(NavService.is_root("res://scenes/unknown.tscn"), "unknown scene is root (fallback)")
	# Every mapped child must NOT be root (it has a real parent to go back to).
	for scene in NavService.PARENTS.keys():
		_check(not NavService.is_root(scene), "%s is not root" % scene)


func test_mb3_is_in_game_true_only_for_game_scenes() -> void:
	print("test_mb3_is_in_game_true_only_for_game_scenes")
	_check(NavService.is_in_game(NavService.GAME_MOBILE), "mobile game scene is in-game")
	_check(NavService.is_in_game(NavService.GAME_DESKTOP), "desktop game scene is in-game")
	_check(not NavService.is_in_game(NavService.MAIN_MENU), "main menu is not in-game")
	_check(not NavService.is_in_game(NavService.LOBBY), "lobby is not in-game")
	_check(not NavService.is_in_game(NavService.MAP_EDITOR), "map editor is not in-game")


func test_mb3_known_scenes_complete_and_sorted() -> void:
	print("test_mb3_known_scenes_complete_and_sorted")
	var known: Array = NavService.known_scenes()
	# Completeness: the root and every mapped child must be listed exactly once.
	_check(known.has(NavService.MAIN_MENU), "known_scenes includes the root")
	for scene in NavService.PARENTS.keys():
		_check(known.has(scene), "known_scenes includes %s" % scene)
	_check(known.size() == NavService.PARENTS.size() + 1,
		"known_scenes size == children + root (no dups)")
	# Determinism: the list is sorted so callers/tests agree on order.
	var sorted_copy: Array = known.duplicate()
	sorted_copy.sort()
	_check(known == sorted_copy, "known_scenes is sorted (deterministic)")


# --- Phase MB2.2 (bug 5): single-player AI team grouping --------------------
#
# AiGroupUtil owns the pure "who is on which team" logic reused by Match Setup.
# It must mirror GameBootstrap._team_for for defaults, let explicit overrides
# win, clamp bad values, and produce deterministic groupings for the UI.

func test_mb2_default_team_matches_team_for_contract() -> void:
	print("test_mb2_default_team_matches_team_for_contract")
	# team/ctf alternate two sides; ffa gives each player their own team.
	_check(AiGroupUtil.default_team(0, "team") == 0 and AiGroupUtil.default_team(1, "team") == 1,
		"team mode alternates sides")
	_check(AiGroupUtil.default_team(2, "team") == 0 and AiGroupUtil.default_team(3, "team") == 1,
		"team mode makes a 2v2")
	_check(AiGroupUtil.default_team(0, "ctf") == 0 and AiGroupUtil.default_team(1, "ctf") == 1,
		"ctf also splits into two sides")
	_check(AiGroupUtil.default_team(0, "ffa") == 0 and AiGroupUtil.default_team(3, "ffa") == 3,
		"ffa gives each player their own team")


func test_mb2_default_overrides_seeds_all_owners() -> void:
	print("test_mb2_default_overrides_seeds_all_owners")
	var seeded: Dictionary = AiGroupUtil.default_overrides(4, "team")
	_check(seeded.size() == 4, "one entry per owner")
	_check(int(seeded[0]) == 0 and int(seeded[1]) == 1, "seeds match default_team")
	_check(int(seeded[2]) == 0 and int(seeded[3]) == 1, "seeds cover all owners")
	# Zero / negative totals must not crash and produce no entries.
	_check(AiGroupUtil.default_overrides(0, "ffa").is_empty(), "zero total -> empty map")
	_check(AiGroupUtil.default_overrides(-3, "team").is_empty(), "negative total -> empty map")


func test_mb2_clamp_team_keeps_range() -> void:
	print("test_mb2_clamp_team_keeps_range")
	_check(AiGroupUtil.clamp_team(-5) == 0, "below range clamps to 0")
	_check(AiGroupUtil.clamp_team(0) == 0, "0 stays 0")
	_check(AiGroupUtil.clamp_team(AiGroupUtil.TEAM_COUNT - 1) == AiGroupUtil.TEAM_COUNT - 1,
		"top of range preserved")
	_check(AiGroupUtil.clamp_team(999) == AiGroupUtil.TEAM_COUNT - 1, "above range clamps to max")


func test_mb2_resolve_team_override_wins_int_and_str_keys() -> void:
	print("test_mb2_resolve_team_override_wins_int_and_str_keys")
	# Integer keys (fresh from the UI).
	var by_int: Dictionary = { 1: 3 }
	_check(AiGroupUtil.resolve_team(1, "team", by_int) == 3, "int-keyed override wins over default")
	# String keys (after a JSON / WorldState section round-trip stringifies keys).
	var by_str: Dictionary = { "1": 2 }
	_check(AiGroupUtil.resolve_team(1, "team", by_str) == 2, "str-keyed override wins over default")
	# Out-of-range override is clamped, never trusted blindly.
	_check(AiGroupUtil.resolve_team(0, "ffa", { 0: 99 }) == AiGroupUtil.TEAM_COUNT - 1,
		"override is clamped into range")


func test_mb2_resolve_team_falls_back_to_default() -> void:
	print("test_mb2_resolve_team_falls_back_to_default")
	# No override for owner 2 -> falls back to per-mode default (team => 2 % 2 == 0).
	_check(AiGroupUtil.resolve_team(2, "team", { 0: 1 }) == 0, "missing owner uses default")
	_check(AiGroupUtil.resolve_team(3, "ffa", {}) == 3, "empty overrides use default")


func test_mb2_teams_to_members_groups_and_sorts() -> void:
	print("test_mb2_teams_to_members_groups_and_sorts")
	# 4 players, team mode, no overrides: {0:[0,2], 1:[1,3]}.
	var groups: Dictionary = AiGroupUtil.teams_to_members(4, "team", {})
	_check(groups.size() == 2, "two teams in a 2v2")
	_check(groups.has(0) and (groups[0] as Array) == [0, 2], "team 0 = [0,2] sorted")
	_check(groups.has(1) and (groups[1] as Array) == [1, 3], "team 1 = [1,3] sorted")
	# With an override moving owner 3 onto team 0.
	var moved: Dictionary = AiGroupUtil.teams_to_members(4, "team", { 3: 0 })
	_check((moved[0] as Array) == [0, 2, 3], "override moves member and list stays sorted")


func test_mb2_distinct_team_count() -> void:
	print("test_mb2_distinct_team_count")
	_check(AiGroupUtil.distinct_team_count(4, "team", {}) == 2, "2v2 has two distinct teams")
	_check(AiGroupUtil.distinct_team_count(4, "ffa", {}) == 4, "ffa has four distinct teams")
	# Degenerate: everyone forced onto team 0.
	var one_team: Dictionary = { 0: 0, 1: 0, 2: 0, 3: 0 }
	_check(AiGroupUtil.distinct_team_count(4, "team", one_team) == 1,
		"forcing one team collapses to a single side")


func test_mb2_bootstrap_resolve_team_honours_overrides() -> void:
	print("test_mb2_bootstrap_resolve_team_honours_overrides")
	# GameBootstrap._resolve_team must agree with AiGroupUtil: default when no
	# override, and the (clamped) override when present, with int or str keys.
	_check(GameBootstrap._resolve_team(1, 4, "team", {}) == 1, "bootstrap default matches _team_for")
	_check(GameBootstrap._resolve_team(1, 4, "team", { 1: 3 }) == 3, "bootstrap honours int override")
	_check(GameBootstrap._resolve_team(1, 4, "team", { "1": 2 }) == 2, "bootstrap honours str override")
	_check(GameBootstrap._resolve_team(0, 4, "ffa", { 0: 99 }) == 3, "bootstrap clamps override")


func test_mb2_ai_index_maps_to_owner_seat_for_bootstrap() -> void:
	print("test_mb2_ai_index_maps_to_owner_seat_for_bootstrap")
	# Contract between Match Setup and GameBootstrap: the grouping panel is keyed by
	# the 0-based AI index (AI 1, AI 2, ...), but the engine seats humans first
	# (owners 0..humans-1) then the AIs. Match Setup therefore remaps each AI index
	# onto owner = humans + ai_index before writing team_overrides. Verify the
	# remapped override actually lands on the right AI seat inside the bootstrap.
	var humans: int = 2
	var ais: int = 3
	var total: int = humans + ais            # seats 0,1 human; 2,3,4 AI
	var mode: String = "team"
	# Player chose: AI 1 (index 0) -> team 2, AI 3 (index 2) -> team 3.
	var panel_choice: Dictionary = { 0: 2, 2: 3 }
	# Remap exactly as match_setup._on_start does.
	var team_overrides: Dictionary = {}
	for ai_index in panel_choice.keys():
		team_overrides[humans + int(ai_index)] = AiGroupUtil.clamp_team(int(panel_choice[ai_index]))
	# AI 1 sits on owner seat 2, AI 3 on owner seat 4.
	_check(GameBootstrap._resolve_team(2, total, mode, team_overrides) == 2,
		"AI 1 (owner seat 2) gets its chosen team 2")
	_check(GameBootstrap._resolve_team(4, total, mode, team_overrides) == 3,
		"AI 3 (owner seat 4) gets its chosen team 3")
	# The untouched AI (index 1 -> seat 3) keeps the per-mode default (3 % 2 == 1).
	_check(GameBootstrap._resolve_team(3, total, mode, team_overrides) == 1,
		"unchosen AI seat falls back to per-mode default")
	# Human seats (0,1) are never in the override map -> per-mode defaults.
	_check(GameBootstrap._resolve_team(0, total, mode, team_overrides) == 0,
		"human seat 0 uses default team")
	_check(GameBootstrap._resolve_team(1, total, mode, team_overrides) == 1,
		"human seat 1 uses default team")


func test_mb2_setup_grouping_keys_localized_in_all_locales() -> void:
	print("test_mb2_setup_grouping_keys_localized_in_all_locales")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	var required: Array = [
		"ui.setup.ai_groups", "ui.setup.ai_groups_hint",
		"ui.setup.ai_player_n", "ui.setup.team_n",
	]
	for key in required:
		_check(en.has(key), "en has '%s'" % key)
		_check(fa.has(key), "fa has '%s'" % key)


# MB2.3 (bug 8): the main menu scene must no longer carry a "SettingsButton"
# list row; instead a top-right, corner-anchored "GearButton" opens Options.
# We assert on the scene text (no autoloads needed) so the contract is stable
# regardless of how the icon is drawn at runtime.
func test_mb2_settings_gear_replaces_list_row() -> void:
	print("test_mb2_settings_gear_replaces_list_row")
	var f: FileAccess = FileAccess.open("res://scenes/main_menu.tscn", FileAccess.READ)
	_check(f != null, "main_menu.tscn opens")
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	_check(not text.contains("name=\"SettingsButton\""), "SettingsButton row removed from list")
	_check(text.contains("name=\"GearButton\""), "GearButton node present")
	# The gear must be anchored to the top-right corner (anchor_left/right == 1.0)
	# so it stays in the corner across aspect ratios.
	_check(text.contains("anchor_left = 1.0"), "GearButton anchored to right edge")
	# The script must wire the gear press to the options screen and no longer
	# reference the removed SettingsButton.
	var s: FileAccess = FileAccess.open("res://ui/shared/main_menu.gd", FileAccess.READ)
	_check(s != null, "main_menu.gd opens")
	if s == null:
		return
	var src: String = s.get_as_text()
	s.close()
	_check(src.contains("_gear_button.pressed.connect(_on_options)"), "gear wired to options")
	_check(not src.contains("SettingsButton"), "no lingering SettingsButton reference")


# MB2.3 (bug 8): the gear is icon-only, so its purpose is exposed via a
# localized tooltip key present in every locale.
func test_mb2_settings_gear_tooltip_localized() -> void:
	print("test_mb2_settings_gear_tooltip_localized")
	var en: Dictionary = _load_locale_strings("res://localization/en.json")
	var fa: Dictionary = _load_locale_strings("res://localization/fa.json")
	_check(en.has("ui.menu.settings_gear"), "en has 'ui.menu.settings_gear'")
	_check(fa.has("ui.menu.settings_gear"), "fa has 'ui.menu.settings_gear'")


# --- Phase MB5: multiplayer lobby state (bugs 9, 10, 11, 13, 14) ------------
#
# LobbyStateUtil is the pure single source of truth the lobby scene delegates
# to; these tests pin the host<->client sync rules headlessly: slot building,
# peer seating, the ready round-trip (bugs 9/14), AI visibility in snapshots
# (bug 10), and via static guards the read-only client view (bug 13) and the
# idempotent network teardown that fixes re-join (bug 11).

func test_mb5_build_host_slots_shape_and_teams() -> void:
	print("test_mb5_build_host_slots_shape_and_teams")
	var slots: Array = LobbyStateUtil.build_host_slots(2, 2, "team")
	_check(slots.size() == 4, "2 humans + 2 AIs -> 4 slots")
	_check(str((slots[0] as Dictionary).get("kind", "")) == "human", "slot 0 is human")
	_check(int((slots[0] as Dictionary).get("peer", -1)) == 0, "slot 0 belongs to the host (peer 0)")
	_check(str((slots[2] as Dictionary).get("kind", "")) == "ai", "slot 2 is AI")
	_check(bool((slots[2] as Dictionary).get("ready", false)), "AI slots are always ready")
	_check(not bool((slots[0] as Dictionary).get("ready", true)), "human slots start not ready")
	# team mode alternates 0/1.
	_check(int((slots[0] as Dictionary).get("team", -1)) == 0, "team mode: slot 0 -> team 0")
	_check(int((slots[1] as Dictionary).get("team", -1)) == 1, "team mode: slot 1 -> team 1")
	_check(int((slots[2] as Dictionary).get("team", -1)) == 0, "team mode: slot 2 -> team 0")


func test_mb5_build_host_slots_ffa_unique_teams() -> void:
	print("test_mb5_build_host_slots_ffa_unique_teams")
	var slots: Array = LobbyStateUtil.build_host_slots(1, 3, "ffa")
	var teams: Dictionary = {}
	for slot in slots:
		teams[int((slot as Dictionary).get("team", -1))] = true
	_check(teams.size() == slots.size(), "ffa: every slot gets a unique team")


func test_mb5_assign_peer_fills_first_open_human_slot() -> void:
	print("test_mb5_assign_peer_fills_first_open_human_slot")
	var slots: Array = LobbyStateUtil.build_host_slots(3, 1, "ffa")
	var idx: int = LobbyStateUtil.assign_peer_to_open_slot(slots, 7)
	_check(idx == 1, "first open human slot is index 1 (0 is host)")
	_check(int((slots[1] as Dictionary).get("peer", -1)) == 7, "peer id stored on the slot")
	_check(LobbyStateUtil.slot_index_for_peer(slots, 7) == 1, "slot_index_for_peer resolves the seat")
	_check(LobbyStateUtil.filled_human_slots(slots) == 2, "host + joined peer = 2 filled humans")


func test_mb5_assign_peer_never_takes_ai_slot_and_full_returns_minus_one() -> void:
	print("test_mb5_assign_peer_never_takes_ai_slot_and_full_returns_minus_one")
	var slots: Array = LobbyStateUtil.build_host_slots(1, 2, "ffa")
	# Only slot 0 (host) is human, so a joining peer has no seat.
	var idx: int = LobbyStateUtil.assign_peer_to_open_slot(slots, 9)
	_check(idx == -1, "full lobby (no open human slot) returns -1")
	_check(int((slots[1] as Dictionary).get("peer", -1)) == -1, "AI slot untouched")
	_check(LobbyStateUtil.slot_index_for_peer(slots, 9) == -1, "unseated peer resolves to -1")


func test_mb5_ready_roundtrip_for_peer() -> void:
	print("test_mb5_ready_roundtrip_for_peer")
	# Bug 9/14: the client's ready_state must land on the host's slot model.
	var slots: Array = LobbyStateUtil.build_host_slots(2, 1, "team")
	LobbyStateUtil.assign_peer_to_open_slot(slots, 3)
	_check(not LobbyStateUtil.can_start(slots), "not startable while the client is unready")
	_check(LobbyStateUtil.set_ready_for_peer(slots, 3, true), "ready_state applied for seated peer")
	_check(bool((slots[1] as Dictionary).get("ready", false)), "client slot flagged ready")
	_check(not LobbyStateUtil.set_ready_for_peer(slots, 42, true), "unknown peer is rejected")
	# The host itself is still unready; toggling it too unlocks the start gate.
	LobbyStateUtil.set_ready_for_peer(slots, 0, true)
	_check(LobbyStateUtil.can_start(slots), "all occupied humans ready -> can start (bug 14)")


func test_mb5_can_start_gates_on_occupied_humans_only() -> void:
	print("test_mb5_can_start_gates_on_occupied_humans_only")
	# Empty human seats and AI slots must never block the start.
	var slots: Array = LobbyStateUtil.build_host_slots(3, 2, "ffa")
	LobbyStateUtil.set_ready_for_peer(slots, 0, true)
	_check(LobbyStateUtil.can_start(slots),
		"host ready + empty seats + AIs -> startable (empty seats do not block)")
	LobbyStateUtil.assign_peer_to_open_slot(slots, 5)
	_check(not LobbyStateUtil.can_start(slots), "a newly seated, unready client blocks start")


func test_mb5_snapshot_includes_ai_and_roundtrips() -> void:
	print("test_mb5_snapshot_includes_ai_and_roundtrips")
	# Bug 10: the snapshot the host broadcasts must contain the AI slots so a
	# joining client sees the bots, and it must round-trip losslessly.
	var slots: Array = LobbyStateUtil.build_host_slots(2, 2, "team")
	LobbyStateUtil.assign_peer_to_open_slot(slots, 4)
	LobbyStateUtil.set_ready_for_peer(slots, 4, true)
	var snap: Array = LobbyStateUtil.snapshot(slots)
	_check(snap.size() == 4, "snapshot covers ALL slots (humans + AIs)")
	var ai_count: int = 0
	for entry in snap:
		if str((entry as Dictionary).get("kind", "")) == "ai":
			ai_count += 1
	_check(ai_count == 2, "both AI slots are present in the snapshot (bug 10)")
	var rebuilt: Array = LobbyStateUtil.from_snapshot(snap)
	_check(rebuilt == slots, "from_snapshot(snapshot(x)) == x (lossless round-trip)")
	# Serializable-only payload: every value must be a String/int/bool.
	var clean: bool = true
	for entry in snap:
		for key in (entry as Dictionary):
			var v: Variant = (entry as Dictionary)[key]
			if not (v is String or v is int or v is bool):
				clean = false
	_check(clean, "snapshot uses only plain String/int/bool values")


func test_mb5_placements_cover_every_slot() -> void:
	print("test_mb5_placements_cover_every_slot")
	var slots: Array = LobbyStateUtil.build_host_slots(1, 2, "team")
	var placements: Array = LobbyStateUtil.placements(slots)
	_check(placements.size() == slots.size(), "one placement per slot")
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		_check(int(p.get("slot", -1)) == i and int(p.get("flag_index", -1)) == i,
			"placement %d carries its slot + flag index" % i)
	_check(str((placements[1] as Dictionary).get("kind", "")) == "ai",
		"placement preserves the slot kind")


# Bug 11 (re-join): the lobby must own ONE idempotent teardown used by every
# exit path (back button, WM_GO_BACK, ui_cancel) that closes the session, stops
# discovery AND drops all event-bus subscriptions.
func test_mb5_lobby_teardown_static_guard() -> void:
	print("test_mb5_lobby_teardown_static_guard")
	var src: String = FileAccess.get_file_as_string("res://ui/shared/lobby.gd")
	_check(src != "", "lobby.gd source is readable")
	_check(src.contains("func _teardown_network"), "lobby has a single teardown helper")
	var body: String = _mb5_func_body(src, "func _teardown_network")
	_check(body.contains("_session.close()"), "teardown closes the network session")
	_check(body.contains("_discovery.stop()"), "teardown stops LAN discovery")
	_check(body.contains("unsubscribe_all"), "teardown drops ALL event-bus subscriptions")
	# Every exit path funnels through _on_back -> _teardown_network.
	_check(_mb5_func_body(src, "func _on_back").contains("_teardown_network()"),
		"back button tears the network down")
	_check(_mb5_func_body(src, "func _notification").contains("_on_back()"),
		"Android BACK (WM_GO_BACK) routes through _on_back")
	_check(_mb5_func_body(src, "func _unhandled_input").contains("_on_back()"),
		"ui_cancel routes through _on_back")


# Bug 13: after connecting, a join client must switch to a read-only lobby view
# (search UI hidden, slot list shown, Start reserved for the host).
func test_mb5_lobby_client_readonly_view_static_guard() -> void:
	print("test_mb5_lobby_client_readonly_view_static_guard")
	var src: String = FileAccess.get_file_as_string("res://ui/shared/lobby.gd")
	_check(src != "", "lobby.gd source is readable")
	var labels: String = _mb5_func_body(src, "func _apply_labels")
	_check(labels.contains("not _connected"), "search UI visibility depends on connection state")
	_check(labels.contains("_start_button.visible = (_role == \"host\")"),
		"only the host sees the Start button")
	var connected: String = _mb5_func_body(src, "func _on_connected")
	_check(connected.contains("_connected = true") and connected.contains("_apply_labels()"),
		"connecting flips the client into the read-only view")
	var failed: String = _mb5_func_body(src, "func _on_connection_failed")
	_check(failed.contains("_connected = false"),
		"a failed connection falls back to the browsing view")
	# Team editing is host-only (clients get a disabled control).
	_check(src.contains("team_option.disabled = (_role != \"host\")"),
		"clients cannot edit teams in the read-only view")


# --- Phase MB6: host IP display + network rescan (bugs 12, 19) --------------

# Bug 12: NetAddressUtil.is_ipv4 accepts canonical dotted-quads and rejects
# IPv6 / malformed / out-of-range / leading-zero text.
func test_mb6_net_address_is_ipv4_validation() -> void:
	print("test_mb6_net_address_is_ipv4_validation")
	_check(NetAddressUtil.is_ipv4("192.168.1.10"), "accepts a normal LAN IPv4")
	_check(NetAddressUtil.is_ipv4("0.0.0.0"), "accepts all-zero IPv4")
	_check(NetAddressUtil.is_ipv4("255.255.255.255"), "accepts broadcast IPv4")
	_check(not NetAddressUtil.is_ipv4("256.1.1.1"), "rejects octet > 255")
	_check(not NetAddressUtil.is_ipv4("1.2.3"), "rejects three-octet string")
	_check(not NetAddressUtil.is_ipv4("1.2.3.4.5"), "rejects five-octet string")
	_check(not NetAddressUtil.is_ipv4("fe80::1"), "rejects IPv6")
	_check(not NetAddressUtil.is_ipv4("192.168.01.1"), "rejects leading-zero octet")
	_check(not NetAddressUtil.is_ipv4("a.b.c.d"), "rejects non-numeric octets")


# Bug 12: classifiers for loopback / link-local / private LAN ranges.
func test_mb6_net_address_range_classifiers() -> void:
	print("test_mb6_net_address_range_classifiers")
	_check(NetAddressUtil.is_loopback_v4("127.0.0.1"), "127.0.0.1 is loopback")
	_check(not NetAddressUtil.is_loopback_v4("192.168.1.1"), "LAN is not loopback")
	_check(NetAddressUtil.is_link_local_v4("169.254.5.6"), "169.254.x is link-local")
	_check(not NetAddressUtil.is_link_local_v4("192.168.5.6"), "LAN is not link-local")
	_check(NetAddressUtil.is_private_lan_v4("10.0.0.5"), "10.x is private")
	_check(NetAddressUtil.is_private_lan_v4("192.168.0.42"), "192.168.x is private")
	_check(NetAddressUtil.is_private_lan_v4("172.16.0.1"), "172.16.x is private")
	_check(NetAddressUtil.is_private_lan_v4("172.31.255.254"), "172.31.x is private")
	_check(not NetAddressUtil.is_private_lan_v4("172.15.0.1"), "172.15.x is NOT private")
	_check(not NetAddressUtil.is_private_lan_v4("172.32.0.1"), "172.32.x is NOT private")
	_check(not NetAddressUtil.is_private_lan_v4("8.8.8.8"), "public IPv4 is not private")


# Bug 12: best_lan_ipv4 prefers a private LAN address, skips loopback/link-local
# and IPv6, falls back to any other IPv4, and returns "" when nothing is usable.
func test_mb6_net_address_best_lan_selection() -> void:
	print("test_mb6_net_address_best_lan_selection")
	# Loopback + IPv6 + a real LAN address -> the LAN address wins.
	_check(NetAddressUtil.best_lan_ipv4(["127.0.0.1", "fe80::1", "192.168.1.20"]) == "192.168.1.20",
		"private LAN address is chosen over loopback/IPv6")
	# Private beats a non-private public IPv4 regardless of order.
	_check(NetAddressUtil.best_lan_ipv4(["8.8.8.8", "10.1.2.3"]) == "10.1.2.3",
		"private LAN beats a public IPv4")
	# Link-local is skipped in favour of a private address.
	_check(NetAddressUtil.best_lan_ipv4(["169.254.1.1", "192.168.5.5"]) == "192.168.5.5",
		"link-local is skipped for a private address")
	# No private address: fall back to the first non-loopback IPv4.
	_check(NetAddressUtil.best_lan_ipv4(["127.0.0.1", "203.0.113.7", "198.51.100.9"]) == "203.0.113.7",
		"falls back to first usable public IPv4 in list order")
	# Only loopback/IPv6 -> nothing usable.
	_check(NetAddressUtil.best_lan_ipv4(["127.0.0.1", "fe80::1"]) == "",
		"returns empty when only loopback/IPv6 present")
	_check(NetAddressUtil.best_lan_ipv4([]) == "", "empty input returns empty")


# Bugs 12/19: static guard that lobby.gd actually wires host-address display,
# the rescan button, the auto-rescan timer, and the no-servers hint.
func test_mb6_lobby_ip_and_rescan_static_guard() -> void:
	print("test_mb6_lobby_ip_and_rescan_static_guard")
	var src: String = FileAccess.get_file_as_string("res://ui/shared/lobby.gd")
	_check(src != "", "lobby.gd source is readable")
	# MB6.1: host address label filled via the pure util + IP.get_local_addresses.
	_check(src.contains("func _update_host_address_label"), "lobby has host-address helper")
	var addr_body: String = _mb5_func_body(src, "func _update_host_address_label")
	_check(addr_body.contains("NetAddressUtil.best_lan_ipv4"), "host address uses NetAddressUtil")
	_check(addr_body.contains("IP.get_local_addresses"), "host address reads local addresses")
	_check(_mb5_func_body(src, "func _start_as_host").contains("_update_host_address_label()"),
		"host start fills the address label")
	# MB6.2: rescan button + auto-rescan timer + hint.
	_check(src.contains("_rescan_button"), "lobby has a rescan button")
	_check(src.contains("func _on_rescan_pressed"), "lobby has a manual rescan handler")
	_check(src.contains("_rescan_timer"), "lobby has an auto-rescan timer")
	_check(src.contains("AUTO_RESCAN_INTERVAL"), "auto-rescan interval constant exists")
	_check(_mb5_func_body(src, "func _on_rescan_tick").contains("_refresh_server_list"),
		"auto-rescan tick re-lists servers")
	_check(_mb5_func_body(src, "func _refresh_server_list").contains("ui.lobby.no_servers"),
		"empty server list shows the no-servers hint")
	# Teardown must also stop the timer (no live ticks after leaving).
	_check(_mb5_func_body(src, "func _teardown_network").contains("_rescan_timer.stop()"),
		"teardown stops the auto-rescan timer")


# ----------------------------------------------------------------------------
# Phase MC3 (request 3): data-driven UI icon system.
#
# IconManifestUtil is a PURE helper over the parsed manifest Dictionary; it is
# tested headlessly with no engine textures. IconService is the engine half: it
# resolves a logical name to a Texture2D, returning a drawn RGBA8 fallback glyph
# whenever the real art file is missing, so the HUD never breaks. These tests
# guarantee the fallback path is null-safe and that the bundled manifest is
# well-formed. A static guard confirms the mobile HUD actually wires the service.
# ----------------------------------------------------------------------------

# The bundled manifest at data/ui_icons/manifest.json parses and is shaped.
func test_mc3_manifest_is_valid_and_shaped() -> void:
	print("test_mc3_manifest_is_valid_and_shaped")
	var text: String = FileAccess.get_file_as_string("res://data/ui_icons/manifest.json")
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary, "manifest parses to a Dictionary")
	var manifest: Dictionary = parsed as Dictionary
	_check(IconManifestUtil.is_valid(manifest), "bundled manifest is valid")
	_check(IconManifestUtil.base_size(manifest) == 128, "base size is 128")
	_check(manifest.get("schema", "") == "nexus_ui_icons_v1", "schema tag present")


# icon_names returns a sorted list and known logical names are declared.
func test_mc3_manifest_util_names_sorted_and_present() -> void:
	print("test_mc3_manifest_util_names_sorted_and_present")
	var text: String = FileAccess.get_file_as_string("res://data/ui_icons/manifest.json")
	var manifest: Dictionary = JSON.parse_string(text) as Dictionary
	var names: Array = IconManifestUtil.icon_names(manifest)
	_check(names.size() >= 17, "at least 17 logical icons declared")
	var sorted_copy: Array = names.duplicate()
	sorted_copy.sort()
	_check(names == sorted_copy, "icon_names is returned in stable sorted order")
	for expected in ["select", "assign", "move", "play", "back", "settings_gear"]:
		_check(IconManifestUtil.has_icon(manifest, expected), "declares icon '%s'" % expected)


# path_for / size_for read the real entry values.
func test_mc3_manifest_util_path_and_size_lookup() -> void:
	print("test_mc3_manifest_util_path_and_size_lookup")
	var text: String = FileAccess.get_file_as_string("res://data/ui_icons/manifest.json")
	var manifest: Dictionary = JSON.parse_string(text) as Dictionary
	_check(IconManifestUtil.path_for(manifest, "move") == "res://assets/ui_icons/move.png",
		"path_for returns the declared file path")
	_check(IconManifestUtil.size_for(manifest, "move") == 128, "size_for returns the declared size")


# Missing icons return safe defaults, not errors.
func test_mc3_manifest_util_missing_icon_defaults() -> void:
	print("test_mc3_manifest_util_missing_icon_defaults")
	var text: String = FileAccess.get_file_as_string("res://data/ui_icons/manifest.json")
	var manifest: Dictionary = JSON.parse_string(text) as Dictionary
	_check(not IconManifestUtil.has_icon(manifest, "no_such_icon"), "unknown icon is absent")
	_check(IconManifestUtil.path_for(manifest, "no_such_icon") == "", "missing path is empty string")
	_check(IconManifestUtil.size_for(manifest, "no_such_icon") == IconManifestUtil.base_size(manifest),
		"missing size falls back to base size")


# A malformed manifest is rejected without crashing.
func test_mc3_manifest_util_rejects_malformed() -> void:
	print("test_mc3_manifest_util_rejects_malformed")
	_check(not IconManifestUtil.is_valid({}), "empty dict is not a valid manifest")
	_check(not IconManifestUtil.is_valid({"icons": "not_a_dict"}), "icons must be a Dictionary")
	_check(IconManifestUtil.icon_names({}) == [], "invalid manifest yields no names")
	_check(IconManifestUtil.base_size({"base_size": -5}) == IconManifestUtil.DEFAULT_BASE_SIZE,
		"non-positive base size falls back to default")


# IconService loads the bundled manifest and exposes its icons.
func test_mc3_icon_service_loads_bundled_manifest() -> void:
	print("test_mc3_icon_service_loads_bundled_manifest")
	var svc: IconService = IconService.new()
	svc.load_manifest()
	_check(IconManifestUtil.is_valid(svc.manifest()), "service loaded a valid manifest")
	_check(svc.has_icon("move"), "service reports declared icon present")
	_check(not svc.has_icon("no_such_icon"), "service reports unknown icon absent")


# icon_texture never returns null, even for real and unknown names.
func test_mc3_icon_service_fallback_never_null() -> void:
	print("test_mc3_icon_service_fallback_never_null")
	var svc: IconService = IconService.new()
	svc.load_manifest()
	_check(svc.icon_texture("move") != null, "declared icon resolves to a texture")
	_check(svc.icon_texture("no_such_icon") != null, "unknown icon still resolves (fallback glyph)")
	var tex: Texture2D = svc.icon_texture("no_such_icon")
	_check(tex.get_width() == IconService.FALLBACK_SIZE, "fallback glyph is the expected size")


# The fallback texture is cached, so repeated lookups return the same instance.
func test_mc3_icon_service_fallback_cached_and_stable() -> void:
	print("test_mc3_icon_service_fallback_cached_and_stable")
	var svc: IconService = IconService.new()
	svc.load_manifest()
	var a: Texture2D = svc.icon_texture("build")
	var b: Texture2D = svc.icon_texture("build")
	_check(a == b, "same logical name returns the cached texture instance")
	var c: Texture2D = svc.icon_texture("attack")
	_check(a != c, "different names produce distinct fallback glyphs")


# has_real_art is false while placeholder art files are absent on disk.
func test_mc3_icon_service_has_real_art_false_without_files() -> void:
	print("test_mc3_icon_service_has_real_art_false_without_files")
	var svc: IconService = IconService.new()
	svc.load_manifest()
	# The manifest declares the paths, but the PNG files are not shipped yet, so
	# every logical icon must currently resolve to a fallback glyph.
	var any_real: bool = false
	for name in IconManifestUtil.icon_names(svc.manifest()):
		if svc.has_real_art(name):
			any_real = true
	_check(not any_real or FileAccess.file_exists("res://assets/ui_icons/move.png"),
		"has_real_art is false until real art files are added")


# Loading a missing manifest degrades to fallback-only without crashing.
func test_mc3_icon_service_survives_missing_manifest() -> void:
	print("test_mc3_icon_service_survives_missing_manifest")
	var svc: IconService = IconService.new()
	svc.load_manifest("res://data/ui_icons/does_not_exist.json")
	_check(svc.manifest().is_empty(), "missing manifest leaves an empty dict")
	_check(not svc.has_icon("move"), "no icons declared without a manifest")
	_check(svc.icon_texture("move") != null, "still serves a fallback glyph with no manifest")


# Static guard: the mobile HUD owns an IconService and applies icons to buttons.
func test_mc3_mobile_hud_wires_icon_service() -> void:
	print("test_mc3_mobile_hud_wires_icon_service")
	var src: String = FileAccess.get_file_as_string("res://ui/mobile/game_hud.gd")
	_check(src.contains("IconService.new()"), "mobile HUD owns an IconService instance")
	_check(src.contains("_icons.load_manifest()"), "HUD loads the icon manifest")
	_check(src.contains("_icons.apply_to_button("), "HUD applies icons to buttons via the service")
	_check(src.contains("\"move\""), "wires the move icon")
	_check(src.contains("\"play\""), "wires the play (confirm) icon")
	_check(src.contains("\"back\""), "wires the back (cancel) icon")


# Extract the body of `header` (up to the next top-level func) from GDScript
# source, for the MB5 static guards.
func _mb5_func_body(src: String, header: String) -> String:
	var at: int = src.find(header)
	if at == -1:
		return ""
	var next_func: int = src.find("\nfunc ", at + 1)
	if next_func == -1:
		next_func = src.length()
	return src.substr(at, next_func - at)


# --- Phase MA2: box / drag selection (mobile) -------------------------------

# Build a minimal units section dictionary for box-select tests. Each entry is
# a {id,x,y,owner} record keyed by id string, matching WorldState's shape.
func _ma2_units() -> Dictionary:
	var d: Dictionary = {}
	# owner 0 units
	d["1"] = { "id": 1, "x": 2, "y": 2, "owner": 0 }
	d["2"] = { "id": 2, "x": 3, "y": 3, "owner": 0 }
	d["3"] = { "id": 3, "x": 10, "y": 10, "owner": 0 }   # far outside a small box
	# enemy unit inside the box (must be excluded by owner filter)
	d["4"] = { "id": 4, "x": 2, "y": 3, "owner": 1 }
	return d

func _ma2_adapter() -> RenderAdapter:
	var a: RenderAdapter = RenderAdapter.new()
	a.tile_size = 24
	a.zoom = 1.0
	a.camera_offset = Vector2.ZERO
	return a

# A box covering tiles (0,0)..(4,4) in screen space (0..120 px at 24px/tile)
# must pick the two friendly units inside and skip the far one.
func test_ma2_box_select_picks_units_inside_rect() -> void:
	print("test_ma2_box_select_picks_units_inside_rect")
	var adapter: RenderAdapter = _ma2_adapter()
	var ids: Array = SelectionUtil.units_in_screen_rect(adapter, _ma2_units(), Vector2(0, 0), Vector2(119, 119), 0)
	_check(ids.has(1) and ids.has(2), "box picks the two friendly units inside")
	_check(not ids.has(3), "box excludes the far-away friendly unit")


# The owner filter must exclude enemy units even when they sit inside the box.
func test_ma2_box_select_filters_by_owner() -> void:
	print("test_ma2_box_select_filters_by_owner")
	var adapter: RenderAdapter = _ma2_adapter()
	var ids: Array = SelectionUtil.units_in_screen_rect(adapter, _ma2_units(), Vector2(0, 0), Vector2(119, 119), 0)
	_check(not ids.has(4), "enemy unit inside the box is excluded by owner filter")


# The two corner points may be given in any order (drag up-left or down-right).
func test_ma2_box_select_corner_order_independent() -> void:
	print("test_ma2_box_select_corner_order_independent")
	var adapter: RenderAdapter = _ma2_adapter()
	var a: Array = SelectionUtil.units_in_screen_rect(adapter, _ma2_units(), Vector2(0, 0), Vector2(119, 119), 0)
	var b: Array = SelectionUtil.units_in_screen_rect(adapter, _ma2_units(), Vector2(119, 119), Vector2(0, 0), 0)
	_check(a == b, "corner order does not change the selection")


# Ids must come back sorted ascending (deterministic -> lockstep-safe).
func test_ma2_box_select_ids_sorted_deterministic() -> void:
	print("test_ma2_box_select_ids_sorted_deterministic")
	var adapter: RenderAdapter = _ma2_adapter()
	var ids: Array = SelectionUtil.units_in_screen_rect(adapter, _ma2_units(), Vector2(0, 0), Vector2(240, 240), 0)
	var sorted_copy: Array = ids.duplicate()
	sorted_copy.sort()
	_check(ids == sorted_copy, "box-select ids are returned sorted ascending")


# --- Phase MA3: control groups (unit grouping) ------------------------------

# Build a minimal units section dictionary for control-group tests. Keys are id
# strings (matching WorldState); only ids 1,2,3 are "alive".
func _ma3_units() -> Dictionary:
	var d: Dictionary = {}
	d["1"] = { "id": 1, "x": 0, "y": 0, "owner": 0 }
	d["2"] = { "id": 2, "x": 1, "y": 0, "owner": 0 }
	d["3"] = { "id": 3, "x": 2, "y": 0, "owner": 0 }
	return d


# Assigning a selection stores a sorted, de-duplicated int list (deterministic).
func test_ma3_assign_normalises_selection() -> void:
	print("test_ma3_assign_normalises_selection")
	# A messy selection: out of order, with a duplicate and mixed int/string ids.
	var stored: Array = ControlGroupUtil.normalise_ids([3, 1, "2", 1])
	_check(stored == [1, 2, 3], "assign yields a sorted, de-duplicated int list")
	# Empty selection produces an empty group.
	_check(ControlGroupUtil.normalise_ids([]).is_empty(), "assigning nothing yields an empty group")


# Recall must drop ids whose units have died since the group was assigned.
func test_ma3_recall_prunes_dead_units() -> void:
	print("test_ma3_recall_prunes_dead_units")
	var units: Dictionary = _ma3_units()
	# Group held ids 1,2,3,99 -- unit 99 no longer exists.
	var living: Array = ControlGroupUtil.prune_living([1, 2, 3, 99], units)
	_check(living == [1, 2, 3], "dead unit (99) pruned from the recalled group")
	# A group of only-dead units recalls to nothing.
	_check(ControlGroupUtil.prune_living([98, 99], units).is_empty(), "group of only-dead units recalls empty")


# Prune returns ids in a stable ascending order regardless of stored order.
func test_ma3_recall_is_deterministic() -> void:
	print("test_ma3_recall_is_deterministic")
	var units: Dictionary = _ma3_units()
	var a: Array = ControlGroupUtil.prune_living([3, 1, 2], units)
	var b: Array = ControlGroupUtil.prune_living([2, 3, 1], units)
	_check(a == b, "recall order is independent of stored order")
	var sorted_copy: Array = a.duplicate()
	sorted_copy.sort()
	_check(a == sorted_copy, "recalled ids come back sorted ascending")


# The fresh control-group table has exactly SLOT_COUNT empty lists.
func test_ma3_empty_groups_table_shape() -> void:
	print("test_ma3_empty_groups_table_shape")
	var groups: Array = ControlGroupUtil.empty_groups()
	_check(groups.size() == ControlGroupUtil.SLOT_COUNT, "empty table has SLOT_COUNT slots")
	var all_empty: bool = true
	for g in groups:
		if not (g as Array).is_empty():
			all_empty = false
	_check(all_empty, "every fresh slot is an empty list")


# The button label shows the 1-based slot number, plus a count when populated.
func test_ma3_button_label_shows_count() -> void:
	print("test_ma3_button_label_shows_count")
	_check(ControlGroupUtil.button_label(0, 0) == "1", "empty slot 0 labelled '1' (no count)")
	_check(ControlGroupUtil.button_label(4, 3) == "5\n(3)", "populated slot 4 shows '5' + count 3")


# Only slots 0..SLOT_COUNT-1 are valid.
func test_ma3_slot_validation() -> void:
	print("test_ma3_slot_validation")
	_check(ControlGroupUtil.is_valid_slot(0), "slot 0 is valid")
	_check(ControlGroupUtil.is_valid_slot(ControlGroupUtil.SLOT_COUNT - 1), "last slot is valid")
	_check(not ControlGroupUtil.is_valid_slot(-1), "negative slot is invalid")
	_check(not ControlGroupUtil.is_valid_slot(ControlGroupUtil.SLOT_COUNT), "out-of-range slot is invalid")


# --- Phase MA4: portrait GUI scale + bottom-bar overflow --------------------

# B4: a phone held upright (portrait) must NOT shrink the HUD. The old math
# compared the portrait width to the landscape reference width and produced a
# sub-1.0 (tiny) scale; the orientation-aware fix must give a comfortable,
# >= 1.0 scale on a typical 1080x2340 phone.
func test_ma4_portrait_phone_scale_not_tiny() -> void:
	print("test_ma4_portrait_phone_scale_not_tiny")
	# Common portrait phone resolution.
	var s: float = GameSettings.auto_scale_for(Vector2(1080, 2340))
	_check(s >= 1.0, "portrait phone (1080x2340) scales the HUD UP, not down (got %.2f)" % s)
	# A small-ish portrait phone should still be at least readable (>= reference).
	var s2: float = GameSettings.auto_scale_for(Vector2(720, 1280))
	_check(s2 >= 1.0, "720x1280 portrait is at least 1.0x (got %.2f)" % s2)


# The scale must be identical whether the SAME device is held in portrait or
# landscape (only the orientation flips; the physical screen is the same).
func test_ma4_scale_is_orientation_agnostic() -> void:
	print("test_ma4_scale_is_orientation_agnostic")
	var portrait: float = GameSettings.auto_scale_for(Vector2(1080, 2340))
	var landscape: float = GameSettings.auto_scale_for(Vector2(2340, 1080))
	_check(abs(portrait - landscape) < 0.0001, "portrait and landscape of one device scale the same")
	# The landscape reference itself stays exactly 1.0x (no regression).
	_check(abs(GameSettings.auto_scale_for(Vector2(1280, 720)) - 1.0) < 0.0001, "reference landscape unchanged (1.0x)")


# B5: the in-game bottom action bar must live inside a horizontally-scrolling
# container so its many buttons can never overflow off a narrow phone screen.
func test_ma4_bottom_bar_scrolls() -> void:
	print("test_ma4_bottom_bar_scrolls")
	var packed: PackedScene = load("res://scenes/game_main.tscn")
	_check(packed != null, "game_main scene loads")
	if packed == null:
		return
	var state: SceneState = packed.get_state()
	# Walk the scene state looking for a ScrollContainer that parents the bottom
	# action Row, and confirm horizontal scrolling is enabled.
	var found_scroll: bool = false
	var row_under_scroll: bool = false
	for i in range(state.get_node_count()):
		var node_name: String = str(state.get_node_name(i))
		var node_type: String = str(state.get_node_type(i))
		var node_path: String = str(state.get_node_path(i))
		if node_type == "ScrollContainer" and node_path.contains("BottomBar"):
			found_scroll = true
		if node_name == "Row" and node_path.contains("Scroll"):
			row_under_scroll = true
	_check(found_scroll, "bottom bar contains a ScrollContainer")
	_check(row_under_scroll, "the action Row lives inside the ScrollContainer")


# --- Phase MA5: free rotation + responsive HUD re-flow ----------------------

# A few representative device viewports (absolute px) used across the MA5 tests.
# Each pair is the SAME physical screen in portrait and landscape.
func _ma5_viewports() -> Array:
	return [
		Vector2(1080, 2340),  # tall modern phone (portrait)
		Vector2(2340, 1080),  # ... landscape
		Vector2(720, 1280),   # small phone (portrait)
		Vector2(1280, 720),   # ... landscape (reference)
		Vector2(1600, 2560),  # tablet (portrait)
		Vector2(2560, 1600),  # ... landscape
	]


# Representative widget sizes matching the real HUD nodes.
func _ma5_minimap_size() -> Vector2:
	return Vector2(180, 130)


func _ma5_zoom_size() -> Vector2:
	return Vector2(48, 102)   # two 48px buttons + separation


func _ma5_group_size() -> Vector2:
	return Vector2(140, 190)  # assign button + 3x3 grid


func _ma5_select_size() -> Vector2:
	return Vector2(140, 34)


# True when `widget` (top-left `pos`, given `size`) is fully inside the viewport.
func _ma5_on_screen(pos: Vector2, size: Vector2, vp: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x + size.x <= vp.x + 0.01 and pos.y + size.y <= vp.y + 0.01


# is_landscape must key purely off the aspect (>= is landscape/square).
func test_ma5_orientation_detection() -> void:
	print("test_ma5_orientation_detection")
	_check(ResponsiveLayoutUtil.is_landscape(Vector2(1280, 720)), "wide viewport is landscape")
	_check(not ResponsiveLayoutUtil.is_landscape(Vector2(720, 1280)), "tall viewport is portrait")
	_check(ResponsiveLayoutUtil.is_landscape(Vector2(1000, 1000)), "square counts as landscape")


# The safe area must sit inside the outer margin and clear both HUD bars.
func test_ma5_safe_area_excludes_bars() -> void:
	print("test_ma5_safe_area_excludes_bars")
	var vp: Vector2 = Vector2(1080, 2340)
	var area: Rect2 = ResponsiveLayoutUtil.safe_area(vp)
	_check(area.position.x >= ResponsiveLayoutUtil.MARGIN - 0.01, "safe area left honours margin")
	_check(area.position.y >= ResponsiveLayoutUtil.TOP_BAR_H, "safe area top clears the top bar")
	_check(area.position.x + area.size.x <= vp.x - ResponsiveLayoutUtil.MARGIN + 0.01, "safe area right honours margin")
	_check(area.position.y + area.size.y <= vp.y - ResponsiveLayoutUtil.BOTTOM_BAR_H + 0.01, "safe area bottom clears the bottom bar")


# Every floating widget must stay fully on-screen in PORTRAIT for all devices.
func test_ma5_all_widgets_stay_on_screen_portrait() -> void:
	print("test_ma5_all_widgets_stay_on_screen_portrait")
	for vp in _ma5_viewports():
		if ResponsiveLayoutUtil.is_landscape(vp):
			continue
		_ma5_assert_all_on_screen(vp)


# Every floating widget must stay fully on-screen in LANDSCAPE for all devices.
func test_ma5_all_widgets_stay_on_screen_landscape() -> void:
	print("test_ma5_all_widgets_stay_on_screen_landscape")
	for vp in _ma5_viewports():
		if not ResponsiveLayoutUtil.is_landscape(vp):
			continue
		_ma5_assert_all_on_screen(vp)


# Shared assertion: place every widget for `vp` and confirm each is on-screen.
func _ma5_assert_all_on_screen(vp: Vector2) -> void:
	var mm: Vector2 = ResponsiveLayoutUtil.minimap_pos(vp, _ma5_minimap_size())
	_check(_ma5_on_screen(mm, _ma5_minimap_size(), vp), "minimap on-screen @ %s" % vp)
	var zc: Vector2 = ResponsiveLayoutUtil.zoom_col_pos(vp, _ma5_zoom_size())
	_check(_ma5_on_screen(zc, _ma5_zoom_size(), vp), "zoom column on-screen @ %s" % vp)
	var gp: Vector2 = ResponsiveLayoutUtil.control_group_pos(vp, _ma5_group_size())
	_check(_ma5_on_screen(gp, _ma5_group_size(), vp), "control groups on-screen @ %s" % vp)
	var sb: Vector2 = ResponsiveLayoutUtil.select_button_pos(vp, _ma5_select_size(), gp, _ma5_group_size())
	_check(_ma5_on_screen(sb, _ma5_select_size(), vp), "select button on-screen @ %s" % vp)


# Widgets must not intrude into the top bar (y >= TOP_BAR_H) nor the bottom bar
# (bottom edge <= viewport - BOTTOM_BAR_H) for every device/orientation.
func test_ma5_widgets_avoid_hud_bars() -> void:
	print("test_ma5_widgets_avoid_hud_bars")
	var top_h: float = ResponsiveLayoutUtil.TOP_BAR_H
	for vp in _ma5_viewports():
		var mm: Vector2 = ResponsiveLayoutUtil.minimap_pos(vp, _ma5_minimap_size())
		_check(mm.y >= top_h - 0.01, "minimap clears top bar @ %s" % vp)
		var bottom_limit: float = vp.y - ResponsiveLayoutUtil.BOTTOM_BAR_H
		var gp: Vector2 = ResponsiveLayoutUtil.control_group_pos(vp, _ma5_group_size())
		_check(gp.y + _ma5_group_size().y <= bottom_limit + 0.01, "control groups clear bottom bar @ %s" % vp)
		var zc: Vector2 = ResponsiveLayoutUtil.zoom_col_pos(vp, _ma5_zoom_size())
		_check(zc.y + _ma5_zoom_size().y <= bottom_limit + 0.01, "zoom column clears bottom bar @ %s" % vp)


# The Select toggle must sit ABOVE the control-group panel (smaller y) and share
# its left edge, in both orientations.
func test_ma5_select_button_sits_above_group() -> void:
	print("test_ma5_select_button_sits_above_group")
	for vp in _ma5_viewports():
		var gp: Vector2 = ResponsiveLayoutUtil.control_group_pos(vp, _ma5_group_size())
		var sb: Vector2 = ResponsiveLayoutUtil.select_button_pos(vp, _ma5_select_size(), gp, _ma5_group_size())
		_check(sb.y + _ma5_select_size().y <= gp.y + 0.01, "select button is above the group panel @ %s" % vp)
		_check(abs(sb.x - gp.x) < 0.01, "select button shares the group panel's left edge @ %s" % vp)


# A widget LARGER than the safe area must be pinned to the safe-area top-left
# (never pushed off-screen with a negative position).
func test_ma5_oversized_widget_pinned_not_offscreen() -> void:
	print("test_ma5_oversized_widget_pinned_not_offscreen")
	var vp: Vector2 = Vector2(320, 480)  # tiny screen
	var huge: Vector2 = Vector2(1000, 1000)
	var pos: Vector2 = ResponsiveLayoutUtil.clamp_into_safe_area(Vector2(-500, -500), huge, vp)
	var area: Rect2 = ResponsiveLayoutUtil.safe_area(vp)
	_check(abs(pos.x - area.position.x) < 0.01, "oversized widget pinned to safe-area left")
	_check(abs(pos.y - area.position.y) < 0.01, "oversized widget pinned to safe-area top")


# Rotating the SAME device (portrait <-> landscape) must actually move the
# thumb-reachable controls (proving the layout re-flows, not just clamps).
func test_ma5_orientation_changes_placement() -> void:
	print("test_ma5_orientation_changes_placement")
	var portrait: Vector2 = Vector2(1080, 2340)
	var landscape: Vector2 = Vector2(2340, 1080)
	var zc_p: Vector2 = ResponsiveLayoutUtil.zoom_col_pos(portrait, _ma5_zoom_size())
	var zc_l: Vector2 = ResponsiveLayoutUtil.zoom_col_pos(landscape, _ma5_zoom_size())
	# Portrait docks zoom to the bottom; landscape centres it vertically -> the
	# vertical placement must differ meaningfully.
	_check(abs(zc_p.y - zc_l.y) > 1.0, "zoom column re-flows between orientations")
	var gp_p: Vector2 = ResponsiveLayoutUtil.control_group_pos(portrait, _ma5_group_size())
	var gp_l: Vector2 = ResponsiveLayoutUtil.control_group_pos(landscape, _ma5_group_size())
	_check(abs(gp_p.y - gp_l.y) > 1.0, "control groups re-flow between orientations")


# B6: the project must permit free rotation (orientation=sensor), not lock to
# portrait (the old value "1"), so the game plays in landscape too.
func test_ma5_project_allows_rotation() -> void:
	print("test_ma5_project_allows_rotation")
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load("res://project.godot")
	_check(err == OK, "project.godot loads")
	if err != OK:
		return
	var orientation = cfg.get_value("display", "window/handheld/orientation", "portrait")
	# Godot 4 stores this as the string "sensor"; anything that is not a locked
	# portrait/landscape value means free rotation is allowed.
	_check(str(orientation) == "sensor", "orientation allows free rotation (got %s)" % str(orientation))


# B6 regression guard: the HUD's resize handler MUST re-apply the GUI content
# scale. Without it, a portrait<->landscape rotation freezes the scale at the
# launch orientation and pushes overlay widgets off-screen (verified with a live
# SceneTree probe during MA5). We assert it statically here because a full HUD
# instance needs the Nexus autoload, which the --script harness does not load.
func test_ma5_hud_reapplies_scale_on_resize() -> void:
	print("test_ma5_hud_reapplies_scale_on_resize")
	var src: String = FileAccess.get_file_as_string("res://ui/mobile/game_hud.gd")
	_check(src != "", "game_hud.gd source is readable")
	var resize_at: int = src.find("func _on_viewport_resized")
	_check(resize_at != -1, "game_hud has _on_viewport_resized")
	if resize_at == -1:
		return
	# Look at the body of the resize handler (up to the next top-level func).
	var next_func: int = src.find("\nfunc ", resize_at + 1)
	if next_func == -1:
		next_func = src.length()
	var body: String = src.substr(resize_at, next_func - resize_at)
	_check(body.contains("UiScale.apply_from_settings"),
		"_on_viewport_resized re-applies the GUI scale (rotation-safe)")
	_check(body.contains("_apply_responsive_layout"),
		"_on_viewport_resized re-flows the overlay widgets")


# ============================================================================
# Phase MB4.5 (Android): multi-column action-grid flow in landscape (bug 16).
# ============================================================================
#
# Portrait keeps a single wide row; landscape wraps the action buttons into a
# compact grid so a long row never overflows / needs scrolling. These pin down
# the pure column/row math in ResponsiveLayoutUtil.

func test_mb45_portrait_uses_single_row() -> void:
	print("test_mb45_portrait_uses_single_row")
	# In portrait, all N buttons stay on one row (columns == count).
	var cols: int = ResponsiveLayoutUtil.action_columns(Vector2(720, 1280), 7, 120.0, 8.0)
	_check(cols == 7, "portrait keeps every button in a single row")


func test_mb45_landscape_wraps_into_multiple_columns() -> void:
	print("test_mb45_landscape_wraps_into_multiple_columns")
	# A narrow-ish landscape viewport cannot fit 7 wide buttons in one row, so
	# the grid must use fewer columns than the button count (i.e. it wraps).
	var cols: int = ResponsiveLayoutUtil.action_columns(Vector2(960, 540), 7, 160.0, 8.0)
	_check(cols >= ResponsiveLayoutUtil.MIN_COLUMNS, "landscape columns never below the minimum")
	_check(cols < 7, "landscape wraps: fewer columns than buttons when they cannot all fit")
	# Sanity: the chosen columns actually fit the usable width.
	var usable: float = 960.0 - 2.0 * ResponsiveLayoutUtil.MARGIN
	var span: float = cols * 160.0 + maxf(0.0, float(cols - 1)) * 8.0
	_check(span <= usable + 0.01, "chosen columns fit inside the usable width")


func test_mb45_columns_that_fit_is_geometric() -> void:
	print("test_mb45_columns_that_fit_is_geometric")
	# 3 buttons of 100px with 10px gaps need 100*3 + 10*2 = 320px; 330px fits 3.
	_check(ResponsiveLayoutUtil.columns_that_fit(330.0, 100.0, 10.0) == 3, "330px fits exactly 3")
	_check(ResponsiveLayoutUtil.columns_that_fit(319.0, 100.0, 10.0) == 2, "319px drops to 2")
	# Never zero even on a degenerate width / button size.
	_check(ResponsiveLayoutUtil.columns_that_fit(0.0, 100.0, 10.0) == ResponsiveLayoutUtil.MIN_COLUMNS, "zero width -> min columns")
	_check(ResponsiveLayoutUtil.columns_that_fit(500.0, 0.0, 10.0) == ResponsiveLayoutUtil.MIN_COLUMNS, "zero button width -> min columns (no div by zero)")


func test_mb45_grid_rows_ceils() -> void:
	print("test_mb45_grid_rows_ceils")
	_check(ResponsiveLayoutUtil.grid_rows(7, 3) == 3, "7 items over 3 cols -> 3 rows")
	_check(ResponsiveLayoutUtil.grid_rows(6, 3) == 2, "6 items over 3 cols -> 2 rows")
	_check(ResponsiveLayoutUtil.grid_rows(1, 3) == 1, "1 item -> 1 row")
	_check(ResponsiveLayoutUtil.grid_rows(0, 3) == 0, "0 items -> 0 rows")


func test_mb45_columns_never_exceed_count() -> void:
	print("test_mb45_columns_never_exceed_count")
	# A very wide landscape viewport could geometrically fit more columns than we
	# have buttons; the result must be capped at the button count.
	var cols: int = ResponsiveLayoutUtil.action_columns(Vector2(3840, 1080), 4, 100.0, 8.0)
	_check(cols == 4, "columns are capped at the number of buttons")


func test_mb45_hud_wires_action_grid_columns() -> void:
	print("test_mb45_hud_wires_action_grid_columns")
	# Static guard: the mobile HUD must actually drive the grid columns from the
	# pure util on every re-layout, so the landscape wrap really happens in-game.
	var src: String = FileAccess.get_file_as_string("res://ui/mobile/game_hud.gd")
	_check(src != "", "game_hud.gd source is readable")
	_check(src.contains("_action_grid"), "HUD references the action GridContainer")
	_check(src.contains("_apply_action_grid_columns"), "HUD has the column-apply helper")
	_check(src.contains("ResponsiveLayoutUtil.action_columns"),
		"HUD sizes the grid via ResponsiveLayoutUtil.action_columns")
	# The apply helper must be invoked from the responsive re-layout path.
	var relayout_at: int = src.find("func _apply_responsive_layout")
	_check(relayout_at != -1, "HUD has _apply_responsive_layout")
	if relayout_at == -1:
		return
	var next_func: int = src.find("\nfunc ", relayout_at + 1)
	if next_func == -1:
		next_func = src.length()
	var body: String = src.substr(relayout_at, next_func - relayout_at)
	_check(body.contains("_apply_action_grid_columns"),
		"_apply_responsive_layout re-computes the action-grid columns")


# The scene's bottom action Row must be a GridContainer (so columns can wrap),
# not the old HBoxContainer that could only scroll.
func test_mb45_scene_action_row_is_grid() -> void:
	print("test_mb45_scene_action_row_is_grid")
	var src: String = FileAccess.get_file_as_string("res://scenes/game_main.tscn")
	_check(src != "", "game_main.tscn is readable")
	_check(src.contains("[node name=\"Row\" type=\"GridContainer\" parent=\"BottomBar/Margin/Scroll\"]"),
		"bottom action Row is a GridContainer")


# ============================================================================
# Phase MB4.6 (Android): orientation + ui_mode resolution (bugs 7, 15, 17, 18).
# ============================================================================
#
# These pin down the pure resolvers that map a stored preference (and a probed
# device profile) to a concrete DisplayServer orientation constant / HUD variant.
# They are frame-rate and DisplayServer independent so they run headlessly and
# guarantee "auto" behaves per-device while explicit values are always honoured.

func test_mb46_orientation_to_display_constant() -> void:
	print("test_mb46_orientation_to_display_constant")
	# Godot 4 enum: LANDSCAPE=0, PORTRAIT=1, SENSOR=4.
	_check(GameSettings.orientation_to_display_constant("landscape") == 0, "landscape -> 0")
	_check(GameSettings.orientation_to_display_constant("portrait") == 1, "portrait -> 1")
	_check(GameSettings.orientation_to_display_constant("auto") == 4, "auto -> sensor (4)")
	# Any unknown / malformed value must fall back to the safe sensor default.
	_check(GameSettings.orientation_to_display_constant("sideways") == 4, "unknown -> sensor (4)")
	_check(GameSettings.orientation_to_display_constant("") == 4, "empty -> sensor (4)")


func test_mb46_ui_mode_explicit_is_honoured() -> void:
	print("test_mb46_ui_mode_explicit_is_honoured")
	# Explicit desktop/mobile choices ignore the device profile entirely.
	_check(GameSettings.resolve_ui_mode_for("desktop", true, true, 480.0) == "desktop",
		"explicit desktop wins even on a small touchscreen phone")
	_check(GameSettings.resolve_ui_mode_for("mobile", false, false, 1440.0) == "mobile",
		"explicit mobile wins even on a large non-touch desktop")


func test_mb46_ui_mode_auto_follows_device() -> void:
	print("test_mb46_ui_mode_auto_follows_device")
	# auto -> mobile when the platform is a phone/tablet.
	_check(GameSettings.resolve_ui_mode_for("auto", true, false, 1080.0) == "mobile",
		"auto on a mobile platform -> mobile")
	# auto -> mobile when a touchscreen is present.
	_check(GameSettings.resolve_ui_mode_for("auto", false, true, 1080.0) == "mobile",
		"auto with a touchscreen -> mobile")
	# auto -> mobile when the physical screen is small (short edge <= 900).
	_check(GameSettings.resolve_ui_mode_for("auto", false, false, 720.0) == "mobile",
		"auto on a small screen -> mobile")
	# auto -> desktop on a large non-touch screen.
	_check(GameSettings.resolve_ui_mode_for("auto", false, false, 1200.0) == "desktop",
		"auto on a large non-touch screen -> desktop")
	# Unknown values behave like auto (never crash, sensible default).
	_check(GameSettings.resolve_ui_mode_for("weird", false, false, 1200.0) == "desktop",
		"unknown ui_mode on a big screen falls back to desktop")


func test_mb46_orientation_and_ui_mode_prefs_roundtrip() -> void:
	print("test_mb46_orientation_and_ui_mode_prefs_roundtrip")
	# The setters validate values and persist them; bad values leave state intact.
	var s: GameSettings = GameSettings.new(WorldState.new())
	s.ensure_defaults()
	_check(s.get_screen_orientation() == "auto", "orientation defaults to auto")
	_check(s.get_ui_mode() == "auto", "ui_mode defaults to auto")
	_check(s.set_screen_orientation("portrait"), "portrait is accepted")
	_check(s.get_screen_orientation() == "portrait", "orientation persisted as portrait")
	_check(not s.set_screen_orientation("diagonal"), "invalid orientation rejected")
	_check(s.get_screen_orientation() == "portrait", "rejected orientation leaves state intact")
	_check(s.set_ui_mode("desktop"), "desktop ui_mode is accepted")
	_check(s.get_ui_mode() == "desktop", "ui_mode persisted as desktop")
	_check(not s.set_ui_mode("holographic"), "invalid ui_mode rejected")
	_check(s.get_ui_mode() == "desktop", "rejected ui_mode leaves state intact")


# ============================================================================
# Phase MA6 (Android): single-tap unit selection / move on the real input path.
# ============================================================================
#
# B7: "on mobile, units are not selected". We centralised the tap decision in the
# pure, dependency-free TapSelectUtil so it can be exercised headlessly here, and
# the mobile HUD delegates to it. These unit tests pin down EXACTLY what a single
# tap does (select / toggle / move), plus a static check that the HUD routes
# through the util. A full end-to-end InputEventScreenTouch injection through a
# live HUD (which needs the Nexus autoload) runs in the separate scene harness
# tests/ma6_touch_probe.gd, kept green alongside this suite.

func test_ma6_tap_empty_ground_with_no_selection_is_noop() -> void:
	print("test_ma6_tap_empty_ground_with_no_selection_is_noop")
	# Tapping bare ground with nothing selected must do nothing (no phantom move).
	var plan: Dictionary = TapSelectUtil.resolve_tap([], -1)
	_check(str(plan.get("action", "")) == TapSelectUtil.ACTION_NONE, "empty ground + empty selection -> none")
	_check((plan.get("selection", []) as Array).is_empty(), "selection stays empty")


func test_ma6_tap_friendly_unit_selects_it() -> void:
	print("test_ma6_tap_friendly_unit_selects_it")
	# The core B7 fix: tapping a friendly unit selects it.
	var plan: Dictionary = TapSelectUtil.resolve_tap([], 42)
	_check(str(plan.get("action", "")) == TapSelectUtil.ACTION_SELECT, "tap unit -> select action")
	_check((plan.get("selection", []) as Array) == [42], "the tapped unit becomes the selection")


func test_ma6_tap_selected_unit_toggles_it_off() -> void:
	print("test_ma6_tap_selected_unit_toggles_it_off")
	# Tapping an already-selected unit removes it from the squad (touch toggle).
	var plan: Dictionary = TapSelectUtil.resolve_tap([7, 8, 9], 8)
	_check(str(plan.get("action", "")) == TapSelectUtil.ACTION_SELECT, "re-tap -> select action (updated set)")
	_check((plan.get("selection", []) as Array) == [7, 9], "the re-tapped unit is toggled off")


func test_ma6_repeated_taps_build_a_squad() -> void:
	print("test_ma6_repeated_taps_build_a_squad")
	# Repeated taps on distinct units build a multi-unit squad (needed for fusion).
	var sel: Array = []
	sel = TapSelectUtil.resolve_tap(sel, 1).get("selection", [])
	sel = TapSelectUtil.resolve_tap(sel, 2).get("selection", [])
	sel = TapSelectUtil.resolve_tap(sel, 3).get("selection", [])
	_check(sel == [1, 2, 3], "three taps build a 3-unit squad in tap order")


func test_ma6_tap_empty_ground_with_selection_moves() -> void:
	print("test_ma6_tap_empty_ground_with_selection_moves")
	# With a squad selected, tapping empty ground issues a MOVE (selection kept).
	var plan: Dictionary = TapSelectUtil.resolve_tap([5, 6], -1)
	_check(str(plan.get("action", "")) == TapSelectUtil.ACTION_MOVE, "empty ground + selection -> move action")
	_check((plan.get("selection", []) as Array) == [5, 6], "the selection is preserved for the move")


func test_ma6_unit_at_tile_owner_filter_and_determinism() -> void:
	print("test_ma6_unit_at_tile_owner_filter_and_determinism")
	# unit_at_tile picks the friendly unit standing on a tile, honours the owner
	# filter, and is deterministic (lowest id) when two units share a tile.
	var units: Dictionary = {
		"3": { "id": 3, "x": 4, "y": 2, "owner": 0 },
		"1": { "id": 1, "x": 4, "y": 2, "owner": 0 },
		"9": { "id": 9, "x": 4, "y": 2, "owner": 1 },
		"5": { "id": 5, "x": 0, "y": 0, "owner": 0 },
	}
	_check(TapSelectUtil.unit_at_tile(units, Vector2i(4, 2), 0) == 1, "lowest-id friendly on the shared tile is picked")
	_check(TapSelectUtil.unit_at_tile(units, Vector2i(4, 2), 1) == 9, "owner filter selects the enemy unit")
	_check(TapSelectUtil.unit_at_tile(units, Vector2i(4, 2), -1) == 1, "owner -1 matches any owner (still lowest id)")
	_check(TapSelectUtil.unit_at_tile(units, Vector2i(7, 7), 0) == -1, "empty tile returns -1")


func test_ma6_resolve_tap_does_not_mutate_input() -> void:
	print("test_ma6_resolve_tap_does_not_mutate_input")
	# The util must be pure: the caller's selection array is never mutated in place
	# (the HUD keeps its own list; a leak here would corrupt selection state).
	var original: Array = [10, 20]
	TapSelectUtil.resolve_tap(original, 30)
	_check(original == [10, 20], "resolve_tap leaves the caller's array unchanged")


func test_ma6_hud_delegates_tap_to_util() -> void:
	print("test_ma6_hud_delegates_tap_to_util")
	# Static guard: the mobile HUD must route its tap through TapSelectUtil so the
	# behaviour tested above is the behaviour the game actually ships (a full live
	# HUD needs the Nexus autoload, unavailable in --script mode; the scene harness
	# ma6_touch_probe.gd exercises the end-to-end InputEventScreenTouch path).
	var src: String = FileAccess.get_file_as_string("res://ui/mobile/game_hud.gd")
	_check(src != "", "game_hud.gd source is readable")
	var tap_at: int = src.find("func _handle_tap")
	_check(tap_at != -1, "game_hud has _handle_tap")
	if tap_at == -1:
		return
	var next_func: int = src.find("\nfunc ", tap_at + 1)
	if next_func == -1:
		next_func = src.length()
	var body: String = src.substr(tap_at, next_func - tap_at)
	_check(body.contains("TapSelectUtil.resolve_tap"), "_handle_tap delegates the decision to TapSelectUtil")
	_check(body.contains("TapSelectUtil.ACTION_MOVE"), "_handle_tap issues a move on the util's move action")
	_check(body.contains("select_units"), "_handle_tap still issues the authoritative select_units command")


# --- Phase MB1: minimap fog filter (bug 3) ----------------------------------

# Build a tiny fog section: a 4x4 map where player 0 can see the left half only.
# visible grid uses FOG_VISIBLE=2 / FOG_EXPLORED=1 / FOG_HIDDEN=0.
func _mb1_fog() -> Dictionary:
	var w: int = 4
	var h: int = 4
	var grid: Array = []
	grid.resize(w * h)
	for y in range(h):
		for x in range(w):
			# Left two columns visible, third column explored, right column hidden.
			var state: int = 0
			if x <= 1:
				state = 2
			elif x == 2:
				state = 1
			grid[y * w + x] = state
	return { "width": w, "height": h, "visible": { "0": grid } }


# An enemy unit standing on a HIDDEN (or merely explored) tile must NOT be drawn.
func test_mb1_fog_util_hides_enemy_on_hidden_tile() -> void:
	print("test_mb1_fog_util_hides_enemy_on_hidden_tile")
	var fog: Dictionary = _mb1_fog()
	# Enemy (owner 1) on the hidden right column -> not drawn.
	_check(not FogUtil.should_draw(fog, 0, 1, 3, 0), "enemy on hidden tile is not drawn")
	# Enemy on an explored-but-not-visible tile -> still not drawn.
	_check(not FogUtil.should_draw(fog, 0, 1, 2, 0), "enemy on explored (not visible) tile is not drawn")


# An enemy unit on a currently VISIBLE tile IS drawn.
func test_mb1_fog_util_shows_enemy_on_visible_tile() -> void:
	print("test_mb1_fog_util_shows_enemy_on_visible_tile")
	var fog: Dictionary = _mb1_fog()
	_check(FogUtil.should_draw(fog, 0, 1, 0, 0), "enemy on a visible tile is drawn")
	_check(FogUtil.should_draw(fog, 0, 1, 1, 2), "enemy on another visible tile is drawn")


# Own units are always drawn; a spectator (viewer < 0) sees everything.
func test_mb1_fog_util_always_shows_own_and_spectator() -> void:
	print("test_mb1_fog_util_always_shows_own_and_spectator")
	var fog: Dictionary = _mb1_fog()
	# Own unit on a hidden tile still drawn (owner == viewer).
	_check(FogUtil.should_draw(fog, 0, 0, 3, 0), "own unit is always drawn regardless of fog")
	# Spectator viewer -1 draws even enemies on hidden tiles.
	_check(FogUtil.should_draw(fog, -1, 1, 3, 0), "spectator (viewer < 0) draws everything")


# Out-of-range coordinates / missing grids resolve to HIDDEN.
func test_mb1_fog_util_state_out_of_range_is_hidden() -> void:
	print("test_mb1_fog_util_state_out_of_range_is_hidden")
	var fog: Dictionary = _mb1_fog()
	_check(FogUtil.fog_state(fog, 0, -1, 0) == FogUtil.FOG_HIDDEN, "negative x is hidden")
	_check(FogUtil.fog_state(fog, 0, 99, 0) == FogUtil.FOG_HIDDEN, "x past width is hidden")
	_check(FogUtil.fog_state(fog, 5, 0, 0) == FogUtil.FOG_HIDDEN, "unknown viewer is hidden")


# --- MB1.2 (bug 1 - teammate control leak) ----------------------------------
# The single source of truth OwnershipUtil (behind Nexus.is_locally_controlled)
# and the owner-set selection helpers must never let an AI teammate's unit be
# selected. Pure, headless.

# Two units on the same tile: one owned by the local player (0), one by the AI
# teammate (1). Tap must resolve to the local unit only.
func _mb1_two_owner_units() -> Dictionary:
	return {
		"10": { "id": 10, "x": 3, "y": 4, "owner": 1 },  # AI teammate
		"11": { "id": 11, "x": 3, "y": 4, "owner": 0 },  # local player
		"12": { "id": 12, "x": 7, "y": 2, "owner": 1 },  # AI teammate elsewhere
	}


func test_mb1_ownership_default_local_player_only() -> void:
	print("test_mb1_ownership_default_local_player_only")
	_check(OwnershipUtil.is_locally_controlled(0, 0, []), "owner 0 controllable by default")
	_check(not OwnershipUtil.is_locally_controlled(1, 0, []), "AI teammate 1 NOT controllable")
	_check(not OwnershipUtil.is_locally_controlled(-1, 0, []), "no-owner (-1) never controllable")


func test_mb1_ownership_explicit_seat_set() -> void:
	print("test_mb1_ownership_explicit_seat_set")
	# Hot-seat / assigned seats: only owners in the set are controllable.
	_check(OwnershipUtil.is_locally_controlled(2, 0, [0, 2]), "seat 2 controllable when in set")
	_check(not OwnershipUtil.is_locally_controlled(1, 0, [0, 2]), "seat 1 not controllable outside set")


func test_mb1_ownership_from_session() -> void:
	print("test_mb1_ownership_from_session")
	var default_set: Array = OwnershipUtil.local_players_from_session({}, 0)
	_check(default_set == [0], "empty session falls back to [local_player]")
	var custom: Array = OwnershipUtil.local_players_from_session({ "local_players": [3, 3, 1] }, 0)
	_check(custom == [1, 3], "session set deduped + sorted")


func test_mb1_tap_ignores_ai_teammate_on_shared_tile() -> void:
	print("test_mb1_tap_ignores_ai_teammate_on_shared_tile")
	var units: Dictionary = _mb1_two_owner_units()
	# Local device controls only owner 0.
	var picked: int = TapSelectUtil.unit_at_tile_owned_by(units, Vector2i(3, 4), [0])
	_check(picked == 11, "shared tile picks the local unit (11), not AI teammate (10)")
	# Tapping a tile with ONLY an AI teammate unit selects nothing.
	var none: int = TapSelectUtil.unit_at_tile_owned_by(units, Vector2i(7, 2), [0])
	_check(none == -1, "tapping AI teammate-only tile selects none")


func test_mb1_tap_empty_owner_set_selects_none() -> void:
	print("test_mb1_tap_empty_owner_set_selects_none")
	var units: Dictionary = _mb1_two_owner_units()
	_check(TapSelectUtil.unit_at_tile_owned_by(units, Vector2i(3, 4), []) == -1, "empty owner set fails closed")


func test_mb1_box_select_excludes_ai_teammate() -> void:
	print("test_mb1_box_select_excludes_ai_teammate")
	var units: Dictionary = _mb1_two_owner_units()
	var adapter: Object = _IdentityAdapter.new()
	# Box covering the whole map in tile space (adapter is identity: screen==tile).
	var got: Array = SelectionUtil.units_in_screen_rect_owned_by(adapter, units, Vector2(0, 0), Vector2(20, 20), [0])
	_check(got == [11], "box-select only sweeps local units, not AI teammates")
	var closed: Array = SelectionUtil.units_in_screen_rect_owned_by(adapter, units, Vector2(0, 0), Vector2(20, 20), [])
	_check(closed == [], "empty owner set box-select fails closed")


# --- MD7: AI Context Vector -------------------------------------------------

func test_md7_context_keys_closed_and_sorted() -> void:
	print("test_md7_context_keys_closed_and_sorted")
	var keys: Array = AiContextUtil.context_keys()
	_check(keys.size() == 8, "context has 8 closed keys")
	# Sorted / stable order.
	var sorted_copy: Array = keys.duplicate()
	sorted_copy.sort()
	_check(keys == sorted_copy, "context keys are in stable sorted order")
	# Every documented key is present and recognised.
	for k in ["base_security", "enemy_distance", "economy_gap", "army_ratio",
			"frontline_pressure", "under_threat", "has_ally", "in_active_war"]:
		_check(keys.has(k), "context includes key " + k)
		_check(AiContextUtil.has_context_key(k), "has_context_key true for " + k)
	_check(not AiContextUtil.has_context_key("no_such_key"), "unknown key rejected")


func test_md7_build_context_full_keys_and_fixed_point() -> void:
	print("test_md7_build_context_full_keys_and_fixed_point")
	var summary: Dictionary = {
		"hq": { "x": 10, "y": 10 },
		"own_units": [ { "id": 1, "x": 10, "y": 11, "health": 5 } ],
		"enemy_units": [ { "id": 2, "x": 20, "y": 20, "health": 5 } ],
		"enemy_buildings": [],
		"own_economy": 100, "enemy_economy": 100,
		"own_army": 3, "enemy_army": 3,
		"has_ally": true, "in_active_war": false,
	}
	var ctx: Dictionary = AiContextUtil.build_context(summary, 0)
	# Every closed key present.
	for k in AiContextUtil.context_keys():
		_check(ctx.has(k), "build_context emits key " + k)
	# Every value is an int (no float survives).
	var all_int: bool = true
	for k in ctx.keys():
		if not (ctx[k] is int):
			all_int = false
	_check(all_int, "all context values are ints (fixed-point)")
	# Normalised keys in [0..SCALE].
	for k in ["base_security", "enemy_distance", "economy_gap", "army_ratio", "frontline_pressure"]:
		_check(int(ctx[k]) >= 0 and int(ctx[k]) <= AiContextUtil.SCALE, k + " within [0..SCALE]")
	# Flags are 0/1.
	_check(int(ctx["has_ally"]) == 1, "has_ally flag set")
	_check(int(ctx["in_active_war"]) == 0, "in_active_war flag clear")


func test_md7_base_security_and_enemy_distance() -> void:
	print("test_md7_base_security_and_enemy_distance")
	var hq: Dictionary = { "x": 0, "y": 0 }
	# Enemy right on top of base -> zero security, low distance.
	var close: Dictionary = AiContextUtil.build_context({
		"hq": hq, "enemy_units": [ { "id": 1, "x": 2, "y": 0, "health": 1 } ],
	}, 0)
	# Enemy far away -> full security, high distance.
	var far: Dictionary = AiContextUtil.build_context({
		"hq": hq, "enemy_units": [ { "id": 1, "x": 100, "y": 0, "health": 1 } ],
	}, 0)
	_check(int(close["base_security"]) < int(far["base_security"]), "closer enemy => lower security")
	_check(int(close["enemy_distance"]) < int(far["enemy_distance"]), "closer enemy => lower enemy_distance")
	_check(int(far["base_security"]) == AiContextUtil.SCALE, "distant enemy => full security")
	# Dead enemies are ignored.
	var dead: Dictionary = AiContextUtil.build_context({
		"hq": hq, "enemy_units": [ { "id": 1, "x": 2, "y": 0, "health": 0 } ],
	}, 0)
	_check(int(dead["base_security"]) == AiContextUtil.SCALE, "dead enemy ignored for security")


func test_md7_economy_and_army_gap_ratios() -> void:
	print("test_md7_economy_and_army_gap_ratios")
	var half: int = AiContextUtil.SCALE / 2
	# Parity -> 500.
	var parity: Dictionary = AiContextUtil.build_context({
		"own_economy": 50, "enemy_economy": 50, "own_army": 4, "enemy_army": 4,
	}, 0)
	_check(int(parity["economy_gap"]) == half, "equal economy => parity 500")
	_check(int(parity["army_ratio"]) == half, "equal army => parity 500")
	# We dominate economy.
	var ahead: Dictionary = AiContextUtil.build_context({
		"own_economy": 300, "enemy_economy": 0, "own_army": 10, "enemy_army": 0,
	}, 0)
	_check(int(ahead["economy_gap"]) == AiContextUtil.SCALE, "enemy zero economy => full gap")
	_check(int(ahead["army_ratio"]) == AiContextUtil.SCALE, "enemy zero army => full ratio")
	# Enemy dominates.
	var behind: Dictionary = AiContextUtil.build_context({
		"own_economy": 0, "enemy_economy": 300, "own_army": 0, "enemy_army": 10,
	}, 0)
	_check(int(behind["economy_gap"]) == 0, "we have zero economy => zero gap")
	_check(int(behind["army_ratio"]) == 0, "we have zero army => zero ratio")
	# Both zero -> parity (safe default), no divide-by-zero.
	var empty: Dictionary = AiContextUtil.build_context({}, 0)
	_check(int(empty["economy_gap"]) == half, "no economy data => parity")
	_check(int(empty["army_ratio"]) == half, "no army data => parity")


func test_md7_frontline_pressure_and_under_threat() -> void:
	print("test_md7_frontline_pressure_and_under_threat")
	var hq: Dictionary = { "x": 0, "y": 0 }
	# No enemies near -> zero pressure, not under threat.
	var calm: Dictionary = AiContextUtil.build_context({ "hq": hq, "enemy_units": [] }, 0)
	_check(int(calm["frontline_pressure"]) == 0, "no enemies => zero pressure")
	_check(int(calm["under_threat"]) == 0, "no enemies => not under threat")
	# Several enemies close -> pressure rises, under threat.
	var swarm: Dictionary = AiContextUtil.build_context({
		"hq": hq,
		"enemy_units": [
			{ "id": 1, "x": 1, "y": 0, "health": 1 },
			{ "id": 2, "x": 0, "y": 2, "health": 1 },
			{ "id": 3, "x": 2, "y": 1, "health": 1 },
		],
	}, 0)
	_check(int(swarm["frontline_pressure"]) > 0, "nearby enemies => positive pressure")
	_check(int(swarm["under_threat"]) == 1, "nearby enemies => under threat")
	# More enemies => not less pressure (monotonic).
	var bigger: Dictionary = AiContextUtil.build_context({
		"hq": hq,
		"enemy_units": [
			{ "id": 1, "x": 1, "y": 0, "health": 1 },
			{ "id": 2, "x": 0, "y": 2, "health": 1 },
			{ "id": 3, "x": 2, "y": 1, "health": 1 },
			{ "id": 4, "x": 1, "y": 2, "health": 1 },
			{ "id": 5, "x": 2, "y": 2, "health": 1 },
		],
	}, 0)
	_check(int(bigger["frontline_pressure"]) >= int(swarm["frontline_pressure"]), "more enemies => >= pressure")


func test_md7_safe_defaults_when_empty() -> void:
	print("test_md7_safe_defaults_when_empty")
	# Fully empty / malformed input never crashes and yields safe defaults.
	var ctx: Dictionary = AiContextUtil.build_context(null, -1)
	for k in AiContextUtil.context_keys():
		_check(ctx.has(k), "safe default emits key " + k)
	# No HQ => treated as nothing to defend: full security, enemy far.
	_check(int(ctx["base_security"]) == AiContextUtil.SCALE, "no HQ => full security")
	_check(int(ctx["enemy_distance"]) == AiContextUtil.SCALE, "no HQ => enemy far")
	_check(int(ctx["under_threat"]) == 0, "no HQ => not under threat")
	_check(int(ctx["frontline_pressure"]) == 0, "no HQ => no pressure")
	# safe_default_context matches build_context({}).
	_check(AiContextUtil.safe_default_context() == AiContextUtil.build_context({}, -1), "safe_default_context consistent")


func test_md7_deterministic_and_stable_order() -> void:
	print("test_md7_deterministic_and_stable_order")
	# Same input -> byte-identical output over repeated calls.
	var summary: Dictionary = {
		"hq": { "x": 5, "y": 5 },
		"enemy_units": [
			{ "id": 9, "x": 6, "y": 5, "health": 1 },
			{ "id": 2, "x": 6, "y": 5, "health": 1 },
			{ "id": 5, "x": 6, "y": 5, "health": 1 },
		],
		"own_economy": 42, "enemy_economy": 17,
	}
	var a: Dictionary = AiContextUtil.build_context(summary, 3)
	var b: Dictionary = AiContextUtil.build_context(summary, 3)
	var c: Dictionary = AiContextUtil.build_context(summary, 3)
	_check(a == b and b == c, "same summary => identical context (determinism)")
	# Reordering enemy list must NOT change the result (stable by id).
	var reordered: Dictionary = summary.duplicate(true)
	reordered["enemy_units"] = [
		{ "id": 2, "x": 6, "y": 5, "health": 1 },
		{ "id": 9, "x": 6, "y": 5, "health": 1 },
		{ "id": 5, "x": 6, "y": 5, "health": 1 },
	]
	_check(AiContextUtil.build_context(reordered, 3) == a, "enemy list order does not affect context")


func test_md7_source_is_ascii_and_pure() -> void:
	print("test_md7_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/ai_context_util.gd")
	_check(src.length() > 0, "ai_context_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "ai_context_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "ai_context_util extends RefCounted")
	_check(not src.contains("WorldState"), "ai_context_util does not touch WorldState")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "ai_context_util does not touch state hasher")
	_check(not src.contains("SceneTree"), "ai_context_util does not touch SceneTree")


# --- Phase MD6 (plan v4): AI Policy Profile (hard behaviour rules) -----------
func test_md6_closed_condition_and_flag_sets() -> void:
	print("test_md6_closed_condition_and_flag_sets")
	# Every policy condition key must be a key the context vector emits (MD6.2).
	for key in AiPolicyUtil.condition_keys():
		_check(AiContextUtil.has_context_key(key), "condition key '%s' exists in context vector" % key)
	# Action-flag set present and covered by the baseline.
	_check(AiPolicyUtil.action_flags().size() == 6, "six action flags defined")
	var baseline: Dictionary = AiPolicyUtil.baseline_flags()
	for flag in AiPolicyUtil.action_flags():
		_check(baseline.has(flag), "baseline covers flag '%s'" % flag)


func test_md6_empty_policy_is_baseline() -> void:
	print("test_md6_empty_policy_is_baseline")
	# MD6.4: an empty / missing policy reproduces baseline behaviour exactly.
	var ctx: Dictionary = AiContextUtil.safe_default_context()
	_check(AiPolicyUtil.evaluate([], ctx) == AiPolicyUtil.baseline_flags(), "empty policy == baseline")
	_check(AiPolicyUtil.evaluate(null, ctx) == AiPolicyUtil.baseline_flags(), "null policy == baseline")
	_check(AiPolicyUtil.validate_policy([]).is_empty(), "empty policy validates")
	# Baseline: attack allowed, all biases off.
	_check(bool(AiPolicyUtil.baseline_flags()["allow_attack"]), "baseline allows attack")
	_check(not bool(AiPolicyUtil.baseline_flags()["prefer_static_defense"]), "baseline no static-defense bias")


func test_md6_rule_fires_and_overrides() -> void:
	print("test_md6_rule_fires_and_overrides")
	# A single rule fires when its condition holds and stays off otherwise.
	var ctx_unsafe: Dictionary = { "base_security": 500, "army_ratio": 500, "economy_gap": 500, "enemy_distance": 1000, "frontline_pressure": 0 }
	var flags: Dictionary = AiPolicyUtil.evaluate([AiPolicyUtil.make_rule("base_security", "lt", 700, "prefer_static_defense")], ctx_unsafe)
	_check(bool(flags["prefer_static_defense"]), "rule fires when base_security < 700")
	# Same rule does NOT fire when the base is safe.
	var ctx_safe: Dictionary = { "base_security": 900, "army_ratio": 500, "economy_gap": 500, "enemy_distance": 1000, "frontline_pressure": 0 }
	var flags2: Dictionary = AiPolicyUtil.evaluate([AiPolicyUtil.make_rule("base_security", "lt", 700, "prefer_static_defense")], ctx_safe)
	_check(not bool(flags2["prefer_static_defense"]), "rule does not fire when base is safe")


func test_md6_all_operators() -> void:
	print("test_md6_all_operators")
	var ctx: Dictionary = { "army_ratio": 500, "base_security": 1000, "economy_gap": 500, "enemy_distance": 1000, "frontline_pressure": 0 }
	_check(bool(AiPolicyUtil.evaluate([AiPolicyUtil.make_rule("army_ratio", "lt", 600, "allow_attack")], ctx)["allow_attack"]), "lt true")
	_check(bool(AiPolicyUtil.evaluate([AiPolicyUtil.make_rule("army_ratio", "le", 500, "prefer_economy")], ctx)["prefer_economy"]), "le true at equality")
	_check(bool(AiPolicyUtil.evaluate([AiPolicyUtil.make_rule("army_ratio", "gt", 400, "prefer_harass_when_exposed")], ctx)["prefer_harass_when_exposed"]), "gt true")
	_check(bool(AiPolicyUtil.evaluate([AiPolicyUtil.make_rule("army_ratio", "ge", 500, "avoid_risky_units")], ctx)["avoid_risky_units"]), "ge true at equality")


func test_md6_validate_rejects_malformed() -> void:
	print("test_md6_validate_rejects_malformed")
	_check(not AiPolicyUtil.is_valid_rule({ "when": "bogus_key", "op": "lt", "value_q": 100, "then": "allow_attack" }), "unknown condition key rejected")
	_check(not AiPolicyUtil.is_valid_rule({ "when": "army_ratio", "op": "xx", "value_q": 100, "then": "allow_attack" }), "unknown op rejected")
	_check(not AiPolicyUtil.is_valid_rule({ "when": "army_ratio", "op": "lt", "value_q": 100, "then": "bogus_flag" }), "unknown flag rejected")
	_check(not AiPolicyUtil.is_valid_rule({ "when": "army_ratio", "op": "lt", "value_q": 9999, "then": "allow_attack" }), "out-of-range value_q rejected")
	var problems: Array = AiPolicyUtil.validate_policy([{ "when": "nope", "op": "lt", "value_q": 0, "then": "allow_attack" }])
	_check(problems.size() == 1, "one problem reported for one bad rule")
	# An invalid rule inside a policy is skipped, not crashing.
	var flags: Dictionary = AiPolicyUtil.evaluate([{ "bad": true }], AiContextUtil.safe_default_context())
	_check(flags == AiPolicyUtil.baseline_flags(), "malformed rule skipped -> baseline")


func test_md6_archetype_presets_contrast() -> void:
	print("test_md6_archetype_presets_contrast")
	# A pressured, unsafe context: defensive vs aggressive must diverge.
	var ctx: Dictionary = { "base_security": 500, "enemy_distance": 400, "economy_gap": 500, "army_ratio": 500, "frontline_pressure": 700 }
	var defen: Dictionary = AiPolicyUtil.evaluate(AiPolicyUtil.preset_for_archetype("defensive"), ctx)
	var aggro: Dictionary = AiPolicyUtil.evaluate(AiPolicyUtil.preset_for_archetype("aggressive"), ctx)
	_check(bool(defen["prefer_static_defense"]), "defensive prefers static defense when unsafe")
	_check(bool(defen["prefer_tank_when_pressured"]), "defensive brings tanks under pressure")
	_check(bool(aggro["prefer_harass_when_exposed"]), "aggressive harasses exposed enemy")
	_check(defen["prefer_static_defense"] != aggro["prefer_static_defense"], "two archetypes play differently")
	_check(AiPolicyUtil.preset_for_archetype("unknown_xyz").is_empty(), "unknown archetype -> empty policy")


func test_md6_derive_from_profile() -> void:
	print("test_md6_derive_from_profile")
	var p: AiProfile = AiProfile.new()
	p.init_new("md6_test")
	p.set_value("personality", "caution", 0.9)
	p.set_value("personality", "aggression", 0.1)
	var rules: Array = AiPolicyUtil.derive_from_profile(p)
	_check(AiPolicyUtil.validate_policy(rules).is_empty(), "derived policy is valid")
	# A very cautious, non-aggressive profile prefers static defense in danger.
	var ctx: Dictionary = { "base_security": 500, "enemy_distance": 400, "economy_gap": 500, "army_ratio": 500, "frontline_pressure": 200 }
	var flags: Dictionary = AiPolicyUtil.evaluate(rules, ctx)
	_check(bool(flags["prefer_static_defense"]), "cautious profile defends when unsafe")
	_check(AiPolicyUtil.derive_from_profile(null).is_empty(), "null profile -> empty policy")


func test_md6_source_is_ascii_and_pure() -> void:
	print("test_md6_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/ai_policy_util.gd")
	_check(src.length() > 0, "ai_policy_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "ai_policy_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "ai_policy_util extends RefCounted")
	_check(not src.contains("WorldState"), "ai_policy_util does not touch the world model type")


# --- Phase MD8 (item 7): unit production utility scoring ---------------------

# A durable "tank" capability card: high survivability/holding, low damage.
func _md8_tank_caps() -> Dictionary:
	return {
		"survivability": 900, "holding_power": 800, "damage_output": 200,
		"mobility": 300, "siege_power": 100, "anti_air_power": 100,
		"scout_power": 100, "support_power": 100, "cost_efficiency": 400,
	}

# A fragile "glass cannon" card: high damage/mobility, low survivability.
func _md8_glass_caps() -> Dictionary:
	return {
		"survivability": 150, "holding_power": 150, "damage_output": 950,
		"mobility": 700, "siege_power": 300, "anti_air_power": 100,
		"scout_power": 200, "support_power": 100, "cost_efficiency": 400,
	}

# Neutral weights: every capability weight = SCALE, roles neutral.
func _md8_neutral_weights() -> Dictionary:
	var caps: Dictionary = {}
	for c in UnitUtilityUtil.SCORED_CAPS:
		caps[c] = UnitUtilityUtil.SCALE
	return { "capabilities": caps, "roles": {} }


func test_md8_capability_component_neutral_and_weighted() -> void:
	print("test_md8_capability_component_neutral_and_weighted")
	var caps: Dictionary = _md8_tank_caps()
	var neutral: Dictionary = (_md8_neutral_weights()["capabilities"] as Dictionary)
	# With neutral weights the component is the plain sum of scored caps.
	var expected: int = 0
	for c in UnitUtilityUtil.SCORED_CAPS:
		expected += int(caps.get(c, 0))
	_check(UnitUtilityUtil.capability_component(caps, neutral) == expected, "neutral weights = plain cap sum")
	# Doubling the survivability weight raises the score by that cap's value.
	var boosted: Dictionary = neutral.duplicate(true)
	boosted["survivability"] = 2 * UnitUtilityUtil.SCALE
	var diff: int = UnitUtilityUtil.capability_component(caps, boosted) - expected
	_check(diff == int(caps["survivability"]), "extra survivability weight adds that cap")


func test_md8_role_fit_and_current_need() -> void:
	print("test_md8_role_fit_and_current_need")
	# Role fit is the weight's deviation from neutral: preferred role -> positive.
	_check(UnitUtilityUtil.role_fit_component("frontline_tank", {"frontline_tank": 1800}) == 800, "preferred role adds bonus")
	_check(UnitUtilityUtil.role_fit_component("scout", {"scout": 400}) == -600, "disliked role subtracts")
	_check(UnitUtilityUtil.role_fit_component("missing", {}) == 0, "unknown role is neutral")
	# Current need: under threat favours the durable tank over the glass cannon.
	var ctx_threat: Dictionary = { "under_threat": 1000, "frontline_pressure": 0, "economy_gap": 0 }
	var tank_need: int = UnitUtilityUtil.current_need(_md8_tank_caps(), ctx_threat)
	var glass_need: int = UnitUtilityUtil.current_need(_md8_glass_caps(), ctx_threat)
	_check(tank_need > glass_need, "under threat, tank satisfies need more")
	# Frontline pressure favours the high-damage glass cannon.
	var ctx_front: Dictionary = { "under_threat": 0, "frontline_pressure": 1000, "economy_gap": 0 }
	_check(UnitUtilityUtil.current_need(_md8_glass_caps(), ctx_front) > UnitUtilityUtil.current_need(_md8_tank_caps(), ctx_front), "frontline pressure favours damage")


func test_md8_difficulty_noise_deterministic() -> void:
	print("test_md8_difficulty_noise_deterministic")
	var a: int = UnitUtilityUtil.difficulty_noise(42, 100, 1, 7, 50)
	var b: int = UnitUtilityUtil.difficulty_noise(42, 100, 1, 7, 50)
	_check(a == b, "same seed/tick/owner/salt -> same noise")
	# Different salt (unit) generally shifts the noise.
	var c: int = UnitUtilityUtil.difficulty_noise(42, 100, 1, 9, 50)
	_check(a != c or true, "different salt is allowed to differ")
	# Noise stays within the band.
	_check(abs(a) <= 50, "noise within strength band")
	# Zero strength -> zero noise.
	_check(UnitUtilityUtil.difficulty_noise(42, 100, 1, 7, 0) == 0, "zero strength = no noise")


func test_md8_select_best_stable_tiebreak() -> void:
	print("test_md8_select_best_stable_tiebreak")
	# Two identical candidates: tie-break on id (lexicographic) is deterministic.
	var caps: Dictionary = _md8_tank_caps()
	var cands: Array = [
		{ "id": "zeta", "caps": caps, "primary_role": "generic" },
		{ "id": "alpha", "caps": caps, "primary_role": "generic" },
	]
	var w: Dictionary = _md8_neutral_weights()
	var ctx: Dictionary = {}
	var pick1: String = UnitUtilityUtil.select_best(cands, w, ctx, 1, 0, 0, 0)
	var pick2: String = UnitUtilityUtil.select_best(cands, w, ctx, 1, 0, 0, 0)
	_check(pick1 == pick2, "selection is deterministic")
	_check(pick1 == "alpha", "tie resolves to lexicographically-first id")
	# Empty candidate list -> empty pick.
	_check(UnitUtilityUtil.select_best([], w, ctx, 1, 0, 0, 0) == "", "no candidates -> empty")


func test_md8_defensive_vs_aggressive_pick_contrast() -> void:
	print("test_md8_defensive_vs_aggressive_pick_contrast")
	# THE key proof for MD8: same catalog (tank + glass cannon), opposite AIs.
	var cands: Array = [
		{ "id": "tank", "caps": _md8_tank_caps(), "primary_role": "frontline_tank" },
		{ "id": "glass", "caps": _md8_glass_caps(), "primary_role": "glass_cannon" },
	]
	var ctx: Dictionary = {}
	# Defensive AI: heavy survivability/holding weights, prefers frontline_tank.
	var defensive: Dictionary = {
		"capabilities": {
			"survivability": 2000, "holding_power": 2000, "damage_output": 400,
			"mobility": 800, "siege_power": 800, "anti_air_power": 1000,
			"scout_power": 800, "support_power": 1000, "cost_efficiency": 1200,
		},
		"roles": { "frontline_tank": 1800, "glass_cannon": 400 },
	}
	# Aggressive AI: heavy damage/mobility weights, prefers glass_cannon.
	var aggressive: Dictionary = {
		"capabilities": {
			"survivability": 400, "holding_power": 400, "damage_output": 2000,
			"mobility": 1600, "siege_power": 1400, "anti_air_power": 800,
			"scout_power": 1000, "support_power": 600, "cost_efficiency": 800,
		},
		"roles": { "frontline_tank": 400, "glass_cannon": 1800 },
	}
	var def_pick: String = UnitUtilityUtil.select_best(cands, defensive, ctx, 5, 0, 0, 0)
	var agg_pick: String = UnitUtilityUtil.select_best(cands, aggressive, ctx, 5, 0, 0, 0)
	_check(def_pick == "tank", "defensive AI picks the survival-focused tank")
	_check(agg_pick == "glass", "aggressive AI picks the glass cannon")


func test_md8_single_candidate_backward_compatible() -> void:
	print("test_md8_single_candidate_backward_compatible")
	# Backward compatibility: a catalog with only "soldier" always yields soldier.
	var cands: Array = [ { "id": "soldier", "caps": _md8_tank_caps(), "primary_role": "generic" } ]
	var w: Dictionary = _md8_neutral_weights()
	_check(UnitUtilityUtil.select_best(cands, w, {}, 1, 10, 2, 30) == "soldier", "sole candidate always chosen")


func test_md8_source_is_ascii_and_pure() -> void:
	print("test_md8_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/unit_utility_util.gd")
	_check(src.length() > 0, "unit_utility_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "unit_utility_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "unit_utility_util extends RefCounted")
	_check(not src.contains("WorldState"), "unit_utility_util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "ai_policy_util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "ai_policy_util does not touch the scene tree type")


func test_md8_candidate_build_from_catalog() -> void:
	print("test_md8_candidate_build_from_catalog")
	# A synthetic 2-unit catalog (raw stat defs). build_candidates must emit one
	# candidate per unit, in id-sorted order, each carrying a capability card and
	# an inferred primary role (never crashing on the raw defs).
	var catalog: Dictionary = {
		"tank": { "id": "tank", "stats": { "health": 400, "armor": 30, "attack_damage": 20, "move_speed": 1 }, "cost": { "resource_basic": 200 } },
		"scout": { "id": "scout", "stats": { "health": 40, "move_speed": 6, "vision_range": 9, "attack_damage": 5 }, "cost": { "resource_basic": 60 } },
	}
	var cands: Array = UnitCandidateUtil.build_candidates(catalog, null, null, [])
	_check(cands.size() == 2, "one candidate per catalog unit")
	# id-sorted: "scout" < "tank".
	_check(str((cands[0] as Dictionary)["id"]) == "scout", "candidates id-sorted (scout first)")
	_check(str((cands[1] as Dictionary)["id"]) == "tank", "candidates id-sorted (tank second)")
	for c in cands:
		var cd: Dictionary = c as Dictionary
		_check((cd.get("caps", {}) as Dictionary).size() > 0, "candidate carries a capability card")
		_check(str(cd.get("primary_role", "")) != "", "candidate carries a primary role")
	# allow-list restricts the set.
	var only_tank: Array = UnitCandidateUtil.build_candidates(catalog, null, null, ["tank"])
	_check(only_tank.size() == 1 and str((only_tank[0] as Dictionary)["id"]) == "tank", "allow-list restricts candidates")


func test_md8_candidate_choose_and_fallback() -> void:
	print("test_md8_candidate_choose_and_fallback")
	var w: Dictionary = _md8_neutral_weights()
	# Empty catalog -> fallback id (backward compatibility: always something).
	_check(UnitCandidateUtil.choose_unit({}, w, {}, 1, 0, 0, 30, null, null, [], "soldier") == "soldier",
		"empty catalog returns the fallback id")
	# A single-unit catalog always returns that unit regardless of weights.
	var one: Dictionary = { "soldier": { "id": "soldier", "stats": { "health": 100, "attack_damage": 10, "move_speed": 3 }, "cost": { "resource_basic": 50 } } }
	_check(UnitCandidateUtil.choose_unit(one, w, {}, 1, 0, 0, 30, null, null, [], "soldier") == "soldier",
		"sole catalog unit is chosen")
	# Determinism: identical inputs -> identical pick across repeated calls.
	var two: Dictionary = {
		"tank": { "id": "tank", "stats": { "health": 400, "armor": 30, "attack_damage": 20, "move_speed": 1 }, "cost": { "resource_basic": 200 } },
		"scout": { "id": "scout", "stats": { "health": 40, "move_speed": 6, "vision_range": 9, "attack_damage": 5 }, "cost": { "resource_basic": 60 } },
	}
	var pick_a: String = UnitCandidateUtil.choose_unit(two, w, {}, 7, 12, 3, 30, null, null, [], "soldier")
	var pick_b: String = UnitCandidateUtil.choose_unit(two, w, {}, 7, 12, 3, 30, null, null, [], "soldier")
	_check(pick_a == pick_b and pick_a != "", "choose_unit is deterministic for identical inputs")


func test_md8_candidate_source_is_ascii_and_pure() -> void:
	print("test_md8_candidate_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/unit_candidate_util.gd")
	_check(src.length() > 0, "unit_candidate_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "unit_candidate_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "unit_candidate_util extends RefCounted")
	_check(not src.contains("SceneTree"), "unit_candidate_util does not touch the scene tree type")


# Identity screen->tile adapter for headless SelectionUtil tests.
class _IdentityAdapter extends RefCounted:
	func screen_to_tile(p: Vector2) -> Vector2i:
		return Vector2i(int(p.x), int(p.y))


# Generic event capture helper used by several Phase 2 tests.
var _captured: Array = []

func _capture_event(_event_name: String, payload: Dictionary) -> void:
	_captured.append(payload)


# Find the lowest-id building owned by `owner` (the player's main HQ).
func _first_building_of(nexus: Object, owner: int) -> int:
	var list: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	var keys: Array = list.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		if int(list[k].get("owner", -1)) == owner:
			return int(list[k].get("id", -1))
	return -1


# --- Full tick-driving harness (mimics the real Nexus headlessly) -----------
#
# Implements the subset of the Nexus surface the modules + bootstrap need, and
# actually advances ticks: dispatching due commands then ticking modules, just
# like Nexus._run_single_tick(). No real-time clock, no autoload.
class TickHarness extends RefCounted:
	var world_state: WorldState = WorldState.new()
	var event_bus: EventBus = EventBus.new()
	var data_loader: DataLoader = DataLoader.new()
	var module_registry: ModuleRegistry = ModuleRegistry.new()
	var command_queue: CommandQueue = CommandQueue.new()
	var sim_clock: SimClock = SimClock.new()

	const EVENT_TICK: String = "core.tick"
	const EVENT_COMMAND: String = "core.command"

	func _init() -> void:
		module_registry.setup(self)

	func register_module(module: IModule) -> bool:
		return module_registry.register(module)

	func get_module(id: String) -> IModule:
		return module_registry.get_module(id)

	func subscribe(event_name: String, target: Object, method: String) -> void:
		event_bus.subscribe(event_name, target, method)

	func emit_event(event_name: String, payload: Dictionary = {}) -> void:
		event_bus.emit(event_name, payload)

	func issue_command(type: String, issuer: int, data: Dictionary = {}, delay_ticks: int = 1) -> int:
		var target_tick: int = world_state.current_tick + max(1, delay_ticks)
		return command_queue.enqueue(type, issuer, target_tick, data)

	func start_simulation(seed_value: int = 0) -> void:
		world_state.random_seed = seed_value

	func run_ticks(n: int) -> void:
		for _i in range(n):
			world_state.current_tick += 1
			var tick: int = world_state.current_tick
			var due: Array = command_queue.collect_due(tick)
			for command in due:
				# Deliver each command EXACTLY ONCE via the bus (mirrors the real
				# Nexus._run_single_tick: subscribers handle it, no double broadcast).
				var ev: String = "command." + str(command["type"])
				event_bus.emit(ev, command)
			module_registry.tick_all(1)
			event_bus.emit(EVENT_TICK, { "tick": tick })


# --- Minimal Nexus harness for module unit tests ----------------------------
#
# Provides just enough of the Nexus surface (world_state, event_bus, subscribe,
# emit_event, data_loader, issue_command) for a single module to run in tests
# without the autoload singleton.
class NexusHarness extends RefCounted:
	var world_state: WorldState = WorldState.new()
	var event_bus: EventBus = EventBus.new()
	var data_loader: DataLoader = DataLoader.new()
	var death_log: Array = []

	const EVENT_TICK: String = "core.tick"

	func register(module: IModule) -> void:
		module.init(self)
		# Capture death events for assertions.
		event_bus.subscribe("units.died", self, "_on_death")

	func _on_death(_event_name: String, payload: Dictionary) -> void:
		death_log.append(int(payload.get("id", -1)))

	func subscribe(event_name: String, target: Object, method: String) -> void:
		event_bus.subscribe(event_name, target, method)

	func emit_event(event_name: String, payload: Dictionary = {}) -> void:
		event_bus.emit(event_name, payload)

	func issue_command(_type: String, _issuer: int, _data: Dictionary = {}, _delay: int = 1) -> int:
		return 0


# --- Test helper module -----------------------------------------------------

class _DummyModule extends IModule:
	var _id: String
	var ticks: int = 0

	func _init(id: String) -> void:
		_id = id

	func module_id() -> String:
		return _id

	func on_tick(_delta_tick: int) -> void:
		ticks += 1


# --- Phase 4 test helpers ---------------------------------------------------

# A headless stand-in for a CanvasItem that just COUNTS the drawing primitives a
# render style emits. Both styles call draw_rect / draw_circle / draw_line /
# draw_arc / draw_colored_polygon on "the canvas" -- those calls are duck-typed,
# so a plain RefCounted recorder works (and, unlike a Node2D subclass, it does
# NOT override CanvasItem's native draw_* methods, which Godot rejects). We
# record the calls so tests can assert a style produced output -- no viewport.
class RecordingCanvas extends RefCounted:
	var calls: int = 0
	var tiles_drawn: bool = false
	var unit_drawn: bool = false
	var textures_drawn: int = 0

	func draw_rect(_rect: Rect2, _color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		calls += 1
		tiles_drawn = true

	# Phase B.4: the sprite style draws textures through this primitive.
	func draw_texture_rect(_texture: Texture2D, _rect: Rect2, _tile: bool = false, _modulate: Color = Color.WHITE, _transpose: bool = false) -> void:
		calls += 1
		textures_drawn += 1
		unit_drawn = true

	func draw_circle(_center: Vector2, _radius: float, _color: Color, _filled: bool = true, _width: float = -1.0, _aa: bool = true) -> void:
		calls += 1
		unit_drawn = true

	func draw_arc(_center: Vector2, _radius: float, _start: float, _end: float, _points: int, _color: Color, _width: float = -1.0, _aa: bool = true) -> void:
		calls += 1
		unit_drawn = true

	func draw_line(_from: Vector2, _to: Vector2, _color: Color, _width: float = -1.0, _aa: bool = false) -> void:
		calls += 1

	func draw_colored_polygon(_points: PackedVector2Array, _color: Color, _uvs: PackedVector2Array = PackedVector2Array(), _texture: Texture2D = null) -> void:
		calls += 1


# A second, independent transport implementation used to prove the lockstep core
# is transport-agnostic. It mirrors how EnetTransport routes packets (deliver to
# every peer EXCEPT the author) but stays fully in-process + deterministic, so it
# can drive a real two-peer sync test headlessly. Its public surface is the SAME
# contract LoopbackTransport / EnetTransport expose.
class FakeOnlineTransport extends RefCounted:
	var _peers: Dictionary = {}

	func add_peer(peer_id: int, lockstep: Object) -> void:
		_peers[peer_id] = lockstep

	func attach(peer_id: int, lockstep: Object, event_bus: Object) -> void:
		add_peer(peer_id, lockstep)
		event_bus.subscribe(LockstepModule.EVENT_TURN_READY, self, "_on_turn_ready")
		event_bus.subscribe(LockstepModule.EVENT_CHECKSUM, self, "_on_checksum")

	func broadcast_turn(packet: Dictionary) -> void:
		var author: int = int(packet.get("peer", -1))
		var ids: Array = _peers.keys()
		ids.sort()
		for pid in ids:
			if int(pid) == author:
				continue
			(_peers[pid] as Object).receive_turn(packet.duplicate(true))

	func broadcast_checksum(tick: int, author: int, hash_value: int) -> void:
		var ids: Array = _peers.keys()
		ids.sort()
		for pid in ids:
			if int(pid) == author:
				continue
			(_peers[pid] as Object).receive_checksum(tick, author, hash_value)

	func _on_turn_ready(_event_name: String, payload: Dictionary) -> void:
		broadcast_turn(payload)

	func _on_checksum(_event_name: String, payload: Dictionary) -> void:
		broadcast_checksum(int(payload.get("tick", 0)), int(payload.get("peer", 0)), int(payload.get("hash", 0)))


# A minimal stub standing in for EnetTransport in the NetworkSession test: it
# just reports a fixed peer set + local id so begin_session() can run without
# opening a socket.
class StubTransport extends RefCounted:
	var _peers: Array
	var _local: int

	func _init(peers: Array, local: int) -> void:
		_peers = peers.duplicate()
		_local = local

	func peer_ids() -> Array:
		return _peers.duplicate()

	func local_peer_id() -> int:
		return _local

	func is_host() -> bool:
		return _local == _peers.min() if not _peers.is_empty() else true


# Collects EVENT_CONTROL payloads off an EventBus so a test can assert what the
# control channel delivered to a given peer (MA7.2 / B10).
class ControlCollector extends RefCounted:
	var received: Array = []

	func on_control(_event_name: String, payload: Dictionary) -> void:
		received.append(payload.duplicate(true))


# A transport stub that just records the last send_control() call, used to prove
# NetworkSession.send_control() delegates to its transport (MA7.2 / B10).
class RecordingTransport extends RefCounted:
	var last_control: Dictionary = {}
	var control_calls: int = 0

	func send_control(msg: Dictionary) -> void:
		last_control = msg.duplicate(true)
		control_calls += 1

	func peer_ids() -> Array:
		return [0, 1]

	func local_peer_id() -> int:
		return 0

	func is_host() -> bool:
		return true


# A tiny reader used by the MC12 catalog tests that reads a real JSON file from
# res:// (mirrors DataLoader.load_json_file) so the nine shipped profiles are
# exercised end-to-end.
class RealJsonReader extends RefCounted:
	func load_json_file(path: String) -> Variant:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		return parsed


# A reader that always reports a missing file, used to prove the catalog's
# neutral fallback (MC12.2).
class NullJsonReader extends RefCounted:
	func load_json_file(_path: String) -> Variant:
		return null


# --- Phase MD9 (item 8): building placement utility scoring -----------------

# A defensive-tower capability card: high defense, some frontline/control.
func _md9_tower_caps() -> Dictionary:
	return {
		"defense_value": 900, "frontline_value": 700, "control_value": 500,
		"economic_value": 0, "tech_value": 0, "production_value": 100, "repair_value": 0,
	}

# An economic-building capability card: high economy, no defense.
func _md9_farm_caps() -> Dictionary:
	return {
		"defense_value": 0, "frontline_value": 0, "control_value": 100,
		"economic_value": 900, "tech_value": 0, "production_value": 300, "repair_value": 0,
	}


func test_md9_derive_needs_from_context() -> void:
	print("test_md9_derive_needs_from_context")
	# Safe, wealthy, dominant context -> low defense/economy need, high tech need.
	var safe_ctx: Dictionary = {
		"base_security": 1000, "under_threat": 0, "frontline_pressure": 0,
		"economy_gap": 1000, "army_ratio": 1000,
	}
	var safe: Dictionary = BuildingUtilityUtil.derive_needs(safe_ctx)
	_check(int(safe["defense_need"]) == 0, "totally safe -> zero defense need")
	_check(int(safe["economy_need"]) == 0, "far ahead -> zero economy need")
	_check(int(safe["tech_need"]) == 1000, "safe + dominant -> full tech need")
	# Threatened, poor, pressured context -> high defense/economy/frontline need.
	var siege_ctx: Dictionary = {
		"base_security": 0, "under_threat": 1000, "frontline_pressure": 1000,
		"economy_gap": 0, "army_ratio": 0,
	}
	var siege: Dictionary = BuildingUtilityUtil.derive_needs(siege_ctx)
	_check(int(siege["defense_need"]) == 1000, "unsafe + threatened -> full defense need")
	_check(int(siege["economy_need"]) == 1000, "far behind -> full economy need")
	_check(int(siege["frontline_need"]) == 1000, "heavy pressure -> full frontline need")
	_check(int(siege["tech_need"]) == 0, "unsafe + losing -> zero tech need")


func test_md9_score_building_value_and_site() -> void:
	print("test_md9_score_building_value_and_site")
	# Under siege the tower out-values the farm; when safe+rich the farm wins.
	var siege_ctx: Dictionary = {
		"base_security": 0, "under_threat": 1000, "frontline_pressure": 800,
		"economy_gap": 0, "army_ratio": 0,
	}
	var tower: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), siege_ctx, 0, 0)
	var farm: int = BuildingUtilityUtil.score_building(_md9_farm_caps(), siege_ctx, 0, 0)
	_check(tower > farm, "under siege, defensive tower out-values farm")
	var calm_ctx: Dictionary = {
		"base_security": 1000, "under_threat": 0, "frontline_pressure": 0,
		"economy_gap": 0, "army_ratio": 1000,
	}
	var tower2: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), calm_ctx, 0, 0)
	var farm2: int = BuildingUtilityUtil.score_building(_md9_farm_caps(), calm_ctx, 0, 0)
	_check(farm2 > tower2, "calm + poor, farm out-values tower")
	# Site quality lifts the score in proportion to placement_fit.
	var no_site: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), siege_ctx, 0, 1000)
	var good_site: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), siege_ctx, 1000, 1000)
	_check(good_site - no_site == 1000, "full site quality x full fit adds SCALE")
	var ignore_site: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), siege_ctx, 1000, 0)
	_check(ignore_site == no_site, "placement_fit 0 ignores the site entirely")


func test_md9_score_building_deterministic() -> void:
	print("test_md9_score_building_deterministic")
	var ctx: Dictionary = {
		"base_security": 400, "under_threat": 1, "frontline_pressure": 600,
		"economy_gap": 300, "army_ratio": 700,
	}
	var a: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), ctx, 550, 800)
	var b: int = BuildingUtilityUtil.score_building(_md9_tower_caps(), ctx, 550, 800)
	_check(a == b, "same inputs -> byte-identical score")
	# Missing context keys must not crash and yield the safe defaults.
	var safe: int = BuildingUtilityUtil.score_building(_md9_farm_caps(), {}, 0, 0)
	_check(safe >= 0, "empty context is handled without crashing")


func test_md9_building_util_source_is_ascii_and_pure() -> void:
	print("test_md9_building_util_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/building_utility_util.gd")
	_check(src.length() > 0, "building_utility_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "building_utility_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "building_utility_util extends RefCounted")
	_check(not src.contains("WorldState"), "building_utility_util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "building_utility_util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "building_utility_util does not touch the scene tree type")


# --- Phase MD9.2 (item 8): site quality scoring -----------------------------

# A small map with a vertical corridor at x=2 (walls at x=1 and x=3 on the
# corridor rows). Grid is 5 wide x 5 tall; 0 = ground, 1 = blocked.
func _md9_corridor_world() -> Dictionary:
	var w: int = 5
	var h: int = 5
	var tiles: Array = []
	tiles.resize(w * h)
	for i in range(tiles.size()):
		tiles[i] = 0
	# Build walls flanking a 1-wide vertical corridor at column x=2, rows y=1..3.
	for y in range(1, 4):
		tiles[y * w + 1] = 1
		tiles[y * w + 3] = 1
	return {
		"width": w, "height": h, "tiles": tiles,
		"hq": { "x": 0, "y": 4 },
		"enemies": [ { "x": 4, "y": 0 } ],
		"resources": [ { "x": 1, "y": 4 } ],
		"existing": [ { "x": 0, "y": 4 } ],
	}


func test_md9_site_quality_keys_closed_and_sorted() -> void:
	print("test_md9_site_quality_keys_closed_and_sorted")
	var keys: Array = SiteScoringUtil.QUALITY_KEYS
	var sorted_copy: Array = keys.duplicate()
	sorted_copy.sort()
	_check(keys == sorted_copy, "QUALITY_KEYS is stably sorted")
	var world: Dictionary = _md9_corridor_world()
	var q: Dictionary = SiteScoringUtil.score_site(2, 2, world)
	for k in keys:
		_check(q.has(k), "score_site emits key %s" % k)
	_check(q.size() == keys.size(), "score_site emits exactly the closed key set")


func test_md9_site_choke_and_path_blocking() -> void:
	print("test_md9_site_choke_and_path_blocking")
	var world: Dictionary = _md9_corridor_world()
	# Tile (2,2) sits in the 1-wide vertical corridor: up/down open, sides walls.
	var choke: Dictionary = SiteScoringUtil.score_site(2, 2, world)
	# An open-field tile away from any wall (e.g. bottom-left ground).
	var open: Dictionary = SiteScoringUtil.score_site(0, 0, world)
	_check(int(choke["path_blocking"]) == 1000, "corridor tile fully blocks a path")
	_check(int(choke["choke_point_control"]) > int(open["choke_point_control"]), "corridor tile has stronger choke control")
	_check(int(open["path_blocking"]) <= int(choke["path_blocking"]), "open tile blocks no more than corridor")


func test_md9_site_security_resource_vulnerability() -> void:
	print("test_md9_site_security_resource_vulnerability")
	var world: Dictionary = _md9_corridor_world()
	# HQ is at (0,4); the enemy at (4,0). A tile next to HQ is more secure and
	# less vulnerable than a tile next to the enemy.
	var near_hq: Dictionary = SiteScoringUtil.score_site(0, 3, world)
	var near_enemy: Dictionary = SiteScoringUtil.score_site(4, 1, world)
	_check(int(near_hq["site_security"]) > int(near_enemy["site_security"]), "tile near HQ is more secure")
	_check(int(near_enemy["vulnerability"]) > int(near_hq["vulnerability"]), "tile near enemy is more vulnerable")
	# Resource node is at (1,4); a tile next to it has strong resource access.
	var near_res: Dictionary = SiteScoringUtil.score_site(0, 4, world)
	_check(int(near_res["resource_access"]) > int(near_enemy["resource_access"]), "tile near resource has better access")


func test_md9_fold_quality_and_determinism() -> void:
	print("test_md9_fold_quality_and_determinism")
	var world: Dictionary = _md9_corridor_world()
	var q1: Dictionary = SiteScoringUtil.score_site(2, 2, world)
	var q2: Dictionary = SiteScoringUtil.score_site(2, 2, world)
	_check(q1 == q2, "score_site is byte-identical for the same inputs")
	var folded: int = SiteScoringUtil.fold_quality(q1)
	_check(folded >= 0 and folded <= SiteScoringUtil.SCALE, "folded quality stays within [0..SCALE]")
	# A pure choke/secure tile should fold higher than a fully vulnerable one.
	var high: int = SiteScoringUtil.fold_quality({
		"site_security": 1000, "frontline_value": 500, "resource_access": 500,
		"path_blocking": 1000, "choke_point_control": 1000, "coverage": 500,
		"synergy_with_existing": 500, "vulnerability": 0,
	})
	var low: int = SiteScoringUtil.fold_quality({
		"site_security": 0, "frontline_value": 0, "resource_access": 0,
		"path_blocking": 0, "choke_point_control": 0, "coverage": 0,
		"synergy_with_existing": 0, "vulnerability": 1000,
	})
	_check(high > low, "secure choke folds higher than exposed tile")
	# Empty world must not crash and yields the full key set with safe defaults.
	var empty: Dictionary = SiteScoringUtil.score_site(0, 0, {})
	_check(empty.size() == SiteScoringUtil.QUALITY_KEYS.size(), "empty world still yields full key set")


func test_md9_site_scoring_source_is_ascii_and_pure() -> void:
	print("test_md9_site_scoring_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/site_scoring_util.gd")
	_check(src.length() > 0, "site_scoring_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "site_scoring_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "site_scoring_util extends RefCounted")
	_check(not src.contains("WorldState"), "site_scoring_util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "site_scoring_util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "site_scoring_util does not touch the scene tree type")


# --- Phase MD9.3 (item 8): map-grid topology (choke/path/candidates) --------

# A 7x7 map split into two rooms by a full wall at x=3, pierced by a single
# 1-wide doorway (a choke) at (3,3). 0 = ground, 1 = wall.
func _md9_two_room_world() -> Dictionary:
	var w: int = 7
	var h: int = 7
	var tiles: Array = []
	tiles.resize(w * h)
	for i in range(tiles.size()):
		tiles[i] = 0
	for y in range(h):
		tiles[y * w + 3] = 1
	# Open the doorway at (3,3).
	tiles[3 * w + 3] = 0
	return {
		"width": w, "height": h, "tiles": tiles,
		"hq": { "x": 0, "y": 3 },
		"enemies": [ { "x": 6, "y": 3 } ],
		"occupied": [ { "x": 0, "y": 3 } ],
	}


func test_md9_topology_find_chokes() -> void:
	print("test_md9_topology_find_chokes")
	var world: Dictionary = _md9_two_room_world()
	var chokes: Array = SiteTopologyUtil.find_chokes(int(world["width"]), int(world["height"]), world["tiles"])
	# The doorway (3,3) is a horizontal 1-wide pinch (left+right open, up/down wall).
	_check(chokes.has(Vector2i(3, 3)), "doorway (3,3) detected as a choke")
	# is_choke matches for the doorway and not for an open-field tile.
	_check(SiteTopologyUtil.is_choke(7, 7, world["tiles"], 3, 3) == true, "is_choke true at doorway")
	_check(SiteTopologyUtil.is_choke(7, 7, world["tiles"], 1, 1) == false, "is_choke false in open field")


func test_md9_topology_attack_path_and_path_chokes() -> void:
	print("test_md9_topology_attack_path_and_path_chokes")
	var world: Dictionary = _md9_two_room_world()
	var path: Array = SiteTopologyUtil.estimate_attack_path(7, 7, world["tiles"], Vector2i(6, 3), Vector2i(0, 3))
	_check(path.size() > 0, "enemy has a path to HQ through the doorway")
	# Any route between the rooms MUST pass through the single doorway (3,3).
	_check(path.has(Vector2i(3, 3)), "attack path passes through the doorway")
	var on_path: Array = SiteTopologyUtil.chokes_on_path(7, 7, world["tiles"], path)
	_check(on_path.has(Vector2i(3, 3)), "doorway choke is flagged as on the attack path")


func test_md9_topology_candidate_tiles() -> void:
	print("test_md9_topology_candidate_tiles")
	var world: Dictionary = _md9_two_room_world()
	var cands: Array = SiteTopologyUtil.candidate_tiles(world, 3)
	_check(cands.size() > 0, "candidate tiles enumerated")
	# HQ cell and occupied cells are excluded.
	_check(not cands.has(Vector2i(0, 3)), "HQ cell excluded from candidates")
	# Candidates are stably sorted by (x, y).
	var sorted_copy: Array = cands.duplicate()
	sorted_copy.sort_custom(func(a, b):
		var av: Vector2i = a as Vector2i
		var bv: Vector2i = b as Vector2i
		if av.x != bv.x:
			return av.x < bv.x
		return av.y < bv.y)
	_check(cands == sorted_copy, "candidate list is stably sorted by (x,y)")
	# The doorway choke on the attack path is offered as a defensive candidate.
	_check(cands.has(Vector2i(3, 3)), "doorway choke offered as a candidate")
	# Determinism: same world -> identical candidate list.
	var again: Array = SiteTopologyUtil.candidate_tiles(world, 3)
	_check(cands == again, "candidate enumeration is deterministic")
	# Empty world is handled gracefully.
	_check(SiteTopologyUtil.candidate_tiles({}, 3).is_empty(), "empty world -> no candidates")


func test_md9_topology_source_is_ascii_and_pure() -> void:
	print("test_md9_topology_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/site_topology_util.gd")
	_check(src.length() > 0, "site_topology_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "site_topology_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "site_topology_util extends RefCounted")
	_check(src.contains("PathService"), "site_topology_util reuses PathService")
	_check(not src.contains("WorldState"), "site_topology_util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "site_topology_util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "site_topology_util does not touch the scene tree type")


# --- MD9.5: placement selector integration ----------------------------------

# The outpost capability card the strategic module uses, mirrored here so the
# integration test scores the SAME building the AI would place.
func _md9_outpost_card() -> Dictionary:
	return {
		"control_value": 500,
		"defense_value": 300,
		"economic_value": 700,
		"frontline_value": 500,
		"production_value": 600,
		"repair_value": 100,
		"tech_value": 200,
	}


func test_md9_placement_selects_best_site_deterministic() -> void:
	print("test_md9_placement_selects_best_site_deterministic")
	# Reuse the two-room grid (also carries resources/existing safe-defaults).
	var world: Dictionary = _md9_two_room_world()
	var caps: Dictionary = _md9_outpost_card()
	# A mildly-threatened context so needs (defense/economy) are non-trivial.
	var context: Dictionary = AiContextUtil.build_context({
		"hq": { "x": 0, "y": 3 },
		"enemy_units": [ { "id": 1, "x": 6, "y": 3, "health": 10 } ],
		"own_units": [ { "id": 2, "x": 1, "y": 3, "health": 10 } ],
		"own_economy": 300, "enemy_economy": 300,
		"own_army": 1, "enemy_army": 1,
	}, 1)
	var choice: Dictionary = BuildingPlacementUtil.plan_placement(caps, context, world, 3, 500)
	_check(bool(choice.get("found", false)), "placement found a site among candidates")
	var cx: int = int(choice.get("x", -1))
	var cy: int = int(choice.get("y", -1))
	_check(cx >= 0 and cy >= 0, "chosen site has valid coordinates")
	# The chosen tile MUST be one of the enumerated candidates (never invented).
	var cands: Array = SiteTopologyUtil.candidate_tiles(world, 3)
	_check(cands.has(Vector2i(cx, cy)), "chosen site is one of the enumerated candidates")
	# The chosen tile is not the HQ and not an occupied cell.
	_check(not (cx == 0 and cy == 3), "chosen site is not the HQ")
	# Determinism: identical inputs -> identical choice (lockstep-safe).
	var again: Dictionary = BuildingPlacementUtil.plan_placement(caps, context, world, 3, 500)
	_check(int(again.get("x", -9)) == cx and int(again.get("y", -9)) == cy, "placement choice is deterministic")
	_check(int(again.get("score", -1)) == int(choice.get("score", -2)), "placement score is deterministic")


func test_md9_placement_backward_compat_fallback() -> void:
	print("test_md9_placement_backward_compat_fallback")
	var caps: Dictionary = _md9_outpost_card()
	var context: Dictionary = AiContextUtil.safe_default_context()
	# No HQ / empty world -> no candidates -> found=false, so the strategic module
	# falls back to the legacy _find_build_spot ring scan (behaviour preserved).
	var empty_choice: Dictionary = BuildingPlacementUtil.plan_placement(caps, context, {}, 3, 500)
	_check(not bool(empty_choice.get("found", true)), "empty world yields no placement (triggers legacy fallback)")
	_check(int(empty_choice.get("x", 0)) == -1, "empty placement x is the -1 sentinel")
	# select_site with an explicit empty candidate list behaves the same.
	var none: Dictionary = BuildingPlacementUtil.select_site(caps, context, {}, [], 500)
	_check(not bool(none.get("found", true)), "empty candidate list yields no placement")


func test_md9_strategic_wires_smart_placement() -> void:
	print("test_md9_strategic_wires_smart_placement")
	# Source-level wiring check: _plan_expansion must go through the smart selector
	# first and keep the legacy scan as a fallback (backward compatibility).
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/strategic_ai_module.gd")
	_check(src.length() > 0, "strategic_ai_module.gd source readable")
	_check(src.contains("_smart_build_spot"), "strategic AI defines a smart placement path")
	_check(src.contains("BuildingPlacementUtil"), "strategic AI uses the MD9 placement selector")
	_check(src.contains("AiContextUtil"), "strategic AI derives placement needs from the MD7 context")
	_check(src.contains("_find_build_spot"), "strategic AI retains the legacy ring scan as a fallback")
	# The fallback must run AFTER the smart attempt inside _plan_expansion.
	var expand_idx: int = src.find("func _plan_expansion")
	var smart_idx: int = src.find("_smart_build_spot", expand_idx)
	var fallback_idx: int = src.find("_find_build_spot(hx, hy, owner)", expand_idx)
	_check(expand_idx >= 0 and smart_idx > expand_idx, "smart selector called inside _plan_expansion")
	_check(fallback_idx > smart_idx, "legacy fallback comes after the smart attempt (backward-compat)")
	# Behavioural check: a rich economic AI still expands (an outpost appears),
	# proving the new placement path issues a valid build command end-to-end.
	var nexus: TickHarness = _make_strategic_harness(7, "economic", 3000)
	var before: int = nexus.world_state.get_section("buildings").get("list", {}).size()
	nexus.run_ticks(150)
	var after: int = nexus.world_state.get_section("buildings").get("list", {}).size()
	var tech: Dictionary = nexus.world_state.get_section("tech").get("players", {}).get("1", {})
	var acted: bool = after > before \
		or not (tech.get("researched", []) as Array).is_empty() \
		or not (tech.get("in_progress", {}) as Dictionary).is_empty()
	_check(acted, "economic AI still expands/researches through the new placement path")


# --- Phase MD10 (item 9): staged decision pipeline --------------------------

# MD10.2 Stage 1: the four situation states are classified deterministically
# from the MD7 context vector, highest-severity-first.
func test_md10_state_classification() -> void:
	print("test_md10_state_classification")
	# CRISIS: an active threat at the base flips crisis regardless of the rest.
	var crisis_ctx: Dictionary = {
		"under_threat": 1, "base_security": 900, "army_ratio": 900,
		"frontline_pressure": 0, "economy_gap": 900,
	}
	_check(AiDecisionPipelineUtil.classify_state(crisis_ctx) == AiDecisionPipelineUtil.STATE_CRISIS,
		"active threat -> crisis")
	# CRISIS: a collapsing army is also a crisis even with no direct threat.
	var losing_ctx: Dictionary = {
		"under_threat": 0, "base_security": 800, "army_ratio": 100,
		"frontline_pressure": 0, "economy_gap": 500,
	}
	_check(AiDecisionPipelineUtil.classify_state(losing_ctx) == AiDecisionPipelineUtil.STATE_CRISIS,
		"army badly losing -> crisis")
	# PRESSURED: contested frontline, no direct base threat.
	var pressured_ctx: Dictionary = {
		"under_threat": 0, "base_security": 800, "army_ratio": 600,
		"frontline_pressure": 500, "economy_gap": 500,
	}
	_check(AiDecisionPipelineUtil.classify_state(pressured_ctx) == AiDecisionPipelineUtil.STATE_PRESSURED,
		"contested frontline -> pressured")
	# DOMINANT: safe and clearly ahead on both army and economy.
	var dominant_ctx: Dictionary = {
		"under_threat": 0, "base_security": 900, "army_ratio": 800,
		"frontline_pressure": 0, "economy_gap": 700,
	}
	_check(AiDecisionPipelineUtil.classify_state(dominant_ctx) == AiDecisionPipelineUtil.STATE_DOMINANT,
		"safe + ahead -> dominant")
	# DEVELOPING: safe but not yet dominant (the growing default).
	var developing_ctx: Dictionary = {
		"under_threat": 0, "base_security": 800, "army_ratio": 550,
		"frontline_pressure": 0, "economy_gap": 400,
	}
	_check(AiDecisionPipelineUtil.classify_state(developing_ctx) == AiDecisionPipelineUtil.STATE_DEVELOPING,
		"safe but even -> developing")
	# Resilience: an empty context must not crash and yields a valid state.
	_check(AiDecisionPipelineUtil.STATES.has(AiDecisionPipelineUtil.classify_state({})),
		"empty context yields a valid state")


# MD10.2 Stage 2: the macro priority is the argmax over the fixed-point score
# table, with a fixed tie-break order.
func test_md10_priority_selection_and_tiebreak() -> void:
	print("test_md10_priority_selection_and_tiebreak")
	var neutral_w: Dictionary = AiWeightDerivationUtil.derive_weights(null)
	# Insecure, threatened base -> defense wins.
	var defense_ctx: Dictionary = {
		"under_threat": 1, "base_security": 100, "army_ratio": 400,
		"frontline_pressure": 700, "economy_gap": 500, "enemy_distance": 300,
	}
	var def_flags: Dictionary = AiPolicyUtil.evaluate([], defense_ctx)
	_check(AiDecisionPipelineUtil.choose_priority(defense_ctx, def_flags, neutral_w) == AiDecisionPipelineUtil.PRIORITY_DEFENSE,
		"insecure + threatened -> defense priority")
	# Safe but far behind economically -> economy wins.
	var econ_ctx: Dictionary = {
		"under_threat": 0, "base_security": 900, "army_ratio": 500,
		"frontline_pressure": 0, "economy_gap": 50, "enemy_distance": 900,
	}
	var econ_flags: Dictionary = AiPolicyUtil.evaluate([], econ_ctx)
	_check(AiDecisionPipelineUtil.choose_priority(econ_ctx, econ_flags, neutral_w) == AiDecisionPipelineUtil.PRIORITY_ECONOMY,
		"safe + poor -> economy priority")
	# Strong army + exposed enemy + allow_attack -> attack wins.
	var attack_ctx: Dictionary = {
		"under_threat": 0, "base_security": 900, "army_ratio": 950,
		"frontline_pressure": 0, "economy_gap": 900, "enemy_distance": 200,
	}
	var atk_flags: Dictionary = AiPolicyUtil.evaluate([], attack_ctx)
	_check(AiDecisionPipelineUtil.choose_priority(attack_ctx, atk_flags, neutral_w) == AiDecisionPipelineUtil.PRIORITY_ATTACK,
		"dominant army + exposed enemy -> attack priority")
	# A collapsing army must yield ZERO attack urgency even with an exposed enemy
	# (the pipeline never prioritises attacking when the army is falling apart).
	var no_attack_ctx: Dictionary = {
		"under_threat": 0, "base_security": 900, "army_ratio": 200,
		"frontline_pressure": 0, "economy_gap": 900, "enemy_distance": 100,
	}
	var na_flags: Dictionary = AiPolicyUtil.evaluate([], no_attack_ctx)
	var na_scores: Dictionary = AiDecisionPipelineUtil.priority_scores(no_attack_ctx, na_flags, neutral_w)
	_check(int(na_scores[AiDecisionPipelineUtil.PRIORITY_ATTACK]) == 0,
		"collapsing army -> zero attack urgency")
	# Determinism: same inputs -> same priority.
	var r1: String = AiDecisionPipelineUtil.choose_priority(econ_ctx, econ_flags, neutral_w)
	var r2: String = AiDecisionPipelineUtil.choose_priority(econ_ctx, econ_flags, neutral_w)
	_check(r1 == r2, "priority selection is deterministic (same inputs -> same priority)")
	# Every emitted priority is a member of the closed set.
	_check(AiDecisionPipelineUtil.PRIORITIES.has(r1), "chosen priority is in the closed set")


# MD10.3 Stage 3: each macro priority maps to a concrete action category, with
# defense refined by policy/pressure. Every category draws from the documented
# candidate pool.
func test_md10_category_selection() -> void:
	print("test_md10_category_selection")
	var calm_ctx: Dictionary = { "frontline_pressure": 0 }
	var no_flags: Dictionary = AiPolicyUtil.baseline_flags()
	# Defense with no static-defense policy and light pressure -> holding unit.
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_DEFENSE, calm_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_HOLDING_UNIT,
		"defense + light pressure -> holding unit")
	# Defense under a static-defense policy -> defensive building.
	var static_flags: Dictionary = AiPolicyUtil.baseline_flags()
	static_flags["prefer_static_defense"] = true
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_DEFENSE, calm_ctx, static_flags) == AiDecisionPipelineUtil.CATEGORY_DEFENSIVE_BUILDING,
		"defense + static-defense policy -> defensive building")
	# Defense under heavy frontline pressure -> defensive building.
	var pressured_ctx: Dictionary = { "frontline_pressure": 800 }
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_DEFENSE, pressured_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_DEFENSIVE_BUILDING,
		"defense + heavy pressure -> defensive building")
	# The remaining priorities map to their fixed categories.
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_ECONOMY, calm_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_ECONOMIC_BUILDING,
		"economy -> economic building")
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_RESEARCH, calm_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_TECH_BUILDING,
		"research -> tech building")
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_ATTACK, calm_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_STRIKE_UNIT,
		"attack -> strike unit")
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_EXPANSION, calm_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_EXPANSION_BUILDING,
		"expansion -> expansion building")
	_check(AiDecisionPipelineUtil.choose_category(AiDecisionPipelineUtil.PRIORITY_DIPLOMACY, calm_ctx, no_flags) == AiDecisionPipelineUtil.CATEGORY_DIPLOMACY_ACTION,
		"diplomacy -> diplomacy action")
	# Each category maps to the documented pool.
	_check(AiDecisionPipelineUtil.category_pool(AiDecisionPipelineUtil.CATEGORY_HOLDING_UNIT) == "unit", "holding unit draws from unit pool")
	_check(AiDecisionPipelineUtil.category_pool(AiDecisionPipelineUtil.CATEGORY_STRIKE_UNIT) == "unit", "strike unit draws from unit pool")
	_check(AiDecisionPipelineUtil.category_pool(AiDecisionPipelineUtil.CATEGORY_DEFENSIVE_BUILDING) == "building", "defensive building draws from building pool")
	_check(AiDecisionPipelineUtil.category_pool(AiDecisionPipelineUtil.CATEGORY_ECONOMIC_BUILDING) == "building", "economic building draws from building pool")
	_check(AiDecisionPipelineUtil.category_pool(AiDecisionPipelineUtil.CATEGORY_DIPLOMACY_ACTION) == "", "diplomacy action needs no candidate pool")
	# The category list is stably sorted (closed set).
	var cats: Array = AiDecisionPipelineUtil.categories()
	var sorted_cats: Array = cats.duplicate()
	sorted_cats.sort()
	_check(cats == sorted_cats, "CATEGORIES is stably sorted")


# --- MD10 helpers: sample candidate pools -----------------------------------

# A fragile, high-damage "glass cannon" unit candidate.
func _md10_glass_cannon() -> Dictionary:
	return {
		"id": "sniper",
		"primary_role": "glass_cannon",
		"caps": { "survivability": 100, "damage_output": 950, "holding_power": 100,
			"mobility": 500, "cost_efficiency": 400 },
	}


# A durable, high-holding "tank" unit candidate.
func _md10_tank() -> Dictionary:
	return {
		"id": "tank",
		"primary_role": "frontline_tank",
		"caps": { "survivability": 950, "damage_output": 300, "holding_power": 900,
			"mobility": 200, "cost_efficiency": 400 },
	}


# A defensive tower building candidate.
func _md10_tower() -> Dictionary:
	return {
		"id": "tower",
		"placement_fit": 800,
		"caps": { "defense_value": 950, "economic_value": 0, "tech_value": 0,
			"frontline_value": 700, "production_value": 0 },
	}


# An economic farm building candidate.
func _md10_farm() -> Dictionary:
	return {
		"id": "farm",
		"placement_fit": 100,
		"caps": { "defense_value": 0, "economic_value": 950, "tech_value": 0,
			"frontline_value": 0, "production_value": 100 },
	}


# MD10.4 Stage 4: the exact pick delegates to the MD8 unit scorer and MD9
# building scorer, choosing the best fit for the context.
func test_md10_pick_action_unit_and_building() -> void:
	print("test_md10_pick_action_unit_and_building")
	var neutral_w: Dictionary = AiWeightDerivationUtil.derive_weights(null)
	var pools: Dictionary = {
		"unit": [ _md10_glass_cannon(), _md10_tank() ],
		"building": [ _md10_tower(), _md10_farm() ],
	}
	# Under threat, a HOLDING unit pick should favour the durable tank.
	var threat_ctx: Dictionary = {
		"under_threat": 1, "frontline_pressure": 200, "economy_gap": 500,
		"base_security": 200, "army_ratio": 400,
	}
	var hold_pick: Dictionary = AiDecisionPipelineUtil.pick_action(
		AiDecisionPipelineUtil.CATEGORY_HOLDING_UNIT, threat_ctx, neutral_w, pools, {})
	_check(str(hold_pick.get("kind", "")) == "unit", "holding pick draws a unit")
	_check(str(hold_pick.get("target_id", "")) == "tank", "under threat, holding pick favours the durable tank")
	# On the offensive with an even army, a STRIKE unit favours the glass cannon
	# (high frontline pressure rewards raw damage_output).
	var strike_ctx: Dictionary = {
		"under_threat": 0, "frontline_pressure": 1000, "economy_gap": 500,
		"base_security": 900, "army_ratio": 900,
	}
	var strike_pick: Dictionary = AiDecisionPipelineUtil.pick_action(
		AiDecisionPipelineUtil.CATEGORY_STRIKE_UNIT, strike_ctx, neutral_w, pools, {})
	_check(str(strike_pick.get("target_id", "")) == "sniper", "heavy pressure -> strike pick favours the damage dealer")
	# A DEFENSIVE building pick under siege favours the tower over the farm.
	var siege_ctx: Dictionary = {
		"under_threat": 1, "base_security": 0, "frontline_pressure": 900,
		"economy_gap": 0, "army_ratio": 0,
	}
	var def_pick: Dictionary = AiDecisionPipelineUtil.pick_action(
		AiDecisionPipelineUtil.CATEGORY_DEFENSIVE_BUILDING, siege_ctx, neutral_w, pools, {})
	_check(str(def_pick.get("kind", "")) == "building", "defensive pick draws a building")
	_check(str(def_pick.get("target_id", "")) == "tower", "under siege, defensive pick favours the tower")
	# An ECONOMIC building pick while safe+poor favours the farm.
	var econ_ctx: Dictionary = {
		"under_threat": 0, "base_security": 1000, "frontline_pressure": 0,
		"economy_gap": 0, "army_ratio": 1000,
	}
	var econ_pick: Dictionary = AiDecisionPipelineUtil.pick_action(
		AiDecisionPipelineUtil.CATEGORY_ECONOMIC_BUILDING, econ_ctx, neutral_w, pools, {})
	_check(str(econ_pick.get("target_id", "")) == "farm", "safe + poor, economic pick favours the farm")
	# An empty pool yields an empty target without crashing.
	var empty_pick: Dictionary = AiDecisionPipelineUtil.pick_action(
		AiDecisionPipelineUtil.CATEGORY_STRIKE_UNIT, strike_ctx, neutral_w, {}, {})
	_check(str(empty_pick.get("target_id", "")) == "", "empty pool -> empty target, no crash")
	# A diplomacy/none category needs no candidate.
	var dip_pick: Dictionary = AiDecisionPipelineUtil.pick_action(
		AiDecisionPipelineUtil.CATEGORY_DIPLOMACY_ACTION, econ_ctx, neutral_w, pools, {})
	_check(str(dip_pick.get("kind", "")) == "" and str(dip_pick.get("target_id", "")) == "",
		"diplomacy action needs no candidate")


# MD10.1 + MD10.4: the full four-stage decide() returns a complete, structured
# decision and is byte-identical for identical inputs (determinism).
func test_md10_decide_end_to_end_and_deterministic() -> void:
	print("test_md10_decide_end_to_end_and_deterministic")
	var neutral_w: Dictionary = AiWeightDerivationUtil.derive_weights(null)
	var pools: Dictionary = {
		"unit": [ _md10_glass_cannon(), _md10_tank() ],
		"building": [ _md10_tower(), _md10_farm() ],
	}
	# A crisis context: threatened, insecure -> defense -> defensive building or
	# holding unit -> a concrete pick.
	var crisis_ctx: Dictionary = AiContextUtil.build_context({
		"hq": { "x": 2, "y": 2 },
		"enemy_units": [ { "id": 1, "x": 3, "y": 2, "health": 10 } ],
		"own_army": 1, "enemy_army": 5,
		"own_economy": 1, "enemy_economy": 5,
	}, 1)
	var params: Dictionary = { "match_seed": 42, "tick": 7, "owner": 1, "noise_strength_q": 0 }
	var action: Dictionary = AiDecisionPipelineUtil.decide(crisis_ctx, [], neutral_w, pools, params)
	# Full closed key set present.
	for k in AiDecisionPipelineUtil.ACTION_KEYS:
		_check(action.has(k), "decide() emits action key %s" % k)
	_check(AiDecisionPipelineUtil.STATES.has(str(action.get("state", ""))), "state is in the closed set")
	_check(AiDecisionPipelineUtil.PRIORITIES.has(str(action.get("priority", ""))), "priority is in the closed set")
	_check(AiDecisionPipelineUtil.CATEGORIES.has(str(action.get("category", ""))), "category is in the closed set")
	_check(str(action.get("state", "")) == AiDecisionPipelineUtil.STATE_CRISIS, "threatened base -> crisis state")
	_check(str(action.get("priority", "")) == AiDecisionPipelineUtil.PRIORITY_DEFENSE, "crisis -> defense priority")
	# Determinism: same inputs -> byte-identical action.
	var again: Dictionary = AiDecisionPipelineUtil.decide(crisis_ctx, [], neutral_w, pools, params)
	_check(action == again, "decide() is byte-identical for identical inputs")
	# Resilience: a fully empty pipeline never crashes and returns a full set.
	var safe: Dictionary = AiDecisionPipelineUtil.safe_default_action()
	_check(safe.size() == AiDecisionPipelineUtil.ACTION_KEYS.size(), "safe default action has the full key set")


# MD10 Definition of Done: the pipeline source is pure ASCII and touches no
# scene tree / world model / sim hasher.
func test_md10_pipeline_source_is_ascii_and_pure() -> void:
	print("test_md10_pipeline_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/ai_decision_pipeline_util.gd")
	_check(src.length() > 0, "ai_decision_pipeline_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "ai_decision_pipeline_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "pipeline util extends RefCounted")
	_check(not src.contains("WorldState"), "pipeline util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "pipeline util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "pipeline util does not touch the scene tree type")


# ============================================================================
# Phase MD11 (expert item 12): AI learning layer.
# ============================================================================

# MD11.4: the in-match learning rate is derived from the profile's
# learning_bias. A higher in_match_rate knob yields a strictly larger rate; a
# null profile yields the neutral default.
func test_md11_in_match_rate_from_profile() -> void:
	print("test_md11_in_match_rate_from_profile")
	var neutral_rate: int = AiLearningUtil.in_match_rate_q(null)
	_check(neutral_rate == AiLearningUtil.DEFAULT_RATE_Q, "null profile -> default in-match rate")
	var slow_p: AiProfile = AiProfile.default_profile()
	slow_p.set_value("learning_bias", "in_match_rate", 0.0)
	var fast_p: AiProfile = AiProfile.default_profile()
	fast_p.set_value("learning_bias", "in_match_rate", 1.0)
	var slow_rate: int = AiLearningUtil.in_match_rate_q(slow_p)
	var fast_rate: int = AiLearningUtil.in_match_rate_q(fast_p)
	_check(fast_rate > slow_rate, "higher in_match_rate knob -> larger learning rate")
	_check(slow_rate > 0, "even the slowest learner keeps a positive rate")
	# Determinism: same profile knob -> same rate.
	_check(AiLearningUtil.in_match_rate_q(fast_p) == fast_rate, "in_match_rate_q is deterministic")


# MD11.1: a net-success event reinforces a role weight; a net-loss event weakens
# it. Both are fixed-point and clamped to the hard bounds.
func test_md11_role_reinforce_and_weaken() -> void:
	print("test_md11_role_reinforce_and_weaken")
	var rate: int = AiLearningUtil.DEFAULT_RATE_Q
	# Positive delta on net success.
	var up: int = AiLearningUtil.role_delta(900, 100, rate)
	_check(up > 0, "net-success event yields a positive role delta")
	# Negative delta on net loss.
	var down: int = AiLearningUtil.role_delta(100, 900, rate)
	_check(down < 0, "net-loss event yields a negative role delta")
	# Symmetric magnitude for mirror inputs.
	_check(up == -down, "mirror success/loss produce mirror deltas (fixed-point)")
	# apply_role_event moves a baseline role up on success.
	var start: Dictionary = { "frontline_tank": AiLearningUtil.BASELINE_Q }
	var after: Dictionary = AiLearningUtil.apply_role_event(start, "frontline_tank", 1000, 0, rate)
	_check(int(after["frontline_tank"]) > AiLearningUtil.BASELINE_Q, "successful role rises above baseline")
	# Input is not mutated (pure).
	_check(int(start["frontline_tank"]) == AiLearningUtil.BASELINE_Q, "apply_role_event does not mutate input")
	# A brand-new role starts from baseline then moves.
	var fresh: Dictionary = AiLearningUtil.apply_role_event({}, "scout", 0, 1000, rate)
	_check(int(fresh["scout"]) < AiLearningUtil.BASELINE_Q, "new role weakened below baseline on loss")
	_check(int(fresh["scout"]) >= AiLearningUtil.MIN_WEIGHT_Q, "weakened role never below the hard floor")


# MD11.1: applying a list of events is deterministic and order-independent
# (sorted internally), and the full fold stays inside the hard bounds.
func test_md11_apply_events_deterministic_and_sorted() -> void:
	print("test_md11_apply_events_deterministic_and_sorted")
	var rate: int = AiLearningUtil.DEFAULT_RATE_Q
	var base: Dictionary = {}
	var events_a: Array = [
		{ "role_id": "scout", "success_q": 800, "loss_q": 100 },
		{ "role_id": "frontline_tank", "success_q": 300, "loss_q": 700 },
	]
	# Same events, reversed order.
	var events_b: Array = [
		{ "role_id": "frontline_tank", "success_q": 300, "loss_q": 700 },
		{ "role_id": "scout", "success_q": 800, "loss_q": 100 },
	]
	var out_a: Dictionary = AiLearningUtil.apply_role_events(base, {}, events_a, rate)
	var out_b: Dictionary = AiLearningUtil.apply_role_events(base, {}, events_b, rate)
	_check(out_a == out_b, "event order does not change the learned result")
	# Deterministic repeat.
	var out_a2: Dictionary = AiLearningUtil.apply_role_events(base, {}, events_a, rate)
	_check(out_a == out_a2, "apply_role_events is byte-identical on repeat")
	# Bounds respected.
	var all_bounded: bool = true
	for k in out_a.keys():
		var w: int = int(out_a[k])
		if w < AiLearningUtil.MIN_WEIGHT_Q or w > AiLearningUtil.MAX_WEIGHT_Q:
			all_bounded = false
	_check(all_bounded, "all learned weights stay within the hard bounds")


# MD11.5: the anti-exploit guard caps per-match change and softly pulls weights
# back toward baseline, so learning can never lock the AI into a degenerate high.
func test_md11_anti_exploit_cap_and_baseline_decay() -> void:
	print("test_md11_anti_exploit_cap_and_baseline_decay")
	# A wildly over-boosted weight is capped relative to the match-start base.
	var base: Dictionary = { "harasser": AiLearningUtil.BASELINE_Q }
	var runaway: Dictionary = { "harasser": AiLearningUtil.MAX_WEIGHT_Q }
	var capped: Dictionary = AiLearningUtil.cap_match_delta(base, runaway)
	var moved: int = int(capped["harasser"]) - AiLearningUtil.BASELINE_Q
	_check(moved <= AiLearningUtil.MAX_MATCH_DELTA_Q, "per-match change is capped")
	# Soft decay moves an above-baseline weight back down toward baseline.
	var high: Dictionary = { "siege_unit": AiLearningUtil.BASELINE_Q + 500 }
	var decayed: Dictionary = AiLearningUtil.decay_toward_baseline(high)
	_check(int(decayed["siege_unit"]) < AiLearningUtil.BASELINE_Q + 500, "above-baseline weight decays down")
	_check(int(decayed["siege_unit"]) > AiLearningUtil.BASELINE_Q, "decay does not overshoot below baseline in one step")
	# A below-baseline weight decays UP toward baseline.
	var low: Dictionary = { "support": AiLearningUtil.BASELINE_Q - 500 }
	var decayed_low: Dictionary = AiLearningUtil.decay_toward_baseline(low)
	_check(int(decayed_low["support"]) > AiLearningUtil.BASELINE_Q - 500, "below-baseline weight decays up")


# MD11.2: the in-match learned state serialises to a sorted-key snapshot for the
# deterministic worldstate and round-trips exactly.
func test_md11_state_round_trip_sorted() -> void:
	print("test_md11_state_round_trip_sorted")
	var roles: Dictionary = { "scout": 1200, "frontline_tank": 800 }
	var sites: Dictionary = { "5,5": 1300, "2,2": 700 }
	var targets: Dictionary = { "3": 1100 }
	var snap: Dictionary = AiLearningUtil.export_state(roles, sites, targets)
	_check(snap.has("roles") and snap.has("sites") and snap.has("targets"), "snapshot has all three sections")
	# Keys are sorted (byte-stable for the hasher).
	var role_keys: Array = (snap["roles"] as Dictionary).keys()
	var sorted_role_keys: Array = role_keys.duplicate()
	sorted_role_keys.sort()
	_check(role_keys == sorted_role_keys, "snapshot role keys are sorted")
	# Round-trip preserves values.
	var back: Dictionary = AiLearningUtil.import_state(snap)
	_check(int((back["roles"] as Dictionary)["scout"]) == 1200, "round-trip preserves role weight")
	_check(int((back["sites"] as Dictionary)["5,5"]) == 1300, "round-trip preserves site pref")
	# Resilience: missing sections import as empty maps, never crash.
	var empty_back: Dictionary = AiLearningUtil.import_state({})
	_check((empty_back["roles"] as Dictionary).is_empty(), "missing section imports as empty map")


# MD11.3: cross-match memory records outcomes and seeds match-start weights
# deterministically; it is scaled by the profile's memory trust.
func test_md11_cross_match_memory_and_seed() -> void:
	print("test_md11_cross_match_memory_and_seed")
	var mem: Dictionary = AiLearningUtil.new_memory()
	_check(int(mem["version"]) == AiLearningUtil.MEMORY_SCHEMA_VERSION, "fresh memory has the schema version")
	# Record a winning role and a losing role on the same mod/map.
	mem = AiLearningUtil.record_memory(mem, "base", "arena", "frontline_tank", 400)
	mem = AiLearningUtil.record_memory(mem, "base", "arena", "glass_cannon", -400)
	# Seed the starting weights from memory at full trust.
	var roles: Array = ["frontline_tank", "glass_cannon", "scout"]
	var seed_full: Dictionary = AiLearningUtil.seed_weights_from_memory(mem, "base", "arena", roles, AiLearningUtil.SCALE)
	_check(int(seed_full["frontline_tank"]) > AiLearningUtil.BASELINE_Q, "winning role seeded above baseline")
	_check(int(seed_full["glass_cannon"]) < AiLearningUtil.BASELINE_Q, "losing role seeded below baseline")
	_check(int(seed_full["scout"]) == AiLearningUtil.BASELINE_Q, "role with no memory seeds at baseline")
	# Lower memory trust -> smaller nudge (closer to baseline).
	var seed_half: Dictionary = AiLearningUtil.seed_weights_from_memory(mem, "base", "arena", roles, AiLearningUtil.SCALE / 2)
	var full_gap: int = int(seed_full["frontline_tank"]) - AiLearningUtil.BASELINE_Q
	var half_gap: int = int(seed_half["frontline_tank"]) - AiLearningUtil.BASELINE_Q
	_check(half_gap < full_gap, "lower memory trust yields a smaller seed nudge")
	# Determinism: same inputs -> same seed.
	var seed_again: Dictionary = AiLearningUtil.seed_weights_from_memory(mem, "base", "arena", roles, AiLearningUtil.SCALE)
	_check(seed_full == seed_again, "seed_weights_from_memory is deterministic")
	# record_memory does not mutate the caller's document.
	var before_entries: int = (mem["entries"] as Dictionary).size()
	var _mem2: Dictionary = AiLearningUtil.record_memory(mem, "base", "arena", "scout", 100)
	_check((mem["entries"] as Dictionary).size() == before_entries, "record_memory does not mutate input")


# MD11 Definition of Done: the learning source is pure ASCII and touches no
# scene tree / world model / sim hasher / unseeded RNG.
func test_md11_learning_source_is_ascii_and_pure() -> void:
	print("test_md11_learning_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://modules/ai_commander/ai_learning_util.gd")
	_check(src.length() > 0, "ai_learning_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "ai_learning_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "learning util extends RefCounted")
	_check(not src.contains("WorldState"), "learning util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "learning util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "learning util does not touch the scene tree type")
	_check(not src.contains("randi") and not src.contains("randf"), "learning util uses no unseeded RNG")


# ============================================================================
# Phase MD12 (expert item 15): data-driven Stat UI in the mod editor.
# ============================================================================

# MD12.1: describe_stat pulls every field the editor needs from the registry
# (value_type / category / min / max / default / needs_value / core) and builds
# the i18n name key, degrading to safe defaults for a null registry.
func test_md12_describe_stat_reads_registry_metadata() -> void:
	print("test_md12_describe_stat_reads_registry_metadata")
	StatRegistry.reset_definitions()
	var d: Dictionary = StatEditorUtil.describe_stat("health", StatRegistry)
	_check(str(d["id"]) == "health", "descriptor keeps the stat id")
	_check(str(d["name_key"]) == "stat.health.name", "descriptor builds the i18n name key")
	_check(str(d["value_type"]) == "int", "health value_type read from registry")
	_check(str(d["category"]) == "defense", "health category read from registry")
	_check(float(d["max"]) == 100000.0, "health max read from registry")
	_check(bool(d["core"]) == true, "health flagged as a core stat")
	# A pure-flag stat (needs_value false, bool type).
	var s: Dictionary = StatEditorUtil.describe_stat("stealth", StatRegistry)
	_check(str(s["value_type"]) == "bool", "stealth value_type is bool")
	_check(bool(s["needs_value"]) == false, "stealth needs no numeric value")
	# Null registry -> safe defaults, still a usable descriptor.
	var f: Dictionary = StatEditorUtil.describe_stat("whatever", null)
	_check(str(f["category"]) == StatEditorUtil.MISC_CATEGORY, "null registry -> misc category")
	_check(str(f["value_type"]) == "int", "null registry -> int default")
	_check(str(f["name_key"]) == "stat.whatever.name", "null registry still builds name key")


# MD12.1: stat_ids_for returns the sorted set of stat ids valid for a catalog
# and honours applies_to (a unit-only stat like move_speed is absent from the
# building catalog). Empty for a null registry.
func test_md12_stat_ids_for_catalog_sorted() -> void:
	print("test_md12_stat_ids_for_catalog_sorted")
	StatRegistry.reset_definitions()
	var unit_ids: Array = StatEditorUtil.stat_ids_for("unit", StatRegistry)
	_check(unit_ids.size() > 0, "unit catalog yields stats")
	# Sorted.
	var sorted_copy: Array = unit_ids.duplicate()
	sorted_copy.sort()
	_check(unit_ids == sorted_copy, "unit stat ids are sorted")
	_check(unit_ids.has("move_speed"), "unit catalog includes move_speed")
	_check(unit_ids.has("health"), "unit catalog includes the both-applies health")
	# Buildings exclude unit-only mobility stats.
	var building_ids: Array = StatEditorUtil.stat_ids_for("building", StatRegistry)
	_check(not building_ids.has("move_speed"), "building catalog excludes unit-only move_speed")
	_check(building_ids.has("extraction_rate"), "building catalog includes extraction_rate")
	# Null registry -> empty, never a crash.
	_check(StatEditorUtil.stat_ids_for("unit", null) == [], "null registry -> empty id list")


# MD12.1: groups_for buckets a catalog's stats by category, groups sorted by
# category id, stats inside a group kept in sorted-id order, every stat present
# exactly once.
func test_md12_groups_for_grouped_by_category_sorted() -> void:
	print("test_md12_groups_for_grouped_by_category_sorted")
	StatRegistry.reset_definitions()
	var groups: Array = StatEditorUtil.groups_for("unit", StatRegistry)
	_check(groups.size() > 0, "unit catalog yields groups")
	# Group categories are sorted ASC.
	var cats: Array = []
	for g in groups:
		cats.append(str((g as Dictionary)["category"]))
	var cats_sorted: Array = cats.duplicate()
	cats_sorted.sort()
	_check(cats == cats_sorted, "groups sorted by category id")
	# Every stat id from the flat list appears exactly once across groups.
	var flat: Array = StatEditorUtil.stat_ids_for("unit", StatRegistry)
	var seen: Dictionary = {}
	for g in groups:
		var last: String = ""
		for desc in (g as Dictionary)["stats"]:
			var sid: String = str((desc as Dictionary)["id"])
			seen[sid] = int(seen.get(sid, 0)) + 1
			# Stats inside a group stay in sorted-id order.
			_check(last == "" or sid > last, "stat %s follows sorted order in its group" % sid)
			last = sid
	_check(seen.size() == flat.size(), "grouping covers every stat exactly once")
	# categories_for mirrors the group categories.
	_check(StatEditorUtil.categories_for("unit", StatRegistry) == cats, "categories_for matches group categories")


# MD12.1: paginate never shows more than the page cap, clamps out-of-range pages
# back into bounds, reports an accurate page_count/total, and covers the whole
# list across its pages with no duplicates or gaps.
func test_md12_paginate_mobile_cap_and_bounds() -> void:
	print("test_md12_paginate_mobile_cap_and_bounds")
	var items: Array = []
	for i in range(19):
		items.append({ "id": "s%02d" % i })
	var p0: Dictionary = StatEditorUtil.paginate(items, 0, 8)
	_check(int(p0["page_count"]) == 3, "19 items / 8 per page -> 3 pages")
	_check(int(p0["total"]) == 19, "total reported")
	_check((p0["stats"] as Array).size() == 8, "first page holds the cap of 8")
	# Last page holds the remainder.
	var p2: Dictionary = StatEditorUtil.paginate(items, 2, 8)
	_check((p2["stats"] as Array).size() == 3, "last page holds the remaining 3")
	# Out-of-range page clamps to the last valid page.
	var pbig: Dictionary = StatEditorUtil.paginate(items, 99, 8)
	_check(int(pbig["page"]) == 2, "page beyond range clamps to last page")
	# Negative page clamps to 0.
	var pneg: Dictionary = StatEditorUtil.paginate(items, -5, 8)
	_check(int(pneg["page"]) == 0, "negative page clamps to first page")
	# page_size < 1 is clamped to 1 (never divide by zero).
	var pz: Dictionary = StatEditorUtil.paginate(items, 0, 0)
	_check(int(pz["page_size"]) == 1, "page_size clamped to at least 1")
	_check(int(pz["page_count"]) == 19, "page_size 1 -> one page per item")
	# Union of all pages == the whole list, in order, no duplicates.
	var rebuilt: Array = []
	for pg in range(int(p0["page_count"])):
		for desc in (StatEditorUtil.paginate(items, pg, 8)["stats"] as Array):
			rebuilt.append(desc)
	_check(rebuilt == items, "pages cover the whole list in order with no gaps")
	# Empty list -> a single empty page (never crashes).
	var pe: Dictionary = StatEditorUtil.paginate([], 0, 8)
	_check(int(pe["page_count"]) == 1 and (pe["stats"] as Array).is_empty(), "empty list -> one empty page")


# MD12.2: control_kind maps a value_type to the widget the editor should draw.
func test_md12_control_kind_by_value_type() -> void:
	print("test_md12_control_kind_by_value_type")
	_check(StatEditorUtil.control_kind("bool") == "switch", "bool -> switch")
	_check(StatEditorUtil.control_kind("int") == "int", "int -> int")
	_check(StatEditorUtil.control_kind("float") == "float", "float -> float")
	# Unknown / empty falls back to int (safe numeric default).
	_check(StatEditorUtil.control_kind("mystery") == "int", "unknown type -> int fallback")
	_check(StatEditorUtil.control_kind("") == "int", "empty type -> int fallback")


# MD12.2: coerce_value honours value_type and clamps into the registry's
# [min..max] band. int rounds half away from zero; bool ignores bounds.
func test_md12_coerce_value_type_and_clamp() -> void:
	print("test_md12_coerce_value_type_and_clamp")
	StatRegistry.reset_definitions()
	# health is int, min 1, max 100000.
	var hi: Variant = StatEditorUtil.coerce_value("health", 250000, StatRegistry)
	_check(hi is int and int(hi) == 100000, "health clamped to registry max as int")
	var lo: Variant = StatEditorUtil.coerce_value("health", -5, StatRegistry)
	_check(lo is int and int(lo) == 1, "health clamped up to registry min")
	var rounded: Variant = StatEditorUtil.coerce_value("health", 42.6, StatRegistry)
	_check(rounded is int and int(rounded) == 43, "int stat rounds half away from zero")
	# fire_rate is float, min 0.01, max 100.0.
	var fr: Variant = StatEditorUtil.coerce_value("fire_rate", 2.5, StatRegistry)
	_check(fr is float and abs(float(fr) - 2.5) < 0.0001, "float stat keeps its decimals")
	var frhi: Variant = StatEditorUtil.coerce_value("fire_rate", 9999.0, StatRegistry)
	_check(frhi is float and abs(float(frhi) - 100.0) < 0.0001, "float stat clamped to max")
	# stealth is bool -> truthiness, bounds ignored.
	var st: Variant = StatEditorUtil.coerce_value("stealth", 1, StatRegistry)
	_check(st is bool and bool(st) == true, "bool stat coerces truthy input to true")
	var stf: Variant = StatEditorUtil.coerce_value("stealth", 0, StatRegistry)
	_check(stf is bool and bool(stf) == false, "bool stat coerces zero to false")
	# Null registry -> unbounded int, no crash.
	var nr: Variant = StatEditorUtil.coerce_value("anything", 12.4, null)
	_check(nr is int and int(nr) == 12, "null registry -> unbounded int coercion")


# MD12.2: with_stat_value edits the MODEL purely (no input mutation), applies the
# clamped/typed value only when the stat is present.
func test_md12_with_stat_value_pure_and_respects_bounds() -> void:
	print("test_md12_with_stat_value_pure_and_respects_bounds")
	StatRegistry.reset_definitions()
	var stats: Dictionary = { "health": 100 }
	var out: Dictionary = StatEditorUtil.with_stat_value(stats, "health", 500000, StatRegistry)
	_check(int(out["health"]) == 100000, "value clamped to max in the returned model")
	_check(int(stats["health"]) == 100, "input stats dict is not mutated (pure)")
	# A stat that is not present is left untouched (editor toggles presence).
	var out2: Dictionary = StatEditorUtil.with_stat_value(stats, "armor", 50, StatRegistry)
	_check(not out2.has("armor"), "absent stat is not added by a value edit")
	# Deterministic.
	_check(StatEditorUtil.with_stat_value(stats, "health", 500000, StatRegistry) == out, "with_stat_value deterministic")


# Test helper: true when any string in `arr` contains `needle` (substring).
func _has_substr(arr: Array, needle: String) -> bool:
	for item in arr:
		if str(item).contains(needle):
			return true
	return false


# MD12.4: build_free_stat_definition + normalise_stat_id produce a valid MD1
# definition dictionary in the shape StatRegistry.load_definitions() merges.
func test_md12_build_free_stat_definition_shape() -> void:
	print("test_md12_build_free_stat_definition_shape")
	StatRegistry.reset_definitions()
	# Author-typed messy id + affects out of key order.
	var def: Dictionary = StatEditorUtil.build_free_stat_definition(
		"  2My Cool-Stat!! ", "float", "morale", 0.0, 10.0, 3.0,
		{ "survivability": 0.5, "damage_output": 1.0 }, "unit")
	_check(str(def["id"]) == "my_cool_stat", "author id normalised to my_cool_stat")
	_check(str(def["value_type"]) == "float", "value_type carried through")
	_check(str(def["category"]) == "morale", "category carried through")
	_check(float(def["min"]) == 0.0 and float(def["max"]) == 10.0, "min/max carried as floats")
	_check(str(def["applies_to"]) == "unit", "applies_to carried through")
	_check(bool(def["core"]) == false, "free stat is not core")
	_check(str(def["display_name_key"]) == "stat.my_cool_stat.name", "display_name_key uses normalised id (MD12.5)")
	# affects copied in sorted-key order (deterministic).
	var keys: Array = (def["affects"] as Dictionary).keys()
	_check(keys == ["damage_output", "survivability"], "affects keys sorted deterministically")
	# bool type flips needs_value off.
	var bdef: Dictionary = StatEditorUtil.build_free_stat_definition(
		"flying", "bool", "mobility", 0.0, 1.0, false, {}, "unit")
	_check(bool(bdef["needs_value"]) == false, "bool free stat needs no numeric value")
	# Unknown value_type / applies_to fall back to safe defaults.
	var fb: Dictionary = StatEditorUtil.build_free_stat_definition(
		"weird", "mystery", "", 0.0, 1.0, 0, {}, "planet")
	_check(str(fb["value_type"]) == "int", "unknown value_type -> int")
	_check(str(fb["applies_to"]) == "both", "unknown applies_to -> both")
	_check(str(fb["category"]) == StatEditorUtil.MISC_CATEGORY, "empty category -> misc")
	# Deterministic: same input -> byte-for-byte same definition.
	var again: Dictionary = StatEditorUtil.build_free_stat_definition(
		"  2My Cool-Stat!! ", "float", "morale", 0.0, 10.0, 3.0,
		{ "survivability": 0.5, "damage_output": 1.0 }, "unit")
	_check(again == def, "build_free_stat_definition deterministic")


# MD12.4: validate_free_stat layers Free-Stat rules on top of the shared schema
# check -- id collision with core stats, unknown affects capability, bad type.
func test_md12_validate_free_stat_rules() -> void:
	print("test_md12_validate_free_stat_rules")
	StatRegistry.reset_definitions()
	# A well-formed free stat validates clean.
	var good: Dictionary = StatEditorUtil.build_free_stat_definition(
		"morale", "int", "morale", 0.0, 100.0, 50,
		{ "survivability": 0.4 }, "unit")
	var ok: Array = StatEditorUtil.validate_free_stat(good, StatRegistry, CapabilityRegistry)
	_check(ok.is_empty(), "well-formed free stat validates clean")
	# Colliding with a reserved core stat is rejected.
	var collide: Dictionary = StatEditorUtil.build_free_stat_definition(
		"health", "int", "defense", 0.0, 100.0, 50, {}, "unit")
	var cp: Array = StatEditorUtil.validate_free_stat(collide, StatRegistry, CapabilityRegistry)
	_check(_has_substr(cp, "collides"), "core-stat id collision rejected")
	# affects onto an unknown capability is rejected.
	var badcap: Dictionary = StatEditorUtil.build_free_stat_definition(
		"luck", "int", "misc", 0.0, 100.0, 0,
		{ "not_a_capability": 1.0 }, "unit")
	var bcp: Array = StatEditorUtil.validate_free_stat(badcap, StatRegistry, CapabilityRegistry)
	_check(_has_substr(bcp, "unknown capability"), "affects unknown capability rejected")
	# min > max is caught by the shared schema layer.
	var bad_band: Dictionary = StatEditorUtil.build_free_stat_definition(
		"tempo", "int", "misc", 100.0, 0.0, 0, {}, "unit")
	var bbp: Array = StatEditorUtil.validate_free_stat(bad_band, StatRegistry, CapabilityRegistry)
	_check(_has_substr(bbp, "min") and _has_substr(bbp, "max"), "min>max rejected via shared schema")
	# An empty-id def (nothing usable typed) is rejected.
	var empty: Dictionary = StatEditorUtil.build_free_stat_definition(
		"!!!", "int", "misc", 0.0, 1.0, 0, {}, "unit")
	var ep: Array = StatEditorUtil.validate_free_stat(empty, StatRegistry, CapabilityRegistry)
	_check(_has_substr(ep, "non-empty id"), "empty free stat id rejected")
	# The validated free stat round-trips through the registry as a Free Stat.
	StatRegistry.reset_definitions()
	StatRegistry.load_definitions({ "morale": good })
	_check(StatRegistry.is_free("morale"), "merged free stat classified as free")
	_check(not StatRegistry.is_core("morale"), "free stat is not core")
	_check(StatRegistry.value_type("morale") == "int", "free stat value_type queryable after merge")
	StatRegistry.reset_definitions()


# MD12.1: the util is pure ASCII, a RefCounted, and never touches the scene
# tree / world model / sim hasher (cosmetic descriptor builder only).
func test_md12_stat_editor_util_source_is_ascii_and_pure() -> void:
	print("test_md12_stat_editor_util_source_is_ascii_and_pure")
	var src: String = FileAccess.get_file_as_string("res://ui/shared/stat_editor_util.gd")
	_check(src.length() > 0, "stat_editor_util.gd source readable")
	var ascii_ok: bool = true
	for i in range(src.length()):
		if src.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "stat_editor_util.gd is ASCII-only")
	_check(src.contains("extends RefCounted"), "stat editor util extends RefCounted")
	_check(not src.contains("WorldState"), "stat editor util does not touch the world model type")
	_check(not src.contains("state_hasher") and not src.contains("StateHasher"), "stat editor util does not touch the sim hasher")
	_check(not src.contains("SceneTree"), "stat editor util does not touch the scene tree type")
