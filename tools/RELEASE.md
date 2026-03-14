# Release Guide

This document describes how to cut a new release of **proxy-ssl-trust**.

## Prerequisites

- You have push access to the repository and GitHub Actions is enabled.
- Your local `main` is up to date:
  
  ```zsh
  git checkout main
  git pull origin main
  ```
- Your working tree is clean (`git status` shows no changes).
- Commits since the last release preferably follow Conventional Commits (e.g. `feat:`, `fix:`, `chore:`).

## Steps to Create a Release

1. **Confirm clean working tree**
   
   ```zsh
   git status
   ```

2. **Choose the version bump type**
   
   - `patch`: bug fixes and small internal changes.
   - `minor`: new features, no breaking changes.
   - `major`: breaking changes.

3. **Run the release script**
   
   ```zsh
   ./tools/release.sh patch
   ```
   
   Replace `patch` with `minor` or `major` as needed.

   This will:
   - Read the current version from `VERSION` (semantic `MAJOR.MINOR.PATCH`).
   - Compute the next version and update `VERSION`.
   - Update the version strings in `README.md` and `proxy_ssl_trust.sh`.
   - Regenerate `CHANGELOG.md` with a new `## [X.Y.Z] - YYYY-MM-DD` section based on git history.
   - Commit the changes as `chore(release): vX.Y.Z` and create an annotated tag `vX.Y.Z`.

4. **Review the release commit**
   
   ```zsh
   git log -3 --oneline
   cat VERSION
   head -n 40 CHANGELOG.md
   ```

5. **Push commits and tags**
   
   ```zsh
   git push origin main --follow-tags
   ```

   This push triggers the `Release` workflow in `.github/workflows/release.yml`, which reads `CHANGELOG.md` and creates a GitHub Release for the new tag.

6. **Verify on GitHub**
   
   - Check the **Actions** tab for a successful `Release` workflow run.
   - Check the **Releases** tab for the new release, with notes populated from `CHANGELOG.md`.

## Notes

- The `VERSION` file is the single source of truth for the current semantic version.
- If the workflow cannot create a GitHub Release (e.g. due to token permissions), you can still create one manually in the GitHub UI using the section from `CHANGELOG.md` as the body.
