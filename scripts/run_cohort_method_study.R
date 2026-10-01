# ======================= SETUP =============================

project_root <- normalizePath(path = getwd(), mustWork = TRUE)
database_path <- Sys.getenv(
  x = "DATABASE_PATH",
  unset = "database-1M_filtered.duckdb"
)
results_dir <- Sys.getenv(x = "RESULTS_DIR", unset = "results")
target_id <- 1
comparator_id <- 2
outcome_id <- 3

cdm_schema <- "main"
cohort_table <- "cohort"

database_full_path <- normalizePath(
  path = file.path(project_root, database_path),
  mustWork = FALSE
)
results_full_path <- normalizePath(
  path = file.path(project_root, results_dir),
  mustWork = FALSE
)
project_prefix <- paste0(project_root, "/")

# ====================================================

details <- DatabaseConnector::createConnectionDetails(
  dbms = "duckdb",
  server = database_full_path
)
connection <- DatabaseConnector::connect(connectionDetails = details)
columns <- DatabaseConnector::querySql(
  connection = connection,
  sql = stringr::str_c(
    "select column_name from information_schema.columns where ",
    "table_schema = 'main' and table_name = 'cohort'"
  )
) |>
  dplyr::pull(column_name) |>
  stringr::str_to_lower()

results_dir <- fs::path(
  fs::path_dir(path = results_full_path),
  stringr::str_c(
    fs::path_file(path = results_full_path),
    "_",
    as.integer(Sys.time())
  )
)
fs::dir_create(path = results_dir, recurse = TRUE)

covariate_settings <- FeatureExtraction::createDefaultCovariateSettings(
  excludedCovariateConceptIds = c(1308216, 974166),
  addDescendantsToExclude = TRUE
)
cohort_method_data <- CohortMethod::getDbCohortMethodData(
  connectionDetails = details,
  cdmDatabaseSchema = cdm_schema,
  exposureDatabaseSchema = cdm_schema,
  outcomeDatabaseSchema = cdm_schema,
  exposureTable = cohort_table,
  outcomeTable = cohort_table,
  targetId = target_id,
  comparatorId = comparator_id,
  outcomeIds = outcome_id,
  getDbCohortMethodDataArgs =
    CohortMethod::createGetDbCohortMethodDataArgs(
      covariateSettings = covariate_settings,
      removeDuplicateSubjects = "keep first, truncate to second",
      firstExposureOnly = TRUE,
      washoutPeriod = 365,
      restrictToCommonPeriod = TRUE,
      nestingCohortId = NULL
    )
)
# CohortMethod::saveCohortMethodData(
#   cohortMethodData = cohort_method_data,
#   file = fs::path(results_dir, "cohort_method_data.zip")
# )

population <- CohortMethod::createStudyPopulation(
  cohortMethodData = cohort_method_data,
  outcomeId = outcome_id,
  createStudyPopulationArgs = CohortMethod::createCreateStudyPopulationArgs(
    removeSubjectsWithPriorOutcome = TRUE,
    priorOutcomeLookback = 365,
    minDaysAtRisk = 1,
    riskWindowStart = 0,
    startAnchor = "cohort start",
    riskWindowEnd = 90,
    endAnchor = "cohort end"
  )
)

ps <- CohortMethod::createPs(
  cohortMethodData = cohort_method_data,
  population = population,
  createPsArgs = CohortMethod::createCreatePsArgs()
)

matched <- CohortMethod::matchOnPs(
  population = ps,
  matchOnPsArgs = CohortMethod::createMatchOnPsArgs(
    maxRatio = 1,
    caliper = 0.2
  )
)

# stratified <- CohortMethod::stratifyByPs(
#   population = ps,
#   stratifyByPsArgs = CohortMethod::createStratifyByPsArgs()
# )

matched_arm_sizes <- matched |>
  dplyr::count(treatment, name = "n")

balance <- CohortMethod::computeCovariateBalance(
  population = matched,
  cohortMethodData = cohort_method_data
)

mdrr <- CohortMethod::computeMdrr(
  population = matched,
  alpha = 0.05,
  power = 0.8,
  twoSided = TRUE,
  modelType = "logistic"
)

fit <- CohortMethod::fitOutcomeModel(
  population = matched,
  fitOutcomeModelArgs = CohortMethod::createFitOutcomeModelArgs(
    modelType = "logistic"
  )
)
estimate <- CohortMethod::getOutcomeModelEstimates(fit = fit) |>
  tibble::as_tibble() |>
  dplyr::filter(dplyr::row_number() == 1L) |>
  dplyr::transmute(
    target_id = target_id,
    comparator_id = comparator_id,
    outcome_id = outcome_id,
    hazard_ratio = as.numeric(exp(coefficient)),
    ci_95_lower = as.numeric(exp(coefficient - 1.96 * se)),
    ci_95_upper = as.numeric(exp(coefficient + 1.96 * se)),
    log_rr = as.numeric(coefficient),
    se_log_rr = as.numeric(se)
  )
if (any(!is.finite(unlist(estimate))) ||
      any(estimate$hazard_ratio <= 0)) {
  stop("The matched Cox model did not produce a finite positive estimate.")
}
readr::write_csv(
  x = estimate,
  file = fs::path(staging_dir, "effect_estimate.csv"),
  na = ""
)

