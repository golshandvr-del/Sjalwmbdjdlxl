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
docs/         مستندات: STRUCTURE.md (مرجع فاز) + CODE_MAP.md (این) + MODDING/CODE_POLICY/RELEASE + ai/ (حافظه‌ی Agentها: ARCHITECTURE/PROJECT_STATE/DECISIONS/GODOT_PITFALLS)
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
| `ai_commander/ai_weight_derivation_util.gd` | **MD5: از بردارِ ۳۵پارامتریِ `AiProfile` به وزنِ نقش‌ها و capabilityها** (شخصیت روی «ارزشِ نقش» اثر می‌گذارد نه نامِ واحد) | `derive_role_weights(profile)` → `role_id -> weight_q` و `derive_capability_weights(profile)` → `capability_id -> weight_q` (fixed-point، knob → وزن با نگاشتِ مستند: aggression/offense/harassment وزنِ harasser/glass_cannon را بالا و defense وزنِ frontline_tank را بالا می‌برد، MD5.3)؛ `derive_weights` هر دو را یک‌جا می‌دهد؛ `preferred_roles(profile, count)` خلاصه‌ی نمایشیِ «این AI چه نقش‌هایی را ترجیح می‌دهد» برای UIِ roster (MD5.4)؛ **در کنارِ** `ai_strategy_derivation_util` (۴ عددِ macro) نه جایگزینِ آن (MD5.2) — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/ai_context_util.gd` | **MD7: بردارِ وضعیتِ واحد و قطعیِ AI** (لینکِ ششم؛ جای‌گزینِ منطقِ پراکنده‌ی `_enemy_near_base`/`_resources`؛ ورودیِ مشترکِ policy MD6، utility MD8/MD9 و تصمیمِ مرحله‌ای MD10) | `build_context(world_summary, owner)` → مجموعه‌کلیدِ بسته و نسخه‌دارِ fixed-point: `base_security`, `enemy_distance`, `economy_gap`, `army_ratio`, `frontline_pressure` (int در `[0..SCALE]`) و پرچم‌های `under_threat`/`has_ally`/`in_active_war` (۰/۱)؛ فاصله‌ها Manhattanِ صحیح، نسبت‌ها با تقسیمِ صحیحِ round-half-away، اسکنِ دشمن id-sortِ پایدار؛ `context_keys`/`has_context_key`/`safe_default_context`؛ تابِ‌آوری: نبودِ HQ/دشمن/اقتصاد → پیش‌فرضِ امن، هرگز crash و هرگز کلیدِ غایب (MD7.4) — خالص، RefCounted، قطعی، ASCII. خلاصه‌سازِ worldstate در `ai_commander_module.summarize(owner)` است نه در util (MD7.2) |
| `ai_commander/ai_policy_util.gd` | **MD6: پروفایلِ Policy — قواعدِ سختِ رفتاری** (لینکِ پنجم؛ وزن‌ها می‌گویند AI چه را ترجیح می‌دهد، policy می‌گوید چه را باید/نباید بکند؛ روی بردارِ Contextِ MD7 ارزیابی می‌شود) | `evaluate(policy, context)` → مجموعه‌ی بسته‌ی پرچم‌ها `{action_flag: bool}`؛ هر قاعده `{when:<condition_key>, op:lt/le/gt/ge, value_q:int, then:<action_flag>}` یک کلیدِ context را fixed-point با `value_q` مقایسه می‌کند و در صورتِ برقراری پرچمش را روشن می‌کند (اعمال به‌ترتیبِ فهرست، override قطعی)؛ condition_keyهای بسته و نسخه‌دار = همان کلیدهای MD7 (`base_security`/`enemy_distance`/`economy_gap`/`army_ratio`/`frontline_pressure`)، action_flagهای بسته = `allow_attack`/`prefer_static_defense`/`prefer_tank_when_pressured`/`prefer_economy`/`avoid_risky_units`/`prefer_harass_when_exposed` (MD6.2)؛ `baseline_flags`/`condition_keys`/`action_flags`/`is_condition_key`/`is_action_flag`/`is_op`/`make_rule`/`is_valid_rule`/`validate_policy`؛ `preset_for_archetype` برای دفاعی/تهاجمی/اقتصادی/فریبکار و `derive_from_profile(profile)` نگاشتِ knobهای `AiProfile` (آستانه‌ی ۰٫۶) → قاعده (MD6.3)؛ تابِ‌آوری: policyِ خالی/نامعتبر → پرچم‌های baseline (حمله مجاز، biasها خاموش) پس رفتارِ فعلی حفظ می‌شود (MD6.4) — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/unit_utility_util.gd` | **MD8: امتیازدهیِ Utilityِ تولیدِ واحد** (لینکِ هفتم؛ AI به‌جای «سرباز hard-code» واحدِ بیشینه‌ی (نیاز×capability) را می‌سازد) | `score_unit(caps, weights, context)` (میانگینِ وزن‌دارِ fixed-point با اثرِ نویزِ context) و `select_best(candidates)` با گره‌گشاییِ پایدار — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/unit_candidate_util.gd` | **MD8.5: مونتاژِ نامزدهای امتیازدهی از کاتالوگِ واحد** | `build_candidates(catalog, stat_registry, affects, weights, context)` → آرایه‌ی `{unit_type, caps, score}` مرتب و قطعی؛ `choose(...)`/fallback به رفتارِ فعلی وقتی کاتالوگ خالی — خالص، RefCounted، ASCII |
| `ai_commander/building_utility_util.gd` | **MD9.1: امتیازدهیِ Utilityِ جای‌گذاریِ ساختمان** (قرینه‌ی MD8 برای ساختمان‌ها) | `derive_needs(context)` → `{defense_need, economy_need, tech_need, frontline_need}` (fixed-point، از بردارِ Contextِ MD7)؛ `value_component(caps, needs)` (dot-productِ نیاز×capabilityِ ساختمان)، `site_component(site_quality, placement_fit)`، `score_building(caps, context, site_quality, placement_fit)` = ارزشِ ساختمان + کوپلِ محل؛ `_mul_div_round` round-half-away — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/site_scoring_util.gd` | **MD9.2: بردارِ کیفیتِ محلِ ساخت (fixed-point)** | `score_site(x, y, world, span)` → مجموعه‌کلیدِ بسته و نسخه‌دار `site_security`/`frontline_value`/`resource_access`/`path_blocking`/`choke_point_control`/`coverage`/`vulnerability`/`synergy_with_existing` (هر کدام q در `[0..SCALE]`)؛ `fold_quality(quality)` تاشُدنِ وزن‌دار به یک اسکالرِ site_quality (vulnerability جریمه)؛ فاصله‌ها Manhattan، اسنپ‌شاتِ گریدِ تخت (index=y*w+x, 0=walkable مطابقِ PathService)؛ تابِ‌آوری با پیش‌فرضِ امن — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/site_topology_util.gd` | **MD9.3: استخراجِ توپولوژیِ گرید (choke/attack-path/نامزدها)** با بازاستفاده از `PathService` | `is_choke`/`find_chokes` (پینچِ ۱-عرض)، `estimate_attack_path(enemy→hq)` (پوششِ نازکِ `PathService.find_path`)، `chokes_on_path(path)` (چوک‌های رویِ مسیرِ حمله)، `candidate_tiles(world, max_radius)` = حلقه‌های Manhattan حولِ HQ + چوک‌های مسیر، de-dup و مرتب‌شده‌ی پایدار بر `(x,y)`، حذفِ HQ/occupied — خالص، RefCounted، قطعی، بدونِ SceneTree/world model، ASCII |
| `ai_commander/building_placement_util.gd` | **MD9.4: انتخابگرِ نهاییِ محلِ ساخت** = بیشینه‌ی (ارزشِ ساختمان × کیفیتِ محل) با گره‌گشاییِ پایدار بر `(x,y)` | `score_placement(caps, context, world, x, y, fit)` (تاشُدنِ کیفیت→`score_building`)، `select_site(caps, context, world, candidates, fit)` → `{x, y, score, found}` (`found=false`, x/y=-1 وقتی نامزدی نیست تا caller به مسیرِ legacy برگردد)، `plan_placement(...)` شمارشِ نامزدها (MD9.3) + انتخاب در یک فراخوان — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/ai_decision_pipeline_util.gd` | **MD10: خطِ لوله‌ی تصمیمِ چهارمرحله‌ای** (لینکِ پایانیِ ستون‌فقراتِ داده‌محور؛ ادغامِ MD6+MD7+MD8+MD9 در یک تصمیمِ صریح؛ متخصص بند ۹) | `decide(context, policy, weights, candidates, params)` → تصمیمِ ساختاریافته `{state, priority, category, kind, target_id, score, detail}`؛ مرحله ۱ `classify_state(context)` (crisis/pressured/developing/dominant از بردارِ Contextِ MD7)، مرحله ۲ `select_priority(state, policy, weights)` (یکی از attack/defense/diplomacy/economy/expansion/research با گره‌گشاییِ پایدارِ مستند)، مرحله ۳ `select_category(priority, state)` (نگاشتِ اولویت→دسته‌ی اکشن)، مرحله ۴ `pick_action(category, candidates)` با واگذاری به scorerهای MD8/MD9 (select_best، id-sort)؛ بدونِ حالتِ داخلیِ ماندگار (MD10 خط ۵۵۱): تابعِ خالصِ ورودی‌های قطعی؛ تابِ‌آوری: کلیدِ غایبِ context/policyِ خالی/نامزدِ خالی → اکشنِ SAFEِ مستند، هرگز crash؛ سازگاریِ عقب‌رو (MD10.5): ماژول همان Commandها را صادر می‌کند و روی pickِ خالی به منطقِ legacy برمی‌گردد — خالص، RefCounted، قطعی، ASCII |
| `ai_commander/ai_learning_util.gd` | **MD11: لایه‌ی یادگیریِ AI** روی وزنِ نقش/ترجیحِ محل/ترجیحِ هدف (نه statِ خام — تأکیدِ متخصص بند ۱۲) با تفکیکِ قطعیتِ MC13 | سطحِ ۱ (درون‌بازی، قطعی، داخلِ hash): `role_delta(success_q, loss_q, rate_q)`، `apply_role_event`/`apply_role_events` (تقویتِ نقشِ موفق، تضعیفِ نقشِ شکست‌خورده)، `apply_pref_event`/`apply_pref_events` (site/target)، همه fixed-point و pure (ورودی را mutate نمی‌کند)؛ نرخِ یادگیری از `learning_bias`ِ AiProfile: `in_match_rate_q(profile)`/`memory_trust_q(profile)` (تنها مرزِ float→q، MD11.4)؛ پادمانِ اکسپلویت (MD11.5): `cap_match_delta(base, weights)` سقفِ تغییرِ هر وزن در یک بازی + `decay_toward_baseline(weights)` بازگشتِ نرم به baseline، با کف/سقفِ سختِ `MIN_WEIGHT_Q`/`MAX_WEIGHT_Q`؛ round-trip قطعیِ snapshotِ worldstate با کلیدهای مرتب: `export_state`/`import_state` (MD11.2)؛ سطحِ ۲ (بین‌بازی، بیرونِ hash، `user://`، الگوی AiReputationStore): `new_memory`/`record_memory(mem, mod, map, role, outcome_q)`/`seed_weights_from_memory(...)` که فقط وزنِ شروعِ بازی را قطعی می‌چیند و هرگز تصمیمِ زنده را غیرقطعی نمی‌کند (MD11.3) — خالص، RefCounted، قطعی، بدونِ RNGِ unseeded، ASCII |
| `mod_loader.gd` | کشف/بارگذاری مود | `load_mods`, `load_packs` — **پایه‌ی R5/R7** |
| `storage_service.gd` | ریشه‌ی محتوا | `ensure_content_root`, `resolve_pack`, `list_packs` |
| `pack_format.gd` / `pack_reader.gd` / `pack_writer.gd` | فرمت `.nexpack` | `write_from_dir/data`, `read_catalogs` — **پایه‌ی R5** |
| `texture_service.gd` | کش تکسچر | `get_texture` (fallback امن) |
| `localization.gd` | کلید → متن | `load_all`, `set_locale`, `t(key)` |
| `game_settings.gd` | تنظیمات ماندگار | getter/setter اعتبارسنجی‌شده |
| `game_bootstrap.gd` | راه‌اندازی مسابقه | `register_modules`, `load_catalogs`, `load_mods`, `setup_skirmish`, `setup_for_test` — **نقطه‌ی ورود Run/Host (R1)** |

