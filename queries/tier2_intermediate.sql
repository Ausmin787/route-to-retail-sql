-- Q6. What is monthly revenue for each month in 2025?

SELECT
    DATE_TRUNC('month', so.order_date)::date AS sales_month,
    ROUND(SUM(soi.net_sales_value), 2) AS monthly_revenue
FROM sales_orders so
JOIN sales_order_items soi
    ON so.order_id = soi.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY DATE_TRUNC('month', so.order_date)
ORDER BY sales_month;


-- Q7. Which distributors are underperforming vs their zone average revenue?

WITH distributor_revenue AS (
    SELECT
        z.zone_name,
        d.distributor_id,
        d.distributor_name,
        ROUND(SUM(soi.net_sales_value), 2) AS distributor_revenue
    FROM distributors d
    JOIN zones z
        ON d.zone_id = z.zone_id
    JOIN retailers r
        ON d.distributor_id = r.distributor_id
    JOIN sales_orders so
        ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi
        ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY z.zone_name, d.distributor_id, d.distributor_name
),
zone_average AS (
    SELECT
        zone_name,
        AVG(distributor_revenue) AS zone_avg_revenue
    FROM distributor_revenue
    GROUP BY zone_name
)
SELECT
    dr.zone_name,
    dr.distributor_name,
    dr.distributor_revenue,
    ROUND(za.zone_avg_revenue, 2) AS zone_avg_revenue,
    ROUND(dr.distributor_revenue - za.zone_avg_revenue, 2) AS revenue_gap
FROM distributor_revenue dr
JOIN zone_average za
    ON dr.zone_name = za.zone_name
WHERE dr.distributor_revenue < za.zone_avg_revenue
ORDER BY dr.zone_name, revenue_gap;


-- Q8. What is the sell-through rate per category per zone?
-- Proxy used: units sold per retailer.

SELECT
    z.zone_name,
    p.category,
    SUM(soi.quantity_units) AS total_units_sold,
    COUNT(DISTINCT r.retailer_id) AS retailer_count,
    ROUND(
        SUM(soi.quantity_units)::numeric / COUNT(DISTINCT r.retailer_id),
        2
    ) AS units_sold_per_retailer
FROM zones z
JOIN distributors d
    ON z.zone_id = d.zone_id
JOIN retailers r
    ON d.distributor_id = r.distributor_id
JOIN sales_orders so
    ON r.retailer_id = so.retailer_id
JOIN sales_order_items soi
    ON so.order_id = soi.order_id
JOIN products p
    ON soi.product_id = p.product_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY z.zone_name, p.category
ORDER BY z.zone_name, units_sold_per_retailer DESC;


-- Q9: Which promotions had the highest revenue and discount value?
SELECT
    pr.promotion_name,
    pr.category,
    pr.discount_percent,
    COUNT(soi.order_item_id)              AS items_sold,
    ROUND(SUM(soi.gross_sales_value), 2)  AS gross_revenue,
    ROUND(SUM(soi.discount_value), 2)     AS total_discount_given,
    ROUND(SUM(soi.net_sales_value), 2)    AS net_revenue,
    ROUND(SUM(soi.discount_value) * 100.0 
          / SUM(soi.gross_sales_value), 2) AS effective_discount_pct
FROM promotions pr
JOIN sales_order_items soi ON pr.promotion_id = soi.promotion_id
JOIN sales_orders so       ON soi.order_id    = so.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY pr.promotion_id, pr.promotion_name, pr.category, pr.discount_percent
ORDER BY net_revenue DESC;


-- Q10. Revenue contribution of each SKU
-- as a percentage of its category total.

WITH sku_revenue AS (
    SELECT
        p.category,
        p.sku_name,
        SUM(soi.net_sales_value) AS sku_revenue
    FROM products p
    JOIN sales_order_items soi
        ON p.product_id = soi.product_id
    JOIN sales_orders so
        ON soi.order_id = so.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY p.category, p.sku_name
)
SELECT
    category,
    sku_name,
    ROUND(sku_revenue, 2) AS sku_revenue,
    ROUND(
        sku_revenue * 100.0 / SUM(sku_revenue) OVER (PARTITION BY category),
        2
    ) AS category_revenue_percentage
FROM sku_revenue
ORDER BY category, category_revenue_percentage DESC;


-- Q11. Which retailers have never purchased from a promoted SKU?

SELECT
    r.retailer_id,
    r.retailer_name,
    r.channel_type,
    d.distributor_name,
    z.zone_name
FROM retailers r
JOIN distributors d
    ON r.distributor_id = d.distributor_id
JOIN zones z
    ON d.zone_id = z.zone_id
WHERE NOT EXISTS (
    SELECT 1
    FROM sales_orders so
    JOIN sales_order_items soi
        ON so.order_id = soi.order_id
    WHERE so.retailer_id = r.retailer_id
      AND soi.promotion_id IS NOT NULL
)
ORDER BY z.zone_name, d.distributor_name, r.retailer_name;


-- Q12. Top 3 distributors per zone by net revenue.

WITH distributor_revenue AS (
    SELECT
        z.zone_name,
        d.distributor_id,
        d.distributor_name,
        SUM(soi.net_sales_value) AS net_revenue
    FROM zones z
    JOIN distributors d
        ON z.zone_id = d.zone_id
    JOIN retailers r
        ON d.distributor_id = r.distributor_id
    JOIN sales_orders so
        ON r.retailer_id = so.retailer_id
    JOIN sales_order_items soi
        ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY z.zone_name, d.distributor_id, d.distributor_name
),
ranked_distributors AS (
    SELECT
        zone_name,
        distributor_name,
        net_revenue,
        RANK() OVER (
            PARTITION BY zone_name
            ORDER BY net_revenue DESC
        ) AS zone_rank
    FROM distributor_revenue
)
SELECT
    zone_name,
    distributor_name,
    ROUND(net_revenue, 2) AS net_revenue,
    zone_rank
FROM ranked_distributors
WHERE zone_rank <= 3
ORDER BY zone_name, zone_rank;
