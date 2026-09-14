# Hectopolis

A cross-platform tile-placement game about the interplay of urban habitat, ecology and
economy. Place landscape and urban tiles on a grid and watch biodiversity, air, noise,
housing, jobs, shopping, recreation, commuting, climate and the municipal budget respond.
The model is built from public, license-free sources (German and EU law, official
statistics, open scientific models); every parameter cites its source.

- Plan, model and roadmap: [`PLAN.md`](PLAN.md)
- Model documentation: [`docs/model/`](docs/model/README.md)
- Parameters: [`data/params/tiles.json`](data/params/tiles.json)
- License: [AGPL-3.0-or-later](LICENSE) with an [app-store exception](LICENSE-EXCEPTION.md)
- Play the current build: https://crispstrobe.github.io/hectopolis/ (deployed from `main` by `.github/workflows/pages.yml`)

## Layout

```
app/                      Flutter app (Android, iOS, Web, macOS, Windows, Linux)
packages/stadtbau_sim/    pure Dart, deterministic simulation core
data/params/              sourced parameter tables
docs/model/               model documentation
tools/                    checks and generators
```

## Develop

```bash
flutter pub get                      # workspace root
dart run tools/gen_params.dart       # after editing data/params/tiles.json
(cd app && flutter gen-l10n)         # after editing app/lib/l10n/*.arb
tools/check.sh                       # analyze, test, i18n lint, license audit
(cd app && flutter run -d chrome)    # or any device
```

All user-facing strings live in `app/lib/l10n/app_de.arb` and `app_en.arb`.
