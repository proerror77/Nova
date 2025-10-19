package com.nova.designsystem.theme

import androidx.compose.ui.graphics.Color

/**
 * Nova Design System Color Scheme
 * Supports BrandA and BrandB with light/dark modes
 */
data class NovaColorScheme(
    val bgSurface: Color,
    val bgElevated: Color,
    val fgPrimary: Color,
    val fgSecondary: Color,
    val brandPrimary: Color,
    val brandOn: Color,
    val borderSubtle: Color,
    val borderStrong: Color,
    val stateSuccess: Color,
    val stateWarning: Color,
    val stateDanger: Color
)

// Gray Palette
object GrayPalette {
    val Gray0 = Color(0xFFFFFFFF)
    val Gray50 = Color(0xFFF9FAFB)
    val Gray100 = Color(0xFFF2F4F7)
    val Gray200 = Color(0xFFE4E7EC)
    val Gray300 = Color(0xFFD0D5DD)
    val Gray400 = Color(0xFF98A2B3)
    val Gray500 = Color(0xFF667085)
    val Gray600 = Color(0xFF475467)
    val Gray700 = Color(0xFF344054)
    val Gray800 = Color(0xFF1D2939)
    val Gray900 = Color(0xFF101828)
}

// Blue Palette (BrandA)
object BluePalette {
    val Blue50 = Color(0xFFE0F2FE)
    val Blue100 = Color(0xFFB9E6FE)
    val Blue200 = Color(0xFF7CD4FD)
    val Blue300 = Color(0xFF36BFFA)
    val Blue400 = Color(0xFF0BA5EC)
    val Blue500 = Color(0xFF0086C9)
    val Blue600 = Color(0xFF026AA2)
    val Blue700 = Color(0xFF065986)
    val Blue800 = Color(0xFF0B4A6F)
    val Blue900 = Color(0xFF053D5A)
}

// Red Palette (BrandB)
object RedPalette {
    val Red50 = Color(0xFFFEF3F2)
    val Red100 = Color(0xFFFEE4E2)
    val Red200 = Color(0xFFFECDCA)
    val Red300 = Color(0xFFFDA29B)
    val Red400 = Color(0xFFF97066)
    val Red500 = Color(0xFFF04438)
    val Red600 = Color(0xFFD92D20)
    val Red700 = Color(0xFFB42318)
    val Red800 = Color(0xFF912018)
    val Red900 = Color(0xFF7A271A)
}

// Green Palette (Success)
object GreenPalette {
    val Green50 = Color(0xFFECFDF3)
    val Green100 = Color(0xFFD1FADF)
    val Green200 = Color(0xFFA6F4C5)
    val Green300 = Color(0xFF6CE9A6)
    val Green400 = Color(0xFF32D583)
    val Green500 = Color(0xFF12B76A)
    val Green600 = Color(0xFF039855)
    val Green700 = Color(0xFF027A48)
    val Green800 = Color(0xFF05603A)
    val Green900 = Color(0xFF054F31)
}

// Orange Palette (Warning)
object OrangePalette {
    val Orange50 = Color(0xFFFEF6EE)
    val Orange100 = Color(0xFFFDEAD7)
    val Orange200 = Color(0xFFF9DBAF)
    val Orange300 = Color(0xFFF7B27A)
    val Orange400 = Color(0xFFF38744)
    val Orange500 = Color(0xFFF79009)
    val Orange600 = Color(0xFFDC6803)
    val Orange700 = Color(0xFFB54708)
    val Orange800 = Color(0xFF93370D)
    val Orange900 = Color(0xFF792E0D)
}

// BrandA Light Mode
val BrandALightColors = NovaColorScheme(
    bgSurface = GrayPalette.Gray0,
    bgElevated = GrayPalette.Gray50,
    fgPrimary = GrayPalette.Gray900,
    fgSecondary = GrayPalette.Gray600,
    brandPrimary = BluePalette.Blue500,
    brandOn = GrayPalette.Gray0,
    borderSubtle = GrayPalette.Gray200,
    borderStrong = GrayPalette.Gray300,
    stateSuccess = GreenPalette.Green500,
    stateWarning = OrangePalette.Orange500,
    stateDanger = RedPalette.Red500
)

// BrandA Dark Mode
val BrandADarkColors = NovaColorScheme(
    bgSurface = GrayPalette.Gray900,
    bgElevated = GrayPalette.Gray800,
    fgPrimary = GrayPalette.Gray0,
    fgSecondary = GrayPalette.Gray400,
    brandPrimary = BluePalette.Blue400,
    brandOn = Color(0xFF001119),
    borderSubtle = GrayPalette.Gray800,
    borderStrong = GrayPalette.Gray700,
    stateSuccess = GreenPalette.Green500,
    stateWarning = OrangePalette.Orange500,
    stateDanger = RedPalette.Red400
)

// BrandB Light Mode
val BrandBLightColors = NovaColorScheme(
    bgSurface = GrayPalette.Gray0,
    bgElevated = GrayPalette.Gray50,
    fgPrimary = GrayPalette.Gray900,
    fgSecondary = GrayPalette.Gray600,
    brandPrimary = RedPalette.Red500,
    brandOn = GrayPalette.Gray0,
    borderSubtle = GrayPalette.Gray200,
    borderStrong = GrayPalette.Gray300,
    stateSuccess = GreenPalette.Green500,
    stateWarning = OrangePalette.Orange500,
    stateDanger = RedPalette.Red600
)

// BrandB Dark Mode
val BrandBDarkColors = NovaColorScheme(
    bgSurface = GrayPalette.Gray900,
    bgElevated = GrayPalette.Gray800,
    fgPrimary = GrayPalette.Gray0,
    fgSecondary = GrayPalette.Gray400,
    brandPrimary = RedPalette.Red400,
    brandOn = Color(0xFF2A0A08),
    borderSubtle = GrayPalette.Gray800,
    borderStrong = GrayPalette.Gray700,
    stateSuccess = GreenPalette.Green500,
    stateWarning = OrangePalette.Orange500,
    stateDanger = RedPalette.Red500
)
