# iOS release — App Store pipeline (T-403)

Hectopolis ships to the App Store from GitHub Actions:
[`.github/workflows/ios-release.yml`](../../.github/workflows/ios-release.yml)
on a `macos-latest` runner, using the shared build script
[`tools/ios/build-ios-appstore.sh`](../../tools/ios/build-ios-appstore.sh) so
that CI and a developer Mac run the *same* steps.

| | |
|---|---|
| App name (App Store) | **Hectopolis** |
| Bundle id | `com.crispstrobe.hectopolis` |
| Apple Developer team | `N9XSJ4M3GT` |
| Provisioning profile | `Hectopolis AppStore CI` (type `IOS_APP_STORE`) |
| Signing certificate | `Apple Distribution` |
| Version source | `app/pubspec.yaml` → `version: X.Y.Z+BUILD` |

The pipeline is **manual signing** end to end. It never runs
`flutter build ipa` (that forces *automatic* signing, which needs an Xcode
account no runner has) and never passes `-allowProvisioningUpdates` (on a
runner it mints a Development certificate and, to stay under Apple's
five-certificate account limit, silently **revokes the shared Apple
Distribution certificate**, breaking signing for every app on the account).

What the job does, in order:

1. `flutter config --no-enable-swift-package-manager`, `flutter pub get` (pub
   workspace root), `cd app && flutter gen-l10n`.
2. Import `DIST_CERT_P12_BASE64` into a throwaway keychain, append it to the
   user search list, set the partition list (otherwise `codesign` waits forever
   on a GUI "allow access?" prompt).
3. Install `ASC_PROFILE_BASE64` as `<UUID>.mobileprovision` into **both**
   `~/Library/MobileDevice/Provisioning Profiles/` and
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (Xcode 16+/26
   moved the directory; installing into only one gives "no profiles were
   found" for a profile that is plainly on disk).
4. `flutter build ios --release --config-only --no-codesign`, then
   `pod install`, then an **unsigned** `xcodebuild … CODE_SIGNING_ALLOWED=NO
   CODE_SIGNING_REQUIRED=NO clean archive`.
5. `xcodebuild -exportArchive` with
   [`app/ios/ExportOptions.plist`](../../app/ios/ExportOptions.plist), which
   applies the Distribution signing.
6. `xcrun altool --validate-app` (advisory), upload the `.ipa` as a workflow
   artifact, and — only for a real release — `xcrun altool --upload-package`.

Every signing and upload step is fail-loud: no `continue-on-error` anywhere, so
a green run can never again mean "uploaded nothing".

---

## 1. Secrets

Eight repo secrets. The workflow's first step fails with an explicit list if any
of them is empty, so a misconfigured repo stops in ten seconds instead of forty
minutes in.

| Secret | Value | How to create it |
|---|---|---|
| `ASC_API_KEY_P8_BASE64` | base64 of `AuthKey_<KEY_ID>.p8` | §1.1 |
| `ASC_KEY_ID` | App Store Connect API key id (`9RMU3C7422` on this account) | comes with the key |
| `ASC_ISSUER_ID` | issuer UUID (`5f618ba3-98ef-42ad-835c-fbbef6c76cf5`) | shown on the ASC Keys page |
| `ASC_APP_ID` | numeric Apple ID of the app record | §2, after the record exists |
| `ASC_TEAM_ID` | `N9XSJ4M3GT` | Apple Developer membership page |
| `DIST_CERT_P12_BASE64` | base64 of the Apple Distribution `.p12` (cert **and** private key) | §1.2 |
| `DIST_CERT_PASSWORD` | password of that `.p12` | you choose it in §1.2 |
| `ASC_PROFILE_BASE64` | base64 of the `Hectopolis AppStore CI` `.mobileprovision` | §1.3 |

Set them with:

```bash
base64 -i AuthKey_9RMU3C7422.p8 | gh secret set ASC_API_KEY_P8_BASE64
printf '9RMU3C7422' | gh secret set ASC_KEY_ID
# …and so on
```

### 1.1 App Store Connect API key — **human, one-time**

Apple only issues API keys through the browser. In App Store Connect →
Users and Access → Integrations → App Store Connect API, create a key with the
**App Manager** role, download the `.p8` **once** (it cannot be downloaded
again), and note the key id and issuer id.

This account already has one (`9RMU3C7422`); it is shared with the sibling apps
and kept outside every repository. If you have it locally, that is all you need
— skip to §1.2.

### 1.2 Apple Distribution certificate and `.p12`

Two ways, both headless. **Never** create the certificate by archiving with
`-allowProvisioningUpdates` and never use the Xcode GUI: see the warning above.

**(a) Reuse the existing shared identity** (preferred — one certificate for all
the apps on the account). On the build Mac the exportable keychain is
`~/Library/Keychains/brickwright-build.keychain-db`; it has a permissive
partition list, so export needs no prompt:

```bash
security export -k ~/Library/Keychains/brickwright-build.keychain-db \
  -t identities -f pkcs12 -P '<throwaway-password>' -o /tmp/AppleDistribution.p12
base64 -i /tmp/AppleDistribution.p12 | gh secret set DIST_CERT_P12_BASE64
printf '<throwaway-password>' | gh secret set DIST_CERT_PASSWORD
```

Do **not** reach for `login.keychain-db`: exporting a private key from it is
blocked non-interactively (`SecKeychainItemExport: User canceled the
operation`). The exported `.p12` carries both the Apple Distribution and the
Mac Installer Distribution identity; iOS signing uses the former. Verify:

```bash
security import /tmp/AppleDistribution.p12 -k /tmp/verify.keychain-db -P '<pw>'
security find-identity -v -p codesigning /tmp/verify.keychain-db   # must list "Apple Distribution"
```

**(b) Mint a new one through the API's CSR flow** (works from any machine,
including this Linux box — no keychain involved):

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr \
  -subj "/CN=Hectopolis Dist/O=CrispStrobe/C=DE"
