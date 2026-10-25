# NotNotProton

NotNotProton is a modified version of [NotProton](https://github.com/NotProtonNot/NotProton) by
NotProtonNot, modified on 25 October 2026. It no longer requires CrossOver: it runs on free
Wine builds, and it is renamed. It is released under GPLv3, like the original; see LICENSE and NOTICE.

NotNotProton enables the Steam Play experience from Linux Steam in the macOS Steam client.

This is done by forcibly enabling the Steam Play functionality in macOS Steam (which is
present and inert) as well as by porting some components of Valve's Proton to macOS.

This tool is intended to be used with the current stable and beta Steam Clients (the October 13th
2026 update, web UI build 1791918634, and later) paired with **CrossOver 26.3 or CrossOver [Preview](https://www.codeweavers.com/preview)
20260821 / 20261006 / 20261015**, or with a free build: WineHQ 11.9 through 11.18, devel or staging,
or CrossOver 26.3 compiled from CodeWeavers' open source tree.

**NTFS file systems/drivers are not currently supported.**

**This fork runs on free software.** No CrossOver license is involved: the Status pane offers every build this fork pins and unpacks the one you pick into `~/Applications`, where NotNotProton treats it like a CrossOver copy. That is [Gcenx](https://github.com/Gcenx/macOS_Wine_builds/releases)'s WineHQ 11.16, 11.17 and 11.18 in both devel and staging, WineHQ Staging 11.9, and CrossOver 26.3 compiled from CodeWeavers' open source tree by the [Barrel](https://github.com/MrTuNNe/Barrel) project; the older pins, 11.15 and its staging pair among them, sit under *Older builds*. Each is hash pinned on its loader and on both arches of its ntdll, and they appear in Steam's per-game Compatibility list as `WineHQ 11.18`, `WineHQ Staging 11.18`, `CrossOver 26.3 (FOSS)` and so on, so the same game can be given a different Wine, the way Proton builds are chosen per game.

These builds are x86_64, so they run under Rosetta; the FEX tools remain CrossOver only. The bridge is compiled against WineHQ 11.15, so 11.15 and 11.15 staging share its ABI; the other builds are on either side of that one and should be treated as experimental until they have been played on.

**Graphics backends are not bundled.** A Wine build carries no Direct3D translation layer of its own, so DX9-11 falls back to Wine's own wined3d through OpenGL and DX12 goes through vkd3d and MoltenVK. A game's properties page in Steam lists the DX layers found in `~/Library/Application Support/notproton/plugins/` under Developer, where they are switched per prefix. The Status pane fetches DXVK and DXMT into that folder; D3DMetal is Apple's, so it comes from your own Game Porting Toolkit download.

Both the FEX and the Rosetta versions are supported. I recommend using the FEX version of the 
Preview 20261006, as it includes both the FEX version as well as the Rosetta one. 

I further recommend going into Steam Settings - Compatibility and selecting the Rosetta version as your default compatibility tool. You can select FEX on a per game basis by right clicking a game in Steam, going into Properties - Compatibility and selecting FEX there.

If a game has a native macOS version as well as a Windows one, Steam will download the macOS version. To override this behavior, right click on the game, select Properties, select Compatibility. Enable 'Force the use of a specific Steam Play compatibility tool'. Select whichever compatibility tool you want to use, a CrossOver build or one of the WineHQ builds. That will make Steam download the Windows version. Unchecking the 'Force the use...' box or selecting 'No Compatibility Tool' in the drop down list will revert to the macOS version of the game, with the specifics there varying based on your Steam version.

**Valve Anti-Cheat is not supported.** Proton itself does not support VAC in Valve titles; Valve ships native Linux ports instead. VAC titles will launch in Insecure Mode and will not allow matchmaking. 

Please read NOTICE and THIRD_PARTY_NOTICES.md for license information.

Please open issue reports with any issues. PRs are welcome and encouraged.

NotProton, by [NotProtonNot](https://github.com/NotProtonNot), is the basis for this fork: the app,
the dylib and the bridge are his work, and the change here is that CrossOver is no longer required.
He blocked me on Reddit, which is why this fork exists at all: without the block there would be no
NotNotProton. So, thanks for the code, and thanks for the block.

There are many other people who worked on similar ideas, similar projects. NotProton was not based
on their work, but they still deserve thanks:

[Nat Brown](https://github.com/natbro) made [Kaon](https://github.com/natbro/kaon), which is similar in goals to NotProton.

mont127's [Neutron](https://github.com/mont127/Neutron) is also a similar idea, but implemented differently. 

[Gio](https://github.com/giodotblue) was working enabling Steam Play inside of Steam on macOS prior to the release of NotProton itself. 
I would have done things differently had I been aware of that. 

Thanks to everyone who has positively contributed to macOS gaming. 

Developer Notes:

As far as the source structure goes, the macOS app itself is located in the ```app``` folder. The core logic is in ```dylib```.
```lsteamclient``` is a macOS port of Valve's lsteamclient. ```steam-shim```is a port of Valve's
steam-helper from Proton 9.0. ntdll-patch patches each runner the app
makes/places in the ```~/Library/Application Support/notproton/runners/``` folder, whether it is a
CrossOver build or a WineHQ one, so that
lsteamclient is loaded.
