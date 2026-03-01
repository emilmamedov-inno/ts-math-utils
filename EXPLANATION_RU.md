# Пошаговое объяснение CI/CD Pipeline

Этот файл создан в учебных целях и содержит детальное объяснение выполненных действий по настройка CI/CD конвейера в соответствии с требованиями задания.

---

### Пункт-задание: Create a simple TypeScript package (e.g. a sum(a, b) function).
**Объяснение:**
Я инициализировал Node.js проект с поддержкой TypeScript, настроил `tsconfig.json` и создал исходный файл `src/index.ts`, куда поместил математические функции, включая запрошенную `sum(a, b)`. Также был написан набор unit-тестов с помощью тестового фреймворка `vitest`, чтобы убедиться в работоспособности функции. Скрипт сборки (`npm run build`) компилирует TypeScript в обычный JavaScript и генерирует типы (`.d.ts`) в директорию `dist/`.

### Пункт-задание: Identify and externalize reusable actions or workflows (i.e. put them in a reusable repo).
**Объяснение:**
Я вынес повторяющуюся логику GitHub Actions в отдельный репозиторий [cicd-shared-actions](https://github.com/emilmamedov-inno/cicd-shared-actions). Были созданы так называемые **composite actions** (составные экшены):
1. `setup-node-deps` - устанавливает нужную версию Node.js, настраивает кеширование npm и выполняет чистую установку зависимостей (`npm ci`) из `package-lock.json`. Этот шаг повторяется почти во всех воркфлоу, поэтому его вынос — это классический best practice.
2. `check-version-exists` - проверяет с помощью npm API, существует ли уже такая версия пакета в публичном реестре.
3. `create-release` - автоматизирует создание git-тега и GitHub Release через утилиту `gh` CLI.

Затем в главном репозитории в `.github/workflows/*.yml` эти экшены вызываются через синтаксис `uses: emilmamedov-inno/cicd-shared-actions/setup-node-deps@main`.

### Пункт-задание: The package must be publishable to npm (a scoped package or test registry is acceptable).
**Объяснение:**
В `package.json` было прописано scoped имя пакета (`@emilmamedov-inno/ts-math-utils`). Это гарантирует отсутствие конфликтов имен в публичном npm регистре. Были подготовлены файлы `.npmignore` и `.gitignore`, чтобы в NPM пакет уходила исключительно директория со собранным кодом (`dist/`) и типы, а исходники TypeScript и тестовые файлы оставались локально. В самом воркфлоу релиза добавлен шаг с `npm publish`, который использует токен авторизации.

### Пункт-задание: Pull Request Verification, on every pull request (Enforce up-to-date branch, Enforce linear history, Run linting, build, unit tests, lock check).
**Объяснение:**
Был создан воркфлоу `.github/workflows/pr-checks.yml`, который срабатывает на событие `on: pull_request`.
В нем есть шаги (steps), которые:
- Проверяют наличие файла `package-lock.json` с помощью bash скрипта: `if [ ! -f package-lock.json ]; then exit 1; fi`.
- Запускает `npm run lint` (ESLint), `npm run build` (tsc компилятор) и `npm test` (Unit тесты Vitest).
А для требований "Enforce up-to-date branch" и "linear history", я использовал API GitHub (через утилиту `gh`) для настройки **Branch Protection Rules** для ветки `main`. Теперь пулл реквест физически не может быть смержен (заблокирована кнопка Merge), если ветка устарела, если не пройдены тесты (status checks), или если коммиты не выстроены в прямую линию (linear history).

### Пункт-задание: Label-Driven Workflow (verify label -> Triggers integration/E2E tests).
**Объяснение:**
Создан файл `.github/workflows/label-verify.yml`. У него стоит триггер `on: pull_request: types: [labeled]`. Внутри джобы (job) прописано условие `if: github.event.label.name == 'verify'`. Таким образом, этот workflow запускается ТОЛЬКО когда на PR вешают лейбл `verify`. Он запускает специально настроенный E2E тест, который вначале билдит приложение, а затем пытается импортировать его прямо из скомпилированной папки `/dist`, эмулируя то, как конечный пользователь будет использовать NPM пакет.

### Пункт-задание: Label-Driven Workflow (publish label -> Generates RC, Blocks if version exists, Produces artifacts).
**Объяснение:**
Создан файл `.github/workflows/label-publish.yml` с условием `if: github.event.label.name == 'publish'`.
- Он берет текущую версию из `package.json`.
- Использует наш reusable action `check-version-exists`, который делает запрос к npm `npm view <pkg>@<version>`. Если получает успешный ответ, workflow завершается с ошибкой (`exit 1`), тем самым блокируя merge.
- С помощью `git rev-parse` берется короткий хэш текущего коммита.
- С помощью команды `npm version X.Y.Z-dev-HASH` и `npm pack` генерируется Release Candidate таббол-архив (`.tgz`).
- Этот артефакт загружается на GitHub Actions (`actions/upload-artifact`), после чего его можно скачать прямо со страницы PR, как publishable artifact.

### Пункт-задание: Release on Merge (Automatically publish, git tag, GitHib Release).
**Объяснение:**
Воркфлоу `.github/workflows/release.yml` срабатывает на `pull_request: types: [closed]`. В условии выполняется строгая проверка `if: github.event.pull_request.merged == true && contains(github.event.pull_request.labels.*.name, 'publish')`. То есть: PR должен быть именно смёржен, а не просто закрыт, и на нем до момента мерджа ДОЛЖЕН был висеть лейбл `publish`.
Только при этих условиях воркфлоу делает `npm publish`, после чего вызывает наш reusable action `create-release`, который пробивает git-тег формата `vX.Y.Z` и с помощью команд GitHub CLI публикует красивую страницу релиза на GitHub.

### Пункт-задание: Versioning (Use semantic versioning, version explicitly bumped in PR, dev pre-views).
**Объяснение:**
Процесс обязывает разработчика вручную поднимать версию (Bump version) прямо в `package.json` внутри своего Pull Request. За это отвечает шаг из проверки `publish` лейбла: если версия в PR уже существует в NPM, Pipeline становится красным и мердж запрещается. Пока разработчик не поднимет версию по SemVer (например, на `1.0.1`), Pipeline его не пропустит. Pre-merge билды с суффиксом `X.Y.Z-dev-<short-sha>` генерируются автоматически в рамках шага создания Release Candidate Artifact (через команду `npm version`).

### Пункт-задание: Constraints (automate branch protection setup, no manual steps allowed after PR approval).
**Объяснение:**
Был написан bash скрипт `scripts/setup-branch-protection.sh`. Он использует `gh api`, отправляя настроенный JSON payload на endpoint настройки Branch Protection для репозитория. Он принудительно включает requirement на "Strict Status Checks", "Linear History" и "1 Approving Review", а также создает лейблы "verify" и "publish" на уровне репозитория. Из-за архитектуры, созданной с помощью Label-Driven Action-ов, после аппрува (Approval) пулл реквеста разработчику остается только нажать "Merge" — всё остальное (публикация, тег, релиз) произойдет на 100% автоматически в облаке. 
