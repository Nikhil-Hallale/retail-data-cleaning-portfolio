-- ====================================================================
-- PROJECT: Retail Store Analytics - Comprehensive Data Profiling
-- OBJECTIVE: Audit raw_clothing_sales to isolate data anomalies and data leakage
-- DATABASE SYSTEM: SQLite
-- ====================================================================

-- 1. OVERALL RECORD COUNT AUDIT
SELECT COUNT(*) AS total_raw_records 
FROM raw_clothing_sales;


-- 2. NULL & DATA GAP ASSESSMENT
SELECT 
    COUNT(*) - COUNT(date) AS missing_dates,
    COUNT(*) - COUNT(customer_name) AS anonymous_customers,
    COUNT(*) - COUNT(phone) AS missing_phone_numbers,
    COUNT(*) - COUNT(category) AS unassigned_categories,
    COUNT(*) - COUNT(item) AS unnamed_items,
    COUNT(*) - COUNT(qty) AS unrecorded_quantities,
    COUNT(*) - COUNT(price) AS missing_unit_prices,
    COUNT(*) - COUNT(total_amount) AS broken_totals,
    COUNT(*) - COUNT(payment_mode) AS missing_payment_modes,
    COUNT(*) - COUNT(branch) AS missing_branches,
    COUNT(*) - COUNT(sales_rep) AS ghost_sales_missing_sales_reps
FROM raw_clothing_sales;


-- 3. CATEGORY & ITEM TEXT CASING PROFILE
SELECT DISTINCT category, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY category;


-- 4. BRANCH & LOCATION TEXT NORMALIZATION PROFILE
SELECT DISTINCT branch, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY branch
ORDER BY frequency DESC;


-- 5. PAYMENT MODE UNIFICATION PROFILING
SELECT DISTINCT payment_mode, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY payment_mode;


-- 6. DISCOUNT LOGGING TRACKING AUDIT
SELECT DISTINCT discount, COUNT(*) as frequency
FROM raw_clothing_sales
GROUP BY discount;


-- 7. QUANTITY DESTRUCTION & CANCELLED ORDER DETECTION
SELECT COUNT(*) AS zero_or_negative_quantity_transactions
FROM raw_clothing_sales
WHERE qty <= 0 OR qty IS NULL OR qty = '';


-- 8. PRODUCT COLOR VARIATION & CASE SKEW AUDIT
SELECT color, COUNT(*) as tracking_count
FROM raw_clothing_sales
GROUP BY color
ORDER BY color;


-- 9. CURRENCY FORMATTING & STRANGE STRING DETECTION IN PRICE
SELECT price, COUNT(*) AS distribution_count
FROM raw_clothing_sales 
WHERE price LIKE '%Rs.%' OR price LIKE '%₹%' OR price LIKE '%?%'
GROUP BY price;


-- 10. ADVANCED STRING-BASED DATE DETECTION
SELECT date, COUNT(*) AS string_month_count
FROM raw_clothing_sales 
WHERE date LIKE '%Jan%' OR date LIKE '%Feb%' OR date LIKE '%Mar%' OR date LIKE '%Apr%' 
   OR date LIKE '%May%' OR date LIKE '%Jun%' OR date LIKE '%Jul%' OR date LIKE '%Aug%' 
   OR date LIKE '%Sep%' OR date LIKE '%Oct%' OR date LIKE '%Nov%' OR date LIKE '%Dec%'
GROUP BY date;


-- 11. PHONE NUMBER FORMAT CORRUPTION & CONNECTOR CHECK
SELECT COUNT(*) AS corrupted_phone_records
FROM raw_clothing_sales
WHERE phone LIKE '%-%' OR phone LIKE '%+%' OR phone LIKE '% %';


-- 12. APPAREL CLOTHING SIZE LOGISTICS GAP
SELECT category, COUNT(*) AS apparel_missing_sizes
FROM raw_clothing_sales
WHERE size IS NULL OR TRIM(size) = ''
GROUP BY category;


-- 13. EXACT TRANSACTION RECORD DUPLICATION DENSITY
SELECT COUNT(*) - COUNT(DISTINCT date || customer_name || phone || item || qty || price) AS identical_duplicate_rows
FROM raw_clothing_sales;


-- 14. HIDDEN PRODUCT NAME LEADING/TRAILING SPACE PADDING
SELECT COUNT(*) AS items_with_corrupt_space_padding
FROM raw_clothing_sales
WHERE item LIKE ' %' OR item LIKE '% ';
