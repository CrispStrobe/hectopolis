<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Windows release checklist (T-404)

The desktop workflow produces two different Windows packages:

* `hectopolis-windows.zip` is the raw release bundle.
* `hectopolis-windows-<version>-test-signed.msix` proves the installer recipe on a
  hosted Windows runner. It is a short-lived workflow artifact, not a release file.

Do not distribute the test-signed MSIX. The `msix` development package ships its test
certificate and private key publicly. That is useful for CI validation, but it gives users
no trustworthy publisher identity. The workflow does not install or trust that certificate,
and keeps the package outside `dist/` so a tag cannot attach it to a GitHub release.

## What CI validates

`.github/workflows/desktop-release.yml` builds the release executable once, then runs
`dart run msix:create` with the declarative settings in `app/pubspec.yaml`. The job converts
Flutter's `0.1.1+5` version form to MSIX's four-part `0.1.1.5`, then checks that:

* the Windows SDK can unpack and validate the package;
* `AppxManifest.xml` and `hectopolis.exe` are present; and
* the package has a non-expired signer certificate.

Run it from **Actions → desktop-release → Run workflow**. The raw bundle and the explicitly
named test-signed MSIX are retained for 14 days. A dry run creates no GitHub release.

## Production route A: Microsoft Store

This is the preferred route because Microsoft signs the delivered package.

1. Create the product in Partner Center and reserve its name.
2. Open **Product identity** and copy the exact Package/Identity/Name, Publisher, and
   PublisherDisplayName values. They are assigned values; do not infer them from the bundle ID.
3. Supply those values to the MSIX build and enable `store: true`. Keep the package version
   monotonically increasing. For example, use a temporary local configuration or a dedicated
   release workflow rather than replacing the checked-in CI test identity without review.
4. Build the Store MSIX on Windows, upload it to the product submission, and let Partner Center
   validation and signing finish before publishing.

The Store identity values are deliberately absent from the repository until the product exists.
Once they are known, add them as repository variables or checked-in non-secret metadata and add
a Store-only packaging/upload step. A first manual submission is the sensible validation point.

## Production route B: direct distribution

For a GitHub release or private download, obtain a Windows code-signing certificate whose
subject matches the manifest Publisher. Store the PFX and password as GitHub secrets, decode the
PFX only into `$RUNNER_TEMP`, and pass `certificate_path`, `certificate_password`, and the exact
`publisher` to `msix:create`. Delete the temporary certificate in an `always()` cleanup step.

Before publishing, verify the finished file with `Get-AuthenticodeSignature`, install it on a
clean Windows machine without importing any test root, launch it, exercise LAN host/join, and
confirm that upgrading from the previous version preserves local progress.

## Local development package

After a Windows release build, the same CI-only package can be created locally:

```powershell
cd app
flutter build windows --release
dart run msix:create --version 0.1.1.5 --output-name hectopolis-test-signed
```

Because `install_certificate: false` is checked in, this does not modify the local trusted-root
store. Installation requires an explicit development trust decision and must never be presented
as the production installation path.
