-- =============================================================================
-- 05_seller_scorecard.sql
-- Ecommerce Marketplace Analytics — Seller Health Scorecard
--
-- Business Question:
--   Which sellers are our best performers? Which are dragging down
--   customer experience with slow delivery and high returns?
--
-- Answers:
--   1. Composite seller scorecard with RANK()
--   2. Delivery performance by fulfillment type
--   3. Return rate distribution and top offenders
--   4. Seller GMV contribution (top 20% Pareto check)
--   5. New vs veteran seller performance comparison
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Composite seller scorecard using window functions
-- Scores each seller on 4 dimensions, then ranks overall.
-- Ideal for a sortable dashboard table in Power BI.
-- -----------------------------------------------------------------------------
WITH seller_metrics AS (
    SELECT
        o.seller_id,
        COUNT(o.order_id)                                           AS total_orders,
        ROUND(SUM(o.gmv), 2)                                        AS total_gmv,
        ROUND(AVG(o.gmv), 2)                                        AS avg_order_value,
        ROUND(
            SUM(CASE WHEN o.status = 'Delivered' THEN 1 ELSE 0 END) * 100.0
            / COUNT(o.order_id), 2
        )                                                            AS fulfillment_rate_pct,
        ROUND(AVG(o.delivery_days), 1)                              AS avg_delivery_days,
        ROUND(
            SUM(CASE WHEN o.return_flag THEN 1 ELSE 0 END) * 100.0
            / COUNT(o.order_id), 2
        )                                                            AS return_rate_pct
    FROM orders o
    GROUP BY o.seller_id
    HAVING COUNT(o.order_id) >= 10       -- Only sellers with meaningful volume
),
scored AS (
    SELECT
        sm.*,
        s.fulfillment_type,
        s.seller_rating,
        s.city,
        s.category_focus,
        -- Composite score (higher = better):
        --   fulfillment_rate contributes positively
        --   return_rate contributes negatively
        --   delivery speed contributes (inverse)
        --   seller_rating contributes positively
        ROUND(
            (sm.fulfillment_rate_pct * 0.35)
            + ((5.0 - sm.return_rate_pct) * 4 * 0.25)
            + ((14.0 - COALESCE(sm.avg_delivery_days, 14)) / 14.0 * 100 * 0.20)
            + (s.seller_rating * 20 * 0.20)
        , 2) AS composite_score
    FROM seller_metrics sm
    JOIN sellers s ON sm.seller_id = s.seller_id
)
SELECT
    seller_id,
    city,
    category_focus,
    fulfillment_type,
    total_orders,
    total_gmv,
    fulfillment_rate_pct,
    avg_delivery_days,
    return_rate_pct,
    seller_rating,
    composite_score,
    RANK() OVER (ORDER BY composite_score DESC)                 AS overall_rank,
    RANK() OVER (PARTITION BY category_focus
                 ORDER BY composite_score DESC)                  AS rank_in_category,
    NTILE(4) OVER (ORDER BY composite_score DESC)               AS performance_quartile
    -- Quartile 1 = Top performers, Quartile 4 = Bottom performers
FROM scored
ORDER BY overall_rank;


-- -----------------------------------------------------------------------------
-- Query 2: Delivery performance by fulfillment type
-- FBA typically faster than Self-Ship — this query proves (or disproves) it.
-- -----------------------------------------------------------------------------
SELECT
    s.fulfillment_type,
    COUNT(o.order_id)                           AS total_orders,
    ROUND(AVG(o.delivery_days), 2)              AS avg_delivery_days,
    MIN(o.delivery_days)                        AS min_delivery_days,
    MAX(o.delivery_days)                        AS max_delivery_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.delivery_days)
    , 1)                                         AS median_delivery_days,
    ROUND(
        SUM(CASE WHEN o.delivery_days <= 3 THEN 1 ELSE 0 END) * 100.0
        / COUNT(o.order_id), 2
    )                                            AS pct_delivered_in_3_days,
    ROUND(
        SUM(CASE WHEN o.delivery_days > 7 THEN 1 ELSE 0 END) * 100.0
        / COUNT(o.order_id), 2
    )                                            AS pct_delayed_over_7_days
FROM orders o
JOIN sellers s ON o.seller_id = s.seller_id
WHERE o.status = 'Delivered'
  AND o.delivery_days IS NOT NULL
GROUP BY s.fulfillment_type
ORDER BY avg_delivery_days;


