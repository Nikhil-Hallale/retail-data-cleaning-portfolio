/* ============================================================
   PROJECT   : Clothing Store Sales - Data Cleaning
   SCRIPT    : 02_cleaning_clothing_sales.sql
   SOURCE    : raw_clothing_sales   (see 01_profiling script)
   OUTPUT    : cleaned_clothing_sales
   DIALECT   : PostgreSQL (regexp_replace, TO_DATE, ~ operator)
   RUN ORDER : 01_profiling_raw_clothing_sales.sql first, so you
               have "before" numbers to compare against.
   ============================================================ */


-- ------------------------------------------------------------
-- STEP 0 -- Clean slate if re-running
-- ------------------------------------------------------------
DROP TABLE IF EXISTS cleaned_clothing_sales;


-- ------------------------------------------------------------
-- STEP 1 -- Stage: drop junk rows, fully blank rows, and exact
--           duplicate rows before touching individual columns.
--           (Fixes profiling sections 3, 4, 5a)
-- ------------------------------------------------------------
CREATE TEMP TABLE staged_sales AS
SELECT DISTINCT ON ("Bill No", "Date", "Customer Name", "Phone", "Item", "Total Amount") *
FROM raw_clothing_sales
WHERE
    NOT (
        NULLIF(TRIM("Bill No"), '')       IS NULL
        AND NULLIF(TRIM("Date"), '')          IS NULL
        AND NULLIF(TRIM("Customer Name"), '') IS NULL
        AND NULLIF(TRIM("Item"), '')          IS NULL
        AND NULLIF(TRIM("Total Amount"), '')  IS NULL
    )
    AND "Bill No" NOT ILIKE '%total%'
    AND ("Total Amount" IS NULL OR "Total Amount" NOT ILIKE '=%');


-- ------------------------------------------------------------
-- STEP 2 -- Build the cleaned table, one CTE per fix.
-- ------------------------------------------------------------
CREATE TABLE cleaned_clothing_sales AS

WITH

-- 2a. Date -> single ISO DATE type.
--     (Fixes profiling section 6)
--     ASSUMPTION, stated explicitly: this file has two distinct
--     slash-date patterns -- one 4-digit-year, one 2-digit-year.
--     Profiling showed they behave as MM/DD/YYYY and DD/MM/YY
--     respectively in this export. That mapping is specific to
--     this source system; re-verify before reusing on another
--     file, since numeric slash-dates are ambiguous in general.
dates AS (
    SELECT
        *,
        CASE
            WHEN "Date" ~ '^\d{4}-\d{2}-\d{2}$'
                THEN TO_DATE("Date", 'YYYY-MM-DD')
            WHEN "Date" ~ '^\d{2}-\d{2}-\d{4}$'
                THEN TO_DATE("Date", 'DD-MM-YYYY')
            WHEN "Date" ~ '^\d{2}/\d{2}/\d{4}$'
                THEN TO_DATE("Date", 'MM/DD/YYYY')
            WHEN "Date" ~ '^\d{2}/\d{2}/\d{2}$'
                THEN TO_DATE("Date", 'DD/MM/YY')
            WHEN "Date" ~ '^\d{2} [A-Za-z]{3} \d{4}$'
                THEN TO_DATE("Date", 'DD Mon YYYY')
            ELSE NULL
        END AS transaction_date_clean
    FROM staged_sales
),

-- 2b. Phone -> digits-only 10-digit number, or true NULL.
--     Collapses the "NA" placeholder text into the same NULL
--     used for genuinely blank cells.
--     (Fixes profiling section 12)
phones AS (
    SELECT
        *,
        CASE
            WHEN "Phone" IS NULL OR TRIM("Phone") = '' OR "Phone" ILIKE 'na'
                THEN NULL
            ELSE regexp_replace(TRIM("Phone"), '[^0-9]', '', 'g')
        END AS phone_clean
    FROM dates
),

-- 2c. Price -> numeric, currency symbols stripped.
--     Missing/unparseable price becomes NULL, never 0 -- a
--     literal 0 would understate AVG(price) and misrepresent a
--     real sale as free.
--     (Fixes profiling sections 8a/8b)
prices AS (
    SELECT
        *,
        CASE
            WHEN regexp_replace(TRIM("Price"), '(Rs\.?|₹)', '', 'gi') ~ '^\d+(\.\d+)?$'
                THEN regexp_replace(TRIM("Price"), '(Rs\.?|₹)', '', 'gi')::numeric
            ELSE NULL
        END AS price_clean
    FROM phones
),

-- 2d. Qty -> positive integer or NULL; negative qty flagged
--     separately as a return instead of being discarded.
--     (Fixes profiling section 9)
quantities AS (
    SELECT
        *,
        CASE WHEN "Qty" ~ '^-?\d+$' AND "Qty"::int < 0 THEN TRUE ELSE FALSE END AS is_return,
        CASE
            WHEN "Qty" ~ '^\d+$' AND "Qty"::int > 0 THEN "Qty"::int
            ELSE NULL
        END AS qty_clean
    FROM prices
),

-- 2e. Discount -> integer percent (0-100).
--     "Yes" with no percentage given is treated as unknown, not
--     guessed at, so it falls back to 0 rather than fabricating
--     a discount amount.
--     (Fixes profiling section 10)
discounts AS (
    SELECT
        *,
        CASE
            WHEN "Discount" ~ '^\d+%$'        THEN replace("Discount", '%', '')::int
            WHEN "Discount" ~ '^\d+(\.\d+)?$' THEN ROUND("Discount"::numeric)::int
            ELSE 0
        END AS discount_clean
    FROM quantities
),