---

## ۲.۵ خطِ لوله‌ی تصمیمِ AI داده‌محور (معماریِ دورِ MD — نمای کلی)

> این نمای واحدِ «چطور یک AI بدونِ دانستنِ نامِ واحد تصمیم می‌گیرد» است. هر مرحله یک
> util خالصِ قطعیِ fixed-point (`SCALE=1000`) است؛ هیچ float در مسیرِ تصمیمی که روی
> `state_hasher` اثر دارد باقی نمی‌ماند (قانونِ طلاییِ بند ۲.۱). موتور فهرستِ
> Capability را هرگز تغییر نمی‌دهد؛ مود فقط **مقدارِ** capability را از راهِ
> stat/affects عوض می‌کند (بند ۲.۳/۲.۴).

```
[data/*.json: stat خام]                         (MD1: Stat as Data — StatRegistry)
        |
        v
[affects: Stat -> Capability]                   (MD2: capability_registry + stat_affects_util)
        |
        v
[بردارِ Capabilityِ fixed-point]                (MD3: derived_metrics_util.compute_capabilities)
        |   q = SCALE*v/(v+H) (منحنیِ اشباع) + cost_efficiency/resource_pressure
        v
[Role / Tag]                                    (MD4: role_inference_util -> primary_role)
        |
        +--<-- [AiProfile 35-knob] --> [وزنِ نقش/capability]   (MD5: ai_weight_derivation_util)
        |
        v
[Context Vector]  <-- world summary            (MD7: ai_context_util.build_context)
        |
        v
[Policy flags]    <-- Context                  (MD6: ai_policy_util.evaluate)
        |
        v
[Utility Scoring]                              (MD8 unit_utility_util / MD9 building_utility_util)
        |   score = sum(need_q * capability_q) + context/site
        v
[Staged Decision: state->priority->category->pick]   (MD10: ai_decision_pipeline_util.decide)
        |
        v
[Command صادر می‌شود]  (ai_commander_module / strategic_ai_module — legacy فقط fallback)
        |
        v
[Learning]  سطح۱ درون‌بازی (داخلِ hash) + سطح۲ بین‌بازی (user://، بیرونِ hash)  (MD11: ai_learning_util)
```

