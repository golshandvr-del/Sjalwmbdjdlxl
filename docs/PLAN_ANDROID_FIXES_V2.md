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

## فاز MB1 — درستیِ گیم‌پلیِ پایه: مالکیت، مقصدِ pause، مینی‌مپ (باگ‌های ۱، ۲، ۳) 🔴

**چرا با هم:** هر سه در «مسیرِ انتخاب/فرمانِ نیرو + رندرِ read-only» ریشه دارند و
همگی قطعیت‌محورند؛ اصلاحشان با هم از رگرسیونِ متقابل جلوگیری می‌کند.

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

## فاز MB3 — کلیدِ back اندروید (باگ ۶) 🔴

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
- **MB3.4:** تست‌ها (منطقِ پشته‌ی ناوبری به‌صورتِ util خالص) + commit/push.

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