# POST /v1/certificates {certificateType: DISTRIBUTION, csrContent: <contents of dist.csr>}
#   -> attributes.certificateContent (base64 DER)
openssl x509 -inform DER -in cert.der -out cert.pem
openssl pkcs12 -export -legacy -inkey dist.key -in cert.pem -out dist.p12 -passout pass:PW
```

`-legacy` is not optional: `security import` on the runner only reads the old
PKCS#12 encryption, and newer OpenSSL writes a format it rejects. Import the
same `.p12` into the Mac's keychain too, so local builds keep working.

Note the certificate's SHA-1 — the profile in §1.3 must be bound to *this*
certificate.

### 1.3 Bundle id and provisioning profile

The bundle id `com.crispstrobe.hectopolis` is registered through the API
(`POST /v1/bundleIds`, platform `UNIVERSAL`). The `tools/asc/` client can do it.

The profile must be an **explicit** one created through the API — Xcode-managed
profiles do not appear in `GET /v1/profiles` and cannot be downloaded:

```
POST /v1/profiles
{ "data": { "type": "profiles",
  "attributes": { "name": "Hectopolis AppStore CI", "profileType": "IOS_APP_STORE" },
  "relationships": { "bundleId":    { "data": {"type":"bundleIds","id":"<bundle id resource id>"} },
                     "certificates": { "data": [{"type":"certificates","id":"<cert id>"}] } } } }
```

The response's `attributes.profileContent` is the base64 `.mobileprovision` —
that is `ASC_PROFILE_BASE64` verbatim.

Two things must line up or `-exportArchive` fails:

* the profile's **name** must be exactly `Hectopolis AppStore CI`, because
  `ExportOptions.plist` selects it by name. The workflow asserts this and stops
  with a clear error otherwise;
* the profile's **certificate** must be the one in `DIST_CERT_P12_BASE64`
  (`profile "…" doesn't include signing certificate` otherwise). The workflow
  compares SHA-1 fingerprints and warns on a mismatch. A revoked certificate
  looks identical from the outside — always re-issue the profile after
  (re)creating a certificate.

---

## 2. What only a human can do

| Step | Who |
|---|---|
| Generate the App Store Connect API key | **Human** (browser, one-time) |
| Register the bundle id | agent / API |
| **Create the app record** — name `Hectopolis`, bundle id `com.crispstrobe.hectopolis`, primary language German | **Human** (browser; Apple blocks this via API, always) |
| Certificates, profiles, signing config, archive, export, validate, upload | agent / CI |
| Age rating questionnaire | **Human decides**, agent can submit |
| **App Privacy "nutrition label"** | **Human** (browser; Apple blocks this via API, always) |
| Store listing text, screenshots, pricing, category | agent / API |
| **Submit for Review** | **Human**, always |

After the app record exists, read its numeric id (`GET /v1/apps`) and store it
as `ASC_APP_ID`. `altool` needs it: without `--apple-id` it fails with "Cannot
determine the Apple ID from Bundle ID".

Hectopolis-specific notes for the listing:

* Export compliance is answered in the binary: `ITSAppUsesNonExemptEncryption`
  is `false` in `app/ios/Runner/Info.plist`, so no build ever sits in "Missing
  Compliance". The app uses no encryption beyond exempt platform HTTPS.
* Privacy label: the app collects nothing and has no accounts, no analytics and
  no ads. `shared_preferences` stores settings and progress on the device only;
  `url_launcher` opens the source-code and licence links from the About screen;
  `package_info_plus` reads the app's own version. Answer "Data Not Collected".
* The About screen must keep showing the AGPL-3.0-or-later notice, the section 7
  app-store exception and the third-party licences (see `LICENSE-EXCEPTION.md`)
  — that exception is what makes App Store distribution possible at all.

---

## 3. Dry run — build and sign without uploading

