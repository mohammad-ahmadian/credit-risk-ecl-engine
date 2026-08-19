import sys
import os

# Force Python to add the root project directory to its path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import pytest
import numpy as np
import pandas as pd
from sqlalchemy import text
from src.database.db_connection import get_db_engine
from src.models.pd_model import ProbabilityOfDefaultEngine

def test_database_connection():
    """Test 1: Verify PostgreSQL CreditRiskDB connection works."""
    engine = get_db_engine()
    with engine.connect() as conn:
        result = conn.execute(text("SELECT 1;")).scalar()
    assert result == 1, "Database connection test failed."

def test_loan_portfolio_non_empty():
    """Test 2: Verify fact_loans table contains populated records."""
    engine = get_db_engine()
    with engine.connect() as conn:
        count = conn.execute(text("SELECT COUNT(*) FROM fact_loans;")).scalar()
    assert count >= 2000, "Loan portfolio table has insufficient records."

def test_pd_predictions_bounds():
    """Test 3: Verify Probability of Default predictions are bounded between 0 and 1."""
    engine = get_db_engine()
    with engine.connect() as conn:
        df = pd.read_sql("SELECT pd_12m, pd_lifetime FROM pd_model_predictions;", conn)
    assert (df['pd_12m'] >= 0.0).all() and (df['pd_12m'] <= 1.0).all(), "PD 12M out of valid range [0, 1]."
    assert (df['pd_lifetime'] >= 0.0).all() and (df['pd_lifetime'] <= 1.0).all(), "PD Lifetime out of valid range [0, 1]."

def test_scorecard_points_bounds():
    """Test 4: Verify Credit Scorecard points are bounded between 300 and 850."""
    engine = get_db_engine()
    with engine.connect() as conn:
        scores = pd.read_sql("SELECT scorecard_points FROM pd_model_predictions;", conn)['scorecard_points']
    assert (scores >= 300).all() and (scores <= 850).all(), "Scorecard points out of standard range [300, 850]."

def test_excel_summary_file_exists():
    """Test 5: Verify that the auditable Excel summary workbook was generated."""
    excel_path = os.path.join("reports", "ifrs9_ecl_summary_model.xlsx")
    assert os.path.exists(excel_path), f"Excel summary report missing at {excel_path}"