#!/usr/bin/env python3
"""
Similarity Computation Job for Nova Recommendation System (P1-3)

Computes item-item and user-user similarities from interaction data
and stores results in ClickHouse for later sync to Redis.

This is a batch job that should run periodically (e.g., daily).

Usage:
    python compute_similarity.py --type item --min-interactions 10
    python compute_similarity.py --type user --min-common-items 5
    python compute_similarity.py --type all
"""

import argparse
import logging
import os
from datetime import datetime
from typing import Dict

import clickhouse_connect

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SimilarityComputer:
    """
    Batch computation of item and user similarities.
    """

    def __init__(
        self,
        clickhouse_host: str = "localhost",
        clickhouse_port: int = 8123,
        clickhouse_database: str = "nova_feed",
        clickhouse_user: str = "default",
        clickhouse_password: str = "",
    ):
        self.client = clickhouse_connect.get_client(
            host=clickhouse_host,
            port=clickhouse_port,
            database=clickhouse_database,
            username=clickhouse_user,
            password=clickhouse_password,
        )
        logger.info(f"Connected to ClickHouse: {clickhouse_host}:{clickhouse_port}/{clickhouse_database}")

    def compute_item_similarity(
        self,
        lookback_days: int = 30,
        min_user_interactions: int = 10,
        min_co_interactions: int = 5,
        min_jaccard: float = 0.05,
        top_k_per_item: int = 100,
    ) -> Dict:
        """
        Compute item-item similarity based on co-interaction patterns.

        Algorithm:
        1. Build item-user interaction matrix (users who engaged with each item)
        2. Compute Jaccard similarity for item pairs
        3. Compute Cosine similarity for item pairs
        4. Store combined similarity score

        Args:
            lookback_days: Days of interaction history to consider
            min_user_interactions: Minimum users per item
            min_co_interactions: Minimum co-interactions for valid pair
            min_jaccard: Minimum Jaccard score threshold
            top_k_per_item: Maximum similar items per item

        Returns:
            Statistics dict
        """
        logger.info("Computing item similarity...")

        # Step 1: Clear old similarity data (older than computation window)
        clear_query = """
        ALTER TABLE item_similarity DELETE
        WHERE computed_at < now() - INTERVAL 2 DAY
        """
        try:
            self.client.command(clear_query)
            logger.info("Cleared old item similarity data")
        except Exception as e:
            logger.warning(f"Could not clear old data: {e}")

        # Step 2: Compute and insert new similarities
        compute_query = """
        INSERT INTO item_similarity (
            item_id, similar_item_id, similarity_score, similarity_type,
            co_interaction_count, jaccard_score, cosine_score, computed_at, version
        )
        WITH
        -- Build item-user sets
        item_users AS (
            SELECT
                content_id AS item_id,
                groupUniqArray(user_id) AS users,
                count(DISTINCT user_id) AS user_count
            FROM watch_events
            WHERE event_date >= today() - %(lookback_days)s
              AND completion_rate >= 0.5
            GROUP BY content_id
            HAVING user_count >= %(min_user_interactions)s
        ),
        -- Compute pairwise similarities
        item_pairs AS (
            SELECT
                a.item_id AS item_a,
                b.item_id AS item_b,
                length(arrayIntersect(a.users, b.users)) AS intersection_size,
                length(arrayDistinct(arrayConcat(a.users, b.users))) AS union_size,
                a.user_count AS a_count,
                b.user_count AS b_count
            FROM item_users a
            INNER JOIN item_users b ON a.item_id < b.item_id
            WHERE length(arrayIntersect(a.users, b.users)) >= %(min_co_interactions)s
        ),
        -- Calculate scores
        scored_pairs AS (
            SELECT
                item_a,
                item_b,
                intersection_size,
                intersection_size / union_size AS jaccard,
                intersection_size / sqrt(a_count * b_count) AS cosine,
                -- Combined score with Jaccard weighted more
                0.6 * (intersection_size / union_size) +
                0.4 * (intersection_size / sqrt(a_count * b_count)) AS combined_score
            FROM item_pairs
            WHERE intersection_size / union_size >= %(min_jaccard)s
        ),
        -- Rank and limit per item (both directions)
        ranked AS (
            SELECT
                item_a AS item_id,
                item_b AS similar_item_id,
                combined_score,
                intersection_size,
                jaccard,
                cosine,
                row_number() OVER (PARTITION BY item_a ORDER BY combined_score DESC) AS rn
            FROM scored_pairs

            UNION ALL

            SELECT
                item_b AS item_id,
                item_a AS similar_item_id,
                combined_score,
                intersection_size,
                jaccard,
                cosine,
                row_number() OVER (PARTITION BY item_b ORDER BY combined_score DESC) AS rn
            FROM scored_pairs
        )
        SELECT
            item_id,
            similar_item_id,
            combined_score AS similarity_score,
            'co_interaction' AS similarity_type,
            intersection_size AS co_interaction_count,
            jaccard AS jaccard_score,
            cosine AS cosine_score,
            now() AS computed_at,
            toUnixTimestamp(now()) AS version
        FROM ranked
        WHERE rn <= %(top_k)s
        """

        try:
            self.client.command(
                compute_query,
                parameters={
                    "lookback_days": lookback_days,
                    "min_user_interactions": min_user_interactions,
                    "min_co_interactions": min_co_interactions,
                    "min_jaccard": min_jaccard,
                    "top_k": top_k_per_item,
                }
            )

            # Get statistics
            stats_query = """
            SELECT
                count() AS total_pairs,
                count(DISTINCT item_id) AS unique_items,
                avg(similarity_score) AS avg_similarity,
                max(similarity_score) AS max_similarity
            FROM item_similarity
            WHERE computed_at >= now() - INTERVAL 1 HOUR
            """
            stats_result = self.client.query(stats_query)
            stats = dict(zip(stats_result.column_names, stats_result.result_rows[0]))

            logger.info(f"Item similarity computed: {stats}")
            return stats

        except Exception as e:
            logger.error(f"Failed to compute item similarity: {e}")
            return {"error": str(e)}

    def compute_user_similarity(
        self,
        lookback_days: int = 30,
        min_item_interactions: int = 10,
        min_common_items: int = 5,
        min_jaccard: float = 0.05,
        top_k_per_user: int = 50,
    ) -> Dict:
        """
        Compute user-user similarity based on behavior patterns.

        Algorithm:
        1. Build user-item interaction matrix
        2. Compute Jaccard similarity for user pairs
        3. Store combined similarity score

        Args:
            lookback_days: Days of history to consider
            min_item_interactions: Minimum items per user
            min_common_items: Minimum common items for valid pair
            min_jaccard: Minimum Jaccard score threshold
            top_k_per_user: Maximum similar users per user

        Returns:
            Statistics dict
        """
        logger.info("Computing user similarity...")

        # Clear old data
        clear_query = """
        ALTER TABLE user_similarity DELETE
        WHERE computed_at < now() - INTERVAL 2 DAY
        """
        try:
            self.client.command(clear_query)
            logger.info("Cleared old user similarity data")
        except Exception as e:
            logger.warning(f"Could not clear old data: {e}")

        # Compute and insert
        compute_query = """
        INSERT INTO user_similarity (
            user_id, similar_user_id, similarity_score, similarity_type,
            common_items_count, common_authors_count, jaccard_score, cosine_score,
            computed_at, version
        )
        WITH
        -- Build user-item sets
        user_items AS (
            SELECT
                user_id,
                groupUniqArray(content_id) AS items,
                count(DISTINCT content_id) AS item_count
            FROM watch_events
            WHERE event_date >= today() - %(lookback_days)s
              AND completion_rate >= 0.5
            GROUP BY user_id
            HAVING item_count >= %(min_item_interactions)s
        ),
        -- Compute pairwise similarities
        user_pairs AS (
            SELECT
                a.user_id AS user_a,
                b.user_id AS user_b,
                length(arrayIntersect(a.items, b.items)) AS common_items,
                length(arrayDistinct(arrayConcat(a.items, b.items))) AS union_items,
                a.item_count AS a_count,
                b.item_count AS b_count
            FROM user_items a
            INNER JOIN user_items b ON a.user_id < b.user_id
            WHERE length(arrayIntersect(a.items, b.items)) >= %(min_common_items)s
        ),
        -- Calculate scores
        scored_pairs AS (
            SELECT
                user_a,
                user_b,
                common_items,
                common_items / union_items AS jaccard,
                common_items / sqrt(a_count * b_count) AS cosine,
                0.6 * (common_items / union_items) +
                0.4 * (common_items / sqrt(a_count * b_count)) AS combined_score
            FROM user_pairs
            WHERE common_items / union_items >= %(min_jaccard)s
        ),
        -- Rank and limit (both directions)
        ranked AS (
            SELECT
                user_a AS user_id,
                user_b AS similar_user_id,
                combined_score,
                common_items,
                jaccard,
                cosine,
                row_number() OVER (PARTITION BY user_a ORDER BY combined_score DESC) AS rn
            FROM scored_pairs

            UNION ALL

            SELECT
                user_b AS user_id,
                user_a AS similar_user_id,
                combined_score,
                common_items,
                jaccard,
                cosine,
                row_number() OVER (PARTITION BY user_b ORDER BY combined_score DESC) AS rn
            FROM scored_pairs
        )
        SELECT
            user_id,
            similar_user_id,
            combined_score AS similarity_score,
            'behavior' AS similarity_type,
            common_items AS common_items_count,
            0 AS common_authors_count,
            jaccard AS jaccard_score,
            cosine AS cosine_score,
            now() AS computed_at,
            toUnixTimestamp(now()) AS version
        FROM ranked
        WHERE rn <= %(top_k)s
        """

        try:
            self.client.command(
                compute_query,
                parameters={
                    "lookback_days": lookback_days,
                    "min_item_interactions": min_item_interactions,
                    "min_common_items": min_common_items,
                    "min_jaccard": min_jaccard,
                    "top_k": top_k_per_user,
                }
            )

            # Get statistics
            stats_query = """
            SELECT
                count() AS total_pairs,
                count(DISTINCT user_id) AS unique_users,
                avg(similarity_score) AS avg_similarity,
                max(similarity_score) AS max_similarity
            FROM user_similarity
            WHERE computed_at >= now() - INTERVAL 1 HOUR
            """
            stats_result = self.client.query(stats_query)
            stats = dict(zip(stats_result.column_names, stats_result.result_rows[0]))

            logger.info(f"User similarity computed: {stats}")
            return stats

        except Exception as e:
            logger.error(f"Failed to compute user similarity: {e}")
            return {"error": str(e)}

    def update_user_recent_items(
        self,
        lookback_days: int = 7,
    ) -> Dict:
        """
        Update user_recent_items table from watch_events and likes.

        This provides seed items for Item-CF recall.
        """
        logger.info("Updating user recent items...")

        # Insert from watch events (high completion)
        watch_query = """
        INSERT INTO user_recent_items (
            user_id, post_id, interaction_type, interaction_time, interaction_weight, version
        )
        SELECT
            user_id,
            content_id AS post_id,
            if(completion_rate >= 0.9, 'complete', 'view') AS interaction_type,
            event_time AS interaction_time,
            completion_rate AS interaction_weight,
            toUnixTimestamp(event_time) AS version
        FROM watch_events
        WHERE event_date >= today() - %(lookback_days)s
          AND completion_rate >= 0.5
        """

        try:
            self.client.command(
                watch_query,
                parameters={"lookback_days": lookback_days}
            )

            # Get statistics
            stats_query = """
            SELECT
                count() AS total_interactions,
                count(DISTINCT user_id) AS unique_users,
                count(DISTINCT post_id) AS unique_posts
            FROM user_recent_items
            WHERE interaction_time >= now() - INTERVAL %(lookback_days)s DAY
            """
            stats_result = self.client.query(
                stats_query,
                parameters={"lookback_days": lookback_days}
            )
            stats = dict(zip(stats_result.column_names, stats_result.result_rows[0]))

            logger.info(f"User recent items updated: {stats}")
            return stats

        except Exception as e:
            logger.error(f"Failed to update user recent items: {e}")
            return {"error": str(e)}


