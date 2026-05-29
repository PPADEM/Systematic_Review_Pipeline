# Load required libraries
library(openalexR)
library(dplyr)
library(stringr)
library(purrr)
library(tidyr)

# ==========================================
# CONFIGURATION
# ==========================================
options(openalexR.mailto = "josh.tyler@bristol.ac.uk")

API_QUERIES <- c(
  "\"party decline\""
)

TARGET_PHRASES <- c("party decline")

# Number of top-cited papers to use for snowballing and keyword discovery
SNOWBALL_ANCHORS <- 5

# ==========================================
# PHASE 1: Search, Retrieve, and Sort by Impact
# ==========================================
cat("1. Fetching titles and abstracts from OpenAlex...\n")

fetch_single_term <- function(query) {
  cat(sprintf("   -> Searching for: %s\n", query))

  tryCatch(
    {
      res <- suppressWarnings(
        oa_fetch(
          entity = "works",
          title_and_abstract.search = query,
          from_publication_date = "2000-01-01",
          options = list(sort = "cited_by_count:desc")
        )
      )

      if (is.null(res) || nrow(res) == 0) {
        return(tibble(id = character()))
      }
      return(res)
    },
    error = function(e) {
      message("      Failed to fetch: ", query, " | Error: ", e$message)
      return(tibble(id = character()))
    }
  )
}

papers <- map(API_QUERIES, fetch_single_term) |> bind_rows()

if (nrow(papers) == 0) {
  stop("No papers found. Please check parameters.")
}

papers <- papers |> distinct(id, .keep_all = TRUE)
cat(sprintf(
  "\nTotal unique papers found: %d. Processing text...\n",
  nrow(papers)
))

# ==========================================
# PHASE 2: Clean Metadata
# ==========================================
text_data <- papers |>
  mutate(
    abstract = ifelse(is.na(abstract), "", abstract),
    title = ifelse(is.na(title), "", title),
    journal = ifelse(
      is.na(source_display_name),
      "Unknown Journal",
      source_display_name
    ),
    citations = ifelse(is.na(cited_by_count), 0, cited_by_count),
    authors = map_chr(authorships, function(x) {
      if (is.data.frame(x) && "author_display_name" %in% names(x)) {
        paste(x$author_display_name, collapse = "; ")
      } else if (is.data.frame(x) && "au_display_name" %in% names(x)) {
        paste(x$au_display_name, collapse = "; ")
      } else {
        "Unknown Author"
      }
    }),
    searchable_text = paste(title, abstract, sep = " - ")
  ) |>
  select(
    id,
    doi,
    publication_year,
    journal,
    authors,
    citations,
    title,
    searchable_text
  )

# ==========================================
# PHASE 3: Extract Context
# ==========================================
cat("2. Extracting keyword context from abstracts...\n")

dynamic_regex_core <- paste(TARGET_PHRASES, collapse = "|")
regex_pattern <- regex(
  sprintf(".{0,150}(%s).{0,150}", dynamic_regex_core),
  ignore_case = TRUE
)

results <- text_data |>
  mutate(
    context_mentions = map(
      searchable_text,
      ~ str_extract_all(.x, regex_pattern)[[1]]
    )
  ) |>
  unnest(context_mentions) |>
  mutate(
    context_mentions = str_squish(context_mentions),
    matched_term = tolower(str_extract(
      context_mentions,
      regex(dynamic_regex_core, ignore_case = TRUE)
    ))
  ) |>
  # Note: Keeping the 'id' column here so we can pass it to Phase 4
  select(
    id,
    citations,
    publication_year,
    journal,
    authors,
    title,
    doi,
    matched_term,
    context_mentions
  ) |>
  arrange(desc(citations))

cat(sprintf(
  "   -> Extracted %d specific mentions from the abstracts.\n",
  nrow(results)
))
write.csv(
  results,
  "outputs/party_decline_africa_abstracts.csv",
  row.names = FALSE
)

# ==========================================
# PHASE 4: Citation Snowballing
# ==========================================
cat(sprintf(
  "\n3. Running Citation Snowballing on the top %d cited papers...\n",
  SNOWBALL_ANCHORS
))

# Get the distinct top cited papers that ACTUALLY contained our context phrases
anchor_papers <- results |>
  distinct(id, .keep_all = TRUE) |>
  slice_head(n = SNOWBALL_ANCHORS)

anchor_ids <- anchor_papers$id

# Run the snowball function
snowball_network <- suppressWarnings(oa_snowball(
  identifier = anchor_ids,
  verbose = FALSE
))

snowball_nodes <- snowball_network$nodes
snowball_edges <- snowball_network$edges

cat(sprintf(
  "   -> Discovered a network of %d related papers and %d citation links!\n",
  nrow(snowball_nodes),
  nrow(snowball_edges)
))

# ==========================================
# EXPORT: Save both flat CSVs and rich RDS files
# ==========================================
# 1. Save the full, raw, nested dataset as an R object (.rds)
saveRDS(snowball_nodes, "outputs/snowball_papers_full.rds")

# 2. Clean the nodes dataframe to drop lists, then save as a flat CSV
snowball_nodes_clean <- snowball_nodes |>
  select(-where(is.list))

write.csv(
  snowball_nodes_clean,
  "outputs/snowball_papers_flat.csv",
  row.names = FALSE
)
write.csv(snowball_edges, "outputs/snowball_connections.csv", row.names = FALSE)

# ==========================================
# PHASE 5: N-Gram Keyword Discovery
# ==========================================
cat("\n4. Discovering hidden keywords via N-Grams...\n")

safe_ngrams <- function(id) {
  tryCatch(
    {
      # suppressMessages hides the repetitive "ngrams not available" text
      res <- suppressMessages(oa_ngrams(works_identifier = id))
      if (is.null(res)) {
        return(tibble())
      }
      return(res)
    },
    error = function(e) {
      return(tibble())
    }
  )
}

anchor_ngrams <- map(anchor_ids, safe_ngrams) |> bind_rows()

# FIX: Check that rows exist AND that the 'ngram_tokens' column was actually returned
if (nrow(anchor_ngrams) > 0 && "ngram_tokens" %in% names(anchor_ngrams)) {
  discovered_keywords <- anchor_ngrams |>
    filter(ngram_tokens %in% c(2, 3)) |>
    group_by(ngram) |>
    summarise(
      total_frequency = sum(ngram_count, na.rm = TRUE),
      papers_using_term = n_distinct(works_identifier)
    ) |>
    filter(
      !str_detect(
        ngram,
        "et al|in this|of the|to the|we find|this paper|in a|on the|by the"
      )
    ) |>
    arrange(desc(total_frequency)) |>
    slice_head(n = 30)

  cat("   -> Top 5 discovered phrases used by these authors:\n")
  print(head(discovered_keywords, 5))

  write.csv(
    discovered_keywords,
    "outputs/discovered_keywords.csv",
    row.names = FALSE
  )
} else {
  cat(
    "   -> No N-Grams available for these specific texts (likely due to publisher paywalls).\n"
  )
}

cat(
  "\nPipeline complete! All available CSV and RDS files have been exported successfully.\n"
)
