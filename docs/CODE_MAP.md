# نقشه‌ی کد — Project Nexus (Code Map)
### مرجع سریع برای پیدا کردن «کجا چه کاری انجام می‌شود» بدون خواندن کل کد

> **هدف:** AI/توسعه‌دهنده‌ی بعدی با این فایل بتواند در چند دقیقه بفهمد هر قابلیت
> در کدام فایل/تابع است و برای پیاده‌سازی خواسته‌های نسخه ۰.۶.۰ (بخش‌های
> `R#`/`P#` در `docs/STRUCTURE.md`) از کجا شروع کند.
>
> این سند **مکمل** `docs/STRUCTURE.md` است: STRUCTURE «چه چیزی و چرا» را می‌گوید،
> CODE_MAP «کجا در کد» را. هر دو باید هم‌زمان به‌روز بمانند.

---

## ۱. نمودار پوشه‌ها (نگاشت مسئولیت)

```
core/        مغز مرکزی و اجزای آن (هرگز گیم‌پلی ندارد)
modules/     ماژول‌های مستقل گیم‌پلی (فقط از EventBus/WorldState استفاده می‌کنند)
ui/          رابط کاربری (mobile / desktop / shared) — فقط می‌خواند و فرمان صادر می‌کند
render/       سبک‌های رندر جابه‌جاشونده پشت RenderAdapter (simple/detailed/sprite)
assets/      هنر پایه (textures/؛ محل آینده‌ی fonts/ و theme/ — فاز P1)
data/         محتوای داده‌محور (JSON): units/buildings/objects/tech/scenarios/difficulty
localization/ متن نمایشی ترجمه‌شده (تنها جای مجاز متن غیرانگلیسی): en.json, fa.json
mods/         مودهای نمونه (example_mod, playdough_demo)
platforms/    تنظیمات export هر پلتفرم
tests/        تست‌های واحد/یکپارچگی (headless): tests/test_runner.gd
tools/        ابزار: مدل‌های ادیتور (mod_project/scenario_project) + linter + registry
docs/         مستندات: STRUCTURE.md (مرجع فاز) + CODE_MAP.md (این) + MODDING/CODE_POLICY/RELEASE + BUG_REPORT.md (گزارش ممیزی باگ P9-QA)
scenes/       صحنه‌های Godot (.tscn)
```

---

## ۲. هسته (`core/`)

