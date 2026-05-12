# backend/reports/evidence.py
import uuid
from datetime import datetime, timezone


def build_evidence(account_id: str, scores_map: dict, G) -> dict:
    sc = scores_map.get(account_id, {})

    node_attrs = G.nodes.get(account_id, {})
    neighbors = set(G.predecessors(account_id)) | set(G.successors(account_id))

    timeline = []
    for u, v, attrs in G.edges(data=True):
        if u == account_id or v == account_id:
            timeline.append({
                "from": u, "to": v,
                "amount": attrs.get("amount", 0),
                "type": attrs.get("type", ""),
                "timestamp": str(attrs.get("timestamp", "")),
                "is_fraud": attrs.get("is_fraud", 0),
            })
    timeline.sort(key=lambda x: x["timestamp"])

    return {
        "report_id": str(uuid.uuid4()),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "subject_account": account_id,
        "risk_score": sc.get("risk_score", 0),
        "triggered_patterns": sc.get("triggered_patterns", []),
        "transaction_timeline": timeline,
        "connected_accounts": list(neighbors),
        "shap_breakdown": sc.get("shap_breakdown", {}),
        "llm_narrative": "",
        "investigator_notes": "",
    }