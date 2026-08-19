import time
import subprocess
import logging
import os
from datetime import datetime

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler()
    ]
)

from src.data.generate_credit_data import generate_and_load_credit_data
from src.models.pd_model import ProbabilityOfDefaultEngine
from src.models.ifrs9_ecl_engine import IFRS9ExpectedCreditLossEngine
from src.database.create_views import deploy_credit_sql_views

def run_full_credit_pipeline():
    """
    Master Orchestrator: Executes the complete End-to-End IFRS 9 Credit Risk Pipeline across R, Python, and SQL.
    """
    start_time = time.time()
    logging.info("=================================================================")
    logging.info("🚀 STARTING END-TO-END IFRS 9 CREDIT RISK & ECL PIPELINE")
    logging.info("=================================================================")

    try:
        # Stage 1: Generate Loan Portfolio Data in PostgreSQL
        logging.info("STAGE 1/5: Generating Loan Portfolio Data in PostgreSQL...")
        generate_and_load_credit_data(num_records=2500, seed=42)

        # Stage 2: Execute R WoE Binning & Information Value Script
        logging.info("STAGE 2/5: Executing R WoE Scorecard Feature Engineering Script...")
        r_script_path = os.path.join("R_scripts", "scorecard_woe.R")
        
        result = subprocess.run(f"Rscript {r_script_path}", capture_output=True, text=True, shell=True)
        
        if result.returncode != 0:
            logging.warning(f"⚠️ Rscript execution output/note: {result.stderr}")
            if not os.path.exists("data/credit_woe_transformed.csv"):
                raise RuntimeError("R WoE script execution failed and credit_woe_transformed.csv missing.")
            else:
                logging.info("✅ Using existing credit_woe_transformed.csv dataset.")
        else:
            logging.info("✅ R WoE Scorecard script executed successfully.")

        # Stage 3: Train Python PD Models (Logistic Regression & XGBoost)
        logging.info("STAGE 3/5: Training Python PD Models & Scorecard Calibration...")
        pd_engine = ProbabilityOfDefaultEngine()
        pd_engine.train_and_evaluate_models()

        # Stage 4: Compute IFRS 9 3-Stage ECL & Export Executive Excel Workbook
        logging.info("STAGE 4/5: Computing IFRS 9 ECL Provisions & Generating Excel Workbook...")
        ecl_engine = IFRS9ExpectedCreditLossEngine(collateral_haircut=0.20)
        ecl_engine.calculate_ifrs9_ecl()

        # Stage 5: Deploy SQL Credit Reporting Views
        logging.info("STAGE 5/5: Deploying SQL Credit Reporting Views for Power BI...")
        deploy_credit_sql_views()

        elapsed_time = time.time() - start_time
        logging.info("=================================================================")
        logging.info(f"🎉 CREDIT PIPELINE COMPLETED SUCCESSFULLY IN {elapsed_time:.2f} SECONDS!")
        logging.info("=================================================================")

    except Exception as e:
        logging.error(f"❌ CREDIT PIPELINE FAILED WITH ERROR: {e}", exc_info=True)
        raise e

if __name__ == "__main__":
    run_full_credit_pipeline()