#!/bin/sh

set -u

usage () {
	cat <<-EOF
	usage: $0 [--unstable] [--deploy] [--deploy-platform <platform>] <build-label> <archive-url>...
	Collect Crown package and binary sizes under data/.
	Use --unstable to save nightly builds under data/unstable/.
	Use --deploy to also measure release deployments of samples/00-empty.
	EOF
}

die () {
	echo "error: $*" >&2
	exit 1
}

csv_quote () {
	printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')"
}

directory_bytes () {
	find "$1" -type f -exec wc -c {} + >"$work/counts" || return 1
	awk '
		/^[[:space:]]*[0-9]+ total$/ { next }
		{ bytes += $1 }
		END { printf "%.0f\n", bytes }
	' "$work/counts"
}

run_editor () (
	XDG_CONFIG_HOME=$deployment_work/config
	XDG_DATA_HOME=$deployment_work/data-home
	XDG_CACHE_HOME=$deployment_work/cache
	XDG_RUNTIME_DIR=$deployment_work/runtime
	TMPDIR=$deployment_work/tmp
	export XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR TMPDIR
	if test "$deployment_host" = windows64 && command -v cygpath >/dev/null 2>&1
	then
		APPDATA=$(cygpath -w "$XDG_CONFIG_HOME") || exit 1
		LOCALAPPDATA=$(cygpath -w "$XDG_DATA_HOME") || exit 1
		TEMP=$(cygpath -w "$TMPDIR") || exit 1
		TMP=$TEMP
		export APPDATA LOCALAPPDATA TEMP TMP
	fi
	if test "$1" != --help && test "$deployment_host" = linux64
	then
		exec dbus-run-session -- "$editor_launcher" editor "$@"
	fi
	exec "$editor_launcher" editor "$@"
)

collect_deployment () {
	deployment_output=$deployment_work/output/$deployment_target
	set -- --source-dir "$deployment_work/project" \
		--deploy --output-dir "$deployment_output" --config release --app-title 00-empty
	case "$deployment_target" in
	linux64)
		set -- "$@" --platform linux
		deployment_package=$deployment_output/linux/x64/release/00-empty
		;;
	windows64)
		set -- "$@" --platform windows
		deployment_package=$deployment_output/windows/x64/release/00-empty
		;;
	android-*)
		if test -z "${ANDROID_SDK_PATH:-}" || test -z "${ANDROID_NDK_ROOT:-}"
		then
			echo 'Set ANDROID_SDK_PATH and ANDROID_NDK_ROOT for Android deployment.' >&2
			return 1
		fi
		set -- "$@" --platform android --arch "${deployment_target#android-}" \
			--app-id org.crownengine.stats.empty --app-version-code 1 --app-version-name 1.0
		deployment_package=$deployment_output/android/${deployment_target#android-}/release/org.crownengine.stats.empty-1.0.apk
		;;
	wasm|wasm64)
		if test -z "${EMSCRIPTEN:-}"
		then
			echo 'Set EMSCRIPTEN for HTML5 deployment.' >&2
			return 1
		fi
		set -- "$@" --platform html5
		test "$deployment_target" != wasm64 || set -- "$@" --arch wasm64
		deployment_package=$deployment_output/html5/$deployment_target/release/00-empty
		;;
	esac
	run_editor "$@" || return 1
	case "$deployment_target" in
	android-*)
		deployment_bytes=$(wc -c <"$deployment_package") || return 1
		;;
	*)
		test -d "$deployment_package" || return 1
		deployment_bytes=$(directory_bytes "$deployment_package") || return 1
		;;
	esac
	printf 'archive,configuration,bytes\n%s,"release",%s\n' \
		"$quoted_archive" "$((deployment_bytes))" >"$deployment_work/result.csv" || return 1
	mkdir -p "$release_dir/deployments" || return 1
	mv "$deployment_work/result.csv" "$release_dir/deployments/$deployment_target.csv" || return 1
}

