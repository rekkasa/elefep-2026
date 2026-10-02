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

on.exit(DatabaseConnector::disconnect(connection))
