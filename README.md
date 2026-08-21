# Automated Systematic & Scoping Literature Review Pipeline in R

An automated, user-friendly R pipeline for conducting systematic and scoping literature reviews across **Elsevier Scopus** and **OpenAlex** bibliographic databases.

## 🎯 What This Tool Does

This pipeline automates the labor-intensive initial stages of a systematic literature review:

1. **Constructs Boolean API Queries**: Combines your thematic search keywords and geographic filters using precise boolean logic across both Scopus and OpenAlex, supporting single-category (`OR` / `AND`) or multi-block (`multi`) search modes.
2. **Queries Scopus & OpenAlex**: Programmatically retrieves academic publications, handling pagination and rate limits automatically.
3. **Harmonizes Metadata**: Standardizes schemas across both databases into a single clean format.
4. **Performs 2-Stage Deduplication**: Merges duplicate papers across databases using exact DOI matching and fuzzy title string matching.
5. **Flags Curated Target Journals**: Automatically checks each paper's journal against a reference list of ~121 top Political Science, Administrative, and Area/African Studies journals and flags them (`Y` / `N`) in a dedicated column.
6. **Exports Customizable Datasets**: Saves structured CSV datasets directly to root or to custom subfolder paths specified in `output_filename`.

## 🔍 How the Search Logic Works

Understanding how your search parameters are built into API queries:

### 1. Topic Keywords (`OR`, `AND`, or `multi` Logic)

Keywords grouped inside each topic category in `SEARCH_TOPICS` are joined together using the `topic_operator` setting:
> **OR Mode** (default): `("political party" OR "party organization" OR "party decline")`
> **AND Mode**: `("political party" AND "party organization" AND "party decline")`
> **MULTI Mode**: Combines multiple concept blocks (e.g. `BLOCK 1` AND `BLOCK 2` AND ... AND `BLOCK N`), where terms inside each block are separated by `OR`:
> `((Block 1 terms separated by OR) AND (Block 2 terms separated by OR)) AND (GEO terms separated by OR)`

### 2. Geographic Terms (`OR` Logic)

Geographic terms in `GEO_TERMS` are always joined together with **`OR`** operators:
> `("Africa" OR "Sub-Saharan Africa" OR "West Africa")`

### 3. Combining Topics & Geography (`AND` Logic)

The pipeline joins the topic group and the geographic group together using an **`AND`** operator, and restricts results by publication year:

```
Final Query (OR/AND mode) = (Topic Keywords [OR/AND]) AND (Geographic Terms [OR]) AND PUBYEAR >= START_YEAR
Final Query (MULTI mode)  = ((Block 1 [OR]) AND (Block 2 [OR])) AND (Geographic Terms [OR]) AND PUBYEAR >= START_YEAR
```

---

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

---

## 🛠️ Customizing Output File Locations & Search Modes

By default, files are saved directly at the repository root folder. If a subfolder path is included in `output_filename`, the directory is created automatically:

```r
source("R/pipeline_functions.R")

# Run 1: General Broad Search (OR mode)
general_data <- run_scoping_review(
  search_topics   = list(party = c("political party", "party decline")),
  geo_terms       = c("Africa", "Sub-Saharan Africa"),
  start_year      = 2020,
  topic_operator  = "OR",
  output_filename = "general_search.csv"
)

# Run 2: Multi-Block Search (BLOCK 1 AND BLOCK 2 AND GEO)
multi_data <- run_scoping_review(
  search_topics   = list(
    parties = c("political party", "party organization"),
    communication = c("communication", "meeting", "social media")
  ),
  geo_terms       = c("Africa", "Sub-Saharan Africa"),
  start_year      = 2020,
  topic_operator  = "multi",
  output_filename = "outputs/multi_block_search.csv"
)
```

## 🚀 Execution

Execute the script directly from your terminal or Positron/RStudio console:

```bash
Rscript api_pipeline_example.R
```

---

## 📊 Output File Schema

Outputs are exported to the location specified in `output_filename`:

| Column Name | Description | Example |
|:-----------------------|:-----------------------|:-----------------------|
| `database` | Provenance database source(s) | `Scopus; OpenAlex` |
| `query_category` | Thematic search category or multi-block combination | `party_linkages` or `party_block & communication_block` |
| `scopus_id` | Scopus record identifier | `2-s2.0-85123456789` |
| `openalex_id` | OpenAlex work URI | `https://openalex.org/W4323539164` |
| `title` | Article title | `Parties, Political Finance, and Representation` |
| `journal` | Source journal / publication name | `Journal of Modern African Studies` |
| `publication_year` | Year of publication | `2023` |
| `doi` | Standardized DOI | `10.1017/s0022278x2300001` |
| `citations` | Highest reported citation count | `14` |
| `abstract` | Full article text abstract | `This article examines...` |
| `authors` | Semicolon-separated list of author names | `Smith, J.; Kwame, A.` |
| `target_journal` | Flag (`Y`/`N`) indicating if journal matches curated political science/administrative/African studies list | `Y` |