Do this first, and after any change to signing, the Xcode project or the
workflow.

1. GitHub → Actions → **ios-release** → *Run workflow*.
2. Leave `dry_run` at its default **true**.
3. The job builds, signs, runs `altool --validate-app` and attaches the signed
   `.ipa` as the `hectopolis-ios-ipa` artifact. It never calls `--upload-package`.

A dry run proves the whole chain — certificate, profile, project settings,
CocoaPods integration, export — without spending a build number or putting
anything in front of Apple.

On a Mac, the identical run is:

```bash
export ASC_KEY_ID=9RMU3C7422 ASC_ISSUER_ID=5f618ba3-98ef-42ad-835c-fbbef6c76cf5 ASC_APP_ID=<numeric app id>
tools/ios/build-ios-appstore.sh --no-upload
```

The script needs the Distribution identity in a keychain on the search list and
the profile already installed; it does not touch the keychain itself. **Without
`--no-upload` it uploads** — that is the only difference between a rehearsal and
a release. `--upload-only` re-uploads the `.ipa` already in
`app/build/ios/ipa/` (useful when the upload, and only the upload, failed).

---

## 4. Releasing

1. **Bump the version** in `app/pubspec.yaml` — `version: X.Y.Z+BUILD`:
   * always increment `BUILD`. Apple rejects a duplicate `CFBundleVersion`, and
     a rejected upload still burns the number.
   * increment `X.Y.Z` too whenever the previous marketing version was already
     **approved**. Bumping only the build number leaves the binary declaring the
     old `CFBundleShortVersionString`, and Apple rejects it *after* submission
     with **ITMS-90062** ("must contain a higher version than that of the
     previously approved version"). Same marketing version + higher build is
     only allowed while a version is still in review.
   * `ExportOptions.plist` sets `manageAppVersionAndBuildNumber = false`, so
     `pubspec.yaml` really is the single source of truth.
2. Commit, run `tools/check.sh`, and do a dry run (§3).
3. Tag and push:
   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```
   The tag push triggers the same job with `dry_run` off: it builds, signs,
   validates and uploads to App Store Connect.
4. Apple takes a few minutes to process the build. It then appears in
   TestFlight (internal testers) and can be attached to an App Store version.
5. Create/attach the App Store version, fill in the metadata, and — human —
   hit **Submit for Review**.

### External TestFlight and store copy

`data/store/metadata.json` is the version-controlled source for the German and
English listing and beta copy. The public privacy and support pages live in
`app/web/` and are deployed with GitHub Pages.

After a real build upload has processed, run **appstore-prepare** with
`action=submit-external` and the exact build number. It sets export compliance,
both beta localizations, review contact, per-build test notes, assigns the build
to the external **Public Beta** group and submits it to Beta App Review. The
default `audit` action is read-only.

Full App Store submission still has two deliberate browser gates: confirm
**Data Not Collected** under App Privacy and make the final Submit for Review
decision. Neither has a public App Store Connect API.

---

## 5. When it breaks

| Symptom | Cause |
|---|---|
| `error: redefinition of '<plugin symbol>'` during archive | Swift Package Manager plugin references came back into `app/ios/Runner.xcodeproj/project.pbxproj`. They are stripped on purpose (`FlutterGeneratedPluginSwiftPackage`, `XCLocalSwiftPackageReference`, `XCSwiftPackageProductDependency`); Flutter 3.44 leaves the Podfile installing the same plugins, so the sources land twice. Re-strip them and keep `flutter config --no-enable-swift-package-manager` in the job. |
| `No profiles for 'com.crispstrobe.hectopolis' were found` | Something switched signing back to automatic — almost always `flutter build ipa`. Use the unsigned `xcodebuild archive` + `-exportArchive` path. |
| `profile "Hectopolis AppStore CI" doesn't include signing certificate` | `ASC_PROFILE_BASE64` is bound to a different certificate than `DIST_CERT_P12_BASE64`, or that certificate was revoked. Re-issue the profile against the current certificate. |
| `exportArchive` succeeds but "no .ipa" | The `.ipa` is named after `PRODUCT_NAME`, not after the scheme. Both the script and the workflow glob `*.ipa`; never hard-code `Runner.ipa`. |
| `Cannot determine the Apple ID from Bundle ID` | `--apple-id` / `ASC_APP_ID` missing, or the app record does not exist yet. |
| Build stuck in "Missing Compliance" | `ITSAppUsesNonExemptEncryption` lost from `Info.plist`. |
| `codesign` hangs | The keychain partition list was not set after `security import`. |
| A distribution certificate vanished account-wide | Someone ran `-allowProvisioningUpdates`. Re-mint the certificate (§1.2) and re-issue every profile bound to the old one. |

`plutil`, `security`, `xcodebuild` and `altool` are macOS-only, so none of this
can be exercised on the Linux development box — a dry run on the runner is the
first real test.
