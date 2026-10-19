import Foundation

/// 全部偏好设置都走这一个 suite，命令行版和 .app 版共用。
enum AppSettings {
    static let suiteName = "local.chardiff"

    /// 从旧 suite 搬一次设置。改名前用 local.fontcompare，不搬的话选过的字体全丢。
    static func migrate() {
        let old = UserDefaults(suiteName: "local.fontcompare") ?? .standard
        let now = UserDefaults(suiteName: suiteName) ?? .standard
        guard now.object(forKey: "characters") == nil else { return }
        for key in migrationKeys where old.object(forKey: key) != nil {
            now.set(old.object(forKey: key)!, forKey: key)
        }
    }

    private static let migrationKeys = [
        "characters", "fontA", "fontB", "pointSize",
        "overlay", "guides", "writeNewline", "writeDedupe",
        "pickFile", "recentFonts", "charFileDir", "windowFrame",
    ]
}

extension UserDefaults {
    /// 取本应用的共享 suite。
    static let appSettings = UserDefaults(suiteName: AppSettings.suiteName) ?? .standard
}
