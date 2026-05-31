-- Q19. Distributor revenue-at-risk score
-- Composite score across three risk signals, weighted and normalized to 0–10:
--   • Consecutive declining months  — 40%  (momentum risk)
--   • Revenue gap vs zone average   — 35%  (structural underperformance)
--   • Low promotion participation   — 25%  (commercial disengagement)
-- Output: top 10 at-risk distributors with score breakdown + risk_tier label.

WITH monthly_revenue AS (
    SELECT
        d.distributor_id,
        d.distributor_name,
        z.zone_name,
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value) AS monthly_revenue
    FROM distributors d
    JOIN zones z ON d.zone_id = z.zone_id
    JOIN retailers r ON d.distributor_id = r.distributor_id
    JOIN sales_orders so ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY d.distributor_id, d.distributor_name, z.zone_name,
             DATE_TRUNC('month', so.order_date)
),

-- Component 1: consecutive month-on-month declines (Q15 pattern)
decline_flags AS (
    SELECT
        distributor_id,
        sales_month,
        monthly_revenue,
        CASE
            WHEN monthly_revenue < LAG(monthly_revenue) OVER (
                     PARTITION BY distributor_id ORDER BY sales_month)
            THEN 1 ELSE 0
        END AS declined
    FROM monthly_revenue
),
consecutive_declines AS (
    SELECT
        distributor_id,
        COUNT(*) AS consecutive_decline_months
    FROM (
        SELECT
            distributor_id,
            declined,
            LAG(declined) OVER (PARTITION BY distributor_id ORDER BY sales_month) AS prev_declined
        FROM decline_flags
    ) chained
    WHERE declined = 1 AND prev_declined = 1
    GROUP BY distributor_id
),

-- Components 2 & 3: zone revenue gap and promotion participation
distributor_totals AS (
    SELECT
        d.distributor_id,
        d.distributor_name,
        z.zone_name,
        SUM(soi.net_sales_value)                                              AS total_revenue,
        COUNT(soi.order_item_id)                                              AS total_items,
        COUNT(soi.order_item_id) FILTER (WHERE soi.promotion_id IS NOT NULL) AS promoted_items
    FROM distributors d
    JOIN zones z ON d.zone_id = z.zone_id
    JOIN retailers r ON d.distributor_id = r.distributor_id
    JOIN sales_orders so ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY d.distributor_id, d.distributor_name, z.zone_name
),
zone_avg AS (
    SELECT zone_name, AVG(total_revenue) AS avg_zone_revenue
    FROM distributor_totals
    GROUP BY zone_name
),

-- Assemble raw signal values
signals AS (
    SELECT
        dt.distributor_id,
        dt.distributor_name,
        dt.zone_name,
        ROUND(dt.total_revenue, 2) AS total_revenue,
        COALESCE(cd.consecutive_decline_months, 0) AS consecutive_decline_months,
        ROUND(
            GREATEST(0, za.avg_zone_revenue - dt.total_revenue) * 100.0
            / NULLIF(za.avg_zone_revenue, 0),
            2
        ) AS pct_below_zone_avg,
        ROUND(
            dt.promoted_items * 100.0 / NULLIF(dt.total_items, 0),
            2
        ) AS promo_participation_rate
    FROM distributor_totals dt
    JOIN zone_avg za ON dt.zone_name = za.zone_name
    LEFT JOIN consecutive_declines cd ON dt.distributor_id = cd.distributor_id
),

-- Min-max scaling per component so all land on 0–10
bounds AS (
    SELECT
        MIN(consecutive_decline_months) AS min_dec,  MAX(consecutive_decline_months) AS max_dec,
        MIN(pct_below_zone_avg)         AS min_gap,  MAX(pct_below_zone_avg)         AS max_gap,
        MIN(promo_participation_rate)   AS min_promo, MAX(promo_participation_rate)   AS max_promo
    FROM signals
),
normalized AS (
    SELECT
        s.*,
        -- Decline score: more declines → higher risk
        ROUND(
            (s.consecutive_decline_months - b.min_dec) * 10.0
            / NULLIF(b.max_dec - b.min_dec, 0),
            2
        ) AS decline_score,
        -- Gap score: further below zone average → higher risk
        ROUND(
            (s.pct_below_zone_avg - b.min_gap) * 10.0
            / NULLIF(b.max_gap - b.min_gap, 0),
            2
        ) AS gap_score,
        -- Promo score: lower participation → higher risk (inverted)
        ROUND(
            (b.max_promo - s.promo_participation_rate) * 10.0
            / NULLIF(b.max_promo - b.min_promo, 0),
            2
        ) AS low_promo_score
    FROM signals s
    CROSS JOIN bounds b
)
SELECT
    distributor_name,
    zone_name,
    total_revenue,
    consecutive_decline_months,
    pct_below_zone_avg,
    promo_participation_rate,
    decline_score,
    gap_score,
    low_promo_score,
    ROUND(
        decline_score   * 0.40
        + gap_score     * 0.35
        + low_promo_score * 0.25,
        2
    ) AS composite_risk_score,
    CASE
        WHEN (decline_score * 0.40 + gap_score * 0.35 + low_promo_score * 0.25) >= 6.0
            THEN 'Critical'
        WHEN (decline_score * 0.40 + gap_score * 0.35 + low_promo_score * 0.25) >= 3.0
            THEN 'Watch'
        ELSE 'Stable'
    END AS risk_tier
FROM normalized
ORDER BY composite_risk_score DESC
LIMIT 10;