-- -----------------------------------------------------------------------------
-- Query 3: Return rate distribution + top offenders
-- Sellers with high return rates damage customer trust and increase costs.
-- -----------------------------------------------------------------------------
WITH seller_returns AS (
    SELECT
        o.seller_id,
        s.category_focus,
        s.fulfillment_type,
        COUNT(o.order_id)                                               AS total_orders,
        SUM(CASE WHEN o.return_flag THEN 1 ELSE 0 END)                 AS returns,
        ROUND(
            SUM(CASE WHEN o.return_flag THEN 1 ELSE 0 END) * 100.0
            / COUNT(o.order_id), 2
        )                                                                AS return_rate_pct
    FROM orders o
    JOIN sellers s ON o.seller_id = s.seller_id
    GROUP BY o.seller_id, s.category_focus, s.fulfillment_type
    HAVING COUNT(o.order_id) >= 10
)
SELECT
    seller_id,
    category_focus,
    fulfillment_type,
    total_orders,
    returns,
    return_rate_pct,
    CASE
        WHEN return_rate_pct > 15 THEN 'Critical — Review Account'
        WHEN return_rate_pct > 10 THEN 'High — Send Warning'
        WHEN return_rate_pct > 5  THEN 'Moderate — Monitor'
        ELSE 'Healthy'
    END AS return_health_flag,
    RANK() OVER (ORDER BY return_rate_pct DESC) AS return_rate_rank
FROM seller_returns
ORDER BY return_rate_pct DESC
LIMIT 30;


-- -----------------------------------------------------------------------------
-- Query 4: Seller GMV Pareto analysis
-- Do the top 20% of sellers generate 80% of GMV? (Classic Pareto check)
-- Uses cumulative window sum to identify the tipping point.
-- -----------------------------------------------------------------------------
WITH seller_gmv AS (
    SELECT
        seller_id,
        ROUND(SUM(gmv), 2) AS total_gmv
    FROM orders
    WHERE status NOT IN ('Cancelled', 'Returned')
    GROUP BY seller_id
),
ranked AS (
    SELECT
        seller_id,
        total_gmv,
        RANK() OVER (ORDER BY total_gmv DESC) AS gmv_rank,
        COUNT(*) OVER ()                       AS total_sellers,
        SUM(total_gmv) OVER ()                 AS platform_total_gmv,
        SUM(total_gmv) OVER (ORDER BY total_gmv DESC
                             ROWS BETWEEN UNBOUNDED PRECEDING
                             AND CURRENT ROW)  AS cumulative_gmv
    FROM seller_gmv
)
SELECT
    gmv_rank,
    seller_id,
    total_gmv,
    ROUND(total_gmv * 100.0 / platform_total_gmv, 3)      AS gmv_share_pct,
    ROUND(cumulative_gmv * 100.0 / platform_total_gmv, 2)  AS cumulative_gmv_pct,
    ROUND(gmv_rank * 100.0 / total_sellers, 1)             AS pct_of_sellers
FROM ranked
ORDER BY gmv_rank
LIMIT 50;


-- -----------------------------------------------------------------------------
-- Query 5: New vs veteran seller performance
-- Sellers who joined > 1 year before their first order vs newer sellers.
-- Shows onboarding effectiveness and seller lifecycle value.
-- NOTE: PostgreSQL users can replace the JULIANDAY logic with:
--       DATE_PART('year', AGE(first_order_date, s.join_date)) >= 1
-- -----------------------------------------------------------------------------
WITH seller_first_order AS (
    SELECT seller_id, MIN(order_date) AS first_order_date
    FROM orders
    GROUP BY seller_id
),
seller_tenure AS (
    SELECT
        s.seller_id,
        CASE
            WHEN (JULIANDAY(sfo.first_order_date) - JULIANDAY(s.join_date)) >= 365
            THEN 'Veteran (1+ year)'
            ELSE 'New (< 1 year)'
        END AS tenure_bucket
    FROM sellers s
    JOIN seller_first_order sfo ON s.seller_id = sfo.seller_id
)
SELECT
    st.tenure_bucket                            AS seller_tenure,
    COUNT(DISTINCT o.seller_id)                 AS seller_count,
    COUNT(o.order_id)                           AS total_orders,
    ROUND(AVG(o.gmv), 2)                        AS avg_order_value,
    ROUND(
        SUM(CASE WHEN o.status = 'Delivered' THEN 1 ELSE 0 END) * 100.0
        / COUNT(o.order_id), 2
    )                                            AS fulfillment_rate_pct,
    ROUND(
        SUM(CASE WHEN o.return_flag THEN 1 ELSE 0 END) * 100.0
        / COUNT(o.order_id), 2
    )                                            AS return_rate_pct,
    ROUND(AVG(o.delivery_days), 2)              AS avg_delivery_days
FROM orders o
JOIN seller_tenure st ON o.seller_id = st.seller_id
GROUP BY st.tenure_bucket
ORDER BY st.tenure_bucket;
