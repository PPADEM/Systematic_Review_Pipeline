# ==============================================================================
# PIPELINE: AUTOMATED SCOPING REVIEW ON POLITICAL SCIENCE RESEARCH IN AFRICA
# MERGING SCOPUS AND OPENALEX BIBLIOMETRIC DATA
# ==============================================================================
# Authors: Scoping Review Computational Pipeline
# Required Packages: rscopus, openalexR, dplyr, purrr, stringr, tidyr, 
#                    tibble, stringdist, synthesisr
# ==============================================================================

# ------------------------------------------------------------------------------
# LIBRARIES & GLOBAL CONFIGURATION
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(rscopus)
  library(openalexR)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(tibble)
  library(stringdist)
  library(synthesisr)
})

# 1. API Credentials Setup
# Set Scopus API key from environment variable (if available)
scopus_key <- Sys.getenv("ELSEVIER_SCOPUS_KEY")
if (scopus_key != "") {
  set_api_key(scopus_key)
} else {
  message("[Notice] ELSEVIER_SCOPUS_KEY not set in environment. Scopus queries will be skipped or limited.")
}

# Set OpenAlex polite pool email (required for elevated rate limits and polite pool)
options(openalexR.mailto = "josh.tyler@bristol.ac.uk")

# 2. Output Directory Setup
if (!dir.exists("outputs")) {
  dir.create("outputs", recursive = TRUE)
}

# 3. Execution Parameters
START_YEAR <- 2020
SNOWBALL_ANCHORS <- 5

# Regional Search String for African Continent & Sub-Regions
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

# Targeted Phrases for In-Depth Context Extraction
TARGET_PHRASES <- c(
  "party decline",
  "clientelism",
  "patronage",
  "constituency service"
)


# ==============================================================================
# UTILITY HELPER FUNCTIONS
# ==============================================================================

#' Standardize DOIs by removing protocol prefixes, 'doi:', and trailing slashes
clean_doi <- function(doi_vec) {
  doi_clean <- tolower(trimws(as.character(doi_vec)))
  doi_clean <- str_remove(doi_clean, "^https?://(dx\\.)?doi\\.org/")
  doi_clean <- str_remove(doi_clean, "^doi:")
  doi_clean <- str_remove(doi_clean, "/+$")
  doi_clean[doi_clean == "" | is.na(doi_clean) | doi_clean == "na"] <- NA_character_
  return(doi_clean)
}

#' Normalize title strings by lowercasing, removing punctuation, and collapsing whitespace
clean_title <- function(title_vec) {
  t_clean <- tolower(as.character(title_vec))
  t_clean <- str_replace_all(t_clean, "[[:punct:]]", " ")
  t_clean <- str_replace_all(t_clean, "[[:space:]]+", " ")
  t_clean <- str_trim(t_clean)
  t_clean[t_clean == "" | is.na(t_clean)] <- NA_character_
  return(t_clean)
}

#' Return the longest non-empty string in a vector (ideal for picking fullest abstract/authors)
max_length_str <- function(vec) {
  vec <- na.omit(vec)
  vec <- vec[vec != "" & vec != "Unknown Author" & vec != "Unknown Journal"]
  if (length(vec) == 0) return("")
  vec[which.max(nchar(vec))]
}

#' Wrapper for openalexR calls with automatic rate-limit (HTTP 429) retries & exponential backoff
oa_fetch_with_retry <- function(..., max_retries = 3, initial_sleep = 2.0) {
  for (attempt in seq_len(max_retries)) {
    res <- tryCatch(
      {
        oa_fetch(...)
      },
      error = function(e) {
        if (str_detect(e$message, "429|Too Many Requests")) {
          sleep_time <- initial_sleep * attempt
          message(sprintf("      [Rate Limit 429] Retrying in %.1f seconds (Attempt %d/%d)...", sleep_time, attempt, max_retries))
          Sys.sleep(sleep_time)
          return(NULL)
        } else {
          message("      [OpenAlex Error] ", e$message)
          return(tibble())
        }
      }
    )
    if (!is.null(res) && is.data.frame(res)) return(res)
  }
  return(tibble())
}

