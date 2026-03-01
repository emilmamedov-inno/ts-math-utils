#!/usr/bin/env bash
# setup-repos.sh
# Creates GitHub repositories and pushes code.
# Usage: ./scripts/setup-repos.sh

set -euo pipefail

GITHUB_USER="emilmamedov-inno"
MAIN_REPO="ts-math-utils"
ACTIONS_REPO="cicd-shared-actions"

echo "========================================="
echo "  CI/CD Repository Setup Script"
echo "========================================="
echo ""

# --- Step 1: Create and push reusable actions repo ---
echo "📁 Step 1: Setting up reusable actions repo (${ACTIONS_REPO})..."
cd /home/emil/cicd-shared-actions

if ! gh repo view "${GITHUB_USER}/${ACTIONS_REPO}" &>/dev/null; then
  git init
  git add -A
  git commit -m "Initial commit: reusable GitHub Actions"
  gh repo create "${ACTIONS_REPO}" --public --source=. --remote=origin --push
  echo "✅ Created and pushed ${ACTIONS_REPO}"
else
  echo "⚠️  Repo ${ACTIONS_REPO} already exists, pushing updates..."
  git init 2>/dev/null || true
  git remote add origin "https://github.com/${GITHUB_USER}/${ACTIONS_REPO}.git" 2>/dev/null || true
  git add -A
  git commit -m "Update reusable actions" --allow-empty
  git push -u origin main 2>/dev/null || git push -u origin master
fi

echo ""

# --- Step 2: Create and push main package repo ---
echo "📁 Step 2: Setting up main package repo (${MAIN_REPO})..."
cd /home/emil/cicd

# Remove old remote if it exists
git remote remove origin 2>/dev/null || true

if ! gh repo view "${GITHUB_USER}/${MAIN_REPO}" &>/dev/null; then
  git add -A
  git commit -m "Initial commit: TypeScript math utils with CI/CD" --allow-empty
  gh repo create "${MAIN_REPO}" --public --source=. --remote=origin --push
  echo "✅ Created and pushed ${MAIN_REPO}"
else
  echo "⚠️  Repo ${MAIN_REPO} already exists, pushing updates..."
  git remote add origin "https://github.com/${GITHUB_USER}/${MAIN_REPO}.git"
  git add -A
  git commit -m "Update CI/CD pipeline" --allow-empty
  git push -u origin main 2>/dev/null || git push -u origin master
fi

echo ""

# --- Step 3: Setup branch protection ---
echo "🔒 Step 3: Setting up branch protection..."
bash /home/emil/cicd/scripts/setup-branch-protection.sh "${GITHUB_USER}/${MAIN_REPO}"

echo ""
echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "Repositories:"
echo "  Main:    https://github.com/${GITHUB_USER}/${MAIN_REPO}"
echo "  Actions: https://github.com/${GITHUB_USER}/${ACTIONS_REPO}"
echo ""
echo "Next steps:"
echo "  1. Add NPM_TOKEN secret to ${MAIN_REPO} for publishing"
echo "  2. Create a feature branch, make changes, and open a PR"
echo "  3. Use 'verify' label for E2E tests"
echo "  4. Use 'publish' label for release candidate"
echo "  5. Merge to trigger automatic release"
