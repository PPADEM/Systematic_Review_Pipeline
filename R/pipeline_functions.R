# ==============================================================================
# FUNCTION LIBRARY: AUTOMATED BIBLIOGRAPHIC SCOPING REVIEWS
# ==============================================================================
# Contains core pipeline functions: Scopus & OpenAlex dual-API fetching,
# rate-limit retry logic, schema harmonization, 2-stage hybrid deduplication,
# multi-block search logic, and target journal list matching.
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
  library(africamonitor)
})

#### 1. CURATED TARGET JOURNALS ####

TARGET_JOURNALS <- c(
  # Political Science journals
  "Acta Politica",
  "American Journal of Political Science",
  "American Political Science Review",
  "American Politics Research",
  "Annals of the American Academy of Political and Social Science",
  "Annual Review of Political Science",
  "British Journal of Political Science",
  "British Journal of Politics and International Relations",
  "Comparative Political Studies",
  "Comparative Politics",
  "Democratization",
  "Electoral Studies",
  "European Journal of International Relations",
  "European Journal of Political Research",
  "European Policy Analysis",
  "European Political Science",
  "European Political Science Review",
  "Frontiers in Political Science",
  "Government and Opposition",
  "Government Information Quarterly",
  "International Affairs",
  "International Journal of Press/Politics",
  "International Journal of Public Opinion Research",
  "International Organization",
  "International Political Science Review",
  "International Studies Quarterly",
  "International Studies Review",
  "Journal of Comparative Policy Analysis: Research and Practice",
  "Journal of Deliberative Democracy",
  "Journal of Democracy",
  "Journal of Elections, Public Opinion and Parties",
  "Journal of Experimental Political Science",
  "Journal of Politics",
  "Party Politics",
  "Perspectives on Politics",
  "Political Analysis",
  "Political Behavior",
  "Political Communication",
  "Political Geography",
  "Political Psychology",
  "Political Quarterly",
  "Political Research Quarterly",
  "Political Science Quarterly",
  "Political Science Research and Methods",
  "Political Studies",
  "Political Studies Review",
  "Politics",
  "Politics & Gender",
  "Politics and Gender",
  "Politics and Governance",
  "PS - Political Science and Politics",
  "PS: Political Science & Politics",
  "PS: Political Science and Politics",
  "Representation",
  "Social Science Quarterly",
  "Territory, Politics, Governance",
  "West European Politics",
  "World Development",
  "World Politics",

  # Administrative Journals
  "Administration and Society",
  "Administration & Society",
  "American Review of Public Administration",
  "Conflict Management and Peace Science",
  "Earth System Governance",
  "Environmental Politics",
  "Geopolitics",
  "Global Policy",
  "Global Studies Quarterly",
  "Globalizations",
  "Governance",
  "International Environmental Agreements: Politics, Law and Economics",
  "International Review of Administrative Sciences",
  "Journal of Environmental Policy and Planning",
  "Journal of Ethnic and Migration Studies",
  "Journal of European Integration",
  "Journal of European Public Policy",
  "Journal of Health Politics, Policy and Law",
  "Journal of Peace Research",
  "Journal of Public Administration Research and Theory",
  "Journal of Social Policy",
  "Local Government Studies",
  "Marine Policy",
  "New Political Economy",
  "Policy and Politics",
  "Policy & Politics",
  "Policy and Society",
  "Policy Sciences",
  "Policy Studies Journal",
  "Public Administration",
  "Public Administration Review",
  "Public Choice",
  "Public Money and Management",
  "Public Money & Management",
  "Public Opinion Quarterly",
  "Public Performance & Management Review",
  "Public Performance and Management Review",
  "Public Policy and Administration",
  "Publius",
  "Publius: The Journal of Federalism",
  "Regional Studies",
  "Regulation and Governance",
  "Regulation & Governance",
  "Research and Politics",
  "Research & Politics",
  "Review of International Organizations",
  "Review of International Political Economy",
  "Review of Policy Research",
  "Review of Public Personnel Administration",
  "Social Policy and Administration",
  "Social Policy & Administration",

  # Area Studies/African Studies+
  "Africa Development",
  "Africa Spectrum",
  "Africa Today",
  "Africa: The Journal of the International African Institute",
  "African Affairs",
  "African Journal of Political Science",
  "African Studies Quarterly",
  "African Studies Review",
  "Canadian Journal of African Studies",
  "Commonwealth and Comparative Politics",
  "Commonwealth & Comparative Politics",
  "Critical African Studies",
  "Journal of Asian and African Studies",
  "Journal of Contemporary African Studies",
  "Nordic Journal of African Studies",
  "Politeia",
  "Politikon: South African Journal of Political Studies",
  "Politikon",
  "Review of African Political Economy",
  "The Journal Modern African Studies",
  "The Journal of Modern African Studies",
  "Journal of Modern African Studies",
  "Third World Quarterly",
  "The Journal of African Elections",
  "Journal of African Elections",
  "Journal of Southern African Studies",
  "Journal of East African Studies"
)

