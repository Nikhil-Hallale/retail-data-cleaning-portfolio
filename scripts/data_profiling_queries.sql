/* ============================================================
   PROJECT   : Clothing Store Sales - Data Cleaning
   SCRIPT    : 01_profiling_raw_clothing_sales.sql
   PURPOSE   : Load the raw export and quantify every data
               quality issue in it before any cleaning happens.
   DIALECT   : PostgreSQL
               (ILIKE, regexp_replace, ~ operator, FILTER clause)
   ============================================================ */


-- ------------------------------------------------------------
-- 0. TABLE DEFINITION
--    Every column is TEXT on purpose: the raw file mixes
--    numbers, currency symbols, percent signs, and blanks in
--    the same column, so nothing here is safe to type strictly
--    at load time. Typing happens during cleaning, not loading.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS raw_clothing_sales;

CREATE TABLE raw_clothing_sales (
    "Bill No"        TEXT,
    "Date"           TEXT,
    "Customer Name"  TEXT,
    "Phone"          TEXT,
    "Category"       TEXT,
    "Item"           TEXT,
    "Size"           TEXT,
    "Color"          TEXT,
    "Qty"            TEXT,
    "Price"          TEXT,
    "Discount"       TEXT,
    "Total Amount"   TEXT,
    "Payment Mode"   TEXT,
    "Branch"         TEXT,
    "Sales Rep"      TEXT
);

-- Load with psql (adjust path):
-- \copy raw_clothing_sales FROM 'raw_clothing_sales.csv' WITH (FORMAT csv, HEADER true);


-- ------------------------------------------------------------
-- 1. SHAPE CHECK
-- ------------------------------------------------------------
SELECT COUNT(*) AS total_rows
FROM raw_clothing_sales;


-- ------------------------------------------------------------
-- 2. MISSING VALUES PER COLUMN
--    Blank strings and whitespace-only values are counted as
--    missing too, since a raw CSV rarely gives a true NULL.
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Bill No"), '')       IS NULL) AS missing_bill_no,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Date"), '')          IS NULL) AS missing_date,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Customer Name"), '') IS NULL) AS missing_customer_name,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Phone"), '')         IS NULL) AS missing_phone,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Category"), '')      IS NULL) AS missing_category,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Item"), '')          IS NULL) AS missing_item,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Size"), '')          IS NULL) AS missing_size,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Color"), '')         IS NULL) AS missing_color,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Qty"), '')           IS NULL) AS missing_qty,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Price"), '')         IS NULL) AS missing_price,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Discount"), '')      IS NULL) AS missing_discount,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Total Amount"), '')  IS NULL) AS missing_total_amount,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Payment Mode"), '')  IS NULL) AS missing_payment_mode,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Branch"), '')        IS NULL) AS missing_branch,
    COUNT(*) FILTER (WHERE NULLIF(TRIM("Sales Rep"), '')     IS NULL) AS missing_sales_rep
FROM raw_clothing_sales;


-- ------------------------------------------------------------
-- 3. FULLY BLANK ROWS
-- ------------------------------------------------------------
SELECT *
FROM raw_clothing_sales
WHERE NULLIF(TRIM("Bill No"), '')       IS NULL
  AND NULLIF(TRIM("Date"), '')          IS NULL
  AND NULLIF(TRIM("Customer Name"), '') IS NULL
  AND NULLIF(TRIM("Item"), '')          IS NULL
  AND NULLIF(TRIM("Total Amount"), '')  IS NULL;


-- ------------------------------------------------------------
-- 4. JUNK / SUMMARY ROWS
--    Leftover totals rows or spreadsheet formulas saved as
--    literal text (e.g. "=SUM(above)").
-- ------------------------------------------------------------
SELECT *
FROM raw_clothing_sales
WHERE "Bill No" ILIKE '%total%'
   OR "Total Amount" ILIKE '=%';


-- ------------------------------------------------------------
-- 5. DUPLICATE ROWS
-- ------------------------------------------------------------
-- 5a. Rows that are identical across the fields that uniquely
--     identify a transaction
SELECT "Bill No", "Date", "Customer Name", "Phone", "Item", "Total Amount",
       COUNT(*) AS occurrences
FROM raw_clothing_sales
GROUP BY "Bill No", "Date", "Customer Name", "Phone", "Item", "Total Amount"
HAVING COUNT(*) > 1;

-- 5b. Duplicate Bill No (should be unique per transaction)
SELECT "Bill No", COUNT(*) AS occurrences
FROM raw_clothing_sales
GROUP BY "Bill No"
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- 6. DATE FORMAT INCONSISTENCY
--    A clean column should show exactly one non-zero bucket.
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN "Date" ~ '^\d{4}-\d{2}-\d{2}$'       THEN 'YYYY-MM-DD'
        WHEN "Date" ~ '^\d{2}-\d{2}-\d{4}$'       THEN 'DD-MM-YYYY'
        WHEN "Date" ~ '^\d{2}/\d{2}/\d{4}$'       THEN 'slash, 4-digit year'
        WHEN "Date" ~ '^\d{2}/\d{2}/\d{2}$'       THEN 'slash, 2-digit year'
        WHEN "Date" ~ '^\d{2} [A-Za-z]{3} \d{4}$' THEN 'DD Mon YYYY'
        ELSE 'unrecognized'
    END AS date_format,
    COUNT(*) AS row_count
