# Полный разбор задания CI/CD Challenge — Часть 3
# Глубокое погружение: Runner, Secrets, Permissions, Concurrency, и общая архитектура

> Эта часть — бонус. Здесь всё, что НЕ является прямым требованием задания, но критично для понимания того, КАК и ПОЧЕМУ всё работает.

---

## БЛОК 7: GITHUB ACTIONS RUNNER — ЧТО ЭТО ЗА МАШИНА

---

### Что стоит за `runs-on: ubuntu-latest`

**Ключевой код (присутствует в каждом workflow):**
```yaml
runs-on: ubuntu-latest
```

**Что под капотом:**

Когда GitHub Actions получает событие (PR, лейбл, merge), он должен ГДЕ-ТО выполнить workflow. Это "где-то" — **Runner** — виртуальная машина (VM), которая создаётся с нуля для каждого запуска.

```
Событие (PR создан)
       │
       ▼
GitHub Actions Orchestrator:
  "Нужна VM с ubuntu-latest"
       │
       ▼
Azure Cloud (GitHub принадлежит Microsoft):
  Поднимает VM:
  ├── 2 CPU (x86_64)
  ├── 7 ГБ RAM
  ├── 14 ГБ SSD
  ├── Ubuntu 22.04 LTS
  ├── Предустановлено: git, node, python, docker, gh CLI, curl, jq...
  └── Имя: github-runner-<random>
       │
       ▼
Runner Agent (программа на C#/.NET):
  1. Получает задание от Orchestrator
  2. git clone репозитория
  3. Выполняет шаги workflow последовательно
  4. Отправляет логи в реалтайме на GitHub
  5. Отправляет финальный статус (success/failure)
       │
       ▼
VM УНИЧТОЖАЕТСЯ. Диск стирается. Следов нет.
```

**Почему VM уничтожается:**
- **Безопасность:** Один workflow не может подсмотреть секреты другого
- **Чистота:** Каждый запуск начинается с идентичного состояния
- **Изоляция:** Сломанный workflow не может повлиять на следующий

**Доступные Runner-ы:**

| Label | ОС | CPU | RAM | Когда использовать |
|---|---|---|---|---|
| `ubuntu-latest` | Ubuntu 22.04 | 2 | 7 ГБ | 95% случаев, самый дешёвый |
| `ubuntu-24.04` | Ubuntu 24.04 | 2 | 7 ГБ | Нужны свежие пакеты |
| `windows-latest` | Windows Server 2022 | 2 | 7 ГБ | .NET, PowerShell |
| `macos-latest` | macOS 14 (ARM) | 3 | 7 ГБ | iOS/macOS сборки |
| `self-hosted` | Твоё железо | Любой | Любой | Корпоративные ограничения |

macOS Runner стоит 10x дороже Ubuntu в минутах. Поэтому для Node.js проектов ВСЕГДА `ubuntu-latest`.

**Сколько стоит:**

```
GitHub Free (для публичных репо):
  ├── GitHub-hosted runners: БЕСПЛАТНО и БЕЗЛИМИТНО
  └── Артефакты: 500 МБ

GitHub Free (для приватных репо):
  ├── 2,000 минут/месяц (Ubuntu)
  ├── 1 минута Ubuntu = 1 минута
  ├── 1 минута Windows = 2 минуты
  └── 1 минута macOS = 10 минут

Наш workflow (pr-checks) занимает ~45 секунд.
2000 / 0.75 ≈ 2666 запусков в месяц бесплатно.
```

---

## БЛОК 8: SECRETS И БЕЗОПАСНОСТЬ

---

### Как работают `secrets.NPM_TOKEN` и `secrets.GITHUB_TOKEN`

**Ключевой код:**
```yaml
env:
  NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

**Что под капотом при обработке `${{ secrets.XXX }}`:**

```
1. Workflow YAML парсится на сервере GitHub (НЕ на Runner-е)
2. GitHub находит ${{ secrets.NPM_TOKEN }}
3. Идёт в зашифрованное хранилище (Vault)
4. Расшифровывает значение с помощью ключа, привязанного к репозиторию
5. Подставляет значение в env переменную
6. Отправляет на Runner — но с правилом:
   "Если это значение появится в stdout/stderr — замени на ***"

Поэтому в логах:
  echo $NODE_AUTH_TOKEN
  → ***

  echo "Publishing with token npm_a1b2c3d4e5f6"
  → Publishing with token ***
