# ==========================================
# LIBRARIES & GLOBAL CONFIGURATION
# ==========================================
library(rscopus)
library(openalexR)
library(dplyr)
library(purrr)
library(stringr)
library(tidyr)
library(tibble)
library(synthesisr)

# 1. API Credentials Setup
set_api_key(Sys.getenv("ELSEVIER_SCOPUS_KEY"))
options(openalexR.mailto = "josh.tyler@bristol.ac.uk")

# 2. Output directory creation
if (!dir.exists("outputs")) {
  dir.create("outputs")
}

# 3. Parameters
START_YEAR <- 2020
SNOWBALL_ANCHORS <- 5

# Regional Search String
AFRICA_GEO <- '("Africa" OR "Sub-Saharan Africa" OR "Northern Africa" OR "West Africa" OR "East Africa" OR "Southern Africa" OR "Central Africa")'

# Multi-Block Search Categories
QUERY_BLOCKS <- list(
  party_linkages = c(
    '"political party"',
    '"party organization"',
    '"party linkage"',
    '"party system"',
    '"candidate selection"',
    '"party decline"'
  ),
  constituency_representation = c(
    '"constituency service"',
    '"constituency focus"',
    '"constituency work"',
    '"home style"',
    '"district focus"',
    '"local representation"'
  ),
  responsiveness_patronage = c(
    '"service responsiveness"',
    '"clientelism"',
    '"patronage"',
    '"constituency development fund"',
    '"particularistic"'
  )
)

# Targeted extraction phrases for Phase 3 Context Extraction
TARGET_PHRASES <- c(
  "party decline",
  "clientelism"
)


# ==========================================
# PHASE 1: DUAL-API INGESTION
# ==========================================
cat("\n=== PHASE 1: Fetching Data from Scopus & OpenAlex APIs ===\n")

# Scopus Search Function
fetch_scopus_block <- function(query_name, keywords) {
  Sys.sleep(1) # Rate limit safeguard

  kw_string <- paste(keywords, collapse = " OR ")
  scopus_q <- sprintf(
    'TITLE-ABS-KEY((%s) AND %s) AND PUBYEAR > %d',
    kw_string,
    AFRICA_GEO,
    START_YEAR - 1
  )

  cat(sprintf("   -> [Scopus] Fetching block: %s\n", query_name))

  tryCatch(
    {
      res <- scopus_search(query = scopus_q, max_count = 200, count = 25)

      if (is.null(res$entries) || length(res$entries) == 0) {
        return(tibble())
      }

      # Safe parsing per entry to prevent gen_entries_to_df() crashes
      parsed_entries <- map_dfr(res$entries, function(x) {
        tibble(
          database = "Scopus",
          query_category = query_name,
          openalex_id = x$`dc:identifier` %||% NA_character_,
          title = x$`dc:title` %||% NA_character_,
          journal = x$`prism:publicationName` %||% "Unknown Journal",
          publication_year = x$`prism:coverDate` %||% NA_character_,
          doi = x$`prism:doi` %||% NA_character_,
          citations = as.numeric(x$`citedby-count` %||% 0),
          abstract = x$`prism:description` %||% "",
          authors = x$`dc:creator` %||% "Unknown Author"
        )
      })

      # Clean publication year format
      parsed_entries <- parsed_entries %>%
        mutate(
          publication_year = as.integer(str_extract(
            publication_year,
            "^\\d{4}"
          ))
        )

      return(parsed_entries)
    },
    error = function(e) {
      message("      Scopus search failed: ", e$message)
      return(tibble())
    }
  )
}

