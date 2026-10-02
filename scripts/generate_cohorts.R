source("scripts/setup_generate_cohorts.R")

details <- DatabaseConnector::createConnectionDetails(
  dbms = "duckdb",
  server = database_path
)
connection <- DatabaseConnector::connect(
  connectionDetails = details
)
generation <- CohortGenerator::generateCohortSet(
  connection = connection,
  cdmDatabaseSchema = "main",
  cohortDatabaseSchema = "main",
  cohortTableNames = table_names,
  cohortDefinitionSet = definitions,
  stopOnError = TRUE,
  incremental = FALSE
)

counts <- CohortGenerator::getCohortCounts(
  connection = connection,
  cohortDatabaseSchema = "main"
) |>
  dplyr::rename(
    cohort_id = cohortId,
    cohort_entries = cohortEntries,
    cohort_subjects = cohortSubjects
  ) |>
  dplyr::mutate(
    cohort_id = as.integer(cohort_id),
    cohort_entries = as.integer(cohort_entries),
    cohort_subjects = as.integer(cohort_subjects)
  ) |>
  dplyr::filter(cohort_id %in% c(1L, 2L, 3L)) |>
  dplyr::arrange(cohort_id)

print(counts)
