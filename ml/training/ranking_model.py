#!/usr/bin/env python3
"""
GBDT Ranking Model Training (P1-5)

Trains a LightGBM GBDT model for ranking and exports to ONNX format
for inference in the Rust ranking-service.

Features (30 dimensions):
- User features: 8 dimensions (indices 0-7)
- Content features: 10 dimensions (indices 8-17)
- Author features: 5 dimensions (indices 18-22)
- Interaction features: 4 dimensions (indices 23-26)
- Context features: 3 dimensions (indices 27-29)

Usage:
    python ranking_model.py --input ./data/training/ --output ./models/
    python ranking_model.py --input ./data/training/ --output ./models/ --tune-hyperparams

Model outputs:
- ranking_gbdt.onnx: ONNX model for Rust inference
- ranking_gbdt.txt: LightGBM native format (backup)
- model_metrics.json: Training metrics and validation scores
"""

import argparse
import json
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    auc,
    log_loss,
    ndcg_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GroupKFold, train_test_split

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# Feature names in order (must match scorer.rs)
FEATURE_NAMES = [
    # User features (8)
    'user_follower_count', 'user_following_count', 'user_post_count',
    'user_avg_session_length', 'user_active_days_30d', 'user_avg_daily_watch_time',
    'user_content_type_pref', 'user_engagement_rate',
    # Content features (10)
    'post_age_hours', 'post_like_count', 'post_comment_count', 'post_view_count',
    'post_completion_rate', 'post_engagement_rate', 'content_duration_minutes',
    'has_music', 'is_original', 'trending_velocity',
    # Author features (5)
    'author_follower_count', 'author_avg_engagement', 'author_post_frequency',
    'author_content_quality', 'author_response_rate',
    # Interaction features (4)
    'user_author_affinity', 'user_author_interaction_count',
    'user_author_like_ratio', 'user_author_avg_completion',
    # Context features (3)
    'hour_of_day', 'day_of_week', 'is_weekend',
]

FEATURE_DIM = 30


def load_training_data(input_path: str) -> pd.DataFrame:
    """
    Load training data from Parquet files.
    """
    input_path = Path(input_path)

    if input_path.is_file():
        logger.info(f"Loading single file: {input_path}")
        return pd.read_parquet(input_path)

    # Load all parquet files in directory
    parquet_files = list(input_path.glob("**/*.parquet"))
    if not parquet_files:
        raise FileNotFoundError(f"No parquet files found in {input_path}")

    logger.info(f"Loading {len(parquet_files)} parquet files from {input_path}")
    dfs = [pd.read_parquet(f) for f in parquet_files]
    df = pd.concat(dfs, ignore_index=True)

    logger.info(f"Loaded {len(df)} samples")
    return df


