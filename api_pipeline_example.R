# AUTOMATED SCOPING LITERATURE REVIEW PIPELINE

# Load pipeline functions
source("R/pipeline_functions.R")

#### 1. API Credentials Setup ####
if (Sys.getenv("OPENALEX_KEY") != "") {
  options(openalexR.apikey = Sys.getenv("OPENALEX_KEY"))
}

if (Sys.getenv("ELSEVIER_SCOPUS_KEY") != "") {
  set_api_key(Sys.getenv("ELSEVIER_SCOPUS_KEY"))
}

options(openalexR.mailto = "josh.tyler@bristol.ac.uk")

#### 2. Shared Parameters ####
GEO_TERMS <- c(
  "Africa",
  "Sub-Saharan Africa",
  "West Africa",
  "East Africa",
  "Southern Africa",
  "Central Africa"
)
START_YEAR          <- 2020
MAX_SCOPUS_RECORDS  <- 5000 # Maximum records to retrieve per topic from Scopus
MAX_OPENALEX_PAGES  <- 5    # Maximum pages (200 records/page = 1,000 items) from OpenAlex

#### 3. RUN 1: General Broad Search (using OR - saved at root) ####
GENERAL_TOPICS <- list(
  party_linkages = c(
    "political party",
    "party organization",
    "party linkage",
    "party decline"
  ),
  representation = c(
    "constituency service",
    "constituency focus",
    "local representation"
  )
)

general_results <- run_scoping_review(
  search_topics       = GENERAL_TOPICS,
  geo_terms           = GEO_TERMS,
  start_year          = START_YEAR,
  topic_operator      = "OR",
  max_scopus_records  = MAX_SCOPUS_RECORDS,
  max_openalex_pages  = MAX_OPENALEX_PAGES,
  output_filename     = "general_scoping_review.csv"  # Saved at folder root
)

#### 4. RUN 2: Targeted Strict Search (using AND - saved in outputs/ subfolder) ####
TARGETED_TOPICS <- list(
  patronage_parties = c("clientelism", "political party")
)

targeted_results <- run_scoping_review(
  search_topics       = TARGETED_TOPICS,
  geo_terms           = GEO_TERMS,
  start_year          = START_YEAR,
  topic_operator      = "AND",
  max_scopus_records  = MAX_SCOPUS_RECORDS,
  max_openalex_pages  = MAX_OPENALEX_PAGES,
  output_filename     = "outputs/targeted_scoping_review.csv"  # Saved in outputs/ subfolder
)
