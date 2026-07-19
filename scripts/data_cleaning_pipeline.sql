-- ====================================================================
-- PROJECT: Retail Store Analytics - Data Cleaning & ETL Pipeline (V2)
-- OBJECTIVE: Clean, transform, index, and strictly filter out dead sales rows
-- DATABASE SYSTEM: SQLite
-- ====================================================================

-- STEP 1: INITIALIZE TARGET WAREHOUSE STRUCTURE
DROP TABLE IF EXISTS cleaned_clothing_store_sales;

CREATE TABLE cleaned_clothing_store_sales AS 
SELECT 
    -- Generates a clean, sequential primary key index (1, 2, 3...)
    ROW_NUMBER() OVER() AS transaction_id,
    
    date                AS transaction_date,
    customer_name       AS customer_name,
    phone               AS phone_number,
    
    -- FIX: Forces Title Case ('men' -> 'Men') and catches hidden NULL categories
    CASE 
        WHEN category IS NULL OR TRIM(category) = '' THEN 'Unassigned'
        ELSE UPPER(SUBSTR(TRIM(category), 1, 1)) || LOWER(SUBSTR(TRIM(category), 2))
    END AS category,
    
    item                AS item_name,
    size                AS item_size,
    color               AS color,
    qty                 AS quantity,
    price               AS price_per_unit,
    discount            AS discount_percentage,
    total_amount        AS total_amount,
    payment_mode        AS payment_mode,
    branch              AS branch_name,
    sales_rep           AS sales_rep_name
FROM raw_clothing_sales
-- FIX: Strict elimination of dead rows. 
-- If quantity is 0, empty, or NULL, it's not a real transaction and shouldn't pollute metrics.
WHERE qty > 0 AND qty IS NOT NULL AND qty != '';


-- STEP 2: RECTIFY TEXT CASING, TRIM WHITESPACE, AND RESOLVE NULL CUSTOMERS
UPDATE cleaned_clothing_store_sales
SET 
    item_name = TRIM(item_name),
    color = TRIM(color),
    customer_name = CASE 
        WHEN LOWER(TRIM(customer_name)) IN ('customer', 'walk-in', 'walk in', '') OR customer_name IS NULL THEN 'Walk-in'
        ELSE TRIM(customer_name)
    END;


-- STEP 3: NORMALIZE OPERATIONAL SEGMENTS (BRANCHES & PAYMENTS)
UPDATE cleaned_clothing_store_sales
SET 
    branch_name = CASE 
        WHEN LOWER(TRIM(branch_name)) IN ('mall road', 'mall rd') THEN 'Mall Road'
        WHEN LOWER(TRIM(branch_name)) IN ('main market') THEN 'Main Market'
        WHEN LOWER(TRIM(branch_name)) IN ('station branch') THEN 'Station Branch'
        WHEN branch_name IS NULL THEN 'Main Branch'
        ELSE TRIM(branch_name)
    END,
    payment_mode = CASE 
        WHEN UPPER(TRIM(payment_mode)) IN ('CASH') THEN 'Cash'
        WHEN UPPER(TRIM(payment_mode)) IN ('UPI', 'PHONEPE', 'GPAY') THEN 'UPI'
        WHEN UPPER(TRIM(payment_mode)) IN ('CARD', 'DEBIT CARD', 'CREDIT CARD') THEN 'Card'
        ELSE 'Other'
    END;


-- STEP 4: PURGE CORRUPTED CURRENCY TEXT FROM NUMERIC CHANNELS
UPDATE cleaned_clothing_store_sales
SET 
    price_per_unit = REPLACE(REPLACE(price_per_unit, 'Rs.', ''), '₹', '');


-- STEP 5: STANDARDIZE DISCOUNT STRINGS INTO FLAT INTEGERS
UPDATE cleaned_clothing_store_sales
SET 
    discount_percentage = CASE 
        WHEN discount_percentage IS NULL OR discount_percentage IN ('0', 'No', '') THEN '0'
        WHEN discount_percentage = 'Yes' THEN '10' -- Strategic fallback for textual markers
        ELSE REPLACE(discount_percentage, '%', '')
    END;


-- STEP 6: ENFORCE REVENUE CALCULATIONS & RE-COMPUTE FINANCIAL TOTALS
UPDATE cleaned_clothing_store_sales
SET 
    price_per_unit = CASE WHEN price_per_unit IS NULL OR price_per_unit = '' THEN 0 ELSE price_per_unit END,
    total_amount = CAST(quantity AS REAL) * CAST(price_per_unit AS REAL) * (1.0 - (CAST(discount_percentage AS REAL) / 100.0));