| فایل | نقش | توابع کلیدی |
|---|---|---|
| `nexus.gd` | Autoload؛ سیم‌کشی + حلقه‌ی tick | `issue_command`, `emit_event`, `subscribe`, `get_module`, `toggle_pause`, `shutdown_simulation` |
| `event_bus.gd` | pub/sub | `subscribe`, `unsubscribe_all`, `emit`, `set_log_enabled` |
| `world_state.gd` | تنها منبع حقیقت | `get_section`, `current_tick`, سریال‌سازی بخش‌ها |
| `module_registry.gd` | چرخه‌ی حیات ماژول | ثبت/init/tick/shutdown |
| `sim_clock.gd` | tick قطعی + Active Pause | `is_paused`, `pause`, `time_scale` |
| `command_queue.gd` | صف فرمان (پایه‌ی lockstep) | enqueue/dispatch |
| `data_loader.gd` | بارگذاری JSON + merge مود | `get_catalog`, `get_entry`, `load_catalogs` |
| `save_system.gd` | سریال/بازیابی کل بازی | serialize/restore کل WorldState — **پایه‌ی R3/R4** |
| `state_hasher.gd` | checksum قطعی | تشخیص desync — **پایه‌ی R7 (مقایسه‌ی hash مود/state)** |
| `capability_registry.gd` | **MD2.1: قرارداد بسته و نسخه‌دارِ Capability** (لایه‌ی واسطِ ثابتِ موتور بین statِ خام و AI) | `all_ids` (sorted), `has_capability`, `record`, `applies_to`, `default_q` (fixed-point)، `name_key` (i18n)، `ids_for(unit/building)` — فهرست هرگز با مود تغییر نمی‌کند |
| `stat_affects_util.gd` | **MD2.2–2.4: نگاشتِ `affects` (Stat → Capability)** با وزنِ fixed-point (`SCALE=1000`) | `builtin_map` (نگاشتِ توکارِ Core Stats)، `builtin_affects_for`، `quantize_weight`، `resolve_affects(stat_registry)` (ادغامِ affectsِ مودها روی توکار — وصلِ بی‌کدِ Free Stat)، `validate_affects` (ردِ capabilityِ ناشناخته/وزنِ خارج از بازه) — خالص و قطعی |
| `derived_metrics_util.gd` | **MD3: از statِ خام به بردارِ Capabilityِ نرمال‌شده‌ی fixed-point** (لینکِ سومِ ستونِ داده‌محور؛ AI فقط این بردار را می‌خواند نه statِ خام/نامِ واحد) | `compute_capabilities(entity_def, stat_registry, affects)` (منحنیِ اشباعِ قطعی `q=SCALE*v/(v+H)`)، `cost_efficiency`/`resource_pressure` (MD3.2)، `cache_key`/`compute_capabilities_cached` (MD3.3، بودجه‌ی موبایل، بی‌اثر روی hash)، تابِ‌آوری با `default_q` برای statِ غایب (MD3.4) — خالص، RefCounted، ASCII |
| `role_inference_util.gd` | **MD4: از بردارِ Capability به نقشِ AI** (لینکِ چهارم؛ نقشِ تصمیم‌ساز از capability می‌آید نه از `category`ِ نمایشی/نامِ واحد) | `infer_roles(capabilities, target)` → آرایه‌ی `{role, score_q}` مرتب‌شده‌ی نزولی (score DESC, role ASC) قطعی و fixed-point؛ `primary_role` با گره‌گشاییِ الفبایی (MD4.2)؛ امضاهای نقشِ واحد/ساختمان (`UNIT_SIGNATURES`/`BUILDING_SIGNATURES`) با وزنِ مثبت/منفی؛ تابِ‌آوری: بردارِ خالی/ناقص → نقشِ `generic` هرگز خالی نمی‌ماند (MD4.3)؛ `target=auto` جدولِ نقش را از رویِ سیگنالِ غالبِ بردار انتخاب می‌کند — خالص، RefCounted، ASCII |
| `ai_weight_derivation_util.gd` | **MD5: از بردارِ ۳۵پارامتریِ `AiProfile` به وزنِ نقش‌ها و capabilityها** (شخصیت روی «ارزشِ نقش» اثر می‌گذارد نه نامِ واحد) | `derive_role_weights(profile)` → `role_id -> weight_q` و `derive_capability_weights(profile)` → `capability_id -> weight_q` (fixed-point، knob → وزن با نگاشتِ مستند: aggression/offense/harassment وزنِ harasser/glass_cannon را بالا و defense وزنِ frontline_tank را بالا می‌برد، MD5.3)؛ `derive_weights` هر دو را یک‌جا می‌دهد؛ `preferred_roles(profile, count)` خلاصه‌ی نمایشیِ «این AI چه نقش‌هایی را ترجیح می‌دهد» برای UIِ roster (MD5.4)؛ **در کنارِ** `ai_strategy_derivation_util` (۴ عددِ macro) نه جایگزینِ آن (MD5.2) — خالص، RefCounted، قطعی، ASCII |
| `ai_context_util.gd` | **MD7: بردارِ وضعیتِ واحد و قطعیِ AI** (لینکِ ششم؛ جای‌گزینِ منطقِ پراکنده‌ی `_enemy_near_base`/`_resources`؛ ورودیِ مشترکِ policy MD6، utility MD8/MD9 و تصمیمِ مرحله‌ای MD10) | `build_context(world_summary, owner)` → مجموعه‌کلیدِ بسته و نسخه‌دارِ fixed-point: `base_security`, `enemy_distance`, `economy_gap`, `army_ratio`, `frontline_pressure` (int در `[0..SCALE]`) و پرچم‌های `under_threat`/`has_ally`/`in_active_war` (۰/۱)؛ فاصله‌ها Manhattanِ صحیح، نسبت‌ها با تقسیمِ صحیحِ round-half-away، اسکنِ دشمن id-sortِ پایدار؛ `context_keys`/`has_context_key`/`safe_default_context`؛ تابِ‌آوری: نبودِ HQ/دشمن/اقتصاد → پیش‌فرضِ امن، هرگز crash و هرگز کلیدِ غایب (MD7.4) — خالص، RefCounted، قطعی، ASCII. خلاصه‌سازِ worldstate در `ai_commander_module.summarize(owner)` است نه در util (MD7.2) |
| `mod_loader.gd` | کشف/بارگذاری مود | `load_mods`, `load_packs` — **پایه‌ی R5/R7** |
| `storage_service.gd` | ریشه‌ی محتوا | `ensure_content_root`, `resolve_pack`, `list_packs` |
| `pack_format.gd` / `pack_reader.gd` / `pack_writer.gd` | فرمت `.nexpack` | `write_from_dir/data`, `read_catalogs` — **پایه‌ی R5** |
| `texture_service.gd` | کش تکسچر | `get_texture` (fallback امن) |
| `localization.gd` | کلید → متن | `load_all`, `set_locale`, `t(key)` |
| `game_settings.gd` | تنظیمات ماندگار | getter/setter اعتبارسنجی‌شده |
| `game_bootstrap.gd` | راه‌اندازی مسابقه | `register_modules`, `load_catalogs`, `load_mods`, `setup_skirmish`, `setup_for_test` — **نقطه‌ی ورود Run/Host (R1)** |

