import AppKit

Prefs.registerDefaults()

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
// Sem ícone no Dock: o Ponto vive na barra de menus.
application.setActivationPolicy(.accessory)
application.run()
