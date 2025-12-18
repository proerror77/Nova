#!/usr/bin/env python3
"""
Feature Extraction Module for Nova Recommendation System (P1-3)

Extracts and computes features for training data from ClickHouse.

Feature Categories:
1. User Features (8 dimensions)
2. Content Features (10 dimensions)
3. Author Features (5 dimensions)
4. Interaction Features (4 dimensions)
5. Context Features (3 dimensions)

Total: 30 dimensions (expanded from original 9)
"""

import logging
from datetime import datetime
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


class FeatureExtractor:
    """
    Feature extraction from ClickHouse for training data.
    """

    def __init__(self, clickhouse_client):
        """
        Initialize feature extractor.

        Args:
            clickhouse_client: ClickHouse client connection
        """
        self.client = clickhouse_client

    def get_features_batch(
        self,
        user_ids: List[str],
        post_ids: List[str],
        timestamps: List[datetime],
        tolerance_seconds: int = 3600,
    ) -> pd.DataFrame:
        """
        Batch fetch features for user-post pairs from training_features table.

        Args:
            user_ids: List of user IDs
            post_ids: List of post IDs
            timestamps: List of impression timestamps
            tolerance_seconds: Time tolerance for feature snapshot matching

        Returns:
            DataFrame with features
        """
        if not user_ids:
            return pd.DataFrame()

        query = """
        SELECT
            user_id,
            post_id,
            -- User features
            user_follower_count,
            user_following_count,
            user_post_count,
            user_avg_session_length,
            user_active_days_30d,
            -- Content features
            post_age_hours,
            post_like_count,
            post_comment_count,
            post_view_count,
            post_completion_rate,
            post_engagement_rate,
            content_duration_ms,
            has_music,
            is_original,
            -- Author features
            author_follower_count,
            author_avg_engagement,
            author_post_frequency,
            -- Interaction features
            user_author_affinity,
            user_author_interaction_count,
            -- Recall features
            recall_source,
            recall_weight,
            -- Extra features (JSON)
            extra_features
        FROM training_features
        WHERE (user_id, post_id) IN (
            SELECT user_id, post_id FROM (
                SELECT
                    arrayJoin(%(user_ids)s) AS user_id,
                    arrayJoin(%(post_ids)s) AS post_id
            )
        )
        ORDER BY snapshot_time DESC
        LIMIT 1 BY user_id, post_id
        """

        try:
            result = self.client.query(
                query,
                parameters={
                    "user_ids": user_ids,
                    "post_ids": post_ids,
                }
            )
            return pd.DataFrame(result.result_rows, columns=result.column_names)
        except Exception as e:
            logger.warning(f"Failed to fetch features: {e}")
            return pd.DataFrame()

    def compute_user_features(
        self,
        user_ids: List[str],
        reference_time: datetime,
    ) -> pd.DataFrame:
        """
        Compute user features from raw data.

        User Features (8 dimensions):
        1. follower_count - Number of followers
        2. following_count - Number of following
        3. post_count - Number of posts created
        4. avg_session_length - Average session duration
        5. active_days_30d - Days active in last 30 days
        6. avg_daily_watch_time - Average daily watch time
        7. content_type_preference - Preferred content type
        8. avg_interaction_rate - Average interaction rate
        """
        if not user_ids:
            return pd.DataFrame()

        query = """
        WITH user_stats AS (
            SELECT
                user_id,
                count(DISTINCT event_date) AS active_days_30d,
                avg(watch_duration_ms) AS avg_watch_duration,
                sum(watch_duration_ms) / 30.0 AS avg_daily_watch_time,
                countIf(completion_rate >= 0.7) / count() AS completion_interaction_rate
            FROM watch_events
            WHERE user_id IN %(user_ids)s
              AND event_date >= %(start_date)s
              AND event_date <= %(end_date)s
            GROUP BY user_id
        ),
        user_likes AS (
            SELECT
                user_id,
                count() AS like_count_30d
            FROM likes_cdc
            WHERE user_id IN %(user_ids)s
              AND created_at >= %(start_time)s
              AND is_deleted = 0
            GROUP BY user_id
        )
        SELECT
            us.user_id,
            us.active_days_30d,
            us.avg_watch_duration,
            us.avg_daily_watch_time,
            us.completion_interaction_rate,
            COALESCE(ul.like_count_30d, 0) AS like_count_30d
        FROM user_stats us
        LEFT JOIN user_likes ul ON us.user_id = ul.user_id
        """

        end_date = reference_time.strftime("%Y-%m-%d")
        start_date = (reference_time - pd.Timedelta(days=30)).strftime("%Y-%m-%d")
        start_time = (reference_time - pd.Timedelta(days=30)).isoformat()

        try:
            result = self.client.query(
                query,
                parameters={
                    "user_ids": user_ids,
                    "start_date": start_date,
                    "end_date": end_date,
                    "start_time": start_time,
                }
            )
            return pd.DataFrame(result.result_rows, columns=result.column_names)
        except Exception as e:
            logger.warning(f"Failed to compute user features: {e}")
            return pd.DataFrame()

    def compute_content_features(
        self,
        post_ids: List[str],
        reference_time: datetime,
    ) -> pd.DataFrame:
        """
        Compute content features from raw data.

        Content Features (10 dimensions):
        1. post_age_hours - Hours since post creation
        2. like_count - Total likes
        3. comment_count - Total comments
        4. view_count - Total views
        5. completion_rate - Average completion rate
        6. engagement_rate - (likes + comments) / views
        7. content_duration_ms - Content duration in ms
        8. has_music - Whether has background music
        9. is_original - Whether is original content
        10. trending_velocity - Recent engagement growth rate
        """
        if not post_ids:
            return pd.DataFrame()

        query = """
        WITH post_engagement AS (
            SELECT
                content_id AS post_id,
                count() AS view_count,
                avg(completion_rate) AS avg_completion_rate,
                countIf(completion_rate >= 0.9) AS high_completion_count
            FROM watch_events
            WHERE content_id IN %(post_ids)s
            GROUP BY content_id
        ),
        post_likes AS (
            SELECT
                post_id,
                count() AS like_count
            FROM likes_cdc
            WHERE post_id IN %(post_ids)s
              AND is_deleted = 0
            GROUP BY post_id
        ),
        post_comments AS (
            SELECT
                post_id,
                count() AS comment_count
            FROM comments_cdc
            WHERE post_id IN %(post_ids)s
              AND is_deleted = 0
            GROUP BY post_id
        ),
        recent_engagement AS (
            SELECT
                content_id AS post_id,
                count() AS recent_views
            FROM watch_events
            WHERE content_id IN %(post_ids)s
              AND event_time >= %(recent_start)s
            GROUP BY content_id
        )
        SELECT
            pe.post_id,
            COALESCE(pe.view_count, 0) AS view_count,
            COALESCE(pe.avg_completion_rate, 0) AS completion_rate,
            COALESCE(pl.like_count, 0) AS like_count,
            COALESCE(pc.comment_count, 0) AS comment_count,
            COALESCE(re.recent_views, 0) AS recent_views,
            -- Engagement rate
            if(pe.view_count > 0,
               (COALESCE(pl.like_count, 0) + COALESCE(pc.comment_count, 0)) / pe.view_count,
               0) AS engagement_rate,
            -- Trending velocity (recent views / total views)
            if(pe.view_count > 0,
               COALESCE(re.recent_views, 0) / pe.view_count,
               0) AS trending_velocity
        FROM post_engagement pe
        LEFT JOIN post_likes pl ON pe.post_id = pl.post_id
        LEFT JOIN post_comments pc ON pe.post_id = pc.post_id
        LEFT JOIN recent_engagement re ON pe.post_id = re.post_id
        """

        recent_start = (reference_time - pd.Timedelta(hours=24)).isoformat()

        try:
            result = self.client.query(
                query,
                parameters={
                    "post_ids": post_ids,
                    "recent_start": recent_start,
                }
            )
            return pd.DataFrame(result.result_rows, columns=result.column_names)
        except Exception as e:
            logger.warning(f"Failed to compute content features: {e}")
            return pd.DataFrame()

    def compute_interaction_features(
        self,
        user_ids: List[str],
        author_ids: List[str],
    ) -> pd.DataFrame:
        """
        Compute user-author interaction features.

        Interaction Features (4 dimensions):
        1. user_author_affinity - Computed affinity score
        2. interaction_count - Total interactions with author
        3. like_ratio - Likes / views for this author's content
        4. avg_completion_for_author - Avg completion rate for author's content
        """
        if not user_ids or not author_ids:
            return pd.DataFrame()

        # Create user-author pairs
        pairs = list(zip(user_ids, author_ids))
        unique_pairs = list(set(pairs))

        if not unique_pairs:
            return pd.DataFrame()

        query = """
        WITH pair_interactions AS (
            SELECT
                user_id,
                author_id,
                count() AS interaction_count,
                avg(completion_rate) AS avg_completion_for_author,
                countIf(completion_rate >= 0.7) / count() AS like_ratio
            FROM watch_events we
            INNER JOIN (
                SELECT content_id, author_id FROM posts_cdc WHERE is_deleted = 0
            ) p ON we.content_id = p.content_id
            WHERE (user_id, author_id) IN %(pairs)s
            GROUP BY user_id, author_id
        )
        SELECT
            user_id,
            author_id,
            interaction_count,
            avg_completion_for_author,
            like_ratio,
            -- Affinity score: weighted combination
            (0.5 * least(interaction_count / 10.0, 1.0) +
             0.3 * avg_completion_for_author +
             0.2 * like_ratio) AS user_author_affinity
        FROM pair_interactions
        """

        try:
            result = self.client.query(
                query,
                parameters={"pairs": unique_pairs}
            )
            return pd.DataFrame(result.result_rows, columns=result.column_names)
        except Exception as e:
            logger.warning(f"Failed to compute interaction features: {e}")
            return pd.DataFrame()


