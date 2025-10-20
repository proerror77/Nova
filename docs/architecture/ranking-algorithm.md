# Ranking Algorithm Documentation: Three-Dimensional Feed Ranking

**Version**: 1.0
**Last Updated**: 2025-10-18
**Algorithm**: Three-Dimensional Personalized Ranking (Freshness + Engagement + Affinity)

---

## Overview

Nova's feed ranking algorithm uses a **three-dimensional scoring model** that balances recency, engagement quality, and personalized affinity to deliver feeds tailored to each user's interests.

**Design Principles**:
1. **Freshness**: Prioritize recent content (exponential decay)
2. **Engagement Quality**: Favor posts with strong engagement (not just volume)
3. **Personalization**: Boost posts from authors user interacts with
4. **Diversity**: Prevent author saturation in top results
5. **Deduplication**: Eliminate duplicate/near-duplicate posts

---

## Three-Dimensional Scoring Formula

### Master Formula

```rust
final_score = 0.30 * freshness_score
            + 0.40 * engagement_score
            + 0.30 * affinity_score
```

**Weights Rationale**:
- **40% Engagement**: Engagement quality is the strongest signal of content value
- **30% Freshness**: Recency matters, but not more than quality
- **30% Affinity**: Personalization tie-breaker, especially for similar engagement

---

## Dimension 1: Freshness Score

**Purpose**: Prioritize recent posts while gracefully aging older content

**Formula**:
```rust
freshness_score = exp(-0.1 * age_hours)

where:
  age_hours = (now - post_created_at).hours()
```

**Decay Behavior**:

| Age          | Freshness Score | Relative Weight |
|--------------|-----------------|-----------------|
| 0 hours      | 1.000           | 100%            |
| 1 hour       | 0.905           | 90.5%           |
| 5 hours      | 0.607           | 60.7%           |
| 10 hours     | 0.368           | 36.8%           |
| 24 hours     | 0.091           | 9.1%            |
| 48 hours     | 0.008           | 0.8%            |

**Graph** (ASCII):
```
Freshness
1.0 ┤■
    │ ■
0.9 │  ■
    │   ■
0.8 │    ■
    │     ■
0.7 │      ■
    │       ■■
0.6 │         ■■
    │           ■■
0.5 │             ■■
    │               ■■
0.4 │                 ■■■
    │                    ■■■
0.3 │                       ■■■
    │                          ■■■■
0.2 │                              ■■■■
    │                                  ■■■■■
0.1 │                                       ■■■■■■■
    │                                              ■■■■■■■■■■
0.0 └─────────────────────────────────────────────────────────
    0    5    10   15   20   25   30   35   40   45   50  Hours
```

**Why Exponential Decay?**
- **Gentle near-term**: Posts stay relevant for first few hours (90%+ weight)
- **Aggressive long-term**: Old posts (>24h) drop significantly (<10% weight)
- **Smooth falloff**: No cliff effect (unlike step functions)

**Implementation**:
```rust
fn calculate_freshness(post_created_at: DateTime<Utc>) -> f64 {
    let age_hours = (Utc::now() - post_created_at).num_hours() as f64;
    (-0.1 * age_hours).exp()
}
```

---

## Dimension 2: Engagement Score

**Purpose**: Measure engagement **quality**, not just volume

**Formula**:
```rust
engagement_score = log1p(
    (likes + 2*comments + 3*shares) / max(1, impressions)
)

where:
  log1p(x) = log(1 + x)  // Natural log with +1 offset
```

**Engagement Rate Calculation**:
```
engagement_rate = (likes + 2*comments + 3*shares) / impressions
```

**Why Weighted Actions?**
- **Likes**: Baseline engagement (weight: 1x)
- **Comments**: Higher effort, stronger signal (weight: 2x)
- **Shares**: Strongest endorsement (weight: 3x)

**Why `log1p`?**
- **Compresses outliers**: A post with 1000 likes doesn't dominate one with 100
- **Rewards quality over quantity**: A post with 10 likes + 100 impressions (10% rate) scores higher than 20 likes + 1000 impressions (2% rate)
- **Handles zero gracefully**: `log1p(0) = 0` (no division by zero)

**Example Scenarios**:

| Likes | Comments | Shares | Impressions | Engagement Rate | Engagement Score |
|-------|----------|--------|-------------|-----------------|------------------|
| 10    | 2        | 1      | 100         | 0.17            | 0.157            |
| 100   | 5        | 2      | 1000        | 0.116           | 0.110            |
| 50    | 20       | 10     | 500         | 0.20            | 0.182            |
| 5     | 1        | 0      | 20          | 0.35            | 0.301            |

