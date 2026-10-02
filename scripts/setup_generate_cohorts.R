project_root <- normalizePath(
  path = getwd(),
  mustWork = TRUE
)
database_input <- Sys.getenv(
  x = "DATABASE_PATH",
  unset = "database-1M_filtered.duckdb"
)
cohort_definition_input <- Sys.getenv(
  x = "COHORT_DEFINITION_DIR",
  unset = "cohorts"
)
project_cohort_map <- list(
  cohort_id = as.integer(c(1, 2, 3)),
  file_name = c("ace.json", "hydrochlorothiazide.json", "cough.json"),
  cohort_name = c("ACE/lisinopril", "Hydrochlorothiazide", "Cough")
)

database_path <- normalizePath(
  path = file.path(project_root, database_input),
  mustWork = FALSE
)

project_prefix <- paste0(project_root, "/")

cohort_definition_dir <- fs::path_norm(
  path = fs::path_abs(
    path = cohort_definition_input,
    start = project_root
  )
)

definition_files <- fs::path(
  cohort_definition_dir,
  project_cohort_map$file_name
)

# Read and translate every definition before connecting or mutating the CDM.
json_values <- character(length(project_cohort_map$cohort_id))
expression_values <- vector(
  mode = "list",
  length = length(project_cohort_map$cohort_id)
)
options_values <- vector(
  mode = "list",
  length = length(project_cohort_map$cohort_id)
)
sql_values <- character(length(project_cohort_map$cohort_id))

for (index in seq_len(length(project_cohort_map$cohort_id))) {
  json_values[[index]] <- readr::read_file(
    file = definition_files[[index]],
    locale = readr::locale(encoding = "UTF-8")
  )
  expression_values[[index]] <- CirceR::cohortExpressionFromJson(json_values[[index]])
  options_values[[index]] <- CirceR::createGenerateOptions(
    generateStats = TRUE
  )
  sql_values[[index]] <- CirceR::buildCohortQuery(
    expression = expression_values[[index]],
    options = options_values[[index]]
  )
}

definitions <- tibble::tibble(
  cohortId = project_cohort_map$cohort_id,
  cohortName = project_cohort_map$cohort_name,
  json = json_values,
  sql = sql_values
)

details <- DatabaseConnector::createConnectionDetails(
  dbms = "duckdb",
  server = database_path
)
connection <- DatabaseConnector::connect(
  connectionDetails = details
)
# available_tables <- DatabaseConnector::querySql(
#   connection = connection,
#   sql = stringr::str_c(
#     "select table_name from information_schema.tables ",
#     "where table_schema = 'main'"
#   )
# ) |>
#   dplyr::pull(table_name) |>
#   stringr::str_to_lower()

table_names <- CohortGenerator::getCohortTableNames(
  cohortTable = "cohort"
)

CohortGenerator::createCohortTables(
  connection = connection,
  cohortDatabaseSchema = "main",
  cohortTableNames = table_names,
  incremental = TRUE
)
DatabaseConnector::disconnect(connection)