```

GitHub сканирует ВСЕ выводимые строки и маскирует совпадения с секретами. Но есть нюансы:

```
Обход маскировки (НЕ ДЕЛАЙ ТАК):
  echo $NODE_AUTH_TOKEN | base64
  → bnBtX2ExYjJjM2Q0ZTVmNg==     ← НЕ замаскировано! Base64 ≠ оригинал

  echo $NODE_AUTH_TOKEN | rev
  → 6f5e4d3c2b1a_mpn               ← НЕ замаскировано!
```

Именно поэтому GitHub рекомендует НИКОГДА не echo-ить секреты даже в "безопасном" виде.

**Иерархия секретов:**

```
Organization secrets     → доступны ВСЕМ репо в организации
       │
Repository secrets       → доступны только этому репо (${{ secrets.NPM_TOKEN }})
       │
Environment secrets      → доступны только при деплое в конкретный environment
       │
       └── Environment protection rules:
           ├── Required reviewers (кто-то должен одобрить деплой)
           ├── Wait timer (задержка перед деплоем)
           └── Branch restrictions (только из main)
```

Для нашего проекта: `NPM_TOKEN` — repository secret. Для enterprise: обычно organization secret + environment protection.

**Создание NPM_TOKEN:**

```
1. npmjs.com → Profile → Access Tokens → Generate New Token
2. Тип: "Automation" (не "Publish" — Automation не требует 2FA)
3. Копируешь токен: npm_a1b2c3...
4. GitHub → Repository → Settings → Secrets → Actions → New secret
5. Name: NPM_TOKEN, Value: npm_a1b2c3...
```

---

## БЛОК 9: PERMISSIONS — ПРИНЦИП LEAST PRIVILEGE

---

### Зачем в каждом workflow блок `permissions`

**Ключевой код:**
```yaml
# pr-checks.yml, label-verify.yml, label-publish.yml:
permissions:
  contents: read

# release.yml:
permissions:
  contents: write
  packages: write
```

**Теория:**

**Principle of Least Privilege** — даём МИНИМАЛЬНО необходимые права.

```
Без блока permissions:
  Workflow получает ВСЕ права GITHUB_TOKEN по умолчанию:
  contents: write, issues: write, pull-requests: write, packages: write ...
  
  Риск: компрометированная зависимость выполняет:
    git push origin main --force     ← МОЖЕТ (contents: write)
    gh issue close --all             ← МОЖЕТ (issues: write)

С permissions: { contents: read }:
  git push → 403 Forbidden           ← НЕ МОЖЕТ
  gh issue close → 403 Forbidden     ← НЕ МОЖЕТ
  git clone → OK                     ← МОЖЕТ (read)
```

**Почему `release.yml` имеет `contents: write`:**

```
release.yml:
  git tag -a "v1.0.0" → создание тега → нужен contents: write
  git push origin tag → push тега     → нужен contents: write
  gh release create   → создание релиза → нужен contents: write

  Без write → 403 при push tag → workflow упадёт
```

А `pr-checks.yml` только ЧИТАЕТ код (checkout, lint, build, test) — ему `contents: read` достаточно.

**`GITHUB_TOKEN` permissions vs Repository Settings:**

Есть два уровня ограничений:
```
Repository Settings → Actions → General → Workflow permissions:
  ○ Read and write        ← максимальные права по умолчанию
  ● Read repository contents and packages only   ← минимальные

Workflow YAML → permissions:
  contents: write          ← может РАСШИРИТЬ до максимума из Settings
                             (но не может выйти за пределы)
```

Если в Settings стоит "Read only", а в YAML написано `contents: write` — `write` будет разрешён, потому что YAML переопределяет. Но если Organization policy запрещает — то нет.

---

## БЛОК 10: ПОРЯДОК ВЫПОЛНЕНИЯ И CONCURRENCY

---

### В каком порядке выполняются workflow-ы

**Теория:**

Все workflow-ы **независимы друг от друга**. Если ты создал PR — `pr-checks.yml` запустится. Если потом повесил лейбл — `label-verify.yml` запустится ПАРАЛЛЕЛЬНО, не дожидаясь завершения `pr-checks.yml`.

```
Событие           Workflow                  Связь
────────           ────────                  ─────
PR создан    ──→   pr-checks.yml            Независимый
Лейбл verify ──→   label-verify.yml         Независимый (но зачем verify, если checks ещё идут?)
Лейбл publish──→   label-publish.yml        Независимый
PR merged    ──→   release.yml              Независимый

Между ними НЕТ зависимостей на уровне Actions.
Зависимость обеспечивается Branch Protection:
  "Merge заблокирован, пока pr-checks не зелёный"
