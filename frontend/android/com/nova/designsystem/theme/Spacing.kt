package com.nova.designsystem.theme

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Nova Design System Spacing Scale
 */
object NovaSpacing {
    val xs: Dp = 4.dp
    val sm: Dp = 8.dp
    val md: Dp = 12.dp
    val lg: Dp = 16.dp
    val xl: Dp = 24.dp
    val xxl: Dp = 32.dp
}

/**
 * Border Radius Values
 */
object NovaRadius {
    val sm: Dp = 8.dp
    val md: Dp = 12.dp
    val lg: Dp = 16.dp
}

/**
 * Avatar Size Scale
 */
object NovaAvatarSize {
    val xs: Dp = 24.dp
    val sm: Dp = 32.dp
    val md: Dp = 40.dp
    val lg: Dp = 56.dp
}

/**
 * Icon Size Scale
 */
object NovaIconSize {
    val md: Dp = 20.dp
    val lg: Dp = 24.dp
}

/**
 * Component-specific dimensions
 */
object NovaComponents {
    object PostCard {
        val paddingX: Dp = 12.dp
        val paddingY: Dp = 8.dp
        val corner: Dp = 12.dp
    }

    object Story {
        val diameter: Dp = 68.dp
        val ring: Dp = 2.dp
    }

    object Grid {
        const val columns: Int = 3
        val gap: Dp = 2.dp
        val thumbCorner: Dp = 4.dp
    }

    object HitArea {
        val min: Dp = 44.dp
    }
}