#### 2. HELPER & CLEANING UTILITIES ####

#' Standardize DOIs (strip protocols, prefixes, and trailing slashes)
clean_doi <- function(doi_vec) {
  doi_clean <- tolower(trimws(as.character(doi_vec)))
  doi_clean <- str_remove(doi_clean, "^https?://(dx\\.)?doi\\.org/")
  doi_clean <- str_remove(doi_clean, "^doi:")
  doi_clean <- str_remove(doi_clean, "/+$")
  doi_clean[
    doi_clean == "" | is.na(doi_clean) | doi_clean == "na"
  ] <- NA_character_
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

#' Normalize journal names for exact matching against target journal list
clean_journal_name <- function(journal_vec) {
  j_clean <- tolower(as.character(journal_vec))
  j_clean <- str_replace_all(j_clean, "&", " and ")
  j_clean <- str_replace_all(j_clean, "[[:punct:]]", " ")
  j_clean <- str_replace_all(j_clean, "[[:space:]]+", " ")
  j_clean <- str_trim(j_clean)
  return(j_clean)
}

#' Return longest non-empty string in vector (for journal/abstract merging)
max_str <- function(vec) {
  vec <- na.omit(vec)
  vec <- vec[vec != "" & vec != "Unknown Author" & vec != "Unknown Journal"]
  if (length(vec) == 0) {
    return("")
  }
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
          message(sprintf(
            "      [OpenAlex 429 Limit] Pausing %.1f seconds before retry (Attempt %d/%d)...",
            wait_time,
            attempt,
            max_retries
          ))
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
    if (!is.data.frame(x)) {
      return("Unknown Author")
    }
    a_names <- if ("author_display_name" %in% names(x)) {
      x$author_display_name
    } else {
      x$display_name %||% "Unknown Author"
    }
    paste(na.omit(a_names), collapse = "; ")
  })
}

#### 3. INGESTION FUNCTIONS: SCOPUS & OPENALEX ####

