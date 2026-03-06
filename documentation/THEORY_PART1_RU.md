# Полный разбор задания CI/CD Challenge — Часть 1
# Project Scope + Pull Request Verification

> Формат: точная цитата → код → теория → альтернативы → что под капотом.

---

## БЛОК 1: PROJECT SCOPE

---

### «Create a simple TypeScript package (e.g. a sum(a, b) function)»

**Ключевой код — `src/index.ts`:**
```typescript
export function sum(a: number, b: number): number {
    return a + b;
}
export function subtract(a: number, b: number): number { return a - b; }
export function multiply(a: number, b: number): number { return a * b; }
```

**Ключевой код — `tsconfig.json` (важные поля):**
```json
"outDir": "./dist",
"rootDir": "./src",
"declaration": true
```

**Ключевой код — `package.json` (важные поля):**
```json
"main": "./dist/index.js",
"types": "./dist/index.d.ts",
"scripts": { "build": "tsc" }
```

**Теория:**

TypeScript — **надмножество** JavaScript. Любой JS — валидный TS, но не наоборот. TS добавляет **статическую типизацию**: компилятор проверяет типы ДО запуска.

```
Компиляция:

  index.ts (TypeScript)          index.js (JavaScript)
  ┌─────────────────┐          ┌─────────────────┐
  │ function sum(    │   tsc   │ function sum(    │
  │   a: number,     │ ──────> │   a, b) {        │  ← типы СТЁРТЫ
  │   b: number):    │         │   return a + b;  │
  │   number {       │         │ }                │
  │   return a + b;  │         └─────────────────┘
  │ }                │          index.d.ts (Declaration)
  └─────────────────┘          ┌─────────────────┐
                               │ declare function │
                               │ sum(a: number,   │  ← типы СОХРАНЕНЫ
                               │     b: number):  │     для подсказок IDE
                               │     number;      │
                               └─────────────────┘
```

**Что под капотом при `tsc`:**

1. **Парсинг** — `tsc` читает `.ts` файлы и строит AST (Abstract Syntax Tree) — дерево, описывающее структуру кода. Каждая переменная, функция, тип — узел дерева.

2. **Type Checking** — компилятор проходит по AST и проверяет: совместимы ли типы? Если `sum` ожидает `number`, а ты передал `string` — ошибка фиксируется здесь. Это самый *дорогой* этап — в больших проектах занимает 80% времени компиляции.

3. **Emit** — генерация `.js` и `.d.ts`. Типы СТИРАЮТСЯ из `.js` (type erasure) — в рантайме (при выполнении) типов нет, это чисто compile-time проверка. `.d.ts` сохраняет типы отдельно для IDE.

4. **Module Resolution** — `tsc` вычисляет, где находится каждый `import`. `"moduleResolution": "NodeNext"` в нашем tsconfig означает: "Резолви модули так же, как Node.js" (с учётом `exports` в package.json, `.js` расширений и т.д.).

**Почему такой подход, а не другой:**

| Подход | Плюсы | Минусы | Почему не выбрали |
|---|---|---|---|
| **tsc (наш выбор)** | Нативный, нулевая настройка, генерирует `.d.ts` | Не поддерживает бандлинг | Для библиотеки — идеально |
| **esbuild** | В 100x быстрее tsc | НЕ проверяет типы, НЕ генерирует `.d.ts` | Быстро, но теряем главное — типы |
| **tsup** | Обёртка над esbuild + генерация `.d.ts` | Лишняя зависимость | Overkill для простого пакета |
| **Rollup + @rollup/plugin-typescript** | Бандлинг, tree-shaking | Сложная настройка | Для библиотеки бандлинг не нужен |
| **swc** | Быстрый, Rust-based | Экспериментальная поддержка `.d.ts` | Недостаточно стабилен для типов |

Для npm-пакета-библиотеки `tsc` — лучший выбор: он единственный, кто одновременно проверяет типы И генерирует `.d.ts` без сторонних инструментов. Для приложения (сайт, сервер) лучше esbuild/tsup.