def main():
    parser = argparse.ArgumentParser(description="Similarity Computation Job")
    parser.add_argument(
        "--type",
        type=str,
        choices=["item", "user", "recent", "all"],
        default="all",
        help="Type of similarity to compute"
    )
    parser.add_argument("--lookback-days", type=int, default=30, help="Days of history")
    parser.add_argument("--min-interactions", type=int, default=10, help="Min interactions per item/user")
    parser.add_argument("--min-co-interactions", type=int, default=5, help="Min co-interactions for pairs")
    parser.add_argument("--min-jaccard", type=float, default=0.05, help="Min Jaccard score")
    parser.add_argument("--top-k", type=int, default=100, help="Top-K similar items/users")

    # ClickHouse settings
    parser.add_argument("--clickhouse-host", type=str, default=os.getenv("CLICKHOUSE_HOST", "localhost"))
    parser.add_argument("--clickhouse-port", type=int, default=int(os.getenv("CLICKHOUSE_PORT", "8123")))
    parser.add_argument("--clickhouse-database", type=str, default=os.getenv("CLICKHOUSE_DATABASE", "nova_feed"))
    parser.add_argument("--clickhouse-user", type=str, default=os.getenv("CLICKHOUSE_USER", "default"))
    parser.add_argument("--clickhouse-password", type=str, default=os.getenv("CLICKHOUSE_PASSWORD", ""))

    args = parser.parse_args()

    computer = SimilarityComputer(
        clickhouse_host=args.clickhouse_host,
        clickhouse_port=args.clickhouse_port,
        clickhouse_database=args.clickhouse_database,
        clickhouse_user=args.clickhouse_user,
        clickhouse_password=args.clickhouse_password,
    )

    results = {}

    if args.type in ["item", "all"]:
        results["item_similarity"] = computer.compute_item_similarity(
            lookback_days=args.lookback_days,
            min_user_interactions=args.min_interactions,
            min_co_interactions=args.min_co_interactions,
            min_jaccard=args.min_jaccard,
            top_k_per_item=args.top_k,
        )

    if args.type in ["user", "all"]:
        results["user_similarity"] = computer.compute_user_similarity(
            lookback_days=args.lookback_days,
            min_item_interactions=args.min_interactions,
            min_common_items=args.min_co_interactions,
            min_jaccard=args.min_jaccard,
            top_k_per_user=min(args.top_k, 50),
        )

    if args.type in ["recent", "all"]:
        results["user_recent_items"] = computer.update_user_recent_items(
            lookback_days=7,
        )

    # Print results
    print("\n=== Computation Results ===")
    for comp_type, stats in results.items():
        print(f"\n{comp_type}:")
        for key, value in stats.items():
            print(f"  {key}: {value}")


if __name__ == "__main__":
    main()
