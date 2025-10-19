# Design System & Multi-Brand Theming - Task List

## Implementation Tasks

- [ ] 1. **Create Unified tokens.design.json (Cross-Platform)**
    - [ ] 1.1. Generate core token palette (gray/blue/coral families)
        - *Goal*: Define base color palette with 11 families (gray 0-900, blue/coral 500-700)
        - *Details*: Create JSON with { gray, blue, coral, green, amber } palettes in core section
        - *Requirements*: Acc.1, Core Feature 1
    - [ ] 1.2. Create typography scale (3 sizes)
        - *Goal*: Define SF Pro Text scale for label/sm, body/md, title/lg
        - *Details*: fontFamily, fontSize, lineHeight, fontWeight for each scale
        - *Requirements*: Acc.1, Non-Func Requirements
    - [ ] 1.3. Create spacing & metrics (6 spaces, 3 radii, 2 motions)
        - *Goal*: Define 8pt grid-based spacing, corner radii, motion curves
        - *Details*: space{xs-2xl}, radius{sm/md/lg}, motion{fast/base/slow}
        - *Requirements*: Acc.1, Core Feature 1
    - [ ] 1.4. Create 4 theme variants (BrandA/B × Light/Dark)
        - *Goal*: Generate brand-specific color sets for all 8 theme combinations
        - *Details*: 11 semantic colors per variant (bg.surface, fg.primary, brand.primary, etc.)
        - *Requirements*: Acc.1, Core Feature 2, Core Feature 3
    - [ ] 1.5. Export tokens.design.json to design-system/ folder
        - *Goal*: Save complete Tokens Studio JSON format
        - *Details*: Include $metadata, $themes, core, brandA/B.light/dark sections
        - *Requirements*: Acc.1

- [ ] 2. **Generate iOS Architecture (SwiftUI + xcassets)**
    - [ ] 2.1. Create 4 xcassets color groups
        - *Goal*: Set up XCAssets structure for all 8 theme colors
        - *Details*: brandA.light/, brandA.dark/, brandB.light/, brandB.dark/ folders with 11 colors each
        - *Requirements*: Acc.2, Acc.5
    - [ ] 2.2. Map color values from tokens.design.json to xcassets
        - *Goal*: Populate all color hex values from tokens into xcassets
        - *Details*: Create Contents.json for each color with Appearance + Light/Dark variants
        - *Requirements*: Acc.2
    - [ ] 2.3. Generate Theme.swift runtime file
        - *Goal*: Create Theme struct with BrandSkin enum, Colors, TypeScale, Space, Metric
        - *Details*: Include @Environment injection and color accessor methods
        - *Requirements*: Acc.2, Acc.4
    - [ ] 2.4. Create EnvironmentKey + View extension
        - *Goal*: Make Theme injectable via SwiftUI @Environment
        - *Details*: ThemeKey struct, environment(\.theme) extension, .theme() modifier
        - *Requirements*: Acc.2, Acc.4
    - [ ] 2.5. Test theme switching in iOS preview
        - *Goal*: Verify all 8 combinations render correctly
        - *Details*: Create preview canvas with BrandA/B × Light/Dark variations
        - *Requirements*: Acc.5

- [ ] 3. **Generate Android Architecture (Jetpack Compose)**
    - [ ] 3.1. Create colors.xml (light) and values-night/colors.xml (dark)
        - *Goal*: XML color resources for Android Material3
        - *Details*: Define <color> tags for all semantic colors, following Android resource naming
        - *Requirements*: Acc.3, Acc.5
    - [ ] 3.2. Create dimens.xml (spacing & metrics)
        - *Goal*: Define dimension resources for spacing, radius, hit areas
        - *Details*: <dimen> tags for space{xs-2xl}, radius{sm/md/lg}, avatar sizes, etc.
        - *Requirements*: Acc.3
    - [ ] 3.3. Generate Theme.kt (Compose runtime)
        - *Goal*: Create composable Theme objects with CompositionLocal
        - *Details*: BrandSkin enum, ColorScheme data class, LocalBrandTheme, LocalColorScheme
        - *Requirements*: Acc.3, Acc.4
    - [ ] 3.4. Create CompositionLocal providers
        - *Goal*: Enable theme propagation through Compose hierarchy
        - *Details*: NovaApp composable with CompositionLocalProvider setup
        - *Requirements*: Acc.3, Acc.4
    - [ ] 3.5. Integrate Material3 theming
        - *Goal*: Map custom colors to Material3 ColorScheme
        - *Details*: Link brandPrimary → primary, stateSuccess → tertiary, etc.
        - *Requirements*: Acc.3
    - [ ] 3.6. Test theme switching in Android preview
        - *Goal*: Verify all 8 combinations render in Compose preview
        - *Details*: Create @Preview functions for BrandA/B × Light/Dark combinations
        - *Requirements*: Acc.5

- [ ] 4. **Create Integration & Documentation**
    - [ ] 4.1. Write iOS integration guide
        - *Goal*: Step-by-step instructions for using Theme.swift
        - *Details*: 1) Add xcassets to project, 2) Copy Theme.swift, 3) Inject at App root, 4) Usage examples
        - *Requirements*: Acc.6, User Story 2
    - [ ] 4.2. Write Android integration guide
        - *Goal*: Step-by-step instructions for using Theme.kt
        - *Details*: 1) Add res/ files, 2) Copy Theme.kt, 3) Wrap App with CompositionLocal, 4) Usage examples
        - *Requirements*: Acc.6, User Story 3
    - [ ] 4.3. Create example component (PostCard) for both platforms
        - *Goal*: Demonstrate theme usage in real component
        - *Details*: SwiftUI PostCard + Compose PostCard using theme tokens
        - *Requirements*: Acc.6, User Stories 2-3
    - [ ] 4.4. Create theme switching example
        - *Goal*: Show how to switch brands at runtime
        - *Details*: iOS: UserDefaults + refresh mechanism; Android: state recomposition
        - *Requirements*: Acc.4, User Story 4
    - [ ] 4.5. Generate SETUP.md for designers (Figma Tokens Studio import)
        - *Goal*: Guide designers on importing tokens.design.json and syncing back
        - *Details*: Instructions for Tokens Studio setup, variable binding, export workflow
        - *Requirements*: User Story 1

## Task Dependencies

1. Task 1 (tokens.design.json) must complete FIRST — all other tasks depend on token definitions
2. Task 2 (iOS) and Task 3 (Android) can execute in PARALLEL after Task 1
3. Task 4 (Integration & Docs) executes after Tasks 2 & 3 complete
4. Subtasks within Task 2 & 3 have internal ordering (e.g., create colors before Theme.swift)

## Estimated Timeline

- Task 1: 1 hour (token generation + validation)
- Task 2: 2 hours (iOS architecture + testing)
- Task 3: 2 hours (Android architecture + testing)
- Task 4: 1.5 hours (guides + examples)
- **Total: 6.5 hours** (sequential); **4 hours** (with Task 2-3 parallel)
