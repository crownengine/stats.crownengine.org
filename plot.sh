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

# sRGB equivalents of crown-website's silver and cool-horizon color roles.
canvas='#050607'
surface='#121415'
line='#27292b'
grid='#505356'
ink='#f6f7f8'
muted='#b5b8ba'
brand='#71aaf4'

cat >"$work/index.html" <<-EOF
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Crown Build Sizes</title>
<!-- Google tag (gtag.js) -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-HBZD4B34QJ"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());

  gtag('config', 'G-HBZD4B34QJ');
</script>
<style>
html { color-scheme: dark; background: $canvas; color: $ink; font-family: "Inter Variable", Inter, system-ui, sans-serif; }
body { max-width: 1400px; margin: 2rem auto; padding: 0 1rem; text-align: center; font-size: 18px; line-height: 1.6; }
h1 { line-height: 1.2; }
p { color: $muted; }
a { color: $brand; }
object { display: block; width: 100%; aspect-ratio: 16 / 9; margin: 2rem 0; box-sizing: border-box; background: $surface; border: 1px solid $line; border-radius: 0.5rem; }
</style>
<h1>Crown Build Sizes</h1>
<p>Click a legend entry to show or hide a series. Hover over a data point to see its size.</p>
EOF

for table in "$work"/deployment.tsv "$work"/runtime-*.tsv "$work"/editor.tsv "$work"/archives.tsv
do
	test -f "$table" || continue
	name=${table##*/}
	name=${name%.tsv}
	case "$name" in
	deployment) title='Bundle Size' ;;
	runtime-release) title='Runtime Size' ;;
	runtime-*) title="Runtime Size (${name#runtime-})" ;;
	editor) title='Editor Size' ;;
	archives) title='Package Sizes' ;;
	esac
	case "$name" in
	deployment) description='Release bundle of an empty project (samples/00-empty).' ;;
	runtime-release) description='Crown Runtime binaries in release configuration, excluding shared dependencies.' ;;
	runtime-*) description='Crown Runtime binaries, excluding shared dependencies.' ;;
	editor) description='Crown Editor binaries, excluding shared dependencies.' ;;
	archives) description='Full Crown package, compressed and extracted.' ;;
	esac
	cat >"$work/plot.gnuplot" <<-EOF
	set terminal svg size 1600,900 dynamic mouse standalone enhanced font 'sans-serif,18' background '$surface'
	set output '$name.svg'
	set title "$title\n{/=16 $description}" enhanced font ',24' textcolor rgb '$ink'
	set datafile separator '\t'
	set datafile columnheaders
	set datafile missing 'NaN'
	set xlabel 'Release' noenhanced textcolor rgb '$muted'
	set ylabel "Size (MiB)\n{/=14 Lower is better}" enhanced textcolor rgb '$muted'
	set yrange [0:*]
	set lmargin at screen 0.07
	set rmargin at screen 0.97
	set bmargin at screen 0.18
	set tmargin at screen 0.86
	set border linecolor rgb '$muted'
	set grid ytics linecolor rgb '$grid' linewidth 1.2 dashtype 3
	set xtics noenhanced rotate by -60 font ',13' textcolor rgb '$muted'
	set ytics noenhanced textcolor rgb '$muted'
	set key inside left top vertical Left reverse opaque fc rgb '$surface' box linecolor rgb '$grid' linewidth 1 samplen 2.5 spacing 1.1 offset 1,-1 noenhanced font ',17' textcolor variable
	EOF
	# Keep platform colors consistent across plots; distinguish related series by line style.
	awk -F '\t' -v brand="$brand" '
		NR == 1 {
			for (column = 2; column <= NF; ++column) {
				series = $column
				color = brand
				if (series ~ /^android/) color = "#3ddc84"
				else if (series ~ /^linux/) color = "#fcc624"
				else if (series ~ /^windows/) color = "#00a4ef"
				else if (series ~ /^wasm/) color = "#9f8cff"
				else if (series ~ /^html5/) color = "#f06529"
				else if (series ~ /^(macos|osx)/) color = "#b5b8ba"
				dash = (series ~ /-uncompressed$/ ? 2 : 1)
				point = 7
				if (series ~ /^(android-arm64|wasm64)$/) {
					dash = 3
					point = 9
				}
				printf "set style line %d linecolor rgb \"%s\" linewidth 3 dashtype %d pointtype %d pointsize 0.7\n", column - 1, color, dash, point
			}
			exit
		}
	' "$table" >>"$work/plot.gnuplot" || exit 1
	printf "plot for [c=2:*] '%s.tsv' using 0:(column(c)/1048576.0):xticlabels(1) with linespoints linestyle (c - 1) title columnheader(c), for [c=2:*] '%s.tsv' using 0:(column(c)/1048576.0):(sprintf('%%.2f MiB', column(c)/1048576.0)) with labels hypertext point pointtype 7 pointsize 0.9 linecolor rgb '#ff000000' font 'sans-serif,18' notitle\n" \
		"$name" "$name" >>"$work/plot.gnuplot" || exit 1
	(cd "$work" && gnuplot plot.gnuplot) || exit 1
	# Style the SVG links, tooltips, legend, and controls.
	awk -v ink="$ink" -v surface="$surface" -v muted="$muted" -v brand="$brand" '
		# Older gnuplot scripts embed a CDATA terminator in a JavaScript string.
		{ gsub(/"]]>"/, "\"]]]]><![CDATA[>\"") }
		/<text>.*samples\/00-empty/ {
			sub(/samples\/00-empty/, "<a xlink:href=\"https://github.com/crownengine/crown/tree/master/samples/00-empty\" target=\"_blank\">samples/00-empty</a>")
		}
		/<text>.*Full Crown package/ {
			sub(/Full Crown package/, "<a xlink:href=\"https://crownengine.org/download\" target=\"_blank\">Full Crown package</a>")
		}
		# Reference the plot for the blurred legend backdrop.
		/<\/defs>/ {
			print
			print "<g id=\"plot-data\">"
			next
		}
		/<g stroke=.none. shape-rendering=.crispEdges.>/ { print "</g>" }
		# The key background is the only filled polygon in these line plots.
		/<polygon / {
			print "<defs><clipPath id=\"legend-clip\">"
			print
			print "</clipPath>"
			print "<filter id=\"legend-blur\" color-interpolation-filters=\"sRGB\">"
			print "<feGaussianBlur stdDeviation=\"6\"/>"
			print "</filter></defs>"
			print "<g class=\"legend-background\" clip-path=\"url(#legend-clip)\" pointer-events=\"none\">"
			print
			print "<use xlink:href=\"#plot-data\" filter=\"url(#legend-blur)\"/>"
			sub(/<polygon /, "<polygon fill-opacity=\"0.55\" ")
			print
			print "</g>"
			next
		}
		/<\/svg>/ {
			print "<style>"
			printf "a { fill: %s; text-decoration: underline; }\n", brand
			print "#coord_text { display: none; }"
			print "#hypertext, #hypertextbox { transform: translateY(-32px); }"
			printf "#hypertext { fill: %s; font-family: sans-serif; font-size: 18px; }\n", ink
			printf "#hypertextbox { fill: %s; stroke: %s; }\n", surface, muted
			print "</style>"
			print "<script type=\"text/javascript\"><![CDATA["
			# Group native tooltip layers before gnuplot initializes its mouse handlers.
			print "var tooltipPlots = Array.from(document.querySelectorAll(\"#plot-data > g\")).filter(function (plot) { return plot.querySelector(\"g[onmousemove]\"); });"
			print "var keys = Array.from(new Set(Array.from(document.querySelectorAll(\"g[id$=_keyentry]\"), function (key) { return key.id; })));"
			print "keys.forEach(function (key, i) {"
			print "    document.getElementById(key.replace(\"_keyentry\", \"\")).appendChild(tooltipPlots[i]);"
			print "});"
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
	' "$work/$name.svg" >"$work/$name.svg.tmp" || exit 1
	mv "$work/$name.svg.tmp" "$work/$name.svg" || exit 1
	printf '<object data="plots/%s.svg" type="image/svg+xml" aria-label="%s"><a href="plots/%s.svg">%s</a></object>\n' \
		"$name" "$title" "$name" "$title" >>"$work/index.html" || exit 1
done
printf '</html>\n' >>"$work/index.html" || exit 1
rm -f "$output/plots/runtime-development.svg" || exit 1
cp "$work"/*.svg "$output/plots/" || exit 1
cp "$work/index.html" "$output/index.html" || exit 1
: >"$output/.nojekyll"
echo "Generated $output/index.html"
