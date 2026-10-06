# پک کامل پرامپت‌های تصویری — Project Nexus (نسخه ۲)

> این سند جایگزین بخش ۱ از `ASSET_PROMPTS_fa.md` نمی‌شود، بلکه آن را **کامل** می‌کند.
> هر فایلی که تحویل بدهی، کد بدون هیچ تغییری خودش آن را برمی‌دارد (همه مسیرها
> داده‌محورند: `data/ui_skin/skin.json`، `data/ui_icons/manifest.json`، و فیلد
> `visual.texture` در `data/units/*.json` و `data/buildings/*.json`).
> تا وقتی فایلی نیامده، بازی از جایگزین برنامه‌ای استفاده می‌کند و خراب نمی‌شود.
>
> **مودپذیری:** هر مود می‌تواند همین فایل‌ها را با همین نام در
> `<mod>/textures/...` یا `<mod>/ui_skin/skin.json` جایگزین کند. پس سبک پایه
> را «خنثی و تمیز» نگه داریم تا مودها رویش بسازند.

## قوانین مشترک (برای همه — در انتهای هر پرامپت هم آمده)

- PNG، ۳۲ بیت، sRGB. **بدون متن، بدون واترمارک، بدون امضا.**
- سبک واحد کل بازی: **«Tactical sci-fi command console»** — تیره، تمیز، نیمه‌تخت،
  لبه‌های دقیق، نور لبه‌ای ملایم. پالت پایه:
  پس‌زمینه `#0e1219`، پنل `#161c27`، آبی تأکید `#3d6fb4`، طلایی عنوان `#e1be57`،
  متن `#e0e8f2`. **از بنفش/ارغوانی اشباع پرهیز شود.**
- آیکن‌ها و اسپرایت‌ها: پس‌زمینه **کاملاً شفاف**، سوژه وسط، حاشیه امن ۱۰٪.
- اسپرایت‌های واحد/ساختمان: **نمای از بالا (top-down، کاملاً عمودی)**، چون نقشه
  شبکه‌ای و از بالاست. **رنگ تیم نزن** — بازی خودش زیر هر واحد یک حلقه/قاب رنگ
  تیم می‌کشد؛ بدنه را خاکستری-فلزی خنثی با جزئیات رنگی کم بساز.

---

## بخش A — پس‌زمینه‌های منو (۶ فایل) → `assets/textures/ui/`

اندازه: **1920×1080**، بدون شفافیت (JPG ممنوع، PNG). مرکز تصویر باید آرام و کم‌جزئیات
باشد چون منوها وسط قرار می‌گیرند؛ جزئیات را به لبه‌ها ببر. بازی خودش وینیت و شبکه
روی آن می‌کشد، پس تصویر را زیادی تیره نکن.

| فایل | پرامپت |
|---|---|
| `bg_main_menu.png` | `Wide cinematic key art for a sci-fi real-time strategy game main menu, high orbital view of a dark planet surface at dusk with a glowing holographic tactical grid projected over terrain, faint outlines of a fortified command base at the lower left and an enemy base far right, deep navy and steel-blue palette with subtle warm gold accent lights, calm empty dark center area for menu buttons, atmospheric haze, clean and modern, no text, no logo, no characters, 1920x1080` |
| `bg_match_setup.png` | `Dark sci-fi war-room background, top-down holographic strategy table showing a stylized terrain map with grid lines and two opposing base markers, soft blue hologram glow, steel and navy tones, very dark edges, quiet empty center, minimal detail, no text, no UI elements, 1920x1080` |
| `bg_options.png` | `Minimal dark technical background, close-up of a sleek command console panel with faint circuit traces and soft blue indicator lights out of focus, navy and graphite tones, large calm negative space in the center, subtle depth of field, no text, no symbols, 1920x1080` |
| `bg_lobby.png` | `Dark sci-fi network hub background, abstract globe made of thin glowing blue connection lines and nodes on the right side, dark navy space, faint hexagon pattern, calm empty left and center, no text, no logos, 1920x1080` |
| `bg_editor.png` | `Very subtle dark blueprint workspace background for a level and mod editor, faint engineering grid, thin construction lines and measurement marks at the edges, deep graphite-navy, extremely low contrast so UI panels stay readable, no text, no numbers, 1920x1080` |
| `bg_default.png` | `Generic dark sci-fi interface backdrop, soft gradient from deep navy at top to near black at bottom, faint hexagonal texture, slight blue light bloom at top center, extremely minimal, no text, 1920x1080` |

## بخش B — لوگو (۱ فایل) → `assets/textures/ui/logo.png`

اندازه **1024×512**، پس‌زمینه شفاف.
`Game logo wordmark "PROJECT NEXUS", bold geometric futuristic sans-serif letters, brushed gold metal with a thin bright edge highlight, a small stylized hexagonal node emblem integrated left of the text, clean vector look, centered, transparent background, PNG with alpha, no other text, 1024x512`
> اگر مدل متن را خراب نوشت، فقط نشان شش‌ضلعی را بدون متن بساز (`logo emblem only, no text`) — نام بازی را خود منو با فونت می‌نویسد.

## بخش C — زمین نقشه (۳ فایل) → `assets/textures/`