```

**Jobs внутри одного workflow:**

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: ...
  test:
    needs: [lint]              # ← ЗАВИСИМОСТЬ: test ждёт lint
    runs-on: ubuntu-latest
    steps: ...
```

`needs:` создаёт зависимость МЕЖДУ job-ами. Без `needs:` — все jobs запускаются параллельно.

У нас jobs внутри каждого workflow — один (нет параллелизма). Между workflows — только Branch Protection.

**Concurrency — защита от гонок:**

```yaml
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false
```

Мы НЕ используем concurrency (для простоты), но вот зачем он нужен:

```
Ситуация без concurrency:
  PR #1 merged → release.yml запущен → npm publish 1.1.0...
  PR #2 merged через 5 секунд → release.yml запущен → npm publish 1.2.0...
  
  Оба бегут ПАРАЛЛЕЛЬНО:
    release #1: git tag v1.1.0 → git push → npm publish 1.1.0
    release #2: git tag v1.2.0 → git push → npm publish 1.2.0
    
  Возможный результат: теги перепутались, npm publish порядок неопределён
  
С concurrency { group: release, cancel-in-progress: false }:
  release #1 запускается
  release #2 ЖДЁТ завершения #1
  → гарантированный последовательный порядок
```

---

## БЛОК 11: ПОЛНАЯ СХЕМА СОБЫТИЙ ОТ НАЧАЛА ДО КОНЦА

---

```
ТВОЙ КОМПЬЮТЕР                     GITHUB                              NPM
══════════════                     ══════                              ═══

1. git checkout -b feature/divide
2. Редактируешь src/index.ts
   (добавляешь divide())
3. Редактируешь package.json
   ("version": "1.0.0" → "1.1.0")
4. git add . && git commit -m "feat: add divide"
5. git push origin feature/divide
                │
                │  push в feature-ветку
                │  (НЕ в main)
                ▼
         Ветка появилась на GitHub
         Workflows НЕ запускаются
         (нет триггера pull_request)
                │
6. На GitHub:   │
   "Create PR"  │
                ▼
         ⚡ Событие: pull_request (opened)
         ┌──────────────────────────┐
         │     pr-checks.yml        │
         │  ┌─────────────────────┐ │
         │  │ 1. Checkout code    │ │
         │  │ 2. Setup Node+deps  │ │    ← uses: cicd-shared-actions/setup-node-deps
         │  │ 3. Check lockfile   │ │
         │  │ 4. Lint (eslint)    │ │
         │  │ 5. Build (tsc)     │ │
         │  │ 6. Unit tests      │ │
         │  └─────────────────────┘ │
         │  Status: ✅ or ❌        │
         └──────────────────────────┘

         Branch Protection проверяет:
         "Verify Pull Request" = ✅?
         strict (up-to-date)?
         1 approving review?
                │
7. Label:       │
   "verify"     │
                ▼
         ⚡ Событие: pull_request (labeled, name=verify)
         ┌──────────────────────────┐
         │    label-verify.yml      │
         │  ┌─────────────────────┐ │
         │  │ 1. Checkout         │ │
         │  │ 2. Setup Node+deps  │ │
         │  │ 3. Build            │ │
         │  │ 4. E2E tests       │ │    ← import('../../dist/index.js')
         │  └─────────────────────┘ │
         │  Status: ✅ or ❌        │
         └──────────────────────────┘
                │
8. Label:       │
   "publish"    │
                ▼
         ⚡ Событие: pull_request (labeled, name=publish)
         ┌──────────────────────────────┐
         │     label-publish.yml        │
         │  ┌────────────────────────┐  │
         │  │ 1. Checkout            │  │
         │  │ 2. Setup Node+deps     │  │
         │  │ 3. Extract version     │  │  → "1.1.0"
         │  │ 4. Check npm exists    │  │  → uses: check-version-exists
         │  │ 5. Block if exists     │  │  → exit 1 if true
         │  │ 6. Dev version suffix  │  │  → "1.1.0-dev-a3b8c2f"
         │  │ 7. Build              │  │
         │  │ 8. npm pack → .tgz    │  │
         │  │ 9. Upload artifact    │  │  → downloadable .tgz
         │  └────────────────────────┘  │
         │  Status: ✅ or ❌            │
         └──────────────────────────────┘
                │
9. Reviewer:    │
   "Approve" ✅ │
                │
10. Author:     │
    "Squash     │
     and merge" │
                ▼
         Код влит в main.
         PR закрыт со статусом "merged".

         ⚡ Событие: pull_request (closed, merged=true, label=publish)
         ┌──────────────────────────────┐
         │        release.yml           │
         │  ┌────────────────────────┐  │
         │  │ 1. Checkout (depth=0)  │  │
         │  │ 2. Setup Node+deps     │  │
         │  │ 3. Extract version     │  │  → "1.1.0"
         │  │ 4. Build              │  │
         │  │ 5. npm publish         │──│──────────────────→ Пакет v1.1.0
         │  │ 6. git tag v1.1.0     │  │                     в npm registry ✅
         │  │ 7. git push tag       │  │
         │  │ 8. gh release create   │  │
         │  └────────────────────────┘  │
         │  Status: ✅                  │
         └──────────────────────────────┘

         Результат:
         ├── npm: @emilmamedov-inno/ts-math-utils@1.1.0 ✅
         ├── Git tag: v1.1.0 ✅
         └── GitHub Release: Release v1.1.0 с changelog ✅
```