#' Safely parse author names and institutional country codes from OpenAlex authorships list
parse_openalex_authorships <- function(authorships_list) {
  if (is.null(authorships_list) || length(authorships_list) == 0) {
    return(list(authors = "Unknown Author", author_countries = NA_character_, affiliations = NA_character_))
  }
  
  parsed <- map(authorships_list, function(x) {
    if (!is.data.frame(x)) {
      return(list(author_str = "Unknown Author", country_str = NA_character_, affil_str = NA_character_))
    }
    
    # Author Name
    names_vec <- if ("author_display_name" %in% names(x)) {
      x$author_display_name
    } else if ("au_display_name" %in% names(x)) {
      x$au_display_name
    } else if ("display_name" %in% names(x)) {
      x$display_name
    } else {
      "Unknown Author"
    }
    
    # Affiliations & Countries
    countries_vec <- character()
    affil_vec <- character()
    
    if ("affiliations" %in% names(x) && is.list(x$affiliations)) {
      affil_data <- map_dfr(x$affiliations, function(aff) {
        if (is.data.frame(aff)) aff else tibble()
      })
      if (nrow(affil_data) > 0) {
        if ("country_code" %in% names(affil_data)) {
          countries_vec <- na.omit(affil_data$country_code)
        }
        if ("display_name" %in% names(affil_data)) {
          affil_vec <- na.omit(affil_data$display_name)
        }
      }
    }
    
    if ("affiliation_raw" %in% names(x)) {
      raw_aff <- na.omit(x$affiliation_raw)
      affil_vec <- c(affil_vec, raw_aff)
    }
    
    list(
      author_str = paste(na.omit(names_vec), collapse = "; "),
      country_str = paste(unique(countries_vec[countries_vec != ""]), collapse = "; "),
      affil_str = paste(unique(affil_vec[affil_vec != ""]), collapse = "; ")
    )
  })
  
  list(
    authors = map_chr(parsed, ~ .x$author_str),
    author_countries = map_chr(parsed, ~ .x$country_str),
    affiliations = map_chr(parsed, ~ .x$affil_str)
  )
}


# ==============================================================================
# PHASE 1: DUAL-API INGESTION (SCOPUS & OPENALEX)
# ==============================================================================
cat("\n=================================================================\n")
cat("=== PHASE 1: Fetching Bibliographic Data from Scopus & OpenAlex ===\n")
cat("=================================================================\n")

# 1A. Scopus Search Engine Integration
fetch_scopus_block <- function(query_name, keywords) {
  if (Sys.getenv("ELSEVIER_SCOPUS_KEY") == "") {
    return(tibble())
  }
  
  Sys.sleep(1.0) # Rate limiting safeguard (Scopus allows ~9 req/sec, polite pause)
  
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
      # scopus_search handles pagination internally up to max_count
      res <- scopus_search(query = scopus_q, max_count = 200, count = 25, verbose = FALSE)
      
      if (is.null(res$entries) || length(res$entries) == 0) {
        return(tibble())
      }
      
      # Parse Scopus entries safely per record
      parsed_entries <- map_dfr(res$entries, function(x) {
        # Authors in Scopus entry
        author_str <- if (!is.null(x$`dc:creator`)) {
          x$`dc:creator`
        } else if (!is.null(x$author) && is.list(x$author)) {
          authors_df <- map_dfr(x$author, as_tibble)
          if ("authname" %in% names(authors_df)) {
            paste(authors_df$authname, collapse = "; ")
          } else {
            "Unknown Author"
          }
        } else {
          "Unknown Author"
        }
        
        # Scopus ID vs OpenAlex ID demarcation
        sc_id <- x$`dc:identifier` %||% NA_character_
        
        # Safe Affiliation & Country extraction from Scopus
        affil_str <- NA_character_
        country_str <- NA_character_
        
        if (!is.null(x$affiliation)) {
          if (is.data.frame(x$affiliation)) {
            aff_names <- x$affiliation$affilname %||% NA_character_
            affil_str <- paste(na.omit(aff_names), collapse = "; ")
            c_names <- x$affiliation$`affiliation-country` %||% NA_character_
            country_str <- paste(unique(na.omit(c_names)), collapse = "; ")
          } else if (is.list(x$affiliation)) {
            aff_names <- map_chr(x$affiliation, function(a) {
              if (is.list(a)) a$affilname %||% "" else as.character(a)
            })
            affil_str <- paste(unique(aff_names[aff_names != ""]), collapse = "; ")
            c_names <- map_chr(x$affiliation, function(a) {
              if (is.list(a)) a$`affiliation-country` %||% "" else ""
            })
            country_str <- paste(unique(c_names[c_names != ""]), collapse = "; ")
          } else {
            affil_str <- as.character(x$affiliation)
          }
        }
        if (is.na(affil_str) || affil_str == "") affil_str <- NA_character_
        if (is.na(country_str) || country_str == "") country_str <- NA_character_
        
        tibble(
          database = "Scopus",
          query_category = query_name,
          scopus_id = sc_id,
          openalex_id = NA_character_,
          title = x$`dc:title` %||% NA_character_,
          journal = x$`prism:publicationName` %||% "Unknown Journal",
          publication_year = x$`prism:coverDate` %||% NA_character_,
          doi = x$`prism:doi` %||% NA_character_,
          citations = as.numeric(x$`citedby-count` %||% 0),
          abstract = x$`prism:description` %||% "",
          authors = author_str,
          author_countries = country_str,
          affiliations = affil_str
        )
      })
      
      # Clean publication year format from coverDate (YYYY-MM-DD -> YYYY)
      parsed_entries <- parsed_entries %>%
        mutate(
          publication_year = as.integer(str_extract(publication_year, "^\\d{4}"))
        )
      
      return(parsed_entries)
    },
    error = function(e) {
      message("      [Scopus Error] Block: ", query_name, " | ", e$message)
      return(tibble())
    }
  )
}

