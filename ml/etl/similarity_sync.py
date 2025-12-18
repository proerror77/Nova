#!/usr/bin/env python3
"""
Similarity Sync Job for Nova Recommendation System (P1-3)

Syncs pre-computed item and user similarities from ClickHouse to Redis
for real-time use by Item-CF and User-CF recall strategies.

Redis Data Structures:
- item:similar:{post_id} -> Sorted Set (similar_item_id -> similarity_score)
- user:similar:{user_id} -> Sorted Set (similar_user_id -> similarity_score)
- user:recent_items:{user_id} -> Sorted Set (post_id -> timestamp)

Usage:
    python similarity_sync.py --type item --batch-size 1000
    python similarity_sync.py --type user --batch-size 500
    python similarity_sync.py --type all
"""

import argparse
import logging
import os
from datetime import datetime
from typing import Dict, List, Tuple

import clickhouse_connect
import redis
from redis import Redis

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SimilaritySync:
    """
    Synchronize similarity data from ClickHouse to Redis.
    """

    # Redis key prefixes (must match ranking-service constants)
    ITEM_SIMILAR_KEY = "item:similar:"
    USER_SIMILAR_KEY = "user:similar:"
    USER_RECENT_ITEMS_KEY = "user:recent_items:"

    # TTL settings (seconds)
    ITEM_SIMILAR_TTL = 86400 * 7   # 7 days
    USER_SIMILAR_TTL = 86400 * 7   # 7 days
    USER_RECENT_TTL = 86400 * 30   # 30 days

    def __init__(
        self,
        clickhouse_host: str = "localhost",
        clickhouse_port: int = 8123,
        clickhouse_database: str = "nova_feed",
        clickhouse_user: str = "default",
        clickhouse_password: str = "",
        redis_host: str = "localhost",
        redis_port: int = 6379,
        redis_db: int = 0,
        redis_password: str = None,
    ):
        # ClickHouse connection
        self.ch_client = clickhouse_connect.get_client(
            host=clickhouse_host,
            port=clickhouse_port,
            database=clickhouse_database,
            username=clickhouse_user,
            password=clickhouse_password,
        )
        logger.info(f"Connected to ClickHouse: {clickhouse_host}:{clickhouse_port}/{clickhouse_database}")

        # Redis connection
        self.redis_client = Redis(
            host=redis_host,
            port=redis_port,
            db=redis_db,
            password=redis_password,
            decode_responses=True,
        )
        self.redis_client.ping()
        logger.info(f"Connected to Redis: {redis_host}:{redis_port}/{redis_db}")

    def sync_item_similarity(
        self,
        batch_size: int = 1000,
        top_k: int = 50,
    ) -> Dict:
        """
        Sync item similarity from ClickHouse to Redis.

        Args:
            batch_size: Number of items to process per batch
            top_k: Maximum similar items per item

        Returns:
            Statistics dict
        """
        logger.info("Starting item similarity sync...")

        # Query distinct items with similarity data
        count_query = """
        SELECT count(DISTINCT item_id) AS item_count
        FROM item_similarity FINAL
        """
        count_result = self.ch_client.query(count_query)
        total_items = count_result.result_rows[0][0]
        logger.info(f"Total items with similarity data: {total_items}")

        # Process in batches
        stats = {"items_processed": 0, "pairs_synced": 0, "errors": 0}
        offset = 0

        while offset < total_items:
            query = """
            SELECT
                item_id,
                groupArray(%(top_k)s)(similar_item_id) AS similar_items,
                groupArray(%(top_k)s)(similarity_score) AS scores
            FROM (
                SELECT
                    item_id,
                    similar_item_id,
                    similarity_score,
                    row_number() OVER (PARTITION BY item_id ORDER BY similarity_score DESC) AS rn
                FROM item_similarity FINAL
            )
            WHERE rn <= %(top_k)s
            GROUP BY item_id
            ORDER BY item_id
            LIMIT %(batch_size)s OFFSET %(offset)s
            """

            try:
                result = self.ch_client.query(
                    query,
                    parameters={
                        "top_k": top_k,
                        "batch_size": batch_size,
                        "offset": offset,
                    }
                )

                # Use pipeline for batch Redis writes
                pipe = self.redis_client.pipeline()

                for row in result.result_rows:
                    item_id, similar_items, scores = row

                    key = f"{self.ITEM_SIMILAR_KEY}{item_id}"

                    # Delete existing and add new
                    pipe.delete(key)

                    if similar_items and scores:
                        # Create score mapping
                        score_mapping = {
                            similar_items[i]: scores[i]
                            for i in range(len(similar_items))
                        }
                        pipe.zadd(key, score_mapping)
                        pipe.expire(key, self.ITEM_SIMILAR_TTL)
                        stats["pairs_synced"] += len(similar_items)

                    stats["items_processed"] += 1

                pipe.execute()
                logger.info(f"Processed items {offset} - {offset + len(result.result_rows)}")

            except Exception as e:
                logger.error(f"Error processing batch at offset {offset}: {e}")
                stats["errors"] += 1

            offset += batch_size

        logger.info(f"Item similarity sync complete: {stats}")
        return stats

    def sync_user_similarity(
        self,
        batch_size: int = 500,
        top_k: int = 30,
    ) -> Dict:
        """
        Sync user similarity from ClickHouse to Redis.

        Args:
            batch_size: Number of users to process per batch
            top_k: Maximum similar users per user

        Returns:
            Statistics dict
        """
        logger.info("Starting user similarity sync...")

        # Query distinct users with similarity data
        count_query = """
        SELECT count(DISTINCT user_id) AS user_count
        FROM user_similarity FINAL
        """
        count_result = self.ch_client.query(count_query)
        total_users = count_result.result_rows[0][0]
        logger.info(f"Total users with similarity data: {total_users}")

        # Process in batches
        stats = {"users_processed": 0, "pairs_synced": 0, "errors": 0}
        offset = 0

        while offset < total_users:
            query = """
            SELECT
                user_id,
                groupArray(%(top_k)s)(similar_user_id) AS similar_users,
                groupArray(%(top_k)s)(similarity_score) AS scores
            FROM (
                SELECT
                    user_id,
                    similar_user_id,
                    similarity_score,
                    row_number() OVER (PARTITION BY user_id ORDER BY similarity_score DESC) AS rn
                FROM user_similarity FINAL
            )
            WHERE rn <= %(top_k)s
            GROUP BY user_id
            ORDER BY user_id
            LIMIT %(batch_size)s OFFSET %(offset)s
            """

            try:
                result = self.ch_client.query(
                    query,
                    parameters={
                        "top_k": top_k,
                        "batch_size": batch_size,
                        "offset": offset,
                    }
                )

                pipe = self.redis_client.pipeline()

                for row in result.result_rows:
                    user_id, similar_users, scores = row

                    key = f"{self.USER_SIMILAR_KEY}{user_id}"

                    pipe.delete(key)

                    if similar_users and scores:
                        score_mapping = {
                            similar_users[i]: scores[i]
                            for i in range(len(similar_users))
                        }
                        pipe.zadd(key, score_mapping)
                        pipe.expire(key, self.USER_SIMILAR_TTL)
                        stats["pairs_synced"] += len(similar_users)

                    stats["users_processed"] += 1

                pipe.execute()
                logger.info(f"Processed users {offset} - {offset + len(result.result_rows)}")

            except Exception as e:
                logger.error(f"Error processing batch at offset {offset}: {e}")
                stats["errors"] += 1

            offset += batch_size

        logger.info(f"User similarity sync complete: {stats}")
        return stats

    def sync_user_recent_items(
        self,
        batch_size: int = 1000,
        lookback_days: int = 7,
        max_items_per_user: int = 50,
    ) -> Dict:
        """
        Sync user recent items from ClickHouse to Redis.

        This populates the seed items for Item-CF recall.

        Args:
            batch_size: Number of users to process per batch
            lookback_days: Days of history to consider
            max_items_per_user: Maximum recent items per user

        Returns:
            Statistics dict
        """
        logger.info("Starting user recent items sync...")

        # Query distinct active users
        count_query = """
        SELECT count(DISTINCT user_id) AS user_count
        FROM user_recent_items FINAL
        WHERE interaction_time >= now() - INTERVAL %(lookback_days)s DAY
        """
        count_result = self.ch_client.query(
            count_query,
            parameters={"lookback_days": lookback_days}
        )
        total_users = count_result.result_rows[0][0]
        logger.info(f"Total active users: {total_users}")

        stats = {"users_processed": 0, "items_synced": 0, "errors": 0}
        offset = 0

        while offset < total_users:
            query = """
            SELECT
                user_id,
                groupArray(%(max_items)s)(post_id) AS items,
                groupArray(%(max_items)s)(toUnixTimestamp(interaction_time)) AS timestamps
            FROM (
                SELECT
                    user_id,
                    post_id,
                    interaction_time,
                    row_number() OVER (PARTITION BY user_id ORDER BY interaction_time DESC) AS rn
                FROM user_recent_items FINAL
                WHERE interaction_time >= now() - INTERVAL %(lookback_days)s DAY
            )
            WHERE rn <= %(max_items)s
            GROUP BY user_id
            ORDER BY user_id
            LIMIT %(batch_size)s OFFSET %(offset)s
            """

            try:
                result = self.ch_client.query(
                    query,
                    parameters={
                        "max_items": max_items_per_user,
                        "lookback_days": lookback_days,
                        "batch_size": batch_size,
                        "offset": offset,
                    }
                )

                pipe = self.redis_client.pipeline()

                for row in result.result_rows:
                    user_id, items, timestamps = row

                    key = f"{self.USER_RECENT_ITEMS_KEY}{user_id}"

                    pipe.delete(key)

                    if items and timestamps:
                        score_mapping = {
                            items[i]: timestamps[i]
                            for i in range(len(items))
                        }
                        pipe.zadd(key, score_mapping)
                        pipe.expire(key, self.USER_RECENT_TTL)
                        stats["items_synced"] += len(items)

                    stats["users_processed"] += 1

                pipe.execute()
                logger.info(f"Processed users {offset} - {offset + len(result.result_rows)}")

            except Exception as e:
                logger.error(f"Error processing batch at offset {offset}: {e}")
                stats["errors"] += 1

            offset += batch_size

        logger.info(f"User recent items sync complete: {stats}")
        return stats

    def get_sync_stats(self) -> Dict:
        """
        Get current sync statistics from Redis.
        """
        stats = {}

        # Count item similarity keys
        item_keys = self.redis_client.keys(f"{self.ITEM_SIMILAR_KEY}*")
        stats["item_similarity_keys"] = len(item_keys)

        # Count user similarity keys
        user_keys = self.redis_client.keys(f"{self.USER_SIMILAR_KEY}*")
        stats["user_similarity_keys"] = len(user_keys)

        # Count user recent items keys
        recent_keys = self.redis_client.keys(f"{self.USER_RECENT_ITEMS_KEY}*")
        stats["user_recent_items_keys"] = len(recent_keys)

        # Sample sizes
        if item_keys:
            sample_key = item_keys[0]
            stats["sample_item_similar_count"] = self.redis_client.zcard(sample_key)

        if user_keys:
            sample_key = user_keys[0]
            stats["sample_user_similar_count"] = self.redis_client.zcard(sample_key)

        return stats


