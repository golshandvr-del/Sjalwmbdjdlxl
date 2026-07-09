# برنامه‌ریزی و فازبندی — رفع باگ‌های نسخه‌ی اندروید (دور دوم، فاز MB)

> **دامنه:** این سند مخصوصِ ۲۹ باگِ جدیدی است که کاربر پس از فازِ `MA` (که کامل شد)
> روی گوشیِ اندروید گزارش کرده. تمرکز همچنان **نسخه‌ی اندروید** است
> (طبق درخواست: «اول اندرویدش ساخته بشه»).
>
> **قانونِ کاریِ الزامی (از `AGENT_RULES.md` قانون ۱ — مهم‌ترین قانون):**
> بعد از هر ادیت روی هر فایل → بلافاصله `git add + commit + push`.
> بعد از هر ۲–۳ تغییر → یک push جمعی هم مطمئن شود.
> چرخه‌ی الزامی: **«Edit → Commit → Edit → Commit»** تا پایانِ کار.
>
> **محیط تست:** `Godot v4.x` (headless) — هر فاز باید تست‌های خودش را به
> `tests/test_runner.gd` اضافه کند و کل مجموعه سبز بماند (پایه: `903/903`).
> کد باید **ASCII خالص** باشد (قانون ۴). اسناد می‌توانند فارسی باشند.
>
> **پیش‌نیازِ درک:** این سند مکملِ `docs/CODE_MAP.md` (کجا در کد) و
> `docs/PLAN_ANDROID_FIXES.md` (فازِ MA پیشین) است.

---

## ۰. جدولِ نگاشتِ باگ‌ها به کد (منبعِ واحدِ حقیقت)

