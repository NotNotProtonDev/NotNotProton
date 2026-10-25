// Allow list of CrossOver builds the runner clones from. The ntdll hook sites
// are hardcoded RVAs, so a build not pinned here would be patched at the wrong
// offsets. New builds go in after running ntdll-patch/resolve.py and pinning
// the hashes.

import Foundation

enum WineArch: String, Sendable, CaseIterable {
    case x86_64Windows = "x86_64-windows"
    case i386Windows = "i386-windows"
    case aarch64Windows = "aarch64-windows"
}

struct RunnerBuild: Sendable, Equatable, Identifiable {
    // CFBundleVersion, which also names the directory under runners/ and keys
    // the ntdll hash tables. Changing it orphans an installed runner.
    let bundleVersion: String

    // CFBundleShortVersionString. CrossOver inverts the usual pair and sets this
    // to the build date, so it is the string the download page shows. Display
    // only, never identity.
    let releaseVersion: String

    let flavor: String?

    let loaderSHA256: String

    let cleanNtdll: [WineArch: String]
    let patchedNtdll: [WineArch: String]

    var tools: [CompatTool] = []

    var rebuilds: [RunnerRebuild] = []

    var id: String { flavor.map { "\(bundleVersion)-\($0)" } ?? bundleVersion }

    func matching(loaderSHA256 hash: String) -> RunnerBuild? {
        if hash == loaderSHA256 { return self }
        guard let rebuild = rebuilds.first(where: { $0.loaderSHA256 == hash }) else { return nil }
        return RunnerBuild(
            bundleVersion: bundleVersion, releaseVersion: releaseVersion, flavor: flavor,
            loaderSHA256: rebuild.loaderSHA256, cleanNtdll: rebuild.cleanNtdll,
            patchedNtdll: rebuild.patchedNtdll, tools: tools, rebuilds: rebuilds
        )
    }

    var flavorName: String { flavor?.uppercased() ?? "Rosetta" }

    var displayVersion: String { "\(releaseVersion) \(flavorName)" }

    var productName: String { bundleVersion.hasPrefix("winehq-") ? "WineHQ" : "CrossOver" }
}

// The version of CrossOver offered in China has different hashes but is identical in the ways that matter
struct RunnerRebuild: Sendable, Equatable {
    let loaderSHA256: String
    let cleanNtdll: [WineArch: String]
    let patchedNtdll: [WineArch: String]
}

struct CompatTool: Sendable, Hashable, Identifiable {
    enum Flavor: String, Sendable, CaseIterable {
        case rosetta
        case fex

        var name: String { self == .fex ? "FEX" : "Rosetta" }
        var unixDir: String { self == .fex ? "aarch64-unix" : "x86_64-unix" }

        // CrossOver's FEX build needs Tahoe. Its Rosetta tool runs on Sequoia.
        static let fexAvailable = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
    }

    let name: String
    let flavor: Flavor
    let display: String

    var id: String { name }

    var prefixArch: PrefixArch { flavor == .fex ? .arm64 : .x86_64 }
}

struct InstalledTool: Sendable, Hashable, Identifiable {
    let tool: CompatTool
    let build: String

    var id: String { tool.name }
    var name: String { tool.name }
    var display: String { tool.display }
}

enum SupportedRunners {

    // First entry is what windows-only games get when Steam has no mapping.
    static let toolPreference = [
        legacyToolName, "notproton-winehq", "notproton-winehq-staging", "notproton-winehq-11.18",
        "notproton-winehq-staging-11.18", "notproton-winehq-11.17", "notproton-winehq-staging-11.17",
        "notproton-winehq-11.16", "notproton-winehq-staging-11.16", "notproton-winehq-staging-11.9",
        "notproton-fex", "notproton-fex-rosetta", "notproton-preview",
        "notproton-fex-41069", "notproton-fex-rosetta-41069", "notproton-preview-41069",
        "notproton-fex-41073", "notproton-fex-rosetta-41073", "notproton-preview-41073", "notproton-26.3",
    ]

    static let legacyToolName = "notproton"

    // The only builds that can own the 'notproton' tool name.
    static let legacyHolders = ["27.0.0.40921-fex", "27.0.0.40921", "27.0.0.41069-fex", "27.0.0.41069"]

