import Common

struct OptSlashCommand: Command {
    let args: OptSlashCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        OptSlashPanel.shared.toggle()
        return true
    }
}
