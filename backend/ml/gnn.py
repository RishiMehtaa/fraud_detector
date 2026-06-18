# backend/ml/gnn.py
import numpy as np
import pandas as pd
import pickle
from pathlib import Path

import torch
from torch_geometric.data import Data

from graph.builder import load as load_graph
from ml.isolation_forest import load_model, score
import torch.nn as nn
import torch.nn.functional as F
from torch_geometric.nn import SAGEConv
from sklearn.metrics import precision_score, recall_score, f1_score

from data.loader import DATA_PATH

ISO_MODEL_PATH = Path(__file__).parent / "iso_forest.pkl"


def _make_stratified_masks(labels: torch.Tensor, seed: int = 42) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    rng = np.random.default_rng(seed)
    labels_np = labels.cpu().numpy().astype(int)
    indices = np.arange(labels_np.shape[0])

    train_indices = []
    val_indices = []
    test_indices = []

    for value in (0, 1):
        class_indices = indices[labels_np == value]
        rng.shuffle(class_indices)
        n = len(class_indices)
        n_test = max(1, int(round(n * 0.15)))
        n_val = max(1, int(round(n * 0.15)))
        if n_test + n_val >= n:
            n_test = max(1, n // 5)
            n_val = max(1, n // 5)
        test_indices.extend(class_indices[:n_test])
        val_indices.extend(class_indices[n_test:n_test + n_val])
        train_indices.extend(class_indices[n_test + n_val:])

    rng.shuffle(train_indices)
    rng.shuffle(val_indices)
    rng.shuffle(test_indices)

    num_nodes = labels_np.shape[0]
    train_mask = torch.zeros(num_nodes, dtype=torch.bool)
    val_mask = torch.zeros(num_nodes, dtype=torch.bool)
    test_mask = torch.zeros(num_nodes, dtype=torch.bool)
    train_mask[train_indices] = True
    val_mask[val_indices] = True
    test_mask[test_indices] = True
    return train_mask, val_mask, test_mask


def _get_iso_scores_by_account() -> dict:
    model = load_model()
    raw_csv = pd.read_csv(DATA_PATH)
    s = score(model)
    raw_csv["anomaly_score"] = s.values
    orig = raw_csv.groupby("nameOrig")["anomaly_score"].mean().to_dict()
    dest = raw_csv.groupby("nameDest")["anomaly_score"].mean().to_dict()
    combined = {}
    for k in set(orig) | set(dest):
        vals = [v for v in [orig.get(k), dest.get(k)] if v is not None]
        combined[k] = float(np.mean(vals))
    return combined


def build_pyg_data() -> Data:
    G = load_graph()
    iso_scores = _get_iso_scores_by_account()

    nodes = list(G.nodes())
    node_index = {n: i for i, n in enumerate(nodes)}

    rows = []
    for n in nodes:
        attr = G.nodes[n]
        in_deg = G.in_degree(n)
        out_deg = G.out_degree(n)

        out_edges = list(G.out_edges(n, data=True))
        in_edges = list(G.in_edges(n, data=True))

        out_amounts = [e[2]["amount"] for e in out_edges]
        in_amounts = [e[2]["amount"] for e in in_edges]

        avg_sent = float(np.mean(out_amounts)) if out_amounts else 0.0
        avg_recv = float(np.mean(in_amounts)) if in_amounts else 0.0
        total_sent = float(np.sum(out_amounts)) if out_amounts else 0.0
        total_recv = float(np.sum(in_amounts)) if in_amounts else 0.0
        sent_std = float(np.std(out_amounts)) if len(out_amounts) > 1 else 0.0
        recv_std = float(np.std(in_amounts)) if len(in_amounts) > 1 else 0.0

        all_edges = out_edges + in_edges
        if all_edges:
            timestamps = [e[2]["timestamp"] for e in all_edges]
            ts_sorted = sorted(timestamps)
            span_hours = float((ts_sorted[-1] - ts_sorted[0]).total_seconds() / 3600.0) if len(ts_sorted) > 1 else 0.0
            gaps = [
                float((b - a).total_seconds() / 3600.0)
                for a, b in zip(ts_sorted, ts_sorted[1:])
            ]
            avg_gap_hours = float(np.mean(gaps)) if gaps else 0.0
            recent = [t for t in ts_sorted if t >= ts_sorted[-1] - pd.Timedelta(hours=24)]
            tx_velocity = len(recent)
        else:
            span_hours = 0.0
            avg_gap_hours = 0.0
            tx_velocity = 0

        unique_counterparties = float(len({edge[1] for edge in out_edges} | {edge[0] for edge in in_edges}))

        iso_score = iso_scores.get(n, 0.0)
        acct_type = 1.0 if str(n).startswith("M") else 0.0

        rows.append([
            in_deg,
            out_deg,
            avg_sent,
            avg_recv,
            total_sent,
            total_recv,
            sent_std,
            recv_std,
            span_hours,
            avg_gap_hours,
            unique_counterparties,
            tx_velocity,
            iso_score,
            acct_type,
        ])

    x = torch.tensor(rows, dtype=torch.float)

    edge_index_list = []
    for u, v in G.edges():
        edge_index_list.append([node_index[u], node_index[v]])
    edge_index = torch.tensor(edge_index_list, dtype=torch.long).t().contiguous()

    fraud_labels = []
    for n in nodes:
        out_fraud = any(e[2].get("is_fraud", 0) for e in G.out_edges(n, data=True))
        in_fraud = any(e[2].get("is_fraud", 0) for e in G.in_edges(n, data=True))
        fraud_labels.append(1.0 if (out_fraud or in_fraud) else 0.0)

    y = torch.tensor(fraud_labels, dtype=torch.float)

    train_mask, val_mask, test_mask = _make_stratified_masks(y)

    data = Data(x=x, edge_index=edge_index, y=y, train_mask=train_mask, val_mask=val_mask, test_mask=test_mask)
    torch.save(data, Path(__file__).parent / "pyg_data.pt")
    return data





class GraphSAGE(nn.Module):
    def __init__(self, in_channels: int):
        super().__init__()
        self.conv1 = SAGEConv(in_channels, 64)
        self.conv2 = SAGEConv(64, 32)
        self.classifier = nn.Linear(32, 1)
        self.skip = nn.Linear(in_channels, 1)
        self.dropout = nn.Dropout(0.3)

    def forward(self, x, edge_index):
        residual = self.skip(x)
        x = F.relu(self.conv1(x, edge_index))
        x = self.dropout(x)
        x = F.relu(self.conv2(x, edge_index))
        x = self.dropout(x)
        return (self.classifier(x) + residual).squeeze(-1)


def _best_threshold(labels: np.ndarray, probabilities: np.ndarray) -> float:
    candidates = np.unique(np.concatenate(([0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95], probabilities)))
    best_threshold = 0.5
    best_f1 = -1.0

    for threshold in candidates:
        preds = (probabilities >= threshold).astype(int)
        f1 = f1_score(labels, preds, zero_division=0)
        if f1 > best_f1:
            best_f1 = f1
            best_threshold = float(threshold)

    return best_threshold


def train_gnn():
    data = torch.load(Path(__file__).parent / "pyg_data.pt", weights_only=False)

    if not hasattr(data, "train_mask") or not hasattr(data, "val_mask") or not hasattr(data, "test_mask"):
        train_mask, val_mask, test_mask = _make_stratified_masks(data.y)
        data.train_mask = train_mask
        data.val_mask = val_mask
        data.test_mask = test_mask

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    data = data.to(device)

    model = GraphSAGE(in_channels=data.x.shape[1]).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.005)

    train_labels = data.y[data.train_mask]
    positive_count = float(train_labels.sum().item())
    negative_count = float(train_labels.numel() - positive_count)
    pos_weight = torch.tensor([negative_count / max(positive_count, 1.0)], device=device)
    criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)

    for epoch in range(1, 101):
        model.train()
        optimizer.zero_grad()
        out = model(data.x, data.edge_index)
        loss = criterion(out[data.train_mask], data.y[data.train_mask])
        loss.backward()
        optimizer.step()
        if epoch % 20 == 0:
            print(f"Epoch {epoch:02d} | Loss: {loss.item():.4f}")

    model.eval()
    with torch.no_grad():
        out = model(data.x, data.edge_index)
        val_probs = torch.sigmoid(out[data.val_mask]).cpu().numpy()
        val_labels = data.y[data.val_mask].cpu().numpy()
        threshold = _best_threshold(val_labels, val_probs)

        test_probs = torch.sigmoid(out[data.test_mask]).cpu().numpy()
        test_labels = data.y[data.test_mask].cpu().numpy()
        preds = (test_probs >= threshold).astype(int)

    print(f"Selected threshold: {threshold:.2f}")
    print(f"Precision: {precision_score(test_labels, preds, zero_division=0):.4f}")
    print(f"Recall:    {recall_score(test_labels, preds, zero_division=0):.4f}")
    print(f"F1:        {f1_score(test_labels, preds, zero_division=0):.4f}")

    torch.save(model.state_dict(), Path(__file__).parent / "graphsage.pt")
    print("Model saved to ml/graphsage.pt")


