import AppKit

enum AppBrand {
    static let resourcesURL = URL(string: "https://shiyeai.cn/")!
    static let onboardingCompletionKey = "hasCompletedInitialOnboarding"

    @discardableResult
    static func openResources() -> Bool {
        NSWorkspace.shared.open(resourcesURL)
    }

    static func xiaohongshuQRCodeImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "ShiyeAI-Xiaohongshu-QR", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// 企微二维码（反馈与诊断用）。文件未随包提供时返回 nil，UI 会优雅隐藏。
    static func wecomQRCodeImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "Wecom-QR", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
