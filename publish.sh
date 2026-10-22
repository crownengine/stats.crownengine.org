#!/bin/sh

set -u

case "${1:-}" in
-h|--help)
	echo "usage: $0"
	exit 0
	;;
esac
test $# -eq 0 || { echo "usage: $0" >&2; exit 1; }
case "$0" in
*/*) root=${0%/*} ;;
*) root=. ;;
esac
root=$(CDPATH='' cd "$root" && pwd) || exit 1
cd "$root" || exit 1
git_dir=$(git rev-parse --absolute-git-dir) || exit 1
if git worktree list --porcelain | grep -F -x 'branch refs/heads/gh-pages' >/dev/null 2>&1
then
	echo 'error: gh-pages is checked out in a worktree' >&2
	exit 1
fi

mkdir -p "$root/trash" || exit 1
work=$(mktemp -d "$root/trash/publish.XXXXXX") || exit 1
trap 'rm -rf "$work"' 0
trap 'exit 130' 1 2 3 15
"$root/plot.sh" "$work/site" || exit 1
previous=$(git rev-parse --verify refs/heads/gh-pages 2>/dev/null) || previous=

GIT_DIR=$git_dir
GIT_WORK_TREE=$work/site
GIT_INDEX_FILE=$work/index
export GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
cd "$GIT_WORK_TREE" || exit 1
git read-tree --empty || exit 1
git add --force -- index.html plots .nojekyll || exit 1
if test -n "$previous"
then
	git ls-tree "$previous" -- CNAME >"$work/cname" || exit 1
	git update-index --index-info <"$work/cname" || exit 1
fi
tree=$(git write-tree) || exit 1
if test -n "$previous"
then
	previous_tree=$(git rev-parse "$previous^{tree}") || exit 1
	if test "$tree" = "$previous_tree"
	then
		echo 'gh-pages is already up to date'
		exit 0
	fi
	set -- -p "$previous"
else
	set --
fi
commit=$(printf 'Update Crown release size plots\n' | git commit-tree "$tree" "$@") || exit 1
git update-ref refs/heads/gh-pages "$commit" "$previous" || exit 1
echo "Updated local gh-pages to $commit"
