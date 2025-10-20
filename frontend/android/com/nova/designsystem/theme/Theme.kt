package com.nova.designsystem.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/**
 * Nova Design System Theme
 *
 * Supports 8 theme combinations:
 * - BrandA Light/Dark
 * - BrandB Light/Dark
 *
 * @param skin Brand skin (BRAND_A or BRAND_B)
 * @param isDark Dark mode enabled
 * @param enableDynamicColor Enable Material You dynamic colors (Android 12+)
 * @param content Composable content
 */
@Composable
fun NovaTheme(
    skin: BrandSkin = BrandSkin.BRAND_A,
    isDark: Boolean = isSystemInDarkTheme(),
    enableDynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    // Determine color scheme based on brand and dark mode
    val novaColors = when (skin) {
        BrandSkin.BRAND_A -> if (isDark) BrandADarkColors else BrandALightColors
        BrandSkin.BRAND_B -> if (isDark) BrandBDarkColors else BrandBLightColors
    }

    // Map Nova colors to Material3 ColorScheme
    val materialColors = when {
        enableDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (isDark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        isDark -> darkColorScheme(
            primary = novaColors.brandPrimary,
            onPrimary = novaColors.brandOn,
            secondary = novaColors.fgSecondary,
            onSecondary = novaColors.bgSurface,
            tertiary = novaColors.stateSuccess,
            onTertiary = Color.White,
            background = novaColors.bgSurface,
            onBackground = novaColors.fgPrimary,
            surface = novaColors.bgSurface,
            onSurface = novaColors.fgPrimary,
            surfaceVariant = novaColors.bgElevated,
            onSurfaceVariant = novaColors.fgSecondary,
            error = novaColors.stateDanger,
            onError = Color.White,
            outline = novaColors.borderStrong,
            outlineVariant = novaColors.borderSubtle
        )
        else -> lightColorScheme(
            primary = novaColors.brandPrimary,
            onPrimary = novaColors.brandOn,
            secondary = novaColors.fgSecondary,
            onSecondary = novaColors.bgSurface,
            tertiary = novaColors.stateSuccess,
            onTertiary = Color.White,
            background = novaColors.bgSurface,
            onBackground = novaColors.fgPrimary,
            surface = novaColors.bgSurface,
            onSurface = novaColors.fgPrimary,
            surfaceVariant = novaColors.bgElevated,
            onSurfaceVariant = novaColors.fgSecondary,
            error = novaColors.stateDanger,
            onError = Color.White,
            outline = novaColors.borderStrong,
            outlineVariant = novaColors.borderSubtle
        )
    }

    // Update system bars
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = novaColors.bgSurface.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !isDark
        }
    }

    // Provide theme values
    CompositionLocalProvider(
        LocalBrandTheme provides skin,
        LocalColorScheme provides novaColors
    ) {
        MaterialTheme(
            colorScheme = materialColors,
            typography = NovaTypography,
            content = content
        )
    }
}

/**
 * Preview helper for BrandA Light
 */
@Composable
fun NovaThemeBrandALight(content: @Composable () -> Unit) {
    NovaTheme(skin = BrandSkin.BRAND_A, isDark = false, content = content)
}

/**
 * Preview helper for BrandA Dark
 */
@Composable
fun NovaThemeBrandADark(content: @Composable () -> Unit) {
    NovaTheme(skin = BrandSkin.BRAND_A, isDark = true, content = content)
}

/**
 * Preview helper for BrandB Light
 */
@Composable
fun NovaThemeBrandBLight(content: @Composable () -> Unit) {
    NovaTheme(skin = BrandSkin.BRAND_B, isDark = false, content = content)
}

/**
 * Preview helper for BrandB Dark
 */
@Composable
fun NovaThemeBrandBDark(content: @Composable () -> Unit) {
    NovaTheme(skin = BrandSkin.BRAND_B, isDark = true, content = content)
}
