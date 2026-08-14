# ==============================================================================
# FUNCTION LIBRARY: AUTOMATED BIBLIOGRAPHIC SCOPING REVIEWS
# ==============================================================================
# Contains core pipeline functions: Scopus & OpenAlex dual-API fetching,
# rate-limit retry logic, schema harmonization, and 2-stage hybrid deduplication.
# ==============================================================================

suppressPackageStartupMessages({
  library(rscopus)
  library(openalexR)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(tibble)
  library(stringdist)
})

# ------------------------------------------------------------------------------
# 1. HELPER & CLEANING UTILITIES
# ------------------------------------------------------------------------------

#' Standardize DOIs (strip protocols, prefixes, and trailing slashes)
clean_doi <- function(doi_vec) {
  doi_clean <- tolower(trimws(as.character(doi_vec)))
  doi_clean <- str_remove(doi_clean, "^https?://(dx\\.)?doi\\.org/")
  doi_clean <- str_remove(doi_clean, "^doi:")
  doi_clean <- str_remove(doi_clean, "/+$")
  doi_clean[doi_clean == "" | is.na(doi_clean) | doi_clean == "na"] <- NA_character_
  return(doi_clean)
}

#' Normalize title strings for fuzzy string matching
clean_title <- function(title_vec) {
  t_clean <- tolower(as.character(title_vec))
  t_clean <- str_replace_all(t_clean, "[[:punct:]]", " ")
  t_clean <- str_replace_all(t_clean, "[[:space:]]+", " ")
  t_clean <- str_trim(t_clean)
  t_clean[t_clean == "" | is.na(t_clean)] <- NA_character_
  return(t_clean)
}

#' Return longest non-empty string in vector (for journal/abstract merging)
max_str <- function(vec) {
  vec <- na.omit(vec)
  vec <- vec[vec != "" & vec != "Unknown Author" & vec != "Unknown Journal"]
  if (length(vec) == 0) return("")
  vec[which.max(nchar(vec))]
}

#' Safe OpenAlex API query wrapper with automated HTTP 429 retry backoff
oa_fetch_retry <- function(..., max_retries = 3, sleep_sec = 5.0) {
  for (attempt in seq_len(max_retries)) {
    res <- tryCatch(
      {
        oa_fetch(...)
      },
      error = function(e) {
        if (str_detect(e$message, "429|Too Many Requests")) {
          wait_time <- sleep_sec * attempt
          message(sprintf("      [OpenAlex 429 Limit] Pausing %.1f seconds before retry (Attempt %d/%d)...", wait_time, attempt, max_retries))
          Sys.sleep(wait_time)
          return(NULL)
        }
        return(tibble())
      }
    )
    if (!is.null(res) && is.data.frame(res) && nrow(res) > 0) return(res)
  }
  return(tibble())
}

#' Extract author names from OpenAlex authorships
parse_openalex_authors <- function(authorships_list) {
  if (is.null(authorships_list) || length(authorships_list) == 0) {
    return("Unknown Author")
  }
  map_chr(authorships_list, function(x) {
    if (!is.data.frame(x)) return("Unknown Author")
    a_names <- if ("author_display_name" %in% names(x)) x$author_display_name else x$display_name %||% "Unknown Author"
    paste(na.omit(a_names), collapse = "; ")
  })
}

# ------------------------------------------------------------------------------
# 2. INGESTION FUNCTIONS: SCOPUS & OPENALEX
# ------------------------------------------------------------------------------

