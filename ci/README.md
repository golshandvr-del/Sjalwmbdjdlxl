# CI Workflow files (mirror)

این پوشه یک نسخه‌ی آینه‌ای (mirror) از فایل‌های CI پروژه است.

فایل‌های اصلی در `.github/workflows/` قرار دارند ولی چون توکن GitHub App
اجازه‌ی نوشتن روی مسیر `workflows` را ندارد، آن‌ها روی این remise (GitHub)
پوش نمی‌شوند. این کپی برای جلوگیری از گم‌شدن محتوای CI نگهداری می‌شود.

- `ci.yml` — تست headless (Godot 4.3) + linter CODE_POLICY.
- `build-android.yml` — بیلد اندروید (arm64-v8a).

برای فعال‌سازی مجدد روی GitHub، محتوای این فایل‌ها را در
`.github/workflows/` قرار دهید (نیاز به توکن با مجوز `workflows`).
