# Automated Systematic & Scoping Literature Review Pipeline in R

An automated, user-friendly R pipeline for conducting systematic and scoping literature reviews across **Elsevier Scopus** and **OpenAlex** bibliographic databases.

## 🎯 What This Tool Does

This pipeline automates the labor-intensive initial stages of a systematic literature review:

1. **Constructs Boolean API Queries**: Combines your thematic search keywords and geographic filters using precise boolean logic.
2. **Queries Scopus & OpenAlex**: Programmatically retrieves academic publications, handling pagination and rate limits automatically.
3. **Harmonizes Metadata**: Standardizes schemas across both databases into a single clean format.
4. **Performs 2-Stage Deduplication**: Merges duplicate papers across databases using exact DOI matching and fuzzy title string matching.
5. **Exports Ready-to-Analyze Data**: Writes a clean, structured CSV dataset to `outputs/scoping_review_dataset.csv`.

## 🔍 How the Search Logic Works

Understanding how your search parameters are built into API queries:

### 1. Topic Keywords (`OR` Logic)

Keywords grouped inside each topic category in `SEARCH_TOPICS` are joined together with **`OR`** operators:
> `("political party" OR "party organization" OR "party decline")`

### 2. Geographic Terms (`OR` Logic)

Geographic terms in `GEO_TERMS` are joined together with **`OR`** operators:
> `("Africa" OR "Sub-Saharan Africa" OR "West Africa")`

### 3. Combining Topics & Geography (`AND` Logic)

The pipeline joins the topic group and the geographic group together using an **`AND`** operator, and restricts results by publication year:

$$\text{Final Query} = \Big( \text{Keyword}_1 \text{ OR } \text{Keyword}_2 \text{ OR } \dots \Big) \mathbf{\text{ AND }} \Big( \text{GeoTerm}_1 \text{ OR } \text{GeoTerm}_2 \text{ OR } \dots \Big) \mathbf{\text{ AND }} \text{PUBYEAR} \ge \text{START\_YEAR}$$

**Scopus Query Example**: `TITLE-ABS-KEY(("political party" OR "party decline") AND ("Africa" OR "Sub-Saharan Africa")) AND PUBYEAR > 2019`

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

- **OpenAlex Key**: Get a free API key at [OpenAlex.org](https://openalex.org) (unlocks 100,000 queries/day).
- **Scopus Key**: Provided by your university library or Elsevier developer portal. *(If omitted, the pipeline skips Scopus and runs cleanly on OpenAlex)*.

## 🛠️ Customizing `api_pipeline.R`

All user settings are configured at the top of [`api_pipeline.R`](file:///Users/jt17630/Documents/PPADEM/Code/Systematic_Review_Pipeline/api_pipeline.R):

```r
# 1. Define Search Topics & Keywords
SEARCH_TOPICS <- list(
  party_linkages = c(
    "political party", "party organization", "party linkage", "party decline"
  )
)

# 2. Define Geographic Filter Terms
GEO_TERMS <- c("Africa", "Sub-Saharan Africa", "West Africa", "East Africa")

# 3. Define Year Cutoff and Retrieval Limits
START_YEAR          <- 2020  # Publication year cutoff (2020 onward)
MAX_SCOPUS_RECORDS  <- 5000  # Max total records to fetch per topic from Scopus
MAX_OPENALEX_PAGES  <- 20    # Max pages (200 records per page) from OpenAlex
```

## 🚀 Running the Pipeline

Execute the pipeline directly from your terminal or Positron/RStudio console:

```bash
Rscript api_pipeline.R
```

## 🔄 What Happens Under the Hood

When you execute `api_pipeline.R`, the system runs two main steps:

### Step 1: Ingestion & Throttling Protection

- Queries Elsevier Scopus in batches of 10 items per HTTP call (conforming to developer API rules).
- Queries OpenAlex using standard indexed fulltext search.
- Includes automatic backoff retries (`oa_fetch_retry`) to safely pause and retry if temporary API throttling occurs.

### Step 2: 2-Stage Hybrid Deduplication

- **Stage 1 (Clean DOI Exact Match)**: Standardizes DOIs (stripping `https://doi.org/`, `doi:`, trailing slashes, and lowercasing) and merges records found in both databases while tracking provenance (`database = "Scopus; OpenAlex"`).
- **Stage 2 (Title Fuzzy Match)**: Cleans title punctuation and applies Jaro-Winkler string distance matching ($\le 0.12$) constrained within $\pm 1$ publication year to merge records missing DOIs or suffering from minor title typos.

## 📊 Output File Schema

The final deduplicated dataset is saved to `outputs/scoping_review_dataset.csv`:

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

## 📁 Repository Structure

```
├── README.md               # Pipeline documentation & user guide
├── api_pipeline.R          # Simple user configuration & execution script
├── R/
│   └── pipeline_functions.R # Modular function library (fetching, deduplication, helpers)
└── outputs/
    └── scoping_review_dataset.csv # Main output dataset
```