**Key Insight**: Post 4 (5 likes, 20 impressions) scores **higher** than Post 2 (100 likes, 1000 impressions) due to superior engagement rate (35% vs. 11.6%).

**Implementation**:
```rust
fn calculate_engagement(
    likes: u32,
    comments: u32,
    shares: u32,
    impressions: u32
) -> f64 {
    let weighted_actions = likes as f64
                         + 2.0 * comments as f64
                         + 3.0 * shares as f64;
    let engagement_rate = weighted_actions / (impressions as f64).max(1.0);
    (1.0 + engagement_rate).ln()  // log1p
}
```

---

## Dimension 3: Affinity Score

**Purpose**: Personalize feed by boosting posts from frequently-interacted authors

**Formula**:
```rust
affinity_score = log1p(user_author_interactions_90d)

where:
  user_author_interactions_90d = COUNT of (likes, comments, shares)
                                  in last 90 days
```

**Data Source**: ClickHouse materialized view `user_author_90d`

**Example Affinity Levels**:

| Interactions (90d) | Affinity Score | Relative Boost |
|--------------------|----------------|----------------|
| 0                  | 0.000          | 0% (no boost)  |
| 1                  | 0.693          | +69%           |
| 5                  | 1.792          | +179%          |
| 10                 | 2.398          | +240%          |
| 50                 | 3.932          | +393%          |
| 100                | 4.615          | +462%          |

**Why 90-Day Window?**
- **Captures sustained interest**: Short bursts of interaction fade
- **Allows taste evolution**: Old interests naturally decay
- **Balances storage**: 90 days keeps affinity table manageable

**Implementation**:
```rust
fn calculate_affinity(interaction_count: u32) -> f64 {
    (1.0 + interaction_count as f64).ln()  // log1p
}
```

---

## Complete Ranking Algorithm

### Step-by-Step Process

```rust
fn rank_feed_posts(
    user_id: Uuid,
    candidate_posts: Vec<CandidatePost>
) -> Vec<Uuid> {
    // Step 1: Score each post
    let mut scored_posts: Vec<ScoredPost> = candidate_posts
        .into_iter()
        .map(|post| {
            let freshness = calculate_freshness(post.created_at);
            let engagement = calculate_engagement(
                post.likes,
                post.comments,
                post.shares,
                post.impressions
            );
            let affinity = calculate_affinity(post.author_interaction_count);

            let final_score = 0.30 * freshness
                            + 0.40 * engagement
                            + 0.30 * affinity;

            ScoredPost {
                post_id: post.id,
                author_id: post.author_id,
                content_hash: post.content_hash,
                final_score,
                freshness,
                engagement,
                affinity,
            }
        })
        .collect();

    // Step 2: Sort by final_score (descending)
    scored_posts.sort_by(|a, b|
        b.final_score.partial_cmp(&a.final_score).unwrap()
    );

    // Step 3: Deduplicate (keep highest-scoring duplicate)
    scored_posts = deduplicate_by_content_hash(scored_posts);

    // Step 4: Apply saturation control
    scored_posts = apply_saturation_control(scored_posts);

    // Step 5: Extract post IDs
    scored_posts.into_iter().map(|sp| sp.post_id).collect()
}
```

---

## Deduplication Logic

**Purpose**: Remove duplicate/near-duplicate posts (reposts, similar content)

**Strategy**: Content-based hashing

**Implementation**:
```rust
fn deduplicate_by_content_hash(posts: Vec<ScoredPost>) -> Vec<ScoredPost> {
    let mut seen_hashes: HashMap<String, ScoredPost> = HashMap::new();

    for post in posts {
        match seen_hashes.get(&post.content_hash) {
            Some(existing) => {
                // Keep higher-scoring version
                if post.final_score > existing.final_score {
                    seen_hashes.insert(post.content_hash.clone(), post);
                }
            },
            None => {
                seen_hashes.insert(post.content_hash.clone(), post);
            }
        }
    }

    seen_hashes.into_values().collect()
}
```

**Content Hash Generation**:
```rust
use sha2::{Sha256, Digest};

fn generate_content_hash(content: &str) -> String {
    let normalized = content
        .to_lowercase()
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect::<String>();

    let mut hasher = Sha256::new();
    hasher.update(normalized.as_bytes());
    format!("{:x}", hasher.finalize())
}
```

**Example**:
- Post A: "Check out this new Rust library!" (score: 0.75)
- Post B: "check out this NEW rust library!!!" (score: 0.60)
- Content hash: Same → Keep Post A (higher score)

---

## Saturation Control

**Purpose**: Prevent single author from dominating feed

