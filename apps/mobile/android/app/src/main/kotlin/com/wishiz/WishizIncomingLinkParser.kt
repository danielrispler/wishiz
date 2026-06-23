package com.wishiz

object WishizIncomingLinkParser {
    const val actionView = "android.intent.action.VIEW"
    const val actionSend = "android.intent.action.SEND"

    fun extractPendingValue(
        action: String?,
        dataString: String? = null,
        subject: String? = null,
        text: String? = null,
    ): String? {
        return when (action) {
            actionView -> normalizeRoute(dataString)
            actionSend -> normalizeSharedText(
                listOfNotNull(text?.trim(), subject?.trim()).filter { it.isNotEmpty() }
            )
            else -> null
        }
    }

    fun normalizeRoute(route: String?): String? {
        val trimmedRoute = route?.trim()
        return if (trimmedRoute.isNullOrEmpty()) null else trimmedRoute
    }

    fun normalizeSharedText(pieces: List<String>): String? {
        if (pieces.isEmpty()) {
            return null
        }

        val lines = linkedSetOf<String>()
        for (piece in pieces) {
            piece
                .split(Regex("\\r?\\n"))
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .forEach { lines.add(it) }
        }

        return if (lines.isEmpty()) null else lines.joinToString(separator = "\n")
    }
}