# 1B. OpenAlex Search Engine Integration
fetch_openalex_block <- function(query_name, keywords) {
  cat(sprintf("   -> [OpenAlex] Fetching block: %s\n", query_name))
  
  # Retain unquoted and quoted terms properly for API query
  block_results <- map_dfr(keywords, function(term) {
    Sys.sleep(1.2) # Polite 1.2-second pause between term queries
    
    # Strip boundary quotes for clean construction
    raw_term <- str_replace_all(term, '^"|"$', '')
    query_str <- sprintf('"%s" AND "Africa"', raw_term)
    
    oa_fetch_with_retry(
      entity = "works",
      title_and_abstract.search = query_str,
      from_publication_date = sprintf("%d-01-01", START_YEAR),
      pages = 1:5, # Fetch up to top 5 pages (1000 items) per keyword
      verbose = FALSE
    )
  })
  
  if (nrow(block_results) == 0) {
    return(tibble())
  }
  
  # Deduplicate terms within this query block
  block_results <- block_results %>% distinct(id, .keep_all = TRUE)
  
  # Schema Harmonization for openalexR v3.0+
  tryCatch(
    {
      # Parse authorships list column safely
      authorship_data <- parse_openalex_authorships(block_results$authorships)
      
      # Journal / Source display name
      journal_vec <- if ("source_display_name" %in% names(block_results)) {
        block_results$source_display_name
      } else if ("primary_location.source.display_name" %in% names(block_results)) {
        block_results$`primary_location.source.display_name`
      } else if ("so" %in% names(block_results)) {
        block_results$so
      } else {
        "Unknown Journal"
      }
      
      # Abstract
      abstract_vec <- if ("abstract" %in% names(block_results)) {
        block_results$abstract
      } else if ("ab" %in% names(block_results)) {
        block_results$ab
      } else {
        ""
      }
      
      # Title
      title_vec <- if ("title" %in% names(block_results)) {
        block_results$title
      } else if ("display_name" %in% names(block_results)) {
        block_results$display_name
      } else {
        NA_character_
      }
      
      # DOI
      doi_vec <- if ("doi" %in% names(block_results)) {
        block_results$doi
      } else {
        NA_character_
      }
      
      block_results %>%
        mutate(
          database = "OpenAlex",
          query_category = query_name,
          scopus_id = NA_character_,
          openalex_id = id,
          title = title_vec,
          journal = ifelse(is.na(journal_vec), "Unknown Journal", journal_vec),
          publication_year = as.integer(publication_year),
          doi = doi_vec,
          citations = as.numeric(cited_by_count %||% 0),
          abstract = ifelse(is.na(abstract_vec), "", abstract_vec),
          authors = authorship_data$authors,
          author_countries = authorship_data$author_countries,
          affiliations = authorship_data$affiliations
        ) %>%
        select(
          database,
          query_category,
          scopus_id,
          openalex_id,
          title,
          journal,
          publication_year,
          doi,
          citations,
          abstract,
          authors,
          author_countries,
          affiliations
        )
    },
    error = function(e) {
      message("      [OpenAlex Parsing Error] Block: ", query_name, " | ", e$message)
      tibble()
    }
  )
}

