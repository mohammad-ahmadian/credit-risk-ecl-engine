-- ====================================================================
-- SQL REPORTING VIEWS FOR IFRS 9 CREDIT RISK DASHBOARD
-- ====================================================================

-- View 1: Complete Credit Portfolio Overview (Loan + Borrower + PD + ECL)
CREATE OR REPLACE VIEW vw_credit_portfolio_overview AS
SELECT 
    l.loan_id,
    l.loan_code,
    b.borrower_code,
    b.age,
    b.employment_status,
    b.annual_income,
    b.debt_to_income_ratio,
    b.credit_score_bureau,
    l.loan_amount,
    l.interest_rate_pct,
    l.term_months,
    l.collateral_value,
    l.current_balance AS ead,
    l.days_past_due,
    l.is_defaulted,
    p.pd_12m,
    p.pd_lifetime,
    p.scorecard_points,
    e.ifrs9_stage,
    e.lgd,
    e.ecl_amount,
    CASE 
        WHEN e.ifrs9_stage = 1 THEN 'Stage 1 (Performing)'
        WHEN e.ifrs9_stage = 2 THEN 'Stage 2 (SICR)'
        WHEN e.ifrs9_stage = 3 THEN 'Stage 3 (Defaulted)'
    END AS ifrs9_stage_name
FROM fact_loans l
JOIN dim_borrowers b ON l.borrower_id = b.borrower_id
LEFT JOIN pd_model_predictions p ON b.borrower_code = p.borrower_code
LEFT JOIN fact_ecl_impairment e ON l.loan_id = e.loan_id;

-- View 2: IFRS 9 Staging & Provisioning Executive Summary
CREATE OR REPLACE VIEW vw_ifrs9_ecl_summary AS
SELECT 
    e.ifrs9_stage,
    CASE 
        WHEN e.ifrs9_stage = 1 THEN 'Stage 1 (Performing)'
        WHEN e.ifrs9_stage = 2 THEN 'Stage 2 (SICR)'
        WHEN e.ifrs9_stage = 3 THEN 'Stage 3 (Defaulted)'
    END AS ifrs9_stage_name,
    COUNT(e.ecl_id) AS loan_count,
    SUM(e.ead) AS total_ead,
    SUM(e.ecl_amount) AS total_ecl,
    ROUND(AVG(e.pd_12m)::numeric, 6) AS avg_pd_12m,
    ROUND(AVG(e.lgd)::numeric, 4) AS avg_lgd,
    ROUND((SUM(e.ecl_amount) / SUM(e.ead) * 100)::numeric, 4) AS coverage_ratio_pct
FROM fact_ecl_impairment e
GROUP BY e.ifrs9_stage
ORDER BY e.ifrs9_stage ASC;

-- View 3: Credit Scorecard Points Banding Distribution
CREATE OR REPLACE VIEW vw_scorecard_distribution AS
SELECT 
    CASE 
        WHEN p.scorecard_points < 500 THEN '1. Poor (< 500)'
        WHEN p.scorecard_points BETWEEN 500 AND 599 THEN '2. Fair (500-599)'
        WHEN p.scorecard_points BETWEEN 600 AND 699 THEN '3. Good (600-699)'
        ELSE '4. Excellent (700+)'
    END AS score_band,
    COUNT(p.pred_id) AS borrower_count,
    ROUND(AVG(p.pd_12m)::numeric * 100, 2) AS avg_pd_12m_pct,
    ROUND(AVG(p.scorecard_points)::numeric, 0) AS avg_scorecard_points
FROM pd_model_predictions p
GROUP BY score_band
ORDER BY score_band ASC;

-- View 4: Top 50 Impaired Credit Exposures
CREATE OR REPLACE VIEW vw_top_impaired_loans AS
SELECT 
    l.loan_code,
    b.borrower_code,
    b.employment_status,
    e.ifrs9_stage,
    l.days_past_due,
    p.scorecard_points,
    e.ead,
    ROUND((e.pd_12m * 100)::numeric, 2) AS pd_12m_pct,
    ROUND((e.lgd * 100)::numeric, 2) AS lgd_pct,
    e.ecl_amount
FROM fact_ecl_impairment e
JOIN fact_loans l ON e.loan_id = l.loan_id
JOIN dim_borrowers b ON l.borrower_id = b.borrower_id
LEFT JOIN pd_model_predictions p ON b.borrower_code = p.borrower_code
WHERE e.ifrs9_stage > 1
ORDER BY e.ecl_amount DESC
LIMIT 50;

-- View 5: Scorecard Feature Information Value (IV) Rankings
CREATE OR REPLACE VIEW vw_feature_iv_rankings AS
SELECT 
    iv_id,
    feature_name,
    information_value,
    predictive_power,
    ROUND((information_value)::numeric, 4) AS iv_formatted
FROM feature_information_values
ORDER BY information_value DESC;