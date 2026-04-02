package com.example.wishiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WishizIncomingLinkParserTest {
    @Test
    fun `returns route payload for action view wishiz app links`() {
        assertEquals(
            "https://wishiz.app/lists/wishlist-42",
            WishizIncomingLinkParser.extractPendingValue(
                action = WishizIncomingLinkParser.actionView,
                dataString = "https://wishiz.app/lists/wishlist-42",
            ),
        )
    }

    @Test
    fun `returns route payload for action view custom scheme links`() {
        assertEquals(
            "wishiz://lists/wishlist-42",
            WishizIncomingLinkParser.extractPendingValue(
                action = WishizIncomingLinkParser.actionView,
                dataString = "wishiz://lists/wishlist-42",
            ),
        )
    }

    @Test
    fun `normalizes shared text for action send`() {
        assertEquals(
            "https://wishiz.app/lists/wishlist-42\nJoin my list",
            WishizIncomingLinkParser.extractPendingValue(
                action = WishizIncomingLinkParser.actionSend,
                subject = "Join my list",
                text = "https://wishiz.app/lists/wishlist-42",
            ),
        )
    }

    @Test
    fun `returns null for unsupported actions`() {
        assertNull(
            WishizIncomingLinkParser.extractPendingValue(
                action = "android.intent.action.MAIN",
                dataString = "https://wishiz.app/lists/wishlist-42",
            ),
        )
    }
}
