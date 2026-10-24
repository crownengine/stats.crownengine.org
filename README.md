# Crown Stats

Measure Crown build sizes and generate plots.

Requires curl, tar, unzip, and gnuplot.

Collect a release using one or more archive URLs:

```sh
./run-stats.sh v0.65.4 \
    https://github.com/crownengine/crown/releases/download/v0.65.4/crown-0.65.4-linux-x64.tar.gz
```

Results are saved under `data/`. Add `--deploy` before the release label to also
measure deployments.

Use `--unstable` to save nightly builds under `data/unstable/`. Google Drive
links are supported directly.

To collect automatically, push a commit with this message (one archive URL per
line). GitHub Actions reads the tip commit and commits the results to the same
branch:

```text
stats: v0.65.4

https://github.com/crownengine/crown/releases/download/v0.65.4/crown-0.65.4-linux-x64.tar.gz
https://github.com/crownengine/crown/releases/download/v0.65.4/crown-0.65.4-windows-x64.zip
```

For nightly builds:

```text
stats: unstable 0.66.0-master-abcdef

https://drive.google.com/uc?export=download&id=LINUX_FILE_ID
https://drive.google.com/uc?export=download&id=WINDOWS_FILE_ID
```

Generate both pages:

```sh
./plot.sh
```

Open `site/index.html` or `site/unstable/index.html`. Use `./plot.sh --unstable`
to generate only the nightly page.

Update the local `gh-pages` branch (does not push):

```sh
./publish.sh
```
