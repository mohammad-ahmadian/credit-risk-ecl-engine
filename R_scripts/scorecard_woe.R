# ====================================================================
# IFRS 9 CREDIT SCORECARD: WOE BINNING & INFORMATION VALUE (R)
# ====================================================================

# 0. Read Environment Variables from .env File
if (file.exists(".env")) {
  readRenviron(".env")
}


suppressPackageStartupMessages({
  library(scorecard)
  library(DBI)
  library(RPostgres)
  library(dplyr)
})

cat("🔄 Connecting to PostgreSQL CreditRiskDB...\n")

# 1. Database Connection Parameters
db_host <- Sys.getenv("DB_HOST", "localhost")
db_port <- as.numeric(Sys.getenv("DB_PORT", 5432))
db_name <- Sys.getenv("DB_NAME", "CreditRiskDB")
db_user <- Sys.getenv("DB_USER", "postgres")
db_pass <- Sys.getenv("DB_PASSWORD", "admin123")

# Connect to PostgreSQL
con <- dbConnect(
  RPostgres::Postgres(),
  dbname = db_name,
  host = db_host,
  port = db_port,
  user = db_user,
  password = db_pass
)

# 2. Query Credit Data from Database
query <- "
  SELECT 
    b.borrower_code,
    b.age,
    b.employment_status,
    b.annual_income,
    b.debt_to_income_ratio,
    b.credit_score_bureau,
    l.loan_amount,
    l.interest_rate_pct,
    l.is_defaulted
  FROM fact_loans l
  JOIN dim_borrowers b ON l.borrower_id = b.borrower_id;
"

credit_df <- dbGetQuery(con, query)
cat(sprintf("✅ Loaded %d credit records from database.\n", nrow(credit_df)))

# 3. Information Value (IV) Calculation
# Target variable: is_defaulted (1 = Default, 0 = Non-Default)
iv_df <- iv(credit_df, y = "is_defaulted")

# Add Predictive Power Label
iv_df <- iv_df %>%
  mutate(
    predictive_power = case_when(
      info_value < 0.02 ~ "Not Predictive",
      info_value >= 0.02 & info_value < 0.10 ~ "Weak",
      info_value >= 0.10 & info_value < 0.30 ~ "Medium",
      info_value >= 0.30 & info_value <= 0.50 ~ "Strong",
      TRUE ~ "Suspiciously High"
    )
  )

cat("\n=======================================================\n")
cat("📊 CREDIT FEATURE INFORMATION VALUE (IV) RANKINGS\n")
cat("=======================================================\n")
print(iv_df %>% select(variable, info_value, predictive_power))
cat("=======================================================\n\n")

# 4. Save IV Rankings to PostgreSQL Table
cat("📥 Uploading Information Values to PostgreSQL...\n")

for (i in 1:nrow(iv_df)) {
  var_name <- iv_df$variable[i]
  iv_val <- iv_df$info_value[i]
  pred_power <- iv_df$predictive_power[i]
  
  upsert_sql <- sprintf("
    INSERT INTO feature_information_values (feature_name, information_value, predictive_power)
    VALUES ('%s', %f, '%s')
    ON CONFLICT (feature_name) DO UPDATE
    SET information_value = EXCLUDED.information_value,
        predictive_power = EXCLUDED.predictive_power;
  ", var_name, iv_val, pred_power)
  
  dbExecute(con, upsert_sql)
}

# 5. Optimal WoE Binning Transformation
cat("⚡ Performing Optimal Monotonic WoE Binning...\n")

# Option A: Tell woebin to skip ID columns
bins <- woebin(credit_df, y = "is_defaulted", var_skip = "borrower_code")

# Export WoE Binned Data (retains borrower_code in final output)
credit_woe <- woebin_ply(credit_df, bins)

# Write WoE dataset to CSV for Python ML modeling
write.csv(credit_woe, "data/credit_woe_transformed.csv", row.names = FALSE)

cat("🎉 WoE Transformation complete! Output saved to data/credit_woe_transformed.csv\n")

# Disconnect DB
dbDisconnect(con)