# Exercise 2

## Activity 2.1

### Table creation
```sql
create table orders (
    customer_name text,
    product_category text,
    quantity int,
    price_per_unit numeric,
    order_date date,
    country text
);

\copy orders from '/data/orders_1M.csv' with csv header;
```

### A. Highest price per unit
Query:
```sql
select * from orders order by price_per_unit desc limit 1;
```
Result:
Emma Brown, Automotive, 3 units, 2000.00, 2024-10-11, Italy.

### B. Top 3 categories by quantity sold
Query:
```sql
select product_category, sum(quantity)
from orders
group by product_category
order by sum(quantity) desc
limit 3;
```
Result:
1. Health & Beauty: 300842
2. Electronics: 300804
3. Toys: 300598

### C. Total revenue per product category
Query:
```sql
select product_category, sum(price_per_unit * quantity) as revenue
from orders
group by product_category
order by revenue desc;
```
Result:
- Automotive: ~306.58M
- Electronics: ~241.52M
- Home & Garden: ~78.02M
- Sports: ~61.84M
- Health & Beauty: ~46.59M
- Office Supplies: ~38.27M
- Fashion: ~31.56M
- Toys: ~23.27M
- Grocery: ~15.26M
- Books: ~12.73M

### D. Top 5 customers by spending
Query:
```sql
select customer_name, count(*), sum(price_per_unit * quantity) as total_spent
from orders
group by customer_name
order by total_spent desc
limit 5;
```
Result:
1. Carol Taylor - 1028 orders - 991179.18
2. Nina Lopez - 980 orders - 975444.95
3. Daniel Jackson - 1033 orders - 959344.48
4. Carol Lewis - 943 orders - 947708.57
5. Daniel Young - 973 orders - 946030.14

### E. Observations
All 5 customers have almost the exact same amount of orders (around 950-1030) and their total spending is really close (all around 950k - 990k). 
Looking at dataset_generator.py, there are only 32 first names and 33 last names, so only 1056 possible full names. Since 1M rows are generated with uniform random choices, each customer is picked around 1000000 / 1056 = ~947 times. Because the quantities and prices are also random, everything averages out. In real life you would have a few customers spending a lot and most people only buying once or twice.


## Activity 2.2

### Step 1
Created smaller tables:
```sql
create table people_50k as select * from people_big where id <= 50000;
create table people_100k as select * from people_big where id <= 100000;
create table people_200k as select * from people_big where id <= 200000;
```

Measurements:

| rows in table | join result (COUNT(*)) | time |
|---|---|---|
| 50 000 | 27501822 | ~3.5 s |
| 100 000 | 109946508 | ~13 s |
| 200 000 | 439395606 | ~52 s |

When the table size doubles, the results and execution time grow by around 4x. This means the query is O(N^2) because each person matches with everyone else from the same country.

Prediction for 1M rows (people_big):
1M is 5 times bigger than 200k, so 5^2 = 25x.
- Predicted rows: 439395606 * 25 = ~10.98 billion rows.
- Predicted time: 52s * 25 = ~1300 seconds (around 20-25 minutes).

### Step 2: Does an index help?
```sql
create index on people_100k(country);
analyze people_100k;
```
No, it does not help at all. The query still took ~13s. 
Checking explain analyze, Postgres still does a Hash Join and ignores the index. An index helps if you filter for one country like WHERE country = 'Austria', but here we are joining everything. Using an index to look up 100k rows would cause a lot of random lookups which is slower than just scanning the table. The main issue is calculating and counting over 100 million matches.

### Step 3: Rewrite
Instead of doing a self join, we can just count how many people live in each country, square that number (since everyone pairs with everyone in the same country), and sum them up:

```sql
select sum(cnt * cnt)
from (
    select country, count(*)::bigint as cnt
    from people_big
    group by country
) s;
```

Result on people_100k: 109946508 in ~20ms (was 13s).
Result on people_big: 10983941260 in ~0.25s (was predicted >20 mins).

### Step 4: Discussion
- The rewrite in Step 3 shows that an O(N^2) query cannot be fixed by hardware or indexes. If data doubles the work quadruples, so adding more CPU only gives a small linear speedup. Fixing the query to O(N) gives an instant massive speedup with no hardware changes.
- If the business actually needs all the pairs, 1M rows will produce ~11 billion pairs (~1 TB of data). A single Postgres instance will run out of memory or disk space. A distributed system like Spark would help because we can partition by country, so workers can generate the pairs in parallel without needing to communicate with each other. But usually dumping 11 billion rows is not useful, so we should filter or paginate instead.
- An OLTP database like Postgres is meant for small transactions, not full table scans. Scanning 1M rows wastes I/O because it reads full rows off disk instead of just the country column like a columnar database would. Long running queries also block Postgres vacuum and slow down normal transactions. In a real cloud setup, analytical queries should run on a separate replica, data warehouse, or lakehouse instead of the main production database.
