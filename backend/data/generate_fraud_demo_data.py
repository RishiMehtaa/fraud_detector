from __future__ import annotations

import csv
import json
import random
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).parent
OUTPUT_CSV = ROOT / "fraud_demo_test.csv"
OUTPUT_MANIFEST = ROOT / "fraud_demo_manifest.json"

SEED = 42
random.seed(SEED)


@dataclass
class AccountState:
    balance: float
    last_step: int = 0
    tx_count: int = 0
    tx_sum: float = 0.0
    total_in: float = 0.0
    total_out: float = 0.0


def account_name(prefix: str, index: int) -> str:
    return f"{prefix}{index:010d}"[:11]


def make_accounts(prefix: str, count: int, min_balance: float, max_balance: float) -> dict[str, AccountState]:
    return {
        account_name(prefix, i): AccountState(balance=round(random.uniform(min_balance, max_balance), 2))
        for i in range(1, count + 1)
    }


def pick_amount(low: float, high: float) -> float:
    return round(random.uniform(low, high), 2)


def emit_row(
    rows: list[dict],
    account_id: str,
    dest_id: str,
    tx_type: str,
    amount: float,
    step: int,
    fraud: int,
    accounts: dict[str, AccountState],
    note: str,
    case_id: str,
    fraud_type: str,
) -> None:
    src = accounts[account_id]
    dst = accounts.setdefault(dest_id, AccountState(balance=round(random.uniform(5000, 25000), 2)))

    oldbalance_org = round(src.balance, 2)
    oldbalance_dest = round(dst.balance, 2)

    src.balance = round(max(0.0, src.balance - amount), 2)
    dst.balance = round(dst.balance + amount, 2)

    newbalance_org = round(src.balance, 2)
    newbalance_dest = round(dst.balance, 2)

    src.last_step = step
    src.tx_count += 1
    src.tx_sum += amount
    src.total_out += amount
    dst.total_in += amount

    rows.append(
        {
            "nameOrig": account_id,
            "nameDest": dest_id,
            "type": tx_type,
            "amount": amount,
            "step": step,
            "oldbalanceOrg": oldbalance_org,
            "newbalanceOrig": newbalance_org,
            "oldbalanceDest": oldbalance_dest,
            "newbalanceDest": newbalance_dest,
            "isFraud": fraud,
            "fraud_type": fraud_type,
            "case_id": case_id,
            "note": note,
        }
    )


def normal_activity(rows: list[dict], accounts: dict[str, AccountState], start_step: int, count: int) -> int:
    names = list(accounts.keys())
    step = start_step
    types = ["PAYMENT", "CASH_OUT", "CASH_IN", "DEBIT", "TRANSFER"]

    for _ in range(count):
        src = random.choice(names)
        dst = random.choice([n for n in names if n != src])
        tx_type = random.choice(types)
        amount = pick_amount(50, 25000)
        if amount > accounts[src].balance and accounts[src].balance > 0:
            amount = round(accounts[src].balance * random.uniform(0.15, 0.65), 2)
        amount = max(25.0, amount)
        emit_row(rows, src, dst, tx_type, amount, step, 0, accounts, "baseline activity", "normal", "normal")
        step += random.randint(1, 4)

    return step


