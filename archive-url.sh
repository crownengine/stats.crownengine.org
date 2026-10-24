#!/bin/sh

resolve_archive_url () {
	url=$1
	case "$url" in
	https://?*/*|http://?*/*) ;;
	*)
		echo "error: unsupported archive URL: $url" >&2
		return 1
		;;
	esac
	download_url=$url
	archive=${url%%\?*}
	archive=${archive%%\#*}
	archive=${archive##*/}
	case "$url" in
	https://drive.google.com/*|http://drive.google.com/*|\
	https://drive.usercontent.google.com/*|http://drive.usercontent.google.com/*)
		case "$url" in
		*/file/d/*)
			drive_id=${url#*/file/d/}
			drive_id=${drive_id%%/*}
			drive_id=${drive_id%%\?*}
			drive_id=${drive_id%%\#*}
			;;
		*) drive_id=$(printf '%s\n' "$url" | sed -n 's/.*[?&]id=\([^&#]*\).*/\1/p') || return 1 ;;
		esac
		case "$drive_id" in
		''|*[!A-Za-z0-9_-]*)
			echo 'error: unsupported Google Drive file link' >&2
			return 1
			;;
		esac
		download_url="https://drive.usercontent.google.com/download?id=$drive_id&export=download&confirm=t"
		headers=$(curl --fail --location --silent --show-error --head --retry 2 \
			--connect-timeout 30 --max-time 60 -- "$download_url") || return 1
		archive=$(printf '%s\n' "$headers" | awk '
			tolower($0) ~ /^http\// { filename = "" }
			tolower($0) ~ /^content-disposition:/ {
				sub(/\r$/, "")
				if (match(tolower($0), /;[[:space:]]*filename[[:space:]]*=[[:space:]]*/)) {
					filename = substr($0, RSTART + RLENGTH)
					if (filename ~ /^"/) {
						sub(/^"/, "", filename)
						sub(/".*$/, "", filename)
					} else {
						sub(/;.*/, "", filename)
						sub(/[[:space:]]*$/, "", filename)
					}
				}
			}
			END { print filename }
		') || return 1
		;;
	esac
	case "$archive" in
	''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+-]*)
		echo "error: unsupported archive name: $archive" >&2
		return 1
		;;
	esac
	case "$archive" in
	*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2|*.tar|*.zip|*.AppImage|*.appimage) ;;
	*)
		echo "error: unsupported archive format: $archive" >&2
		return 1
		;;
	esac
}