#' Query Elsevier Scopus API: TITLE-ABS-KEY((Topic_Keywords_Op) AND (Geo_OR_Terms))
fetch_scopus_data <- function(
  search_topics,
  geo_terms = NULL,
  start_year = 2020,
  topic_operator = "OR",
  max_records = 5000
) {
  sc_key <- Sys.getenv("ELSEVIER_SCOPUS_KEY")
  if (sc_key == "") {
    cat(
      "   -> [Scopus] Key not found in environment (ELSEVIER_SCOPUS_KEY); skipping Scopus.\n"
    )
    return(tibble())
  }
  set_api_key(sc_key)

  run_date <- as.character(Sys.Date())

  op <- toupper(trimws(topic_operator))
  if (!op %in% c("OR", "AND", "MULTI")) {
    op <- "OR"
  }

  has_geo <- !is.null(geo_terms) && length(geo_terms) > 0 && any(nchar(trimws(geo_terms)) > 0)
  if (has_geo) {
    clean_geos <- str_replace_all(geo_terms[nchar(trimws(geo_terms)) > 0], '^"|"$', '')
    geo_scopus_str <- paste(sprintf('"%s"', clean_geos), collapse = " OR ")
  }

  if (op == "MULTI") {
    # Multi-block mode: combine ALL blocks in search_topics with AND, terms within each block with OR
    block_strs <- map_chr(names(search_topics), function(block_name) {
      kw_vec <- search_topics[[block_name]]
      clean_kws <- str_replace_all(kw_vec, '^"|"$', '')
      paste0("(", paste(sprintf('"%s"', clean_kws), collapse = " OR "), ")")
    })

    combined_topic_str <- paste(block_strs, collapse = " AND ")
    if (has_geo) {
      scopus_q <- sprintf(
        'TITLE-ABS-KEY((%s) AND (%s)) AND PUBYEAR > %d',
        combined_topic_str,
        geo_scopus_str,
        start_year - 1
      )
    } else {
      scopus_q <- sprintf(
        'TITLE-ABS-KEY(%s) AND PUBYEAR > %d',
        combined_topic_str,
        start_year - 1
      )
    }
    category_name <- paste(names(search_topics), collapse = " & ")

    cat(sprintf(
      "   -> [Scopus] Querying multi-block topics: %s (max limit: %d records)\n",
      category_name,
      max_records
    ))
    Sys.sleep(0.3)

    tryCatch(
      {
        res <- scopus_search(
          query = scopus_q,
          max_count = max_records,
          count = 10,
          verbose = FALSE
        )
        if (is.null(res$entries) || length(res$entries) == 0) {
          return(tibble())
        }

        map_dfr(res$entries, function(x) {
          tibble(
            database = "Scopus",
            query_category = category_name,
            search_query = scopus_q,
            search_date = run_date,
            scopus_id = x$`dc:identifier` %||% NA_character_,
            openalex_id = NA_character_,
            title = x$`dc:title` %||% NA_character_,
            journal = x$`prism:publicationName` %||% "Unknown Journal",
            publication_year = as.integer(str_extract(
              x$`prism:coverDate` %||% "",
              "^\\d{4}"
            )),
            doi = x$`prism:doi` %||% NA_character_,
            citations = as.numeric(x$`citedby-count` %||% 0),
            abstract = x$`prism:description` %||% "",
            authors = x$`dc:creator` %||% "Unknown Author"
          )
        })
      },
      error = function(e) tibble()
    )
  } else {
    map_dfr(names(search_topics), function(category) {
      kw_vec <- search_topics[[category]]
      clean_kws <- str_replace_all(kw_vec, '^"|"$', '')
      kw_str <- paste(
        sprintf('"%s"', clean_kws),
        collapse = sprintf(" %s ", op)
      )

      if (has_geo) {
        scopus_q <- sprintf(
          'TITLE-ABS-KEY((%s) AND (%s)) AND PUBYEAR > %d',
          kw_str,
          geo_scopus_str,
          start_year - 1
        )
      } else {
        scopus_q <- sprintf(
          'TITLE-ABS-KEY(%s) AND PUBYEAR > %d',
          kw_str,
          start_year - 1
        )
      }

      cat(sprintf(
        "   -> [Scopus] Querying topic: %s [Topic Op: %s] (max limit: %d records)\n",
        category,
        op,
        max_records
      ))
      Sys.sleep(0.3)

      tryCatch(
        {
          res <- scopus_search(
            query = scopus_q,
            max_count = max_records,
            count = 10,
            verbose = FALSE
          )
          if (is.null(res$entries) || length(res$entries) == 0) {
            return(tibble())
          }

          map_dfr(res$entries, function(x) {
            tibble(
              database = "Scopus",
              query_category = category,
              search_query = scopus_q,
              search_date = run_date,
              scopus_id = x$`dc:identifier` %||% NA_character_,
              openalex_id = NA_character_,
              title = x$`dc:title` %||% NA_character_,
              journal = x$`prism:publicationName` %||% "Unknown Journal",
              publication_year = as.integer(str_extract(
                x$`prism:coverDate` %||% "",
                "^\\d{4}"
              )),
              doi = x$`prism:doi` %||% NA_character_,
              citations = as.numeric(x$`citedby-count` %||% 0),
              abstract = x$`prism:description` %||% "",
              authors = x$`dc:creator` %||% "Unknown Author"
            )
          })
        },
        error = function(e) tibble()
      )
    })
  }
}

