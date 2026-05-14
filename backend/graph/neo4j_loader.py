import os, pickle, csv, subprocess
import networkx as nx

PKL = os.path.join(os.path.dirname(__file__), "../data/graph.pkl")
IMPORT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../data/neo4j_import"))


def export_csvs():
    os.makedirs(IMPORT_DIR, exist_ok=True)
    with open(PKL, "rb") as f:
        G: nx.DiGraph = pickle.load(f)

    nodes_path = os.path.join(IMPORT_DIR, "nodes.csv")
    edges_path = os.path.join(IMPORT_DIR, "edges.csv")

    with open(nodes_path, "w", newline="") as f:
        w = csv.writer(f)
        # neo4j-admin import requires these exact header names
        w.writerow(["accountId:ID", "account_type", "total_volume:float", "tx_count:int", ":LABEL"])
        for n, d in G.nodes(data=True):
            w.writerow([
                n,
                d.get("account_type", "C"),
                float(d.get("total_volume", 0)),
                int(d.get("tx_count", 0)),
                "Account"
            ])

    with open(edges_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([":START_ID", ":END_ID", "amount:float", "timestamp", "type", "is_fraud:boolean", ":TYPE"])
        for u, v, d in G.edges(data=True):
            w.writerow([
                u, v,
                float(d.get("amount", 0)),
                str(d.get("timestamp", "")),
                str(d.get("type", "")),
                "true" if d.get("is_fraud") else "false",
                "SENT"
            ])

    print(f"Exported {G.number_of_nodes()} nodes, {G.number_of_edges()} edges")


def bulk_import():
    # Stop container, wipe data, bulk import, restart
    print("Stopping Neo4j...")
    subprocess.run(["docker", "compose", "down"], cwd=os.path.join(os.path.dirname(__file__), "../../"), check=True)

    print("Running bulk import...")
    result = subprocess.run([
        "docker", "run", "--rm",
        "-v", f"{IMPORT_DIR}:/import",
        "-v", "fraud_detection_neo4j_data:/data",
        "neo4j:5",
        "neo4j-admin", "database", "import", "full",
        "--nodes=/import/nodes.csv",
        "--relationships=/import/edges.csv",
        "--overwrite-destination=true",
        "neo4j"
    ], capture_output=False)

    if result.returncode != 0:
        print("Import failed.")
        return

    print("Restarting Neo4j...")
    subprocess.run(["docker", "compose", "up", "-d"], cwd=os.path.join(os.path.dirname(__file__), "../../"), check=True)
    print("Done. Wait ~15s for Neo4j to start, then verify at http://localhost:7474")


if __name__ == "__main__":
    export_csvs()
    bulk_import()