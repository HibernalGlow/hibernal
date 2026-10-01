import AppKit

let isLoginLaunch = CommandLine.arguments.contains("--login")
let app = NSApplication.shared
let appDelegate = AppDelegate(loginLaunch: isLoginLaunch)
app.delegate = appDelegate
_ = appDelegate
app.run()