class SimilarityComputer:
    """
    Compute item and user similarities for CF recall strategies.
    """

    def __init__(self, clickhouse_client):
        self.client = clickhouse_client

    def compute_item_similarity_batch(
        self,
        min_co_interactions: int = 5,
        min_jaccard: float = 0.05,
        top_k: int = 50,
    ) -> pd.DataFrame:
        """
        Compute item-item similarity based on co-interaction patterns.

        Similarity = Jaccard(users who interacted with item A, users who interacted with item B)
        """
        query = """
        WITH item_users AS (
            SELECT
                content_id AS item_id,
                groupArray(user_id) AS users,
                length(groupArray(user_id)) AS user_count
            FROM (
                SELECT DISTINCT content_id, user_id
                FROM watch_events
                WHERE completion_rate >= 0.5
                  AND event_date >= today() - 30
            )
            GROUP BY content_id
            HAVING user_count >= 10
        ),
        item_pairs AS (
            SELECT
                a.item_id AS item_a,
                b.item_id AS item_b,
                length(arrayIntersect(a.users, b.users)) AS intersection_size,
                length(arrayUnion(a.users, b.users)) AS union_size,
                a.user_count AS a_count,
                b.user_count AS b_count
            FROM item_users a
            CROSS JOIN item_users b
            WHERE a.item_id < b.item_id
        )
        SELECT
            item_a AS item_id,
            item_b AS similar_item_id,
            intersection_size AS co_interaction_count,
            intersection_size / union_size AS jaccard_score,
            -- Cosine similarity approximation
            intersection_size / sqrt(a_count * b_count) AS cosine_score,
            -- Combined similarity
            0.6 * (intersection_size / union_size) + 0.4 * (intersection_size / sqrt(a_count * b_count)) AS similarity_score
        FROM item_pairs
        WHERE intersection_size >= %(min_co_interactions)s
          AND intersection_size / union_size >= %(min_jaccard)s
        ORDER BY item_a, similarity_score DESC
        """

        try:
            result = self.client.query(
                query,
                parameters={
                    "min_co_interactions": min_co_interactions,
                    "min_jaccard": min_jaccard,
                }
            )
            df = pd.DataFrame(result.result_rows, columns=result.column_names)

            # Take top-k per item
            df = df.groupby('item_id').head(top_k)

            logger.info(f"Computed {len(df)} item similarity pairs")
            return df

        except Exception as e:
            logger.error(f"Failed to compute item similarity: {e}")
            return pd.DataFrame()

    def compute_user_similarity_batch(
        self,
        min_common_items: int = 5,
        min_jaccard: float = 0.05,
        top_k: int = 30,
    ) -> pd.DataFrame:
        """
        Compute user-user similarity based on behavior patterns.

        Similarity based on:
        - Common items interacted with
        - Common authors followed/liked
        """
        query = """
        WITH user_items AS (
            SELECT
                user_id,
                groupArray(content_id) AS items,
                length(groupArray(content_id)) AS item_count
            FROM (
                SELECT DISTINCT user_id, content_id
                FROM watch_events
                WHERE completion_rate >= 0.5
                  AND event_date >= today() - 30
            )
            GROUP BY user_id
            HAVING item_count >= 10
        ),
        user_pairs AS (
            SELECT
                a.user_id AS user_a,
                b.user_id AS user_b,
                length(arrayIntersect(a.items, b.items)) AS common_items,
                length(arrayUnion(a.items, b.items)) AS union_items,
                a.item_count AS a_count,
                b.item_count AS b_count
            FROM user_items a
            CROSS JOIN user_items b
            WHERE a.user_id < b.user_id
        )
        SELECT
            user_a AS user_id,
            user_b AS similar_user_id,
            common_items AS common_items_count,
            common_items / union_items AS jaccard_score,
            common_items / sqrt(a_count * b_count) AS cosine_score,
            0.6 * (common_items / union_items) + 0.4 * (common_items / sqrt(a_count * b_count)) AS similarity_score
        FROM user_pairs
        WHERE common_items >= %(min_common_items)s
          AND common_items / union_items >= %(min_jaccard)s
        ORDER BY user_a, similarity_score DESC
        """

        try:
            result = self.client.query(
                query,
                parameters={
                    "min_common_items": min_common_items,
                    "min_jaccard": min_jaccard,
                }
            )
            df = pd.DataFrame(result.result_rows, columns=result.column_names)

            # Take top-k per user
            df = df.groupby('user_id').head(top_k)

            logger.info(f"Computed {len(df)} user similarity pairs")
            return df

        except Exception as e:
            logger.error(f"Failed to compute user similarity: {e}")
            return pd.DataFrame()

    def sync_to_clickhouse(
        self,
        item_similarity_df: pd.DataFrame,
        user_similarity_df: pd.DataFrame,
    ):
        """
        Insert computed similarities into ClickHouse tables.
        """
        if not item_similarity_df.empty:
            # Prepare item similarity data
            item_data = item_similarity_df[[
                'item_id', 'similar_item_id', 'similarity_score',
                'co_interaction_count', 'jaccard_score', 'cosine_score'
            ]].copy()
            item_data['similarity_type'] = 'co_interaction'
            item_data['computed_at'] = datetime.now()
            item_data['version'] = int(datetime.now().timestamp())

            self.client.insert(
                'item_similarity',
                item_data.values.tolist(),
                column_names=item_data.columns.tolist(),
            )
            logger.info(f"Inserted {len(item_data)} item similarity records")

        if not user_similarity_df.empty:
            # Prepare user similarity data
            user_data = user_similarity_df[[
                'user_id', 'similar_user_id', 'similarity_score',
                'common_items_count', 'jaccard_score', 'cosine_score'
            ]].copy()
            user_data.columns = [
                'user_id', 'similar_user_id', 'similarity_score',
                'common_items_count', 'jaccard_score', 'cosine_score'
            ]
            user_data['similarity_type'] = 'behavior'
            user_data['common_authors_count'] = 0  # To be computed separately
            user_data['computed_at'] = datetime.now()
            user_data['version'] = int(datetime.now().timestamp())

            self.client.insert(
                'user_similarity',
                user_data.values.tolist(),
                column_names=user_data.columns.tolist(),
            )
            logger.info(f"Inserted {len(user_data)} user similarity records")