**نکاتِ کلیدیِ معماری:**
- **AI فقط با Capability + Role کار می‌کند**، نه با statِ خام و نه با نامِ واحد →
  هر مودِ آینده بدونِ یک خطِ کدِ جدید کار می‌کند (اثباتِ نهایی: تستِ `test_md14_mod_free_stat_round_trip_understood_by_ai`).
- **قطعیت:** کلِ زنجیره صحیح/fixed-point است، مرتب‌سازیِ پایدار بر id، گِردکردنِ
  round-half-away-from-zero؛ حضورِ statِ پویا hashِ شبیه‌سازی را نمی‌شکند
  (تستِ `test_md14_dynamic_stats_do_not_break_determinism`).
- **جداییِ cosmetic/simulation:** نمایشِ UIِ metric/role (MD12) هرگز به
  `core/state_hasher.gd` دست نمی‌زند؛ هر چیزِ اثرگذار بر رفتار از راهِ Command می‌رود.
- **تابِ‌آوری (بند ۲.۵):** statِ غایب → `default_q`، بردارِ ناقص → نقشِ `generic`،
  context/policy/نامزدِ خالی → اکشنِ SAFE؛ هرگز crash/RNGِ بی‌seed.

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
| AI | `ai_commander/strategic_ai_module.gd` | AI استراتژیک | expand/research/upgrade/push؛ **MD9.5:** `_plan_expansion` از `BuildingPlacementUtil` (value×site-quality) برای انتخابِ محل استفاده می‌کند با fallbackِ عقب‌رو به اسکنِ حلقه‌ایِ `_find_build_spot` وقتی نامزدی نباشد؛ اسنپ‌شاتِ گرید/context در `_placement_world_snapshot`/`_placement_context` (بازاستفاده از `AiContextUtil`) ساخته می‌شود؛ **MD10.5:** `_plan_for_player` ابتدا خطِ لوله‌ی `AiDecisionPipelineUtil.decide` را برای اولویتِ کلان اجرا می‌کند و در صورتِ نبودِ تصمیمِ معتبر به منطقِ اولویتِ legacy برمی‌گردد (خروجیِ Commandها بدون تغییر) |
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
| `ui/shared/mod_editor.gd` | 🔴 مود ادیتور فعلی (فقط hp/cost/color) | **باید کامل بازسازی شود (R8/P6)**؛ **MD12.2/12.4: کنترلِ پویا به‌ازای هر stat + تعریفِ Free Stat** روی مدلِ MD1 |
| `ui/shared/stat_editor_util.gd` | **MD12: منطقِ خالصِ UIِ داده‌محورِ Stat** (به‌ازای هر stat یک کنترل، از رویِ StatRegistryِ داده‌محور — بدونِ SceneTree/world model/sim hash، cosmetic) | `stat_ids_for_catalog`/`groups_for` (گروه‌بندی بر `category`، id-sortِ پایدار، MD12.1)، `paginate` (سقفِ نمایشِ موبایل)، `describe_stat` (متادیتای registry)، `control_kind` (اسلایدر/عدد/سوییچ بر `value_type`)، `coerce_value` + clamp به min/max، `with_stat_value` (ویرایشِ خالصِ مدل، MD12.2)، `build_free_stat_definition`/`validate_free_stat` (Free Stat جدید: name/category/type/min/max/default/affects، MD12.4)، `stat_display_name` (کلیدِ پویا `stat.<id>.name` با fallback، MD12.5) — خالص، RefCounted، قطعی، ASCII |
| `ui/shared/map_editor.gd` + `tile_grid.gd` | ادیتور نقشه (پایه) | **ارتقا در P6.7 (زوم/دریا/ساحل/آبجکت)** |
| `ui/shared/custom_games.gd` | لیست بازی‌های سفارشی | `list_scenarios` |
| `ui/shared/ui_scale.gd` | مقیاس GUI | `apply_from_settings` |
| `ui/shared/hud_logic_util.gd` | (T004/T005) منطقِ خالص و مشترکِ دو HUD (DEC-015) | HQ محلی، تحقیقِ بعدی، مالکانِ قابل‌کنترل، سرعت، برچسبِ سبک، نتیجه‌ی مسابقه، تاریخچه‌ی چت، پیشنهادِ مأموریت/پیمان، فهرستِ هدف‌ها |
| `core/save_snapshot_util.gd` | (T003) اعتبارسنجیِ کاملِ snapshot پیش از load/import (DEC-012) | `SaveSnapshotUtil.validate` — all-or-nothing |

