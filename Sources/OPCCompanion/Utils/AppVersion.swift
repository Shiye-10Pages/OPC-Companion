import Foundation

/// App 版本工具。版本号单一真相源是仓库根 `version.json`；打包时由 build.sh 把它 stamp 进
/// Info.plist 的 CFBundleShortVersionString。运行期从 Bundle 读取，与线上 version.json 比对决定是否提示更新。
enum AppVersion {
    /// "0.0.0" 表示未 stamp（多为 `swift run` 的开发态，非 .app 包）。
    static let devSentinel = "0.0.0"

    static var current: String {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v! : devSentinel
    }

    static var isDevBuild: Bool { current == devSentinel }

    /// 语义化比较：`a` 是否严格旧于 `b`。仅取每段前导数字（"1.2.10" > "1.2.9"，缺省段按 0）。
    static func isOlder(_ a: String, than b: String) -> Bool {
        let pa = parse(a), pb = parse(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static func parse(_ v: String) -> [Int] {
        v.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .map { seg in Int(seg.prefix(while: { $0.isNumber })) ?? 0 }
    }
}
