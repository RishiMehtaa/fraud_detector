# backend/ml/isolation_forest.py
import pandas as pd
import numpy as np
import pickle
from pathlib import Path
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import LabelEncoder

from data.loader import DATA_PATH, load

MODEL_PATH = Path(__file__).parent / "iso_forest.pkl"


def _build_features(df: pd.DataFrame) -> pd.DataFrame:
    raw = pd.read_csv(DATA_PATH)
    enc = LabelEncoder()
    raw["type_encoded"] = enc.fit_transform(raw["type"])
    raw["hour_of_day"] = (raw["step"] % 24).astype(int)
    raw["day_of_week"] = (raw["step"] // 24 % 7).astype(int)
    raw["balance_delta_orig"] = raw["newbalanceOrig"] - raw["oldbalanceOrg"]
    raw["balance_delta_dest"] = raw["newbalanceDest"] - raw["oldbalanceDest"]
    return raw[["amount", "hour_of_day", "day_of_week", "type_encoded",
                "balance_delta_orig", "balance_delta_dest"]]


def train() -> IsolationForest:
    X = _build_features(None)
    model = IsolationForest(contamination=0.02, n_estimators=100, random_state=42, n_jobs=-1)
    model.fit(X)
    with open(MODEL_PATH, "wb") as f:
        pickle.dump(model, f)
    return model


def score(model: IsolationForest) -> pd.Series:
    X = _build_features(None)
    raw = model.score_samples(X)
    normalized = 1 - (raw - raw.min()) / (raw.max() - raw.min())
    return pd.Series(normalized, name="anomaly_score")


def load_model() -> IsolationForest:
    with open(MODEL_PATH, "rb") as f:
        return pickle.load(f)
    

def evaluate() -> dict:
    from sklearn.metrics import precision_score, recall_score, f1_score, roc_auc_score, confusion_matrix
    raw = pd.read_csv(DATA_PATH)
    labels = raw["isFraud"].values
    model = load_model()
    scores = score(model).values
    threshold = np.percentile(scores, 98)
    preds = (scores >= threshold).astype(int)
    cm = confusion_matrix(labels, preds)
    metrics = {
        "precision":  round(float(precision_score(labels, preds, zero_division=0)), 4),
        "recall":     round(float(recall_score(labels, preds, zero_division=0)), 4),
        "f1":         round(float(f1_score(labels, preds, zero_division=0)), 4),
        "roc_auc":    round(float(roc_auc_score(labels, scores)), 4),
        "confusion_matrix": cm.tolist(),
    }
    for k, v in metrics.items():
        print(f"{k}: {v}")
    return metrics