collect_deployments () {
	case "$(uname -s)" in
	Linux) deployment_host=linux64; editor_suffix= ;;
	MINGW*|MSYS*|CYGWIN*) deployment_host=windows64; editor_suffix=.exe ;;
	*)
		echo 'Skipping deployment: no native desktop deployer for this host'
		return 0
		;;
	esac
	find "$work/extracted" -type f -name "crown-launcher$editor_suffix" >"$work/launchers" || return 1
	deployment_sdk=
	while IFS= read -r launcher
	do
		sdk=${launcher%/*}
		if test -f "$sdk/platforms/$deployment_host/bin/crown-editor-release$editor_suffix"
		then
			deployment_sdk=$sdk
			editor_launcher=$launcher
			break
		fi
	done <"$work/launchers"
	if test -z "$deployment_sdk"
	then
		echo "Skipping deployment: no native $deployment_host editor in $archive"
		return 0
	fi
	case "$archive" in
	*.AppImage|*.appimage) editor_launcher=$work/extracted/squashfs-root/AppRun ;;
	esac
	deployment_work=$work/deployment
	rm -rf "$deployment_work"
	mkdir -p "$deployment_work/config" "$deployment_work/data-home" \
		"$deployment_work/cache" "$deployment_work/tmp" || return 1
	case "$deployment_host" in
	windows64) mkdir "$deployment_work/runtime" || return 1 ;;
	*) mkdir -m 700 "$deployment_work/runtime" || return 1 ;;
	esac
	deployment_logs=$root/trash/deploy-$release
	if ! run_editor --help >"$deployment_work/help" 2>&1
	then
		mkdir -p "$deployment_logs" || return 1
		cp "$deployment_work/help" "$deployment_logs/editor-help.log" || return 1
		echo "error: cannot start the release editor; see $deployment_logs/editor-help.log" >&2
		return 1
	fi
	if ! grep -q -e '--deploy' "$deployment_work/help"
	then
		echo "Skipping deployment: $release has no deployment CLI"
		return 0
	fi
	cp -R "$deployment_sdk/samples/00-empty" "$deployment_work/project" || return 1
	deployment_failed=0
	for deployment_target in "$deployment_host" android-arm android-arm64 wasm wasm64
	do
		if test -n "$deploy_platform" && test "$deployment_target" != "$deploy_platform"
		then
			continue
		fi
		if ! awk -F, -v target="$deployment_target" '
			$1 == target && $2 == "runtime" && $3 == "release" { found = 1 }
			END { exit !found }
		' "$work/binary-sizes"
		then
			continue
		fi
		if test "$deployment_target" = wasm64 && ! grep -q -e '^[[:space:]]*wasm64[[:space:]]*$' "$deployment_work/help"
		then
			echo "Skipping wasm64 deployment: unsupported by this editor CLI"
			continue
		fi
		echo "Deploying $release / 00-empty / $deployment_target / release"
		if collect_deployment >"$deployment_work/$deployment_target.log" 2>&1
		then
			echo "Recorded $((deployment_bytes)) deployment bytes for $deployment_target"
		else
			mkdir -p "$deployment_logs" || return 1
			cp "$deployment_work/$deployment_target.log" "$deployment_logs/$deployment_target.log" || return 1
			echo "error: deployment failed; see $deployment_logs/$deployment_target.log" >&2
			deployment_failed=1
		fi
	done
	return "$deployment_failed"
}

collect_archive () {
	resolve_archive_url "$1" || return 1

	echo "Collecting $release / $archive"
	rm -rf "$work/extracted"
	mkdir "$work/extracted" || return 1
	curl --fail --location --silent --show-error --retry 2 \
		--connect-timeout 30 --max-time 900 \
		--output "$work/download" -- "$download_url" || return 1
	compressed=$(wc -c <"$work/download") || return 1
	compressed=$((compressed))

	case "$archive" in
	*.zip)
		unzip -q "$work/download" -d "$work/extracted" || return 1
		;;
	*.AppImage|*.appimage)
		chmod +x "$work/download" || return 1
		(cd "$work/extracted" && ../download --appimage-extract >../extraction.log) || return 1
		;;
	*)
		tar -xf "$work/download" -C "$work/extracted" || return 1
		;;
	esac

	extracted=$(directory_bytes "$work/extracted") || return 1

	find "$work/extracted" -type f \( \
		-name 'crown-*' -o -name 'libcrown-*' -o -name 'level-editor-*' \
	\) >"$work/files" || return 1
	: >"$work/binary-sizes"
	while IFS= read -r file
	do
		bin=${file%/*}
		test "${bin##*/}" = bin || continue
		platform=${bin%/*}
		platform=${platform##*/}
		case "$platform" in
		mingw32) platform=windows32 ;;
		mingw64) platform=windows64 ;;
		esac
		case "$platform" in
		''|*[!A-Za-z0-9_-]*) continue ;;
		esac
		name=${file##*/}
		for configuration in debug development release
		do
			case "$name" in
			crown-"$configuration"|crown-"$configuration".exe|libcrown-"$configuration".so|\
			crown-"$configuration".wasm|crown-"$configuration".js|crown-"$configuration".worker.js)
				component=runtime
				;;
			crown-editor-"$configuration"|crown-editor-"$configuration".exe)
				component=editor
				;;
			level-editor-"$configuration"|level-editor-"$configuration".exe)
				test ! -f "$bin/crown-editor-$configuration" || continue
				test ! -f "$bin/crown-editor-$configuration.exe" || continue
				component=editor
				;;
			*) continue ;;
			esac
			bytes=$(wc -c <"$file") || return 1
			printf '%s,%s,%s,%s\n' "$platform" "$component" "$configuration" "$((bytes))" \
				>>"$work/binary-sizes" || return 1
		done
	done <"$work/files"
	if test ! -s "$work/binary-sizes"
	then
		echo "error: no Crown binaries found in $archive" >&2
		return 1
	fi

	quoted_archive=$(csv_quote "$archive") || return 1
	printf 'archive,url,compressed_bytes,extracted_bytes\n' >"$work/archives.csv" || return 1
	if test -f "$release_dir/archives.csv"
	then
		awk -v prefix="$quoted_archive," 'NR > 1 && index($0, prefix) != 1' \
			"$release_dir/archives.csv" >>"$work/archives.csv" || return 1
	fi
	printf '%s,%s,%s,%s\n' "$quoted_archive" "$(csv_quote "$url")" "$compressed" "$extracted" \
		>>"$work/archives.csv" || return 1

	: >"$work/binary-rows"
	if test -f "$release_dir/binaries.csv"
	then
		awk -v prefix="$quoted_archive," 'NR > 1 && index($0, prefix) != 1' \
			"$release_dir/binaries.csv" >>"$work/binary-rows" || return 1
	fi
	awk -F, -v archive="$quoted_archive" '
		{ key = $1 SUBSEP $2 SUBSEP $3; bytes[key] += $4 }
		END {
			for (key in bytes) {
				split(key, fields, SUBSEP)
				printf "%s,\"%s\",\"%s\",\"%s\",%.0f\n", archive, fields[1], fields[2], fields[3], bytes[key]
			}
		}
	' "$work/binary-sizes" >>"$work/binary-rows" || return 1
	printf 'archive,platform,component,configuration,bytes\n' >"$work/binaries.csv" || return 1
	sort "$work/binary-rows" >>"$work/binaries.csv" || return 1

	mkdir -p "$release_dir" || return 1
	mv "$work/archives.csv" "$release_dir/archives.csv" || return 1
	mv "$work/binaries.csv" "$release_dir/binaries.csv" || return 1
	if test ! -f "$data_directory/releases.csv"
	then
		printf 'release\n' >"$data_directory/releases.csv" || return 1
	fi
	if ! grep -F -x "\"$release\"" "$data_directory/releases.csv" >/dev/null 2>&1
	then
		printf '"%s"\n' "$release" >>"$data_directory/releases.csv" || return 1
	fi
	echo "Recorded $compressed compressed bytes, $extracted extracted bytes"
	test "$deploy" -eq 0 || collect_deployments || return 1
}

