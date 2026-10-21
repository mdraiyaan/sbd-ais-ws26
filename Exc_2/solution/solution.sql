\timing on

-- setup orders table
drop table if exists orders;
create table orders (
    customer_name text,
    product_category text,
    quantity int,
    price_per_unit numeric,
    order_date date,
    country text
);

\copy orders from '/data/orders_1M.csv' with csv header;

-- 2.1 A: highest unit price
select * from orders order by price_per_unit desc limit 1;

-- 2.1 B: top 3 categories by total quantity
select product_category, sum(quantity)
from orders
group by product_category
order by sum(quantity) desc
limit 3;

-- 2.1 C: total revenue per category
select product_category, sum(price_per_unit * quantity) as revenue
from orders
group by product_category
order by revenue desc;

-- 2.1 D: top 5 customers by spending
select customer_name, count(*), sum(price_per_unit * quantity) as total_spent
from orders
group by customer_name
order by total_spent desc
limit 5;


-- 2.2 self join
-- smaller tables for testing
create table people_50k as select * from people_big where id <= 50000;
create table people_100k as select * from people_big where id <= 100000;
create table people_200k as select * from people_big where id <= 200000;

-- step 1 queries
select count(*) from people_50k p1 join people_50k p2 on p1.country = p2.country;
select count(*) from people_100k p1 join people_100k p2 on p1.country = p2.country;
select count(*) from people_200k p1 join people_200k p2 on p1.country = p2.country;

-- step 2 index test
create index on people_100k(country);
analyze people_100k;

explain analyze
select count(*) from people_100k p1 join people_100k p2 on p1.country = p2.country;

-- step 3 rewrite
-- test on 100k
select sum(cnt * cnt)
from (
    select country, count(*)::bigint as cnt
    from people_100k
    group by country
) s;

-- run on full 1M
select sum(cnt * cnt)
from (
    select country, count(*)::bigint as cnt
    from people_big
    group by country
) s;
