> **AI agents (OpenHands etc.): read `AGENTS.md` first. It takes precedence over this
> file for AI-driven work.** Corrections to the rules below (decision DEC-003 in
> `docs/ai/DECISIONS.md`): the git remote is `origin` (not `github`); AI agents commit
> and push immediately to their task branch `oh/<task-id>-<slug>`, never to `main`;
> rule 3 (`project-nexus/` folder) is obsolete — the repository root is the project.

# ⛔ قوانین الزامی و غیرقابل نادیده‌گرفتن برای هر عامل/توسعه‌دهنده (AGENT RULES)

> این فایل یک **دستور الزامی** است. هر عامل هوش مصنوعی یا توسعه‌دهنده‌ای که روی این
> مخزن کار می‌کند، **موظف** است قبل از هر کاری این فایل را بخواند و مو به مو رعایت کند.

---

## 🔴 قانون شماره ۱ — COMMIT فوری بعد از هر تغییر (مهم‌ترین قانون)

**هر تغییری در هر فایلی باید بلافاصله بعد از اعمال تغییر در گیت‌هاب `commit` شود.**

دلیل: ممکن است کاملاً ناگهانی در وسط کار، گفتگو/نشست قطع شود و کار از دست برود.

قواعد اجرایی:
- هر **ادیت** در هر فایل پروژه → بلافاصله `git add <file> && git commit && git push`.
- هر **ایجاد فایل جدید** → بلافاصله `git add <file> && git commit && git push`.
- **تا commit (و push) انجام نشود، نمی‌توان سراغ ادیت یا ایجاد فایل جدید رفت.**
- هرگز چند تغییر را جمع نکن و «بعداً یکجا commit می‌کنم» ممنوع است.

الگوی دستور استاندارد:
```bash
git add <changed_file>
git commit -m "<short-desc of the single change>"
git push origin <your-task-branch>   # AI agents: never main (see AGENTS.md)
```

---

## 🟠 قانون شماره ۲ — همیشه اسناد را به‌روز نگه‌دار

بعد از هر مجموعه تغییر معنادار، فایل‌های زیر باید به‌روز شوند (و طبق قانون ۱ commit شوند):
- `docs/STRUCTURE.md` (سند مرجع فازبندی و وضعیت)
- `README.md`
- `docs/ai/PROJECT_STATE.md` (وضعیت تأییدشده و Known Issues)
- سایر فایل‌های `docs/*.md` مرتبط

## 🟠 قانون شماره ۳ — کل پروژه در یک پوشه واحد

کل کد پروژه در ریشه‌ی همین repository نگهداری می‌شود (پوشه‌ی جداگانه‌ی `project-nexus/` منسوخ است — DEC-003).

## 🟠 قانون شماره ۴ — سیاست کد

- کد منبع (`core/ modules/ ui/ render/ tools/ scenes/`) باید **ASCII خالص** باشد.
- اسناد `docs/*.md` می‌توانند فارسی باشند (تصمیم عمدی پروژه).
- هرجا تست و کد اختلاف داشتند، پیش‌فرض این است که کد محصول درست و تست کهنه است،
  مگر شواهد خلافش.

---

> **یادآوری نهایی:** قانون شماره ۱ (commit فوری) بر همه‌ی قوانین دیگر اولویت دارد.