---

## ۵. ابزار ادیتور (`tools/`) — 🟢 زیرساخت آماده برای وصل‌کردن UI

> **مهم:** این‌ها مدل‌های headless‌اند که **الان وجود دارند و تست‌شده‌اند**. فاز P6
> فقط باید UI را به این‌ها وصل کند — نه اینکه از صفر بسازد.

| فایل | چه چیزی آماده است |
|---|---|
| `tools/mod_project.gd` | کل مدل مود: کاتالوگ‌های units/buildings/objects/scenarios/tech؛ درخت (`add_child`/`add_sibling`/`rename_node`/`build_tree`/`set_parent`)؛ کارخانه‌ها (`default_unit`/`default_building`/`default_object`/`default_multipart_unit`/`default_multipart_building`)؛ اعتبارسنجی (`validate_unit`/`validate_building`/`validate_object`/`validate`)؛ تصویر (`add_texture_validated`/`unique_texture_name`)؛ manifest (`build_manifest`/`save_pack`/`open_pack`) |
| `tools/stat_registry.gd` | تعریف همه‌ی statها (`needs_value`/`applies_to`/`group`) + `compatible`/`conflicts` (جدول سازگاری چندبخشی)؛ **MD1: Stat به‌عنوان Data** — `load_definitions(catalog)` merge می‌کند، getterهای متادیتا (`value_type`/`category`/`min_of`/`max_of`/`higher_is_better`/`ai_importance`/`affects`)، پرچمِ `is_core`/`is_free`، و `validate_definition` |
| `data/stats/*.json` | **MD1.1:** کاتالوگِ داده‌ی هر Core Stat با متادیتای کامل (`type`/`category`/`min`/`max`/`default`/`higher_is_better`/`ai_importance`/`affects`)؛ در راه‌اندازی (game_bootstrap) قبل و بعدِ modها روی پیش‌فرضِ توکار merge می‌شود |
| `data/test_synthetic/*.json` | **MD13.1:** شش واحدِ مصنوعیِ فقط‌stat‌خام (heavy_tank، fragile_sniper، fast_scout، siege_walker، fast_raider، economy_harvester) به‌عنوانِ **دروازه‌ی کیفیتِ** کلِ دورِ MD؛ تست‌های `test_md13_*` این‌ها را از دیسک بار می‌کنند و از خطِ لوله‌ی واقعی (`raw -> capabilities -> roles -> pick`) عبور می‌دهند تا نقشِ درست و انتخابِ سازگار با شخصیتِ AI را اثبات کنند |
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
`map`, `units` (`list`/`upgrades`), `local_selection` (محلی، خارج از hash)، `buildings` (`list`), `economy`
(`players`), `tech`, `fog`, `difficulty`, `lockstep` (محلی، خارج از hash)، `ui_prefs`. هنگام افزودن
داده‌ی جدید، بخش تازه اضافه کن و در ماژول مربوطه `_ensure_state` بگذار.

## ۸. تست‌ها
همه در `tests/test_runner.gd` (اجرای headless). نام‌گذاری: `test_phase_<x>_*`.
هر فاز جدید (`P#`) باید تست‌های `test_060_p<n>_*` خودش را اضافه کند. خروجی
`0`=سبز، `1`=قرمز.

## ۹. قانون به‌روزرسانی این سند
هر بار فایل/تابع مهمی اضافه/جابه‌جا شد، ردیف مربوطه را همین‌جا به‌روز کن تا AI
بعدی مجبور به خواندن دوباره‌ی کل کد نشود.