# Execute Query Extractions across all Blocks
scopus_raw <- imap_dfr(QUERY_BLOCKS, ~ fetch_scopus_block(.y, .x))
openalex_raw <- imap_dfr(QUERY_BLOCKS, ~ fetch_openalex_block(.y, .x))

combined_raw <- bind_rows(scopus_raw, openalex_raw)
cat(sprintf(
  "\nIngestion Summary: %d raw records retrieved (Scopus: %d | OpenAlex: %d)\n",
  nrow(combined_raw),
  nrow(scopus_raw),
  nrow(openalex_raw)
))


# ==============================================================================
# PHASE 2: HARMONIZATION & 2-STAGE HYBRID DEDUPLICATION
# ==============================================================================
cat("\n=================================================================\n")
cat("=== PHASE 2: Data Harmonization & 2-Stage Hybrid Deduplication ===\n")
cat("=================================================================\n")

if (nrow(combined_raw) == 0) {
  stop("No records retrieved from API queries. Please verify search strings or API credentials.")
}

deduplicate_and_merge <- function(df) {
  # 1. Preprocessing & Clean Keys
  df <- df %>%
    mutate(
      clean_doi_key = clean_doi(doi),
      norm_title = clean_title(title),
      publication_year = as.integer(publication_year)
    )
  
  # Partition into records with clean DOI vs missing clean DOI
  has_doi <- df %>% filter(!is.na(clean_doi_key))
  no_doi  <- df %>% filter(is.na(clean_doi_key))
  
  # Stage 1: Group by Clean DOI and collapse duplicate metadata
  merged_doi <- has_doi %>%
    group_by(clean_doi_key) %>%
    summarise(
      database = paste(sort(unique(database)), collapse = "; "),
      scopus_id = coalesce(first(na.omit(scopus_id)), NA_character_),
      openalex_id = coalesce(first(na.omit(openalex_id)), NA_character_),
      title = first(na.omit(title)),
      journal = max_length_str(journal),
      publication_year = first(na.omit(publication_year)),
      doi = coalesce(first(na.omit(doi)), first(clean_doi_key)),
      citations = max(citations, na.rm = TRUE),
      abstract = max_length_str(abstract),
      authors = max_length_str(authors),
      author_countries = max_length_str(author_countries),
      affiliations = max_length_str(affiliations),
      norm_title = first(norm_title),
      query_category = paste(sort(unique(query_category)), collapse = "; "),
      .groups = "drop"
    )
  
  # Stage 2: Combine Stage 1 results with no_doi records and perform Fuzzy String Matching
  candidates <- bind_rows(merged_doi, no_doi)
  n <- nrow(candidates)
  
  if (n <= 1) {
    return(candidates %>% select(-clean_doi_key, -norm_title))
  }
  
  # Compute Jaro-Winkler string distance matrix on normalized titles
  dist_matrix <- stringdistmatrix(candidates$norm_title, candidates$norm_title, method = "jw", p = 0.1)
  
  dup_group <- seq_len(n)
  
  # Group titles with Jaro-Winkler distance <= 0.12 AND publication year within +/- 1 year
  for (i in seq_len(n - 1)) {
    for (j in (i + 1):n) {
      y_i <- candidates$publication_year[i]
      y_j <- candidates$publication_year[j]
      same_year <- is.na(y_i) || is.na(y_j) || abs(y_i - y_j) <= 1
      
      if (!is.na(dist_matrix[i, j]) && dist_matrix[i, j] <= 0.12 && same_year) {
        dup_group[j] <- dup_group[i]
      }
    }
  }
  
  candidates$dup_group <- dup_group
  
  # Final collapse across fuzzy duplicate groups
  final_df <- candidates %>%
    group_by(dup_group) %>%
    summarise(
      database = paste(sort(unique(unlist(str_split(database, "; ")))), collapse = "; "),
      scopus_id = coalesce(first(na.omit(scopus_id)), NA_character_),
      openalex_id = coalesce(first(na.omit(openalex_id)), NA_character_),
      title = first(na.omit(title)),
      journal = max_length_str(journal),
      publication_year = first(na.omit(publication_year)),
      doi = coalesce(first(na.omit(doi)), first(na.omit(clean_doi_key))),
      citations = max(citations, na.rm = TRUE),
      abstract = max_length_str(abstract),
      authors = max_length_str(authors),
      author_countries = max_length_str(author_countries),
      affiliations = max_length_str(affiliations),
      query_category = paste(sort(unique(unlist(str_split(query_category, "; ")))), collapse = "; "),
      .groups = "drop"
    ) %>%
    select(-dup_group)
  
  return(final_df)
}

