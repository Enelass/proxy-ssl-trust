#!/bin/zsh
set -euo pipefail

bump_type="patch"
no_push=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    major|minor|patch)
      bump_type="$1" ;;
    --no-push)
      no_push=true ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [major|minor|patch] [--no-push]" >&2
      exit 1 ;;
  esac
  shift
done

if ! git diff --quiet --ignore-submodules HEAD || [[ -n $(git status --porcelain) ]]; then
  echo "Working tree is dirty. Commit or stash changes before releasing." >&2
  exit 1
fi

if [[ ! -f VERSION ]]; then
  echo "VERSION file not found" >&2
  exit 1
fi

current_version=$(< VERSION)
if [[ ! "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version in VERSION: $current_version" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current_version"

case "$bump_type" in
  major)
    major=$((major + 1))
    minor=0
    patch=0 ;;
  minor)
    minor=$((minor + 1))
    patch=0 ;;
  patch)
    patch=$((patch + 1)) ;;
esac

new_version="$major.$minor.$patch"
short_version="$major.$minor"

echo "$new_version" > VERSION

# Update README current version (short form)
perl -pi -e "s/(\\*\\*Current Version\\*\\*: )[0-9]+\\.[0-9]+/\$1$short_version/" README.md

# Update script header VERSION line (short form)
perl -pi -e "s/(#  VERSION: )[0-9]+\\.[0-9]+/\$1$short_version/" proxy_ssl_trust.sh

# Update local version variable (short form)
perl -pi -e "s/(local version=\")[0-9]+\\.[0-9]+(\")/\$1$short_version\$2/" proxy_ssl_trust.sh

./tools/generate-changelog.sh "$new_version"

git add VERSION README.md CHANGELOG.md proxy_ssl_trust.sh

git commit -m "chore(release): v$new_version"

tag="v$new_version"
git tag -a "$tag" -m "Release v$new_version"

echo "Created release commit and tag $tag."
if [[ "$no_push" == false ]]; then
  echo "Next step: push with 'git push origin HEAD --follow-tags'" >&2
fi
