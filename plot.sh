#!/bin/sh

set -u

case "${1:-}" in
-h|--help)
	echo "usage: $0 [output-directory]"
	exit 0
	;;
esac
test $# -le 1 || { echo "usage: $0 [output-directory]" >&2; exit 1; }
case "$0" in
*/*) root=${0%/*} ;;
*) root=. ;;
esac
root=$(CDPATH='' cd "$root" && pwd) || exit 1
output=${1:-$root/site}
mkdir -p "$output/plots" "$root/trash" || exit 1
output=$(CDPATH='' cd "$output" && pwd) || exit 1
work=$(mktemp -d "$root/trash/plot.XXXXXX") || exit 1
trap 'rm -rf "$work"' 0
trap 'exit 130' 1 2 3 15
LC_ALL=C
export LC_ALL

test -s "$root/data/releases.csv" || { echo 'error: no release data' >&2; exit 1; }
command -v gnuplot >/dev/null 2>&1 || { echo 'error: gnuplot is required' >&2; exit 1; }

index=0
: >"$work/releases.tsv"
: >"$work/measurements.tsv"
while IFS= read -r release
do
	test "$release" != release || continue
	release=${release#\"}
	release=${release%\"}
	version=${release#v}
	if test "${version%%.*}" = 0
	then
		version=${version#*.}
		test "${version%%.*}" -ge 48 || continue
	fi
	index=$((index + 1))
	printf '%s\t%s\n' "$index" "$release" >>"$work/releases.tsv" || exit 1
	for csv in "$root/data/$release/archives.csv" "$root/data/$release/binaries.csv"
	do
		test -f "$csv" || continue
		awk -F, -v release_index="$index" -v release="$release" '
			function package(name, format) {
				format = name
				sub(/^.*\./, "", format)
				if (name ~ /\.tar\.gz$/) format = "tar.gz"
				if (name ~ /\.tar\.xz$/) format = "tar.xz"
				if (name ~ /\.tar\.bz2$/) format = "tar.bz2"
				sub(/\.(tar\.(gz|xz|bz2)|tgz|tar|zip|AppImage|appimage)$/, "", name)
				if (match(name, /-(linux|windows|android|html5|macos|osx)-[^-]+$/))
					name = substr(name, RSTART + 1)
				else
					sub(/^crown-[^-]+-/, "", name)
				return name "-" format
			}
			NR == 1 { archives = ($2 == "url"); next }
			{
				for (i = 1; i <= NF; ++i) gsub(/^"|"$/, "", $i)
				if (!archives && $4 == "development") next
				series = package($1)
				if (archives) {
					printf "%d\t%s\tarchives\t%s-compressed\t%s\n", release_index, release, series, $(NF - 1)
					printf "%d\t%s\tarchives\t%s-uncompressed\t%s\n", release_index, release, series, $NF
				} else if ($3 == "runtime") {
					printf "%d\t%s\truntime-%s\t%s\t%s\n", release_index, release, $4, $2, $5
				} else {
					printf "%d\t%s\t%s\t%s\t%s\n", release_index, release, $3, $2, $5
				}
			}
		' "$csv" >>"$work/measurements.tsv" || exit 1
	done
	for csv in "$root/data/$release/deployments/"*.csv
	do
		test -f "$csv" || continue
		platform=${csv##*/}
		platform=${platform%.csv}
		awk -F, -v release_index="$index" -v release="$release" -v platform="$platform" '
			NR > 1 && $2 == "\"release\"" {
				printf "%d\t%s\tdeployment\t%s\t%s\n", release_index, release, platform, $3
			}
		' "$csv" >>"$work/measurements.tsv" || exit 1
	done
done <"$root/data/releases.csv"
test -s "$work/measurements.tsv" || { echo 'error: no measurements' >&2; exit 1; }
sort -t "$(printf '\t')" -k3,3 -k4,4 -k1,1n "$work/measurements.tsv" >"$work/sorted.tsv" || exit 1

awk -F '\t' -v directory="$work" '
	FNR == NR { labels[$1] = $2; releases = $1; next }
	{
		plot = $3
		series = $4
		if (!seen[plot, series]++) columns[plot, ++count[plot]] = series
		values[plot, $1, series] = $5
	}
	END {
		for (plot in count) {
			file = directory "/" plot ".tsv"
			printf "Release" >file
			for (column = 1; column <= count[plot]; ++column)
				printf "\t%s", columns[plot, column] >file
			printf "\n" >file
			for (release = 1; release <= releases; ++release) {
				printf "%s", labels[release] >file
				for (column = 1; column <= count[plot]; ++column) {
					key = plot SUBSEP release SUBSEP columns[plot, column]
					printf "\t%s", (key in values ? values[key] : "NaN") >file
				}
				printf "\n" >file
			}
			close(file)
		}
	}
