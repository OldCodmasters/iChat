# Releasing iChat

Stage 1 distribution is a **GitHub Release** with:

1. **Addon zip** — `Interface/AddOns/iChat/`
2. **Companion** — run from the tagged source (`companion/`)
3. **Relay server** — run from the tagged source (`server/`)

There is no CurseForge / Wago / npm publish in Stage 1. Transport is chatlog `fs.watch` + overlay + WebSocket relay (see root README).

## Cut a release

1. Ensure `main` is green and reviewed (CODEOWNERS / ruleset).
2. Update `addon/iChat/iChat.toc` `## Version:` if needed.
3. Tag and push from `main`:

```bash
git checkout main
git pull origin main
git tag -a v0.3.0 -m "iChat v0.3.0"
git push origin v0.3.0
```

4. GitHub Actions workflow [`.github/workflows/release.yml`](../.github/workflows/release.yml) builds `iChat-addon-v0.3.0.zip` and creates the Release.
5. Smoke: download the zip, install addon, run server + companion against the tag, confirm overlay + `/gsay` chatlog path.

## Versioning

- Tags: `vMAJOR.MINOR.PATCH`
- Prefer aligning TOC `## Version:` with the tag without the `v` prefix when practical (e.g. tag `v0.3.0` → TOC `0.3.0`).