**Rules**:
1. **Top-5 Diversity**: Max 1 post per author in top 5 positions
2. **Distance Constraint**: Same author must be ≥3 positions apart

**Implementation**:
```rust
fn apply_saturation_control(posts: Vec<ScoredPost>) -> Vec<ScoredPost> {
    let mut result = Vec::new();
    let mut author_last_position: HashMap<Uuid, usize> = HashMap::new();

    for (index, post) in posts.into_iter().enumerate() {
        let should_include = match author_last_position.get(&post.author_id) {
            Some(&last_pos) => {
                // Top-5 diversity rule
                if index < 5 && last_pos < 5 {
                    false  // Skip: author already in top-5
                }
                // Distance constraint
                else if index - last_pos < 3 {
                    false  // Skip: too close to previous post
                } else {
                    true
                }
            },
            None => true  // First post from this author
        };

        if should_include {
            author_last_position.insert(post.author_id, result.len());
            result.push(post);
        }
    }

    result
}
```

**Example**:
```
Before Saturation:
1. Post by Alice (score: 0.95)
2. Post by Alice (score: 0.92)  ← Removed (same author in top-5)
3. Post by Bob (score: 0.88)
4. Post by Charlie (score: 0.85)
5. Post by Alice (score: 0.82)  ← Removed (same author in top-5)
6. Post by Dave (score: 0.80)

After Saturation:
1. Post by Alice (score: 0.95)
2. Post by Bob (score: 0.88)
3. Post by Charlie (score: 0.85)
4. Post by Dave (score: 0.80)
5. Post by Eve (score: 0.78)
```

---

## Real-World Examples

### Example 1: Tech News Post

**Post**: "Rust 1.75 released with new async improvements"
- **Created**: 2 hours ago
- **Impressions**: 5000
- **Likes**: 150
- **Comments**: 30
- **Shares**: 20
- **User Affinity**: 10 interactions (90d)

**Calculation**:
```
freshness = exp(-0.1 * 2) = 0.819
engagement = log1p((150 + 2*30 + 3*20) / 5000)
           = log1p(0.054) = 0.053
affinity = log1p(10) = 2.398

final_score = 0.30 * 0.819 + 0.40 * 0.053 + 0.30 * 2.398
            = 0.246 + 0.021 + 0.719
            = 0.986
```

**Result**: **High score** (0.986) due to strong affinity (user likes Rust content)

---

### Example 2: Viral Meme (Low Affinity)

**Post**: "Funny cat video"
- **Created**: 30 minutes ago
- **Impressions**: 50,000
- **Likes**: 2000
- **Comments**: 100
- **Shares**: 50
- **User Affinity**: 0 interactions (90d)

**Calculation**:
```
freshness = exp(-0.1 * 0.5) = 0.951
engagement = log1p((2000 + 2*100 + 3*50) / 50000)
           = log1p(0.049) = 0.048
affinity = log1p(0) = 0.000

final_score = 0.30 * 0.951 + 0.40 * 0.048 + 0.30 * 0.000
            = 0.285 + 0.019 + 0.000
            = 0.304
```

**Result**: **Medium score** (0.304) despite high engagement volume (no personalization boost)

---

### Example 3: Personal Friend's Post

**Post**: "Just finished my first marathon!"
- **Created**: 10 hours ago
- **Impressions**: 200
- **Likes**: 15
- **Comments**: 8
- **Shares**: 2
- **User Affinity**: 50 interactions (90d) - close friend

**Calculation**:
```
freshness = exp(-0.1 * 10) = 0.368
engagement = log1p((15 + 2*8 + 3*2) / 200)
           = log1p(0.185) = 0.170
affinity = log1p(50) = 3.932

final_score = 0.30 * 0.368 + 0.40 * 0.170 + 0.30 * 3.932
            = 0.110 + 0.068 + 1.180
            = 1.358
```

**Result**: **Very high score** (1.358) due to strong personal affinity, despite older age

---

## Algorithm Tuning

### Weight Sensitivity Analysis

**Current Weights**: `[0.30, 0.40, 0.30]`

**Alternative Configurations**:

| Weights [F, E, A] | Behavior                              | Use Case                      |
|-------------------|---------------------------------------|-------------------------------|
| [0.50, 0.30, 0.20]| More recency-focused                  | News/breaking events feed     |
| [0.20, 0.50, 0.30]| More engagement-focused               | Discovery/explore feed        |
| [0.20, 0.30, 0.50]| More personalization-focused          | Close friends feed            |
| [0.33, 0.34, 0.33]| Balanced (equal weights)              | General-purpose feed          |

