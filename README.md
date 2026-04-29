# Wings Auto Patch + Release

This repository automates:

1. Fetching upstream `https://github.com/pterodactyl/wings`
2. Applying local patch files from `patches/*.patch`
3. Building release-safe `linux/amd64` and `linux/arm64` binaries
4. Publishing a GitHub release tagged as `vX.Y.Z-YYYYMMDD`

`X.Y.Z` is parsed from the latest top entry in upstream `CHANGELOG.md`.

## Install Latest Release

```bash
sudo curl -L -o /usr/local/bin/wings "https://github.com/noticebrick/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
sudo chmod u+x /usr/local/bin/wings
```

## Workflow

Workflow file: `.github/workflows/weekly-patch-release.yml`

Triggers:

1. Weekly schedule (Monday 03:00 UTC)
2. Manual run (`workflow_dispatch`)

Manual inputs:

1. `upstream_ref` (optional): branch/tag/SHA to build from
2. `date_override` (optional): force date in `YYYYMMDD`

## Patches

Put patch files into `patches/` with `.patch` extension.

They are applied in filename order using `git apply`.

## Output

Each run creates:

1. `dist/wings_linux_amd64`
2. `dist/wings_linux_arm64`
3. `dist/SHA256SUMS`

Then a GitHub release is created (or updated) with tag format:

`vX.Y.Z-YYYYMMDD`
