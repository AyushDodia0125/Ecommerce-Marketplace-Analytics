# 🛒 E-Commerce Marketplace Analytics

An end-to-end data analytics project simulating the analytics function of an Indian e-commerce marketplace (Amazon / Flipkart scale). Covers the full analyst workflow: **database design → SQL analysis → Python EDA → Power BI dashboarding**.

---

## 📌 Project Objective

To demonstrate the core competencies of a **Data / Business Analyst** at a Tier 1 tech company:
- Designing and querying a normalized relational database
- Performing exploratory data analysis and business-oriented Python analytics
- Building executive-level dashboards in Power BI
- Delivering actionable business insights from data

---

## 🗂️ Project Structure

```
Ecommerce-Marketplace-Analytics/
│
├── data/                         # Generated synthetic CSVs (6 tables)
│   ├── customers.csv             # 5,000 customers
│   ├── sellers.csv               #   500 sellers
│   ├── products.csv              # 2,000 SKUs
│   ├── orders.csv                # 50,000 orders (2023–2024)
│   ├── events.csv                # 200,000 clickstream events
│   └── inventory.csv             # ~40,000 weekly inventory snapshots
│
├── sql/
│   ├── 01_schema.sql             # Full DB schema with indexes
│   ├── 02_funnel_analysis.sql    # Conversion funnel (view → purchase)
│   ├── 03_cohort_retention.sql   # Monthly cohort retention matrix
│   ├── 04_supply_gap.sql         # Stockout & supply gap detection
│   ├── 05_seller_scorecard.sql   # Seller ranking with window functions
│   ├── 06_gmv_revenue.sql        # GMV trends, discount burn, AOV
│   └── 07_rfm_segmentation.sql   # RFM customer segmentation
│
├── notebooks/
│   └── eda_and_modeling.ipynb    # Python EDA + forecasting + churn model
│
├── dashboard/
│   ├── marketplace_dashboard.pbix
│   └── screenshots/              # Dashboard page previews
│
├── reports/
│   └── insights_summary.pdf      # 1-page executive findings report
│
├── generate_dataset.py           # Synthetic data generator
├── load_and_validate.py          # SQLite loader + query validator
├── marketplace.db                # Local SQLite database
└── README.md
```

---

## 🗃️ Database Schema

Six normalized tables covering the full marketplace data model:

| Table | Type | Rows | Description |
|---|---|---|---|
| `customers` | Dimension | 5,000 | User profiles, city, segment, acquisition channel |
| `sellers` | Dimension | 500 | Seller profiles, fulfillment type, ratings |
| `products` | Dimension | 2,000 | SKUs with category, brand, MRP |
| `orders` | Fact | 50,000 | Transactions with GMV, discounts, delivery days |
| `events` | Fact | 200,000 | Clickstream: view → cart → checkout → purchase |
| `inventory` | Fact | ~40,000 | Weekly stock snapshots per seller–product pair |

---

## 🔍 SQL Analysis Modules

### 1. Conversion Funnel Analysis (`02_funnel_analysis.sql`)
Tracks drop-off across the purchase funnel: **View → Add to Cart → Checkout → Purchase**
- Overall platform conversion rate
- Funnel by product category (identifies weakest categories)
- Funnel by platform (Android App vs iOS App vs Web)
- Weekly conversion trend with 4-week rolling average

### 2. Customer Cohort Retention (`03_cohort_retention.sql`)
Groups customers by their first-order month and measures repeat purchasing.
- Full 12-month cohort retention matrix
- 30 / 60 / 90-day retention summary
- Average orders per cohort (engagement depth)
- Revenue retained by cohort (monetary impact)

### 3. Supply Gap Detection (`04_supply_gap.sql`)
Identifies where demand outpaces supply — critical for ops and category teams.
- Stockout rate by category
- Demand vs supply ratio with health labels
- Top 20 supply-starved SKUs (most stockout weeks)
- Estimated GMV loss from stockouts
- Seller coverage per category

### 4. Seller Health Scorecard (`05_seller_scorecard.sql`)
Ranks sellers using a composite score across 4 dimensions.
- Composite score with `RANK()` and `NTILE()` window functions
- Delivery performance by fulfillment type (FBA vs Self-Ship)
- Return rate distribution + offender flagging
- GMV Pareto analysis (do top 20% generate 80% of GMV?)
- New vs veteran seller performance comparison

