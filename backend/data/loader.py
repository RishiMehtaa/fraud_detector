import pandas as pd
from pathlib import Path

DATA_PATH = Path(__file__).parent / "paysim.csv"

def load() -> pd.DataFrame:
    df = pd.read_csv(DATA_PATH)
    df = df.rename(columns={
        "nameOrig": "account_id",
        "nameDest": "dest_id",
        "type": "type",
        "amount": "amount",
        "isFraud": "is_fraud"
    })
    df["timestamp"] = pd.to_datetime("2024-01-01") + pd.to_timedelta(df["step"], unit="h")
    return df[["account_id", "dest_id", "type", "amount", "timestamp", "is_fraud"]]