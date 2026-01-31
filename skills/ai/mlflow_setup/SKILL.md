---
name: mlflow_setup
description: Sets up MLflow for experiment tracking, model versioning, and artifact management in ML projects.
model: haiku
color: orange
---

# MLflow Setup Skill

Configures experiment tracking and model management environment using MLflow.

## Prerequisites

- Python 3.9+ with virtual environment activated
- Project structure created

## Workflow

### 1. Install Dependencies

```bash
# Verify virtual environment activation
source .venv/bin/activate

# Install MLflow
pip install mlflow>=2.10.0

# Additional utilities
pip install python-dotenv pyyaml

# Update requirements.txt
pip freeze | grep -E "mlflow|python-dotenv|pyyaml" >> requirements.txt
```

### 2. Create Project Structure

```bash
mkdir -p src/{experiments,models,utils}
mkdir -p mlruns  # MLflow local storage
mkdir -p artifacts
mkdir -p configs
```

### 3. MLflow Configuration File

**configs/mlflow.yaml:**
```yaml
tracking:
  uri: ./mlruns  # Local or server URI
  experiment_name: ${PROJECT_NAME}

artifact:
  root: ./artifacts

model_registry:
  enabled: true

logging:
  log_models: true
  log_artifacts: true
  autolog: true
```

### 4. Environment Variables

**.env:**
```bash
# MLflow
MLFLOW_TRACKING_URI=./mlruns
MLFLOW_EXPERIMENT_NAME=${PROJECT_NAME}

# Optional: Remote tracking server
# MLFLOW_TRACKING_URI=http://localhost:5000
# MLFLOW_S3_ENDPOINT_URL=http://localhost:9000
```

### 5. MLflow Utilities

**src/utils/mlflow_utils.py:**
```python
"""MLflow utility functions for experiment tracking."""

import os
from pathlib import Path
from typing import Any, Dict, Optional
from contextlib import contextmanager

import mlflow
from mlflow.tracking import MlflowClient
from dotenv import load_dotenv

load_dotenv()


def init_mlflow(
    experiment_name: Optional[str] = None,
    tracking_uri: Optional[str] = None
) -> str:
    """Initialize MLflow with experiment.

    Args:
        experiment_name: Name of the experiment.
        tracking_uri: MLflow tracking server URI.

    Returns:
        Experiment ID.
    """
    uri = tracking_uri or os.getenv("MLFLOW_TRACKING_URI", "./mlruns")
    name = experiment_name or os.getenv("MLFLOW_EXPERIMENT_NAME", "default")

    mlflow.set_tracking_uri(uri)
    mlflow.set_experiment(name)

    experiment = mlflow.get_experiment_by_name(name)
    return experiment.experiment_id


@contextmanager
def start_run(
    run_name: Optional[str] = None,
    tags: Optional[Dict[str, str]] = None,
    nested: bool = False
):
    """Context manager for MLflow run.

    Args:
        run_name: Name of the run.
        tags: Tags to attach to the run.
        nested: Whether this is a nested run.

    Yields:
        Active MLflow run.
    """
    with mlflow.start_run(run_name=run_name, nested=nested) as run:
        if tags:
            mlflow.set_tags(tags)
        yield run


def log_params(params: Dict[str, Any]) -> None:
    """Log multiple parameters.

    Args:
        params: Dictionary of parameters.
    """
    mlflow.log_params(params)


def log_metrics(metrics: Dict[str, float], step: Optional[int] = None) -> None:
    """Log multiple metrics.

    Args:
        metrics: Dictionary of metrics.
        step: Step number for time-series metrics.
    """
    mlflow.log_metrics(metrics, step=step)


def log_artifact(local_path: str, artifact_path: Optional[str] = None) -> None:
    """Log a local file or directory as an artifact.

    Args:
        local_path: Path to the local file or directory.
        artifact_path: Destination path within the artifact store.
    """
    mlflow.log_artifact(local_path, artifact_path)


def log_model(
    model: Any,
    artifact_path: str,
    registered_model_name: Optional[str] = None,
    **kwargs
) -> None:
    """Log a model with automatic flavor detection.

    Args:
        model: The model to log.
        artifact_path: Path within the artifact store.
        registered_model_name: Name to register in model registry.
    """
    # Detect model type and use appropriate logging
    model_type = type(model).__module__.split(".")[0]

    if model_type == "sklearn":
        mlflow.sklearn.log_model(
            model, artifact_path,
            registered_model_name=registered_model_name,
            **kwargs
        )
    elif model_type == "torch":
        mlflow.pytorch.log_model(
            model, artifact_path,
            registered_model_name=registered_model_name,
            **kwargs
        )
    elif model_type == "transformers":
        mlflow.transformers.log_model(
            model, artifact_path,
            registered_model_name=registered_model_name,
            **kwargs
        )
    else:
        mlflow.pyfunc.log_model(
            artifact_path,
            python_model=model,
            registered_model_name=registered_model_name,
            **kwargs
        )


def get_best_run(
    experiment_name: str,
    metric: str,
    ascending: bool = True
) -> Optional[mlflow.entities.Run]:
    """Get the best run based on a metric.

    Args:
        experiment_name: Name of the experiment.
        metric: Metric name to optimize.
        ascending: If True, lower is better.

    Returns:
        Best run or None.
    """
    client = MlflowClient()
    experiment = client.get_experiment_by_name(experiment_name)

    if not experiment:
        return None

    order = "ASC" if ascending else "DESC"
    runs = client.search_runs(
        experiment_ids=[experiment.experiment_id],
        order_by=[f"metrics.{metric} {order}"],
        max_results=1
    )

    return runs[0] if runs else None


def load_model(model_uri: str) -> Any:
    """Load a model from MLflow.

    Args:
        model_uri: URI of the model (runs:/, models:/, etc.)

    Returns:
        Loaded model.
    """
    return mlflow.pyfunc.load_model(model_uri)
```