#' Query OpenAlex API: single combined query per topic category (or 1 multi-block query) using configurable topic_operator
fetch_openalex_data <- function(
  search_topics,
  geo_terms = NULL,
  start_year = 2020,
  topic_operator = "OR",
  max_pages = 5
) {
  oa_key <- Sys.getenv("OPENALEX_KEY")
  if (oa_key != "") {
    options(openalexR.apikey = oa_key)
  }

  run_date <- as.character(Sys.Date())

  op <- toupper(trimws(topic_operator))
  if (!op %in% c("OR", "AND", "MULTI")) {
    op <- "OR"
  }

  has_geo <- !is.null(geo_terms) && length(geo_terms) > 0 && any(nchar(trimws(geo_terms)) > 0)
  if (has_geo) {
    clean_geos <- str_replace_all(geo_terms[nchar(trimws(geo_terms)) > 0], '^"|"$', '')
    geo_or_str <- paste(sprintf('"%s"', clean_geos), collapse = " OR ")
  }

  if (op == "MULTI") {
    # Multi-block mode: combine ALL blocks in search_topics with AND, terms within each block with OR
    block_strs <- map_chr(names(search_topics), function(block_name) {
      kw_vec <- search_topics[[block_name]]
      clean_kws <- str_replace_all(kw_vec, '^"|"$', '')
      paste0("(", paste(sprintf('"%s"', clean_kws), collapse = " OR "), ")")
    })

    combined_topic_str <- paste(block_strs, collapse = " AND ")
    query_str <- if (has_geo) sprintf('(%s) AND (%s)', combined_topic_str, geo_or_str) else combined_topic_str
    category_name <- paste(names(search_topics), collapse = " & ")

    cat(sprintf(
      "   -> [OpenAlex] Querying multi-block topics: %s (max pages: %d, 200 items/page)\n",
      category_name,
      max_pages
    ))
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

    if (is.null(block_res) || nrow(block_res) == 0) {
      return(tibble())
    }
    block_res <- block_res %>% distinct(id, .keep_all = TRUE)

    authors_vec <- parse_openalex_authors(block_res$authorships)

    block_res %>%
      mutate(
        database = "OpenAlex",
        query_category = category_name,
        search_query = query_str,
        search_date = run_date,
        scopus_id = NA_character_,
        openalex_id = id,
        title = if ("title" %in% names(.)) title else display_name,
        journal = ifelse(
          is.na(source_display_name),
          "Unknown Journal",
          source_display_name
        ),
        publication_year = as.integer(publication_year),
        doi = doi,
        citations = as.numeric(cited_by_count %||% 0),
        abstract = ifelse(is.na(abstract), "", abstract),
        authors = authors_vec
      ) %>%
      select(
        database,
        query_category,
        search_query,
        search_date,
        scopus_id,
        openalex_id,
        title,
        journal,
        publication_year,
        doi,
        citations,
        abstract,
        authors
      )
  } else {
    map_dfr(names(search_topics), function(category) {
      kw_vec <- search_topics[[category]]
      clean_kws <- str_replace_all(kw_vec, '^"|"$', '')
      cat(sprintf(
        "   -> [OpenAlex] Querying topic category: %s [Topic Op: %s] (max pages: %d, 200 items/page)\n",
        category,
        op,
        max_pages
      ))

      kw_str <- paste(
        sprintf('"%s"', clean_kws),
        collapse = sprintf(" %s ", op)
      )
      query_str <- if (has_geo) sprintf('(%s) AND (%s)', kw_str, geo_or_str) else kw_str

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

      if (is.null(block_res) || nrow(block_res) == 0) {
        return(tibble())
      }
      block_res <- block_res %>% distinct(id, .keep_all = TRUE)

      authors_vec <- parse_openalex_authors(block_res$authorships)

      block_res %>%
        mutate(
          database = "OpenAlex",
          query_category = category,
          search_query = query_str,
          search_date = run_date,
          scopus_id = NA_character_,
          openalex_id = id,
          title = if ("title" %in% names(.)) title else display_name,
          journal = ifelse(
            is.na(source_display_name),
            "Unknown Journal",
            source_display_name
          ),
          publication_year = as.integer(publication_year),
          doi = doi,
          citations = as.numeric(cited_by_count %||% 0),
          abstract = ifelse(is.na(abstract), "", abstract),
          authors = authors_vec
        ) %>%
        select(
          database,
          query_category,
          search_query,
          search_date,
          scopus_id,
          openalex_id,
          title,
          journal,
          publication_year,
          doi,
          citations,
          abstract,
          authors
        )
    })
  }
}