#' Query Elsevier Scopus API: TITLE-ABS-KEY((Topic_OR_Terms) AND (Geo_OR_Terms))
fetch_scopus_data <- function(search_topics, geo_terms, start_year, max_records = 5000) {
  sc_key <- Sys.getenv("ELSEVIER_SCOPUS_KEY")
  if (sc_key == "") {
    cat("   -> [Scopus] Key not found in environment (ELSEVIER_SCOPUS_KEY); skipping Scopus.\n")
    return(tibble())
  }
  set_api_key(sc_key)
  
  clean_geos <- str_replace_all(geo_terms, '^"|"$', '')
  geo_scopus_str <- paste(sprintf('"%s"', clean_geos), collapse = " OR ")
  
  map_dfr(names(search_topics), function(category) {
    kw_vec <- search_topics[[category]]
    clean_kws <- str_replace_all(kw_vec, '^"|"$', '')
    kw_str <- paste(sprintf('"%s"', clean_kws), collapse = " OR ")
    
    scopus_q <- sprintf('TITLE-ABS-KEY((%s) AND (%s)) AND PUBYEAR > %d', kw_str, geo_scopus_str, start_year - 1)
    
    cat(sprintf("   -> [Scopus] Querying topic: %s (max limit: %d records)\n", category, max_records))
    Sys.sleep(0.3)
    
    tryCatch({
      res <- scopus_search(query = scopus_q, max_count = max_records, count = 10, verbose = FALSE)
      if (is.null(res$entries) || length(res$entries) == 0) return(tibble())
      
      map_dfr(res$entries, function(x) {
        tibble(
          database = "Scopus", query_category = category,
          scopus_id = x$`dc:identifier` %||% NA_character_, openalex_id = NA_character_,
          title = x$`dc:title` %||% NA_character_, journal = x$`prism:publicationName` %||% "Unknown Journal",
          publication_year = as.integer(str_extract(x$`prism:coverDate` %||% "", "^\\d{4}")),
          doi = x$`prism:doi` %||% NA_character_, citations = as.numeric(x$`citedby-count` %||% 0),
          abstract = x$`prism:description` %||% "", authors = x$`dc:creator` %||% "Unknown Author"
        )
      })
    }, error = function(e) tibble())
  })
}

#' Query OpenAlex API: 1 single combined query per topic category (minimizes HTTP calls by 95%)
fetch_openalex_data <- function(search_topics, geo_terms, start_year, max_pages = 5) {
  oa_key <- Sys.getenv("OPENALEX_KEY")
  if (oa_key != "") {
    options(openalexR.apikey = oa_key)
  }
  
  clean_geos <- str_replace_all(geo_terms, '^"|"$', '')
  geo_or_str <- paste(sprintf('"%s"', clean_geos), collapse = " OR ")
  
  map_dfr(names(search_topics), function(category) {
    kw_vec <- search_topics[[category]]
    clean_kws <- str_replace_all(kw_vec, '^"|"$', '')
    cat(sprintf("   -> [OpenAlex] Querying topic category: %s (max pages: %d, 200 items/page)\n", category, max_pages))
    
    kw_or_str <- paste(sprintf('"%s"', clean_kws), collapse = " OR ")
    query_str <- sprintf('(%s) AND (%s)', kw_or_str, geo_or_str)
    
    Sys.sleep(0.3)
    
    block_res <- oa_fetch_retry(
      entity = "works",
      search = query_str,
      from_publication_date = sprintf("%d-01-01", start_year),
      pages = 1:max_pages,
      per_page = 200,
      api_key = oa_key,
      verbose = FALSE
    )
    
    if (is.null(block_res) || nrow(block_res) == 0) return(tibble())
    block_res <- block_res %>% distinct(id, .keep_all = TRUE)
    
    authors_vec <- parse_openalex_authors(block_res$authorships)
    
    block_res %>%
      mutate(
        database = "OpenAlex", query_category = category,
        scopus_id = NA_character_, openalex_id = id,
        title = if ("title" %in% names(.)) title else display_name,
        journal = ifelse(is.na(source_display_name), "Unknown Journal", source_display_name),
        publication_year = as.integer(publication_year), doi = doi,
        citations = as.numeric(cited_by_count %||% 0), abstract = ifelse(is.na(abstract), "", abstract),
        authors = authors_vec
      ) %>%
      select(database, query_category, scopus_id, openalex_id, title, journal, publication_year, doi, citations, abstract, authors)
  })
}

# ------------------------------------------------------------------------------
# 3. 2-STAGE HYBRID DEDUPLICATION FUNCTION
# ------------------------------------------------------------------------------

