-- =============================================================================
-- 04_supply_gap.sql
-- Ecommerce Marketplace Analytics — Supply Gap Detection
--
-- Business Question:
--   Which categories and SKUs have demand outpacing supply?
--   Where are stockouts hurting GMV the most?
--
-- Answers:
--   1. Stockout rate by product category
--   2. Demand vs supply ratio per category
--   3. Top 20 supply-starved SKUs (most stockout weeks)
--   4. Stockout impact on revenue (estimated GMV loss)
--   5. City-level supply coverage gap
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Stockout rate by category
-- % of inventory records where the product was out of stock.
-- Benchmarks which categories need urgent seller recruitment.
-- -----------------------------------------------------------------------------
SELECT
    p.category,
    COUNT(*)                                                AS total_inventory_records,
    SUM(CASE WHEN i.stockout_flag THEN 1 ELSE 0 END)       AS stockout_records,
    ROUND(
        SUM(CASE WHEN i.stockout_flag THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2
    )                                                       AS stockout_rate_pct,
    ROUND(AVG(i.units_available), 1)                       AS avg_units_available,
    ROUND(AVG(i.units_sold), 1)                            AS avg_units_sold_per_week
FROM inventory i
JOIN products p ON i.product_id = p.product_id
GROUP BY p.category
ORDER BY stockout_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- Query 2: Demand vs supply ratio per category
-- Ratio > 1 = demand exceeds available supply — a supply gap signal.
-- Uses order volume as a proxy for demand.
-- -----------------------------------------------------------------------------
WITH demand AS (
    SELECT
        p.category,
        COUNT(o.order_id)   AS total_orders,
        SUM(o.gmv)          AS total_demand_gmv
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY p.category
),
supply AS (
    SELECT
        p.category,
        SUM(i.units_available)  AS total_units_available,
        SUM(i.units_sold)       AS total_units_sold
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    GROUP BY p.category
)
SELECT
    d.category,
    d.total_orders,
    ROUND(d.total_demand_gmv, 0)            AS demand_gmv,
    s.total_units_available,
    s.total_units_sold,
    ROUND(
        d.total_orders * 1.0
        / NULLIF(s.total_units_available, 0), 3
    )                                        AS demand_to_supply_ratio,
    CASE
        WHEN d.total_orders * 1.0 / NULLIF(s.total_units_available, 0) > 0.5
        THEN 'High Pressure'
        WHEN d.total_orders * 1.0 / NULLIF(s.total_units_available, 0) > 0.2
        THEN 'Moderate Pressure'
        ELSE 'Healthy'
    END                                      AS supply_health
FROM demand d
JOIN supply s ON d.category = s.category
ORDER BY demand_to_supply_ratio DESC;


-- -----------------------------------------------------------------------------
-- Query 3: Top 20 supply-starved SKUs
-- Products with the most stockout weeks — prioritise for seller outreach
-- or direct sourcing negotiations.
-- -----------------------------------------------------------------------------
SELECT
    i.product_id,
    p.category,
    p.subcategory,
    p.brand,
    p.mrp,
    COUNT(*)                                                AS total_weeks_tracked,
    SUM(CASE WHEN i.stockout_flag THEN 1 ELSE 0 END)       AS weeks_out_of_stock,
    ROUND(
        SUM(CASE WHEN i.stockout_flag THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2
    )                                                       AS stockout_pct,
    ROUND(AVG(i.units_sold), 1)                            AS avg_weekly_units_sold
FROM inventory i
JOIN products p ON i.product_id = p.product_id
GROUP BY i.product_id, p.category, p.subcategory, p.brand, p.mrp
HAVING COUNT(*) >= 4                  -- Only SKUs with at least 4 weeks of data
ORDER BY stockout_pct DESC, avg_weekly_units_sold DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Query 4: Estimated GMV loss from stockouts
-- Approximates revenue lost when a product was out of stock.
-- Calculated as: stockout_weeks × avg_weekly_units_sold × product_mrp
-- This is a conservative estimate — important for exec-level framing.
-- -----------------------------------------------------------------------------
WITH sku_stats AS (
    SELECT
        i.product_id,
        COUNT(*)                                                AS total_weeks,
        SUM(CASE WHEN i.stockout_flag THEN 1 ELSE 0 END)       AS stockout_weeks,
        AVG(CASE WHEN NOT i.stockout_flag
                 THEN i.units_sold ELSE NULL END)               AS avg_units_sold_when_in_stock
    FROM inventory i
    GROUP BY i.product_id
)
SELECT
    p.category,
    COUNT(DISTINCT s.product_id)           AS skus_affected,
    SUM(s.stockout_weeks)                  AS total_stockout_weeks,
    ROUND(
        SUM(
            s.stockout_weeks
            * COALESCE(s.avg_units_sold_when_in_stock, 0)
            * p.mrp
        ), 0
    )                                       AS estimated_gmv_loss
FROM sku_stats s
JOIN products p ON s.product_id = p.product_id
WHERE s.stockout_weeks > 0
GROUP BY p.category
ORDER BY estimated_gmv_loss DESC;


-- -----------------------------------------------------------------------------
-- Query 5: Seller coverage by category
-- How many active sellers exist per category relative to product count?
-- Low coverage = monopoly risk and stockout vulnerability.
-- -----------------------------------------------------------------------------
WITH seller_coverage AS (
    SELECT
        s.category_focus                    AS category,
        COUNT(DISTINCT s.seller_id)         AS active_sellers,
        ROUND(AVG(s.active_listings), 0)    AS avg_listings_per_seller
    FROM sellers s
    GROUP BY s.category_focus
),
product_counts AS (
    SELECT category, COUNT(*) AS total_products
    FROM products
    GROUP BY category
)
SELECT
    pc.category,
    pc.total_products,
    COALESCE(sc.active_sellers, 0)          AS active_sellers,
    COALESCE(sc.avg_listings_per_seller, 0) AS avg_listings_per_seller,
    ROUND(
        pc.total_products * 1.0
        / NULLIF(sc.active_sellers, 0), 1
    )                                        AS products_per_seller,
    CASE
        WHEN sc.active_sellers < 10 THEN 'Critical — Recruit Sellers'
        WHEN sc.active_sellers < 30 THEN 'Low Coverage'
        ELSE 'Adequate'
    END                                      AS coverage_status
FROM product_counts pc
LEFT JOIN seller_coverage sc ON pc.category = sc.category
ORDER BY products_per_seller DESC NULLS FIRST;
