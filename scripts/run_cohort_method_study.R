source("scripts/setup_run_cohort_method_study.R")

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
    removeSubjectsWithPriorOutcome = FALSE,
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

fit
