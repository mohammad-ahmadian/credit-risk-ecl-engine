-- 1. Dimension Table: Borrower Demographics & Financials
CREATE TABLE IF NOT EXISTS dim_borrowers (
    borrower_id SERIAL PRIMARY KEY,
    borrower_code VARCHAR(20) UNIQUE NOT NULL,
    age INT NOT NULL,
    employment_status VARCHAR(50) NOT NULL,
    annual_income NUMERIC(12, 2) NOT NULL,
    debt_to_income_ratio NUMERIC(5, 4) NOT NULL,
    credit_score_bureau INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Fact Table: Loan Portfolio Details
CREATE TABLE IF NOT EXISTS fact_loans (
    loan_id SERIAL PRIMARY KEY,
    loan_code VARCHAR(20) UNIQUE NOT NULL,
    borrower_id INT REFERENCES dim_borrowers(borrower_id) ON DELETE CASCADE,
    origination_date DATE NOT NULL,
    loan_amount NUMERIC(12, 2) NOT NULL,
    interest_rate_pct NUMERIC(6, 4) NOT NULL,
    term_months INT NOT NULL,
    collateral_value NUMERIC(12, 2) NOT NULL,
    current_balance NUMERIC(12, 2) NOT NULL,
    days_past_due INT NOT NULL DEFAULT 0,
    is_defaulted INT NOT NULL DEFAULT 0, -- 1 if defaulted (>90 DPD), 0 otherwise
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Dimension Table: Macroeconomic Credit Indicators
CREATE TABLE IF NOT EXISTS dim_macro_credit (
    macro_id SERIAL PRIMARY KEY,
    record_date DATE UNIQUE NOT NULL,
    gdp_growth_pct NUMERIC(6, 4) NOT NULL,
    unemployment_rate_pct NUMERIC(6, 4) NOT NULL,
    ecb_refi_rate_pct NUMERIC(6, 4) NOT NULL
);

-- 4. Fact Table: IFRS 9 ECL Impairment Results
CREATE TABLE IF NOT EXISTS fact_ecl_impairment (
    ecl_id SERIAL PRIMARY KEY,
    loan_id INT REFERENCES fact_loans(loan_id) ON DELETE CASCADE,
    calc_date DATE NOT NULL,
    ifrs9_stage INT NOT NULL, -- 1: Performing, 2: SICR, 3: Defaulted
    pd_12m NUMERIC(8, 6) NOT NULL,
    pd_lifetime NUMERIC(8, 6) NOT NULL,
    lgd NUMERIC(6, 4) NOT NULL,
    ead NUMERIC(12, 2) NOT NULL,
    ecl_amount NUMERIC(12, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_loan_ecl_date UNIQUE (loan_id, calc_date)
);

-- Indexes for Fast Query Performance
CREATE INDEX IF NOT EXISTS idx_loans_borrower ON fact_loans(borrower_id);
CREATE INDEX IF NOT EXISTS idx_ecl_loan_date ON fact_ecl_impairment(loan_id, calc_date);




-- -------------------------------------


-- Create Table for Storing Feature Information Values (IV)
CREATE TABLE IF NOT EXISTS feature_information_values (
    iv_id SERIAL PRIMARY KEY,
    feature_name VARCHAR(100) UNIQUE NOT NULL,
    information_value NUMERIC(8, 6) NOT NULL,
    predictive_power VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);





-- -------------------------------------


-- Table for Storing Probability of Default (PD) Predictions & Credit Scores
CREATE TABLE IF NOT EXISTS pd_model_predictions (
    pred_id SERIAL PRIMARY KEY,
    borrower_code VARCHAR(20) UNIQUE NOT NULL,
    pd_12m NUMERIC(8, 6) NOT NULL,
    pd_lifetime NUMERIC(8, 6) NOT NULL,
    scorecard_points INT NOT NULL,
    model_type VARCHAR(50) NOT NULL,
    calc_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);