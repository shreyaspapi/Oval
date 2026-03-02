#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 1.1.0
#
# This script:
# 1. Validates the version argument
# 2. Checks that CHANGELOG.md has an entry for the version
# 3. Creates a git tag
# 4. Pushes the tag to trigger the GitHub Actions release workflow

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.1.0"
  exit 1
fi

# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Version must be in semver format (e.g., 1.2.3)"
  exit 1
fi

# Check we're on main branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "Error: You must be on the 'main' branch to release (currently on '$BRANCH')"
  exit 1
fi

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: You have uncommitted changes. Commit or stash them first."
  exit 1
fi

# Check CHANGELOG has an entry for this version
if ! grep -q "## \[$VERSION\]" CHANGELOG.md; then
  echo "Error: No entry found for version $VERSION in CHANGELOG.md"
  echo ""
  echo "Add a section like this to CHANGELOG.md before releasing:"
  echo ""
  echo "  ## [$VERSION] - $(date +%Y-%m-%d)"
  echo "  "
  echo "  ### Added"
  echo "  - Your new feature"
  echo ""
  exit 1
fi

# Check if tag already exists
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "Error: Tag v$VERSION already exists"
  exit 1
fi

echo "Releasing Oval v$VERSION..."
echo ""

# Pull latest
git pull origin main

# Create and push tag
git tag -a "v$VERSION" -m "Release v$VERSION"
git push origin "v$VERSION"

echo ""
echo "Tag v$VERSION pushed. GitHub Actions will now:"
echo "  1. Build the app"
echo "  2. Create the DMG"
echo "  3. Create the GitHub release with notes from CHANGELOG.md"
echo ""
echo "Watch progress at: https://github.com/shreyaspapi/Oval/actions"