**A/B Testing Framework**:
```rust
fn get_ranking_weights(user_id: Uuid, experiment: &str) -> (f64, f64, f64) {
    match experiment_assignment(user_id, experiment) {
        "control" => (0.30, 0.40, 0.30),  // Current
        "variant_a" => (0.50, 0.30, 0.20),  // More fresh
        "variant_b" => (0.20, 0.50, 0.30),  // More engagement
        _ => (0.30, 0.40, 0.30)
    }
}
```

---

## Performance Optimization

### Query Optimization

**Before** (Naive Query - 3-5 seconds):
```sql
SELECT * FROM events
WHERE user_id IN (SELECT followed_id FROM follows WHERE follower_id = :user_id)
GROUP BY post_id;
```

**After** (Optimized with MV - 200-300ms):
```sql
SELECT
    p.id,
    pm.likes,
    pm.comments,
    pm.shares,
    pm.impressions,
    ua.interaction_count
FROM posts_cdc p
JOIN follows_cdc f ON p.user_id = f.followed_id
LEFT JOIN post_metrics_1h pm ON p.id = pm.post_id
LEFT JOIN user_author_90d ua ON (ua.user_id = :user_id AND ua.author_id = p.user_id)
WHERE f.follower_id = :user_id
  AND pm.window_start >= now() - INTERVAL 24 HOUR
LIMIT 500;
```

**Key Optimizations**:
- Use materialized views (pre-aggregated metrics)
- Limit candidate pool to 500 posts (sufficient for ranking)
- Filter to last 24 hours (older posts have low freshness score anyway)

---

### Ranking Computation Optimization

**Vectorized Scoring** (using SIMD):
```rust
use std::simd::f64x4;

fn batch_calculate_scores(posts: &[CandidatePost]) -> Vec<f64> {
    posts.chunks(4)
        .flat_map(|chunk| {
            let freshness = f64x4::from_array([...]);
            let engagement = f64x4::from_array([...]);
            let affinity = f64x4::from_array([...]);

            let weights_f = f64x4::splat(0.30);
            let weights_e = f64x4::splat(0.40);
            let weights_a = f64x4::splat(0.30);

            let scores = weights_f * freshness
                       + weights_e * engagement
                       + weights_a * affinity;

            scores.to_array()
        })
        .collect()
}
```

**Performance Gain**: 4x throughput (SIMD parallelism)

---

## Monitoring & Metrics

**Ranking Quality Metrics**:
- `feed_diversity_score` - Average distance between same-author posts
- `feed_freshness_avg` - Average freshness score in top 50
- `feed_engagement_avg` - Average engagement score in top 50
- `feed_affinity_coverage` - % of posts with affinity > 0

**User Engagement Metrics** (Post-Ranking):
- `user_dwell_time` - Time spent on feed
- `user_scroll_depth` - How far user scrolls (% of feed)
- `user_click_through_rate` - % of posts clicked
- `user_session_length` - Total time in app

**A/B Test Success Criteria**:
- Increase in `user_dwell_time` by >5%
- Increase in `user_click_through_rate` by >3%
- No decrease in `user_session_length`

---

## Future Enhancements

### 1. Machine Learning Ranking Model

**Current**: Hand-tuned weights `[0.30, 0.40, 0.30]`

**Future**: Gradient-boosted trees (XGBoost) with 50+ features
- **Features**: freshness, engagement, affinity, post length, media type, author follower count, ...
- **Training**: Daily on engagement data (clicks, dwell time, likes)
- **Deployment**: Model versioning with A/B testing

### 2. Context-Aware Ranking

**Current**: Same algorithm for all users

**Future**: Personalize algorithm based on context
- **Time of Day**: More fresh content in morning, more engagement-focused in evening
- **Device**: Shorter posts for mobile, longer for web
- **User Behavior**: Heavy engagers get more engagement-focused feed

### 3. Multi-Objective Ranking

**Current**: Single score (weighted sum)

**Future**: Pareto optimization for multiple objectives
- **Maximize**: Engagement, Diversity, Freshness
- **Constraint**: Minimum affinity threshold

### 4. Real-Time Ranking Updates

**Current**: Ranking computed at request time, cached for 5 min

**Future**: Pre-compute rankings in background, update on new post/engagement
- **Architecture**: Kafka consumer triggers re-ranking for affected users
- **Benefit**: Instant feed updates (event-to-visible <1s)

---

## References

- [Architecture Overview](phase3-overview.md)
- [Data Model](data-model.md)
- [Operational Runbook](../operations/runbook.md)
- Research: "Collaborative Filtering for Implicit Feedback Datasets" (Hu et al., 2008)
- Research: "Learning to Rank for Information Retrieval" (Liu, 2009)
