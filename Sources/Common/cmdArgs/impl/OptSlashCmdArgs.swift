public struct OptSlashCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .optSlash,
        allowInConfig: true,
        help: opt_slash_help_generated,
        flags: [:],
        posArgs: [],
    )
}