def compute_feature_vector(features: Dict) -> np.ndarray:
    """
    Convert feature dict to numpy array for model input.

    Expected 30-dimensional vector:
    - User features: 8
    - Content features: 10
    - Author features: 5
    - Interaction features: 4
    - Context features: 3
    """
    vector = np.zeros(30, dtype=np.float32)

    # User features [0-7]
    vector[0] = features.get('user_follower_count', 0) / 10000  # Normalized
    vector[1] = features.get('user_following_count', 0) / 1000
    vector[2] = features.get('user_post_count', 0) / 100
    vector[3] = features.get('user_avg_session_length', 0) / 3600  # In hours
    vector[4] = features.get('user_active_days_30d', 0) / 30
    vector[5] = features.get('avg_daily_watch_time', 0) / 3600000  # In hours
    vector[6] = features.get('content_type_preference', 0)
    vector[7] = features.get('avg_interaction_rate', 0)

    # Content features [8-17]
    vector[8] = min(features.get('post_age_hours', 0) / 168, 1.0)  # Max 1 week
    vector[9] = features.get('post_like_count', 0) / 10000
    vector[10] = features.get('post_comment_count', 0) / 1000
    vector[11] = features.get('post_view_count', 0) / 100000
    vector[12] = features.get('post_completion_rate', 0)
    vector[13] = features.get('post_engagement_rate', 0)
    vector[14] = features.get('content_duration_ms', 0) / 60000  # In minutes
    vector[15] = features.get('has_music', 0)
    vector[16] = features.get('is_original', 1)
    vector[17] = features.get('trending_velocity', 0)

    # Author features [18-22]
    vector[18] = features.get('author_follower_count', 0) / 100000
    vector[19] = features.get('author_avg_engagement', 0)
    vector[20] = features.get('author_post_frequency', 0) / 10  # Posts per day
    vector[21] = features.get('author_content_quality', 0)
    vector[22] = features.get('author_response_rate', 0)

    # Interaction features [23-26]
    vector[23] = features.get('user_author_affinity', 0)
    vector[24] = features.get('user_author_interaction_count', 0) / 100
    vector[25] = features.get('like_ratio', 0)
    vector[26] = features.get('avg_completion_for_author', 0)

    # Context features [27-29]
    vector[27] = features.get('hour_of_day', 12) / 24
    vector[28] = features.get('day_of_week', 3) / 7
    vector[29] = features.get('is_weekend', 0)

    return vector


def get_feature_names() -> List[str]:
    """
    Return list of feature names in order.
    """
    return [
        # User features
        'user_follower_count', 'user_following_count', 'user_post_count',
        'user_avg_session_length', 'user_active_days_30d', 'avg_daily_watch_time',
        'content_type_preference', 'avg_interaction_rate',
        # Content features
        'post_age_hours', 'post_like_count', 'post_comment_count', 'post_view_count',
        'post_completion_rate', 'post_engagement_rate', 'content_duration_ms',
        'has_music', 'is_original', 'trending_velocity',
        # Author features
        'author_follower_count', 'author_avg_engagement', 'author_post_frequency',
        'author_content_quality', 'author_response_rate',
        # Interaction features
        'user_author_affinity', 'user_author_interaction_count',
        'like_ratio', 'avg_completion_for_author',
        # Context features
        'hour_of_day', 'day_of_week', 'is_weekend',
    ]
