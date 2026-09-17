# Contributing to Hectopolis

Thank you for helping. Before you start, read `PLAN.md` (scope, model, roadmap) and
`CLAUDE.md` (conventions). The non-negotiables are:

1. **License.** Your contribution is licensed under AGPL-3.0-or-later **with** the
   additional permission in `LICENSE-EXCEPTION.md`. Sign off every commit
   (`git commit -s`) to certify the Developer Certificate of Origin below.
2. **No code or data of incompatible origin.** Allowed dependency licenses: MIT, BSD,
   Apache-2.0, MPL-2.0, LGPL, GPL-3.0-or-later, Zlib, ISC, Unlicense, CC0. Allowed data
   licenses: CC0, CC-BY 4.0, Datenlizenz Deutschland 2.0, public law texts. Never copy from
   proprietary games, from Ökolopoly/ecopolicy materials, or from share-alike datasets.
3. **Every user-facing string** goes into both `app/lib/l10n/app_de.arb` and
   `app/lib/l10n/app_en.arb` in the same commit.
4. **Every model parameter** goes into `data/params/*.json` with a `source`, and the
   matching `docs/model/*.md` explains the formula and cites it.
5. Run `tools/check.sh` before opening a pull request.

## Guides

- **[Adding a tile type](docs/adding-a-tile-type.md)** — the six files involved, the
  sourcing convention for parameters, and the four things the analyzer will *not*
  catch (one of them a runtime crash).
- **[The model](docs/model/)** — one file per component, each with its formulas,
  its calibration and an explicit list of what it leaves out.

## Developer Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I have the right to submit
    it under the open source license indicated in the file; or
(b) The contribution is based upon previous work that, to the best of my knowledge, is
    covered under an appropriate open source license and I have the right under that
    license to submit that work with modifications, whether created in whole or in part by
    me, under the same open source license (unless I am permitted to submit under a
    different license), as indicated in the file; or
(c) The contribution was provided directly to me by some other person who certified (a),
    (b) or (c) and I have not modified it.
(d) I understand and agree that this project and the contribution are public and that a
    record of the contribution (including all personal information I submit with it,
    including my sign-off) is maintained indefinitely and may be redistributed consistent
    with this project or the open source license(s) involved.

Additionally: I agree that my contribution is licensed under the GNU AGPL v3 or later
together with the additional permission in `LICENSE-EXCEPTION.md`.