### 5. GMV & Revenue Trends (`06_gmv_revenue.sql`)
Business growth and monetization analysis.
- Month-over-month GMV growth with `LAG()` window function
- Discount burn rate trend (discount-to-GMV ratio)
- Top 5 revenue categories with subcategory breakdown
- Category revenue mix shift (quarterly share change)
- AOV trend by customer segment and quarter

### 6. RFM Customer Segmentation (`07_rfm_segmentation.sql`)
Recency–Frequency–Monetary scoring to identify high-value and at-risk customers.
- RFM scores using `NTILE(5)` window functions
- Segment labels: Champion, Loyal, Potential Loyalist, At-Risk, Lost
- Segment distribution and revenue contribution
- Acquisition channel → segment pipeline (which channels bring Champions?)
- City-level segment breakdown for geo intelligence

---

## 📊 Python Analysis (Notebook)

`notebooks/eda_and_modeling.ipynb` covers:

| Section | Analysis | Libraries |
|---|---|---|
| EDA | Distribution analysis, outlier detection, correlation heatmap | pandas, seaborn, matplotlib |
| Seasonality | Order volume and GMV by month/week | matplotlib |
| Demand Forecasting | 7-day / 30-day forecast per top category | statsmodels (ETS) |
| Churn Prediction | Logistic regression, ROC curve, feature importance | scikit-learn |
| Price Elasticity | Discount depth vs order volume regression | scipy, matplotlib |

---

## 📈 Power BI Dashboard

Four-page interactive `.pbix` dashboard:

| Page | Focus |
|---|---|
| **Executive Overview** | GMV KPIs, MoM growth, category breakdown, trend lines |
| **Supply & Demand** | Stockout rate heatmap, supply gap by category, seller coverage |
| **Customer Retention** | Cohort matrix, RFM segment donut, 90-day retention by cohort |
| **Seller Performance** | Scorecard table, delivery days distribution, top/bottom sellers |

---

## 🚀 Getting Started

### 1. Clone the repo
```bash
git clone https://github.com/AyushDodia0125/Ecommerce-Marketplace-Analytics.git
cd Ecommerce-Marketplace-Analytics
```

### 2. Install dependencies
```bash
pip install pandas numpy
```

### 3. Generate the dataset
```bash
python generate_dataset.py
```

### 4. Load into SQLite and validate all queries
```bash
python load_and_validate.py
```

### 5. For PostgreSQL (production setup)
```bash
psql -U your_user -d your_db -f sql/01_schema.sql
# Then use COPY or pgAdmin to load the CSVs
```

### 6. Open the notebook
```bash
jupyter notebook notebooks/eda_and_modeling.ipynb
```

### 7. Open Power BI dashboard
Open `dashboard/marketplace_dashboard.pbix` in Power BI Desktop.
Connect to `marketplace.db` using the SQLite ODBC connector.

---

## 💡 Key Business Insights

> *(Populated after EDA — sample placeholders shown)*

1. **Electronics and Fashion** drive ~52% of platform GMV but have the highest return rates (12–15%), suggesting a quality or expectation mismatch.
2. **Grocery category** shows the highest stockout rate (~28%), indicating severe supply-side gaps despite strong demand signals.
3. **Champions** (top RFM segment) represent only 8% of customers but contribute 34% of total GMV — retention efforts should prioritize this segment.
4. **Social Media** acquisition channel produces the highest share of "Lost" customers, suggesting either misleading ads or poor post-purchase experience.
5. **FBA sellers** deliver 40% faster on average than Self-Ship, but Self-Ship sellers have 18% lower return rates.

---

## 🛠️ Tech Stack

| Layer | Tools |
|---|---|
| Data Generation | Python (pandas, numpy, random) |
| Database | SQLite (dev) / PostgreSQL (prod) |
| SQL | Window functions, CTEs, subqueries, aggregations |
| Python Analysis | pandas, matplotlib, seaborn, scikit-learn, statsmodels |
| Dashboarding | Microsoft Power BI |
| Version Control | Git / GitHub |

---

## 👤 Author

**Ayush Dodia**
- GitHub: [@AyushDodia0125](https://github.com/AyushDodia0125)
- Email: ayushdodia2001@gmail.com
- LinkedIn: [linkedin.com/in/ayushdodia](https://linkedin.com/in/ayushdodia)

---

*This project was self-initiated to demonstrate end-to-end data analytics skills for Data Analyst / Business Analyst / Category Manager roles at Tier 1 tech companies.*