deduplicated_papers <- deduplicate_and_merge(combined_raw)

cat(sprintf(
  "Deduplication Results:\n  - Initial Records: %d\n  - Duplicates Removed: %d\n  - Unique Clean Dataset: %d\n",
  nrow(combined_raw),
  nrow(combined_raw) - nrow(deduplicated_papers),
  nrow(deduplicated_papers)
))

# Format final clean text dataset
text_data <- deduplicated_papers %>%
  mutate(
    abstract = ifelse(is.na(abstract), "", abstract),
    title = ifelse(is.na(title), "", title),
    journal = ifelse(is.na(journal) | journal == "", "Unknown Journal", journal),
    citations = ifelse(is.na(citations), 0, citations),
    authors = ifelse(is.na(authors) | authors == "", "Unknown Author", authors),
    searchable_text = paste(title, abstract, sep = " - ")
  )


# ==============================================================================
# PHASE 3: CONTEXTUAL KEYWORD SENTENCE EXTRACTION
# ==============================================================================
cat("\n=================================================================\n")
cat("=== PHASE 3: Extracting Target Keyword Context from Abstract Text ===\n")
cat("=================================================================\n")

# Escape target phrases to ensure clean regex matching
escaped_phrases <- str_escape(TARGET_PHRASES)
dynamic_regex_core <- paste(escaped_phrases, collapse = "|")
regex_pattern <- regex(
  sprintf(".{0,150}(%s).{0,150}", dynamic_regex_core),
  ignore_case = TRUE
)

context_results <- text_data %>%
  mutate(
    context_mentions = map(
      searchable_text,
      function(txt) {
        matches <- str_extract_all(txt, regex_pattern)[[1]]
        if (length(matches) == 0) character(0) else matches
      }
    )
  ) %>%
  unnest(context_mentions, keep_empty = FALSE) %>%
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
    scopus_id,
    openalex_id,
    doi,
    title,
    journal,
    publication_year,
    citations,
    authors,
    author_countries,
    matched_term,
    context_mentions
  ) %>%
  arrange(desc(citations))

cat(sprintf("Extracted %d contextual phrase mentions across abstracts.\n", nrow(context_results)))
write.csv(context_results, "outputs/context_mentions.csv", row.names = FALSE)


# ==============================================================================
# PHASE 4: CITATION SNOWBALLING (OPENALEX NETWORK MAP)
# ==============================================================================
cat("\n=================================================================\n")
cat(sprintf("=== PHASE 4: Citation Snowballing (Top %d Impact Anchors) ===\n", SNOWBALL_ANCHORS))
cat("=================================================================\n")

# Identify top-cited anchor papers. If an anchor has a DOI but missing OpenAlex ID, resolve it!
anchor_candidates <- text_data %>%
  arrange(desc(citations)) %>%
  slice_head(n = SNOWBALL_ANCHORS * 2)

# Ensure OpenAlex IDs exist for top anchors
anchor_ids <- character()