اندازه **128×128**، **کاملاً قابل تکرار (seamless tileable)**، نمای کاملاً از بالا، بدون سایه جهت‌دار.

| فایل | پرامپت |
|---|---|
| `ground.png` | `Seamless tileable top-down terrain texture, dry dark olive-grey ground with fine gravel and tiny patches of sparse grass, flat even lighting, no shadows, low contrast, game tile, 128x128` |
| `wall.png` | `Seamless tileable top-down texture of rough dark granite rock and boulders seen from directly above, impassable cliff terrain, cool grey tones, flat lighting, game tile, 128x128` |
| `water.png` | `Seamless tileable top-down deep water texture, dark teal-blue with subtle ripples and faint light caustics, flat lighting, game tile, 128x128` |

## بخش D — واحدها (۴ فایل) → `assets/textures/`

اندازه **256×256**، شفاف، top-down، بدنه رنگ خنثی (رنگ تیم را بازی اضافه می‌کند).

| فایل | پرامپت |
|---|---|
| `soldier.png` | `Top-down view of a single futuristic infantry soldier with rifle, seen from directly above, compact readable silhouette, neutral gunmetal grey armor with small light-blue visor glow, clean semi-flat game sprite style, centered, transparent background, PNG alpha, 256x256` |
| `scout.png` | `Top-down view of a light fast scout unit, small two-seat hover bike seen from directly above, slim streamlined shape, neutral grey with a green sensor light, semi-flat game sprite, centered, transparent background, PNG alpha, 256x256` |
| `tank.png` | `Top-down view of a futuristic heavy battle tank seen from directly above, wide treads, large central turret with long cannon pointing up, neutral dark steel with amber detail lights, semi-flat game sprite, centered, transparent background, PNG alpha, 256x256` |
| `hero.png` | `Top-down view of an elite commander hero in heavy powered exosuit with a short cape seen from directly above, larger and more ornate than a normal soldier, gunmetal armor with gold trim and glowing core, semi-flat game sprite, centered, transparent background, PNG alpha, 256x256` |

## بخش E — ساختمان‌ها (۳ فایل) → `assets/textures/`

اندازه **256×256**، شفاف، top-down، شکل مربعی پرکننده ۸۰٪ کادر.

| فایل | پرامپت |
|---|---|
| `hq.png` | `Top-down view of a fortified sci-fi command headquarters building seen from directly above, square footprint, central domed command tower with antenna array, landing pad markings, neutral concrete and steel, small blue lights, semi-flat game sprite, centered, transparent background, PNG alpha, 256x256` |
| `barracks.png` | `Top-down view of a military barracks seen from directly above, rectangular roof with ventilation units, training yard edge and a gate on one side, neutral grey metal roofing, small orange lights, semi-flat game sprite, centered, transparent background, PNG alpha, 256x256` |
| `outpost.png` | `Top-down view of a small forward outpost seen from directly above, compact hexagonal bunker with a sensor mast and sandbag ring, neutral grey and khaki, small cyan light, semi-flat game sprite, centered, transparent background, PNG alpha, 256x256` |

## بخش F — آیکن‌های HUD (۱۷ فایل) → `assets/ui_icons/`

اندازه **128×128**، شفاف. **همه با یک قالب** تا یکدست شوند — فقط `[SUBJECT]` را عوض کن:

`Flat minimal game UI icon of [SUBJECT], single solid off-white color #e0e8f2, thick clean strokes, rounded corners, readable at 32px, centered with 10% padding, no background, transparent PNG alpha, no shadow, no text, 128x128`

| فایل | [SUBJECT] |
|---|---|
| `select.png` | `a mouse cursor arrow inside a dashed selection rectangle` |
| `assign.png` | `a shield badge with a small number slot in its center (leave the slot empty)` |
| `move.png` | `a straight arrow pointing to a target dot` |
| `move_manual.png` | `three dots connected by a zigzag path ending in a flag` |
| `attack.png` | `a crosshair target reticle` |
| `stop.png` | `a solid octagon` |
| `zoom_in.png` | `a magnifying glass with a plus sign` |
| `zoom_out.png` | `a magnifying glass with a minus sign` |
| `settings_gear.png` | `a gear cog with eight teeth` |
| `pause.png` | `two vertical parallel bars` |
| `play.png` | `a right-pointing triangle` |
| `back.png` | `a left-pointing arrow` |
| `message.png` | `a speech bubble` |
| `build.png` | `a hammer crossed with a wrench` |
| `minimap.png` | `a small square map with three dots` |
| `undo.png` | `a counter-clockwise curved arrow` |
| `redo.png` | `a clockwise curved arrow` |

> رنگ را سفید-خاکستری بگذار نه طلایی: بازی آیکن را با رنگ تم رنگ‌آمیزی می‌کند، پس مودها با عوض‌کردن `skin.json` رنگ همه را عوض می‌کنند.

---

## تحویل
فایل‌ها را با **همین نام‌ها** (zip یا تکی) بفرست. من خودم آن‌ها را چک می‌کنم
(اندازه، آلفا، seamless بودن)، اگر لازم بود تغییر اندازه/بهینه‌سازی می‌کنم و در
مسیر درست می‌گذارم. ترتیب پیشنهادی بر اساس اثر بصری: **A → C → D/E → B → F**.