#### 4. 2-STAGE HYBRID DEDUPLICATION FUNCTION & JOURNAL MATCHING ####

#' Perform Stage 1 (Clean DOI Exact) and Stage 2 (Normalized Title Jaro-Winkler) Deduplication,
#' and flag whether publication journal matches the target journal list.
deduplicate_records <- function(df, target_journals = TARGET_JOURNALS) {
  if (nrow(df) == 0) {
    return(df)
  }

  df <- df %>%
    mutate(
      clean_doi_key = clean_doi(doi),
      norm_title = clean_title(title),
      publication_year = as.integer(publication_year)
    )

  has_doi <- df %>% filter(!is.na(clean_doi_key))
  no_doi <- df %>% filter(is.na(clean_doi_key))

  # Stage 1: Exact Clean DOI collapse
  merged_doi <- has_doi %>%
    group_by(clean_doi_key) %>%
    summarise(
      database = paste(sort(unique(database)), collapse = "; "),
      query_category = paste(sort(unique(query_category)), collapse = "; "),
      search_query = paste(sort(unique(unlist(str_split(search_query, " \\|\\| |; ")))), collapse = " || "),
      search_date = paste(sort(unique(unlist(str_split(search_date, "; ")))), collapse = "; "),
      scopus_id = coalesce(first(na.omit(scopus_id)), NA_character_),
      openalex_id = coalesce(first(na.omit(openalex_id)), NA_character_),
      title = first(na.omit(title)),
      journal = max_str(journal),
      publication_year = first(na.omit(publication_year)),
      doi = coalesce(first(na.omit(doi)), first(clean_doi_key)),
      citations = max(citations, na.rm = TRUE),
      abstract = max_str(abstract),
      authors = max_str(authors),
      norm_title = first(norm_title),
      .groups = "drop"
    )

  # Stage 2: Normalized Title Jaro-Winkler distance matching
  candidates <- bind_rows(merged_doi, no_doi)
  n <- nrow(candidates)

  if (n > 1) {
    dist_mat <- stringdistmatrix(
      candidates$norm_title,
      candidates$norm_title,
      method = "jw",
      p = 0.1
    )
    dup_group <- seq_len(n)

    for (i in seq_len(n - 1)) {
      for (j in (i + 1):n) {
        y_i <- candidates$publication_year[i]
        y_j <- candidates$publication_year[j]
        same_year <- is.na(y_i) || is.na(y_j) || abs(y_i - y_j) <= 1
        if (!is.na(dist_mat[i, j]) && dist_mat[i, j] <= 0.12 && same_year) {
          dup_group[j] <- dup_group[i]
        }
      }
    }
    candidates$dup_group <- dup_group
  } else {
    candidates$dup_group <- 1
  }

  clean_df <- candidates %>%
    group_by(dup_group) %>%
    summarise(
      database = paste(
        sort(unique(unlist(str_split(database, "; ")))),
        collapse = "; "
      ),
      query_category = paste(
        sort(unique(unlist(str_split(query_category, "; ")))),
        collapse = "; "
      ),
      search_query = paste(
        sort(unique(unlist(str_split(search_query, " \\|\\| |; ")))),
        collapse = " || "
      ),
      search_date = paste(
        sort(unique(unlist(str_split(search_date, "; ")))),
        collapse = "; "
      ),
      scopus_id = coalesce(first(na.omit(scopus_id)), NA_character_),
      openalex_id = coalesce(first(na.omit(openalex_id)), NA_character_),
      title = first(na.omit(title)),
      journal = max_str(journal),
      publication_year = first(na.omit(publication_year)),
      doi = coalesce(first(na.omit(doi)), first(na.omit(clean_doi_key))),
      citations = max(citations, na.rm = TRUE),
      abstract = max_str(abstract),
      authors = max_str(authors),
      .groups = "drop"
    ) %>%
    select(-dup_group)

  # Flag whether journal matches curated list
  target_j_clean <- clean_journal_name(target_journals)
  clean_df <- clean_df %>%
    mutate(
      target_journal = ifelse(
        clean_journal_name(journal) %in% target_j_clean,
        "Y",
        "N"
      )
    )

  return(clean_df)
}

