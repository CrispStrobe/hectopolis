<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Linux release checklist (T-404)

The desktop workflow packages the same tested Flutter release bundle in three forms:

* `hectopolis-linux.zip` is the raw bundle;
* `Hectopolis-x86_64.AppImage` is a portable, unsandboxed executable; and
* `Hectopolis-<version>-x86_64.flatpak` is a sandboxed single-file Flatpak bundle.

The Flatpak uses `org.freedesktop.Platform//25.08`. A Flatpak-aware graphical installer or
`flatpak install Hectopolis-<version>-x86_64.flatpak` fetches that runtime from Flathub when it
is not already installed. The application bundle does not duplicate the runtime.

## Sandbox permissions

The package grants Wayland with X11 fallback, shared memory, GPU rendering and networking.
Networking is required for opt-in LAN multiplayer. Flatpak exposes this as a single coarse
permission, so it cannot grant private-network access without also making internet sockets
available; Hectopolis itself still has no analytics, crash reporting or external service calls.
It receives no blanket home-directory or host-filesystem permission. Local progress remains in
Flatpak's per-application data directory.

The AppImage is useful on systems without Flatpak. It has no sandbox and inherits the launching
user's normal filesystem and network access, which is why Flatpak is the preferred Linux package
when its runtime is acceptable.

## Local package

Install Flatpak, add Flathub, and install the matching runtime and SDK:

```bash
flatpak remote-add --if-not-exists --user flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub \
  org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08
cd app && flutter build linux --release && cd ..
tools/package_flatpak.sh dist
```

The packaging script exports an OSTree repository and creates the single-file bundle. CI then
installs that exact bundle into an isolated user installation and launches the real application
under Xvfb, which checks both its import and its runtime dependencies.

A GitHub release bundle is not a Flathub submission. Flathub requires a source-based manifest,
review and ongoing runtime maintenance; prepare that separately if store discovery becomes a
priority.