---

## ۳. ماژول‌های گیم‌پلی (`modules/`)

| ماژول | فایل | مسئولیت | توابع مهم برای ۰.۶.۰ |
|---|---|---|---|
| Map | `map/map_module.gd` | گرید نقشه | `create_grid`, `is_walkable`, `find_path`, `get/set_terrain` |
| Map | `map/scenario_loader.gd` | بارگذاری سناریو | `load_scenario_from_catalog`, `list_scenarios` (**R1.2**), `apply_scenario` |
| Units | `units/units_module.gd` | نیروها | `spawn_unit` (**BUG-2**), `_advance_movement` (**BUG-3**), `_handle_move_command`, `_compute_path` |
| Buildings | `buildings/buildings_module.gd` | ساختمان‌ها | `place_building`, `queue_unit` (**BUG-2: اسپاون**), `upgrade_building`, `_tile_free_for_build` |
| Economy | `economy/economy_module.gd` | منابع | `on_tick` (**BUG-1: تولید per-tick**), `try_spend`, `add_resource` |
| Economy | `economy/logistics_module.gd` | کاروان/تدارکات | مسیرهای تأمین |
| Combat | `combat/combat_module.gd` | نبرد/مرگ | `on_tick`, `_acquire_target`, `_apply_damage`, `_credit_kill` (veterancy) |
| TechTree | `tech_tree/tech_tree_module.gd` | تحقیق | `research_blocked_reason`, effects |
| FogOfWar | `fog_of_war/fog_of_war_module.gd` | دید | visible/explored per-viewer |
| Difficulty | `difficulty/difficulty_module.gd` | سختی | presetها + ضرایب |
| HeroFusion | `hero_fusion/hero_fusion_module.gd` | ترکیب قهرمان | recipe — **مرجع منطق ترکیب چندبخشی (R8.2 fusable)** |
| AI | `ai_commander/ai_commander_module.gd` | AI تاکتیکی | تولید/حمله |
| AI | `ai_commander/strategic_ai_module.gd` | AI استراتژیک | expand/research/upgrade/push |
| Victory | `victory/victory_module.gd` | برد/باخت | `_evaluate`, `register_player` — **محل افزودن حالت‌های team/ffa/ctf (R1.5/P7.5)** |
| Multiplayer | `multiplayer/lockstep_module.gd` | lockstep | `start_session`, `submit_local_command`, `can_simulate_tick`, `receive_checksum` (**R6/R7**) |
| Multiplayer | `multiplayer/network_session.gd` | هماهنگ‌کننده‌ی UI شبکه | `host`, `join`, `begin_session` — **پایه‌ی lobby (R6)** |
| Multiplayer | `multiplayer/enet_transport.gd` | ترنسپورت آنلاین ENet | `host/join/close`, `broadcast_turn/checksum` — **پایه‌ی LAN (R6.2/P5.1)** |
| Multiplayer | `multiplayer/loopback_transport.gd` | ترنسپورت درون‌پردازه | مولتی لوکال/تست |