#### 5. MASTER EXECUTION FUNCTION: run_scoping_review() ####

run_scoping_review <- function(
  search_topics,
  geo_terms = NULL,
  start_year = 2020,
  topic_operator = "OR",
  max_scopus_records = 5000,
  max_openalex_pages = 5,
  output_filename = "scoping_review_dataset.csv"
) {
  # Ensure filename ends with .csv extension
  if (!str_detect(output_filename, "\\.csv$")) {
    output_filename <- paste0(output_filename, ".csv")
  }

  # Auto-create target directory if a relative or absolute subfolder path is passed
  target_dir <- dirname(output_filename)
  if (target_dir != "." && !dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE)
  }

  cat("\n=================================================================\n")
  cat(sprintf(
    "1. STEP 1: Fetching Records from Scopus & OpenAlex [%s]\n",
    output_filename
  ))
  cat("=================================================================\n")
  scopus_raw <- fetch_scopus_data(
    search_topics,
    geo_terms,
    start_year,
    topic_operator = topic_operator,
    max_records = max_scopus_records
  )
  openalex_raw <- fetch_openalex_data(
    search_topics,
    geo_terms,
    start_year,
    topic_operator = topic_operator,
    max_pages = max_openalex_pages
  )
  combined_raw <- bind_rows(scopus_raw, openalex_raw)

  cat(sprintf(
    "   -> Raw Records Retrieved: %d (Scopus: %d | OpenAlex: %d)\n",
    nrow(combined_raw),
    nrow(scopus_raw),
    nrow(openalex_raw)
  ))

  if (nrow(combined_raw) == 0) {
    message(
      "[Notice] No records found. Please check search terms or network connection."
    )
    return(tibble())
  }

  cat("\n=================================================================\n")
  cat("2. STEP 2: Harmonizing & Deduplicating Records\n")
  cat("=================================================================\n")
  clean_data <- deduplicate_records(combined_raw)
  cat(sprintf(
    "   -> Clean Dataset: %d unique records (Merged %d duplicates)\n",
    nrow(clean_data),
    nrow(combined_raw) - nrow(clean_data)
  ))
  cat(sprintf(
    "   -> Target Journal Matches: %d / %d records flagged as 'Y'\n",
    sum(clean_data$target_journal == "Y"),
    nrow(clean_data)
  ))

  write.csv(clean_data, output_filename, row.names = FALSE)

  cat("\n=================================================================\n")
  cat(sprintf(
    "SUCCESS! Pipeline Complete. Dataset saved to:\n  %s\n",
    output_filename
  ))
  cat("=================================================================\n\n")

  return(clean_data)
}