#' Perform Stage 1 (Clean DOI Exact) and Stage 2 (Normalized Title Jaro-Winkler) Deduplication
deduplicate_records <- function(df) {
  if (nrow(df) == 0) return(df)
  
  df <- df %>% mutate(clean_doi_key = clean_doi(doi), norm_title = clean_title(title), publication_year = as.integer(publication_year))
  
  has_doi <- df %>% filter(!is.na(clean_doi_key))
  no_doi  <- df %>% filter(is.na(clean_doi_key))
  
  # Stage 1: Exact Clean DOI collapse
  merged_doi <- has_doi %>%
    group_by(clean_doi_key) %>%
    summarise(
      database = paste(sort(unique(database)), collapse = "; "),
      scopus_id = coalesce(first(na.omit(scopus_id)), NA_character_),
      openalex_id = coalesce(first(na.omit(openalex_id)), NA_character_),
      title = first(na.omit(title)), journal = max_str(journal),
      publication_year = first(na.omit(publication_year)), doi = coalesce(first(na.omit(doi)), first(clean_doi_key)),
      citations = max(citations, na.rm = TRUE), abstract = max_str(abstract),
      authors = max_str(authors), norm_title = first(norm_title),
      query_category = paste(sort(unique(query_category)), collapse = "; "),
      .groups = "drop"
    )
  
  # Stage 2: Normalized Title Jaro-Winkler distance matching
  candidates <- bind_rows(merged_doi, no_doi)
  n <- nrow(candidates)
  
  if (n > 1) {
    dist_mat <- stringdistmatrix(candidates$norm_title, candidates$norm_title, method = "jw", p = 0.1)
    dup_group <- seq_len(n)
    
    for (i in seq_len(n - 1)) {
      for (j in (i + 1):n) {
        y_i <- candidates$publication_year[i]; y_j <- candidates$publication_year[j]
        same_year <- is.na(y_i) || is.na(y_j) || abs(y_i - y_j) <= 1
        if (!is.na(dist_mat[i, j]) && dist_mat[i, j] <= 0.12 && same_year) dup_group[j] <- dup_group[i]
      }
    }
    candidates$dup_group <- dup_group
  } else {
    candidates$dup_group <- 1
  }
  
  candidates %>%
    group_by(dup_group) %>%
    summarise(
      database = paste(sort(unique(unlist(str_split(database, "; ")))), collapse = "; "),
      scopus_id = coalesce(first(na.omit(scopus_id)), NA_character_),
      openalex_id = coalesce(first(na.omit(openalex_id)), NA_character_),
      title = first(na.omit(title)), journal = max_str(journal),
      publication_year = first(na.omit(publication_year)), doi = coalesce(first(na.omit(doi)), first(na.omit(clean_doi_key))),
      citations = max(citations, na.rm = TRUE), abstract = max_str(abstract),
      authors = max_str(authors),
      query_category = paste(sort(unique(unlist(str_split(query_category, "; ")))), collapse = "; "),
      .groups = "drop"
    ) %>% select(-dup_group)
}

# ------------------------------------------------------------------------------
# 4. MASTER EXECUTION FUNCTION: run_scoping_review()
# ------------------------------------------------------------------------------

run_scoping_review <- function(search_topics, geo_terms, start_year = 2020, max_scopus_records = 5000, max_openalex_pages = 5, output_dir = "outputs") {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  
  cat("\n=================================================================\n")
  cat("1. STEP 1: Fetching Records from Scopus & OpenAlex\n")
  cat("=================================================================\n")
  scopus_raw <- fetch_scopus_data(search_topics, geo_terms, start_year, max_records = max_scopus_records)
  openalex_raw <- fetch_openalex_data(search_topics, geo_terms, start_year, max_pages = max_openalex_pages)
  combined_raw <- bind_rows(scopus_raw, openalex_raw)
  
  cat(sprintf("   -> Raw Records Retrieved: %d (Scopus: %d | OpenAlex: %d)\n", nrow(combined_raw), nrow(scopus_raw), nrow(openalex_raw)))
  
  if (nrow(combined_raw) == 0) {
    message("[Notice] No records found. Please check search terms or network connection.")
    return(tibble())
  }
  
  cat("\n=================================================================\n")
  cat("2. STEP 2: Harmonizing & Deduplicating Records\n")
  cat("=================================================================\n")
  clean_data <- deduplicate_records(combined_raw)
  cat(sprintf("   -> Clean Dataset: %d unique records (Merged %d duplicates)\n", nrow(clean_data), nrow(combined_raw) - nrow(clean_data)))
  
  main_csv <- file.path(output_dir, "scoping_review_dataset.csv")
  write.csv(clean_data, main_csv, row.names = FALSE)
  
  cat("\n=================================================================\n")
  cat(sprintf("SUCCESS! Pipeline Complete. Main dataset saved to:\n  %s\n", main_csv))
  cat("=================================================================\n\n")
  
  return(clean_data)
}
