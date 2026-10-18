package com.jackwallner.bond

import android.content.Intent

/** Release builds ignore every launch option. The paid boundary cannot be opened here. */
object DebugLaunchOptions {
    @Suppress("UNUSED_PARAMETER")
    fun apply(graph: AppGraph, intent: Intent?) = Unit
}
