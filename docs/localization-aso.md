# Bond — localization & ASO backups

## Backup paths (2026-05-25 go)

| Snapshot | Path |
|----------|------|
| Pre-pull (ASC ground truth) | `fastlane/metadata.bak.20260525-190656/` |
| Pre-upload (optimized copy) | `fastlane/metadata.bak.pre-upload-20260525-190909/` |

## Restore

```bash
./scripts/restore-appstore-metadata.sh fastlane/metadata.bak.pre-upload-20260525-190909
```

## ASC draft

- **Version:** `1.0` (`PREPARE_FOR_SUBMISSION`)
- **App ID:** `6768514177` (`com.jackwallner.bond`)
- **Locales on disk:** 50 (`fastlane/metadata/<locale>/`)
- **State file:** `scripts/.asc-state.json`

## Astro

- **App ID (temporary):** `101` — replace with App Store Connect ID after Bond is live in Astro
- **Stores target:** 91 (`scripts/astro-stores-2026.json`)
- **Sync output:** `scripts/astro-keywords-by-store/_summary.json`

## Playbook

`docs/astro-global-aso-go-2026.md` (copy of Desktop playbook)