unstable=0
deploy=0
deploy_platform=
while test $# -gt 0
do
	case "$1" in
	--unstable) unstable=1 ;;
	--deploy) deploy=1 ;;
	--deploy-platform)
		test $# -ge 2 || die 'missing deployment platform'
		shift
		case "$1" in
		linux64|windows64|android-arm|android-arm64|wasm|wasm64) deploy_platform=$1 ;;
		*) die "unsupported deployment platform: $1" ;;
		esac
		;;
	-h|--help) usage; exit 0 ;;
	--) shift; break ;;
	-*) die "unknown option: $1" ;;
	*) break ;;
	esac
	shift
done
test -z "$deploy_platform" || test "$deploy" -eq 1 || die '--deploy-platform requires --deploy'
test $# -ge 2 || { usage >&2; exit 1; }
release=$1
shift
case "$release" in
''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+-]*) die "unsupported release label: $release" ;;
esac

case "$0" in
*/*) root=${0%/*} ;;
*) root=. ;;
esac
root=$(CDPATH='' cd "$root" && pwd) || exit 1
# shellcheck source=archive-url.sh
. "$root/archive-url.sh"
data_directory=$root/data
test "$unstable" -eq 0 || data_directory=$data_directory/unstable
release_dir=$data_directory/$release
LC_ALL=C
export LC_ALL
mkdir -p "$root/trash" || exit 1
work=$(mktemp -d "$root/trash/stats.XXXXXX") || exit 1
trap 'rm -rf "$work"' 0
trap 'exit 130' 1 2 3 15

failed=0
for url
do
	if ! collect_archive "$url"
	then
		echo "error: failed to collect $url" >&2
		failed=1
	fi
done
exit "$failed"
