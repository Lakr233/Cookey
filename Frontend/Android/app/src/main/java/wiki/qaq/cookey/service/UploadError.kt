package wiki.qaq.cookey.service

sealed class UploadError(val userMessage: String) : Exception(userMessage) {

    data object InvalidRecipientPublicKey : UploadError(
        "The login request contains an invalid recipient key."
    )

    data object EmptySessionPayload : UploadError(
        "The captured browser session was empty. Reload the page, complete login, and try sending again."
    )

    data object InvalidSessionPayload : UploadError(
        "The captured browser session was invalid. Reload the page and try sending again."
    )

    class NetworkError(message: String) : UploadError("Upload failed: $message")

    class ServerError(code: Int, message: String) : UploadError("Server error ($code): $message")
}