---

### «The package must be publishable to npm»

**Ключевой код:**
```json
"name": "@emilmamedov-inno/ts-math-utils"
```
```yaml
# release.yml
- run: |
    echo "//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN}" > ~/.npmrc
    npm publish --access public
```

**Теория:**

**Что под капотом при `npm publish`:**

1. npm читает `package.json` → узнаёт имя, версию, `files`/`.npmignore`
2. Собирает tarball (`.tgz`) — точно как `npm pack`, но не сохраняет файл
3. Отправляет HTTP PUT запрос на `https://registry.npmjs.org/@emilmamedov-inno%2fts-math-utils` с tarball-ом в body
4. Реестр проверяет: токен валидный? Версия не занята? Имя принадлежит этому пользователю?
5. Если всё ок — пакет индексируется и доступен через `npm install` в течение ~30 секунд

**Scoped packages — история:**
До scoped-пакетов npm был "диким западом": кто первый зарегистрировал имя — тот и владеет. Были случаи **name squatting** (захват популярных имён) и даже **typosquatting** (регистрация `loddash` вместо `lodash` с вредоносным кодом). Scoped-пакеты решили эту проблему: `@angular/core` может создать только организация `angular`.

**Почему `--access public`:**
По умолчанию scoped-пакеты приватные (npm Pro, $7/мес). `--access public` публикует бесплатно, но каждый может его скачать.

**Альтернативные реестры (почему мы на npmjs.com):**

| Реестр | Когда использовать |
|---|---|
| **npmjs.com (наш)** | Публичные пакеты для всех |
| **GitHub Packages** | Привязан к GitHub, удобен для приватных пакетов внутри организации |
| **Verdaccio** | Self-hosted, для офлайн-разработки или корпоративных сетей |
| **Artifactory** | Enterprise-уровень, аудит, безопасность |

---

### «Identify and externalize reusable actions»

**Ключевой код:**
```yaml
uses: emilmamedov-inno/cicd-shared-actions/setup-node-deps@main
```
```yaml
# setup-node-deps/action.yml
runs:
  using: 'composite'
  steps:
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: 'npm'
    - shell: bash
      run: npm ci
```

**Теория:**

**Что под капотом при `uses: owner/repo/path@ref`:**

1. GitHub Actions Runner (программа на виртуалке) видит `uses:`
2. Делает `git clone https://github.com/owner/repo.git` с `--branch ref` (или `--depth 1` для SHA)
3. Находит `path/action.yml`
4. Парсит YAML, определяет тип: `composite`, `node20`, или `docker`
5. Для `composite` — просто вставляет шаги из `action.yml` в текущий workflow как будто они были написаны там
6. Для `node20` — запускает Node.js скрипт (указанный в `main:`)
7. Для `docker` — строит/стягивает Docker-образ и запускает контейнер

`composite` — самый простой: это буквально "copy-paste шагов", инкапсулированный в один блок.

**Почему composite, а не другие типы:**

| Тип action | Как работает | Когда использовать |
|---|---|---|
| **Composite (наш)** | Набор shell/uses шагов | Простая автоматизация без кода |
| **JavaScript (node20)** | Node.js скрипт с доступом к @actions/core SDK | Сложная логика, нужен доступ к API |
| **Docker** | Запуск произвольного контейнера | Нужны специфичные инструменты/языки |

Для наших задач (установить Node, проверить npm, создать тег) composite идеален. Писать JavaScript action для `npm ci` — оверинжиниринг.

**`npm ci` vs `npm install` — что под капотом:**

```
npm install:
  1. Читает package.json
  2. Строит "идеальное дерево" зависимостей
  3. Сравнивает с тем, что уже в node_modules
  4. Доустанавливает/обновляет что нужно
  5. МОЖЕТ обновить package-lock.json
  Итог: нестабильный (сегодня одни версии, завтра другие)

npm ci:
  1. УДАЛЯЕТ node_modules полностью
  2. Читает package-lock.json (НЕ package.json!)
  3. Ставит ТОЧНО указанные версии
  4. Если lock не совпадает с package.json → ОШИБКА
  Итог: 100% воспроизводимый результат
```

