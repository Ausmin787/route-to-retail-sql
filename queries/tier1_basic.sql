-- Q1. What is total revenue by zone for the full year 2025?

SELECT
    z.zone_name,
    ROUND(SUM(soi.net_sales_value), 2) AS total_revenue
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
GROUP BY z.zone_name
ORDER BY total_revenue DESC;

-- Q2. Which are the top 10 SKUs by total units sold?

SELECT
    p.sku_name,
    p.category,
    p.brand,
    SUM(soi.quantity_units) AS total_units_sold
FROM products p
JOIN sales_order_items soi
    ON p.product_id = soi.product_id
JOIN sales_orders so
    ON soi.order_id = so.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY p.product_id, p.sku_name, p.category, p.brand
ORDER BY total_units_sold DESC
LIMIT 10;


-- Q3. Which distributors have placed zero orders in the last 60 days of the dataset?

WITH dataset_end AS (
    SELECT MAX(order_date) AS max_order_date
    FROM sales_orders
)
SELECT
    d.distributor_id,
    d.distributor_name,
    z.zone_name,
    d.tier
FROM distributors d
JOIN zones z
    ON d.zone_id = z.zone_id
CROSS JOIN dataset_end de
WHERE NOT EXISTS (
    SELECT 1
    FROM retailers r
    JOIN sales_orders so
        ON r.retailer_id = so.retailer_id
    WHERE r.distributor_id = d.distributor_id
      AND so.order_date > de.max_order_date - INTERVAL '60 days'
      AND so.order_date <= de.max_order_date
)
ORDER BY z.zone_name, d.tier, d.distributor_name;


-- Q4. What is the revenue split between General Trade, Modern Trade, and Wholesale?

SELECT
    r.channel_type,
    ROUND(SUM(soi.net_sales_value), 2) AS total_revenue,
    ROUND(
        SUM(soi.net_sales_value) * 100.0
        / SUM(SUM(soi.net_sales_value)) OVER (),
        2
    ) AS revenue_percentage
FROM retailers r
JOIN sales_orders so
    ON r.retailer_id = so.retailer_id
JOIN sales_order_items soi
    ON so.order_id = soi.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY r.channel_type
ORDER BY total_revenue DESC;


-- Q5 Which product category has the highest weighted gross margin percentage?

SELECT
    p.category,
    ROUND(
        SUM((p.trade_price - p.cost_price) * soi.quantity_units) * 100.0
        / SUM(p.trade_price * soi.quantity_units),
        2
    ) AS weighted_gross_margin_percentage
FROM products p
JOIN sales_order_items soi
    ON p.product_id = soi.product_id
JOIN sales_orders so
    ON soi.order_id = so.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY p.category
ORDER BY weighted_gross_margin_percentage DESC;

