-- Exercise 2: Operational Data Plane with OLTPs
-- Course: Software Architectures for Big Data

\timing on

-- ========================================================
-- Activity 2.1 — E-commerce Analytical Queries
-- ========================================================

DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
    customer_name TEXT,
    product_category TEXT,
    quantity INT,
    price_per_unit NUMERIC(10, 2),
    order_date DATE,
    country TEXT
);

\COPY orders FROM '/data/orders_1M.csv' WITH CSV HEADER;

-- A. Highest price per unit
SELECT * 
FROM orders 
ORDER BY price_per_unit DESC 
LIMIT 1;

-- B. Top 3 categories by total quantity
SELECT product_category, SUM(quantity) AS total_sold
FROM orders
GROUP BY product_category
ORDER BY total_sold DESC
LIMIT 3;

-- C. Revenue per category
SELECT product_category, ROUND(SUM(price_per_unit * quantity), 2) AS revenue
FROM orders
GROUP BY product_category
ORDER BY revenue DESC;

-- D. Top 5 customers by spending
SELECT customer_name, COUNT(*) AS num_orders, ROUND(SUM(price_per_unit * quantity), 2) AS total_spent
FROM orders
GROUP BY customer_name
ORDER BY total_spent DESC
LIMIT 5;


-- ========================================================
-- Activity 2.2 — Self-Join Analysis
-- ========================================================

-- Step 1: Create smaller tables to test scaling
DROP TABLE IF EXISTS people_50k;
DROP TABLE IF EXISTS people_100k;
DROP TABLE IF EXISTS people_200k;

CREATE TABLE people_50k  AS SELECT * FROM people_big WHERE id <= 50000;
CREATE TABLE people_100k AS SELECT * FROM people_big WHERE id <= 100000;
CREATE TABLE people_200k AS SELECT * FROM people_big WHERE id <= 200000;

-- Measurements:
SELECT COUNT(*) FROM people_50k  p1 JOIN people_50k  p2 ON p1.country = p2.country;
SELECT COUNT(*) FROM people_100k p1 JOIN people_100k p2 ON p1.country = p2.country;
SELECT COUNT(*) FROM people_200k p1 JOIN people_200k p2 ON p1.country = p2.country;

-- Step 2: Index test on people_100k
CREATE INDEX idx_country ON people_100k(country);
ANALYZE people_100k;

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM people_100k p1
JOIN people_100k p2 ON p1.country = p2.country;

-- Step 3: Query rewrite without join
-- Test on 100k:
SELECT SUM(cnt * cnt)
FROM (
    SELECT country, COUNT(*)::BIGINT AS cnt
    FROM people_100k
    GROUP BY country
) sub;

-- Run on full 1M table:
SELECT SUM(cnt * cnt)
FROM (
    SELECT country, COUNT(*)::BIGINT AS cnt
    FROM people_big
    GROUP BY country
) sub;
