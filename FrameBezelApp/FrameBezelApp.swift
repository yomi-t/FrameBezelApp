import SwiftUI
import Foundation

/// 起動引数に `--export` などがあれば画面を開かずに書き出して終了し、無ければ通常の GUI として起動する。
@main
enum Launcher {
    static func main() {
        let args = CommandLine.arguments
        guard HeadlessExport.isCommandLineInvocation(args) else {
            FrameBezelApp.main()
            return
        }
        let code = HeadlessExport.runCommandLine(
            arguments: args,
            out: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
            err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
        exit(code)
    }
}

struct FrameBezelApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