def load_gnn_model() -> GraphSAGE:
    data = torch.load(Path(__file__).parent / "pyg_data.pt", weights_only=False, map_location="cpu")
    model = GraphSAGE(in_channels=data.x.shape[1])
    state = torch.load(Path(__file__).parent / "graphsage.pt", 
                       weights_only=True, map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    return model


def evaluate_gnn() -> dict:
    from sklearn.metrics import precision_score, recall_score, f1_score, roc_auc_score, confusion_matrix
    data = torch.load(Path(__file__).parent / "pyg_data.pt", weights_only=False, map_location="cpu")
    model = load_gnn_model()
    model.eval()
    with torch.no_grad():
        logits = model(data.x, data.edge_index)
        probs  = torch.sigmoid(logits).numpy()
    labels = data.y[data.test_mask].numpy()
    scores = probs[data.test_mask.numpy()]
    threshold = _best_threshold(labels, scores)
    preds  = (scores >= threshold).astype(int)
    cm     = confusion_matrix(labels, preds)
    metrics = {
        "threshold":        round(float(threshold), 4),
        "precision":        round(float(precision_score(labels, preds, zero_division=0)), 4),
        "recall":           round(float(recall_score(labels, preds, zero_division=0)), 4),
        "f1":               round(float(f1_score(labels, preds, zero_division=0)), 4),
        "roc_auc":          round(float(roc_auc_score(labels, scores)), 4),
        "confusion_matrix": cm.tolist(),
    }
    for k, v in metrics.items():
        print(f"{k}: {v}")
    return metrics


def compare_baselines() -> dict:
    from sklearn.linear_model import LogisticRegression
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.preprocessing import StandardScaler
    from sklearn.metrics import f1_score, roc_auc_score

    data = torch.load(Path(__file__).parent / "pyg_data.pt", weights_only=False, map_location="cpu")
    X = data.x.numpy()
    y = data.y.numpy().astype(int)

    train_idx = data.train_mask.numpy()
    test_idx  = data.test_mask.numpy()

    X_train, X_test = X[train_idx], X[test_idx]
    y_train, y_test = y[train_idx], y[test_idx]

    scaler  = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s  = scaler.transform(X_test)

    cw = "balanced"

    lr = LogisticRegression(class_weight=cw, max_iter=1000, random_state=42)
    lr.fit(X_train_s, y_train)
    lr_probs = lr.predict_proba(X_test_s)[:, 1]
    lr_preds = (_best_threshold(y_test, lr_probs) <= lr_probs).astype(int)

    rf = RandomForestClassifier(n_estimators=100, class_weight=cw, random_state=42, n_jobs=-1)
    rf.fit(X_train, y_train)
    rf_probs = rf.predict_proba(X_test)[:, 1]
    rf_preds = (_best_threshold(y_test, rf_probs) <= rf_probs).astype(int)

    gnn_metrics = evaluate_gnn()

    results = {
        "logistic_regression": {
            "f1":      round(float(f1_score(y_test, lr_preds, zero_division=0)), 4),
            "roc_auc": round(float(roc_auc_score(y_test, lr_probs)), 4),
        },
        "random_forest": {
            "f1":      round(float(f1_score(y_test, rf_preds, zero_division=0)), 4),
            "roc_auc": round(float(roc_auc_score(y_test, rf_probs)), 4),
        },
        "graphsage": {
            "f1":      gnn_metrics["f1"],
            "roc_auc": gnn_metrics["roc_auc"],
        },
    }

    print("\n--- Baseline Comparison ---")
    for model_name, m in results.items():
        print(f"{model_name:25s} F1={m['f1']:.4f}  AUC={m['roc_auc']:.4f}")
    return results