FROM raw_clothing_sales
GROUP BY 1
ORDER BY row_count DESC;


-- ------------------------------------------------------------
-- 7. TEXT CASING / SPELLING INCONSISTENCY
--    Any column below where the same real value appears more
--    than once under a different spelling/casing needs fixing.
-- ------------------------------------------------------------
SELECT "Category",     COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Item",          COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Size",          COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Color",         COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Payment Mode",  COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Branch",        COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Sales Rep",     COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;
SELECT "Customer Name", COUNT(*) FROM raw_clothing_sales GROUP BY 1 ORDER BY 1;


-- ------------------------------------------------------------
-- 8. PRICE FIELD -- CURRENCY SYMBOLS / NON-NUMERIC VALUES
-- ------------------------------------------------------------
SELECT "Price", COUNT(*) AS occurrences
FROM raw_clothing_sales
WHERE "Price" IS NOT NULL
  AND TRIM("Price") <> ''
  AND regexp_replace(TRIM("Price"), '(Rs\.?|₹)', '', 'gi') !~ '^\d+(\.\d+)?$'
GROUP BY "Price";

-- How many rows are otherwise-clean numbers vs symbol-prefixed
SELECT
    CASE
        WHEN "Price" ~ '^\d+(\.\d+)?$'         THEN 'plain number'
        WHEN "Price" ILIKE 'rs.%'               THEN 'Rs. prefixed'
        WHEN "Price" ~ '₹'                      THEN '₹ prefixed'
        WHEN "Price" IS NULL OR TRIM("Price")='' THEN 'missing'
        ELSE 'other'
    END AS price_format,
    COUNT(*)
FROM raw_clothing_sales
GROUP BY 1;


-- ------------------------------------------------------------
-- 9. QUANTITY ANOMALIES
--    Negative = likely a return keyed into the sales field;
--    zero = invalid, nothing was actually sold.
-- ------------------------------------------------------------
SELECT "Qty", COUNT(*) AS occurrences
FROM raw_clothing_sales
WHERE "Qty" ~ '^-?\d+$'
  AND "Qty"::int <= 0
GROUP BY "Qty";


-- ------------------------------------------------------------
-- 10. DISCOUNT FIELD INCONSISTENCY
--     Mixes plain numbers, "10%"-style strings, and "Yes".
-- ------------------------------------------------------------
SELECT "Discount", COUNT(*) AS occurrences
FROM raw_clothing_sales
GROUP BY "Discount"
ORDER BY 2 DESC;


-- ------------------------------------------------------------
-- 11. TOTAL AMOUNT MISMATCH
--     Recomputes Price * Qty * (1 - Discount%) on the
--     already-numeric subset of rows and flags disagreements
--     with the stored Total Amount.
-- ------------------------------------------------------------
WITH parsed AS (
    SELECT
        "Bill No",
        regexp_replace(TRIM("Price"), '(Rs\.?|₹)', '', 'gi')::numeric AS price_num,
        TRIM("Qty")::numeric AS qty_num,
        CASE
            WHEN "Discount" ~ '^\d+%$'        THEN replace("Discount", '%', '')::numeric
            WHEN "Discount" ~ '^\d+(\.\d+)?$' THEN "Discount"::numeric
            ELSE 0
        END AS discount_pct,
        TRIM("Total Amount")::numeric AS total_stored
    FROM raw_clothing_sales
    WHERE regexp_replace(TRIM("Price"), '(Rs\.?|₹)', '', 'gi') ~ '^\d+(\.\d+)?$'
      AND "Qty" ~ '^\d+$'
      AND "Total Amount" ~ '^\d+(\.\d+)?$'
)
SELECT
    "Bill No", price_num, qty_num, discount_pct,
    ROUND(price_num * qty_num * (1 - discount_pct / 100.0), 2) AS total_recomputed,
    total_stored
FROM parsed
WHERE ROUND(price_num * qty_num * (1 - discount_pct / 100.0), 2) <> total_stored;


-- ------------------------------------------------------------
-- 12. PHONE NUMBER FORMAT INCONSISTENCY
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN "Phone" IS NULL OR TRIM("Phone") = '' THEN 'blank/NULL'
        WHEN "Phone" ILIKE 'na'                     THEN 'placeholder text (NA)'
        WHEN "Phone" ~ '^\+91-\d{10}$'              THEN '+91-prefixed'
        WHEN "Phone" ~ '^\d{5} \d{5}$'               THEN 'spaced 5+5'
        WHEN "Phone" ~ '^\d{10}$'                    THEN 'clean 10-digit'
        ELSE 'other/unexpected'
    END AS phone_format,
    COUNT(*) AS occurrences
FROM raw_clothing_sales
GROUP BY 1
ORDER BY 2 DESC;
