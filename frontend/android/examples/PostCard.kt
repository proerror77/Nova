package com.nova.designsystem.examples

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.nova.designsystem.theme.BrandSkin
import com.nova.designsystem.theme.NovaAvatarSize
import com.nova.designsystem.theme.NovaComponents
import com.nova.designsystem.theme.NovaIconSize
import com.nova.designsystem.theme.NovaRadius
import com.nova.designsystem.theme.NovaSpacing
import com.nova.designsystem.theme.NovaTheme
import com.nova.designsystem.theme.NovaThemeBrandADark
import com.nova.designsystem.theme.NovaThemeBrandALight
import com.nova.designsystem.theme.NovaThemeBrandBDark
import com.nova.designsystem.theme.NovaThemeBrandBLight

/**
 * Instagram-style Post Card Component
 * Demonstrates Nova Design System usage
 */
@Composable
fun PostCard(
    username: String,
    userHandle: String,
    caption: String,
    likes: Int,
    comments: Int,
    modifier: Modifier = Modifier
) {
    val colors = NovaTheme.colors
    var isLiked by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = colors.bgSurface,
        shape = RoundedCornerShape(NovaComponents.PostCard.corner),
        tonalElevation = 1.dp
    ) {
        Column(
            modifier = Modifier.padding(
                horizontal = NovaComponents.PostCard.paddingX,
                vertical = NovaComponents.PostCard.paddingY
            )
        ) {
            // Header: Avatar + Username + Menu
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Avatar
                Surface(
                    modifier = Modifier.size(NovaAvatarSize.md),
                    shape = CircleShape,
                    color = colors.bgElevated
                ) {
                    // Placeholder avatar
                }

                Spacer(modifier = Modifier.width(NovaSpacing.sm))

                // Username and handle
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = username,
                        style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.fgPrimary
                    )
                    Text(
                        text = userHandle,
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = colors.fgSecondary
                    )
                }

                // More menu
                IconButton(onClick = { /* TODO */ }) {
                    Icon(
                        imageVector = Icons.Default.MoreVert,
                        contentDescription = "More options",
                        tint = colors.fgSecondary,
                        modifier = Modifier.size(NovaIconSize.lg)
                    )
                }
            }

            Spacer(modifier = Modifier.height(NovaSpacing.md))

            // Post image placeholder
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp),
                shape = RoundedCornerShape(NovaRadius.sm),
                color = colors.bgElevated
            ) {
                // Image would go here
            }

            Spacer(modifier = Modifier.height(NovaSpacing.md))

            // Action buttons: Like, Comment, Share
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(NovaSpacing.lg)
            ) {
                // Like button
                IconButton(
                    onClick = { isLiked = !isLiked },
                    modifier = Modifier.size(NovaComponents.HitArea.min)
                ) {
                    Icon(
                        imageVector = if (isLiked) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                        contentDescription = "Like",
                        tint = if (isLiked) colors.stateDanger else colors.fgPrimary,
                        modifier = Modifier.size(NovaIconSize.lg)
                    )
                }

                // Comment button
                IconButton(
                    onClick = { /* TODO */ },
                    modifier = Modifier.size(NovaComponents.HitArea.min)
                ) {
                    Icon(
                        imageVector = Icons.Outlined.ChatBubbleOutline,
                        contentDescription = "Comment",
                        tint = colors.fgPrimary,
                        modifier = Modifier.size(NovaIconSize.lg)
                    )
                }

                // Share button
                IconButton(
                    onClick = { /* TODO */ },
                    modifier = Modifier.size(NovaComponents.HitArea.min)
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Send,
                        contentDescription = "Share",
                        tint = colors.fgPrimary,
                        modifier = Modifier.size(NovaIconSize.lg)
                    )
                }
            }

            // Likes count
            Text(
                text = "$likes likes",
                style = androidx.compose.material3.MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = colors.fgPrimary
            )

            Spacer(modifier = Modifier.height(NovaSpacing.xs))

            // Caption
            Row {
                Text(
                    text = username,
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.fgPrimary
                )
                Spacer(modifier = Modifier.width(NovaSpacing.xs))
                Text(
                    text = caption,
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    color = colors.fgPrimary
                )
            }

            Spacer(modifier = Modifier.height(NovaSpacing.xs))

            // View comments
            if (comments > 0) {
                Text(
                    text = "View all $comments comments",
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    color = colors.fgSecondary
                )
            }
        }
    }
}

// Preview Configurations
@Preview(name = "BrandA Light", showBackground = true)
@Composable
private fun PostCardBrandALightPreview() {
    NovaThemeBrandALight {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .background(NovaTheme.colors.bgSurface)
                .padding(NovaSpacing.lg)
        ) {
            PostCard(
                username = "johndoe",
                userHandle = "@john.doe",
                caption = "Amazing sunset at the beach! #travel #photography",
                likes = 1234,
                comments = 56
            )
        }
    }
}

@Preview(name = "BrandA Dark", showBackground = true)
@Composable
private fun PostCardBrandADarkPreview() {
    NovaThemeBrandADark {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .background(NovaTheme.colors.bgSurface)
                .padding(NovaSpacing.lg)
        ) {
            PostCard(
                username = "johndoe",
                userHandle = "@john.doe",
                caption = "Amazing sunset at the beach! #travel #photography",
                likes = 1234,
                comments = 56
            )
        }
    }
}

@Preview(name = "BrandB Light", showBackground = true)
@Composable
private fun PostCardBrandBLightPreview() {
    NovaThemeBrandBLight {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .background(NovaTheme.colors.bgSurface)
                .padding(NovaSpacing.lg)
        ) {
            PostCard(
                username = "johndoe",
                userHandle = "@john.doe",
                caption = "Amazing sunset at the beach! #travel #photography",
                likes = 1234,
                comments = 56
            )
        }
    }
}

@Preview(name = "BrandB Dark", showBackground = true)
@Composable
private fun PostCardBrandBDarkPreview() {
    NovaThemeBrandBDark {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .background(NovaTheme.colors.bgSurface)
                .padding(NovaSpacing.lg)
        ) {
            PostCard(
                username = "johndoe",
                userHandle = "@john.doe",
                caption = "Amazing sunset at the beach! #travel #photography",
                likes = 1234,
                comments = 56
            )
        }
    }
}
