#!/usr/bin/env bash
# validate_repo.sh —— 不连接基础设施的仓库静态检查
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

check_shell_syntax() {
  local count=0 file
  while IFS= read -r -d '' file; do
    bash -n "$file"
    ((count += 1))
  done < <(find . -path './.git' -prune -o -type f -name '*.sh' -print0)
  printf 'PASS shell syntax (%d files)\n' "$count"
}

check_markdown_links() {
  local count=0 doc target resolved
  while IFS= read -r -d '' doc; do
    while IFS= read -r target; do
      target="${target#](}"
      target="${target%)}"
      case "$target" in
        http://*|https://*|mailto:*|\#*|'') continue ;;
      esac
      target="${target%%#*}"
      resolved="$(dirname "$doc")/$target"
      [[ -e "$resolved" ]] || {
        printf 'FAIL missing local link: %s -> %s\n' "$doc" "$target" >&2
        return 1
      }
      ((count += 1))
    done < <(grep -oE '\]\([^)]+\)' "$doc" || true)
  done < <(find . -path './.git' -prune -o -type f -name '*.md' -print0)
  printf 'PASS local Markdown links (%d links)\n' "$count"
}

check_public_boundary() {
  local file
  while IFS= read -r -d '' file; do
    case "$file" in
      *.run|*.pem|*.key|*.crt|*.p12|*.pfx|*.tok)
        printf 'FAIL restricted artifact is tracked: %s\n' "$file" >&2
        return 1
        ;;
    esac
  done < <(git ls-files -z)
  printf 'PASS public artifact boundary\n'
}

check_repository_whitespace() {
  local empty_tree
  empty_tree="$(git hash-object -t tree /dev/null)"
  git diff --check "$empty_tree" HEAD
  git diff --check
  printf 'PASS repository whitespace\n'
}

check_offline_tests() {
  local count=0 test_file
  while IFS= read -r -d '' test_file; do
    bash "$test_file"
    ((count += 1))
  done < <(find tests -maxdepth 1 -type f -name 'test_*.sh' -print0 2>/dev/null)
  printf 'PASS offline tests (%d files)\n' "$count"
}

check_shell_syntax
check_markdown_links
check_public_boundary
check_repository_whitespace
check_offline_tests
printf 'PASS repository validation\n'
