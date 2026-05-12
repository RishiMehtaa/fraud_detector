# backend/main.py
import json
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from graph.builder import load
from ml.gnn import load_gnn_model
from ml.isolation_forest import load_model


# @asynccontextmanager
# async def lifespan(app: FastAPI):
#     app.state.graph = load()
#     with open("data/scores.json", "r", encoding="utf-8") as f:
#         app.state.scores = json.load(f)
#     app.state.gnn = load_gnn_model()
#     app.state.iso = load_model()
#     yield

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.graph = load()
    with open("data/scores.json", "r", encoding="utf-8") as f:
        scores_list = json.load(f)
    app.state.scores = scores_list
    app.state.scores_map = {s["account_id"]: s for s in scores_list}
    app.state.gnn = load_gnn_model()
    app.state.iso = load_model()
    yield


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080", "http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# In backend/main.py — add these two lines after app.add_middleware(...)
from api.routes import router
app.include_router(router)


@app.get("/")
def health(request=None):
    from starlette.requests import Request
    g = app.state.graph
    return {"status": "ok", "nodes": g.number_of_nodes(), "edges": g.number_of_edges()}