for (i in seq_len(nrow(anchor_candidates))) {
  if (length(anchor_ids) >= SNOWBALL_ANCHORS) break
  
  oa_id <- anchor_candidates$openalex_id[i]
  doi_val <- anchor_candidates$doi[i]
  
  if (!is.na(oa_id) && str_detect(oa_id, "^https://openalex.org/")) {
    anchor_ids <- c(anchor_ids, oa_id)
  } else if (!is.na(doi_val) && doi_val != "") {
    # Resolve via OpenAlex API lookup by DOI
    tryCatch({
      res_doi <- oa_fetch_with_retry(entity = "works", doi = doi_val, verbose = FALSE)
      if (!is.null(res_doi) && nrow(res_doi) > 0) {
        anchor_ids <- c(anchor_ids, res_doi$id[1])
      }
    }, error = function(e) NULL)
  }
}

anchor_ids <- unique(na.omit(anchor_ids))

if (length(anchor_ids) > 0) {
  cat(sprintf("   -> Running citation snowball on %d resolved OpenAlex anchor IDs...\n", length(anchor_ids)))
  Sys.sleep(2.0) # Pause before snowball call to avoid 429
  
  snowball_network <- tryCatch(
    {
      suppressWarnings(oa_snowball(identifier = anchor_ids, verbose = FALSE))
    },
    error = function(e) {
      message("      [Snowballing Notice] ", e$message)
      NULL
    }
  )
  
  if (!is.null(snowball_network) && !is.null(snowball_network$nodes) && nrow(snowball_network$nodes) > 0) {
    snowball_nodes <- snowball_network$nodes
    snowball_edges <- snowball_network$edges
    
    cat(sprintf(
      "   -> Citation Network Discovered: %d nodes | %d citation edges\n",
      nrow(snowball_nodes),
      nrow(snowball_edges)
    ))
    
    saveRDS(snowball_nodes, "outputs/snowball_papers_full.rds")
    write.csv(
      snowball_nodes %>% select(-where(is.list)),
      "outputs/snowball_papers_flat.csv",
      row.names = FALSE
    )
    write.csv(snowball_edges, "outputs/snowball_connections.csv", row.names = FALSE)
  } else {
    cat("   -> No snowball citation network returned for selected anchors.\n")
  }
} else {
  cat("   -> No valid OpenAlex anchor IDs available for snowballing.\n")
}


# ==============================================================================
# PHASE 5: N-GRAM TERMINOLOGY DISCOVERY
# ==============================================================================
cat("\n=================================================================\n")
cat("=== PHASE 5: N-Gram Terminology Discovery ===\n")
cat("=================================================================\n")

if (length(anchor_ids) > 0) {
  safe_ngrams <- function(id) {
    Sys.sleep(1.0)
    tryCatch(
      {
        res <- suppressMessages(oa_ngrams(works_identifier = id))
        if (is.null(res)) tibble() else res
      },
      error = function(e) tibble()
    )
  }
  
  anchor_ngrams <- map_dfr(anchor_ids, safe_ngrams)
  
  if (nrow(anchor_ngrams) > 0 && "ngram_tokens" %in% names(anchor_ngrams)) {
    discovered_keywords <- anchor_ngrams %>%
      filter(ngram_tokens %in% c(2, 3)) %>%
      group_by(ngram) %>%
      summarise(
        total_frequency = sum(ngram_count, na.rm = TRUE),
        papers_using_term = n_distinct(works_identifier),
        .groups = "drop"
      ) %>%
      filter(
        !str_detect(
          ngram,
          "et al|in this|of the|to the|we find|this paper|in a|on the|by the|as well"
        )
      ) %>%
      arrange(desc(total_frequency)) %>%
      slice_head(n = 30)
    
    cat("Top discovered N-gram key phrases:\n")
    print(head(discovered_keywords, 5))
    write.csv(discovered_keywords, "outputs/discovered_keywords.csv", row.names = FALSE)
  } else {
    cat("   -> N-Grams not available for current anchor works (publisher restrictions).\n")
  }
}

cat("\n=================================================================\n")
cat("Pipeline Completed Successfully! All output files generated in 'outputs/'.\n")
cat("=================================================================\n")
