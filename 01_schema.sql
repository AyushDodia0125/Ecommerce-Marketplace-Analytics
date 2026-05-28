-- =============================================================================
-- 01_schema.sql
-- Ecommerce Marketplace Analytics — Database Schema
-- Compatible with: PostgreSQL | SQLite (with minor type adjustments noted)
-- =============================================================================

-- Drop tables in reverse dependency order (safe re-run)
DROP TABLE IF EXISTS inventory;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS customers;


-- -----------------------------------------------------------------------------
-- DIMENSION: customers
-- One row per registered user on the platform.
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id         INTEGER         PRIMARY KEY,
    city                VARCHAR(50)     NOT NULL,
    state               VARCHAR(50)     NOT NULL,
    signup_date         DATE            NOT NULL,
    segment             VARCHAR(20)     NOT NULL,   -- New | Regular | Premium | Inactive
    acquisition_channel VARCHAR(50)     NOT NULL,   -- Organic Search | Paid Ads | Social Media | Referral | Email | App Install
    lifetime_orders     INTEGER         NOT NULL DEFAULT 0
);


-- -----------------------------------------------------------------------------
-- DIMENSION: sellers
-- One row per seller registered on the marketplace.
-- -----------------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id           INTEGER         PRIMARY KEY,
    city                VARCHAR(50)     NOT NULL,
    state               VARCHAR(50)     NOT NULL,
    join_date           DATE            NOT NULL,
    category_focus      VARCHAR(50)     NOT NULL,
    fulfillment_type    VARCHAR(20)     NOT NULL,   -- FBA | Self-Ship | Marketplace
    seller_rating       DECIMAL(3,1)    NOT NULL,   -- 0.0 – 5.0
    active_listings     INTEGER         NOT NULL DEFAULT 0
);


-- -----------------------------------------------------------------------------
-- DIMENSION: products
-- One row per SKU listed on the platform.
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id          INTEGER         PRIMARY KEY,
    category            VARCHAR(50)     NOT NULL,
    subcategory         VARCHAR(50)     NOT NULL,
    brand               VARCHAR(50)     NOT NULL,
    mrp                 DECIMAL(10,2)   NOT NULL,
    avg_rating          DECIMAL(3,1)    NOT NULL,
    listing_date        DATE            NOT NULL
);


-- -----------------------------------------------------------------------------
-- FACT: orders
-- One row per customer order. Central fact table.
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id            INTEGER         PRIMARY KEY,
    customer_id         INTEGER         NOT NULL REFERENCES customers(customer_id),
    seller_id           INTEGER         NOT NULL REFERENCES sellers(seller_id),
    product_id          INTEGER         NOT NULL REFERENCES products(product_id),
    order_date          DATE            NOT NULL,
    status              VARCHAR(20)     NOT NULL,   -- Delivered | Cancelled | Returned | Processing
    gmv                 DECIMAL(10,2)   NOT NULL,   -- Gross Merchandise Value (price paid)
    discount_amt        DECIMAL(10,2)   NOT NULL DEFAULT 0,
    delivery_days       INTEGER,                    -- NULL for non-delivered orders
    return_flag         BOOLEAN         NOT NULL DEFAULT FALSE
);


-- -----------------------------------------------------------------------------
-- FACT: events (clickstream)
-- One row per user interaction event (view, cart, checkout, purchase).
-- -----------------------------------------------------------------------------
CREATE TABLE events (
    event_id            INTEGER         PRIMARY KEY,
    customer_id         INTEGER         NOT NULL REFERENCES customers(customer_id),
    product_id          INTEGER         NOT NULL REFERENCES products(product_id),
    event_type          VARCHAR(20)     NOT NULL,   -- view | add_to_cart | remove_from_cart | checkout | purchase
    event_ts            TIMESTAMP       NOT NULL,
    session_id          VARCHAR(20)     NOT NULL,
    platform            VARCHAR(20)     NOT NULL    -- Android App | iOS App | Web | Mobile Web
);


-- -----------------------------------------------------------------------------
-- FACT: inventory
-- One row per (seller, product, week) snapshot.
-- -----------------------------------------------------------------------------
CREATE TABLE inventory (
    inventory_id        INTEGER         PRIMARY KEY,
    product_id          INTEGER         NOT NULL REFERENCES products(product_id),
    seller_id           INTEGER         NOT NULL REFERENCES sellers(seller_id),
    stock_date          DATE            NOT NULL,
    units_available     INTEGER         NOT NULL DEFAULT 0,
    units_sold          INTEGER         NOT NULL DEFAULT 0,
    stockout_flag       BOOLEAN         NOT NULL DEFAULT FALSE
);


-- =============================================================================
-- INDEXES — for query performance
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_orders_customer    ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_product     ON orders(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_date        ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_orders_status      ON orders(status);
CREATE INDEX IF NOT EXISTS idx_events_customer    ON events(customer_id);
CREATE INDEX IF NOT EXISTS idx_events_type        ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_ts          ON events(event_ts);
CREATE INDEX IF NOT EXISTS idx_inventory_product  ON inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_seller   ON inventory(seller_id);
CREATE INDEX IF NOT EXISTS idx_inventory_date     ON inventory(stock_date);
