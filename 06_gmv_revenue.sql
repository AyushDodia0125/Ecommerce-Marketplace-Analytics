-- =============================================================================
-- 06_gmv_revenue.sql
-- Ecommerce Marketplace Analytics — GMV & Revenue Trend Analysis
--
-- Business Question:
--   How is the business growing? Which categories drive revenue?
--   Are discounts sustainable? What is the seasonal pattern?
--
-- Answers:
--   1. Month-over-month GMV growth with % change
--   2. Discount-to-GMV ratio trend (discount burn analysis)
--   3. Top 5 revenue-generating categories
--   4. Category revenue share shift over time (mix shift analysis)
--   5. Average order value (AOV) trend by quarter
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Month-over-month GMV growth
-- Core business health metric. Uses LAG() to compute growth rate.
-- -----------------------------------------------------------------------------
WITH monthly_gmv AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE    AS month,
        COUNT(order_id)                          AS total_orders,
        ROUND(SUM(gmv), 2)                       AS gmv,
        ROUND(SUM(discount_amt), 2)              AS total_discounts,
        ROUND(AVG(gmv), 2)                       AS avg_order_value
    FROM orders
    WHERE status NOT IN ('Cancelled')
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT
    month,
    total_orders,
    gmv,
    total_discounts,
    avg_order_value,
    LAG(gmv) OVER (ORDER BY month)                          AS prev_month_gmv,
    ROUND(
        (gmv - LAG(gmv) OVER (ORDER BY month))
        * 100.0 / NULLIF(LAG(gmv) OVER (ORDER BY month), 0)
    , 2)                                                     AS mom_growth_pct,
    -- 3-month rolling average for smoothed trend
    ROUND(
        AVG(gmv) OVER (
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                                        AS rolling_3m_avg_gmv
FROM monthly_gmv
ORDER BY month;


-- -----------------------------------------------------------------------------
-- Query 2: Discount burn rate analysis
-- High discount-to-GMV ratio eats into unit economics.
-- This query flags months where discounting crossed a threshold.
-- -----------------------------------------------------------------------------
WITH monthly_discounts AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE            AS month,
        ROUND(SUM(gmv), 2)                               AS gmv,
        ROUND(SUM(discount_amt), 2)                      AS total_discounts,
        ROUND(SUM(gmv + discount_amt), 2)                AS gross_revenue,  -- Pre-discount price
        ROUND(
            SUM(discount_amt) * 100.0
            / NULLIF(SUM(gmv + discount_amt), 0), 2
        )                                                 AS discount_rate_pct
    FROM orders
    WHERE status NOT IN ('Cancelled')
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT
    month,
    gmv,
    total_discounts,
    gross_revenue,
    discount_rate_pct,
    CASE
        WHEN discount_rate_pct > 30 THEN 'Aggressive — Review'
        WHEN discount_rate_pct > 20 THEN 'Moderate'
        ELSE 'Conservative'
    END                                                   AS discount_health,
    LAG(discount_rate_pct) OVER (ORDER BY month)          AS prev_month_discount_rate,
    ROUND(
        discount_rate_pct
        - LAG(discount_rate_pct) OVER (ORDER BY month)
    , 2)                                                   AS discount_rate_change
FROM monthly_discounts
ORDER BY month;


-- -----------------------------------------------------------------------------
-- Query 3: Top 5 revenue-generating categories (all-time)
-- With sub-breakdown of top subcategory within each.
-- -----------------------------------------------------------------------------
WITH category_revenue AS (
    SELECT
        p.category,
        p.subcategory,
        COUNT(o.order_id)               AS total_orders,
        ROUND(SUM(o.gmv), 2)            AS total_gmv,
        ROUND(AVG(o.gmv), 2)            AS avg_order_value,
        ROUND(AVG(o.discount_amt), 2)   AS avg_discount,
        ROUND(
            SUM(CASE WHEN o.return_flag THEN 1 ELSE 0 END) * 100.0
            / COUNT(o.order_id), 2
        )                               AS return_rate_pct
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY p.category, p.subcategory
),
category_totals AS (
    SELECT
        category,
        SUM(total_gmv) AS category_gmv
    FROM category_revenue
    GROUP BY category
),
ranked AS (
    SELECT
        cr.*,
        ct.category_gmv,
        RANK() OVER (PARTITION BY cr.category ORDER BY cr.total_gmv DESC) AS subcategory_rank
    FROM category_revenue cr
    JOIN category_totals ct ON cr.category = ct.category
)
SELECT
    category,
    ROUND(category_gmv, 2)                              AS category_total_gmv,
    RANK() OVER (ORDER BY category_gmv DESC)            AS category_rank,
    subcategory,
    total_orders,
    total_gmv                                           AS subcategory_gmv,
    avg_order_value,
    avg_discount,
    return_rate_pct
FROM ranked
WHERE subcategory_rank = 1    -- Top subcategory within each category
ORDER BY category_rank
LIMIT 5;


-- -----------------------------------------------------------------------------
-- Query 4: Category revenue mix shift (quarterly)
-- Shows which categories are gaining or losing share over time.
-- This is the kind of strategic insight analysts present to leadership.
-- -----------------------------------------------------------------------------
WITH quarterly_category AS (
    SELECT
        DATE_TRUNC('quarter', o.order_date)::DATE   AS quarter,
        p.category,
        ROUND(SUM(o.gmv), 2)                        AS gmv
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY DATE_TRUNC('quarter', o.order_date), p.category
),
quarterly_totals AS (
    SELECT quarter, SUM(gmv) AS total_gmv
    FROM quarterly_category
    GROUP BY quarter
)
SELECT
    qc.quarter,
    qc.category,
    qc.gmv,
    ROUND(qc.gmv * 100.0 / qt.total_gmv, 2)        AS gmv_share_pct,
    LAG(ROUND(qc.gmv * 100.0 / qt.total_gmv, 2))
        OVER (PARTITION BY qc.category ORDER BY qc.quarter)
                                                     AS prev_quarter_share_pct,
    ROUND(
        (qc.gmv * 100.0 / qt.total_gmv)
        - LAG(qc.gmv * 100.0 / qt.total_gmv)
          OVER (PARTITION BY qc.category ORDER BY qc.quarter)
    , 2)                                             AS share_change_pp
FROM quarterly_category qc
JOIN quarterly_totals qt ON qc.quarter = qt.quarter
ORDER BY qc.quarter, gmv_share_pct DESC;


-- -----------------------------------------------------------------------------
-- Query 5: Average Order Value (AOV) trend by quarter + segment
-- Breaking AOV by customer segment shows Premium vs Regular customer value.
-- -----------------------------------------------------------------------------
SELECT
    DATE_TRUNC('quarter', o.order_date)::DATE   AS quarter,
    c.segment,
    COUNT(o.order_id)                           AS total_orders,
    ROUND(AVG(o.gmv), 2)                        AS avg_order_value,
    ROUND(MIN(o.gmv), 2)                        AS min_order_value,
    ROUND(MAX(o.gmv), 2)                        AS max_order_value,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.gmv)
    , 2)                                         AS median_order_value
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.status NOT IN ('Cancelled')
GROUP BY DATE_TRUNC('quarter', o.order_date), c.segment
ORDER BY quarter, c.segment;
