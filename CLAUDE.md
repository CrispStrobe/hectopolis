# Hectopolis — agent brief

Read `PLAN.md` first. It holds the vision, constraints, architecture, the simulation model
and the task roadmap. Work through roadmap tasks in order unless told otherwise; mark them
done in `PLAN.md` with a one-line note.

## Environment on this machine

```bash
export PATH="/mnt/volume1/toolchain/flutter/bin:$PATH"
export PUB_CACHE=/mnt/volume1/pub-cache
```

- Flutter 3.44.1 stable, Dart 3.12.1. No Android SDK, no Xcode here: build and test **web**
  and pure Dart. **Desktop Linux builds work on this box**: gtk+-3.0 3.24.41 dev headers,
  cmake, ninja and clang are all present (checked 2026-09-16). `xvfb-run`/`Xvfb` and
  ImageMagick's `import` are there too, so a desktop build can be launched and screenshotted
  headlessly.
- `/mnt/volume1` is nearly full. **Large output goes to `/mnt/storage/code/stadtbau`**
  (CIFS mount): `app/build/` is a symlink there, raw datasets live in
  `/mnt/storage/code/stadtbau/data`. Never put datasets or build output in the repo.
- Scratch files go to the session scratchpad, not the repo.

## Non-negotiables

1. **License**: AGPL-3.0-or-later + our section 7 app-store exception. Every dependency
   must be on the allow-list in `PLAN.md` §2. Run `tools/license_audit.sh` after adding one.
   Never copy code from GPL-2-only, proprietary or unlicensed sources. Ökolopoly/ecopolicy,
   SimCity, Cities: Skylines: concepts only, never names, art, text, tables.
2. **i18n**: every user-facing string in `app/lib/l10n/app_de.arb` and `app_en.arb`, both
   languages in the same commit. Run `tools/i18n_lint.dart`.
3. **Model realism**: every numeric parameter lives in `data/params/*.json` with a `source`.
   Model changes come with a matching update in `docs/model/*.md`.
4. **Sim is pure Dart** (`packages/stadtbau_sim`), deterministic, no Flutter imports.
5. Add `// SPDX-License-Identifier: AGPL-3.0-or-later` as the first line of every source file.

## Commands

```bash
tools/check.sh                      # analyze + test + i18n lint + license audit
tools/check.sh --list               # the stage names
tools/check.sh test-sim i18n        # only those stages — use this when the box is loaded,
                                    # a full run needs three analysis servers and three test
                                    # runners at once and gets OOM-killed with no output
flutter test                        # in app/ or packages/stadtbau_sim/
cd packages/stadtbau_sim && \
  dart run tool/learning_audit.dart  # mission copy in DE+EN, and whether the
                                    # teaching content is actually reachable
flutter build web --release         # writes to app/build/web -> /mnt/storage/...
```

## Style

- Dart: `flutter_lints`, strict analysis, small files, no `dynamic`.
- Commit messages: imperative, reference the task id (`T-105: noise field line-source decay`).
- Documentation and code in English; UI strings in DE and EN via ARB.