-- ====================================================================
-- STEP 7: POST-CLEANING QUALITY ASSURANCE CHECK
-- ====================================================================
-- This query should return 0 if our pipeline worked perfectly!
SELECT COUNT(*) AS remaining_invalid_quantity_rows 
FROM cleaned_clothing_store_sales 
WHERE quantity <= 0 OR quantity IS NULL;

-- This query should return perfectly consolidated, beautiful categories.
SELECT category, COUNT(*) as clean_frequency 
FROM cleaned_clothing_store_sales 
GROUP BY category;

-- ====================================================================
-- METRIC 8: ADVANCED DATE TEXT-TO-NUMBER CONVERSION
-- Converts textual formats (e.g., '25 Jul 2024') into clear, query-ready 'YYYY-MM-DD'
-- ====================================================================
UPDATE cleaned_clothing_store_sales
SET transaction_date = 
    CASE 
        -- Catch text dates by matching the space before the year ' 2023', ' 2024', or ' 2025'
        WHEN transaction_date LIKE '% 202%' THEN 
            SUBSTR(transaction_date, -4) || '-' || -- Year extraction
            CASE 
                WHEN transaction_date LIKE '%Jan%' THEN '01'
                WHEN transaction_date LIKE '%Feb%' THEN '02'
                WHEN transaction_date LIKE '%Mar%' THEN '03'
                WHEN transaction_date LIKE '%Apr%' THEN '04'
                WHEN transaction_date LIKE '%May%' THEN '05'
                WHEN transaction_date LIKE '%Jun%' THEN '06'
                WHEN transaction_date LIKE '%Jul%' THEN '07'
                WHEN transaction_date LIKE '%Aug%' THEN '08'
                WHEN transaction_date LIKE '%Sep%' THEN '09'
                WHEN transaction_date LIKE '%Oct%' THEN '10'
                WHEN transaction_date LIKE '%Nov%' THEN '11'
                WHEN transaction_date LIKE '%Dec%' THEN '12'
            END || '-' || 
            SUBSTR('0' || TRIM(SUBSTR(transaction_date, 1, 2)), -2) -- Padding single-digit days (e.g., '5' to '05')
        
        -- Keeps standard numerical dates untouched
        ELSE transaction_date 
    END;


-- ====================================================================
-- METRIC 9: HIDDEN CORRUPTION CHARACTERS IN FINANCIAL FIELDS
-- Eradicates the '?' and 'Rs.' text markers directly from the numeric column
-- ====================================================================
UPDATE cleaned_clothing_store_sales
SET price_per_unit = REPLACE(REPLACE(REPLACE(price_per_unit, 'Rs.', ''), '₹', ''), '?', '');


-- ====================================================================
-- METRIC 10 : PRODUCT COLOR SKEW STANDARDIZATION
-- Forces Proper/Title Case (e.g., 'grey', 'Grey', 'GREY' all combine cleanly into 'Grey')
-- ====================================================================
UPDATE cleaned_clothing_store_sales
SET color = 
    CASE 
        WHEN color IS NULL OR TRIM(color) = '' THEN 'Unknown'
        ELSE UPPER(SUBSTR(TRIM(color), 1, 1)) || LOWER(SUBSTR(TRIM(color), 2))
    END;

-- ====================================================================
-- CLEANING STEP: SANITIZE PHONE NUMBERS FOR CRM READINESS
-- Strips country codes, structural dashes, and spaces to extract 10-digit numbers
-- ====================================================================
UPDATE cleaned_clothing_store_sales
SET phone_number = 
    CASE 
        WHEN phone_number IS NULL OR TRIM(phone_number) = '' THEN 'No Contact'
        ELSE 
            -- 1. Remove common formatting noise (country prefix signs, structural spaces, dashes)
            CASE 
                -- If it contains +91-, remove it entirely
                WHEN phone_number LIKE '+91-%' THEN REPLACE(phone_number, '+91-', '')
                -- Strip basic special symbols manually for absolute standard string formatting
                ELSE REPLACE(REPLACE(REPLACE(phone_number, '+91', ''), '-', ''), ' ', '')
            END
    END;

-- Final normalization pass: Trim spaces and make sure we keep only the last 10 digits 
-- (This cleanly strips out any accidental remaining prefix numbers)
UPDATE cleaned_clothing_store_sales
SET phone_number = CASE 
    WHEN phone_number = 'No Contact' THEN 'No Contact'
    ELSE SUBSTR(TRIM(phone_number), -10)
END;
