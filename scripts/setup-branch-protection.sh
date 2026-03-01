#!/usr/bin/env bash
# setup-branch-protection.sh
# Automates branch protection rules for the main branch using GitHub CLI.
# Usage: ./scripts/setup-branch-protection.sh <owner/repo>

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo>}"

echo "🔒 Setting up branch protection for ${REPO}..."

# Create required labels
echo "🏷️  Creating labels..."
gh label create "verify" --description "Triggers E2E/integration tests" --color "0E8A16" --repo "${REPO}" 2>/dev/null || echo "  Label 'verify' already exists"
gh label create "publish" --description "Triggers release candidate build and release on merge" --color "D93F0B" --repo "${REPO}" 2>/dev/null || echo "  Label 'publish' already exists"

# Set branch protection using GitHub API
echo "🛡️  Configuring branch protection rules..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/branches/main/protection" \
  -f required_status_checks='{"strict":true,"contexts":["Verify Pull Request"]}' \
  -F enforce_admins=false \
  -f required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  -f restrictions=null \
  -F required_linear_history=true \
  -F allow_force_pushes=false \
  -F allow_deletions=false

echo ""
echo "✅ Branch protection configured successfully!"
echo ""
echo "Rules applied:"
echo "  ✓ Require PR reviews (1 approval, dismiss stale)"
echo "  ✓ Require status checks to pass (PR Checks workflow)"
echo "  ✓ Require branch to be up-to-date with main"
echo "  ✓ Enforce linear history (squash/rebase only)"
echo "  ✓ Block force pushes"
echo "  ✓ Block branch deletion"
echo "  ✓ Labels created: 'verify', 'publish'"
