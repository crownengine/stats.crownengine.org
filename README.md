# Crown Stats

Measure Crown release sizes and generate plots.

Requires curl, tar, unzip, and gnuplot.

Collect a release using one or more archive URLs:

```sh
./run-stats.sh v0.65.4 \
    https://github.com/crownengine/crown/releases/download/v0.65.4/crown-0.65.4-linux-x64.tar.gz
```

Results are saved under `data/`. Add `--deploy` before the release label to also
measure deployments.

To collect automatically, push a commit with this message (one archive URL per
line). GitHub Actions reads the tip commit and commits the results to the same
branch:

```text
stats: v0.65.4

https://github.com/crownengine/crown/releases/download/v0.65.4/crown-0.65.4-linux-x64.tar.gz
https://github.com/crownengine/crown/releases/download/v0.65.4/crown-0.65.4-windows-x64.zip
```

Generate the page:

```sh
./plot.sh
```

Open `site/index.html` to view the plots.

Update the local `gh-pages` branch (does not push):

```sh
./publish.sh
```
