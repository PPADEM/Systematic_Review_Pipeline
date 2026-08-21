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
GEO_TERMS <- c("Africa")
START_YEAR <- 2020
MAX_SCOPUS_RECORDS <- 5000 # Maximum records to retrieve per topic from Scopus
MAX_OPENALEX_PAGES <- 5 # Maximum pages (200 records/page = 1,000 items) from OpenAlex

#### 3. RUN 1: Multi-Block Concept Search (BLOCK 1 AND BLOCK 2 AND GEO - saved at root) ####
# Combines (Party terms separated by OR) AND (Communication terms separated by OR) AND (Africa)
MULTI_TOPICS <- list(
  political_party = c(
    "Intra-party politics",
    "Intraparty politics",
    "Intra-party democracy",
    "Intraparty democracy",
    "Party organisation",
    "Party organization",
    "Party Institutionalisation",
    "Party Institutionalization"
  ),
  communication = c(
    "Communication",
    "Meeting",
    "Delegation",
    "Accountability",
    "Participation",
    "Conference",
    "Social Media",
    "Whats App"
  )
)

multi_results <- run_scoping_review(
  search_topics = MULTI_TOPICS,
  geo_terms = GEO_TERMS,
  start_year = START_YEAR,
  topic_operator = "multi",
  max_scopus_records = MAX_SCOPUS_RECORDS,
  max_openalex_pages = MAX_OPENALEX_PAGES,
  output_filename = "multi_block_scoping_review.csv" # Saved at folder root
)

#### 4. RUN 2: General Broad Search (using OR - saved in outputs/ subfolder) ####
GENERAL_TOPICS <- list(
  political_party = c("Intra-party politics", "Party organisation"),
  communication = c("Communication", "Meeting")
)

general_results <- run_scoping_review(
  search_topics = GENERAL_TOPICS,
  geo_terms = GEO_TERMS,
  start_year = START_YEAR,
  topic_operator = "OR",
  max_scopus_records = MAX_SCOPUS_RECORDS,
  max_openalex_pages = MAX_OPENALEX_PAGES,
  output_filename = "outputs/general_scoping_review.csv"
)

#### 5. RUN 3: Targeted Strict Search (using AND - saved in outputs/ subfolder) ####
TARGETED_TOPICS <- list(
  patronage_parties = c("clientelism", "political party")
)

targeted_results <- run_scoping_review(
  search_topics = TARGETED_TOPICS,
  geo_terms = GEO_TERMS,
  start_year = START_YEAR,
  topic_operator = "AND",
  max_scopus_records = MAX_SCOPUS_RECORDS,
  max_openalex_pages = MAX_OPENALEX_PAGES,
  output_filename = "outputs/targeted_scoping_review.csv" # Saved in outputs/ subfolder
)
