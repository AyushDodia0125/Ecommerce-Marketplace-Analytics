-- =============================================================================
-- 07_rfm_segmentation.sql
-- Ecommerce Marketplace Analytics — RFM Customer Segmentation
--
-- Business Question:
--   Which customers are Champions, Loyals, At-Risk, and Lost?
--   How much revenue does each segment contribute?
--
-- RFM Framework:
--   R (Recency)   — Days since last order (lower = better)
--   F (Frequency) — Total number of orders (higher = better)
--   M (Monetary)  — Total GMV spent (higher = better)
--
-- Answers:
--   1. Raw RFM scores per customer
--   2. RFM segment assignment (Champion, Loyal, At-Risk, etc.)
--   3. Segment distribution and revenue share
--   4. Acquisition channel → segment pipeline
--   5. City-level segment breakdown (geo intelligence)
-- =============================================================================


-- Reference date: 1 day after the last order in the dataset
-- In production, replace with CURRENT_DATE
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Raw RFM metrics per customer
-- Foundation for all downstream segmentation.
-- -----------------------------------------------------------------------------
WITH reference_date AS (
    SELECT MAX(order_date) + 1 AS ref_date FROM orders
),
rfm_raw AS (
    SELECT
        o.customer_id,
        (SELECT ref_date FROM reference_date)
            - MAX(o.order_date)                                 AS recency_days,
        COUNT(DISTINCT o.order_id)                              AS frequency,
        ROUND(SUM(o.gmv), 2)                                    AS monetary
    FROM orders o
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    -- Score each dimension 1–5 (5 = best)
    NTILE(5) OVER (ORDER BY recency_days ASC)     AS r_score,   -- Lower recency = higher score
    NTILE(5) OVER (ORDER BY frequency DESC)       AS f_score,   -- Higher freq = higher score
    NTILE(5) OVER (ORDER BY monetary DESC)        AS m_score    -- Higher monetary = higher score
FROM rfm_raw;


-- -----------------------------------------------------------------------------
-- Query 2: RFM segment assignment
-- Maps score combinations to business-meaningful segments.
-- These segment names are industry-standard and recognizable in interviews.
-- -----------------------------------------------------------------------------
WITH reference_date AS (
    SELECT MAX(order_date) + 1 AS ref_date FROM orders
),
rfm_raw AS (
    SELECT
        o.customer_id,
        (SELECT ref_date FROM reference_date) - MAX(o.order_date) AS recency_days,
        COUNT(DISTINCT o.order_id)                                  AS frequency,
        ROUND(SUM(o.gmv), 2)                                        AS monetary
    FROM orders o
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM rfm_raw
),
rfm_segments AS (
    SELECT
        *,
        CONCAT(r_score, f_score, m_score)          AS rfm_code,
        ROUND((r_score + f_score + m_score) / 3.0, 2) AS avg_rfm_score,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
                THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 4
                THEN 'Loyal Customer'
            WHEN r_score >= 4 AND f_score <= 2
                THEN 'Recent Customer'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3
                THEN 'Potential Loyalist'
            WHEN r_score >= 4 AND f_score = 1 AND m_score = 1
                THEN 'New Customer'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
                THEN 'At-Risk'
            WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
                THEN 'Cannot Lose Them'
            WHEN r_score <= 2 AND f_score <= 2
                THEN 'Lost'
            ELSE 'Needs Attention'
        END                                         AS segment
    FROM rfm_scored
)
SELECT * FROM rfm_segments
ORDER BY avg_rfm_score DESC;


-- -----------------------------------------------------------------------------
-- Query 3: Segment distribution and revenue contribution
-- The exec-level summary: how many customers per segment and how much
-- GMV each segment generates.
-- -----------------------------------------------------------------------------
WITH reference_date AS (
    SELECT MAX(order_date) + 1 AS ref_date FROM orders
),
rfm_raw AS (
    SELECT
        o.customer_id,
        (SELECT ref_date FROM reference_date) - MAX(o.order_date) AS recency_days,
        COUNT(DISTINCT o.order_id)                                  AS frequency,
        ROUND(SUM(o.gmv), 2)                                        AS monetary
    FROM orders o
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT
        customer_id,
        monetary,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4    THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 4                     THEN 'Loyal Customer'
            WHEN r_score >= 4 AND f_score <= 2                     THEN 'Recent Customer'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3    THEN 'Potential Loyalist'
            WHEN r_score >= 4 AND f_score = 1 AND m_score = 1      THEN 'New Customer'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3    THEN 'At-Risk'
            WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4    THEN 'Cannot Lose Them'
            WHEN r_score <= 2 AND f_score <= 2                     THEN 'Lost'
            ELSE 'Needs Attention'
        END AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(customer_id)                              AS customer_count,
    ROUND(COUNT(customer_id) * 100.0
          / SUM(COUNT(customer_id)) OVER (), 2)     AS pct_of_customers,
    ROUND(SUM(monetary), 2)                         AS total_gmv,
    ROUND(SUM(monetary) * 100.0
          / SUM(SUM(monetary)) OVER (), 2)          AS pct_of_revenue,
    ROUND(AVG(monetary), 2)                         AS avg_customer_value
FROM rfm_labeled
GROUP BY segment
ORDER BY total_gmv DESC;


-- -----------------------------------------------------------------------------
-- Query 4: Acquisition channel → RFM segment pipeline
-- Which channels are bringing in Champions vs Lost customers?
-- Informs marketing spend allocation decisions.
-- -----------------------------------------------------------------------------
WITH reference_date AS (
    SELECT MAX(order_date) + 1 AS ref_date FROM orders
),
rfm_raw AS (
    SELECT
        o.customer_id,
        (SELECT ref_date FROM reference_date) - MAX(o.order_date) AS recency_days,
        COUNT(DISTINCT o.order_id)                                  AS frequency,
        ROUND(SUM(o.gmv), 2)                                        AS monetary
    FROM orders o
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT
        customer_id,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4    THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 4                     THEN 'Loyal Customer'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3    THEN 'At-Risk'
            WHEN r_score <= 2 AND f_score <= 2                     THEN 'Lost'
            ELSE 'Other'
        END AS segment
    FROM rfm_scored
)
SELECT
    c.acquisition_channel,
    rl.segment,
    COUNT(rl.customer_id)                           AS customer_count,
    ROUND(COUNT(rl.customer_id) * 100.0
          / SUM(COUNT(rl.customer_id))
            OVER (PARTITION BY c.acquisition_channel), 2) AS pct_within_channel
FROM rfm_labeled rl
JOIN customers c ON rl.customer_id = c.customer_id
GROUP BY c.acquisition_channel, rl.segment
ORDER BY c.acquisition_channel, customer_count DESC;


-- -----------------------------------------------------------------------------
-- Query 5: City-level RFM distribution
-- Geo intelligence — which cities have the most Champions and At-Risk?
-- Useful for hyperlocal marketing and supply planning.
-- -----------------------------------------------------------------------------
WITH reference_date AS (
    SELECT MAX(order_date) + 1 AS ref_date FROM orders
),
rfm_raw AS (
    SELECT
        o.customer_id,
        (SELECT ref_date FROM reference_date) - MAX(o.order_date) AS recency_days,
        COUNT(DISTINCT o.order_id)                                  AS frequency,
        ROUND(SUM(o.gmv), 2)                                        AS monetary
    FROM orders o
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT
        customer_id,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4    THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 4                     THEN 'Loyal Customer'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3    THEN 'At-Risk'
            WHEN r_score <= 2 AND f_score <= 2                     THEN 'Lost'
            ELSE 'Other'
        END AS segment
    FROM rfm_scored
)
SELECT
    c.city,
    c.state,
    COUNT(DISTINCT rl.customer_id)                  AS total_customers,
    SUM(CASE WHEN rl.segment = 'Champion'       THEN 1 ELSE 0 END) AS champions,
    SUM(CASE WHEN rl.segment = 'Loyal Customer' THEN 1 ELSE 0 END) AS loyal_customers,
    SUM(CASE WHEN rl.segment = 'At-Risk'        THEN 1 ELSE 0 END) AS at_risk,
    SUM(CASE WHEN rl.segment = 'Lost'           THEN 1 ELSE 0 END) AS lost,
    ROUND(
        SUM(CASE WHEN rl.segment IN ('Champion', 'Loyal Customer') THEN 1 ELSE 0 END) * 100.0
        / COUNT(DISTINCT rl.customer_id), 2
    )                                               AS high_value_pct
FROM rfm_labeled rl
JOIN customers c ON rl.customer_id = c.customer_id
GROUP BY c.city, c.state
ORDER BY champions DESC;
