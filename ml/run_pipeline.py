#!/usr/bin/env python3
"""
Nova ML Pipeline Orchestrator

Runs the complete ML pipeline:
1. Compute similarities (batch job)
2. Sync similarities to Redis
3. Extract training data
4. Train ranking model
5. Export to ONNX

Usage:
    python run_pipeline.py --all
    python run_pipeline.py --similarity --sync
    python run_pipeline.py --training --export
"""

import argparse
import logging
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def run_similarity_computation(args):
    """Step 1: Compute item and user similarities."""
    logger.info("=" * 60)
    logger.info("Step 1: Computing similarities...")
    logger.info("=" * 60)

    from etl.compute_similarity import SimilarityComputer

    computer = SimilarityComputer(
        clickhouse_host=args.clickhouse_host,
        clickhouse_port=args.clickhouse_port,
        clickhouse_database=args.clickhouse_database,
        clickhouse_user=args.clickhouse_user,
        clickhouse_password=args.clickhouse_password,
    )

    results = {}

    # Item similarity
    logger.info("Computing item similarity...")
    results["item"] = computer.compute_item_similarity(
        lookback_days=args.lookback_days,
        min_user_interactions=10,
        min_co_interactions=5,
        top_k_per_item=100,
    )

    # User similarity
    logger.info("Computing user similarity...")
    results["user"] = computer.compute_user_similarity(
        lookback_days=args.lookback_days,
        min_item_interactions=10,
        min_common_items=5,
        top_k_per_user=50,
    )

    # Update recent items
    logger.info("Updating user recent items...")
    results["recent"] = computer.update_user_recent_items(
        lookback_days=7,
    )

    logger.info(f"Similarity computation complete: {results}")
    return results


def run_similarity_sync(args):
    """Step 2: Sync similarities to Redis."""
    logger.info("=" * 60)
    logger.info("Step 2: Syncing similarities to Redis...")
    logger.info("=" * 60)

    from etl.similarity_sync import SimilaritySync

    syncer = SimilaritySync(
        clickhouse_host=args.clickhouse_host,
        clickhouse_port=args.clickhouse_port,
        clickhouse_database=args.clickhouse_database,
        redis_host=args.redis_host,
        redis_port=args.redis_port,
    )

    results = {}

    # Sync item similarity
    logger.info("Syncing item similarity to Redis...")
    results["item"] = syncer.sync_item_similarity(top_k=50)

    # Sync user similarity
    logger.info("Syncing user similarity to Redis...")
    results["user"] = syncer.sync_user_similarity(top_k=30)

    # Sync user recent items
    logger.info("Syncing user recent items to Redis...")
    results["recent"] = syncer.sync_user_recent_items(lookback_days=7)

    logger.info(f"Similarity sync complete: {results}")
    return results


def run_training_data_extraction(args):
    """Step 3: Extract training data."""
    logger.info("=" * 60)
    logger.info("Step 3: Extracting training data...")
    logger.info("=" * 60)

    from etl.training_data_pipeline import TrainingDataPipeline

    pipeline = TrainingDataPipeline(
        clickhouse_host=args.clickhouse_host,
        clickhouse_port=args.clickhouse_port,
        clickhouse_database=args.clickhouse_database,
    )

    end_date = datetime.now()
    start_date = end_date - timedelta(days=args.training_days)

    logger.info(f"Extracting data from {start_date} to {end_date}")

    df = pipeline.build_training_dataset(
        start_date=start_date,
        end_date=end_date,
        negative_ratio=4.0,
    )

    # Export to parquet
    output_path = Path(args.data_output_dir) / f"training_data_{end_date.strftime('%Y%m%d')}.parquet"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    pipeline.export_to_parquet(df, str(output_path))

    logger.info(f"Training data extracted: {len(df)} samples -> {output_path}")
    return {"samples": len(df), "output_path": str(output_path)}


