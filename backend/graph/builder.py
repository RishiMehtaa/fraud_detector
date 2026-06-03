import networkx as nx
import pandas as pd
import pickle
from pathlib import Path
from data.loader import load as load_csv

GRAPH_PATH = Path(__file__).parent.parent / "data" / "graph.pkl"

def build() -> nx.DiGraph:
    df = load_csv()
    G = nx.DiGraph()

    # Node stats
    sent = df.groupby("account_id").agg(
        total_volume=("amount", "sum"),
        tx_count=("amount", "count")
    ).reset_index()

    all_accounts = pd.DataFrame(
        pd.concat([df["account_id"], df["dest_id"]]).unique(), columns=["account_id"]
    )
    nodes_df = all_accounts.merge(sent, on="account_id", how="left").fillna(0)
    nodes_df["account_type"] = nodes_df["account_id"].str[0]

    G.add_nodes_from([
        (r.account_id, {"account_type": r.account_type,
                        "total_volume": r.total_volume,
                        "tx_count": int(r.tx_count)})
        for r in nodes_df.itertuples()
    ])

    # Edges
    G.add_edges_from([
        (r.account_id, r.dest_id,
         {"amount": r.amount, "timestamp": r.timestamp,
          "type": r.type, "is_fraud": r.is_fraud})
        for r in df.itertuples()
    ])

    with open(GRAPH_PATH, "wb") as f:
        pickle.dump(G, f)

    return G



def get_stats(G: nx.DiGraph) -> dict:
    fraud_edges = sum(1 for _, _, d in G.edges(data=True) if d.get("is_fraud") == 1)
    degrees = [d for _, d in G.degree()]
    components = nx.number_weakly_connected_components(G)
    return {
        "node_count": G.number_of_nodes(),
        "edge_count": G.number_of_edges(),
        "fraud_edge_count": fraud_edges,
        "avg_degree": round(sum(degrees) / len(degrees), 4),
        "connected_components": components
    }

def load():
    import pickle
    with open(GRAPH_PATH, "rb") as f:
        return pickle.load(f)

def load_sample(n=10000):
    import pickle
    with open(GRAPH_PATH, "rb") as f:
        G = pickle.load(f)
    nodes = list(G.nodes())[:n]
    return G.subgraph(nodes).copy()