---

## ۴. رندر (`render/`) و رابط (`ui/`)

| فایل | نقش | نکته برای ۰.۶.۰ |
|---|---|---|
| `render/render_adapter.gd` | پل یک‌طرفه sim→رندر | `fit_map_to_viewport`, `center_camera_on`, `screen_to_tile` (**BUG-3/BUG-4**), `set_style`, `toggle_style` |
| `render/style_simple/…` | سبک تخت | پیش‌فرض فعلی (**BUG-5: ضعیف**) |
| `render/style_detailed/…` | سبک سایه‌دار | نوار HP/رتبه/خط حرکت |
| `render/style_sprite/…` | سبک تکسچرمحور | **باید پیش‌فرض شود (P1.2)** |
| `ui/mobile/game_hud.gd` | HUD موبایل + ورودی لمسی | `_handle_tap` (**BUG-3**)، بدون zoom/pan (**BUG-4**)، محل افزودن کنترل‌گروه/مینی‌مپ (**R11/R12**) |
| `ui/desktop/desktop_hud.gd` | HUD دسکتاپ | کیبورد/ماوس |
| `ui/shared/main_menu.gd` | منوی اصلی | تک‌نفره/چندنفره/تنظیمات/مود ادیتور — **محل ورود به منوی شروع (R1)** |
| `ui/shared/options_menu.gd` | تنظیمات | locale/style/content_path |
| `ui/shared/mod_editor.gd` | 🔴 مود ادیتور فعلی (فقط hp/cost/color) | **باید کامل بازسازی شود (R8/P6)** |
| `ui/shared/map_editor.gd` + `tile_grid.gd` | ادیتور نقشه (پایه) | **ارتقا در P6.7 (زوم/دریا/ساحل/آبجکت)** |
| `ui/shared/custom_games.gd` | لیست بازی‌های سفارشی | `list_scenarios` |
| `ui/shared/ui_scale.gd` | مقیاس GUI | `apply_from_settings` |

---

## ۵. ابزار ادیتور (`tools/`) — 🟢 زیرساخت آماده برای وصل‌کردن UI

> **مهم:** این‌ها مدل‌های headless‌اند که **الان وجود دارند و تست‌شده‌اند**. فاز P6
> فقط باید UI را به این‌ها وصل کند — نه اینکه از صفر بسازد.