# OpenAlex Search Function
fetch_openalex_block <- function(query_name, keywords) {
  cat(sprintf("   -> [OpenAlex] Fetching block: %s\n", query_name))

  # Clean keywords: strip internal escaped quotes
  clean_kw <- str_replace_all(keywords, '^"|"$', '')

  # Map over terms with mandatory rate-limit pauses
  block_results <- map_dfr(clean_kw, function(term) {
    # CRITICAL: 2.0 second pause between individual term requests to avoid 429 limits
    Sys.sleep(2.0)

    tryCatch(
      {
        res <- oa_fetch(
          entity = "works",
          # Combine term with regional filter in the primary search endpoint
          search = sprintf('"%s" AND "Africa"', term),
          from_publication_date = sprintf("%d-01-01", START_YEAR),
          options = list(sort = "cited_by_count:desc"),
          verbose = FALSE
        )
        if (!is.null(res) && nrow(res) > 0) res else tibble()
      },
      error = function(e) {
        message(sprintf(
          "      [OpenAlex Throttled/Error] Term: '%s' | %s",
          term,
          e$message
        ))
        tibble()
      }
    )
  })

  if (nrow(block_results) == 0) {
    return(tibble())
  }

  # Deduplicate terms within this query block
  block_results <- block_results %>% distinct(id, .keep_all = TRUE)

  # openalexR v2.0.0+ Schema Parsing
  tryCatch(
    {
      # Author Extraction
      authors_vec <- if ("authorships" %in% names(block_results)) {
        map_chr(block_results$authorships, function(x) {
          if (is.data.frame(x) && "author_display_name" %in% names(x)) {
            paste(x$author_display_name, collapse = "; ")
          } else if (is.data.frame(x) && "au_display_name" %in% names(x)) {
            paste(x$au_display_name, collapse = "; ")
          } else {
            "Unknown Author"
          }
        })
      } else {
        "Unknown Author"
      }

      # Journal Extraction
      journal_vec <- if (
        "primary_location.source.display_name" %in% names(block_results)
      ) {
        block_results$`primary_location.source.display_name`
      } else if ("source_display_name" %in% names(block_results)) {
        block_results$source_display_name
      } else if ("so" %in% names(block_results)) {
        block_results$so
      } else {
        "Unknown Journal"
      }

      # Abstract Extraction
      abstract_vec <- if ("abstract" %in% names(block_results)) {
        block_results$abstract
      } else if ("ab" %in% names(block_results)) {
        block_results$ab
      } else {
        ""
      }

      # Year Extraction
      pub_year_vec <- if ("publication_year" %in% names(block_results)) {
        as.integer(block_results$publication_year)
      } else {
        NA_integer_
      }

      block_results %>%
        mutate(
          database = "OpenAlex",
          query_category = query_name,
          authors = authors_vec,
          journal = ifelse(is.na(journal_vec), "Unknown Journal", journal_vec),
          abstract = ifelse(is.na(abstract_vec), "", abstract_vec),
          publication_year = pub_year_vec,
          citations = as.numeric(cited_by_count)
        ) %>%
        select(
          database,
          query_category,
          openalex_id = id,
          title = display_name,
          journal,
          publication_year,
          doi,
          citations,
          abstract,
          authors
        )
    },
    error = function(e) {
      message("      OpenAlex parsing error: ", e$message)
      tibble()
    }
  )
}

# Execute Extractions
scopus_raw <- imap_dfr(QUERY_BLOCKS, ~ fetch_scopus_block(.y, .x))
openalex_raw <- imap_dfr(QUERY_BLOCKS, ~ fetch_openalex_block(.y, .x))

combined_raw <- bind_rows(scopus_raw, openalex_raw)
cat(sprintf(
  "Raw Extracted Records: %d (Scopus: %d | OpenAlex: %d)\n",
  nrow(combined_raw),
  nrow(scopus_raw),
  nrow(openalex_raw)
))


# ==========================================
# PHASE 2: PRISMA HARMONIZATION & DEDUPLICATION
# ==========================================
cat("\n=== PHASE 2: Harmonization & PRISMA Deduplication ===\n")

dedup_step1 <- deduplicate(
  combined_raw,
  match_variable = "doi",
  method = "exact"
)
deduplicated_papers <- deduplicate(
  dedup_step1,
  match_variable = "title",
  method = "string_dist",
  rm.duplicates = TRUE
)

cat(sprintf(
  "Duplicates Removed: %d\nFinal Unique Dataset: %d\n",
  nrow(combined_raw) - nrow(deduplicated_papers),
  nrow(deduplicated_papers)
))

# Clean up text and fill empty values
text_data <- deduplicated_papers %>%
  mutate(
    abstract = ifelse(is.na(abstract), "", abstract),
    title = ifelse(is.na(title), "", title),
    journal = ifelse(is.na(journal), "Unknown Journal", journal),
    citations = ifelse(is.na(citations), 0, citations),
    authors = ifelse(is.na(authors), "Unknown Author", authors),
    searchable_text = paste(title, abstract, sep = " - ")
  )


# ==========================================
# PHASE 3: EXTRACT KEYWORD CONTEXT
# ==========================================
cat("\n=== PHASE 3: Extracting Keyword Context from Text ===\n")

