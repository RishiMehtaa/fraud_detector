import networkx as nx
from itertools import islice
from collections import defaultdict
import pandas as pd




def detect_cycles(G: nx.DiGraph) -> list[dict]:
    results = []
    try:
        cycles = nx.simple_cycles(G)
        for cycle in islice(cycles, 50000):
            if not (3 <= len(cycle) <= 7):
                continue

            edges = []
            valid = True
            for i in range(len(cycle)):
                src = cycle[i]
                dst = cycle[(i + 1) % len(cycle)]
                if not G.has_edge(src, dst):
                    valid = False
                    break
                edges.append(G[src][dst])

            if not valid:
                continue

            timestamps = [e.get("timestamp").timestamp() if hasattr(e.get("timestamp"), "timestamp") else float(e.get("timestamp", 0)) for e in edges]
            duration_hrs = (max(timestamps) - min(timestamps)) / 3600
            if duration_hrs > 72:
                continue

            amounts = [e.get("amount", 0) for e in edges]
            flow_valid = True
            for i in range(1, len(amounts)):
                if amounts[i - 1] == 0:
                    flow_valid = False
                    break
                if amounts[i] / amounts[i - 1] < 0.8:
                    flow_valid = False
                    break
            if not flow_valid:
                continue

            total_amount = sum(amounts)
            confidence = min(1.0, total_amount / 1_000_000)

            results.append({
                "account_id": cycle[0],
                "cycle_path": cycle,
                "total_amount": total_amount,
                "duration_hrs": round(duration_hrs, 2),
                "confidence": round(confidence, 4),
            })

    except Exception as e:
        print(f"Cycle detection error: {e}")

    return results


def detect_structuring(G: nx.DiGraph) -> list[dict]:
    records = []
    for node in G.nodes():
        edges = [(G[node][dst]["timestamp"], G[node][dst]["amount"])
                 for dst in G.successors(node)
                 if G[node][dst]["amount"] < 50000]

        if len(edges) < 3:
            continue

        df = pd.DataFrame(edges, columns=["timestamp", "amount"])
        df["timestamp"] = pd.to_datetime(df["timestamp"])
        df = df.sort_values("timestamp")

        window = pd.Timedelta(hours=24)
        flagged = []
        for i, row in df.iterrows():
            mask = (df["timestamp"] >= row["timestamp"]) & \
                   (df["timestamp"] < row["timestamp"] + window)
            w = df[mask]
            if len(w) < 3:
                continue
            total = w["amount"].sum()
            if total <= 150000:
                continue
            cv = w["amount"].std() / w["amount"].mean() if w["amount"].mean() > 0 else 999
            if cv >= 0.2:
                continue
            flagged.append({
                "account_id": node,
                "window_start": str(w["timestamp"].min()),
                "window_end": str(w["timestamp"].max()),
                "tx_count": len(w),
                "total": round(total, 2),
                "cv": round(cv, 4),
                "confidence": round(min(1.0, total / 500000), 4),
            })

        if flagged:
            records.append(max(flagged, key=lambda x: x["total"]))

    return records

def detect_shell_clusters(G: nx.DiGraph) -> list[dict]:
    import community as community_louvain

    undirected = G.to_undirected()
    partition = community_louvain.best_partition(undirected)

    clusters = {}
    for node, cid in partition.items():
        clusters.setdefault(cid, []).append(node)

    results = []
    for cid, members in clusters.items():
        size = len(members)
        if not (3 <= size <= 20):
            continue

        member_set = set(members)
        internal_edges = sum(
            1 for u, v in G.edges()
            if u in member_set and v in member_set
        )
        total_edges = sum(
            1 for u, v in G.edges()
            if u in member_set or v in member_set
        )
        if total_edges == 0:
            continue

        internal_ratio = internal_edges / total_edges
        if internal_ratio <= 0.9:
            continue

        total_volume = sum(
            G[u][v]["amount"] for u, v in G.edges()
            if u in member_set or v in member_set
        )
        confidence = round(min(1.0, internal_ratio), 4)

        results.append({
            "cluster_id": cid,
            "member_accounts": members,
            "internal_ratio": round(internal_ratio, 4),
            "total_volume": round(total_volume, 2),
            "confidence": confidence,
        })

    return results


def detect_dormant_activation(G: nx.DiGraph) -> list[dict]:
    import pandas as pd

    results = []
    for node in G.nodes():
        edges = sorted(
            [(G[node][dst]["timestamp"], G[node][dst]["amount"])
             for dst in G.successors(node)],
            key=lambda x: x[0]
        )
        if len(edges) < 2:
            continue

        timestamps = [e[0] for e in edges]
        amounts = [e[1] for e in edges]

        for i in range(1, len(timestamps)):
            gap_days = (timestamps[i] - timestamps[i-1]).total_seconds() / 86400
            if gap_days < 180:
                continue

            pre_txns = amounts[:i]
            post_txns = amounts[i:]

            pre_monthly_avg = (sum(pre_txns) / len(pre_txns)) * 30 if pre_txns else 0
            if pre_monthly_avg == 0:
                continue

            post_volume = sum(post_txns)
            if post_volume <= 10 * pre_monthly_avg:
                continue

            results.append({
                "account_id": node,
                "dormancy_days": round(gap_days, 1),
                "pre_avg": round(pre_monthly_avg, 2),
                "post_volume": round(post_volume, 2),
                "confidence": round(min(1.0, post_volume / (10 * pre_monthly_avg) / 10), 4),
            })
            break

    return results

def detect_profile_mismatch(G: nx.DiGraph) -> list[dict]:
    import numpy as np

    PROFILES = {
        "C": {"mean": 200000, "std": 50000},
        "M": {"mean": 5000000, "std": 1000000},
    }

    results = []
    for node in G.nodes():
        prefix = node[0] if node[0] in PROFILES else None
        if prefix is None:
            continue

        total_volume = sum(
            G[node][dst]["amount"] for dst in G.successors(node)
        )
        if total_volume == 0:
            continue

        profile = PROFILES[prefix]
        z_score = (total_volume - profile["mean"]) / profile["std"]
        if z_score <= 3:
            continue

        results.append({
            "account_id": node,
            "account_type": "customer" if prefix == "C" else "merchant",
            "expected_range": f"{profile['mean'] - 2*profile['std']} - {profile['mean'] + 2*profile['std']}",
            "actual_volume": round(total_volume, 2),
            "z_score": round(z_score, 4),
            "confidence": round(min(1.0, z_score / 10), 4),
        })

    return results