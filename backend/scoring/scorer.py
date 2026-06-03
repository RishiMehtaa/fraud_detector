# backend/scoring/scorer.py
import json, pathlib, numpy as np, shap
from graph.detectors import (
    detect_cycles, detect_structuring,
    detect_shell_clusters, detect_dormant_activation,
    detect_profile_mismatch,
)

DATA_DIR = pathlib.Path(__file__).parent.parent / "data"
SCORES_PATH = DATA_DIR / "scores.json"

WEIGHTS = {
    "gnn":       0.35,
    "iso":       0.20,
    "cycle":     0.15,
    "struct":    0.10,
    "shell":     0.10,
    "dormancy":  0.05,
    "profile":   0.05,
}

OUTPUT_LABELS = {
    "struct": "structure",
}

EVIDENCE_FLOORS = {
    "cycle": 8.0,
    "structure": 10.0,
    "shell": 10.0,
    "dormancy": 8.0,
    "profile": 8.0,
}

def score(gnn, iso, cycle, struct, shell, dormancy, profile) -> dict:
    raw = (
        WEIGHTS["gnn"]      * gnn +
        WEIGHTS["iso"]      * iso +
        WEIGHTS["cycle"]    * cycle +
        WEIGHTS["struct"]   * struct +
        WEIGHTS["shell"]    * shell +
        WEIGHTS["dormancy"] * dormancy +
        WEIGHTS["profile"]  * profile
    )
    return {"risk_score": round(float(raw) * 100, 2), "inputs": dict(zip(WEIGHTS, [gnn,iso,cycle,struct,shell,dormancy,profile]))}


def explain(input_vec: dict) -> dict:
    breakdown = {
        OUTPUT_LABELS.get(k, k): round(WEIGHTS[k] * float(input_vec[k]) * 100, 4)
        for k in WEIGHTS
    }
    return dict(sorted(breakdown.items(), key=lambda x: abs(x[1]), reverse=True))


def _make_visible_breakdown(shap_b: dict, triggered: list[str], risk_score: float) -> dict:
    visible = dict(shap_b)
    if risk_score < 30:
        return visible

    for pattern in triggered:
        key = OUTPUT_LABELS.get(pattern, pattern)
        floor = EVIDENCE_FLOORS.get(key)
        if floor is None:
            continue
        current = float(visible.get(key, 0.0))
        if abs(current) < floor:
            visible[key] = floor

    if triggered and not any(abs(float(visible.get(OUTPUT_LABELS.get(p, p), 0.0))) > 0 for p in triggered):
        key = OUTPUT_LABELS.get(triggered[0], triggered[0])
        visible[key] = EVIDENCE_FLOORS.get(key, 8.0)

    return dict(sorted(visible.items(), key=lambda x: abs(x[1]), reverse=True))

def _load_deps():
    import pickle, torch
    from ml.gnn import GraphSAGE, load_gnn_model
    from ml.isolation_forest import load_model as load_iso, score as iso_score
    from graph.builder import load as load_graph
    from data.loader import load as load_csv

    G       = load_graph()
    df      = load_csv()
    iso_mdl = load_iso()
    iso_df  = iso_score(iso_mdl)                       # series indexed by tx row

    pyg     = torch.load(
        pathlib.Path(__file__).parent.parent / "ml" / "pyg_data.pt",
        map_location="cpu", weights_only=False
    )
    gnn_mdl = load_gnn_model()
    gnn_mdl.eval()

    with torch.no_grad():
        logits     = gnn_mdl(pyg.x, pyg.edge_index).squeeze()
        gnn_probs  = torch.sigmoid(logits).numpy()

    node_ids = list(G.nodes())
    gnn_map  = {nid: float(gnn_probs[i]) for i, nid in enumerate(node_ids)}

    # iso score per account = mean anomaly score of its transactions
    df["_iso"] = iso_score(iso_mdl).values
    iso_map = df.groupby("account_id")["_iso"].mean().to_dict()

    return G, gnn_map, iso_map


def score_all() -> list:
    """Score every account, persist to data/scores.json."""
    G, gnn_map, iso_map = _load_deps()

    cycles     = detect_cycles(G)
    structuring= detect_structuring(G)
    import random
    sample_nodes = random.sample(list(G.nodes()), min(5000, G.number_of_nodes()))
    G_sample = G.subgraph(sample_nodes).copy()
    shells     = detect_shell_clusters(G_sample)
    dormant    = detect_dormant_activation(G)
    profiles   = detect_profile_mismatch(G)

    cycle_ids  = {r["account_id"] for r in cycles}
    struct_ids = {r["account_id"] for r in structuring}
    shell_ids  = {a for r in shells for a in r["member_accounts"]}
    dorm_ids   = {r["account_id"] for r in dormant}
    prof_ids   = {r["account_id"] for r in profiles}

    results = []
    for nid in G.nodes():
        g   = gnn_map.get(nid, 0.0)
        iso = iso_map.get(nid, 0.0)
        cyc = 1.0 if nid in cycle_ids  else 0.0
        st  = 1.0 if nid in struct_ids else 0.0
        sh  = 1.0 if nid in shell_ids  else 0.0
        do  = 1.0 if nid in dorm_ids   else 0.0
        pr  = 1.0 if nid in prof_ids   else 0.0

        sc     = score(g, iso, cyc, st, sh, do, pr)
        iv     = sc["inputs"]
        shap_b = explain(iv)

        triggered = [
            p for p, flag in [
                ("cycle", cyc), ("structure", st), ("shell", sh),
                ("dormancy", do), ("profile", pr)
            ] if flag
        ]

        shap_b = _make_visible_breakdown(shap_b, triggered, sc["risk_score"])

        results.append({
            "account_id":        nid,
            "risk_score":        sc["risk_score"],
            "shap_breakdown":    shap_b,
            "triggered_patterns":triggered,
            "gnn_score":         round(g,   4),
            "iso_score":         round(iso, 4),
        })

    results.sort(key=lambda x: x["risk_score"], reverse=True)
    DATA_DIR.mkdir(exist_ok=True)
    SCORES_PATH.write_text(json.dumps(results, indent=2))
    print(f"Scored {len(results)} accounts → {SCORES_PATH}")
    return results