-- 2f. Categorical / free-text columns -> trimmed, consistently
--     cased, known typos and near-duplicates collapsed onto one
--     canonical spelling.
--     (Fixes profiling section 7)
text_fields AS (
    SELECT
        *,
        INITCAP(TRIM("Category")) AS category_clean,

        CASE
            WHEN INITCAP(TRIM("Item")) = 'Kurthi'                THEN 'Kurti'
            WHEN INITCAP(TRIM("Item")) IN ('Tshirt', 'T Shirt')  THEN 'T-Shirt'
            ELSE INITCAP(TRIM("Item"))
        END AS item_clean,

        CASE
            WHEN INITCAP(TRIM("Size")) IN ('Free Size', 'One Size') THEN 'Free Size'
            WHEN "Size" IS NULL OR TRIM("Size") = ''                THEN NULL
            ELSE UPPER(TRIM("Size"))
        END AS size_clean,

        INITCAP(TRIM("Color")) AS color_clean,

        CASE
            WHEN UPPER(TRIM("Payment Mode")) = 'CASH'                                THEN 'Cash'
            WHEN UPPER(TRIM("Payment Mode")) IN ('UPI', 'GPAY', 'PHONEPE')            THEN 'UPI'
            WHEN UPPER(TRIM("Payment Mode")) IN ('CARD', 'DEBIT CARD', 'CREDIT CARD') THEN 'Card'
            WHEN "Payment Mode" IS NULL OR TRIM("Payment Mode") = ''                  THEN 'Unknown'
            ELSE 'Other'
        END AS payment_mode_clean,

        CASE
            WHEN UPPER(TRIM("Branch")) IN ('MALL ROAD', 'MALL RD')  THEN 'Mall Road'
            WHEN UPPER(TRIM("Branch")) = 'MAIN MARKET'              THEN 'Main Market'
            WHEN UPPER(TRIM("Branch")) = 'STATION BRANCH'           THEN 'Station Branch'
            ELSE NULL   -- unrecognized/blank left NULL rather than guessed
        END AS branch_clean,

        CASE
            WHEN "Sales Rep" IS NULL OR TRIM("Sales Rep") = '' THEN NULL
            ELSE INITCAP(TRIM("Sales Rep"))
        END AS sales_rep_clean,

        CASE
            WHEN "Customer Name" IS NULL OR TRIM("Customer Name") = ''
                 OR UPPER(TRIM("Customer Name")) IN ('WALK IN', 'WALK-IN', 'CUSTOMER')
                THEN 'Walk-in'
            ELSE INITCAP(TRIM("Customer Name"))
        END AS customer_name_clean

    FROM discounts
)

-- 2g. Final projection: Total Amount is recomputed from the now
--     -clean Price / Qty / Discount rather than trusting the
--     original stored value, which profiling showed disagreed
--     with the math on a meaningful share of rows.
--     (Fixes profiling section 11)
SELECT
    ROW_NUMBER() OVER (ORDER BY transaction_date_clean, "Bill No") AS transaction_id,
    transaction_date_clean AS transaction_date,
    customer_name_clean    AS customer_name,
    phone_clean             AS phone_number,
    category_clean          AS category,
    item_clean               AS item_name,
    size_clean                AS item_size,
    color_clean                AS color,
    qty_clean                   AS quantity,
    price_clean                  AS price_per_unit,
    discount_clean                AS discount_percentage,
    CASE
        WHEN price_clean IS NOT NULL AND qty_clean IS NOT NULL
            THEN ROUND(price_clean * qty_clean * (1 - discount_clean / 100.0), 2)
        ELSE NULL
    END AS total_amount,
    payment_mode_clean  AS payment_mode,
    branch_clean        AS branch_name,
    sales_rep_clean     AS sales_rep_name,
    is_return
FROM text_fields;


-- ------------------------------------------------------------
-- STEP 3 -- Verification. Every query below should come back
--           empty / zero if the cleaning worked as intended.
-- ------------------------------------------------------------

-- 3a. No duplicate rows
SELECT customer_name, phone_number, item_name, total_amount, COUNT(*)
FROM cleaned_clothing_sales
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) > 1;

-- 3b. Exactly one representation of missing per categorical column
SELECT DISTINCT payment_mode FROM cleaned_clothing_sales;
SELECT DISTINCT branch_name  FROM cleaned_clothing_sales;
SELECT DISTINCT item_size    FROM cleaned_clothing_sales;

-- 3c. No zero-priced rows standing in for missing prices
SELECT COUNT(*) AS zero_price_rows
FROM cleaned_clothing_sales
WHERE price_per_unit = 0;

-- 3d. Total Amount is internally consistent
SELECT COUNT(*) AS mismatched_totals
FROM cleaned_clothing_sales
WHERE total_amount IS NOT NULL
  AND total_amount <> ROUND(price_per_unit * quantity * (1 - discount_percentage / 100.0), 2);

-- 3e. Date range sanity check (single clean DATE type now)
SELECT MIN(transaction_date) AS earliest, MAX(transaction_date) AS latest
FROM cleaned_clothing_sales;

-- 3f. Row count before/after
SELECT
    (SELECT COUNT(*) FROM raw_clothing_sales)     AS raw_row_count,
    (SELECT COUNT(*) FROM cleaned_clothing_sales) AS cleaned_row_count;