**`cache: 'npm'` — что под капотом:**

GitHub Actions хранит кэш в облачном хранилище (Azure Blob Storage). При каждом запуске:
1. Вычисляется `hash(package-lock.json)` = ключ кэша
2. Если кэш с таким ключом есть → скачивается в `~/.npm/` (НЕ в node_modules!)
3. `npm ci` вместо скачивания c registry берёт пакеты из `~/.npm/`
4. После workflow — обновляет кэш, если ключ изменился

```
Первый запуск: npm ci → скачивает из registry → 30 сек → сохраняет в кэш
Второй запуск: npm ci → берёт из кэша ~/.npm → 3 сек
Lock изменился: npm ci → новый hash → cache miss → скачивает заново
```

---

## БЛОК 2: PULL REQUEST VERIFICATION

---

### «Enforce up-to-date branch with main»

**Ключевой код:**
```json
"required_status_checks": { "strict": true }
```

**Теория:**

**Что под капотом на сервере GitHub:**

Когда `strict: true`, GitHub перед каждым merge проверяет: "SHA коммита, на который указывает `main`, является ли он ПРЕДКОМ HEAD-а ветки PR?"

```
Другими словами: `git merge-base --is-ancestor main feature`

Если ДА → ветка содержит все коммиты из main → ✅ up-to-date
Если НЕТ → main ушёл вперёд → ❌ "This branch is out-of-date with the base branch"
```

**Что видит разработчик:**

На странице PR появляется жёлтая плашка: "This branch is out-of-date with the base branch" и кнопка **"Update branch"**. При нажатии GitHub выполняет `git merge main` в твою ветку (или rebase, если настроено), тесты перезапускаются.

**Реальный production-инцидент (зачем это нужно):**

```
Дано: микросервис с API endpoint GET /users

PR #1 (Алиса): Удаляет endpoint GET /users (deprecated)
PR #2 (Борис): Добавляет кэширование для GET /users

Без strict:
  main: ..── A
              \── PR #1 (тесты ✅, нет зависимости от /users)
              \── PR #2 (тесты ✅, /users ещё существует)
  
  Мержим PR #1 → main: /users удалён
  Мержим PR #2 → main: кэширование для несуществующего /users → 💥 500 в продакшене

С strict:
  Мержим PR #1 → main: /users удалён
  PR #2 помечается "out-of-date" → Борис обновляет ветку → тесты ПАДАЮТ ❌
  → Борис видит проблему ДО мерджа
```

**Альтернативный подход — Merge Queue:**

GitHub с 2023 года предлагает **Merge Queue** — автоматическую очередь. Вместо `strict: true`:
1. PR ставится в очередь
2. GitHub сам создаёт "пробный мердж" с текущим main
3. Тесты запускаются на пробном мердже
4. Если ок — мерджит. Если нет — выкидывает из очереди.

Merge Queue лучше масштабируется (100+ PR/день), но сложнее в настройке. Для нашего проекта `strict: true` проще и достаточно.

---

### «Enforce linear history»

**Ключевой код:**
```json
"required_linear_history": true
```

**Теория — три стратегии слияния подробно:**

**❌ 1. Merge commit (ЗАПРЕЩЁН нами):**
```
main:  A ── B ── C ─── M ── ...
                  \   /
feature:           D─E
```
`M` — merge commit. Имеет ДВУХ родителей (C и E). `git log --graph` показывает "рельсы". В крупных проектах (100+ разработчиков) история превращается в нечитаемый клубок.

Плюсы: сохраняет полную историю ветки (каждый коммит).
Минусы: грязная история, сложный `git bisect`, `git revert` merge commit-а — боль (нужен `-m 1` или `-m 2` и легко ошибиться).

