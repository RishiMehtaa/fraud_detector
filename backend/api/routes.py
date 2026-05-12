# backend/api/routes.py
from fastapi import APIRouter, Request, Query

router = APIRouter()


@router.get("/graph")
def get_graph(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(100, le=500),
    min_risk: float = Query(0.0),
):
    G = request.app.state.graph
    # scores_list: list[dict] = request.app.state.scores

    # scores_map = {s["account_id"]: s for s in scores_list}
    scores_map = request.app.state.scores_map

    all_nodes = list(G.nodes(data=True))
    filtered = [
        (nid, attrs) for nid, attrs in all_nodes
        if scores_map.get(nid, {}).get("risk_score", 0) >= min_risk
    ]

    start = (page - 1) * limit
    page_nodes = filtered[start: start + limit]
    node_ids = {nid for nid, _ in page_nodes}

    nodes_out = []
    for nid, attrs in page_nodes:
        sc = scores_map.get(nid, {})
        nodes_out.append({
            "id": nid,
            "risk_score": sc.get("risk_score", 0),
            "account_type": attrs.get("account_type", "C"),
            "total_volume": attrs.get("total_volume", 0),
            "triggered_patterns": sc.get("triggered_patterns", []),
        })

    edges_out = []
    for u, v, attrs in G.edges(data=True):
        if u in node_ids and v in node_ids:
            edges_out.append({
                "source": u,
                "target": v,
                "amount": attrs.get("amount", 0),
                "timestamp": attrs.get("timestamp", ""),
                "type": attrs.get("type", ""),
            })

    return {"nodes": nodes_out, "edges": edges_out, "total": len(filtered), "page": page}


@router.get("/alerts")
def get_alerts(request: Request, limit: int = Query(100, le=500)):
    scores_list: list[dict] = request.app.state.scores
    G = request.app.state.graph

    sorted_scores = sorted(scores_list, key=lambda x: x["risk_score"], reverse=True)
    top = sorted_scores[:limit]

    results = []
    for s in top:
        aid = s["account_id"]
        node_attrs = G.nodes.get(aid, {})
        results.append({
            "account_id": aid,
            "risk_score": s["risk_score"],
            "triggered_patterns": s.get("triggered_patterns", []),
            "top_shap_feature": (
                max(s.get("shap_breakdown", {}).items(), key=lambda x: abs(x[1]), default=("", 0))[0]
            ),
            "amount": node_attrs.get("total_volume", 0),
        })

    return results


from fastapi import HTTPException

@router.get("/account/{account_id}")
def get_account(account_id: str, request: Request):
    G = request.app.state.graph
    # scores_map = {s["account_id"]: s for s in request.app.state.scores}
    scores_map = request.app.state.scores_map

    if account_id not in G:
        raise HTTPException(status_code=404, detail="Account not found")

    neighbors_1 = set(G.predecessors(account_id)) | set(G.successors(account_id))
    neighbors_2 = set()
    for n in neighbors_1:
        neighbors_2 |= set(G.predecessors(n)) | set(G.successors(n))
    subgraph_nodes = {account_id} | neighbors_1 | neighbors_2

    sub_nodes = []
    for nid in subgraph_nodes:
        attrs = G.nodes.get(nid, {})
        sc = scores_map.get(nid, {})
        sub_nodes.append({
            "id": nid,
            "risk_score": sc.get("risk_score", 0),
            "account_type": attrs.get("account_type", "C"),
            "total_volume": attrs.get("total_volume", 0),
            "triggered_patterns": sc.get("triggered_patterns", []),
        })

    sub_edges = []
    for u, v, attrs in G.edges(data=True):
        if u in subgraph_nodes and v in subgraph_nodes:
            sub_edges.append({
                "source": u, "target": v,
                "amount": attrs.get("amount", 0),
                "timestamp": str(attrs.get("timestamp", "")),
                "type": attrs.get("type", ""),
            })

    timeline = sorted(
        [e for e in sub_edges if e["source"] == account_id or e["target"] == account_id],
        key=lambda x: x["timestamp"]
    )

    sc = scores_map.get(account_id, {})
    return {
        "account_id": account_id,
        "risk_score": sc.get("risk_score", 0),
        "shap_breakdown": sc.get("shap_breakdown", {}),
        "triggered_patterns": sc.get("triggered_patterns", []),
        "subgraph": {"nodes": sub_nodes, "edges": sub_edges},
        "timeline": timeline,
    }