dynamic_regex_core <- paste(TARGET_PHRASES, collapse = "|")
regex_pattern <- regex(
  sprintf(".{0,150}(%s).{0,150}", dynamic_regex_core),
  ignore_case = TRUE
)

context_results <- text_data %>%
  mutate(
    context_mentions = map(
      searchable_text,
      ~ str_extract_all(.x, regex_pattern)[[1]]
    )
  ) %>%
  unnest(context_mentions) %>%
  mutate(
    context_mentions = str_squish(context_mentions),
    matched_term = tolower(str_extract(
      context_mentions,
      regex(dynamic_regex_core, ignore_case = TRUE)
    ))
  ) %>%
  select(
    database,
    query_category,
    openalex_id,
    citations,
    publication_year,
    journal,
    authors,
    title,
    doi,
    matched_term,
    context_mentions
  ) %>%
  arrange(desc(citations))

cat(sprintf(
  "Extracted %d specific target phrase mentions.\n",
  nrow(context_results)
))
write.csv(context_results, "outputs/context_mentions.csv", row.names = FALSE)


# ==========================================
# PHASE 4: CITATION SNOWBALLING (OpenAlex)
# ==========================================
cat(sprintf(
  "\n=== PHASE 4: Citation Snowballing (Top %d Cited OpenAlex Anchors) ===\n",
  SNOWBALL_ANCHORS
))

# Filter anchor papers specifically to OpenAlex entries (required for oa_snowball API call)
anchor_papers <- text_data %>%
  filter(
    database == "OpenAlex",
    str_detect(openalex_id, "^https://openalex.org/")
  ) %>%
  arrange(desc(citations)) %>%
  slice_head(n = SNOWBALL_ANCHORS)

if (nrow(anchor_papers) > 0) {
  anchor_ids <- anchor_papers$openalex_id

  snowball_network <- suppressWarnings(oa_snowball(
    identifier = anchor_ids,
    verbose = FALSE
  ))
  snowball_nodes <- snowball_network$nodes
  snowball_edges <- snowball_network$edges

  cat(sprintf(
    "Discovered network: %d related papers | %d citation links\n",
    nrow(snowball_nodes),
    nrow(snowball_edges)
  ))

  saveRDS(snowball_nodes, "outputs/snowball_papers_full.rds")
  write.csv(
    snowball_nodes %>% select(-where(is.list)),
    "outputs/snowball_papers_flat.csv",
    row.names = FALSE
  )
  write.csv(
    snowball_edges,
    "outputs/snowball_connections.csv",
    row.names = FALSE
  )
} else {
  cat("No eligible OpenAlex anchor IDs found for snowballing.\n")
  anchor_ids <- character()
}


# ==========================================
# PHASE 5: N-GRAM KEYWORD DISCOVERY
# ==========================================
cat("\n=== PHASE 5: N-Gram Keyword Discovery ===\n")

if (length(anchor_ids) > 0) {
  safe_ngrams <- function(id) {
    tryCatch(
      {
        res <- suppressMessages(oa_ngrams(works_identifier = id))
        if (is.null(res)) tibble() else res
      },
      error = function(e) tibble()
    )
  }

  anchor_ngrams <- map(anchor_ids, safe_ngrams) %>% bind_rows()

  if (nrow(anchor_ngrams) > 0 && "ngram_tokens" %in% names(anchor_ngrams)) {
    discovered_keywords <- anchor_ngrams %>%
      filter(ngram_tokens %in% c(2, 3)) %>%
      group_by(ngram) %>%
      summarise(
        total_frequency = sum(ngram_count, na.rm = TRUE),
        papers_using_term = n_distinct(works_identifier)
      ) %>%
      filter(
        !str_detect(
          ngram,
          "et al|in this|of the|to the|we find|this paper|in a|on the|by the"
        )
      ) %>%
      arrange(desc(total_frequency)) %>%
      slice_head(n = 30)

    cat("Top discovered N-gram phrases:\n")
    print(head(discovered_keywords, 5))
    write.csv(
      discovered_keywords,
      "outputs/discovered_keywords.csv",
      row.names = FALSE
    )
  } else {
    cat("No N-Grams available for selected anchor texts.\n")
  }
}

cat("\nPipeline Complete! All outputs generated in the 'outputs/' directory.\n")