| فایل | چه چیزی آماده است |
|---|---|
| `tools/mod_project.gd` | کل مدل مود: کاتالوگ‌های units/buildings/objects/scenarios/tech؛ درخت (`add_child`/`add_sibling`/`rename_node`/`build_tree`/`set_parent`)؛ کارخانه‌ها (`default_unit`/`default_building`/`default_object`/`default_multipart_unit`/`default_multipart_building`)؛ اعتبارسنجی (`validate_unit`/`validate_building`/`validate_object`/`validate`)؛ تصویر (`add_texture_validated`/`unique_texture_name`)؛ manifest (`build_manifest`/`save_pack`/`open_pack`) |
| `tools/stat_registry.gd` | تعریف همه‌ی statها (`needs_value`/`applies_to`/`group`) + `compatible`/`conflicts` (جدول سازگاری چندبخشی)؛ **MD1: Stat به‌عنوان Data** — `load_definitions(catalog)` merge می‌کند، getterهای متادیتا (`value_type`/`category`/`min_of`/`max_of`/`higher_is_better`/`ai_importance`/`affects`)، پرچمِ `is_core`/`is_free`، و `validate_definition` |
| `data/stats/*.json` | **MD1.1:** کاتالوگِ داده‌ی هر Core Stat با متادیتای کامل (`type`/`category`/`min`/`max`/`default`/`higher_is_better`/`ai_importance`/`affects`)؛ در راه‌اندازی (game_bootstrap) قبل و بعدِ modها روی پیش‌فرضِ توکار merge می‌شود |
| `tools/graphic_model.gd` | مدل `graphic{mode,logical_size,parts}` + `validate_layer_sizes` + `validate_image` (PNG، ۱۶..۵۱۲) |
| `tools/scenario_project.gd` | مدل نقشه/سناریو: قلم land/sea/wall، `place_object`، resize، round-trip |
| `tools/coast_autotile.gd` | `coast_bitmask(x,y)` — ساحل فقط‌رندری |
| `tools/graphic_model.gd` | (بالا) |
| `tools/mod_editor.gd` / `mod_project.gd` / `scenario_project.gd` | مدل‌ها |
| `tools/check_code_policy.gd` | linter انگلیسی‌فقط (CI) |
| `tools/build_release.sh` | بیلد release (P8.6) |
| `tools/gui_project.gd` | (MC7) مدلِ داده‌محورِ GUI: صفحه‌ها→ویجت‌ها (logical_id/rect/icon/display_name)؛ پس‌زمینه‌ی color/image/video با `validate_video_background` (فقط .ogv، حداکثر ۱۶MB/۳۰s)؛ round-trip JSON (`.nexgui`)، save/load |
| `tools/gui_widget_catalog.gd` | (MC7) فهرستِ logical_idهای مجاز برای هر صفحه (تضمینِ «نام ظاهری، کارکرد ثابت») + `validate_project_dict` |
| `ui/shared/gui_render_util.gd` | (MC7) تبدیلِ مدلِ GUI به چیدمانِ رندری با fallback به پیش‌فرض (cosmetic) |
| `ui/shared/gui_editor.gd` | (MC7) صحنه‌ی ادیتورِ GUI: صفحات/ویجت‌ها، ویرایشِ rect/icon/نامِ ظاهری، ویرایشِ پس‌زمینه (رنگ/عکس/ویدئو)، save/export/import — thin view روی `GuiProject` |
| `tools/ai_profile.gd` | (MC12) مدلِ شخصیتِ AI: بردارِ ۳۵ پارامتریِ رفتار + ۹ پروفایلِ پیش‌فرض (data/ai_profiles) + خلاصه/نقش/سبک |
| `tools/ai_builder_util.gd` | (MC14) منطقِ خالصِ سازندهٔ AI: presetهای آرکتایپ، randomizeِ بذرمحور، duplicate/reset/export/import |
| `ui/shared/ai_roster_util.gd` | (MC14) فهرستِ AI (۹ پیش‌فرض + ساختهٔ کاربر) برای match setup: toggle/selected/resolve — id-مرتب |
| `tools/turret_angle_util.gd` | (MC14.5) ریاضیِ زاویه‌ی cosmetic: aim به هدف، fixed از heading/facing، idle-spinِ ساختمانِ دفاعی، `step_toward` |
| `tools/firing_combination_util.gd` | (MC14.4) ترکیبِ بخش‌های شلیکِ نیروهای ادغام‌شده با سقفِ `MAX_COMBINED_FIRING_PARTS` (=۲) — قطعی، بی‌رندر |
| `tools/graphic_facing_edit_util.gd` | (MC14.6) منطقِ خالصِ ویرایشِ facing + firing-part/mount در mod editor: set/toggle/mount با تضمینِ «حداکثر ۱ بخشِ شلیکِ authored» |

