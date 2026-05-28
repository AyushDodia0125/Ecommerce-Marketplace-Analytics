# Power BI Dashboard Setup Guide
## E-Commerce Marketplace Analytics

**Estimated time to build: 2–3 hours**
**Output: 4-page interactive .pbix dashboard**

---

## Step 1 — Connect to the Database

1. Open **Power BI Desktop**
2. Click **Get Data → More → Database → ODBC**
3. Select your SQLite ODBC driver (install from https://www.ch-werner.de/sqliteodbc/ if needed)
4. Browse to `marketplace.db` in the project folder
5. In the Navigator, select all 6 tables: `customers`, `sellers`, `products`, `orders`, `events`, `inventory`
6. Click **Load**

**Alternative (CSV import):**
Go to **Get Data → Text/CSV** and load each file from the `/data` folder individually. Repeat for all 6 files.

---

## Step 2 — Set Up Relationships (Model View)

Go to the **Model** view (icon on the left sidebar) and create these relationships:

| From Table | Column | To Table | Column | Cardinality |
|---|---|---|---|---|
| orders | customer_id | customers | customer_id | Many → One |
| orders | seller_id | sellers | seller_id | Many → One |
| orders | product_id | products | product_id | Many → One |
| events | customer_id | customers | customer_id | Many → One |
| events | product_id | products | product_id | Many → One |
| inventory | product_id | products | product_id | Many → One |
| inventory | seller_id | sellers | seller_id | Many → One |

**Cross filter direction:** Single (default) for all relationships.

---

## Step 3 — Create a Date Table

In **Home → Transform Data → New Query → Blank Query**, paste:

```m
let
    StartDate = #date(2023, 1, 1),
    EndDate   = #date(2024, 12, 31),
    DayCount  = Duration.Days(EndDate - StartDate) + 1,
    Source    = List.Dates(StartDate, DayCount, #duration(1,0,0,0)),
    TableFrom = Table.FromList(Source, Splitter.SplitByNothing()),
    ChangedType = Table.TransformColumnTypes(TableFrom, {{"Column1", type date}}),
    Renamed   = Table.RenameColumns(ChangedType, {{"Column1", "Date"}}),
    WithYear  = Table.AddColumn(Renamed, "Year",    each Date.Year([Date]),   Int64.Type),
    WithMonth = Table.AddColumn(WithYear,"Month",   each Date.Month([Date]),  Int64.Type),
    WithMName = Table.AddColumn(WithMonth,"MonthName",each Date.MonthName([Date]), type text),
    WithQ     = Table.AddColumn(WithMName,"Quarter",each "Q" & Text.From(Date.QuarterOfYear([Date])), type text),
    WithWDay  = Table.AddColumn(WithQ, "Weekday",  each Date.DayOfWeekName([Date]), type text)
in
    WithWDay
```

Name this query `DateTable`. Then in Model view, link:
- `DateTable[Date]` → `orders[order_date]` (Mark as Date Table: right-click → Mark as Date Table → Date)

---

## Step 4 — DAX Measures

In **Home → New Measure**, create these measures one by one.

### Core KPIs

```dax
Total GMV =
CALCULATE(
    SUM(orders[gmv]),
    orders[status] <> "Cancelled"
)
```

```dax
Total Orders =
CALCULATE(
    COUNTROWS(orders),
    orders[status] <> "Cancelled"
)
```

```dax
Avg Order Value =
DIVIDE([Total GMV], [Total Orders], 0)
```

```dax
Return Rate % =
DIVIDE(
    CALCULATE(COUNTROWS(orders), orders[return_flag] = TRUE()),
    [Total Orders],
    0
) * 100
```

```dax
Discount Burn Rate % =
DIVIDE(
    CALCULATE(SUM(orders[discount_amt]), orders[status] <> "Cancelled"),
    CALCULATE(SUM(orders[gmv]) + SUM(orders[discount_amt]), orders[status] <> "Cancelled"),
    0
) * 100
```

### MoM Growth

```dax
GMV Previous Month =
CALCULATE(
    [Total GMV],
    DATEADD(DateTable[Date], -1, MONTH)
)
```

```dax
GMV MoM Growth % =
DIVIDE(
    [Total GMV] - [GMV Previous Month],
    [GMV Previous Month],
    0
) * 100
```

### Seller Metrics

```dax
Avg Delivery Days =
CALCULATE(
    AVERAGE(orders[delivery_days]),
    orders[status] = "Delivered",
    NOT ISBLANK(orders[delivery_days])
)
```

```dax
Fulfillment Rate % =
DIVIDE(
    CALCULATE(COUNTROWS(orders), orders[status] = "Delivered"),
    [Total Orders],
    0
) * 100
```

### Supply & Inventory

```dax
Stockout Rate % =
DIVIDE(
    CALCULATE(COUNTROWS(inventory), inventory[stockout_flag] = TRUE()),
    COUNTROWS(inventory),
    0
) * 100
```

```dax
Demand to Supply Ratio =
DIVIDE(
    [Total Orders],
    SUM(inventory[units_available]),
    0
)
```

### Funnel (from Events table)

```dax
Total Views =
CALCULATE(COUNTROWS(events), events[event_type] = "view")
```

```dax
Total Add to Cart =
CALCULATE(COUNTROWS(events), events[event_type] = "add_to_cart")
```

```dax
Total Purchases =
CALCULATE(COUNTROWS(events), events[event_type] = "purchase")
```

```dax
View to Purchase % =
DIVIDE([Total Purchases], [Total Views], 0) * 100
```

---

## Step 5 — Build the 4 Dashboard Pages

### Page 1 — Executive GMV Overview

**Layout:**
- Top row: 4 KPI cards — `Total GMV`, `Total Orders`, `Avg Order Value`, `Return Rate %`
- Middle: Line chart — `Total GMV` by `DateTable[Date]` (month granularity)
- Bottom left: Bar chart — `Total GMV` by `products[category]`
- Bottom right: Waterfall chart — `GMV MoM Growth %` by month

**Slicers (top bar):**
- `DateTable[Year]` (dropdown)
- `products[category]` (multi-select)
- `orders[status]` (multi-select, default exclude Cancelled)

**Formatting tips:**
- KPI card background: `#F0F4F8`
- GMV line chart: accent color `#1a6faf`, fill below the line at 20% opacity
- Bar chart: sorted descending by GMV

---

### Page 2 — Supply & Demand

**Layout:**
- Top row: 3 KPI cards — `Stockout Rate %`, `Demand to Supply Ratio`, `Total GMV` (for context)
- Middle: Clustered bar — `Stockout Rate %` vs `Demand to Supply Ratio` by `products[category]`
- Bottom left: Matrix table — Top 20 SKUs sorted by stockout rate
  - Rows: `products[product_id]`, `products[brand]`
  - Values: `Stockout Rate %`, `Total Orders`, `Avg Order Value`
- Bottom right: Bar — `Total Orders` by `sellers[fulfillment_type]`

**Conditional formatting:**
- On the SKU matrix, apply background color scale on `Stockout Rate %` (white → red)

---

### Page 3 — Customer Retention

**Layout:**
- Top row: 3 KPI cards — `Total Orders`, `Avg Order Value`, `View to Purchase %`
- Middle: Matrix (Cohort Retention) — Rows: `customers[signup_date]` (month), Columns: month number (calculated column), Values: active customers count
- Bottom left: Donut chart — `Total GMV` by `customers[segment]`
- Bottom right: Clustered column — `Total Orders` by `customers[acquisition_channel]`

**To create a simplified cohort view:**
Add a calculated column in `orders`:

```dax
Month Number =
DATEDIFF(
    CALCULATE(MIN(orders[order_date]),
              ALLEXCEPT(orders, orders[customer_id])),
    orders[order_date],
    MONTH
)
```

---

### Page 4 — Seller Performance

**Layout:**
- Top row: 3 KPI cards — `Fulfillment Rate %`, `Avg Delivery Days`, `Return Rate %`
- Middle: Table — Seller scorecard
  - Columns: `sellers[seller_id]`, `sellers[city]`, `sellers[category_focus]`, `sellers[fulfillment_type]`, `Total Orders`, `Total GMV`, `Fulfillment Rate %`, `Avg Delivery Days`, `Return Rate %`
  - Sort by `Total GMV` descending
- Bottom left: Scatter chart — `Avg Delivery Days` (X) vs `Return Rate %` (Y), size = `Total GMV`, color = `sellers[fulfillment_type]`
- Bottom right: Bar chart — `Avg Delivery Days` by `sellers[fulfillment_type]`

**Conditional formatting on Seller Table:**
- `Fulfillment Rate %`: green scale (low = red, high = green)
- `Return Rate %`: red scale (low = green, high = red)
- `Avg Delivery Days`: blue scale (low = dark blue = fast)

---

## Step 6 — Theming & Publish

1. **Theme:** Go to View → Themes → Browse → import a custom JSON theme, or use the built-in "Executive" theme
2. **Page navigation:** Add buttons on each page to navigate between pages (Insert → Buttons → Navigator)
3. **Export screenshots:** File → Export → Export to PDF, or use Print Screen per page into `/dashboard/screenshots/`
4. **Save:** File → Save As → `marketplace_dashboard.pbix`

---

## Recommended Color Palette

| Element | Hex Code |
|---|---|
| Primary blue | `#1a6faf` |
| Accent orange | `#e05c2a` |
| Success green | `#2eaa72` |
| Warning amber | `#d4a017` |
| Neutral gray | `#6c757d` |
| Background | `#f8f9fa` |
| Card background | `#ffffff` |

---

*Once built, export 1 screenshot per page and save to `dashboard/screenshots/` before pushing to GitHub.*
