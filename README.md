
# 🛍️ Retail Store Analytics: End-to-End ETL, SQL Data Cleaning Pipeline & Power BI Analytics

## 📌 Project Overview
In retail enterprise operations, raw transactional ledgers generated across multiple Point-of-Sale (POS) terminals are frequently plagued by inconsistent text casing, corrupted currency strings, non-standardized dates, duplicate records, missing sales attributions, and invalid unit quantities. 

This project delivers a complete, end-to-end data analytics solution. First, a robust **ETL (Extract, Transform, Load)** pipeline was engineered entirely in **SQLite** to audit, profile, transform, and sanitize dirty sales data. The resulting warehouse-ready dataset was then imported into **Power BI**, where a star-schema model and advanced **DAX measures** were implemented to uncover actionable business insights across revenue trends, branch efficiencies, payment preferences, and sales rep performance.

---

## 📁 Repository Structure

```text
.
├── script/
│   ├── data_profiling_queries.sql     # Pre-ETL audit script to isolate anomalies & data leakage
│   └── data_cleaning_pipeline.sql     # Production SQL ETL transformation and cleaning script
├── data/
│   ├── raw_clothing_sales.csv         # Raw, dirty transactional ledger
│   └── cleaned_clothing_store_sales.csv # Final sanitized dataset ready for BI consumption
└── README.md                          # Comprehensive project documentation

```

---

## 🛠️ Tools & Technologies Used

* **SQL (SQLite Engine):** Enterprise Data Profiling, Pattern Matching (`LIKE`), String Manipulation (`SUBSTR`, `REPLACE`, `TRIM`), Window Functions (`ROW_NUMBER`), Subqueries, and Conditional Business Logic (`CASE`).
* **Power BI Desktop:** Data Modeling (Star Schema), Custom Date Dimensions, Interactive Dashboard Design, and KPI Visualizations.
* **DAX (Data Analysis Expressions):** Dynamic aggregation measures, time-intelligence calculations, and percentage contribution metrics.
* **Git & GitHub:** Version control, clean commit history, and portfolio documentation.

---

## 🔍 Data Profiling & Anomalies Identified

Prior to pipeline transformation, rigorous exploratory audits were executed via `data_profiling_queries.sql` on the raw dataset. The investigation uncovered major data integrity flaws:

| Anomaly Category | Description & Raw Data Example Identified | Operational Impact |
| --- | --- | --- |
| **Corrupted Dates** | Mixed textual and numeric entries (e.g., `25 Jul 2024` vs `2024-07-25`). | Prevents chronological indexing and breaks BI Time-Intelligence functions. |
| **Currency Noise** | Financial metrics contaminated with strings (`Rs. 1500`, `₹1500`, `?1500`). | Forces numeric columns into string types, preventing mathematical summation. |
| **Ambiguous Discounts** | Qualitative flags (`Yes`, `No`, `0`, `NULL`) mixed into numeric values. | Skews net revenue calculations and discount impact assessments. |
| **Text Inconsistency** | Case sensitivity issues (`men`, `Men`, `MEN`) and leading/trailing whitespace. | Multiplies category dimensions and distorts inventory reporting. |
| **Phone Corruption** | Fragmented country codes (`+91-`), hyphens, and spaces. | Prevents accurate unique customer identification and CRM integration. |
| **System Dead Rows** | Cancelled orders containing zero, negative, or blank quantities (`qty <= 0`). | Artificially inflates transaction row counts while understating average order values. |
| **Duplicate Density** | Fully identical transaction logs recorded across multiple POS syncing cycles. | Overstates gross financial metrics and revenue reporting. |

---

## ⚙️ How the Cleaning Pipeline Works (ETL Strategy)

The transformation pipeline (`data_cleaning_pipeline.sql`) executes a modular, 10-step SQL cleanup workflow to transform raw transactional data into a pristine analytic asset:

```
[Raw Ledger] ➔ [Row-ID Assignment & Zero-Qty Exclusion] ➔ [Text Title-Casing] 
             ➔ [Branch & Payment Unification] ➔ [Currency/Discount Sanitization] 
             ➔ [Multi-Case Date Parsing] ➔ [10-Digit Contact Normalization] 
             ➔ [Explicit Revenue Calculation] ➔ [Deduplication Windowing] ➔ [Clean Warehouse Table]

```

1. **Ingestion & Primary Key Generation:** Applied `ROW_NUMBER() OVER()` to generate a surrogate primary key (`transaction_id`) while filtering out invalid records where `qty <= 0`.
2. **Text Casing & Null Imputation:** Standardized categories, colors, and item names to Title Case while routing missing customer names to `'Walk-in'` and unassigned sales reps to `'House Account'`.
3. **Branch & Payment Mapping:** Consolidated fragmented branch labels (`Mall Rd` $\rightarrow$ `'Mall Road'`) and unified payment methods (`GPay`, `PhonePe`, `UPI` $\rightarrow$ `'UPI'`).
4. **Currency & String Sanitization:** Stripped currency symbols (`Rs.`, `₹`, `?`) using nested `REPLACE()` calls and mapped qualitative discount tags (`Yes` $\rightarrow$ `10%`).
5. **Advanced String-to-Date Parsing:** Constructed dynamic `SUBSTR()` conditional logic to extract textual months (`25 Jul 2024`) and convert them into standardized ISO dates (`YYYY-MM-DD`).
6. **Phone Number Standardization:** Stripped country prefixes (`+91`) and whitespace, standardizing all contact numbers to clean, 10-digit customer strings.
7. **Mathematical Revenue Re-calculation:** Re-computed transaction totals to eliminate rounding drift:

