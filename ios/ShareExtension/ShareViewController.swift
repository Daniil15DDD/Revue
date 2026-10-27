import receive_sharing_intent

/// The "Revue" icon in the iOS share sheet (YouTube, Safari, Photos…).
/// Hands the shared link/image to the app through the App Group, then opens Revue.
class ShareViewController: RSIShareViewController {
    override func shouldAutoRedirect() -> Bool { true }
}
