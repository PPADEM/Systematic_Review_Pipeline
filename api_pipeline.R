# ==============================================================================
# AUTOMATED SCOPING LITERATURE REVIEW PIPELINE
# ==============================================================================
# Simply set your search topics, geographic filter terms, and limits below!
# ==============================================================================

# Load pipeline functions
source("R/pipeline_functions.R")

# 1. API Credentials Setup (Automatically reads OPENALEX_KEY and ELSEVIER_SCOPUS_KEY from ~/.Renviron)
if (Sys.getenv("OPENALEX_KEY") != "") {
  options(openalexR.apikey = Sys.getenv("OPENALEX_KEY"))
}

if (Sys.getenv("ELSEVIER_SCOPUS_KEY") != "") {
  set_api_key(Sys.getenv("ELSEVIER_SCOPUS_KEY"))
}

options(openalexR.mailto = "josh.tyler@bristol.ac.uk")

# 2. Search Topics & Keywords (Grouped by Category)
SEARCH_TOPICS <- list(
  party_linkages = c(
    "political party",
    "party organization",
    "party linkage",
    "party system",
    "candidate selection",
    "party decline"
  ),
  constituency_representation = c(
    "constituency service",
    "constituency focus",
    "constituency work",
    "home style",
    "district focus",
    "local representation"
  ),
  responsiveness_patronage = c(
    "service responsiveness",
    "clientelism",
    "patronage",
    "constituency development fund",
    "particularistic"
  )
)

# 3. Geographic Filter Terms (Continental, Regional, or Country-Specific)
GEO_TERMS <- c(
  "Africa",
  "Sub-Saharan Africa",
  "West Africa",
  "East Africa",
  "Southern Africa",
  "Central Africa"
)

# 4. Pipeline Parameters
START_YEAR <- 2020
MAX_SCOPUS_RECORDS <- 5000 # Maximum records to retrieve per topic from Scopus
MAX_OPENALEX_PAGES <- 20 # Maximum pages (200 records/page = 1,000 records per category) from OpenAlex

# ==============================================================================
# 5. EXECUTE SCOPING REVIEW PIPELINE
# ==============================================================================
results <- run_scoping_review(
  search_topics = SEARCH_TOPICS,
  geo_terms = GEO_TERMS,
  start_year = START_YEAR,
  max_scopus_records = MAX_SCOPUS_RECORDS,
  max_openalex_pages = MAX_OPENALEX_PAGES
)