def run_model_training(args):
    """Step 4: Train the ranking model."""
    logger.info("=" * 60)
    logger.info("Step 4: Training ranking model...")
    logger.info("=" * 60)

    import pandas as pd
    from training.ranking_model import (
        FEATURE_NAMES,
        train_model,
        cross_validate,
        get_feature_importance,
        export_to_onnx,
    )

    # Find latest training data
    data_dir = Path(args.data_output_dir)
    parquet_files = sorted(data_dir.glob("training_data_*.parquet"), reverse=True)

    if not parquet_files:
        raise FileNotFoundError(f"No training data found in {data_dir}")

    data_path = parquet_files[0]
    logger.info(f"Loading training data from {data_path}")

    df = pd.read_parquet(data_path)
    logger.info(f"Loaded {len(df)} samples")

    # Prepare features and labels
    X = df[FEATURE_NAMES].values
    y = df["label"].values
    groups = df["user_id"].values if "user_id" in df.columns else None

    # Cross-validation
    if args.cross_validate:
        logger.info("Running cross-validation...")
        cv_results = cross_validate(X, y, groups, n_splits=5)
        logger.info(f"CV Results: {cv_results}")

    # Train final model
    from sklearn.model_selection import train_test_split
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    logger.info(f"Training set: {len(X_train)}, Validation set: {len(X_val)}")

    model, metrics = train_model(X_train, y_train, X_val, y_val)
    logger.info(f"Training metrics: {metrics}")

    # Feature importance
    importance = get_feature_importance(model)
    logger.info("Top 10 features by importance:")
    for feat, imp in importance[:10]:
        logger.info(f"  {feat}: {imp:.4f}")

    # Save model
    model_dir = Path(args.model_output_dir)
    model_dir.mkdir(parents=True, exist_ok=True)

    model_path = model_dir / "ranking_gbdt.txt"
    model.save_model(str(model_path))
    logger.info(f"Model saved to {model_path}")

    # Export to ONNX
    if args.export_onnx:
        onnx_path = model_dir / "ranking_gbdt.onnx"
        export_to_onnx(model, str(onnx_path))
        logger.info(f"ONNX model exported to {onnx_path}")

    # Save metrics
    import json
    metrics_path = model_dir / "model_metrics.json"
    with open(metrics_path, "w") as f:
        json.dump({
            "metrics": metrics,
            "feature_importance": importance[:20],
            "training_samples": len(X_train),
            "validation_samples": len(X_val),
            "timestamp": datetime.now().isoformat(),
        }, f, indent=2)

    logger.info(f"Metrics saved to {metrics_path}")
    return metrics


def main():
    parser = argparse.ArgumentParser(description="Nova ML Pipeline Orchestrator")

    # Pipeline steps
    parser.add_argument("--all", action="store_true", help="Run all pipeline steps")
    parser.add_argument("--similarity", action="store_true", help="Run similarity computation")
    parser.add_argument("--sync", action="store_true", help="Run Redis sync")
    parser.add_argument("--extract", action="store_true", help="Run training data extraction")
    parser.add_argument("--train", action="store_true", help="Run model training")

    # Training options
    parser.add_argument("--cross-validate", action="store_true", help="Run cross-validation")
    parser.add_argument("--export-onnx", action="store_true", default=True, help="Export ONNX model")
    parser.add_argument("--training-days", type=int, default=30, help="Days of training data")
    parser.add_argument("--lookback-days", type=int, default=30, help="Lookback for similarity")

    # Paths
    parser.add_argument("--data-output-dir", type=str, default="./data", help="Training data output")
    parser.add_argument("--model-output-dir", type=str, default="./models", help="Model output")

    # ClickHouse
    parser.add_argument("--clickhouse-host", type=str,
                       default=os.getenv("CLICKHOUSE_HOST", "localhost"))
    parser.add_argument("--clickhouse-port", type=int,
                       default=int(os.getenv("CLICKHOUSE_PORT", "8123")))
    parser.add_argument("--clickhouse-database", type=str,
                       default=os.getenv("CLICKHOUSE_DATABASE", "nova_feed"))
    parser.add_argument("--clickhouse-user", type=str,
                       default=os.getenv("CLICKHOUSE_USER", "default"))
    parser.add_argument("--clickhouse-password", type=str,
                       default=os.getenv("CLICKHOUSE_PASSWORD", ""))

    # Redis
    parser.add_argument("--redis-host", type=str,
                       default=os.getenv("REDIS_HOST", "localhost"))
    parser.add_argument("--redis-port", type=int,
                       default=int(os.getenv("REDIS_PORT", "6379")))

    args = parser.parse_args()

    # Default to --all if no step specified
    if not any([args.all, args.similarity, args.sync, args.extract, args.train]):
        args.all = True

    results = {}

    try:
        if args.all or args.similarity:
            results["similarity"] = run_similarity_computation(args)

        if args.all or args.sync:
            results["sync"] = run_similarity_sync(args)

        if args.all or args.extract:
            results["extract"] = run_training_data_extraction(args)

        if args.all or args.train:
            results["train"] = run_model_training(args)

        logger.info("=" * 60)
        logger.info("Pipeline complete!")
        logger.info("=" * 60)

        for step, result in results.items():
            logger.info(f"{step}: {result}")

        return 0

    except Exception as e:
        logger.error(f"Pipeline failed: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