def prepare_features(df: pd.DataFrame) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Prepare feature matrix, labels, and groups for training.

    Returns:
        X: Feature matrix (n_samples, 30)
        y: Labels (n_samples,)
        groups: User IDs for group-based splitting (n_samples,)
    """
    # Ensure all required feature columns exist
    available_cols = set(df.columns)
    missing_cols = set(FEATURE_NAMES) - available_cols

    if missing_cols:
        logger.warning(f"Missing columns (will use zeros): {missing_cols}")
        for col in missing_cols:
            df[col] = 0.0

    # Extract features in correct order
    X = df[FEATURE_NAMES].values.astype(np.float32)

    # Labels
    y = df['label'].values.astype(np.float32)

    # Groups (for user-based splitting)
    groups = df['user_id'].values

    logger.info(f"Features shape: {X.shape}")
    logger.info(f"Labels: {np.sum(y == 1)} positive, {np.sum(y == 0)} negative")
    logger.info(f"Positive rate: {np.mean(y):.2%}")

    return X, y, groups


def get_default_params() -> Dict:
    """
    Get default LightGBM parameters optimized for ranking.
    """
    return {
        'objective': 'binary',
        'metric': ['binary_logloss', 'auc'],
        'boosting_type': 'gbdt',
        'num_leaves': 63,
        'max_depth': 8,
        'learning_rate': 0.05,
        'feature_fraction': 0.8,
        'bagging_fraction': 0.8,
        'bagging_freq': 5,
        'min_child_samples': 100,
        'reg_alpha': 0.1,
        'reg_lambda': 0.1,
        'verbose': -1,
        'seed': 42,
        'n_jobs': -1,
    }


def train_model(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_val: np.ndarray,
    y_val: np.ndarray,
    params: Optional[Dict] = None,
    num_boost_round: int = 1000,
    early_stopping_rounds: int = 50,
) -> Tuple[lgb.Booster, Dict]:
    """
    Train LightGBM model.

    Returns:
        model: Trained LightGBM Booster
        metrics: Training metrics
    """
    if params is None:
        params = get_default_params()

    logger.info("Training LightGBM model...")
    logger.info(f"Train size: {len(X_train)}, Val size: {len(X_val)}")

    # Create datasets
    train_data = lgb.Dataset(
        X_train, label=y_train,
        feature_name=FEATURE_NAMES,
    )
    val_data = lgb.Dataset(
        X_val, label=y_val,
        feature_name=FEATURE_NAMES,
        reference=train_data,
    )

    # Train with early stopping
    evals_result = {}
    model = lgb.train(
        params,
        train_data,
        num_boost_round=num_boost_round,
        valid_sets=[train_data, val_data],
        valid_names=['train', 'val'],
        callbacks=[
            lgb.early_stopping(stopping_rounds=early_stopping_rounds),
            lgb.log_evaluation(period=50),
            lgb.record_evaluation(evals_result),
        ],
    )

    logger.info(f"Training complete. Best iteration: {model.best_iteration}")

    # Compute validation metrics
    y_pred_proba = model.predict(X_val, num_iteration=model.best_iteration)
    y_pred = (y_pred_proba > 0.5).astype(int)

    metrics = {
        'best_iteration': model.best_iteration,
        'val_auc': roc_auc_score(y_val, y_pred_proba),
        'val_logloss': log_loss(y_val, y_pred_proba),
        'val_accuracy': accuracy_score(y_val, y_pred),
        'val_precision': precision_score(y_val, y_pred, zero_division=0),
        'val_recall': recall_score(y_val, y_pred, zero_division=0),
        'train_history': evals_result,
    }

    logger.info(f"Validation AUC: {metrics['val_auc']:.4f}")
    logger.info(f"Validation LogLoss: {metrics['val_logloss']:.4f}")
    logger.info(f"Validation Accuracy: {metrics['val_accuracy']:.4f}")

    return model, metrics


def export_to_onnx(
    model: lgb.Booster,
    output_path: str,
) -> str:
    """
    Export LightGBM model to ONNX format.
    """
    try:
        from onnxmltools import convert_lightgbm
        from onnxmltools.convert.common.data_types import FloatTensorType
        import onnx

        logger.info("Converting model to ONNX format...")

        # Define input shape
        initial_types = [('input', FloatTensorType([None, FEATURE_DIM]))]

        # Convert to ONNX
        onnx_model = convert_lightgbm(
            model,
            initial_types=initial_types,
            target_opset=12,
        )

        # Save ONNX model
        onnx_path = os.path.join(output_path, 'ranking_gbdt.onnx')
        onnx.save_model(onnx_model, onnx_path)

        logger.info(f"ONNX model saved to: {onnx_path}")
        return onnx_path

    except ImportError as e:
        logger.warning(f"ONNX conversion failed (missing dependency): {e}")
        logger.warning("Install with: pip install onnxmltools onnx")
        return ""


def compute_feature_importance(model: lgb.Booster) -> Dict[str, float]:
    """
    Compute and return feature importance.
    """
    importance = model.feature_importance(importance_type='gain')
    importance_dict = dict(zip(FEATURE_NAMES, importance.tolist()))

    # Sort by importance
    importance_dict = dict(sorted(importance_dict.items(), key=lambda x: x[1], reverse=True))

    logger.info("\nTop 10 Feature Importance (gain):")
    for i, (name, imp) in enumerate(list(importance_dict.items())[:10]):
        logger.info(f"  {i+1}. {name}: {imp:.2f}")

    return importance_dict


def cross_validate(
    X: np.ndarray,
    y: np.ndarray,
    groups: np.ndarray,
    params: Optional[Dict] = None,
    n_splits: int = 5,
) -> Dict:
    """
    Perform group-based cross-validation (users don't appear in both train and val).
    """
    if params is None:
        params = get_default_params()

    logger.info(f"Running {n_splits}-fold cross-validation...")

    # Use GroupKFold to ensure user-level split
    unique_users = np.unique(groups)
    group_kfold = GroupKFold(n_splits=n_splits)

    cv_scores = {
        'auc': [],
        'logloss': [],
        'accuracy': [],
    }

    for fold, (train_idx, val_idx) in enumerate(group_kfold.split(X, y, groups)):
        X_train, X_val = X[train_idx], X[val_idx]
        y_train, y_val = y[train_idx], y[val_idx]

        # Train model
        train_data = lgb.Dataset(X_train, label=y_train, feature_name=FEATURE_NAMES)
        val_data = lgb.Dataset(X_val, label=y_val, feature_name=FEATURE_NAMES, reference=train_data)

        model = lgb.train(
            params,
            train_data,
            num_boost_round=500,
            valid_sets=[val_data],
            callbacks=[
                lgb.early_stopping(stopping_rounds=30),
                lgb.log_evaluation(period=0),
            ],
        )

        # Evaluate
        y_pred_proba = model.predict(X_val, num_iteration=model.best_iteration)

        cv_scores['auc'].append(roc_auc_score(y_val, y_pred_proba))
        cv_scores['logloss'].append(log_loss(y_val, y_pred_proba))
        cv_scores['accuracy'].append(accuracy_score(y_val, (y_pred_proba > 0.5).astype(int)))

        logger.info(f"Fold {fold+1}: AUC={cv_scores['auc'][-1]:.4f}, LogLoss={cv_scores['logloss'][-1]:.4f}")

    # Compute mean and std
    cv_results = {
        'auc_mean': np.mean(cv_scores['auc']),
        'auc_std': np.std(cv_scores['auc']),
        'logloss_mean': np.mean(cv_scores['logloss']),
        'logloss_std': np.std(cv_scores['logloss']),
        'accuracy_mean': np.mean(cv_scores['accuracy']),
        'accuracy_std': np.std(cv_scores['accuracy']),
        'fold_scores': cv_scores,
    }

    logger.info(f"\nCV Results: AUC={cv_results['auc_mean']:.4f} ± {cv_results['auc_std']:.4f}")
    logger.info(f"CV Results: LogLoss={cv_results['logloss_mean']:.4f} ± {cv_results['logloss_std']:.4f}")

    return cv_results


def tune_hyperparameters(
    X: np.ndarray,
    y: np.ndarray,
    n_trials: int = 50,
) -> Dict:
    """
    Hyperparameter tuning using Optuna (if available).
    """
    try:
        import optuna
        from optuna.integration import LightGBMPruningCallback

        logger.info(f"Starting hyperparameter tuning with {n_trials} trials...")

        # Split for tuning
        X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)

        def objective(trial):
            params = {
                'objective': 'binary',
                'metric': 'auc',
                'boosting_type': 'gbdt',
                'num_leaves': trial.suggest_int('num_leaves', 31, 127),
                'max_depth': trial.suggest_int('max_depth', 4, 12),
                'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.1, log=True),
                'feature_fraction': trial.suggest_float('feature_fraction', 0.6, 0.95),
                'bagging_fraction': trial.suggest_float('bagging_fraction', 0.6, 0.95),
                'bagging_freq': trial.suggest_int('bagging_freq', 1, 10),
                'min_child_samples': trial.suggest_int('min_child_samples', 20, 200),
                'reg_alpha': trial.suggest_float('reg_alpha', 1e-4, 1.0, log=True),
                'reg_lambda': trial.suggest_float('reg_lambda', 1e-4, 1.0, log=True),
                'verbose': -1,
                'seed': 42,
            }

            train_data = lgb.Dataset(X_train, label=y_train)
            val_data = lgb.Dataset(X_val, label=y_val, reference=train_data)

            model = lgb.train(
                params,
                train_data,
                num_boost_round=500,
                valid_sets=[val_data],
                callbacks=[
                    lgb.early_stopping(stopping_rounds=30),
                    LightGBMPruningCallback(trial, 'auc'),
                ],
            )

            y_pred = model.predict(X_val, num_iteration=model.best_iteration)
            return roc_auc_score(y_val, y_pred)

        study = optuna.create_study(direction='maximize')
        study.optimize(objective, n_trials=n_trials, show_progress_bar=True)

        logger.info(f"\nBest trial: AUC={study.best_value:.4f}")
        logger.info(f"Best params: {study.best_params}")

        # Merge best params with defaults
        best_params = get_default_params()
        best_params.update(study.best_params)

        return best_params

    except ImportError:
        logger.warning("Optuna not installed, skipping hyperparameter tuning")
        logger.warning("Install with: pip install optuna")
        return get_default_params()


def main():
    parser = argparse.ArgumentParser(description="Train GBDT Ranking Model")
    parser.add_argument("--input", type=str, required=True, help="Input training data path")
    parser.add_argument("--output", type=str, required=True, help="Output model directory")
    parser.add_argument("--tune-hyperparams", action="store_true", help="Run hyperparameter tuning")
    parser.add_argument("--cv-folds", type=int, default=5, help="Number of CV folds")
    parser.add_argument("--num-boost-round", type=int, default=1000, help="Max boosting rounds")
    parser.add_argument("--early-stopping", type=int, default=50, help="Early stopping rounds")

    args = parser.parse_args()

    # Create output directory
    os.makedirs(args.output, exist_ok=True)

    # Load data
    df = load_training_data(args.input)
    X, y, groups = prepare_features(df)

    # Optional: Hyperparameter tuning
    if args.tune_hyperparams:
        params = tune_hyperparameters(X, y)
    else:
        params = get_default_params()

    # Cross-validation
    cv_results = cross_validate(X, y, groups, params, n_splits=args.cv_folds)

    # Train final model on all data (with held-out validation)
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.15, random_state=42)
    model, metrics = train_model(
        X_train, y_train, X_val, y_val,
        params=params,
        num_boost_round=args.num_boost_round,
        early_stopping_rounds=args.early_stopping,
    )

    # Feature importance
    feature_importance = compute_feature_importance(model)

    # Save LightGBM native format
    lgb_path = os.path.join(args.output, 'ranking_gbdt.txt')
    model.save_model(lgb_path)
    logger.info(f"LightGBM model saved to: {lgb_path}")

    # Export to ONNX
    onnx_path = export_to_onnx(model, args.output)

    # Save metrics
    all_metrics = {
        'timestamp': datetime.now().isoformat(),
        'params': params,
        'train_metrics': metrics,
        'cv_results': cv_results,
        'feature_importance': feature_importance,
        'feature_names': FEATURE_NAMES,
        'feature_dim': FEATURE_DIM,
        'model_files': {
            'lgb': lgb_path,
            'onnx': onnx_path,
        },
    }

    metrics_path = os.path.join(args.output, 'model_metrics.json')
    with open(metrics_path, 'w') as f:
        # Convert numpy types to Python types for JSON serialization
        def convert(obj):
            if isinstance(obj, np.ndarray):
                return obj.tolist()
            if isinstance(obj, (np.int64, np.int32)):
                return int(obj)
            if isinstance(obj, (np.float64, np.float32)):
                return float(obj)
            return obj

        json.dump(all_metrics, f, indent=2, default=convert)
    logger.info(f"Metrics saved to: {metrics_path}")

    print("\n" + "=" * 60)
    print("Training Complete!")
    print("=" * 60)
    print(f"Validation AUC: {metrics['val_auc']:.4f}")
    print(f"CV AUC: {cv_results['auc_mean']:.4f} ± {cv_results['auc_std']:.4f}")
    print(f"\nModels saved to: {args.output}")
    print(f"- LightGBM: {lgb_path}")
    if onnx_path:
        print(f"- ONNX: {onnx_path}")


if __name__ == "__main__":
    main()