import networkx as nx

@router.get("/trace/{source}/{dest}")
def trace_path(source: str, dest: str, request: Request):
    G = request.app.state.graph

    for node in (source, dest):
        if node not in G:
            raise HTTPException(status_code=404, detail=f"Account {node} not found")

    try:
        raw_paths = list(nx.all_simple_paths(G, source, dest, cutoff=6))
    except nx.NetworkXError:
        raw_paths = []

    paths_out = []
    for path in raw_paths:
        hops = []
        for i, node in enumerate(path):
            edge_attrs = {}
            if i < len(path) - 1:
                edge_data = G.get_edge_data(path[i], path[i + 1]) or {}
                edge_attrs = {
                    "amount": edge_data.get("amount", 0),
                    "timestamp": str(edge_data.get("timestamp", "")),
                }
            hops.append({"account_id": node, **edge_attrs})
        paths_out.append(hops)

    return {"source": source, "dest": dest, "paths": paths_out}

import os
from groq import Groq

@router.post("/explain/{account_id}")
def explain_account(account_id: str, request: Request):
    # scores_map = {s["account_id"]: s for s in request.app.state.scores}
    scores_map = request.app.state.scores_map
    if account_id not in scores_map:
        raise HTTPException(status_code=404, detail="Account not found in scores")

    sc = scores_map[account_id]
    patterns = sc.get("triggered_patterns", [])
    shap = sc.get("shap_breakdown", {})
    risk = sc.get("risk_score", 0)

    top_shap = sorted(shap.items(), key=lambda x: abs(x[1]), reverse=True)[:3]
    shap_str = ", ".join(f"{k}={v:.2f}" for k, v in top_shap)

    prompt = (
    f"Account {account_id} has a fraud risk score of {risk:.1f}/100. "
    f"Triggered detection patterns: {', '.join(patterns) if patterns else 'none'}. "
    f"Top risk contributors (SHAP): {shap_str}. "
    f"Feature key: gnn=graph neural network score, iso=isolation forest anomaly score, "
    f"cycle=circular transaction pattern, struct=structuring behavior, "
    f"shell=shell cluster membership, dormancy=dormant account reactivation, profile=volume mismatch. "
    f"Write 2-3 sentences explaining why this account is suspicious, in plain English for a fraud investigator."
)

    client = Groq(api_key=os.environ["GROQ_API_KEY"])
    resp = client.chat.completions.create(
        model="llama-3.1-8b-instant",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=150,
    )
    narrative = resp.choices[0].message.content.strip()

    return {"account_id": account_id, "narrative": narrative}


from reports.evidence import build_evidence

@router.get("/evidence/{account_id}")
def get_evidence(account_id: str, request: Request):
    G = request.app.state.graph
    scores_map = request.app.state.scores_map

    if account_id not in scores_map and account_id not in G:
        raise HTTPException(status_code=404, detail="Account not found")

    if account_id not in G and account_id in scores_map:
        sc = scores_map[account_id]
        return {
            "report_id": str(__import__('uuid').uuid4()),
            "generated_at": __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),
            "subject_account": account_id,
            "risk_score": sc.get("risk_score", 0),
            "triggered_patterns": sc.get("triggered_patterns", []),
            "transaction_timeline": [],
            "connected_accounts": [],
            "shap_breakdown": sc.get("shap_breakdown", {}),
            "llm_narrative": "",
            "investigator_notes": "",
        }


    return build_evidence(account_id, scores_map, G)