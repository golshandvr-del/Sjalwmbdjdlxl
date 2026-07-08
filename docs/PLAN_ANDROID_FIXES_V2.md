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