**✅ 2. Squash and merge (РАЗРЕШЁН, рекомендуем):**
```
main:  A ── B ── C ── [DE] ── ...
```
Все коммиты PR сжимаются в ОДИН. Сообщение = заголовок PR.

Плюсы: чистейшая история, один коммит = один PR = одна фича, тривиальный revert.
Минусы: теряется детальная история (10 коммитов стали одним). Но обычно это плюс — "fix typo", "WIP", "oops" коммиты никому не нужны.

**✅ 3. Rebase and merge (РАЗРЕШЁН):**
```
main:  A ── B ── C ── D' ── E' ── ...
```
Коммиты "пересаживаются" на верхушку main. Каждый получает НОВЫЙ SHA (D→D'), потому что у них теперь другой родитель.

Плюсы: линейная история + каждый коммит сохранён.
Минусы: новые SHA → подписанные коммиты (GPG) ломаются, ссылки на старые SHA становятся невалидными.

**Что под капотом:**

Когда `required_linear_history: true`, GitHub API при попытке merge commit вернёт:
```json
{
  "message": "At least 1 approving review is required by reviewers with write access. 
               Required linear history must be preserved."
}
```
Кнопка "Create a merge commit" в UI просто пропадает — остаются только "Squash" и "Rebase".

**`git bisect` — почему линейная история критична для дебага:**

`git bisect` — инструмент бинарного поиска бага. "В коммите A всё работало, в коммите Z — сломано. Найди коммит, который сломал."

```
Линейная:  A ── B ── C ── D ── E ── F (сломано)
           ✅        проверяем C
                     ✅   проверяем E
                          ❌  → виноват D или E
                     Нашли за 3 шага (log₂(6))

С мерджами: A ── B ── M₁ ── C ── M₂ ── F (сломано)
                  \   /         \   /
                   X─Y           Z─W
            Bisect путается на merge commit-ах:
            "Какого родителя проверять? M₁ или X?"
            Нужен --first-parent, но даже он не всегда спасает
```

---

### «Run: Linting»

**Ключевой код:**
```javascript
// eslint.config.js
export default tseslint.config(
    eslint.configs.recommended,
    ...tseslint.configs.recommended,
    { ignores: ['dist/', 'node_modules/', 'coverage/', '*.config.*'] }
);
```
```yaml
      - name: Lint
        run: npm run lint    # = eslint src/
```

**Теория:**

**Что под капотом ESLint:**

1. ESLint парсит `.ts` файлы через `@typescript-eslint/parser` в AST (дерево)
2. Каждое правило — это функция-визитор, которая обходит AST
3. Правило `no-unused-vars` ищет узлы "VariableDeclaration", у которых нет узлов "Reference"
4. Если нарушение найдено — создаётся диагностическое сообщение с файлом, строкой, колонкой
5. После обхода всех правил — если есть ошибки уровня "error" → exit code 1

```
Код:                    AST (дерево):                Правило проверяет:

const x = 5;           VariableDeclaration           no-unused-vars:
                       ├── name: "x"                 "На x есть ссылки?"
                       └── init: NumericLiteral(5)    → НЕТ → ❌ ошибка

sum(2, 3);             CallExpression                eqeqeq:
                       ├── callee: "sum"              (не применимо)
                       └── args: [2, 3]
```

**Почему ESLint, а не альтернативы:**

| Инструмент | Язык | Скорость | Экосистема | Почему не выбрали |
|---|---|---|---|---|
| **ESLint (наш)** | JS | Средняя | Огромная (3000+ правил) | — |
| **Biome** | Rust | В 35x быстрее | Маленькая, новый проект | Мало правил для TS |
| **deno lint** | Rust | Быстрый | Только для Deno | Мы используем Node |
| **TSLint** | JS | Медленный | Deprecated с 2019 | Мёртвый проект |

ESLint — стандарт индустрии с самой большой экосистемой плагинов. `typescript-eslint` добавляет правила, использующие информацию о ТИПАХ (чего Biome пока не умеет).

**Flat config vs Legacy config:**

```
Раньше (.eslintrc.json):           Сейчас (eslint.config.js):
{                                   export default [{
  "extends": [                        rules: { ... }
    "eslint:recommended"            }, {
  ],                                  ignores: ['dist/']
  "ignorePatterns": ["dist/"]       }];
}

  Каскад конфигов в каждой          Один массив объектов.
  папке. Сложно понять, какой       Явно и предсказуемо.
  конфиг победил.                   Обычный JS-модуль.
```

ESLint v9+ рекомендует flat config. `eslintrc` deprecated и будет удалён в v10.

---

### «Run: Build»

**Ключевой код:**
```yaml
      - name: Build
        run: npm run build   # = tsc
```

**Теория:**

**Что именно проверяет компилятор (чего НЕ поймает линтер и тесты):**

```typescript
// 1. Structural typing (утиная типизация)
interface Point { x: number; y: number; }
const p: Point = { x: 1, y: 2, z: 3 };
// tsc: ❌ 'z' does not exist in type 'Point'
// Линтер: ✅ (не видит эту проблему)
// Тесты: ✅ (код выполнится без ошибки в JS!)

// 2. Generic constraints
function first<T>(arr: T[]): T { return arr[0]; }
first("hello");
// tsc: ❌ Argument of type 'string' is not assignable to parameter 'T[]'
// Тесты: ✅ (строка — это ArrayLike, в рантайме вернёт "h")

// 3. Exhaustive checks
type Shape = 'circle' | 'square';
function area(s: Shape) {
    switch(s) {
        case 'circle': return 3.14;
        // Забыли 'square'!
    }
}
// tsc: ❌ Not all code paths return a value (если strict)
```

Компилятор ловит ошибки, которые в рантайме могут НЕ ПРОЯВИТЬСЯ или проявиться только в edge-case. Это "математическая" проверка корректности, а не "эмпирическая" (как тесты).

**Порядок шагов Lint → Build → Test в пайплайне неслучаен:**

```
Lint:   Самый быстрый (секунды). Ловит стилистические ошибки.
        Если код "грязный" — нет смысла компилировать.
          │
Build:  Средний (секунды-минуты). Ловит ошибки типов.
        Если не компилируется — нет смысла запускать тесты.
          │
Test:   Самый медленный. Ловит логические ошибки.
        Запускает ТОЛЬКО если код прошёл lint и build.

Принцип "fail fast": падай на самом раннем, дешёвом этапе.
```

---

### «Run: Unit tests»

**Ключевой код:**
```typescript
import { sum, subtract, multiply } from '../index.js';
describe('sum', () => {
    it('adds two positive numbers', () => { expect(sum(2, 3)).toBe(5); });
    it('adds negative numbers',     () => { expect(sum(-1, -2)).toBe(-3); });
});
```

**Теория:**

**Что под капотом `vitest run`:**

1. Vitest читает `vitest.config.ts` → находит паттерн `include: ['src/__tests__/**/*.test.ts']`
2. Находит файлы, подходящие под паттерн
3. Для каждого файла: использует **Vite** для трансформации TS→JS на лету (без предварительной компиляции!)
4. Запускает каждый `it()` блок изолированно
5. Собирает результаты: `expect(sum(2,3)).toBe(5)` → `5 === 5` → pass ✅
6. Если хоть один `expect` не совпал → `AssertionError` → тест marked as failed
7. После всех тестов: если есть failed → `process.exit(1)` → GitHub Actions видит ненулевой exit code → шаг FAILED

**Почему Vitest, а не Jest:**

| | Vitest | Jest |
|---|---|---|
| ESM (import/export) | Нативно | Нужен `--experimental-vm-modules` |
| TypeScript | Из коробки (через Vite) | Нужен `ts-jest` или `@swc/jest` |
| Скорость | Быстрее (HMR, переиспользование трансформаций) | Медленнее |
| Совместимость с Jest API | Да (`describe`, `it`, `expect`) | — |
| Конфиг | `vitest.config.ts` (тот же формат что Vite) | `jest.config.ts` |
| Watch mode | Instant (через Vite HMR) | Полный перезапуск |

У нас `"type": "module"` в package.json (ES Modules). Jest с ESM — болезненная настройка. Vitest работает нативно.

**Паттерн AAA (Arrange-Act-Assert):**
```typescript
it('adds two positive numbers', () => {
    // Arrange (подготовка) — в нашем случае пусто, функция чистая
    // Act (действие)
    const result = sum(2, 3);
    // Assert (проверка)
    expect(result).toBe(5);
});
```
У нас всё в одну строку, но концептуально каждый тест следует этому паттерну.

---

### «Dependencies must be locked (e.g. package-lock.json)»

**Ключевой код:**
```yaml
      - run: |
          if [ ! -f package-lock.json ]; then
            echo "❌ package-lock.json is missing!"
            exit 1
          fi
```

**Теория:**

**Что под капотом package-lock.json:**

Это JSON-файл (~104 КБ в нашем проекте), содержащий ПОЛНОЕ дерево зависимостей:

```json
{
  "packages": {
    "node_modules/vitest": {
      "version": "3.2.4",                    // ТОЧНАЯ версия
      "resolved": "https://registry.npmjs.org/vitest/-/vitest-3.2.4.tgz",  // URL
      "integrity": "sha512-abc123...",        // ХЭШ для проверки целостности
      "dependencies": {
        "@vitest/runner": "^3.2.4"            // и ЕГО зависимости тоже зафиксированы
      }
    }
  }
}
```

`integrity` — SHA-хэш архива. При `npm ci` npm скачивает пакет и сверяет хэш. Если не совпадает — кто-то подменил пакет на сервере (supply chain attack). npm падает с ошибкой.

**Альтернативные менеджеры пакетов:**

| Менеджер | Lock-файл | Особенности |
|---|---|---|
| **npm (наш)** | `package-lock.json` | Стандартный, встроен в Node.js |
| **yarn** | `yarn.lock` | Был быстрее npm, сейчас разница минимальна |
| **pnpm** | `pnpm-lock.yaml` | Хранит пакеты глобально, symlinks. Экономит диск в 2-3x |
| **bun** | `bun.lock` | Bun runtime, очень быстрый, но молодой |

Все они решают одну проблему: **детерминированные установки** (одинаковый вход → одинаковый выход).

---

### «The PR cannot be merged unless all checks pass»

**Ключевой код:**
```json
"required_status_checks": {
    "contexts": ["Verify Pull Request"]
}
```

**Теория:**

**Что под капотом Status Checks:**

GitHub использует **Commit Status API** и **Checks API** — два механизма:

```
1. Commit Status API (старый):
   POST /repos/owner/repo/statuses/{sha}
   { "state": "success", "context": "Verify Pull Request" }

2. Checks API (новый, GitHub Actions использует его):
   POST /repos/owner/repo/check-runs
   { "name": "Verify Pull Request", "conclusion": "success" }
```

Когда workflow завершается, GitHub Actions Runner отправляет результат через Checks API. Branch Protection проверяет ОБА API — поэтому работает и с внешними CI (Jenkins, CircleCI), и с GitHub Actions.

**Почему имя `name:` в workflow КРИТИЧНО:**

```yaml
# pr-checks.yml
jobs:
  pr-checks:
    name: Verify Pull Request    # ← Branch Protection ищет ТОЧНО ЭТО имя
```

Если ты напишешь `name: PR Checks` в workflow, а в Branch Protection стоит `"contexts": ["Verify Pull Request"]` — GitHub будет ждать чека, который никогда не придёт. PR навсегда заблокирован (пока не исправишь имя или не снимешь protection).

> **Продолжение → `THEORY_PART2_RU.md`**
