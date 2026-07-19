-- ====================================================================
-- PROJECT: Retail Store Analytics - Data Profiling Script
-- OBJECTIVE: Audit raw_clothing_sales to identify data anomalies and leakage
-- DATABASE SYSTEM: SQLite
-- ====================================================================

-- 1. OVERALL RECORD COUNT AUDIT
-- Checks total transaction volume logged in the system
SELECT COUNT(*) AS total_raw_records 
FROM raw_clothing_sales;


-- 2. NULL VALUE ASSESSMENT
-- Identifies critical information gaps that break sales reports
SELECT 
    COUNT(*) - COUNT(date) AS missing_dates,
    COUNT(*) - COUNT(customer_name) AS anonymous_customers,
    COUNT(*) - COUNT(phone) AS missing_phone_numbers,
    COUNT(*) - COUNT(category) AS unassigned_categories,
    COUNT(*) - COUNT(item) AS unnamed_items,
    COUNT(*) - COUNT(qty) AS unrecorded_quantities,
    COUNT(*) - COUNT(price) AS missing_unit_prices,
    COUNT(*) - COUNT(total_amount) AS broken_totals,
    COUNT(*) - COUNT(branch) AS missing_branches
FROM raw_clothing_sales;


-- 3. TEXT INCONSISTENCY & WHITESPACE PROFILING
-- Reveals duplicate entries caused by human typing discrepancies (e.g., 'Mall Road' vs 'Mall Rd')
SELECT DISTINCT branch, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY branch
ORDER BY frequency DESC;

SELECT DISTINCT category, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY category;


-- 4. CURRENCY SYMBOL CONTAMINATION CHECK
-- Flags rows where currency formatting strings prevent mathematical calculation
SELECT COUNT(*) AS rows_with_corrupted_price_strings
FROM raw_clothing_sales
WHERE price LIKE '%Rs.%' OR price LIKE '%₹%';


-- 5. DISCOUNT LOGGING ANOMALIES
-- Audits the chaotic tracking of store promotions
SELECT DISTINCT discount, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY discount;


-- 6. QUANTITY ANOMALY AUDIT
-- Flags zero or negative item quantities that skew store metrics
SELECT COUNT(*) AS zero_or_negative_quantity_transactions
FROM raw_clothing_sales
WHERE qty <= 0 OR qty IS NULL;