def main():
    parser = argparse.ArgumentParser(description="Similarity Sync Job")
    parser.add_argument(
        "--type",
        type=str,
        choices=["item", "user", "recent", "all"],
        default="all",
        help="Type of similarity to sync"
    )
    parser.add_argument("--batch-size", type=int, default=1000, help="Batch size")
    parser.add_argument("--top-k", type=int, default=50, help="Top-K similar items/users")
    parser.add_argument("--lookback-days", type=int, default=7, help="Days of history for recent items")

    # ClickHouse settings
    parser.add_argument("--clickhouse-host", type=str, default=os.getenv("CLICKHOUSE_HOST", "localhost"))
    parser.add_argument("--clickhouse-port", type=int, default=int(os.getenv("CLICKHOUSE_PORT", "8123")))
    parser.add_argument("--clickhouse-database", type=str, default=os.getenv("CLICKHOUSE_DATABASE", "nova_feed"))
    parser.add_argument("--clickhouse-user", type=str, default=os.getenv("CLICKHOUSE_USER", "default"))
    parser.add_argument("--clickhouse-password", type=str, default=os.getenv("CLICKHOUSE_PASSWORD", ""))

    # Redis settings
    parser.add_argument("--redis-host", type=str, default=os.getenv("REDIS_HOST", "localhost"))
    parser.add_argument("--redis-port", type=int, default=int(os.getenv("REDIS_PORT", "6379")))
    parser.add_argument("--redis-db", type=int, default=int(os.getenv("REDIS_DB", "0")))
    parser.add_argument("--redis-password", type=str, default=os.getenv("REDIS_PASSWORD", None))

    args = parser.parse_args()

    sync = SimilaritySync(
        clickhouse_host=args.clickhouse_host,
        clickhouse_port=args.clickhouse_port,
        clickhouse_database=args.clickhouse_database,
        clickhouse_user=args.clickhouse_user,
        clickhouse_password=args.clickhouse_password,
        redis_host=args.redis_host,
        redis_port=args.redis_port,
        redis_db=args.redis_db,
        redis_password=args.redis_password,
    )

    results = {}

    if args.type in ["item", "all"]:
        results["item_similarity"] = sync.sync_item_similarity(
            batch_size=args.batch_size,
            top_k=args.top_k,
        )

    if args.type in ["user", "all"]:
        results["user_similarity"] = sync.sync_user_similarity(
            batch_size=args.batch_size,
            top_k=min(args.top_k, 30),  # Cap user similarity at 30
        )

    if args.type in ["recent", "all"]:
        results["user_recent_items"] = sync.sync_user_recent_items(
            batch_size=args.batch_size,
            lookback_days=args.lookback_days,
        )

    # Print final stats
    print("\n=== Sync Results ===")
    for sync_type, stats in results.items():
        print(f"\n{sync_type}:")
        for key, value in stats.items():
            print(f"  {key}: {value}")

    print("\n=== Redis Stats ===")
    redis_stats = sync.get_sync_stats()
    for key, value in redis_stats.items():
        print(f"  {key}: {value}")


if __name__ == "__main__":
    main()
