# Third-party notices

This file is the inventory behind [NOTICE](NOTICE): what this project ships, what it modifies on
your machine, and what it only downloads. [LICENSE](LICENSE) covers our own code.

Three things are separated on purpose, because the obligations differ:

- **Shipped**: built into the app bundle or installed by it. We convey these, so their licenses
  apply to our distribution.
- **Modified in place**: the Wine tree you installed is patched on your disk at install time.
  We never convey a patched Wine binary.
- **Downloaded**: fetched by you or by the app from the publisher. Nothing is redistributed.

## 1. Our own code

GNU GPL v3. Full text in [LICENSE](LICENSE). Source: this repository.

`app/`, `dylib/`, `ntdll-patch/`, `overlay-shim/`, `helpers/`, and `steam-shim/` except the Valve
work noted below.

## 2. Shipped

| component | what it is | license | source | text |
|---|---|---|---|---|
| lsteamclient | macOS port of Valve's `lsteamclient` from Proton 11.0 | Steamworks SDK License | <https://github.com/ValveSoftware/Proton/tree/proton_11.0/lsteamclient> | [LICENSE.lsteamclient](LICENSE.lsteamclient) |
| steam-shim | port of `steam_helper` from Proton 9.0 | BSD-3-Clause | <https://github.com/ValveSoftware/Proton/tree/proton_9.0> | [LICENSE.steam-shim](LICENSE.steam-shim) |
| JsonCpp | `steam-shim/jsoncpp.cpp`, `steam-shim/json/*.h` | public domain / MIT | <https://github.com/open-source-parsers/jsoncpp> | header in file |
| cJSON | `vendor/cJSON.c`, `vendor/cJSON.h` | MIT | <https://github.com/DaveGamble/cJSON> | header in file |
| Sparkle 2.10.0 | update framework embedded in the app bundle | MIT | <https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0> | <https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE> |
| detour payloads | `Resources/detour2*.bin`, `detour32*.bin`, our code, built by `ntdll-patch/build.sh` and `build32.sh` | GPL-3.0 | `ntdll-patch/` | [LICENSE](LICENSE) |
| fonts | sources in `fonts/`, built into the runtime fonts | SIL OFL 1.1 (Liberation, Noto, Source Han Sans); UmeFont license (Ume) | <https://github.com/ValveSoftware/Proton> | per family in `fonts/*/`, build files in [LICENSE.fonts](LICENSE.fonts) |

`steam-shim` compiles against Steamworks SDK headers (Steamworks SDK License, only while in use),
OpenVR headers (BSD-3-Clause, <https://github.com/ValveSoftware/openvr>), and Wine headers
(LGPL-2.1-or-later). Those are build-time dependencies, not conveyed code.

## 3. Modified in place, not conveyed

**Wine**: LGPL-2.1-or-later, <https://gitlab.winehq.org/wine/wine>.

The patcher rewrites one hook site and writes a payload into a code cave in the `ntdll.dll` of the
Wine copy you installed, in your own runner directory. We ship no Wine binary and no patched Wine
binary: the bytes come from your copy.

Every input to that patch is published here so the modified library can be rebuilt or debugged:
`ntdll-patch/shim.S`, `shim32.S`, `detour.c`, `detour32.c`, `resolve.py`, and the resolver output
recorded per build in [SupportedRunner.swift](app/Sources/NotProtonApp/Model/SupportedRunner.swift)
and [NtdllPatcher.swift](app/Sources/NotProtonApp/Model/NtdllPatcher.swift).

If you redistribute a patched runner, the LGPL applies to that tree and you are the one conveying
it, including the source-obligation that comes with a modified LGPL library.

**Engine builds this project pins**: WineHQ builds by Gcenx, LGPL-2.1-or-later,
<https://github.com/Gcenx/macOS_Wine_builds>, and CrossOver 26.3.0 compiled from CodeWeavers' open
source tree by the Barrel project, LGPL-2.1-or-later, <https://github.com/MrTuNNe/Barrel>. You
download and install these yourself; the hashes this project verifies are listed in
`SupportedRunner.swift`.

## 4. Downloaded, never redistributed

| what | license or terms | where from |
|---|---|---|
| Steam client packages | Steam Subscriber Agreement | `valve-packages.manifest` (steampowered.com, steamstatic.com, steamcdn-a.akamaihd.net) |
| wine-mono, wine-gecko | under their own licenses | <https://dl.winehq.org/wine/> |
| winetricks | LGPL-2.1-or-later | <https://github.com/Winetricks/winetricks> |
| DXVK (macOS build) | Zlib | <https://github.com/Gcenx/DXVK-macOS> |
| Barrel Wine (CrossOver 26.3.0 sources) | LGPL-2.1-or-later | <https://github.com/MrTuNNe/Barrel/releases> |
| DXMT | LGPL-2.1 | <https://github.com/3Shain/dxmt> |
| CrossOver (retail or Preview) | proprietary, licensed by you | <https://www.codeweavers.com> |
| FEX (x86 translation, CrossOver builds only) | MIT | <https://github.com/FEX-Emu/FEX> |
| Apple Game Porting Toolkit / D3DMetal | Apple license, your download | <https://developer.apple.com/games/game-porting-toolkit/> |

None of these are bundled. CrossOver and the Game Porting Toolkit in particular are proprietary and
are not redistributable by this project; pointing the app at a copy you own or downloaded is the
only way they are used. DXVK and DXMT are free software; if you install either, its license travels
with the download, not with this repository.

## 5. What this project's own choices guarantee

- **GPL-3.0 (our code)**: complete source in this repository, and every release builds from it.
- **LGPL-2.1 (Wine)**: no Wine binary is conveyed. The patch is applied to your copy, on your
  machine, and all patch inputs are published so the result is reproducible.
- **Steamworks SDK License (lsteamclient)**: notices retained in `LICENSE.lsteamclient`; the port
  is distributed under the same terms Valve granted the Proton project.
- **BSD-3-Clause (steam-shim)**: copyright notice and conditions retained, no endorsement implied.
- **MIT (Sparkle, cJSON, JsonCpp)**: notice retained with each component.
- **OFL (fonts)**: each family's license stays with it in `fonts/`.

If something here is missing or misattributed, please open an issue.