def cycle_ring(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    ring = ["C9000000001", "C9000000002", "C9000000003", "C9000000004"]
    for i, name in enumerate(ring):
        accounts.setdefault(name, AccountState(balance=round(150000 + i * 25000, 2)))

    step = start_step
    amounts = [42000.0, 41800.0, 41500.0, 41250.0]
    for i in range(8):
        src = ring[i % len(ring)]
        dst = ring[(i + 1) % len(ring)]
        amount = amounts[i % len(amounts)]
        emit_row(rows, src, dst, "TRANSFER", amount, step, 1, accounts, "circular movement", "cycle_01", "cycle")
        step += 1

    return step + 2


def structuring(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    src = "C9100000001"
    accounts.setdefault(src, AccountState(balance=350000.0))
    destinations = [f"C91010000{i:02d}" for i in range(1, 8)]
    for i, dest in enumerate(destinations):
        accounts.setdefault(dest, AccountState(balance=round(12000 + i * 700, 2)))

    step = start_step
    for i in range(14):
        dest = destinations[i % len(destinations)]
        amount = pick_amount(18000, 24500)
        emit_row(rows, src, dest, "TRANSFER", amount, step, 1, accounts, "smurfed transfer", "struct_01", "structure")
        step += random.randint(1, 3)

    return step + 3


def dormant_reactivation(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    src = "C9200000001"
    accounts.setdefault(src, AccountState(balance=220000.0))
    dst = "C9201000001"
    accounts.setdefault(dst, AccountState(balance=43000.0))

    step = start_step
    for _ in range(2):
        emit_row(rows, src, dst, "PAYMENT", pick_amount(75, 250), step, 0, accounts, "low dormant activity", "dormant_01", "normal")
        step += 2

    step += 2200
    for _ in range(5):
        amount = pick_amount(28000, 54000)
        emit_row(rows, src, dst, "TRANSFER", amount, step, 1, accounts, "dormant reactivation spike", "dormant_01", "dormant_reactivation")
        step += 1

    return step + 5


def shell_cluster(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    shell_nodes = ["C9300000001", "C9300000002", "C9300000003", "C9300000004", "C9300000005"]
    for i, name in enumerate(shell_nodes):
        accounts.setdefault(name, AccountState(balance=round(50000 + i * 3000, 2)))

    step = start_step
    for i in range(16):
        src = shell_nodes[i % len(shell_nodes)]
        dst = shell_nodes[(i + 1) % len(shell_nodes)]
        amount = pick_amount(9500, 18500)
        emit_row(rows, src, dst, "TRANSFER", amount, step, 1, accounts, "dense shell network", "shell_01", "shell_cluster")
        step += 1

    return step + 4


def profile_mismatch(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    merchant = "M9400000001"
    customer = "C9400000001"
    accounts.setdefault(merchant, AccountState(balance=720000.0))
    accounts.setdefault(customer, AccountState(balance=6200.0))

    dests = [f"M94010000{i:02d}" for i in range(1, 5)]
    for i, dest in enumerate(dests):
        accounts.setdefault(dest, AccountState(balance=round(180000 + i * 10000, 2)))

    step = start_step
    for _ in range(6):
        dest = random.choice(dests)
        amount = pick_amount(180000, 340000)
        emit_row(rows, customer, dest, "TRANSFER", amount, step, 1, accounts, "customer volume mismatch", "profile_01", "profile_mismatch")
        step += 2

    for _ in range(4):
        amount = pick_amount(1500, 4500)
        emit_row(rows, merchant, customer, "PAYMENT", amount, step, 0, accounts, "merchant routine activity", "profile_01", "normal")
        step += 3

    return step + 2


def escalate_primaries(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    """Create 5 high-severity accounts (one per fraud pattern) with intensified transactions."""
    primaries = {
        'cycle': 'C9000000001',
        'structure': 'C9100000001',
        'dormant': 'C9200000001',
        'shell': 'C9300000001',
        'profile': 'M9400000001',
    }
    step = start_step

    # Ensure primaries exist with healthy balances
    for k, acct in primaries.items():
        accounts.setdefault(acct, AccountState(balance=500000.0))

    # cycle primary: add many transfers forming cycles and cross-links
    ring_peers = ['C9000000002', 'C9000000003', 'C9000000004']
    for i, peer in enumerate(ring_peers):
        accounts.setdefault(peer, AccountState(balance=200000.0 + i * 20000))
    for i in range(6):
        dst = ring_peers[i % len(ring_peers)]
        emit_row(rows, primaries['cycle'], dst, 'TRANSFER', pick_amount(50000, 95000), step, 1, accounts, 'escalated cycle transfer', 'cycle_escalate', 'cycle')
        step += 1

    # structure primary: many smurfed transfers to many small accounts
    for i in range(12):
        dest = f"C910200{i:03d}"
        accounts.setdefault(dest, AccountState(balance=round(5000 + i * 100, 2)))
        emit_row(rows, primaries['structure'], dest, 'TRANSFER', pick_amount(15000, 24000), step, 1, accounts, 'escalated structuring', 'struct_escalate', 'structure')
        step += 1

    # dormant primary: big sudden reactivation transfers to external nodes
    for i in range(6):
        dest = f"C920200{i:03d}"
        accounts.setdefault(dest, AccountState(balance=round(30000 + i * 2000, 2)))
        emit_row(rows, primaries['dormant'], dest, 'TRANSFER', pick_amount(30000, 120000), step, 1, accounts, 'escalated dormant reactivation', 'dormant_escalate', 'dormant_reactivation')
        step += 2

    # shell primary: dense intra-shell transfers
    shell_peers = [f"C93010000{i:03d}" for i in range(1, 7)]
    for i, peer in enumerate(shell_peers):
        accounts.setdefault(peer, AccountState(balance=round(40000 + i * 3000, 2)))
    for i in range(20):
        src = shell_peers[i % len(shell_peers)]
        dst = shell_peers[(i + 1) % len(shell_peers)]
        emit_row(rows, src, dst, 'TRANSFER', pick_amount(12000, 60000), step, 1, accounts, 'escalated shell transfer', 'shell_escalate', 'shell_cluster')
        step += 1

    # profile primary: huge anomalous transfers from low-volume customer
    cust = 'C9400000001'
    accounts.setdefault(cust, AccountState(balance=5000.0))
    for i in range(5):
        dest = f"M940200{i:03d}"
        accounts.setdefault(dest, AccountState(balance=round(200000 + i * 10000, 2)))
        emit_row(rows, cust, dest, 'TRANSFER', pick_amount(180000, 360000), step, 1, accounts, 'escalated profile mismatch', 'profile_escalate', 'profile_mismatch')
        step += 2

    return step + 3


def create_medium_cases(rows: list[dict], accounts: dict[str, AccountState], start_step: int) -> int:
    """Create ~8 medium-severity accounts that trigger one pattern each with moderate amounts."""
    step = start_step
    medium_defs = [
        ('cycle', 'C9000000003'),
        ('cycle', 'C9000000004'),
        ('structure', 'C9101000002'),
        ('structure', 'C9101000003'),
        ('dormant', 'C9201000002'),
        ('shell', 'C9300000002'),
        ('profile', 'C9400000002'),
        ('profile', 'M9401000002'),
    ]

    for fraud_type, acct in medium_defs:
        accounts.setdefault(acct, AccountState(balance=round(20000 + random.uniform(0, 50000), 2)))
        # create 2 moderate suspicious transactions
        for i in range(2):
            dst = account_name('C', random.randint(80, 200))
            amount = pick_amount(8000, 40000)
            emit_row(rows, acct, dst, 'TRANSFER', amount, step, 1, accounts, 'medium suspicious', f'med_{fraud_type}', fraud_type)
            step += random.randint(1, 3)

    return step + 2


def build_dataset() -> tuple[list[dict], dict]:
    rows: list[dict] = []
    accounts = make_accounts("C", 70, 18000, 260000)
    accounts.update(make_accounts("M", 18, 90000, 750000))

    step = 1
    step = normal_activity(rows, accounts, step, 220)
    step = cycle_ring(rows, accounts, step)
    step = normal_activity(rows, accounts, step, 40)
    step = structuring(rows, accounts, step)
    step = normal_activity(rows, accounts, step, 40)
    step = dormant_reactivation(rows, accounts, step)
    step = normal_activity(rows, accounts, step, 30)
    step = shell_cluster(rows, accounts, step)
    step = normal_activity(rows, accounts, step, 30)
    step = profile_mismatch(rows, accounts, step)
    step = normal_activity(rows, accounts, step, 50)
    # Add targeted high-severity and medium-severity cases
    step = escalate_primaries(rows, accounts, step)
    step = create_medium_cases(rows, accounts, step)
    rows.sort(key=lambda r: (r["step"], r["nameOrig"], r["nameDest"]))

    summary = defaultdict(int)
    for row in rows:
        summary[row["fraud_type"]] += 1 if row["isFraud"] else 0

    manifest = {
        "seed": SEED,
        "row_count": len(rows),
        "fraud_rows": sum(1 for row in rows if row["isFraud"] == 1),
        "fraud_by_type": dict(summary),
        "fraud_case_ids": ["cycle_01", "struct_01", "dormant_01", "shell_01", "profile_01"],
        "schema": [
            "nameOrig",
            "nameDest",
            "type",
            "amount",
            "step",
            "oldbalanceOrg",
            "newbalanceOrig",
            "oldbalanceDest",
            "newbalanceDest",
            "isFraud",
            "fraud_type",
            "case_id",
            "note",
        ],
    }
    return rows, manifest


def write_outputs(rows: list[dict], manifest: dict) -> None:
    fieldnames = manifest["schema"]
    with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    OUTPUT_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main() -> None:
    rows, manifest = build_dataset()
    write_outputs(rows, manifest)
    print(f"Wrote {len(rows)} rows to {OUTPUT_CSV}")
    print(f"Wrote manifest to {OUTPUT_MANIFEST}")


if __name__ == "__main__":
    main()