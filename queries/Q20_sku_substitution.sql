-- Q20. SKU substitution / cannibalisation analysis
-- Computes Pearson correlation (PostgreSQL CORR() aggregate) between monthly unit sales
-- for every SKU pair within the same category.
-- Pairs with r < -0.5 are flagged as potential substitutes (one grows as the other shrinks).

WITH monthly_sku_units AS (
    SELECT
        p.product_id,
        p.sku_name,
        p.category,
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.quantity_units) AS monthly_units
    FROM products p
    JOIN sales_order_items soi ON p.product_id = soi.product_id
    JOIN sales_orders so ON soi.order_id = so.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY p.product_id, p.sku_name, p.category,
             DATE_TRUNC('month', so.order_date)
)
SELECT
    a.category,
    a.sku_name                                            AS sku_a,
    b.sku_name                                            AS sku_b,
    ROUND(CORR(a.monthly_units, b.monthly_units)::numeric, 3) AS correlation,
    CASE
        WHEN CORR(a.monthly_units, b.monthly_units) < -0.7
            THEN 'Strong substitute — high cannibalisation risk'
        WHEN CORR(a.monthly_units, b.monthly_units) < -0.5
            THEN 'Potential substitute — monitor volume shift'
        ELSE 'No substitution signal'
    END AS interpretation
FROM monthly_sku_units a
JOIN monthly_sku_units b
    ON  a.category    = b.category
    AND a.product_id  < b.product_id   -- deduplicate pairs; avoids (A,B) and (B,A)
    AND a.sales_month = b.sales_month
GROUP BY
    a.category, a.product_id, a.sku_name,
    b.product_id, b.sku_name
HAVING
    CORR(a.monthly_units, b.monthly_units) < -0.5
ORDER BY
    a.category, correlation;
