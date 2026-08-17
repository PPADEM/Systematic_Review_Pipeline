# Automated Systematic & Scoping Literature Review Pipeline in R

An automated, user-friendly R pipeline for conducting systematic and scoping literature reviews across **Elsevier Scopus** and **OpenAlex** bibliographic databases.

## 🎯 What This Tool Does

This pipeline automates the labor-intensive initial stages of a systematic literature review:

1. **Constructs Boolean API Queries**: Combines your thematic search keywords and geographic filters using precise boolean logic across both Scopus and OpenAlex.
2. **Queries Scopus & OpenAlex**: Programmatically retrieves academic publications, handling pagination and rate limits automatically.
3. **Harmonizes Metadata**: Standardizes schemas across both databases into a single clean format.
4. **Performs 2-Stage Deduplication**: Merges duplicate papers across databases using exact DOI matching and fuzzy title string matching.
5. **Exports Customizable Datasets**: Saves structured CSV datasets with custom filenames (allowing multiple review runs in a single script).

## 🔍 How the Search Logic Works

Understanding how your search parameters are built into API queries:

### 1. Topic Keywords (`OR` or `AND` Logic)

Keywords grouped inside each topic category in `SEARCH_TOPICS` are joined together using the `topic_operator` setting (`"OR"` for general search, `"AND"` for targeted strict search):
> **OR Mode** (default): `("political party" OR "party organization" OR "party decline")`
> **AND Mode**: `("political party" AND "party organization" AND "party decline")`

### 2. Geographic Terms (`OR` Logic)

Geographic terms in `GEO_TERMS` are always joined together with **`OR`** operators:
> `("Africa" OR "Sub-Saharan Africa" OR "West Africa")`

### 3. Combining Topics & Geography (`AND` Logic)

The pipeline joins the topic group and the geographic group together using an **`AND`** operator, and restricts results by publication year:

```
Final Query = (Topic Keywords [OR/AND]) AND (Geographic Terms [OR]) AND PUBYEAR >= START_YEAR
```

**Scopus & OpenAlex Query Example (`TOPIC_OPERATOR = "OR"`)**:
> `(("political party" OR "party decline") AND ("Africa" OR "Sub-Saharan Africa")) AND PUBYEAR >= 2020`

## ⚙️ Quick Start Guide

### 1. Prerequisites & Installation

Install the required R packages (R version 4.1+ recommended):

```r
install.packages(c(
  "rscopus",
  "openalexR",
  "dplyr",
  "purrr",
  "stringr",
  "tidyr",
  "tibble",
  "stringdist"
))
```

### 2. API Key Setup

Store your API keys in your user R environment file (`~/.Renviron`). This allows R to automatically authenticate your queries without hardcoding keys in your script:

Add the following lines to `~/.Renviron`:

```env
OPENALEX_KEY="your_openalex_api_key"
ELSEVIER_SCOPUS_KEY="your_scopus_api_key"
```

## 🛠️ Customizing & Running Multiple Reviews in One Script

You can call `run_scoping_review()` multiple times in a single R script by providing custom `output_filename` parameters:

```r
source("R/pipeline_functions.R")

# Run 1: General Broad Search (saved to outputs/general_search.csv)
general_data <- run_scoping_review(
  search_topics   = list(party = c("political party", "party decline")),
  geo_terms       = c("Africa", "Sub-Saharan Africa"),
  start_year      = 2020,
  topic_operator  = "OR",
  output_filename = "general_search.csv"
)

# Run 2: Targeted Strict Search (saved to outputs/targeted_search.csv)
targeted_data <- run_scoping_review(
  search_topics   = list(clientelism = c("clientelism", "political party")),
  geo_terms       = c("Africa", "Sub-Saharan Africa"),
  start_year      = 2020,
  topic_operator  = "AND",
  output_filename = "targeted_search.csv"
)
```

## 🚀 Execution

Execute the script directly from your terminal or Positron/RStudio console:

```bash
Rscript api_pipeline.R
```

## 📊 Output File Schema

Outputs are exported to `outputs/<output_filename>`:

| Column Name | Description | Example |
|:-----------------------|:-----------------------|:-----------------------|
| `database` | Provenance database source(s) | `Scopus; OpenAlex` |
| `query_category` | Thematic search category | `party_linkages` |
| `scopus_id` | Scopus record identifier | `2-s2.0-85123456789` |
| `openalex_id` | OpenAlex work URI | `https://openalex.org/W4323539164` |
| `title` | Article title | `Parties, Political Finance, and Representation` |
| `journal` | Source journal / publication name | `Journal of Modern African Studies` |
| `publication_year` | Year of publication | `2023` |
| `doi` | Standardized DOI | `10.1017/s0022278x2300001` |
| `citations` | Highest reported citation count | `14` |
| `abstract` | Full article text abstract | `This article examines...` |
| `authors` | Semicolon-separated list of author names | `Smith, J.; Kwame, A.` |
