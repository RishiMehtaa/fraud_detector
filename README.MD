# Achilles: AI-Powered Fraud Intelligence Platform

Achilles is a sophisticated, enterprise-grade fraud detection and investigation platform. It combines **Graph Neural Networks (GNN)**, **Unsupervised Machine Learning**, and **Generative AI** to transform raw transaction logs into actionable criminal intelligence.

---

## **Description**
Achilles is designed to bridge the gap between complex data science and frontline fraud investigation. While traditional systems flag transactions based on simple rules, Achilles analyzes the **relationships** between accounts, identifying sophisticated money laundering patterns like layering, structuring, and shell clusters that others miss.

## **Why Use This?**
- **Detect "Guilt by Association"**: Uses Graph Neural Networks to identify suspicious accounts based on who they interact with, not just how much they spend.
- **Explainable AI (XAI)**: No more "black box" decisions. Every risk score is broken down into specific behavioral contributors.
- **Reduce Investigation Time**: Replaces manual SQL/Excel work with an interactive graph and an AI assistant.
- **Narrative Reporting**: Automatically generates human-readable summaries for SAR (Suspicious Activity Report) filings.

## **Who Can Use This?**
- **Fraud Investigators & Analysts**: To triage alerts and perform deep-dive network analysis.
- **Compliance Officers**: To ensure regulatory requirements are met for AML (Anti-Money Laundering).
- **Risk Managers**: To monitor the overall health and exposure of the financial network.
- **Engineering Teams**: As a reference architecture for high-performance graph processing and AI integration.

## **Features**
- **Interactive 2-Hop Network Graph**: Visual fund flow with animated particles, node dragging, and focus effects.
- **Multi-Model Scoring**: Weighted ensemble of GNN (GraphSAGE) and Isolation Forest.
- **Achilles AI Assistant**: A smart LLM agent that converts natural language into database queries and summarizes findings.
- **Real-time Alert Queue**: Prioritized task list with dynamic "Case Status" management.
- **Automated Evidence Export**: One-click generation of JSON-based evidence files for legal review.
- **Advanced Fund Tracing**: Find multi-hop paths (up to 6 hops) between any two accounts in the system.

## **Model Performance**

Achilles uses a weighted ensemble of GraphSAGE and Isolation Forest. Both models were evaluated on a held-out test set from the PaySim synthetic transaction dataset.

### GraphSAGE (Node-Level Fraud Classification)
| Metric | Score |
|---|---|
| ROC-AUC | 0.9286 |
| F1 | 0.75 |
| Precision | 0.60 |
| Recall | 1.0 |
| Threshold | 0.05 |

Recall of 1.0 means no fraud case was missed on the test set. Precision of 0.60 reflects a deliberate tradeoff — in fraud detection, missing a case is costlier than a false positive.

### Isolation Forest (Transaction-Level Anomaly Scoring)
| Metric | Score |
|---|---|
| ROC-AUC | 0.7038 |
| F1 | 0.176 |
| Precision | 1.0 |
| Recall | 0.097 |

Used as an unsupervised anomaly scorer, not a classifier. ROC-AUC of 0.70 confirms it meaningfully ranks suspicious transactions above normal ones.

### Baseline Comparison (Same Node Feature Matrix)
| Model | F1 | ROC-AUC |
|---|---|---|
| Logistic Regression | 0.50 | 0.60 |
| Random Forest | 0.67 | 0.86 |
| **GraphSAGE** | **0.75** | **0.93** |

GraphSAGE outperforms both tabular baselines because it incorporates neighborhood structure via message passing — fraud rings are inherently graph-structured problems that tabular models cannot capture.

> **Note:** All models are trained on [PaySim](https://www.kaggle.com/datasets/ealaxi/paysim1), a synthetic dataset simulating mobile money transactions. Real-world performance will vary.

## **Architecture**
*(Section intentionally blank for future system diagrams)*

## **Demo Video**
*(Section intentionally blank for video walkthrough)*

---

## **How to Run the Project**

### **Prerequisites**
- Docker & Docker Desktop
- Python 3.10+
- Flutter SDK (latest)
- Groq API Key (for Achilles AI)

### **Step 1: Start the Database**
Achilles uses Neo4j for graph storage. Start it via Docker:
```bash
docker compose up -d
```

### **Step 2: Setup the Backend**
1. Navigate to `/backend`.
2. Create a `.env` file and add your key: `GROQ_API_KEY=your_key_here`.
3. Install dependencies: `pip install -r requirements.txt`.
4. Run the server: `python main.py`.

### **Step 3: Setup the Frontend**
1. Navigate to `/frontend`.
2. Install dependencies: `flutter pub get`.
3. Run the web app: `flutter run -d chrome`.

---

## **Future Scope**
- **Synthetic Identity Detection**: Implementing logic to identify accounts created using forged or stolen digital identities.
- **Live Transaction Ingestion**: Integrating with Kafka or RabbitMQ for sub-second real-time fraud prevention.
- **Collaborative Investigation**: Allowing multiple analysts to leave comments and "tag" colleagues on specific suspicious nodes.
- **Mobile Companion App**: A native mobile version of the Alert Queue for on-the-go risk monitoring.

---
**Developed by a 3rd Year Engineering Student focused on high-performance FinTech solutions.**