---

## ۶. نگاشت خواسته‌ی ۰.۶.۰ → نقطه‌ی شروع در کد

| خواسته | از کجا شروع کن |
|---|---|
| **BUG-1** رشد منابع | `modules/economy/economy_module.gd::on_tick` + `data/buildings/hq.json` |
| **BUG-2** اسپاون روی HQ | `modules/buildings/buildings_module.gd::queue_unit`/`_advance_build_queue` → افزودن `find_free_spawn_tile` |
| **BUG-3** حرکت نیرو | `ui/mobile/game_hud.gd::_handle_tap` + `render/render_adapter.gd::screen_to_tile` |
| **BUG-4** zoom/pan | `ui/mobile/game_hud.gd` (`_gui_input`) + `render_adapter.gd` (`zoom`/`camera_offset`) |
| **BUG-5** ظاهر | `render/style_sprite/*` + `assets/` (فونت/تم/تکسچر) |
| **R1** منوی شروع | صحنه‌ی جدید `scenes/match_setup.tscn` + `ui/shared/match_setup.gd`؛ ورود از `main_menu.gd`؛ خروجی به `game_bootstrap.setup_skirmish` |
| **R2** نوار درصد | ویجت جدید `ui/shared/progress_overlay.gd` |
| **R3/R4** save/load/export | `core/save_system.gd` + صحنه‌ی جدید saveها |
| **R5** export/import مود | `core/pack_writer.gd`/`pack_reader.gd` + UI در مود ادیتور |
| **R6** lobby LAN | `modules/multiplayer/network_session.gd` + `enet_transport.gd` + صحنه‌ی lobby جدید |
| **R7** sync مود | `state_hasher.gd` (hash کاتالوگ) + `pack_writer`/`mod_loader` + transport |
| **R8** مود ادیتور | `ui/shared/mod_editor.gd` (بازسازی) روی `tools/mod_project.gd` |
| **R9** map/object editor | `ui/shared/map_editor.gd` روی `tools/scenario_project.gd`+`coast_autotile.gd` |
| **R10** HQ/flag placement | `modules/map/scenario_loader.gd`+`game_bootstrap.gd`؛ فیلد `flags` در سناریو |
| **R11** کنترل‌گروه | `ui/mobile/game_hud.gd` (سمت UI/انتخاب، از طریق `select_units`) |
| **R12** مینی‌مپ/پنل/layout | `ui/mobile/game_hud.gd` + `scenes/game_main.tscn` |

---

## ۷. بخش‌های WorldState (کلیدهای section)
`map`, `units` (`list`/`selected`/`upgrades`), `buildings` (`list`), `economy`
(`players`), `tech`, `fog`, `difficulty`, `lockstep`, `ui_prefs`. هنگام افزودن
داده‌ی جدید، بخش تازه اضافه کن و در ماژول مربوطه `_ensure_state` بگذار.

## ۸. تست‌ها
همه در `tests/test_runner.gd` (اجرای headless). نام‌گذاری: `test_phase_<x>_*`.
هر فاز جدید (`P#`) باید تست‌های `test_060_p<n>_*` خودش را اضافه کند. خروجی
`0`=سبز، `1`=قرمز.

## ۹. قانون به‌روزرسانی این سند
هر بار فایل/تابع مهمی اضافه/جابه‌جا شد، ردیف مربوطه را همین‌جا به‌روز کن تا AI
بعدی مجبور به خواندن دوباره‌ی کل کد نشود.
