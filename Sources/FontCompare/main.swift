import AppKit

// 系统默认要停一会儿才弹提示。这个值不管 AppKit 按毫秒还是秒来读都是「马上」，
// 免得去猜单位。要在窗口起来之前设。
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0.1])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