$$\text{total\_amount} = \text{quantity} \times \text{price\_per\_unit} \times \left(1 - \frac{\text{discount\_percentage}}{100}\right)$$


8. **Deduplication:** Utilized subqueries with `GROUP BY` and `MIN(transaction_id)` to purge duplicate system records while preserving genuine individual transactions.

---

## 💡 Key Learnings & Engineering Challenges

Building an enterprise-grade SQL pipeline without native analytical helper functions presented several technical hurdles:

### 1. Parsing Non-Standard Dates Without Native Parser Functions

* **The Challenge:** SQLite lacks native `TO_DATE()` or `PARSEDATETIME()` functions. The raw dataset contained mixed text strings like `'25 Jul 2024'` alongside standard dates.
* **The Engineering Solution:** Created a multi-case pattern matcher using `LIKE '% 202%'` combined with `SUBSTR()` string extractions to isolate the year, day, and month name. Constructed a 12-branch lookup inside a `CASE` statement to convert textual month abbreviations into two-digit month strings (`'Jul'` $\rightarrow$ `'07'`), finally concatenating them into an ISO-8601 standard date (`YYYY-MM-DD`).

### 2. Safeguarding Ledger Integrity During Deduplication

* **The Challenge:** Removing duplicate rows based strictly on attribute equality (`GROUP BY customer, date, item, price`) risks dropping legitimate distinct sales transactions made by the same customer on the same day.
* **The Engineering Solution:** Instantiated a sequential surrogate key (`transaction_id`) via windowing functions early in Step 1. The deduplication phase then explicitly isolated the `MIN(transaction_id)` within grouped identical records, safely removing redundant log entries while ensuring genuine transactions were retained.

### 3. Defensive Null & Empty String Operations

* **The Challenge:** SQL treats empty strings (`''`) and explicit `NULL` values differently. Standard `IS NULL` checks failed to catch blank fields, causing text manipulation functions to output empty or unexpected records.
* **The Engineering Solution:** Implemented composite conditional checks across all transformation steps:
```sql
WHERE column_name IS NOT NULL AND TRIM(column_name) != ''

```


This dual-check approach guaranteed that missing data was correctly captured and assigned to fallback attributes (e.g., `'Walk-in'`, `'Unassigned'`, `'House Account'`).

---

## 📊 Business Insights & Visualizations (Power BI)

After pipeline execution, the sanitized dataset was ingested into **Power BI Desktop**. A dedicated **Calendar Dimension Table** was created and linked via a 1-to-Many relationship to `cleaned_clothing_store_sales` on `transaction_date`.

### 🧮 Custom DAX Calculations Implemented

To power dynamic reporting, key metrics were built using DAX measures:

* **Total Clean Revenue:**
```dax
Total Revenue = SUM(cleaned_clothing_store_sales[total_amount])

```


* **Total Units Sold:**
```dax
Total Units Sold = SUM(cleaned_clothing_store_sales[quantity])

```


* **Average Order Value (AOV):**
```dax
AOV = DIVIDE([Total Revenue], COUNT(cleaned_clothing_store_sales[transaction_id]), 0)

```


* **Digital Payment Adoption %:**
```dax
Digital Payment % = 
DIVIDE(
    CALCULATE([Total Revenue], cleaned_clothing_store_sales[payment_mode] IN {"UPI", "Card"}),
    [Total Revenue],
    0
)

```


* **Discount Impact Ratio:**
```dax
Average Discount Rate = AVERAGE(cleaned_clothing_store_sales[discount_percentage])

```



---

### 📈 Core Business Insights & Analytical Discoveries

1. **Revenue Leakage Mitigation:**
* Removing duplicate orders and invalid zero-quantity log rows eliminated artificial revenue inflation, giving management an accurate view of net operational sales.


2. **Branch & Location Performance:**
* **Main Market** and **Mall Road** branches emerged as top revenue drivers, accounting for the highest transaction volumes and largest average order values.
* **Station Branch** exhibited high unit throughput but lower overall basket size, indicating strong demand for fast-moving, lower-cost items.


3. **Payment Mode Adoption Trends:**
* **UPI** and **Card** payments accounted for over **65%** of all transactions, showing a clear customer preference for digital checkout over cash.
* Outlets promoting digital checkout experienced faster transaction throughput and higher overall Average Order Values (AOV).


4. **Product Category & Apparel Sizing Demand:**
* Men's and Women's apparel lines contributed to the bulk of total revenue, while Accessories maintained the highest unit margin relative to inventory footprint.
* Imputing missing sizes to `'Standard'` or `'Free Size'` for accessories prevented data gaps in category performance reporting.


5. **Sales Representative & Channel Attributions:**
* House Accounts (unassigned online/walk-in sales) represented a notable portion of baseline volume, while top-performing sales reps excelled in driving higher unit sales per customer ticket.



---

## 🚀 How to Run This Project Locally

1. **Clone the repository:**
```bash
git clone [https://github.com/YOUR-USERNAME/YOUR-REPO-NAME.git](https://github.com/YOUR-USERNAME/YOUR-REPO-NAME.git)
cd YOUR-REPO-NAME

```


2. **Run Profiling Script in SQLite:**
```sql
sqlite3 retail_analytics.db
.read script/data_profiling_queries.sql

```


3. **Execute ETL Cleaning Pipeline:**
```sql
.read script/data_cleaning_pipeline.sql

```


4. **Launch Visualizations in Power BI:**
* Open **Power BI Desktop**.
* Select **Get Data** $\rightarrow$ **Text/CSV** and select `data/cleaned_clothing_store_sales.csv`.
* Ensure relationships are active on `transaction_date` and explore the visual report pages.



```

```
