-- =============================================================================
-- 03_cohort_retention.sql
-- Ecommerce Marketplace Analytics — Customer Cohort Retention Analysis
--
-- Business Question:
--   Of the customers who first ordered in month X, what % are still
--   ordering 1, 2, 3... months later?
--
-- Answers:
--   1. Full monthly cohort retention matrix
--   2. 30 / 60 / 90-day retention summary by cohort
--   3. Average orders per cohort (engagement depth)
--   4. Revenue retained by cohort (monetisation lens)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Monthly cohort retention matrix
-- The classic analyst deliverable. Each row = one cohort month.
-- Each column = month number (0 = signup month, 1 = next month, etc.)
-- Value = % of cohort still active that month.
-- -----------------------------------------------------------------------------
WITH cohort_base AS (
    -- First order date defines the cohort for each customer
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(order_date))::DATE AS cohort_month
    FROM orders
    WHERE status != 'Cancelled'
    GROUP BY customer_id
),
order_activity AS (
    SELECT
        o.customer_id,
        c.cohort_month,
        DATE_TRUNC('month', o.order_date)::DATE AS order_month,
        -- Month number relative to cohort start (0-indexed)
        (DATE_PART('year',  o.order_date) - DATE_PART('year',  c.cohort_month)) * 12
        + (DATE_PART('month', o.order_date) - DATE_PART('month', c.cohort_month))
            AS month_number
    FROM orders o
    JOIN cohort_base c ON o.customer_id = c.customer_id
    WHERE o.status != 'Cancelled'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM cohort_base
    GROUP BY cohort_month
),
retention_raw AS (
    SELECT
        oa.cohort_month,
        oa.month_number,
        COUNT(DISTINCT oa.customer_id) AS active_customers
    FROM order_activity oa
    GROUP BY oa.cohort_month, oa.month_number
)
SELECT
    r.cohort_month,
    cs.cohort_size,
    r.month_number,
    r.active_customers,
    ROUND(r.active_customers * 100.0 / cs.cohort_size, 2) AS retention_pct
FROM retention_raw r
JOIN cohort_sizes cs ON r.cohort_month = cs.cohort_month
WHERE r.month_number BETWEEN 0 AND 11   -- First 12 months
ORDER BY r.cohort_month, r.month_number;


-- -----------------------------------------------------------------------------
-- Query 2: 30 / 60 / 90-day retention summary
-- Flattened view — easy to present in dashboards or exec summaries.
-- -----------------------------------------------------------------------------
WITH cohort_base AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM orders
    WHERE status != 'Cancelled'
    GROUP BY customer_id
),
retention_flags AS (
    SELECT
        c.customer_id,
        c.first_order_date,
        -- Flag if customer ordered within 30/60/90 days after first order
        MAX(CASE WHEN o.order_date BETWEEN c.first_order_date + 1
                                       AND c.first_order_date + 30
                  AND o.status != 'Cancelled'
                 THEN 1 ELSE 0 END) AS retained_30d,
        MAX(CASE WHEN o.order_date BETWEEN c.first_order_date + 1
                                       AND c.first_order_date + 60
                  AND o.status != 'Cancelled'
                 THEN 1 ELSE 0 END) AS retained_60d,
        MAX(CASE WHEN o.order_date BETWEEN c.first_order_date + 1
                                       AND c.first_order_date + 90
                  AND o.status != 'Cancelled'
                 THEN 1 ELSE 0 END) AS retained_90d
    FROM cohort_base c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_id, c.first_order_date
)
SELECT
    DATE_TRUNC('month', first_order_date)::DATE   AS cohort_month,
    COUNT(*)                                       AS cohort_size,
    ROUND(AVG(retained_30d) * 100, 2)             AS retention_30d_pct,
    ROUND(AVG(retained_60d) * 100, 2)             AS retention_60d_pct,
    ROUND(AVG(retained_90d) * 100, 2)             AS retention_90d_pct
FROM retention_flags
GROUP BY DATE_TRUNC('month', first_order_date)
ORDER BY cohort_month;


-- -----------------------------------------------------------------------------
-- Query 3: Average orders per cohort over time
-- Measures engagement depth — Premium customers should show higher values.
-- -----------------------------------------------------------------------------
WITH cohort_base AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(order_date))::DATE AS cohort_month
    FROM orders
    WHERE status != 'Cancelled'
    GROUP BY customer_id
),
customer_orders AS (
    SELECT
        o.customer_id,
        c.cohort_month,
        COUNT(*) AS total_orders
    FROM orders o
    JOIN cohort_base c ON o.customer_id = c.customer_id
    WHERE o.status != 'Cancelled'
    GROUP BY o.customer_id, c.cohort_month
)
SELECT
    cohort_month,
    COUNT(DISTINCT customer_id)       AS cohort_size,
    SUM(total_orders)                 AS total_orders,
    ROUND(AVG(total_orders), 2)       AS avg_orders_per_customer,
    MAX(total_orders)                 AS max_orders_single_customer
FROM customer_orders
GROUP BY cohort_month
ORDER BY cohort_month;


-- -----------------------------------------------------------------------------
-- Query 4: Revenue retained by cohort
-- Shows which cohorts are most valuable in monetary terms —
-- connects retention to business impact (GMV contribution).
-- -----------------------------------------------------------------------------
WITH cohort_base AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(order_date))::DATE AS cohort_month
    FROM orders
    WHERE status != 'Cancelled'
    GROUP BY customer_id
)
SELECT
    c.cohort_month,
    COUNT(DISTINCT o.customer_id)           AS active_customers,
    ROUND(SUM(o.gmv), 2)                   AS total_gmv,
    ROUND(AVG(o.gmv), 2)                   AS avg_order_value,
    ROUND(SUM(o.discount_amt), 2)          AS total_discounts,
    ROUND(SUM(o.discount_amt) * 100.0
          / NULLIF(SUM(o.gmv + o.discount_amt), 0), 2) AS discount_rate_pct
FROM orders o
JOIN cohort_base c ON o.customer_id = c.customer_id
WHERE o.status != 'Cancelled'
GROUP BY c.cohort_month
ORDER BY c.cohort_month;
