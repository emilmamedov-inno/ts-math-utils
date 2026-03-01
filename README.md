# ts-math-utils

A simple TypeScript package for math utilities (`sum`, `subtract`, `multiply`), demonstrating a fully automated CI/CD pipeline using GitHub Actions.

## CI/CD Pipeline & Release Process

This repository implements a fully automated CI/CD workflow with strict branch protection rules, ensuring that all code in the `main` branch is tested, verified, and correctly versioned. The reusable actions powering this pipeline are available at [emilmamedov-inno/cicd-shared-actions](https://github.com/emilmamedov-inno/cicd-shared-actions).

### 1. Pull Request Verification
Every Pull Request targeting `main` must pass the **PR Checks** workflow:
- The branch must be up-to-date with `main`.
- Linear history is enforced (squashes/rebases only, no merge commits).
- **Checks executed:**
  - `package-lock.json` validation (dependencies must be locked).
  - ESLint checks.
  - TypeScript Build compilation.
  - Unit tests via Vitest.
- The PR cannot be merged unless all of these checks succeed and at least 1 approval review is provided.

### 2. Label-Driven Workflows
The pipeline uses PR labels to trigger specific environments and automation:

#### 🏷️ `verify` Label
Adding the `verify` label to a Pull Request triggers the **Integration / E2E Tests** workflow.
- It builds the package and imports it from `dist/` to verify real-world usage scenarios.
- Used to ensure that the compiled output is completely functional before even considering a release.

#### 🏷️ `publish` Label
Adding the `publish` label to a Pull Request turns the PR into a **Release Candidate**.
- Extracts the version defined in `package.json`.
- Checks if the specific version already exists on the npm registry. **If the version already exists, the pipeline fails and blocks the merge.**
- Builds the package with a development suffix (e.g., `1.0.0-dev-<short-sha>`).
- Produces a publishable `.tgz` artifact that can be downloaded from the Action's summary for manual inspection.

### 3. Release on Merge
When a Pull Request that has the `publish` label is successfully merged into `main`:
- The **Release** workflow is triggered.
- It builds the package and automatically publishes the exact version strictly as defined in `package.json` to npm.
- It automatically creates a Git Tag `vX.Y.Z` on the repository.
- Generates a GitHub Release with an auto-generated changelog connecting the PRs and commits.

## Development

```bash
# Install dependencies
npm install

# Run linting
npm run lint

# Run unit tests
npm test

# Run E2E tests
npm run test:e2e

# Build package
npm run build
```
