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

# Set branch protection using GitHub API with proper JSON body
echo "🛡️  Configuring branch protection rules..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Verify Pull Request"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

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
