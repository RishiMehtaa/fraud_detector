import os, re
from groq import Groq
from neo4j import GraphDatabase

NEO4J_URI = "bolt://localhost:7687"
NEO4J_USER = "neo4j"
NEO4J_PASS = "password123"

SCHEMA = """
Node label: Account
  Properties: id (string), account_type (string: "C" or "M"), 
              total_volume (float), tx_count (integer)

Relationship: (Account)-[:SENT]->(Account)
  Properties: amount (float), timestamp (string ISO datetime),
              type (string: CASH_IN CASH_OUT DEBIT PAYMENT TRANSFER),
              is_fraud (boolean)

Indexes exist on Account.id.
Use parameterised WHERE clauses. Never use PROFILE or EXPLAIN.
Return at most 50 rows unless the question asks for aggregates.
"""

PRESETS = {
    "find_cycles": (
    "MATCH (a:Account)-[:SENT*3..4]->(a) "
    "WITH a LIMIT 5 "
    "RETURN a.id AS account_id"
),
    "find_shells": (
        "MATCH (a:Account)-[:SENT]->(b:Account) "
        "WITH b, count(a) AS in_count, sum(a.total_volume) AS vol "
        "WHERE in_count >= 3 "
        "RETURN b.id AS shell_account, in_count, vol ORDER BY vol DESC LIMIT 20"
    ),
    "top_risk": (
        "MATCH (a:Account) "
        "WHERE a.total_volume > 1000000 "
        "RETURN a.id, a.total_volume, a.tx_count "
        "ORDER BY a.total_volume DESC LIMIT 20"
    ),
    "dormant_activations": (
        "MATCH (a:Account)-[r:SENT]->() "
        "WITH a, min(r.timestamp) AS first_tx, max(r.timestamp) AS last_tx, "
        "     count(r) AS tx_count "
        "WHERE tx_count <= 2 "
        "RETURN a.id, first_tx, last_tx, tx_count LIMIT 20"
    ),
    "trace_path": (
        "MATCH path=shortestPath((a:Account {id: 'C1231006815'})"
        "-[:SENT*..6]->(b:Account {id: 'C1666544105'})) "
        "RETURN [n IN nodes(path) | n.id] AS path_nodes"
    ),
}

_groq = Groq(api_key=os.environ["GROQ_API_KEY"])


def _cypher_from_nl(question: str) -> str:
    resp = _groq.chat.completions.create(
        model="llama-3.1-8b-instant",
        messages=[
            {
                "role": "system",
                "content": (
                    "You are a Neo4j Cypher expert. Given a question, return ONLY "
                    "a valid Cypher query and nothing else — no explanation, no markdown, "
                    "no backticks. Use this schema:\n" + SCHEMA
                ),
            },
            {"role": "user", "content": question},
        ],
        temperature=0,
        max_tokens=300,
    )
    raw = resp.choices[0].message.content.strip()
    # Strip accidental markdown fences
    raw = re.sub(r"^```[a-z]*\n?", "", raw)
    raw = re.sub(r"\n?```$", "", raw)
    return raw.strip()


def _run_cypher(cypher: str) -> list[dict]:
    driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASS))
    try:
        with driver.session() as session:
            result = session.run(cypher)
            return [dict(r) for r in result]
    finally:
        driver.close()


def query(question: str, preset: str | None = None) -> dict:
    if preset and preset in PRESETS:
        cypher = PRESETS[preset]
    else:
        cypher = _cypher_from_nl(question)

    try:
        records = _run_cypher(cypher)
        return {"cypher": cypher, "records": records, "error": None}
    except Exception as e:
        return {"cypher": cypher, "records": [], "error": str(e)}