-- =============================================================================
-- 02_funnel_analysis.sql
-- Ecommerce Marketplace Analytics — Conversion Funnel Analysis
--
-- Business Question:
--   Where are users dropping off in the purchase journey?
--   View → Add to Cart → Checkout → Purchase
--
-- Answers:
--   1. Overall funnel conversion rates
--   2. Funnel breakdown by product category
--   3. Funnel breakdown by platform (App vs Web)
--   4. Weekly trend of view-to-purchase rate
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Overall platform-wide funnel
-- Shows absolute counts and step-to-step conversion rates.
-- -----------------------------------------------------------------------------
WITH funnel_counts AS (
    SELECT
        SUM(CASE WHEN event_type = 'view'           THEN 1 ELSE 0 END) AS views,
        SUM(CASE WHEN event_type = 'add_to_cart'    THEN 1 ELSE 0 END) AS add_to_cart,
        SUM(CASE WHEN event_type = 'checkout'       THEN 1 ELSE 0 END) AS checkouts,
        SUM(CASE WHEN event_type = 'purchase'       THEN 1 ELSE 0 END) AS purchases
    FROM events
)
SELECT
    views,
    add_to_cart,
    checkouts,
    purchases,
    ROUND(add_to_cart  * 100.0 / NULLIF(views,        0), 2) AS view_to_cart_pct,
    ROUND(checkouts    * 100.0 / NULLIF(add_to_cart,  0), 2) AS cart_to_checkout_pct,
    ROUND(purchases    * 100.0 / NULLIF(checkouts,    0), 2) AS checkout_to_purchase_pct,
    ROUND(purchases    * 100.0 / NULLIF(views,        0), 2) AS overall_conversion_pct
FROM funnel_counts;


-- -----------------------------------------------------------------------------
-- Query 2: Funnel by product category
-- Identifies which categories have the worst drop-off — actionable for
-- category managers to investigate pricing, content, or UX issues.
-- -----------------------------------------------------------------------------
WITH category_events AS (
    SELECT
        p.category,
        e.event_type,
        COUNT(*) AS event_count
    FROM events e
    JOIN products p ON e.product_id = p.product_id
    GROUP BY p.category, e.event_type
),
pivoted AS (
    SELECT
        category,
        SUM(CASE WHEN event_type = 'view'        THEN event_count ELSE 0 END) AS views,
        SUM(CASE WHEN event_type = 'add_to_cart' THEN event_count ELSE 0 END) AS add_to_cart,
        SUM(CASE WHEN event_type = 'checkout'    THEN event_count ELSE 0 END) AS checkouts,
        SUM(CASE WHEN event_type = 'purchase'    THEN event_count ELSE 0 END) AS purchases
    FROM category_events
    GROUP BY category
)
SELECT
    category,
    views,
    add_to_cart,
    checkouts,
    purchases,
    ROUND(add_to_cart * 100.0 / NULLIF(views,       0), 2) AS view_to_cart_pct,
    ROUND(purchases   * 100.0 / NULLIF(views,       0), 2) AS overall_conversion_pct
FROM pivoted
ORDER BY overall_conversion_pct DESC;


-- -----------------------------------------------------------------------------
-- Query 3: Funnel by platform
-- Are mobile users converting better than web users?
-- Key insight for product / growth analyst roles.
-- -----------------------------------------------------------------------------
WITH platform_events AS (
    SELECT
        platform,
        event_type,
        COUNT(*) AS event_count
    FROM events
    GROUP BY platform, event_type
),
pivoted AS (
    SELECT
        platform,
        SUM(CASE WHEN event_type = 'view'        THEN event_count ELSE 0 END) AS views,
        SUM(CASE WHEN event_type = 'add_to_cart' THEN event_count ELSE 0 END) AS add_to_cart,
        SUM(CASE WHEN event_type = 'checkout'    THEN event_count ELSE 0 END) AS checkouts,
        SUM(CASE WHEN event_type = 'purchase'    THEN event_count ELSE 0 END) AS purchases
    FROM platform_events
    GROUP BY platform
)
SELECT
    platform,
    views,
    add_to_cart,
    purchases,
    ROUND(add_to_cart * 100.0 / NULLIF(views,    0), 2) AS view_to_cart_pct,
    ROUND(purchases   * 100.0 / NULLIF(views,    0), 2) AS overall_conversion_pct
FROM pivoted
ORDER BY overall_conversion_pct DESC;


-- -----------------------------------------------------------------------------
-- Query 4: Weekly view-to-purchase trend
-- Tracks conversion rate over time. Useful for spotting festival-season
-- spikes and diagnosing performance dips.
-- Uses window function to smooth with 4-week rolling average.
-- -----------------------------------------------------------------------------
WITH weekly_events AS (
    SELECT
        DATE_TRUNC('week', event_ts)           AS week_start,
        SUM(CASE WHEN event_type = 'view'     THEN 1 ELSE 0 END) AS views,
        SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchases
    FROM events
    GROUP BY DATE_TRUNC('week', event_ts)
),
weekly_conversion AS (
    SELECT
        week_start,
        views,
        purchases,
        ROUND(purchases * 100.0 / NULLIF(views, 0), 3) AS conversion_pct
    FROM weekly_events
)
SELECT
    week_start,
    views,
    purchases,
    conversion_pct,
    ROUND(
        AVG(conversion_pct) OVER (
            ORDER BY week_start
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ), 3
    ) AS rolling_4w_conversion_pct
FROM weekly_conversion
ORDER BY week_start;
