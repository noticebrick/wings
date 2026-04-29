# Wings Auto Patch + Release

This repository automates:

1. Fetching upstream `https://github.com/pterodactyl/wings`
2. Applying local patch files from `patches/*.patch`
3. Building a release-safe `linux/amd64` binary
4. Publishing a GitHub release tagged as `vX.Y.Z-YYYYMMDD`

`X.Y.Z` is parsed from the latest top entry in upstream `CHANGELOG.md`.

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
2. `dist/SHA256SUMS`

Then a GitHub release is created (or updated) with tag format:

`vX.Y.Z-YYYYMMDD`