    enum LegacyHolder: Equatable, Sendable {
        case build(String)
        case nobody
    }

    static func tools(
        for builds: [RunnerBuild], legacy: LegacyHolder = .nobody,
        fexAvailable: Bool = CompatTool.Flavor.fexAvailable, keeping kept: Set<String> = []
    ) -> [InstalledTool] {
        let installed = Set(builds.map(\.id))
        let holder: String? = switch legacy {
        case .build(let id): id
        case .nobody: nil
        }
        let served: [InstalledTool] = all.filter { installed.contains($0.id) }.flatMap {
            (build: RunnerBuild) -> [InstalledTool] in
            build.tools.enumerated().map { (index: Int, tool: CompatTool) -> InstalledTool in
                let name = build.id == holder && index == 0 ? legacyToolName : tool.name
                return InstalledTool(
                    tool: CompatTool(name: name, flavor: tool.flavor, display: tool.display), build: build.id
                )
            }
        }.filter { $0.tool.flavor != CompatTool.Flavor.fex || fexAvailable || kept.contains($0.name) }
        func rank(_ tool: InstalledTool) -> Int {
            toolPreference.firstIndex(of: tool.name) ?? toolPreference.count
        }
        return served.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static let all: [RunnerBuild] = [
        // The WineHQ build the bridge components are compiled against, see
        // bridge/setup-wine-tree.sh.
        RunnerBuild(
            bundleVersion: "winehq-11.15",
            releaseVersion: "11.15",
            flavor: nil,
            loaderSHA256: "8aa25e55f28a0634a7df04c02dd719d4bc20de645cf42b9ba7d0e3b7d8f66a80",
            cleanNtdll: [
                .x86_64Windows: "682181234a55f5b7eed5b2ffa691fbdef1b488734337ef67ea7b5ce17adf43a2",
                .i386Windows: "49396e7ad804a5345b1b968d02fdb6697ddbb7428e61e20e62806c50c37589d1",
            ],
            patchedNtdll: [
                .x86_64Windows: "08a825e8236e79c909fae3934ca5e8a195a344d06f8affb6e13cdf1bd9ffa783",
                .i386Windows: "88f9a1d16dd7127100eab902156390ec2a5ec67770cfddd3fd3f1237c9965309",
            ],
            tools: [
                CompatTool(name: "notproton-winehq", flavor: .rosetta, display: "WineHQ 11.15"),
            ]
        ),
        // The staging patchset makes some games behave differently, so it is offered beside
        // the plain build rather than replacing it.
        RunnerBuild(
            bundleVersion: "winehq-staging-11.15",
            releaseVersion: "11.15",
            flavor: nil,
            loaderSHA256: "11e31e52cab7be161463bdbcccfc4ab28779efd11f91c025c8ea7fa415c52d08",
            cleanNtdll: [
                .x86_64Windows: "96d3f673061240ef6e4917c7ed8b17fbdddea1cdfc3676518718f671a41ca159",
                .i386Windows: "576b62f87941d676f7c0bc40759b3657e5251602c74b46d6c97dd15574163a14",
            ],
            patchedNtdll: [
                .x86_64Windows: "52d55201940536b6701da181c1d41a6c7fac216ad6895221b6c862ce25c9abe4",
                .i386Windows: "47014cb52aff8aead47698f622f660c7ea01ba99cd8511cb74902c4000149875",
            ],
            tools: [
                CompatTool(name: "notproton-winehq-staging", flavor: .rosetta, display: "WineHQ Staging 11.15"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "winehq-11.18",
            releaseVersion: "11.18",
            flavor: nil,
            loaderSHA256: "52bde7105a2e501a23125cbddc92bf7c5920bccba29215402d272b9c028a14d3",
            cleanNtdll: [
                .x86_64Windows: "958922348a508d88c8bfb7e61380e1970a09c6c19a254ce06c8a2deb17238c6f",
                .i386Windows: "cb21df042349cdc79f69db7d3d5633526ce9650dd454224f9c36559055871593",
            ],
            patchedNtdll: [
                .x86_64Windows: "0cc01b531f08efabdb2714eb67afa10f46ec289ef0b8054e4958e977881a313e",
                .i386Windows: "d554add44778b93e7edb9115346f92c3ab96b3878b078163c5b08967db3f18e8",
            ],
            tools: [
                CompatTool(name: "notproton-winehq-11.18", flavor: .rosetta, display: "WineHQ 11.18"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "winehq-staging-11.18",
            releaseVersion: "11.18",
            flavor: nil,
            loaderSHA256: "6a3bfec3d4e3e96c37474f8288594b8ddc600ca4afd697d82d9d517a899eaae2",
            cleanNtdll: [
                .x86_64Windows: "f3d2dbc3764d3e37eeeeeac923d09c47745e8c7b190324e940d551e0b733b1ab",
                .i386Windows: "57b278521f341e6e2280e5dafd3095c6f39b1857fb18ec3d9a610a53a42e46fe",
            ],
            patchedNtdll: [
                .x86_64Windows: "b6eb0b5ba4d489542a0e34b836e761a7843f60f22455b211a58696f3a55ee51a",
                .i386Windows: "bc4dc54e969022a895cc4702b8e6c3a86b6e795c09d97bf7841b07b52b2965d5",
            ],
            tools: [
                CompatTool(name: "notproton-winehq-staging-11.18", flavor: .rosetta, display: "WineHQ Staging 11.18"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "winehq-11.17",
            releaseVersion: "11.17",
            flavor: nil,
            loaderSHA256: "51d9ba9d2cb4368b688bd2a434baeae23ac155aa4c66bcb2d03a3d032d90d522",
            cleanNtdll: [
                .x86_64Windows: "3ac13a12c10b98564d34f70bcf2974d45c93b746edafe3c6f9f5e5b5b730b59a",
                .i386Windows: "fa07753bb65d179be41e269267e856b40173b3f8c0d720be0d6e4e19ad525aac",
            ],
            patchedNtdll: [
                .x86_64Windows: "e8dd5003f969207fea5ba85a886d9b02ad0ceaf49ee8570308bb6f061361cf43",
                .i386Windows: "a3a759a7e9b57b81f8d953a1dd54a4b8b8471b913c9abe129b5af380b2af23d2",
            ],
            tools: [
                CompatTool(name: "notproton-winehq-11.17", flavor: .rosetta, display: "WineHQ 11.17"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "winehq-staging-11.17",
            releaseVersion: "11.17",
            flavor: nil,
            loaderSHA256: "517531c5183749f6db57030fd1d55c2f684ef1db31b67bb717cea06680c2c132",
            cleanNtdll: [
                .x86_64Windows: "d4c82dcb553e45b506629cb6176147878ffe2ca600066ac105b1d278f9cf51c2",
                .i386Windows: "9c104e98ff2745a04b8ffc9d4381b98d96a8147f4ef27be4389d935f14ba97e4",
            ],
            patchedNtdll: [
                .x86_64Windows: "2935b9755504d902a7dc3a79ce51e193477a63d7824356e8c83a25936c42571c",
                .i386Windows: "5a08f433a815b8cca3268b287b1db916acdf2d209d4211ad003368aba643e3f2",
            ],
            tools: [
                CompatTool(
                    name: "notproton-winehq-staging-11.17", flavor: .rosetta, display: "WineHQ Staging 11.17"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "winehq-11.16",
            releaseVersion: "11.16",
            flavor: nil,
            loaderSHA256: "dbe30d3bec9813df8fd0f3cfcffefa1002fc253ddad5368e64bdd49a36c5731c",
            cleanNtdll: [
                .x86_64Windows: "9d22b10563da76a3576be303c1b7e2c5e370b1585fa220020ffac5a0287fe66b",
                .i386Windows: "f9bc63caffebfc4d15a500a19134d30f22faab127f7b669e40100718d5e4aa95",
            ],
            patchedNtdll: [
                .x86_64Windows: "457825503f1758cc7edadddba087592335aa8af1b5fab6c9cda0ce2bd0d7bd74",
                .i386Windows: "896572c57bf4ee07e31b5d93714b189bc2f63e905b7d0ab8b41090ed45b0758f",
            ],
            tools: [
                CompatTool(name: "notproton-winehq-11.16", flavor: .rosetta, display: "WineHQ 11.16"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "winehq-staging-11.16",
            releaseVersion: "11.16",
            flavor: nil,
            loaderSHA256: "88c015f4db73798bfadd1b890d6f0f4d2931ef0cb2c8e7be795c765a818ddc1e",
            cleanNtdll: [
                .x86_64Windows: "dbd0bd11fcb942c274fe4785ed60c142111c8dd67918a685bfc5661dd829f1bb",
                .i386Windows: "8f044975346a4f08344250995da0e81540672f012580106e88f561169d438609",
            ],
            patchedNtdll: [
                .x86_64Windows: "e319a7960246b0daa09213a946a4a3e17b52c0f779e7f6310d88118cb3b94dbe",
                .i386Windows: "1ccf822ef645c30a2e6ffcf87b8668d8725505383bcd0765d65aec80d49138f0",
            ],
            tools: [
                CompatTool(
                    name: "notproton-winehq-staging-11.16", flavor: .rosetta, display: "WineHQ Staging 11.16"),
            ]
        ),
        // The oldest build offered, for games that regressed in a later Wine.
        RunnerBuild(
            bundleVersion: "winehq-staging-11.9",
            releaseVersion: "11.9",
            flavor: nil,
            loaderSHA256: "fee931b8973c4e0949e5366d38e6ed40628984e5e3014d73202f04044b380fab",
            cleanNtdll: [
                .x86_64Windows: "29013c4c110c7e910660c0a90bb7757f5783d4d556ae1c91ae85f46b20a10faa",
                .i386Windows: "96e1ebb5a3427bd2d493c17e460a4f006778c8b59dcc47b076da98e519b86aa0",
            ],
            patchedNtdll: [
                .x86_64Windows: "ed4420a54405ce3dbc85193d4156c4a3a6922f5ea76897560ca2a14e36338029",
                .i386Windows: "9488cec5bb4d4e8b30dc62e790c3c0094fefb40ce2adef13ddc9b2912f98f8a3",
            ],
            tools: [
                CompatTool(name: "notproton-winehq-staging-11.9", flavor: .rosetta, display: "WineHQ Staging 11.9"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "26.3.0.39832",
            releaseVersion: "26.3",
            flavor: nil,
            loaderSHA256: "b5edb0444b5b25ba0aa5091be1cba11680130895c338cc8044101bce98802a63",
            cleanNtdll: [
                .x86_64Windows: "6dff64c00793ce92124f1316985c63783f539f26b392975c70f57637458d2387",
                .i386Windows: "2c60ee6b00dd13b7f6cb11017778a041ba6a321eaea194f1fa0dca7eab8403e2",
            ],
            patchedNtdll: [
                .x86_64Windows: "c0e21a9a5250f0a97c08d3c3e1798566255387213e2553b1e555264fb9ded97e",
                .i386Windows: "e641d7b2e81ee13877823494679ba2d87e0d61b8a87e8a1ce92b4fe73631ae74",
            ],
            tools: [
                CompatTool(name: "notproton-26.3", flavor: .rosetta, display: "CrossOver 26.3"),
            ],
            rebuilds: [
                // crossoverchina.com
                RunnerRebuild(
                    loaderSHA256: "35aeb1a75a48f3b053dbf2395deac33c530a0b0b7db0bc6357362348af9514ce",
                    cleanNtdll: [
                        .x86_64Windows: "1c4799bb3769ba1392c2298e4904ce0b080f040940b2a273f4eaa0906b231a93",
                        .i386Windows: "21e7d0a6d6868f1853489f5a9798e706509a20a65ee370f50b37ab7b1cdcaae3",
                    ],
                    patchedNtdll: [
                        .x86_64Windows: "3725117cc103acd9d2713535e41733563f340e27604e1abdea5afbdc2c2be65a",
                        .i386Windows: "6d9ef05089fea07d1f4cbebe27df1f9a92dbc8eb245033db9f5e40a943175d5b",
                    ]
                ),
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.40921",
            releaseVersion: "20260821",
            flavor: nil,
            loaderSHA256: "b59d5fdccb62d425230a4e4d157c50c25b63ff586832c60cc5b12b4d6053ab80",
            cleanNtdll: [
                .x86_64Windows: "04c7200b6645decb7c2d1ba6b0195abc9af83257072558d11aa72cc067ac3377",
                .i386Windows: "94cc7c14c1e9dcf58ef501015c115f8405c73b2a65cefe31faa5d9e47f36e58b",
            ],
            patchedNtdll: [
                .x86_64Windows: "b6a98622fb8f7e6a998bc038f442b17d257da3df5e9e135f0c35f7bbc46ea5d6",
                .i386Windows: "25bfde1f50ee96485763968ef10b9d9ad35e38214232f17ebdc009b098af44a0",
            ],
            tools: [
                CompatTool(name: "notproton-preview", flavor: .rosetta, display: "CrossOver 2026 08 21-X86 - Rosetta"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.40921",
            releaseVersion: "20260821",
            flavor: "fex",
            loaderSHA256: "7a6ea337c9caf2217454bec9537371e5d8ca302406bbed40b65316c1a636c4ab",
            cleanNtdll: [
                .x86_64Windows: "f4fa556a3dc20f6e966a803f5de554359227a61a24cd5b5a2ad88a427ceeec58",
                .i386Windows: "09474795d6f306163cebab6429819999fcff50e07dbc4b067a90ec4f74a3a7d7",
                .aarch64Windows: "7823d71fbce6c9947163bf8b96beb299eabb02878245bcaf6759f2a22e81f071",
            ],
            patchedNtdll: [
                .x86_64Windows: "fa8cd8fe7c4c19effade92d55b00fa946b630ab13cbb6721076848238c1dcf6a",
                .i386Windows: "e799ea02418294588ee353a90b967358be316a3044ff9515b28aa1ce07e63981",
                .aarch64Windows: "f40810193a5ef2520774288f354a8604f5ba91828315f643b3ee6688b873dc3f",
            ],
            tools: [
                CompatTool(name: "notproton-fex", flavor: .fex, display: "CrossOver 2026 08 21-ARM64 - FEX"),
                CompatTool(name: "notproton-fex-rosetta", flavor: .rosetta, display: "CrossOver 2026 08 21-ARM64 - Rosetta"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.41069",
            releaseVersion: "20261006",
            flavor: nil,
            loaderSHA256: "8286bfd0c6d2ae337e11784926d371a9f7ed7e8da870bd2f435c2bce8eb3c148",
            cleanNtdll: [
                .x86_64Windows: "5b388fd48823e905616432fba627eb48f68dc14383963bb213d55db3f691b1b9",
                .i386Windows: "e7da2a712870222942ef27a80b3bf4fa70fc8545dd1a64bdc7f2fa24a38debc3",
            ],
            patchedNtdll: [
                .x86_64Windows: "9569625387cf179d306b004c556273e2ec15811b2cfd51f21d078e2a0aa06f7f",
                .i386Windows: "0d8e3ebb57b3173f675eef5e3a0950052c592efa10a7a10193b0beb811b55ea5",
            ],
            tools: [
                CompatTool(name: "notproton-preview-41069", flavor: .rosetta, display: "CrossOver 2026 10 06-X86 - Rosetta"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.41069",
            releaseVersion: "20261006",
            flavor: "fex",
            loaderSHA256: "ef2b9a0ad185d8caa2960a97c135a75b8b85ca62425599e35cf672f787fba64c",
            cleanNtdll: [
                .x86_64Windows: "1b02dcf6ad9d9490870f1127a421c4c0d1471c65ec1574e1e84c05d69801ac7e",
                .i386Windows: "66b1a244a611795c59a93a9491d17f36c98cd8db9be495004a37864e0e5ed4a5",
                .aarch64Windows: "77ca83b2e1a3a1242f9d2d8868328262b2bcfc3f59bacf8b9389ea7e797ea852",
            ],
            patchedNtdll: [
                .x86_64Windows: "7548abd874656f6a6455e7fac659020ed755d92f4e1929a33097bbde964699f5",
                .i386Windows: "e16b0199db721a08201b1512476b9eff255624d2faf3696fa57ff74b1a54be5c",
                .aarch64Windows: "7623c0b33350f511b431d39c7ec0c0d4f5def4183acef0eee5d4a5c694898956",
            ],
            tools: [
                CompatTool(name: "notproton-fex-41069", flavor: .fex, display: "CrossOver 2026 10 06-ARM64 - FEX"),
                CompatTool(name: "notproton-fex-rosetta-41069", flavor: .rosetta, display: "CrossOver 2026 10 06-ARM64 - Rosetta"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.41073",
            releaseVersion: "20261015",
            flavor: nil,
            loaderSHA256: "57144ccad16e75a171d48ea4b20974183e76c1cd5f5022bfc4b8917016b126b5",
            cleanNtdll: [
                .x86_64Windows: "f489347e59d4e8b43c2b0d2abbff9ee31e2059d45fd75fc04e2f4c0d8b04464a",
                .i386Windows: "5249b95eea6df765257b2e5212831f511d8f66134abe3c231b8e73d8f5b4707e",
            ],
            patchedNtdll: [
                .x86_64Windows: "901bff9138707d90efecc592bd9bd3062075a350add4b3a283b089c1da635a61",
                .i386Windows: "7d3df0ee9dd61693293ba74a8d2c588b4dce26fb7f7a78c0c5ed5bdc58869e14",
            ],
            tools: [
                CompatTool(name: "notproton-preview-41073", flavor: .rosetta, display: "CrossOver 2026 10 15-X86 - Rosetta"),
            ]
        ),
        RunnerBuild(
            bundleVersion: "27.0.0.41073",
            releaseVersion: "20261015",
            flavor: "fex",
            loaderSHA256: "f4cedebfb30efc1e91e46ee25296abeb526fe7d814041d7cc6ca693bd4b8cb7b",
            cleanNtdll: [
                .x86_64Windows: "3d24426735defd222fd9518b094b738dc1c12afd13efc41a855013ed0f825129",
                .i386Windows: "3ee764335e50709285361e2542731385f0b06e593a76aa84a3c328c278164c4f",
                .aarch64Windows: "a6678f9d0818e1cdb325e1ce8a07a540433f544b6f756c52a6ab1cfd3f632408",
            ],
            patchedNtdll: [
                .x86_64Windows: "2b47ed8c19d1d15d0f82519d39d64bf34113b285c4ada325bb64c5e587326d33",
                .i386Windows: "3f4b0d9589c1f374e3c2fd135263f2bf3c8300e09dd010fd778936dd71e894ad",
                .aarch64Windows: "2efb13f3303adc2c8ee61b93e027e4e94730a2e6b0162c7e6aebd4104200f07c",
            ],
            tools: [
                CompatTool(name: "notproton-fex-41073", flavor: .fex, display: "CrossOver 2026 10 15-ARM64 - FEX"),
                CompatTool(name: "notproton-fex-rosetta-41073", flavor: .rosetta, display: "CrossOver 2026 10 15-ARM64 - Rosetta"),
            ]
        ),
        // CrossOver 26.3 built from CodeWeavers' open source tree by Barrel's CI, so a free
        // build of the engine without owning CrossOver.
        RunnerBuild(
            bundleVersion: "wine-cx-26.3.0",
            releaseVersion: "26.3",
            flavor: nil,
            loaderSHA256: "1dd3bfd9c969bbd52d8851a9c8cf8c8240fb5940003f51629c4a3d45187b748d",
            cleanNtdll: [
                .x86_64Windows: "e7644f0aa9176208538d026b2b318fe13dfbf2ec8e45a16a7afc5c0c7da8614b",
                .i386Windows: "9363a9511c1eb8078ca9d061b9b0b265d82251383a8cce30c58bae67c70ed6e0",
            ],
            patchedNtdll: [
                .x86_64Windows: "19cffb58ec9d0a9d6723aed44a792a18b7d01a98813a8b4f5eef00562b4b4c7e",
                .i386Windows: "8038882b47f12119a4b6c40e2fade94177bb88bee5ac0d2d623dd1e6381e5757",
            ],
            tools: [
                CompatTool(
                    name: "notproton-cx-foss", flavor: .rosetta, display: "CrossOver 26.3 (FOSS)"),
            ]
        ),
    ]

    static func build(loaderSHA256 hash: String) -> RunnerBuild? {
        all.lazy.compactMap { $0.matching(loaderSHA256: hash) }.first
    }

    static func build(id: String) -> RunnerBuild? {
        all.first { $0.id == id }
    }

    static func displayVersion(forID id: String) -> String {
        build(id: id)?.displayVersion ?? id
    }

    static func productName(forID id: String) -> String {
        build(id: id)?.productName ?? "CrossOver"
    }

    static var versionList: String {
        var seen = Set<String>()
        return all.map(\.releaseVersion)
            .filter { seen.insert($0).inserted }
            .joined(separator: ", ")
    }
}
