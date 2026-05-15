public enum DeletionConfirmationPolicy {
    public static func shouldConfirm(skipConfirmation: Bool) -> Bool {
        !skipConfirmation
    }
}
