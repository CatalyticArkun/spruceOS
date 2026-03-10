# archiveUnpacker regression validation

## Automated coverage matrix

| Area | Scenario | Method |
|---|---|---|
| Lane integrity | `unstage_archive` preserves `preCmd`; fallback to `preMenu` for empty/non-`preCmd`; `unstage_archives_wanted` routes known `preCmd` call-sites correctly | Dynamic shell test fixtures |
| Boot orchestration | `runtime.sh` normal boot uses default `archiveUnpacker.sh`; firstboot/recovery still uses `--silent &`; ThemeGarden still calls no-arg unpacker; no residual normal-boot `pre_cmd` call | Static source assertions via `rg` |
| Mode scope | `RUN_MODE=all` scans `themes`, `preMenu`, `preCmd`; `RUN_MODE=pre_cmd` limits to `preCmd`; invalid mode exits non-zero | Dynamic + static checks |
| Recovery/convergence | fresh `.7z` fail leaves `.extracting`; later retry on `.extracting` succeeds and converges | Stubbed `7zr` failure/success sequence |
| Logging | mode context, lane start/complete, fresh/recovery classification, rename-before-extract, extraction start/success/failure rc, cleanup success/failure | Log assertions |

## Run

```sh
bash -n tests/archive_unpacker/test_archive_unpacker_regression.sh
tests/archive_unpacker/test_archive_unpacker_regression.sh
```

## Real-device manual validation still required

Automated tests intentionally use tiny fixtures and stubs. On MiyooMini-family hardware, manually validate:

1. Trigger a memory-pressure extraction failure during unpacking.
2. Reboot/reinvoke and confirm `.7z.extracting` is retried.
3. Confirm eventual convergence (marker removed after success).
4. Confirm logs distinguish repeated recovery retries from lane/orchestration issues.
