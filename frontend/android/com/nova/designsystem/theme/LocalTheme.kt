package com.nova.designsystem.theme

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Brand skin enum for theme switching
 */
enum class BrandSkin {
    BRAND_A,
    BRAND_B
}

/**
 * CompositionLocal for brand skin
 */
val LocalBrandTheme = staticCompositionLocalOf { BrandSkin.BRAND_A }

/**
 * CompositionLocal for color scheme
 */
val LocalColorScheme = staticCompositionLocalOf { BrandALightColors }

/**
 * Extension properties for easy access to theme values
 */
object NovaTheme {
    val colors: NovaColorScheme
        @androidx.compose.runtime.Composable
        @androidx.compose.runtime.ReadOnlyComposable
        get() = LocalColorScheme.current

    val brand: BrandSkin
        @androidx.compose.runtime.Composable
        @androidx.compose.runtime.ReadOnlyComposable
        get() = LocalBrandTheme.current
}
