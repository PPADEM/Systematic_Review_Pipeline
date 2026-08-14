# ==============================================================================
# AUTOMATED SCOPING LITERATURE REVIEW PIPELINE
# ==============================================================================
# Simply set your search topics, geographic filter terms, and target phrases below!
# ==============================================================================

# Load pipeline functions
source("R/pipeline_functions.R")

# 1. API Setup (Set OpenAlex email for high-speed polite API pool)
options(openalexR.mailto = "josh.tyler@bristol.ac.uk")

# Optional Scopus Key Setup (uncomment if you have institutional Scopus access)
# Sys.setenv(ELSEVIER_SCOPUS_KEY = "your_scopus_api_key")

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

# 4. Target Phrases for Abstract Sentence Context Extraction
TARGET_PHRASES <- c(
  "party decline",
  "clientelism",
  "patronage",
  "constituency service"
)

# ==============================================================================
# 5. EXECUTE SCOPING REVIEW PIPELINE
# ==============================================================================
results <- run_scoping_review(
  search_topics = SEARCH_TOPICS,
  geo_terms = GEO_TERMS,
  start_year = 2020
)
