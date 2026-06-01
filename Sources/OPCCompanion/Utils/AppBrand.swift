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
}
