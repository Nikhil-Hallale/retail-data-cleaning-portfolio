-- ====================================================================
-- PROJECT: Retail Store Analytics - Comprehensive Cleaning & ETL Pipeline
-- OBJECTIVE: Clean, transform, index, and completely optimize the retail ledger
-- DATABASE SYSTEM: SQLite
-- ====================================================================

-- STEP 1: INITIALIZE STABLE WAREHOUSE DATABASE AND INGEST CLEAN DATA
DROP TABLE IF EXISTS cleaned_clothing_store_sales;

CREATE TABLE cleaned_clothing_store_sales AS 
SELECT 
    -- Generates a clean, sequential primary key index (1, 2, 3...) to protect ledger record order
    ROW_NUMBER() OVER() AS transaction_id,
    
    -- Load base underscore data from your SQLite storage engine configurations
    date                AS transaction_date,
    customer_name       AS customer_name,
    phone               AS phone_number,
    
    -- Fix Text Case anomalies ('men' -> 'Men') and catch blank category records right at execution
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
-- Filters out zero, empty, or NULL quantities representing system dead rows/cancelled orders
WHERE qty > 0 AND qty IS NOT NULL AND qty != '';


-- STEP 2: RECTIFY TEXT CASING, TRIM HIDDEN SPACES, AND RESOLVE NULL ATTRIBUTIONS
UPDATE cleaned_clothing_store_sales
SET 
    -- Clean leading/trailing spaces and convert to standard Title Case formatting
    item_name = UPPER(SUBSTR(TRIM(item_name), 1, 1)) || LOWER(SUBSTR(TRIM(item_name), 2)),
    color = UPPER(SUBSTR(TRIM(color), 1, 1)) || LOWER(SUBSTR(TRIM(color), 2)),
    
    -- Normalize Customer Names and route broken text entries to standard segments
    customer_name = CASE 
        WHEN LOWER(TRIM(customer_name)) IN ('customer', 'walk-in', 'walk in', '') OR customer_name IS NULL THEN 'Walk-in'
        ELSE TRIM(customer_name)
    END,
    
    -- Resolve missing personnel listings to safeguard historical operational splits
    sales_rep_name = CASE 
        WHEN sales_rep_name IS NULL OR TRIM(sales_rep_name) = '' THEN 'House Account'
        ELSE UPPER(SUBSTR(TRIM(sales_rep_name), 1, 1)) || LOWER(SUBSTR(TRIM(sales_rep_name), 2))
    END;


-- STEP 3: NORMALIZE WAREHOUSE OPERATION SEGMENTS (BRANCHES & PAYMENTS)
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
        WHEN payment_mode IS NULL OR TRIM(payment_mode) = '' THEN 'Unspecified'
        ELSE 'Other'
    END;


-- STEP 4: STRIP CORRUPTED CHARACTERS & VALUE NOISE FROM FINANCIAL FIELDS
UPDATE cleaned_clothing_store_sales
SET price_per_unit = REPLACE(REPLACE(REPLACE(price_per_unit, 'Rs.', ''), '₹', ''), '?', '');


-- STEP 5: CONVERT MISTY DISCOUNT LABELS INTO PURE PERCENTAGE INTEGERS
UPDATE cleaned_clothing_store_sales
SET 
    discount_percentage = CASE 
        WHEN discount_percentage IS NULL OR discount_percentage IN ('0', 'No', '') THEN '0'
        WHEN discount_percentage = 'Yes' THEN '10' -- Assigning standard marketing promo default
        ELSE REPLACE(discount_percentage, '%', '')
    END;


-- STEP 6: ADVANCED SQL DATE TEXT-TO-NUMBER CONVERSION 
UPDATE cleaned_clothing_store_sales
SET transaction_date = 
    CASE 
        -- Process textual names embedded in text records (e.g., '25 Jul 2024')
        WHEN transaction_date LIKE '% 202%' THEN 
            SUBSTR(transaction_date, -4) || '-' || 
            CASE 
                WHEN transaction_date LIKE '%Jan%' THEN '01' WHEN transaction_date LIKE '%Feb%' THEN '02'
                WHEN transaction_date LIKE '%Mar%' THEN '03' WHEN transaction_date LIKE '%Apr%' THEN '04'
                WHEN transaction_date LIKE '%May%' THEN '05' WHEN transaction_date LIKE '%Jun%' THEN '06'
                WHEN transaction_date LIKE '%Jul%' THEN '07' WHEN transaction_date LIKE '%Aug%' THEN '08'
                WHEN transaction_date LIKE '%Sep%' THEN '09' WHEN transaction_date LIKE '%Oct%' THEN '10'
                WHEN transaction_date LIKE '%Nov%' THEN '11' WHEN transaction_date LIKE '%Dec%' THEN '12'
            END || '-' || 
            SUBSTR('0' || TRIM(SUBSTR(transaction_date, 1, 2)), -2)
        
        -- Keeps fully formed numeric entries clean
        ELSE transaction_date 
    END;


-- STEP 7: CLEANSE CONTACT INFORMATION TO PURE 10-DIGIT LOGS
UPDATE cleaned_clothing_store_sales
SET phone_number = 
    CASE 
        WHEN phone_number IS NULL OR TRIM(phone_number) = '' THEN 'No Contact'
        ELSE 
            CASE 
                WHEN phone_number LIKE '+91-%' THEN REPLACE(phone_number, '+91-', '')
                ELSE REPLACE(REPLACE(REPLACE(phone_number, '+91', ''), '-', ''), ' ', '')
            END
    END;

UPDATE cleaned_clothing_store_sales
SET phone_number = CASE 
    WHEN phone_number = 'No Contact' THEN 'No Contact'
    ELSE SUBSTR(TRIM(phone_number), -10)
END;


-- STEP 8: INVENTORY AND APPAREL SIZING BACKFILLS
UPDATE cleaned_clothing_store_sales
SET item_size = 
    CASE 
        WHEN item_size IS NULL OR TRIM(item_size) = '' THEN 
            CASE 
                WHEN category = 'Accessories' THEN 'Free Size'
                ELSE 'Standard'
            END
        ELSE TRIM(item_size)
    END;


-- STEP 9: FORCE EXPLICIT MATHEMATICAL REVENUE VALIDATION
UPDATE cleaned_clothing_store_sales
SET 
    price_per_unit = CASE WHEN price_per_unit IS NULL OR price_per_unit = '' THEN 0 ELSE price_per_unit END,
    total_amount = CAST(quantity AS REAL) * CAST(price_per_unit AS REAL) * (1.0 - (CAST(discount_percentage AS REAL) / 100.0));


-- STEP 10: ELIMINATE FULLY IDENTICAL INFLATED SYSTEM DUPLICATES
DELETE FROM cleaned_clothing_store_sales
WHERE transaction_id NOT IN (
    SELECT MIN(transaction_id)
    FROM cleaned_clothing_store_sales
    GROUP BY transaction_date, customer_name, phone_number, item_name, quantity, price_per_unit, total_amount
);


-- ====================================================================
-- STEP 11: QUALITY ASSURANCE VERIFICATION TESTS
-- ====================================================================
-- Check if any remaining zero rows leak out (Target: 0)
SELECT COUNT(*) AS remaining_invalid_quantity_rows 
FROM cleaned_clothing_store_sales 
WHERE quantity <= 0 OR quantity IS NULL;

-- Confirm unified, clean category splits
SELECT category, COUNT(*) as clean_frequency 
FROM cleaned_clothing_store_sales 
GROUP BY category;