' "$work/releases.tsv" "$work/sorted.tsv" || exit 1

cat >"$work/index.html" <<-EOF
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Crown release sizes</title>
<style>
body { max-width: 1400px; margin: 2rem auto; padding: 0 1rem; text-align: center; }
object { display: block; width: 100%; aspect-ratio: 16 / 9; }
</style>
<h1>Crown release sizes</h1>
<p>Click a legend entry to show or hide a series. Click a plot to toggle version and size readouts.</p>
EOF

for table in "$work"/deployment.tsv "$work"/runtime-*.tsv "$work"/editor.tsv "$work"/archives.tsv
do
	test -f "$table" || continue
	name=${table##*/}
	name=${name%.tsv}
	case "$name" in
	deployment) title='Deployment Size' ;;
	runtime-release) title='Runtime Size' ;;
	runtime-*) title="Runtime Size (${name#runtime-})" ;;
	editor) title='Editor Size' ;;
	archives) title='Archive Size' ;;
	esac
	case "$name" in
	deployment) description='Release deployment of an empty project (samples/00-empty). Android measures the final APK; other targets sum deployed files.' ;;
	runtime-*) description='Runtime binaries, excluding shared dependencies and separate debug symbols.' ;;
	editor) description='Editor binaries, excluding shared dependencies and separate debug symbols.' ;;
	archives) description='Compressed archive size and the sum of extracted files sizes.' ;;
	esac
	cat >"$work/plot.gnuplot" <<-EOF
	set terminal svg size 1600,900 dynamic mouse standalone noenhanced
	set output '$name.svg'
	set title '$title'
	set datafile separator '\t'
	set datafile missing 'NaN'
	set xlabel 'Release'
	set ylabel 'Size (MiB)'
	set yrange [0:*]
	set lmargin at screen 0.07
	set rmargin at screen 0.80
	set bmargin at screen 0.15
	set tmargin at screen 0.92
	set grid ytics
	set xtics rotate by -60 font ',9'
	set key outside right center
	plot for [c=2:*] '$name.tsv' using 0:(column(c)/1048576.0):xticlabels(1) with linespoints linewidth 1.5 pointtype 7 pointsize 0.4 title columnheader(c)
	EOF
	(cd "$work" && gnuplot plot.gnuplot) || exit 1
	# Customize SVG controls and replace coordinate indices with release labels.
	awk -F '\t' '
		FNR == NR { releases[++count] = $2; next }
		/<\/svg>/ {
			print "<script type=\"text/javascript\"><![CDATA["
			printf "var releases = ["
			for (i = 1; i <= count; ++i)
				printf "%s\"%s\"", (i > 1 ? ", " : ""), releases[i]
			print "];"
			print "function showRelease() {"
			print "    var label = document.getElementById(\"coord_text\");"
			print "    var coordinates = label.textContent.split(/\\s+/);"
			print "    var release = releases[Math.round(Number(coordinates[0]))];"
			print "    if (coordinates.length === 2 && release)"
			print "        label.textContent = release + \" \" + coordinates[1] + \" MiB\";"
			print "}"
			print "window.addEventListener(\"mousemove\", showRelease);"
			print "window.addEventListener(\"click\", showRelease);"
			print "window.addEventListener(\"wheel\", function (event) {"
			print "    event.stopImmediatePropagation();"
			print "}, { capture: true, passive: true });"
			print "window.addEventListener(\"mousedown\", function (event) {"
			print "    event.stopImmediatePropagation();"
			print "}, true);"
			print "window.addEventListener(\"keydown\", function (event) {"
			print "    if ([\"+\", \"-\", \"Add\", \"Subtract\"].indexOf(event.key) !== -1)"
			print "        event.stopImmediatePropagation();"
			print "}, true);"
			print "]]></script>"
		}
		{ print }
	' "$work/releases.tsv" "$work/$name.svg" >"$work/$name.svg.tmp" || exit 1
	mv "$work/$name.svg.tmp" "$work/$name.svg" || exit 1
	printf '<h2>%s</h2>\n<p>%s</p>\n<object data="plots/%s.svg" type="image/svg+xml" aria-label="%s"><a href="plots/%s.svg">%s</a></object>\n' \
		"$title" "$description" "$name" "$title" "$name" "$title" >>"$work/index.html" || exit 1
done
printf '</html>\n' >>"$work/index.html" || exit 1
rm -f "$output/plots/runtime-development.svg" || exit 1
cp "$work"/*.svg "$output/plots/" || exit 1
cp "$work/index.html" "$output/index.html" || exit 1
: >"$output/.nojekyll"
echo "Generated $output/index.html"