---

## БЛОК 12: ЧАСТЫЕ ВОПРОСЫ И EDGE CASES

---

### Что будет, если...

**1. Два PR мержатся одновременно с лейблом `publish`?**

Оба запустят `release.yml`. Первый опубликует версию в npm. Второй:
- Если версия ОДИНАКОВАЯ → `npm publish` вернёт 403 → workflow упадёт
- Если версии РАЗНЫЕ → оба опубликуются (но теги могут конфликтовать при одновременном push)

Решение: `concurrency: { group: release }` (мы обсудили выше).

**2. Что если разработчик НЕ повесит лейбл `publish`?**

PR можно смержить (если pr-checks зелёные и есть аппрув). `release.yml` НЕ запустится (условие `contains(..., 'publish')` = false). Код попадёт в main, но пакет НЕ опубликуется и тег НЕ создастся. Это нормально — не каждый PR = релиз.

**3. Что если `NPM_TOKEN` протух/невалидный?**

`npm publish` вернёт `401 Unauthorized`. Workflow упадёт на последнем шаге. Код УЖЕ в main. Нужно:
1. Обновить токен в GitHub Secrets
2. Перезапустить workflow вручную (Actions → Re-run)
Или: создать trivial PR для повторного мерджа.

**4. Что если тесты зелёные на PR, но после merge в main что-то сломалось?**

Это возможно даже с `strict: true`, если:
- Два PR прошли проверку одновременно и мержатся подряд
- Внешняя зависимость изменилась (API, npm пакет без lock)
- Flaky-тест (нестабильный тест, проходит 99% запусков)

Решение: **Merge Queue** (GitHub автоматически проверяет "комбинации" PR перед мерджем).

**5. Зачем `npm run build` есть и в pr-checks, и в release?**

В `pr-checks` build нужен для ПРОВЕРКИ ("компилируется ли?"). В `release` build нужен для СБОРКИ перед публикацией. Runner между workflows не shared — это РАЗНЫЕ VM. Артефакты build из pr-checks не переносятся в release.

---

## БЛОК 13: ГЛОССАРИЙ

---

| Термин | Определение |
|---|---|
| **CI (Continuous Integration)** | Автоматическая проверка кода при каждом изменении |
| **CD (Continuous Deployment)** | Автоматическая публикация после merge |
| **Runner** | Виртуальная машина, на которой выполняется workflow |
| **Workflow** | YAML-файл с описанием автоматизации |
| **Job** | Набор шагов внутри workflow, выполняется на одной VM |
| **Step** | Одна команда или action внутри job |
| **Action** | Переиспользуемый блок (наш `setup-node-deps`) |
| **Trigger/Event** | Событие, запускающее workflow (`push`, `pull_request`, `labeled`) |
| **Artifact** | Файл, сохранённый workflow для скачивания |
| **Status Check** | Отчёт о результате workflow, привязанный к коммиту |
| **Branch Protection** | Правила, блокирующие merge при невыполнении условий |
| **Squash** | Сжатие всех коммитов PR в один при merge |
| **Tag** | Неподвижная метка на конкретном коммите |
| **Release** | GitHub-страница с описанием релиза, привязанная к тегу |
| **SemVer** | Формат версий MAJOR.MINOR.PATCH |
| **Prerelease** | Версия с суффиксом (1.0.0-dev-abc), меньше финальной |
| **Lock-файл** | Фиксация точных версий зависимостей (package-lock.json) |
| **Scoped package** | npm-пакет с @scope/ префиксом (@org/name) |
| **Composite action** | Action, состоящий из набора shell/uses шагов |
| **Fail fast** | Принцип: падай на самом раннем, дешёвом этапе |
| **Shift left** | Принцип: перемещай проверки как можно раньше в pipeline |
| **Least privilege** | Принцип: давай минимально необходимые права |
