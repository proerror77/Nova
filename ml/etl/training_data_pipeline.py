#!/usr/bin/env python3
"""
Training Data Pipeline for Nova Recommendation System (P1-3)

This module extracts training data from ClickHouse, computes features,
and exports datasets for model training.

ETL Flow:
1. Extract impressions and interactions from ClickHouse CDC tables
2. Generate positive samples (clicks, likes, completes) and negative samples (impressions without click)
3. Join with user/content features
4. Export to Parquet for ML training

Usage:
    python training_data_pipeline.py --date 2024-01-15 --output ./data/training/
    python training_data_pipeline.py --start-date 2024-01-01 --end-date 2024-01-15 --output ./data/training/
"""

import argparse
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import clickhouse_connect
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from feature_extraction import FeatureExtractor

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class TrainingDataPipeline:
    """
    Training data pipeline for recommendation model.

    Extracts user behavior data and computes features for training.
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
        self.feature_extractor = FeatureExtractor(self.client)
        logger.info(f"Connected to ClickHouse: {clickhouse_host}:{clickhouse_port}/{clickhouse_database}")

    def extract_positive_samples(
        self,
        start_date: str,
        end_date: str,
    ) -> pd.DataFrame:
        """
        Extract positive samples from likes and high-completion watches.

        Positive samples:
        - Likes (label_type='like')
        - Watch completion >= 70% (label_type='complete')
        """
        query = """
        SELECT
            user_id,
            post_id,
            author_id,
            1 AS label,
            label_type,
            impression_time,
            click_time,
            watch_duration_ms,
            content_duration_ms,
            completion_rate,
            recall_source,
            position_in_feed,
            session_id,
            device_type,
            hour_of_day,
            day_of_week,
            event_date
        FROM training_interactions
        WHERE event_date >= %(start_date)s
          AND event_date <= %(end_date)s
          AND label = 1
        """

        logger.info(f"Extracting positive samples from {start_date} to {end_date}")

        result = self.client.query(
            query,
            parameters={"start_date": start_date, "end_date": end_date}
        )

        df = pd.DataFrame(result.result_rows, columns=result.column_names)
        logger.info(f"Extracted {len(df)} positive samples")
        return df

    def extract_negative_samples(
        self,
        start_date: str,
        end_date: str,
        negative_ratio: float = 4.0,
    ) -> pd.DataFrame:
        """
        Extract negative samples from impressions without engagement.

        Negative samples:
        - Impression without click (label_type='impression_no_click')
        - Watch completion < 30%

        Uses downsampling to control positive:negative ratio.
        """
        # First, count positive samples for ratio calculation
        count_query = """
        SELECT count() AS cnt
        FROM training_interactions
        WHERE event_date >= %(start_date)s
          AND event_date <= %(end_date)s
          AND label = 1
        """

        count_result = self.client.query(
            count_query,
            parameters={"start_date": start_date, "end_date": end_date}
        )
        positive_count = count_result.result_rows[0][0]

        # Calculate sample limit for negative samples
        negative_limit = int(positive_count * negative_ratio)

        query = """
        SELECT
            user_id,
            post_id,
            author_id,
            0 AS label,
            label_type,
            impression_time,
            click_time,
            watch_duration_ms,
            content_duration_ms,
            completion_rate,
            recall_source,
            position_in_feed,
            session_id,
            device_type,
            hour_of_day,
            day_of_week,
            event_date
        FROM training_interactions
        WHERE event_date >= %(start_date)s
          AND event_date <= %(end_date)s
          AND label = 0
        ORDER BY rand()
        LIMIT %(limit)s
        """

        logger.info(f"Extracting negative samples (ratio {negative_ratio}:1, limit {negative_limit})")

        result = self.client.query(
            query,
            parameters={
                "start_date": start_date,
                "end_date": end_date,
                "limit": negative_limit,
            }
        )

        df = pd.DataFrame(result.result_rows, columns=result.column_names)
        logger.info(f"Extracted {len(df)} negative samples")
        return df

    def join_features(
        self,
        samples: pd.DataFrame,
    ) -> pd.DataFrame:
        """
        Join samples with pre-computed features from training_features table.
        """
        if samples.empty:
            return samples

        # Get unique (user_id, post_id) pairs
        pairs = samples[['user_id', 'post_id', 'impression_time']].drop_duplicates()

        # Batch fetch features
        features_df = self.feature_extractor.get_features_batch(
            pairs['user_id'].tolist(),
            pairs['post_id'].tolist(),
            pairs['impression_time'].tolist(),
        )

        if features_df.empty:
            logger.warning("No features found, using default values")
            return samples

        # Merge on user_id and post_id
        merged = samples.merge(
            features_df,
            on=['user_id', 'post_id'],
            how='left',
        )

        logger.info(f"Joined features: {len(merged)} samples with {len(features_df.columns) - 2} features")
        return merged

    def compute_derived_features(
        self,
        df: pd.DataFrame,
    ) -> pd.DataFrame:
        """
        Compute derived features that depend on training context.
        """
        if df.empty:
            return df

        # Time-based features
        df['is_weekend'] = df['day_of_week'].isin([6, 7]).astype(int)
        df['is_morning'] = df['hour_of_day'].between(6, 11).astype(int)
        df['is_evening'] = df['hour_of_day'].between(18, 23).astype(int)
        df['is_night'] = df['hour_of_day'].between(0, 5).astype(int)

        # Position features
        df['position_bucket'] = pd.cut(
            df['position_in_feed'],
            bins=[0, 3, 10, 30, 100, float('inf')],
            labels=[0, 1, 2, 3, 4],
        ).astype(int)

        # Completion rate buckets
        df['completion_bucket'] = pd.cut(
            df['completion_rate'],
            bins=[0, 0.25, 0.5, 0.75, 0.9, 1.0],
            labels=[0, 1, 2, 3, 4],
        ).astype(int)

        # Recall source encoding
        recall_source_map = {
            '': 0,
            'graph': 1,
            'trending': 2,
            'personalized': 3,
            'item_cf': 4,
            'user_cf': 5,
        }
        df['recall_source_encoded'] = df['recall_source'].map(recall_source_map).fillna(0).astype(int)

        logger.info(f"Computed {6} derived features")
        return df

    def build_training_dataset(
        self,
        start_date: str,
        end_date: str,
        negative_ratio: float = 4.0,
    ) -> pd.DataFrame:
        """
        Build complete training dataset with all features.

        Args:
            start_date: Start date (YYYY-MM-DD)
            end_date: End date (YYYY-MM-DD)
            negative_ratio: Ratio of negative to positive samples

        Returns:
            DataFrame with samples and features
        """
        logger.info(f"Building training dataset from {start_date} to {end_date}")

        # Extract samples
        positive_samples = self.extract_positive_samples(start_date, end_date)
        negative_samples = self.extract_negative_samples(start_date, end_date, negative_ratio)

        # Combine
        all_samples = pd.concat([positive_samples, negative_samples], ignore_index=True)
        logger.info(f"Combined dataset: {len(all_samples)} samples (pos: {len(positive_samples)}, neg: {len(negative_samples)})")

        if all_samples.empty:
            logger.warning("No samples found for the date range")
            return all_samples

        # Join features
        all_samples = self.join_features(all_samples)

        # Compute derived features
        all_samples = self.compute_derived_features(all_samples)

        # Shuffle
        all_samples = all_samples.sample(frac=1, random_state=42).reset_index(drop=True)

        return all_samples

    def export_to_parquet(
        self,
        df: pd.DataFrame,
        output_path: str,
        partition_cols: Optional[List[str]] = None,
    ) -> str:
        """
        Export dataset to Parquet format.

        Args:
            df: DataFrame to export
            output_path: Output directory path
            partition_cols: Optional columns to partition by

        Returns:
            Path to exported file/directory
        """
        os.makedirs(output_path, exist_ok=True)

        if partition_cols:
            # Partitioned dataset
            table = pa.Table.from_pandas(df)
            pq.write_to_dataset(
                table,
                root_path=output_path,
                partition_cols=partition_cols,
            )
            logger.info(f"Exported partitioned dataset to {output_path}")
        else:
            # Single file
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            file_path = os.path.join(output_path, f"training_data_{timestamp}.parquet")
            df.to_parquet(file_path, index=False, compression='snappy')
            logger.info(f"Exported {len(df)} samples to {file_path}")
            return file_path

        return output_path

    def get_dataset_stats(self, df: pd.DataFrame) -> Dict:
        """
        Compute statistics for the training dataset.
        """
        if df.empty:
            return {"error": "Empty dataset"}

        stats = {
            "total_samples": len(df),
            "positive_samples": int((df['label'] == 1).sum()),
            "negative_samples": int((df['label'] == 0).sum()),
            "unique_users": df['user_id'].nunique(),
            "unique_posts": df['post_id'].nunique(),
            "date_range": {
                "start": str(df['event_date'].min()),
                "end": str(df['event_date'].max()),
            },
            "label_distribution": df['label_type'].value_counts().to_dict(),
            "recall_source_distribution": df['recall_source'].value_counts().to_dict(),
            "avg_completion_rate": float(df['completion_rate'].mean()),
            "avg_position_in_feed": float(df['position_in_feed'].mean()),
        }

        return stats

    def run_daily_pipeline(
        self,
        date: str,
        output_path: str,
        negative_ratio: float = 4.0,
    ) -> Tuple[str, Dict]:
        """
        Run daily training data pipeline.

        Args:
            date: Date to process (YYYY-MM-DD)
            output_path: Output directory
            negative_ratio: Negative sampling ratio

        Returns:
            Tuple of (output_file_path, statistics)
        """
        logger.info(f"Running daily pipeline for {date}")

        # Build dataset
        df = self.build_training_dataset(date, date, negative_ratio)

        if df.empty:
            logger.warning(f"No data for {date}")
            return "", {"error": f"No data for {date}"}

        # Get stats
        stats = self.get_dataset_stats(df)

        # Export
        date_output = os.path.join(output_path, f"date={date}")
        file_path = self.export_to_parquet(df, date_output)

        logger.info(f"Daily pipeline complete: {stats['total_samples']} samples")
        return file_path, stats


def main():
    parser = argparse.ArgumentParser(description="Training Data Pipeline")
    parser.add_argument("--date", type=str, help="Single date to process (YYYY-MM-DD)")
    parser.add_argument("--start-date", type=str, help="Start date for range processing")
    parser.add_argument("--end-date", type=str, help="End date for range processing")
    parser.add_argument("--output", type=str, default="./data/training", help="Output directory")
    parser.add_argument("--negative-ratio", type=float, default=4.0, help="Negative sampling ratio")
    parser.add_argument("--clickhouse-host", type=str, default=os.getenv("CLICKHOUSE_HOST", "localhost"))
    parser.add_argument("--clickhouse-port", type=int, default=int(os.getenv("CLICKHOUSE_PORT", "8123")))
    parser.add_argument("--clickhouse-database", type=str, default=os.getenv("CLICKHOUSE_DATABASE", "nova_feed"))
    parser.add_argument("--clickhouse-user", type=str, default=os.getenv("CLICKHOUSE_USER", "default"))
    parser.add_argument("--clickhouse-password", type=str, default=os.getenv("CLICKHOUSE_PASSWORD", ""))

    args = parser.parse_args()

    pipeline = TrainingDataPipeline(
        clickhouse_host=args.clickhouse_host,
        clickhouse_port=args.clickhouse_port,
        clickhouse_database=args.clickhouse_database,
        clickhouse_user=args.clickhouse_user,
        clickhouse_password=args.clickhouse_password,
    )

    if args.date:
        # Single date processing
        file_path, stats = pipeline.run_daily_pipeline(
            args.date,
            args.output,
            args.negative_ratio,
        )
        print(f"Output: {file_path}")
        print(f"Stats: {stats}")

    elif args.start_date and args.end_date:
        # Date range processing
        df = pipeline.build_training_dataset(
            args.start_date,
            args.end_date,
            args.negative_ratio,
        )

        if not df.empty:
            stats = pipeline.get_dataset_stats(df)
            file_path = pipeline.export_to_parquet(df, args.output)
            print(f"Output: {file_path}")
            print(f"Stats: {stats}")
        else:
            print("No data found for the specified date range")

    else:
        # Default: yesterday's data
        yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
        file_path, stats = pipeline.run_daily_pipeline(
            yesterday,
            args.output,
            args.negative_ratio,
        )
        print(f"Output: {file_path}")
        print(f"Stats: {stats}")


if __name__ == "__main__":
    main()