### 6. Experiment Example

**src/experiments/train_example.py:**
```python
"""Example training script with MLflow tracking."""

from dataclasses import dataclass, asdict
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score

from src.utils.mlflow_utils import (
    init_mlflow,
    start_run,
    log_params,
    log_metrics,
    log_model
)


@dataclass
class TrainConfig:
    n_estimators: int = 100
    max_depth: int = 5
    random_state: int = 42
    test_size: float = 0.2


def train(config: TrainConfig) -> dict:
    """Train a model with experiment tracking.

    Args:
        config: Training configuration.

    Returns:
        Dictionary of metrics.
    """
    # Initialize MLflow
    init_mlflow(experiment_name="iris-classification")

    # Load data
    X, y = load_iris(return_X_y=True)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=config.test_size,
        random_state=config.random_state
    )

    with start_run(run_name="random-forest-training"):
        # Log parameters
        log_params(asdict(config))

        # Train model
        model = RandomForestClassifier(
            n_estimators=config.n_estimators,
            max_depth=config.max_depth,
            random_state=config.random_state
        )
        model.fit(X_train, y_train)

        # Evaluate
        y_pred = model.predict(X_test)
        metrics = {
            "accuracy": accuracy_score(y_test, y_pred),
            "f1_score": f1_score(y_test, y_pred, average="weighted")
        }

        # Log metrics
        log_metrics(metrics)

        # Log model
        log_model(
            model,
            artifact_path="model",
            registered_model_name="iris-classifier"
        )

        return metrics


if __name__ == "__main__":
    config = TrainConfig()
    metrics = train(config)
    print(f"Training complete. Metrics: {metrics}")
```

### 7. Run MLflow UI

```bash
# Start MLflow UI server
mlflow ui --host 0.0.0.0 --port 5000

# Access http://localhost:5000 in browser
```

### 8. Add .gitignore

```gitignore
# MLflow
mlruns/
mlartifacts/
artifacts/

# Model files
*.pkl
*.joblib
*.h5
*.pt
*.onnx
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `mlflow ui` | Start UI server |
| `mlflow run .` | Run MLproject |
| `mlflow models serve -m <uri>` | Serve model |
| `mlflow experiments list` | List experiments |
| `mlflow runs list` | List runs |

## Generated Structure

```
${PROJECT_NAME}/
├── src/
│   ├── experiments/
│   │   └── train_example.py
│   ├── models/
│   └── utils/
│       └── mlflow_utils.py
├── configs/
│   └── mlflow.yaml
├── mlruns/              # MLflow local storage
├── artifacts/           # Artifact storage
├── .env
└── requirements.txt
```

## Verification Checklist

- [ ] Verify MLflow installation: `mlflow --version`
- [ ] Run experiment: `python src/experiments/train_example.py`
- [ ] Check UI: `mlflow ui` then open browser
- [ ] Verify model registration

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MLflow Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MLflow: 2.10+
Tracking URI: ./mlruns
Experiment: ${PROJECT_NAME}

- Tracking utilities created
- Example experiment included
- Model logging configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