| # | باگِ گزارشِ کاربر | ریشه‌ی احتمالی در کد | فاز | شدت |
|---|--------------------|----------------------|-----|-----|
| 1 | می‌توانم نیروهای AIِ هم‌تیمی را کنترل کنم | `ui/mobile/game_hud.gd` + `ui/desktop/desktop_hud.gd`: انتخاب با `LOCAL_PLAYER` است ولی فیلترِ مالکیت روی «هم‌تیمی‌ها» نشتی دارد | MB1 | 🔴 |
| 2 | در حالت pause، بلوکِ مقصد و خطِ راهنما نشان داده نمی‌شود؛ چند نیرو مقصدِ یکسان می‌گیرند و روی هم می‌افتند | `ui/mobile/game_hud.gd` (نبودِ نمایشِ مقصدِ در صف)، `core/command_queue.gd`/lockstep در حالت pause، `modules/units/units_module.gd::_handle_move_command` (formation) | MB1 | 🔴 |
| 3 | در مینی‌مپ نیروهای دشمن دیده می‌شوند | `ui/shared/minimap.gd::_draw` — بدونِ فیلترِ `fog_viewer` | MB1 | 🔴 |
| 4 | در منوی شروع، سمتِ راستِ منوهای کشویی توضیح/برچسب (`Name:` و…) نیست | `ui/shared/match_setup.gd::_add_labeled_option` — برچسب هست ولی چیدمان/وضوح ناقص | MB2 | 🟠 |
| 5 | در بازیِ تک‌نفره امکانِ گروه‌بندیِ AIها (مثلِ منوی host) نیست | `ui/shared/match_setup.gd` + پنلِ گروه‌بندیِ lobby باید بازاستفاده شود | MB2 | 🟠 |
| 6 | کلیدِ back گوشی به‌جای بازگشت به منوی قبلی، از بازی خارج می‌شود | همه‌ی صحنه‌ها: نبودِ `NOTIFICATION_WM_GO_BACK_REQUEST`/`ui_cancel` handler | MB3 | 🔴 |
| 7 | بازی همیشه افقی است و بعضی کلیدهای منو بیرونِ صفحه‌اند؛ چرخش کار نمی‌کند | `project.godot` orientation + رفتارِ auto در `game_settings`؛ منوها responsive نیستند | MB4 | 🔴 |
| 8 | تنظیمات باید به‌جای گزینه‌ی منو، یک چرخ‌دنده‌ی گوشه‌ی بالا-راست باشد | `ui/shared/main_menu.gd` (+ دکمه‌ی gear سراسری) | MB2 | 🟠 |
| 9 | وضعیتِ ready بازیکنان به host نشان داده نمی‌شود | `ui/shared/lobby.gd` + `modules/multiplayer/network_session.gd` (`ready_state` نمایش داده نمی‌شود) | MB5 | 🔴 |
| 10 | بات‌های موجود در بازی برای فردِ join‌شده نشان داده نمی‌شوند | `ui/shared/lobby.gd` (clientِ join اسنپ‌شاتِ AI/slots را نمی‌بیند) | MB5 | 🔴 |
| 11 | بعد از یک join موفق و بازگشت، دیگر نمی‌توان دوباره join شد مگر با بستنِ کاملِ اپ | `ui/shared/lobby.gd`/`network_session.gd`/`lan_discovery.gd` (نبودِ teardown/cleanup هنگام خروج) | MB5 | 🔴 |
| 12 | در مولتی‌پلیر یک IP هست که کاربردش نامعلوم است؛ حتی برای host هم IPِ فعلی نمایش داده نمی‌شود | `ui/shared/lobby.gd` (نبودِ نمایشِ IPِ محلیِ host + برچسبِ گویا) | MB6 | 🟠 |
| 13 | بعد از انتخابِ سرورِ یافت‌شده باید یک صفحه‌ی جدیدِ فقط-خواندنی (شبیهِ صفحه‌ی host) باز شود | `ui/shared/lobby.gd` (client بعد از انتخاب باید به یک view لابیِ read-only برود) | MB5 | 🟠 |
| 14 | چون readyِ client به host نمی‌رسد، بازی هرگز شروع نمی‌شود | همان ریشه‌ی #9 — `ready_state` round-trip ناقص | MB5 | 🔴 |
| 15 | چرا هر بار باید بینِ desktop و mobile انتخاب کنم؟ باید به تنظیماتِ کلی منتقل شود، خودکار بر اساسِ دستگاه و قابلِ تعویض | `ui/shared/match_setup.gd` (`_style_option`) → `core/game_settings.gd` + `options_menu.gd` | MB4 | 🟠 |
| 16 | GUIِ ساده و تک‌ستونی؛ در landscape بهتر است دو-ستونی شود | `ui/mobile/game_hud.gd` + `responsive_layout_util.gd` (چیدمانِ دکمه‌ها) | MB4 | 🟠 |
| 17 | باید در تنظیمات بشود حالتِ صفحه (افقی/عمودی/خودکار) را انتخاب کرد | `core/game_settings.gd` + `options_menu.gd` + اعمالِ orientation در زمانِ اجرا | MB4 | 🟠 |
| 18 | روی گوشیِ دیگر برعکس (عمودیِ قفل‌شده) و کلیدها ریز — GUI نیاز به بازطراحیِ اساسی دارد | `game_settings::auto_scale_for` + کلِ سیستمِ responsive/scale | MB4 | 🔴 |
| 19 | در منوی join باید یا خودکار مدام سرچ کند یا دکمه‌ی ذره‌بین باشد | `ui/shared/lobby.gd` (`_search_edit`/`mag` هست ولی auto-refresh/scan ناقص) | MB6 | 🟠 |
| 20 | در map editor باید بشود عکس به‌عنوان نقشه‌ی بازی بارگذاری کرد | `ui/shared/map_editor.gd` + `tools/scenario_project.gd` (نبودِ background image) | MB7 | 🟠 |
| 21 | در map editor فقط یک رنگ برای پرچم/HQ؛ باید پالتِ ۱۶-رنگ باشد؛ باید بخشِ unit و building جدا باشد (طبقِ mod)؛ جابه‌جاییِ آبجکت‌ها | `ui/shared/map_editor.gd` + `tools/scenario_project.gd` | MB7 | 🔴 |
| 22 | map editor باید ابتدا نام و ابعادِ px را بپرسد، سپس واردِ ویرایش شود | `ui/shared/map_editor.gd` (نبودِ دیالوگِ new-map) | MB7 | 🟠 |
| 23 | mod و map در خودِ Godot اجرا می‌شوند اما در build نصبی هنگ می‌کنند | مسیرهای `res://` در برابرِ `user://`؛ فایلِ IO در export؛ threadها | MB8 | 🔴 |
| 24 | در منوی شروع بازی نمی‌شود نقشه‌ی ساخته‌شده را انتخاب کرد | `ui/shared/match_setup.gd::_populate_scenarios` + `custom_games.gd` (نقشه‌های user:// لیست نمی‌شوند) | MB7 | 🔴 |
| 25 | در mod editor نیروهای چندبخشی دوبخشی‌اند نه سه‌بخشی | `tools/mod_project.gd::default_multipart_unit` (پیش‌فرض `parts=2`) | MB8 | 🟠 |
| 26 | با تغییرِ ابعادِ نیرو، متنِ زیرِ کادرِ عکس باید تغییر کند و فقط عکس با همان نسبتِ ابعاد و حجم/ابعادِ منطقی قبول شود | `ui/shared/mod_editor.gd` + `tools/graphic_model.gd::validate_image` | MB8 | 🟠 |
| 27 | خطای TLS handshake error -29184 در Godot | شبکه/HTTPS (mod_sync/lan یا update check با TLS) | MB9 | 🟡 |
| 28 | هشدارِ RGBAFloat not supported → converting to RGBAHalf | فرمتِ تکسچر/`.import` یا shader که RGBAFloat می‌سازد | MB9 | 🟡 |
| 29 | بازی نوارِ loading ندارد؛ هرجا صبر لازم است باید loading باشد | `ui/shared/progress_overlay.gd` هست ولی همه‌جا وصل نشده | MB10 | 🟠 |

---

## اصولِ طراحی که باید حفظ شوند (بدون استثنا)

1. **جداسازیِ منطق/رندر:** UI فقط می‌خواند و **Command** صادر می‌کند؛ هرگز مستقیم `WorldState` را تغییر نمی‌دهد.
2. **قطعیت (Determinism):** هر تغییرِ اثرگذار بر شبیه‌سازی باید قطعی و مستقل از فریم‌ریت باشد (ترتیبِ پایدارِ کلیدها، بدونِ تصادفِ غیرseeded).
3. **cosmetic بودنِ دوربین/مقیاس/چرخش/مینی‌مپ:** zoom/pan/ui_scale/orientation/fog-render هرگز روی hashِ قطعی اثر نگذارند.
4. **transport-agnostic بودنِ lockstep:** هسته‌ی lockstep نباید کدِ سوکت بداند؛ فقط از طریقِ transport.
5. **سازگاریِ `res://` و `user://`:** هر چیزی که در build نصبی خوانده/نوشته می‌شود باید مسیرِ درست را انتخاب کند (باگ ۲۳).

---

# فازبندیِ کار

> هر فاز = یک ناحیه‌ی همگنِ کد. هر فاز به چند **مرحله** (Step) شکسته شده تا طبقِ
> «Edit → Commit» بعد از هر مرحله یک commit ثبت شود. تیکِ ✅ بعد از انجام
> پُر می‌شود. هیچ فازی «تمام» نیست تا (۱) کد + (۲) تستِ headless سبز + (۳)
> commit/push انجام نشده باشد.

---

## فاز MB1 — درستیِ گیم‌پلیِ پایه: مالکیت، مقصدِ pause، مینی‌مپ (باگ‌های ۱، ۲، ۳) ✅ (انجام شد)

**چرا با هم:** هر سه در «مسیرِ انتخاب/فرمانِ نیرو + رندرِ read-only» ریشه دارند و
همگی قطعیت‌محورند؛ اصلاحشان با هم از رگرسیونِ متقابل جلوگیری می‌کند.

**آنچه انجام شد:**
- **MB1.1 (باگ ۳):** `FogUtil` (جدید، خالص) با `should_draw/fog_state`؛ `minimap.gd`
  یگان/ساختمانِ دشمن را از طریقِ `fog_viewer` فیلتر می‌کند تا دشمنِ نادیده در
  مینی‌مپ نشت نکند. تست‌های FogUtil افزوده.
- **MB1.2 (باگ ۱):** `OwnershipUtil` (منبعِ واحدِ حقیقتِ «چه مالکی محلی/قابلِ‌کنترل
  است») + `Nexus.is_locally_controlled(owner)`. هر دو HUD (mobile/desktop) و
  `SelectionUtil.units_in_screen_rect_owned_by` و `TapSelectUtil.unit_at_tile_owned_by`
  انتخاب را فقط به مالک‌های محلی محدود می‌کنند (نه هم‌تیمیِ AI). تست افزوده.
- **MB1.3 (باگ ۲ الف):** `FormationUtil.plan_goals` با مجموعه‌ی «تایل‌های رزروشده‌ی
  بین‌فرمانی» تا چند فرمانِ هم‌تایل هرکدام یک مقصدِ آزادِ یکتا بگیرند
  (`units_module` به آن واگذار می‌کند). تست‌های یکتایی افزوده.
- **MB1.4 (باگ ۲ ب):** خطِ راهنمای حرکت حذف شد؛ فقط یک نشانگرِ مقصدِ cosmetic
  (خارج از hash) باقی ماند تا در حالتِ pause هم بازخوردِ بصری باشد.

**تأیید:** کلِ مجموعه‌ی headless سبز (`933/933`)؛ لینترِ CODE_POLICY بدونِ نقض.

**فایل‌ها:** `ui/mobile/game_hud.gd`, `ui/desktop/desktop_hud.gd`,
`ui/shared/tap_select_util.gd`, `ui/shared/minimap.gd`,
`modules/units/units_module.gd`, `core/placement_planner.gd`, تست‌ها.

**مرحله‌ها:**
- **MB1.1 (باگ ۳ — سریع‌ترین برد):** در `minimap.gd::_draw`، پیش از رسمِ هر
  unit/building، اگر `fog_viewer >= 0` است، فقط چیزهایی رسم شوند که در دیدِ آن
  بازیکن‌اند (از `fog_of_war_module` یا مالکِ خودی). واحد/ساختمانِ دشمنِ نادیده
  حذف شود. تستِ واحد: با `fog_viewer=0`، دشمنِ خارج از دید رسم نشود.
- **MB1.2 (باگ ۱ — نشتیِ کنترلِ هم‌تیمی):** یک منبعِ واحدِ حقیقت برای «چه
  بازیکنی محلی و قابلِ‌کنترل است» بسازید (مثلاً `Nexus.is_locally_controlled(owner)`
  یا در `game_settings`/`session_info`). سپس `_unit_at_tile`/`select_units` در هر
  دو HUD فقط واحدهایی را انتخاب کنند که `owner == LOCAL_PLAYER` (نه هم‌تیمیِ AI).
  تستِ واحد: tap روی واحدِ هم‌تیمیِ AI → `none`/عدمِ انتخاب.
- **MB1.3 (باگ ۲ الف — formation، جلوگیری از روی‌هم‌افتادن):** تأیید/تقویتِ
  `units_module::_handle_move_command` تا چند نیرو با یک/چند فرمانِ هم‌تایل، هر
  کدام به تایلِ آزادِ یکتا بروند. **نکته‌ی pause:** وقتی چند فرمانِ جدا در حالتِ
  pause صف می‌شوند و همه مقصدِ X را دارند، planner باید هنگامِ resolve مقصدهای
  یکتا اختصاص دهد (نه اینکه هر فرمان مستقل X را بگیرد). از `placement_planner.gd`
  استفاده/گسترش دهید. تست: ۳ فرمانِ جدا به تایلِ X → ۳ مقصدِ یکتا.
- **MB1.4 (باگ ۲ ب — نمایشِ مقصدِ در صف در حالت pause):** در HUD، هنگامِ pause
  پس از انتخابِ نیرو و tap روی مقصد، یک نشانگرِ مقصد (و در صورتِ تمایلِ کاربر
  «اگر نباشد بهتر است») رسم شود. طبقِ متنِ کاربر: **خطِ راهنما در حالتِ عادی هم
  «ضایع» است**، پس تصمیم: خطِ راهنما را در هر دو حالت حذف کنیم و فقط یک نشانگرِ
  کوچکِ مقصد (نقطه/پرچمِ کم‌رنگ) نمایش دهیم تا در pause هم بازخوردِ بصری باشد.
  این نشانگر باید cosmetic و خارج از hash باشد.
- **MB1.5:** تست‌های headless برای هر سه + اجرای کلِ مجموعه (بدون رگرسیون) + commit/push.

**معیارِ انجام:** مینی‌مپ فقط دیدِ خودی؛ tap روی AI هیچ انتخابی نمی‌کند؛ n فرمانِ
هم‌تایل → n مقصدِ یکتا؛ در pause نشانگرِ مقصد دیده می‌شود؛ خطِ راهنما حذف شد.

---

## فاز MB2 — منوی شروع، برچسب‌ها، گروه‌بندیِ AIِ تک‌نفره، آیکونِ تنظیمات (باگ‌های ۴، ۵، ۸) 🟠

**فایل‌ها:** `ui/shared/match_setup.gd`, `ui/shared/main_menu.gd`,
`ui/shared/control_group_util.gd`, `scenes/match_setup.tscn`,
`scenes/main_menu.tscn`, `localization/*.json`, تست‌ها.

**مرحله‌ها:**
- **MB2.1 (باگ ۴):** هر ردیفِ `_add_labeled_option` باید یک برچسبِ گویا و
  همیشه-مرئی در سمتِ چپ/بالای هر ورودی داشته باشد (`Name:`, `Map:`,
  `Difficulty:`, …). اطمینان از اینکه برچسب‌ها در چیدمانِ responsive بریده/پنهان
  نمی‌شوند. کلیدهای `ui.setup.*` در `localization/en.json` و `fa.json` کامل شوند.
- **MB2.2 (باگ ۵):** یک پنلِ گروه‌بندیِ AI در Match Setup برای بازیِ تک‌نفره،
  با همان منطقِ گروه‌بندیِ host در lobby (بازاستفاده از `control_group_util.gd`
  یا util مشترک). خروجی در `match_config` ذخیره شود و `game_bootstrap` آن را
  اعمال کند (تیم‌بندیِ AIها).
- **MB2.3 (باگ ۸):** حذفِ گزینه‌ی «Settings» از لیستِ منوی اصلی و افزودنِ یک دکمه‌ی
  چرخ‌دنده (gear) در گوشه‌ی **بالا-راست** که به `options_menu` می‌رود. آیکون از
  یک تکسچر/فونتِ آیکونِ ASCII-safe یا یک `TextureButton`. باید در همه‌ی نسبت‌های
  صفحه در گوشه بماند (responsive).
- **MB2.4:** تست‌ها + commit/push.

---

## فاز MB3 — کلیدِ back اندروید (باگ ۶) ✅ (انجام شد)

**آنچه انجام شد:**
- **MB3.1:** `core/nav_service.gd` — یک utilِ خالصِ ناوبری (بدونِ SceneTree/autoload)
  که منبعِ واحدِ حقیقتِ «back از هر صحنه کجا می‌رود» است: `back_target()`،
  `is_root()`، `is_in_game()`، `known_scenes()`. صحنه‌ی اصلی root است و
  `back_target` برایش `""` می‌دهد تا caller «تأییدِ خروج» بدهد نه خروجِ ناگهانی.
- **MB3.2:** هر صحنه‌ی منو (`main_menu`, `match_setup`, `lobby`, `options_menu`,
  `map_editor`, `mod_editor`, `save_load_menu`, `custom_games`) هندلرِ
  `NOTIFICATION_WM_GO_BACK_REQUEST` + `ui_cancel` دارد که از طریقِ NavService به
  والدِ منطقی برمی‌گردد (نه خروج از اپ).
- **MB3.3:** `ui/mobile/game_hud.gd` — back در حینِ بازی → pause + دیالوگِ تأییدِ
  خروج (هرگز خروجِ ناگهانی).
- **MB3.4:** ۶ تستِ headless برای منطقِ خالصِ NavService در `tests/test_runner.gd`
  (نگاشتِ والد، root فقط برای منوی اصلی، in-game فقط برای صحنه‌های بازی، کاملیِ
  `known_scenes`). fallbackِ امن برای صحنه‌ی ناشناخته پوشش داده شد.

**تأیید:** کلِ مجموعه‌ی headless سبز (`976/976`، ۲ skip)؛ لینترِ CODE_POLICY بدونِ نقض.

**مرحله‌ها (همه انجام شد):**

**فایل‌ها:** یک `autoload`/util ناوبری جدید یا هندلر در هر صحنه:
`ui/shared/main_menu.gd`, `match_setup.gd`, `lobby.gd`, `options_menu.gd`,
`map_editor.gd`, `mod_editor.gd`, `save_load_menu.gd`, `custom_games.gd`,
`ui/mobile/game_hud.gd`, تست‌ها.

**مرحله‌ها:**
- **MB3.1:** یک سرویسِ ناوبریِ سبک (مثلاً `core/nav_service.gd` یا تابع در Nexus)
  که پشته‌ی صحنه‌ها را می‌داند و `go_back()` دارد؛ در نبودِ صحنه‌ی قبلی، به منوی
  اصلی برگردد (نه خروج از اپ).
- **MB3.2:** در هر صحنه، `_notification(NOTIFICATION_WM_GO_BACK_REQUEST)` و/یا
  `_unhandled_input` برای `ui_cancel` → فراخوانیِ `go_back()`. در منوی اصلی،
  back می‌تواند دیالوگِ «خروج؟» بدهد (نه خروجِ ناگهانی).
- **MB3.3:** در حینِ بازی، back → منوی pause/بازگشت به منوی اصلی (با تأیید)،
  نه خروج.
- **MB3.4:** تست‌ها (منطقِ پشته‌ی ناوبری به‌صورتِ util خالص) + commit/push. ✅

---

## فاز MB4 — چرخش/جهت صفحه، انتخابِ خودکارِ دستگاه، بازطراحیِ اساسیِ GUI (باگ‌های ۷، ۱۵، ۱۶، ۱۷، ۱۸) 🔴

**چرا با هم:** همه در «سیستمِ responsive/scale/orientation» ریشه دارند؛ این
بزرگ‌ترین و مهم‌ترین فاز است (کاربر صراحتاً «بازطراحیِ اساسی» خواست).

**فایل‌ها:** `project.godot`, `core/game_settings.gd`,
`ui/shared/options_menu.gd`, `ui/shared/ui_scale.gd`,
`ui/shared/responsive_layout_util.gd`, `ui/mobile/game_hud.gd`,
`ui/shared/main_menu.gd` و بقیه‌ی منوها، `ui/shared/match_setup.gd`, تست‌ها.

**مرحله‌ها:**
- **MB4.1 (باگ ۱۷):** افزودنِ تنظیمِ `screen_orientation` به `game_settings`
  با مقادیرِ `auto` / `portrait` / `landscape` (اعتبارسنجی‌شده، persist‌شده)
  و یک OptionButton در `options_menu`.
- **MB4.2 (باگ ۷ و ۱۸):** اعمالِ orientation در زمانِ اجرا با
  `DisplayServer.screen_set_orientation(...)` بر اساسِ تنظیم؛ `auto` = sensor.
  اطمینان از اینکه بازیِ افقی/عمودی هر دو کار می‌کنند و روی گوشیِ متفاوت قفل
  نمی‌شوند. (ریشه‌ی «یکی افقیِ قفل، یکی عمودیِ قفل» = orientation ثابتِ اشتباه.)
- **MB4.3 (باگ ۱۸ — scale):** بازبینیِ `game_settings::auto_scale_for` تا روی
  DPI/اندازه‌ی واقعیِ صفحه دکمه‌ها هرگز خیلی ریز نشوند؛ یک حداقلِ اندازه‌ی
  لمسیِ منطقی (مثلاً ~۴۸dp) تضمین شود. تست برای چند اندازه/چگالیِ صفحه.
- **MB4.4 (باگ ۱۵):** انتقالِ انتخابِ `desktop`/`mobile` از Match Setup به
  `game_settings` (`ui_mode` با `auto`/`desktop`/`mobile`)؛ پیش‌فرض = خودکار
  بر اساسِ `OS.has_feature("mobile")`/اندازه؛ گزینه در `options_menu`. حذفِ
  `_style_option` از Match Setup و استفاده از تنظیمِ سراسری.
- **MB4.5 (باگ ۱۶):** در `responsive_layout_util`، در حالتِ landscape دکمه‌های
  HUD/منو در **چند ستون** چیده شوند (grid دو-ستونی به‌جای تک‌ستونِ بلند)، و منوها
  هم responsive شوند تا هیچ دکمه‌ای بیرونِ صفحه نیفتد (ریشه‌ی «کلیدها بیرونِ صفحه»).
- **MB4.6:** تست‌های headless (orientation/scale/layout در portrait+landscape و
  چند اندازه) + commit/push.

**معیارِ انجام:** تنظیمِ orientation و ui_mode در options کار می‌کند؛ auto طبقِ
دستگاه؛ در هیچ اندازه/جهتی دکمه بیرونِ صفحه نیست و دکمه‌ها به‌قدرِ کافی بزرگ‌اند.

---

## فاز MB5 — بازبینیِ عمیقِ لابیِ مولتی‌پلیر: ready، بات‌ها، re-join، صفحه‌ی client (باگ‌های ۹، ۱۰، ۱۱، ۱۳، ۱۴) 🔴

**چرا با هم:** همه در جریانِ «host ↔ client sync» در لابی ریشه دارند؛ ۹ و ۱۴ یک
ریشه‌ی مشترک دارند (readyِ client به host نمی‌رسد → بازی شروع نمی‌شود).

**فایل‌ها:** `ui/shared/lobby.gd`, `modules/multiplayer/network_session.gd`,
`modules/multiplayer/enet_transport.gd`, `modules/multiplayer/loopback_transport.gd`,
`modules/multiplayer/lan_discovery.gd`, تست‌ها.

**مرحله‌ها:**
- **MB5.1 (باگ ۹ و ۱۴ — ریشه‌ای):** round-tripِ `ready_state` را تعمیر کنید:
  clientِ join هنگامِ زدنِ Ready باید پیام `ready_state` را روی کانالِ کنترل
  (`net.control`، همان که در MA7 اضافه شد) به host بفرستد؛ host آن را در
  اسنپ‌شاتِ slots اعمال و **به‌همه broadcast** کند و لیبل/آیکونِ Ready را
  به‌ازای هر بازیکن نمایش دهد. دکمه‌ی Start فقط وقتی فعال شود که همه‌ی انسان‌ها
  Ready باشند. تست: شبیه‌سازیِ loopback ready → host وضعیت را می‌بیند و Start فعال.
- **MB5.2 (باگ ۱۰):** host در اسنپ‌شاتِ `slots_update` باید **اسلات‌های AI/bot**
  را هم قرار دهد تا clientِ join همه‌ی بازیکنان (انسان + بات) را ببیند. تست:
  اسنپ‌شات شاملِ باتها → client لیستِ کامل را می‌بیند.
- **MB5.3 (باگ ۱۳):** بعد از انتخابِ سرورِ یافت‌شده توسطِ client، به‌جای نمایشِ
  گزینه‌ها در همان صفحه، به یک **view لابیِ فقط-خواندنی** برود که شبیهِ صفحه‌ی
  مدیریتِ host است ولی فیلدها غیرقابلِ ویرایش‌اند و فقط دکمه‌ی Ready/Leave دارد.
- **MB5.4 (باگ ۱۱ — re-join):** هنگامِ خروجِ client/host از لابی (back/leave)،
  همه‌ی منابعِ شبکه teardown شوند: `network_session.close()`، بستنِ transport،
  توقفِ `lan_discovery` (browse + beacon)، پاکسازیِ slotها و سیگنال‌ها. تضمینِ
  اینکه ورودِ دوباره یک نشستِ تازه بسازد (بدونِ نیاز به بستنِ اپ). تست: host/join
  → leave → دوباره join موفق.
- **MB5.5:** تست‌های headless (loopback برای ready/slots/teardown) + commit/push.

**معیارِ انجام:** host وضعیتِ Ready را می‌بیند؛ client باتها را می‌بیند؛ صفحه‌ی
read-only باز می‌شود؛ leave→re-join بدونِ بستنِ اپ کار می‌کند؛ بازی شروع می‌شود.

---

## فاز MB6 — نمایشِ IP و اسکنِ شبکه در لابی (باگ‌های ۱۲، ۱۹) 🟠

**فایل‌ها:** `ui/shared/lobby.gd`, `modules/multiplayer/lan_discovery.gd`,
`localization/*.json`, تست‌ها.

**مرحله‌ها:**
- **MB6.1 (باگ ۱۲):** برای **host**، IPِ محلیِ فعلی را با
  `IP.get_local_addresses()` (فیلترِ IPv4 غیرِ loopback) پیدا و با یک برچسبِ گویا
  نمایش دهید: «آدرسِ این میزبان: `192.168.x.y`» تا clientها بدانند به کجا وصل شوند.
  برای client، فیلدِ IP باید برچسبِ روشن داشته باشد که کاربردش معلوم باشد
  (یا اگر با discovery خودکار کار می‌کند، فیلدِ دستی مخفی/اختیاری شود).
- **MB6.2 (باگ ۱۹):** منوی join یا **auto-refresh** دوره‌ای (تایمرِ هر ~۲ ثانیه
  browse) داشته باشد، یا یک **دکمه‌ی ذره‌بین** که با زدنش یک اسکن اجرا شود
  (`_search_edit`/`mag` هست — منطقِ scan/refresh را کامل و به دکمه وصل کنید).
  ترجیحاً هر دو: auto-refresh + دکمه‌ی دستی. یک نوارِ loading کوچک حینِ اسکن.
- **MB6.3:** تست‌ها + commit/push.

---

## فاز MB7 — بازسازیِ Map Editor: نام/ابعاد، عکسِ پس‌زمینه، پالتِ رنگ، unit/building، جابه‌جایی، انتخابِ نقشه (باگ‌های ۲۰، ۲۱، ۲۲، ۲۴) 🔴

**فایل‌ها:** `ui/shared/map_editor.gd`, `ui/shared/tile_grid.gd`,
`tools/scenario_project.gd`, `ui/shared/match_setup.gd`, `ui/shared/custom_games.gd`,
`core/data_loader.gd`/`storage_service.gd` (لیستِ نقشه‌های user://), تست‌ها.

**مرحله‌ها:**
- **MB7.1 (باگ ۲۲):** هنگامِ ورود به Map Editor، ابتدا یک دیالوگ نام + ابعاد (به px)
  بگیرد، سپس واردِ صفحه‌ی ویرایش شود. اعتبارسنجیِ نام (ASCII/طول) و ابعاد
  (حداقل/حداکثرِ منطقی). ابعاد → گریدِ `scenario_project`.
- **MB7.2 (باگ ۲۰):** امکانِ بارگذاریِ یک عکس به‌عنوانِ پس‌زمینه/نقشه‌ی بازی
  (background layer). ذخیره در `user://` و ارجاع در سناریو؛ رندر زیرِ گرید.
  اعتبارسنجیِ حجم/ابعاد تا هنگ نکند.
- **MB7.3 (باگ ۲۱ الف — پالتِ رنگ):** یک پالتِ ثابتِ ۱۶-رنگ. کاربر بعد از انتخابِ
  آیتم (flag/HQ/…)، از پالت یک رنگ (تیم/مالک) انتخاب و سپس روی نقشه قرار دهد.
- **MB7.4 (باگ ۲۱ ب — unit/building جدا):** به‌جای بخشِ عمومیِ «unit»، دو بخشِ
  مجزا: **Units** و **Buildings**. هر کدام هنگامِ انتخاب، فهرستِ نیروها/ساختمان‌های
  **همان mod** را از کاتالوگ بیاورد تا کاربر انتخاب و روی زمین بگذارد.
- **MB7.5 (باگ ۲۱ ج — جابه‌جایی):** امکانِ انتخاب و **جابه‌جاییِ** هر آیتمِ
  قرارداده‌شده روی نقشه (drag یا select-then-move) + حذف.
- **MB7.6 (باگ ۲۴):** نقشه‌های ذخیره‌شده (user://) باید در `match_setup`
  (`_populate_scenarios`) و `custom_games` لیست شوند تا در شروعِ بازی قابلِ انتخاب
  باشند. round-trip: بساز → ذخیره → در منوی شروع انتخاب کن → بازی شود.
- **MB7.7:** تست‌ها (scenario_project: resize/place/move/background + لیستِ نقشه‌ها)
  + commit/push.

---

## فاز MB8 — Mod Editor و پایداریِ build نصبی (باگ‌های ۲۵، ۲۶، ۲۳) 🔴

**فایل‌ها:** `tools/mod_project.gd`, `tools/graphic_model.gd`,
`ui/shared/mod_editor.gd`, `core/storage_service.gd`, `core/pack_reader.gd`/
`pack_writer.gd`, `ui/shared/map_editor.gd`, تست‌ها.

**مرحله‌ها:**
- **MB8.1 (باگ ۲۵):** `default_multipart_unit`/`default_multipart_building`
  پیش‌فرض را از `parts=2` به `parts=3` تغییر دهید (سقف `MAX_PARTS=3` است). تأیید
  که UIِ mod editor سه بخش را نشان می‌دهد. تست: پیش‌فرضِ چندبخشی = ۳ بخش.
- **MB8.2 (باگ ۲۶):** در `mod_editor`, وقتی کاربر ابعادِ منطقیِ نیرو (مثلاً
  `20x10 px`) را تغییر می‌دهد، متنِ زیرِ کادرِ آپلود باید به‌روز شود («عکسی با
  نسبتِ 2:1، بین X تا Y px، حداکثر Z KB»)، و `graphic_model::validate_image` فقط
  عکس‌هایی با **همان نسبتِ ابعاد** و در بازه‌ی منطقیِ حجم/ابعاد را بپذیرد تا بازی
  هنگ نکند. تست: عکسِ بد-نسبت رد، عکسِ درست قبول.
- **MB8.3 (باگ ۲۳ — بحرانی، پایداریِ build):** ریشه‌یابیِ هنگ‌شدنِ mod/map در
  build نصبی. علتِ محتمل: خواندن/نوشتنِ فایل با مسیرِ `res://` که در export
  فقط-خواندنی/بسته‌بندی‌شده است، یا IOِ همزمانِ مسدودکننده. راه‌حل: همه‌ی نوشتن‌ها
  به `user://` بروند؛ خواندنِ محتوای کاربر از `user://`، محتوای پایه از `res://`؛
  از `storage_service` به‌عنوانِ لایه‌ی واحد استفاده شود. IOِ سنگین در صورتِ نیاز
  با نوارِ loading (فاز MB10) و بدونِ مسدودسازیِ حلقه‌ی اصلی. تست: round-trip
  ذخیره/بازخوانیِ mod و map از مسیرِ `user://`.
- **MB8.4:** تست‌ها + commit/push.

> **توجه:** باگ ۲۳ فقط با build واقعیِ نصبی قطعی تأیید می‌شود؛ در headless منطقِ
> مسیر (`res://` vs `user://`) و round-trip را تست می‌کنیم و در سند علامتِ
> «نیازمندِ تأییدِ روی دستگاه» می‌گذاریم.

---

## فاز MB9 — ارورها/هشدارهای Godot: TLS و RGBAFloat (باگ‌های ۲۷، ۲۸) 🟡

**فایل‌ها:** `modules/multiplayer/mod_sync.gd`/هرجا HTTPS/TLS استفاده می‌شود،
`assets/**/*.import` و هر منبعِ تکسچرِ RGBAFloat، `render/*`.

**مرحله‌ها:**
- **MB9.1 (باگ ۲۷ — TLS -29184):** خطای `TLS handshake error -29184` معمولاً یعنی
  peer اتصال را بست/گواهی نامعتبر. محلِ استفاده از TLS/HTTPS را بیابید (به‌احتمال
  mod_sync یا یک update/version check). اگر لازم نیست، حذف/غیرفعال؛ اگر لازم است،
  مدیریتِ خطا + timeout + پیامِ کاربرپسند به‌جای spam کردنِ ارور. برای LAN از TLS
  استفاده نشود.
- **MB9.2 (باگ ۲۸ — RGBAFloat):** منبعی که تکسچرِ `RGBAFloat` می‌سازد را پیدا کنید
  (احتمالاً یک تنظیمِ import یا یک Image ساخته‌شده در کد). به یک فرمتِ سازگار با
  GL Compatibility (مثلِ `RGBA8` یا `RGBAHalf`) تغییر دهید تا هشدارِ تبدیل حذف
  شود. هشدار بی‌خطر است ولی باید تمیز شود.
- **MB9.3:** commit/push (این فاز عمدتاً تحقیق + اصلاحِ کوچک است).

---

## فاز MB10 — نوارِ Loading سراسری (باگ ۲۹) 🟠

**فایل‌ها:** `ui/shared/progress_overlay.gd` (موجود),
`core/game_bootstrap.gd`, `ui/shared/*` (منوها), `ui/shared/lobby.gd`,
`ui/shared/map_editor.gd`, `ui/shared/mod_editor.gd`, تست‌ها.

**مرحله‌ها:**
- **MB10.1:** `progress_overlay.gd` را به یک کامپوننتِ قابلِ‌استفاده‌ی مجدد و
  یکدست تبدیل/تأیید کنید (show/hide + متن + درصد/نامعین).
- **MB10.2:** وصل‌کردنِ overlay به هر عملیاتِ صبردار: بارگذاریِ کاتالوگ/مود در
  bootstrap، بارگذاریِ صحنه‌ی بازی، اسکنِ شبکه (MB6)، ذخیره/بازخوانیِ نقشه/مود،
  آپلود/اعتبارسنجیِ عکس. برای عملیاتِ کوتاه از حالتِ نامعین (indeterminate)،
  برای مراحلِ چندگامی از درصد استفاده شود.
- **MB10.3:** تست‌ها (منطقِ show/hide/progress) + commit/push.

---

# ترتیبِ اجرا و معیارِ نهایی

**ترتیبِ پیشنهادی (بر اساسِ اثر/وابستگی):**
`MB1 → MB3 → MB2 → MB4 → MB5 → MB6 → MB7 → MB8 → MB10 → MB9`

**پیشرفتِ فعلی:** MB1 ✅ | MB3 ✅ | MB2 (بعدی) → بقیه در انتظار.

- **MB1** اول: باگ‌های گیم‌پلیِ آزاردهنده و کم‌ریسک (برد سریع).
- **MB3** زود: کلیدِ back مستقل و پرتکرار است.
- **MB4** پیش از map/mod editor: چون GUIِ responsive زیربنای همه‌ی صفحه‌هاست.
- **MB5/MB6** با هم: کلِ مولتی‌پلیر.
- **MB7/MB8** با هم: ادیتورها + پایداریِ build.
- **MB10** نزدیکِ آخر: loading را روی همه‌ی جریان‌های نهایی‌شده وصل می‌کند.
- **MB9** آخر: پاکسازیِ ارور/هشدار.

**هر فاز — چرخه‌ی الزامی:**
1. کد را طبقِ مرحله‌ها بنویس.
2. تستِ headless اضافه کن؛ کلِ مجموعه سبز بماند (بدونِ رگرسیون).
3. لینترِ `CODE_POLICY` بدونِ نقض (کد ASCII خالص).
4. بعد از **هر** ادیت → `git add + commit + push` (قانون ۱).
5. اسناد (`BUG_REPORT.md`, `CODE_MAP.md`, `README.md`, همین سند) به‌روز شوند.

**معیارِ «انجام‌شده» برای کلِ کار:**
- هر ۲۹ باگ یا رفع‌شده یا (برای موارد وابسته به دستگاه مثلِ ۲۳/۲۷) علامتِ
  «نیازمندِ تأییدِ روی دستگاه» + منطقِ اصلاح‌شده و تست‌شده.
- کلِ مجموعه‌ی تستِ headless سبز، بدونِ رگرسیون؛ تست‌های جدیدِ هر فاز افزوده.
- لینترِ `CODE_POLICY` بدونِ تخلف.
- اسنادِ `BUG_REPORT.md`, `CODE_MAP.md`, `STRUCTURE.md`, `README.md` به‌روز.

## نگاشتِ سریعِ فاز ← باگ‌ها

| فاز | باگ‌ها | خلاصه |
|-----|--------|-------|
| MB1 | 1, 2, 3 | مالکیت، مقصدِ pause/formation، مینی‌مپ |
| MB2 | 4, 5, 8 | برچسب‌های منو، گروه‌بندیِ AIِ تک‌نفره، آیکونِ تنظیمات |
| MB3 | 6 | کلیدِ back اندروید |
| MB4 | 7, 15, 16, 17, 18 | orientation، انتخابِ دستگاه، بازطراحیِ GUI |
| MB5 | 9, 10, 11, 13, 14 | لابیِ مولتی‌پلیر (ready/bots/re-join/client view) |
| MB6 | 12, 19 | نمایشِ IP + اسکنِ شبکه |
| MB7 | 20, 21, 22, 24 | بازسازیِ Map Editor + انتخابِ نقشه |
| MB8 | 25, 26, 23 | Mod Editor + پایداریِ build |
| MB9 | 27, 28 | ارورهای TLS و RGBAFloat |
| MB10 | 29 | نوارِ loading سراسری |
