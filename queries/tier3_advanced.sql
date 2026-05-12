-- Q13. Rolling 3-month average revenue per distributor

WITH monthly_revenue AS (
    SELECT
        d.distributor_id,
        d.distributor_name,
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value) AS monthly_revenue
    FROM distributors d
    JOIN retailers r ON d.distributor_id = r.distributor_id
    JOIN sales_orders so ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY d.distributor_id, d.distributor_name, DATE_TRUNC('month', so.order_date)
)
SELECT
    distributor_name,
    sales_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND(
        AVG(monthly_revenue) OVER (
            PARTITION BY distributor_id
            ORDER BY sales_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS rolling_3_month_avg_revenue
FROM monthly_revenue
ORDER BY distributor_name, sales_month;


-- Q14. Month-over-month revenue growth rate using LAG()

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value) AS monthly_revenue
    FROM sales_orders so
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY DATE_TRUNC('month', so.order_date)
),
with_lag AS (
    SELECT
        sales_month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (ORDER BY sales_month) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    sales_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND(previous_month_revenue, 2) AS previous_month_revenue,
    ROUND(
        (monthly_revenue - previous_month_revenue) * 100.0
        / NULLIF(previous_month_revenue, 0),
        2
    ) AS mom_growth_percentage
FROM with_lag
ORDER BY sales_month;


-- Q15. Which distributors had 2 or more consecutive months of declining sales?

WITH monthly_revenue AS (
    SELECT
        d.distributor_id,
        d.distributor_name,
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value) AS monthly_revenue
    FROM distributors d
    JOIN retailers r ON d.distributor_id = r.distributor_id
    JOIN sales_orders so ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY d.distributor_id, d.distributor_name, DATE_TRUNC('month', so.order_date)
),
decline_flags AS (
    SELECT
        distributor_id,
        distributor_name,
        sales_month,
        monthly_revenue,
        CASE
            WHEN monthly_revenue < LAG(monthly_revenue) OVER (
                PARTITION BY distributor_id ORDER BY sales_month
            )
            THEN 1 ELSE 0
        END AS declined_from_previous_month
    FROM monthly_revenue
),
consecutive_check AS (
    SELECT
        *,
        LAG(declined_from_previous_month) OVER (
            PARTITION BY distributor_id ORDER BY sales_month
        ) AS previous_month_also_declined
    FROM decline_flags
)
SELECT
    distributor_name,
    sales_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue
FROM consecutive_check
WHERE declined_from_previous_month = 1
  AND previous_month_also_declined = 1
ORDER BY distributor_name, sales_month;


-- Q16. Cohort analysis:
-- For each retailer first-purchase month, how many are still purchasing 3 months later?

WITH first_purchase AS (
    SELECT
        retailer_id,
        DATE_TRUNC('month', MIN(order_date))::date AS first_purchase_month
    FROM sales_orders
    GROUP BY retailer_id
),
month_3_purchases AS (
    SELECT DISTINCT
        fp.retailer_id,
        fp.first_purchase_month
    FROM first_purchase fp
    JOIN sales_orders so
        ON fp.retailer_id = so.retailer_id
       AND DATE_TRUNC('month', so.order_date)::date =
           fp.first_purchase_month + INTERVAL '3 months'
)
SELECT
    fp.first_purchase_month,
    COUNT(fp.retailer_id) AS cohort_size,
    COUNT(m3.retailer_id) AS retained_after_3_months,
    ROUND(
        COUNT(m3.retailer_id) * 100.0 / COUNT(fp.retailer_id),
        2
    ) AS retention_rate_percentage
FROM first_purchase fp
LEFT JOIN month_3_purchases m3
    ON fp.retailer_id = m3.retailer_id
GROUP BY fp.first_purchase_month
ORDER BY fp.first_purchase_month;


-- Q17. Which SKUs have a declining revenue trend over the last 6 months of 2025?

WITH monthly_sku_revenue AS (
    SELECT
        p.product_id,
        p.sku_name,
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value) AS monthly_revenue
    FROM products p
    JOIN sales_order_items soi ON p.product_id = soi.product_id
    JOIN sales_orders so ON soi.order_id = so.order_id
    WHERE so.order_date >= DATE '2025-07-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY p.product_id, p.sku_name, DATE_TRUNC('month', so.order_date)
),
with_lag AS (
    SELECT
        *,
        LAG(monthly_revenue) OVER (
            PARTITION BY product_id ORDER BY sales_month
        ) AS previous_month_revenue
    FROM monthly_sku_revenue
)
SELECT
    sku_name,
    COUNT(*) FILTER (
        WHERE monthly_revenue < previous_month_revenue
    ) AS declining_month_count,
    ROUND(SUM(monthly_revenue), 2) AS last_6_month_revenue
FROM with_lag
GROUP BY product_id, sku_name
HAVING COUNT(*) FILTER (
    WHERE monthly_revenue < previous_month_revenue
) >= 3
ORDER BY declining_month_count DESC, last_6_month_revenue DESC;


-- Q18. Full distributor scorecard:
-- revenue, latest MoM growth, promotion participation rate, zone rank

WITH monthly_distributor_revenue AS (
    SELECT
        z.zone_name,
        d.distributor_id,
        d.distributor_name,
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value) AS monthly_revenue
    FROM zones z
    JOIN distributors d ON z.zone_id = d.zone_id
    JOIN retailers r ON d.distributor_id = r.distributor_id
    JOIN sales_orders so ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY z.zone_name, d.distributor_id, d.distributor_name, DATE_TRUNC('month', so.order_date)
),
mom_growth AS (
    SELECT
        *,
        LAG(monthly_revenue) OVER (
            PARTITION BY distributor_id ORDER BY sales_month
        ) AS previous_month_revenue
    FROM monthly_distributor_revenue
),
latest_mom AS (
    SELECT DISTINCT ON (distributor_id)
        distributor_id,
        ROUND(
            (monthly_revenue - previous_month_revenue) * 100.0
            / NULLIF(previous_month_revenue, 0),
            2
        ) AS latest_mom_growth_percentage
    FROM mom_growth
    WHERE previous_month_revenue IS NOT NULL
    ORDER BY distributor_id, sales_month DESC
),
distributor_totals AS (
    SELECT
        z.zone_name,
        d.distributor_id,
        d.distributor_name,
        SUM(soi.net_sales_value) AS total_revenue,
        COUNT(*) AS total_order_items,
        COUNT(*) FILTER (WHERE soi.promotion_id IS NOT NULL) AS promoted_order_items
    FROM zones z
    JOIN distributors d ON z.zone_id = d.zone_id
    JOIN retailers r ON d.distributor_id = r.distributor_id
    JOIN sales_orders so ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY z.zone_name, d.distributor_id, d.distributor_name
),
scorecard AS (
    SELECT
        dt.zone_name,
        dt.distributor_name,
        dt.total_revenue,
        lm.latest_mom_growth_percentage,
        ROUND(
            dt.promoted_order_items * 100.0 / NULLIF(dt.total_order_items, 0),
            2
        ) AS promotion_participation_rate,
        RANK() OVER (
            PARTITION BY dt.zone_name
            ORDER BY dt.total_revenue DESC
        ) AS zone_rank
    FROM distributor_totals dt
    LEFT JOIN latest_mom lm
        ON dt.distributor_id = lm.distributor_id
)
SELECT
    zone_name,
    distributor_name,
    ROUND(total_revenue, 2) AS total_revenue,
    latest_mom_growth_percentage,
    promotion_participation_rate,
    zone_rank
FROM scorecard
ORDER BY zone_name, zone_rank;
