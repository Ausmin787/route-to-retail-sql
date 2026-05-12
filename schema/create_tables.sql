-- Route-to-Retail: FMCG Distributor Sales SQL Case Study
-- Run this script once on a clean database to build the schema.
-- Drop order respects foreign-key dependencies.

DROP TABLE IF EXISTS sales_order_items CASCADE;
DROP TABLE IF EXISTS sales_orders       CASCADE;
DROP TABLE IF EXISTS promotions         CASCADE;
DROP TABLE IF EXISTS products           CASCADE;
DROP TABLE IF EXISTS retailers          CASCADE;
DROP TABLE IF EXISTS distributors       CASCADE;
DROP TABLE IF EXISTS zones              CASCADE;

-- ── Lookup / dimension tables ──────────────────────────────────────────────────

CREATE TABLE zones (
    zone_id   SERIAL PRIMARY KEY,
    zone_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE distributors (
    distributor_id   SERIAL PRIMARY KEY,
    distributor_name VARCHAR(100) NOT NULL,
    zone_id          INT  NOT NULL REFERENCES zones(zone_id),
    tier             VARCHAR(10) NOT NULL CHECK (tier IN ('A', 'B', 'C')),
    city             VARCHAR(80) NOT NULL,
    active_status    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE retailers (
    retailer_id   SERIAL PRIMARY KEY,
    retailer_name VARCHAR(120) NOT NULL,
    distributor_id INT NOT NULL REFERENCES distributors(distributor_id),
    city           VARCHAR(80) NOT NULL,
    channel_type   VARCHAR(30) NOT NULL CHECK (
                       channel_type IN ('General Trade', 'Modern Trade', 'Wholesale')
                   ),
    active_status  BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE products (
    product_id  SERIAL PRIMARY KEY,
    sku_name    VARCHAR(120) NOT NULL,
    category    VARCHAR(50)  NOT NULL CHECK (
                    category IN ('Home Care', 'Personal Care', 'Packaged Foods', 'Beverages')
                ),
    brand       VARCHAR(80)  NOT NULL,
    mrp         NUMERIC(10,2) NOT NULL CHECK (mrp > 0),
    trade_price NUMERIC(10,2) NOT NULL CHECK (trade_price > 0),
    cost_price  NUMERIC(10,2) NOT NULL CHECK (cost_price > 0),
    CHECK (trade_price <= mrp),
    CHECK (cost_price  <  trade_price)
);

CREATE TABLE promotions (
    promotion_id   SERIAL PRIMARY KEY,
    promotion_name VARCHAR(120) NOT NULL,
    category       VARCHAR(50)  CHECK (
                       category IN ('Home Care', 'Personal Care', 'Packaged Foods', 'Beverages')
                   ),
    discount_percent NUMERIC(5,2) NOT NULL CHECK (discount_percent BETWEEN 0 AND 70),
    start_date     DATE NOT NULL,
    end_date       DATE NOT NULL,
    CHECK (end_date >= start_date)
);

-- ── Transactional tables ───────────────────────────────────────────────────────

CREATE TABLE sales_orders (
    order_id    SERIAL PRIMARY KEY,
    retailer_id INT  NOT NULL REFERENCES retailers(retailer_id),
    order_date  DATE NOT NULL
);

CREATE TABLE sales_order_items (
    order_item_id     SERIAL PRIMARY KEY,
    order_id          INT  NOT NULL REFERENCES sales_orders(order_id),
    product_id        INT  NOT NULL REFERENCES products(product_id),
    promotion_id      INT  REFERENCES promotions(promotion_id),
    quantity_units    INT  NOT NULL CHECK (quantity_units > 0),
    gross_sales_value NUMERIC(12,2) NOT NULL CHECK (gross_sales_value >= 0),
    discount_value    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
    net_sales_value   NUMERIC(12,2) NOT NULL CHECK (net_sales_value >= 0)
);

-- ── Indexes for analytical queries ────────────────────────────────────────────

CREATE INDEX idx_distributors_zone  ON distributors(zone_id);
CREATE INDEX idx_distributors_tier  ON distributors(tier);
CREATE INDEX idx_retailers_dist     ON retailers(distributor_id);
CREATE INDEX idx_retailers_channel  ON retailers(channel_type);
CREATE INDEX idx_products_category  ON products(category);
CREATE INDEX idx_orders_date        ON sales_orders(order_date);
CREATE INDEX idx_orders_retailer    ON sales_orders(retailer_id);
CREATE INDEX idx_items_order        ON sales_order_items(order_id);
CREATE INDEX idx_items_product      ON sales_order_items(product_id);
CREATE INDEX idx_items_promotion    ON sales_order_items(promotion_id);
