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
from torch_geometric.transforms import RandomNodeSplit
from sklearn.metrics import precision_score, recall_score, f1_score

ISO_MODEL_PATH = Path(__file__).parent / "iso_forest.pkl"


def _get_iso_scores_by_account() -> dict:
    model = load_model()
    raw_csv = pd.read_csv(Path(__file__).parent.parent / "data" / "paysim.csv")
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

        avg_sent = float(np.mean([e[2]["amount"] for e in out_edges])) if out_edges else 0.0
        avg_recv = float(np.mean([e[2]["amount"] for e in in_edges])) if in_edges else 0.0

        all_edges = out_edges + in_edges
        if all_edges:
            timestamps = [e[2]["timestamp"] for e in all_edges]
            ts_sorted = sorted(timestamps)
            window = pd.Timestamp("2024-01-01") + pd.Timedelta(hours=24)
            recent = [t for t in ts_sorted if t >= ts_sorted[-1] - pd.Timedelta(hours=24)]
            tx_velocity = len(recent)
        else:
            tx_velocity = 0

        iso_score = iso_scores.get(n, 0.0)
        acct_type = 1.0 if str(n).startswith("M") else 0.0

        rows.append([in_deg, out_deg, avg_sent, avg_recv, tx_velocity, iso_score, acct_type])

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

    data = Data(x=x, edge_index=edge_index, y=y)
    torch.save(data, Path(__file__).parent / "pyg_data.pt")
    return data





class GraphSAGE(nn.Module):
    def __init__(self, in_channels: int):
        super().__init__()
        self.conv1 = SAGEConv(in_channels, 64)
        self.conv2 = SAGEConv(64, 32)
        self.classifier = nn.Linear(32, 1)
        self.dropout = nn.Dropout(0.3)

    def forward(self, x, edge_index):
        x = F.relu(self.conv1(x, edge_index))
        x = self.dropout(x)
        x = F.relu(self.conv2(x, edge_index))
        x = self.dropout(x)
        return self.classifier(x).squeeze(-1)


def train_gnn():
    data = torch.load(Path(__file__).parent / "pyg_data.pt")

    transform = RandomNodeSplit(split="train_rest", num_val=0.1, num_test=0.1)
    data = transform(data)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    data = data.to(device)

    model = GraphSAGE(in_channels=data.x.shape[1]).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01)
    criterion = nn.BCEWithLogitsLoss()

    for epoch in range(1, 51):
        model.train()
        optimizer.zero_grad()
        out = model(data.x, data.edge_index)
        loss = criterion(out[data.train_mask], data.y[data.train_mask])
        loss.backward()
        optimizer.step()
        if epoch % 10 == 0:
            print(f"Epoch {epoch:02d} | Loss: {loss.item():.4f}")

    model.eval()
    with torch.no_grad():
        out = model(data.x, data.edge_index)
        preds = (torch.sigmoid(out[data.test_mask]) > 0.5).cpu().numpy()
        labels = data.y[data.test_mask].cpu().numpy()

    print(f"Precision: {precision_score(labels, preds, zero_division=0):.4f}")
    print(f"Recall:    {recall_score(labels, preds, zero_division=0):.4f}")
    print(f"F1:        {f1_score(labels, preds, zero_division=0):.4f}")

    torch.save(model.state_dict(), Path(__file__).parent / "graphsage.pt")
    print("Model saved to ml/graphsage.pt")


def load_gnn_model() -> GraphSAGE:
    model = GraphSAGE(in_channels=7)
    state = torch.load(Path(__file__).parent / "graphsage.pt", 
                       weights_only=True, map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    return model