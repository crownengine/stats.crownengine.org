#!/bin/sh

set -eu

die () {
	echo "error: $*" >&2
	exit 1
}

test $# -eq 2 || die "usage: $0 <commit-message-file> <output-directory>"
LC_ALL=C
export LC_ALL
exec 3<"$1"
subject=
IFS= read -r subject <&3 || test -n "$subject" || exit 0
case "$subject" in
stats:*) ;;
*) echo 'Skipping commit without a stats request'; exit 0 ;;
esac
case "$subject" in
'stats: '*) release=${subject#stats: } ;;
*) die 'expected stats: <release-label>' ;;
esac
case "$release" in
''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+-]*) die "unsupported release label: $release" ;;
esac

output=$2
mkdir -p "$output"
: >"$output/urls"
: >"$output/windows-urls"
while IFS= read -r url <&3 || test -n "$url"
do
	test -n "$url" || continue
	case "$url" in
	*[[:space:]]*) die 'expected one archive URL per line' ;;
	esac
	case "$url" in
	https://?*/*|http://?*/*) ;;
	*) die "unsupported archive URL: $url" ;;
	esac
	archive=${url%%\?*}
	archive=${archive%%\#*}
	archive=${archive##*/}
	case "$archive" in
	''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+-]*) die "unsupported archive name: $archive" ;;
	esac
	case "$archive" in
	*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2|*.tar|*.zip|*.AppImage|*.appimage) ;;
	*) die "unsupported archive format: $archive" ;;
	esac
	printf '%s\n' "$url" >>"$output/urls"
	case "$archive" in
	*-windows-*) printf '%s\n' "$url" >>"$output/windows-urls" ;;
	esac
done
test -s "$output/urls" || die 'stats request has no archive URLs'
printf '%s\n' "$release" >"$output/release"
