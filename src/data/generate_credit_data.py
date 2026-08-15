import sys
import os

# Ensure root folder is in python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../')))

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from sqlalchemy import text
from src.database.db_connection import get_db_engine

def create_tables_if_not_exist(engine):
    """Reads schema_credit.sql and creates tables if they do not exist."""
    schema_path = os.path.join(os.path.dirname(__file__), '../database/schema_credit.sql')
    if os.path.exists(schema_path):
        print("🛠️ Checking/Creating database tables from schema_credit.sql...")
        with open(schema_path, 'r') as f:
            schema_sql = f.read()
        with engine.begin() as conn:
            conn.execute(text(schema_sql))
        print("✅ Database tables are ready.")
    else:
        print(f"⚠️ Warning: Could not find schema file at {schema_path}")

def generate_and_load_credit_data(num_records=2500, seed=42):
    np.random.seed(seed)
    engine = get_db_engine()

    # Create tables first
    create_tables_if_not_exist(engine)

    print(f"🔄 Generating realistic credit portfolio ({num_records} loans)...")

    # 1. Generate Borrowers
    borrower_codes = [f"BORR_{i:05d}" for i in range(1, num_records + 1)]
    ages = np.random.randint(21, 68, size=num_records)
    emp_statuses = np.random.choice(['Employed', 'Self-Employed', 'Civil Servant', 'Unemployed'], size=num_records, p=[0.65, 0.18, 0.12, 0.05])
    incomes = np.round(np.random.lognormal(mean=10.6, sigma=0.5, size=num_records), 2)  # Avg ~45k EUR
    dti_ratios = np.round(np.random.uniform(0.10, 0.65, size=num_records), 4)
    bureau_scores = np.random.randint(450, 850, size=num_records)

    borrowers_df = pd.DataFrame({
        "borrower_code": borrower_codes,
        "age": ages,
        "employment_status": emp_statuses,
        "annual_income": incomes,
        "debt_to_income_ratio": dti_ratios,
        "credit_score_bureau": bureau_scores
    })

    # Save borrowers to DB
    with engine.begin() as conn:
        borrowers_df.to_sql("temp_borrowers", conn, if_exists="replace", index=False)
        conn.execute(text("""
            INSERT INTO dim_borrowers (borrower_code, age, employment_status, annual_income, debt_to_income_ratio, credit_score_bureau)
            SELECT borrower_code, age, employment_status, annual_income, debt_to_income_ratio, credit_score_bureau
            FROM temp_borrowers
            ON CONFLICT (borrower_code) DO NOTHING;
            DROP TABLE temp_borrowers;
        """))

    # Fetch Borrower IDs
    with engine.connect() as conn:
        b_map = pd.read_sql("SELECT borrower_id, borrower_code FROM dim_borrowers", conn)
    
    # 2. Generate Loans
    loan_codes = [f"LOAN_{i:05d}" for i in range(1, num_records + 1)]
    start_date = datetime(2021, 1, 1)
    origination_dates = [start_date + timedelta(days=int(np.random.randint(0, 1000))) for _ in range(num_records)]
    loan_amounts = np.round(np.random.uniform(5000, 150000, size=num_records), 2)
    interest_rates = np.round(np.random.uniform(0.025, 0.125, size=num_records), 4)
    terms = np.random.choice([24, 36, 48, 60, 120], size=num_records)
    collaterals = np.round(loan_amounts * np.random.uniform(0.20, 1.20, size=num_records), 2)
    current_balances = np.round(loan_amounts * np.random.uniform(0.15, 0.95, size=num_records), 2)

    # Correlate Days Past Due (DPD) with credit score
    dpd = []
    for score in bureau_scores:
        if score < 550:
            dpd.append(np.random.choice([0, 15, 45, 95, 120], p=[0.30, 0.25, 0.20, 0.15, 0.10]))
        elif score < 680:
            dpd.append(np.random.choice([0, 15, 45, 95], p=[0.70, 0.18, 0.08, 0.04]))
        else:
            dpd.append(np.random.choice([0, 15], p=[0.96, 0.04]))

    is_defaulted = [1 if d >= 90 else 0 for d in dpd]

    loans_df = pd.DataFrame({
        "loan_code": loan_codes,
        "borrower_id": b_map['borrower_id'].values,
        "origination_date": origination_dates,
        "loan_amount": loan_amounts,
        "interest_rate_pct": interest_rates,
        "term_months": terms,
        "collateral_value": collaterals,
        "current_balance": current_balances,
        "days_past_due": dpd,
        "is_defaulted": is_defaulted
    })

    with engine.begin() as conn:
        loans_df.to_sql("temp_loans", conn, if_exists="replace", index=False)
        conn.execute(text("""
            INSERT INTO fact_loans (loan_code, borrower_id, origination_date, loan_amount, interest_rate_pct, term_months, collateral_value, current_balance, days_past_due, is_defaulted)
            SELECT loan_code, borrower_id, origination_date, loan_amount, interest_rate_pct, term_months, collateral_value, current_balance, days_past_due, is_defaulted
            FROM temp_loans
            ON CONFLICT (loan_code) DO NOTHING;
            DROP TABLE temp_loans;
        """))

    print("🎉 Credit portfolio data populated in PostgreSQL successfully!")

if __name__ == "__main__":
    generate_and_load_credit_data()