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
        "MATCH (a:Account)-[:SENT]->(b:Account)-[:SENT]->(c:Account)-[:SENT]->(a) "
        "RETURN a.id AS account_id, b.id AS hop_1, c.id AS hop_2 LIMIT 10"
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
        "MATCH path=shortestPath((a:Account {id: 'C0000000012'})"
        "-[:SENT*..6]->(b:Account {id: 'C0000000009'})) "
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
                    "a valid Cypher query and nothing else. DO NOT use parameters like $account_id. "
                    "Hardcode values into the query. Use this schema:\n" + SCHEMA
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
    """
    Smart query router:
    1. Decide if we need Cypher or just a conversational reply.
    2. If Cypher, run it and summarize with data.
    3. If conversational, just reply.
    """
    if preset and preset in PRESETS:
        cypher = PRESETS[preset]
        try:
            records = _run_cypher(cypher)
            summary = _summarize_with_data(question, records)
            return {"cypher": cypher, "records": records, "summary": summary, "error": None}
        except Exception as e:
            return {"cypher": cypher, "records": [], "summary": "I encountered a technical issue while scanning the network, but I'm still here to help. What else can I check for you?", "error": str(e)}

    # 1. Routing & Intent Detection
    routing_prompt = (
        "You are a helpful Fraud Investigation Assistant named Achilles "
        "Your task is to decide if the user's question requires querying a Neo4j database or if it's a general/conversational question.\n\n"
        "DATABASE SCHEMA:\n" + SCHEMA + "\n\n"
        "If the user asks for specific data, counts, paths, or patterns (e.g., 'find cycles', 'how many transfers', 'is account X risky'), "
        "reply with 'QUERY: <Cypher Query>'.\n"
        "If the user is just greeting you, asking about your capabilities, or making small talk, reply with 'TALK: <Conversational Response>'.\n"
        "NEOR4J RULES: DO NOT use parameters ($id). Hardcode values. Return at most 50 rows.\n"
        "User Question: " + question
    )

    try:
        resp = _groq.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[{"role": "user", "content": routing_prompt}],
            temperature=0,
        )
        decision = resp.choices[0].message.content.strip()

        if decision.startswith("QUERY:"):
            cypher = decision.replace("QUERY:", "").strip()
            # Clean cypher
            cypher = re.sub(r"^```[a-z]*\n?", "", cypher)
            cypher = re.sub(r"\n?```$", "", cypher).strip()
            
            try:
                records = _run_cypher(cypher)
                summary = _summarize_with_data(question, records)
                return {"cypher": cypher, "records": records, "summary": summary, "error": None}
            except Exception as e:
                return {"cypher": cypher, "records": [], "summary": "I tried to look that up in the transaction logs, but ran into a database error. Could you try rephrasing your question?", "error": str(e)}
        
        else:
            # It's a conversational talk response
            talk_reply = decision.replace("TALK:", "").strip()
            return {"cypher": None, "records": [], "summary": talk_reply, "error": None}

    except Exception as e:
        return {"cypher": None, "records": [], "summary": "I'm sorry, I'm having trouble processing that right now. How can I assist you otherwise?", "error": str(e)}


def _summarize_with_data(question: str, records: list) -> str:
    if not records:
        return "I scanned the transaction network for you, but I couldn't find any records that match that specific criteria at the moment."

    summary_prompt = (
        "You are an expert Fraud Investigator. Below is the data retrieved from our graph database regarding a user's question.\n"
        "Write a detailed, professional, and helpful response. Use specific IDs, amounts, and counts from the data provided.\n"
        "If multiple items are found, summarize the most important ones. Speak like a human colleague.\n\n"
        f"Question: {question}\n"
        f"Data: {str(records[:15])}"
    )

    try:
        resp = _groq.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[{"role": "user", "content": summary_prompt}],
            temperature=0.5,
            max_tokens=400,
        )
        return resp.choices[0].message.content.strip()
    except:
        return f"I found {len(records)} relevant records in the database, including accounts like {records[0].get('id', 'unknown')}. How would you like me to proceed with this info?"