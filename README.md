# Automated Systematic & Scoping Literature Review Pipeline in R

This repository provides an automated R pipeline for conducting systematic and scoping literature reviews. It programmatically queries **Elsevier Scopus** and **OpenAlex** APIs, harmonizes metadata fields, and performs 2-stage deduplication to export a clean, structured dataset for downstream analysis.

---

## 📋 Prerequisites & Installation

Ensure you have R (version 4.1 or higher) installed along with the following packages:

```R
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

---

## ⚙️ User Guide: How to Customize `api_pipeline.R`

All user inputs and search parameters are defined at the top of [`api_pipeline.R`](file:///Users/jt17630/Documents/PPADEM/Code/Systematic_Review_Pipeline/api_pipeline.R). Customize the settings below for your review:

### 1. API Credentials Setup

- **OpenAlex Email (Required for Polite Pool)**:
  Set your email address to use OpenAlex's fast "polite pool":
  ```R
  options(openalexR.mailto = "josh.tyler@bristol.ac.uk")
  ```

- **Scopus API Key (Optional)**:
  If your institution has Scopus API access, set your API key as an environment variable or uncomment line 14:
  ```R
  Sys.setenv(ELSEVIER_SCOPUS_KEY = "your_32_character_api_key")
  ```
  *(If no Scopus key is set, the pipeline automatically skips Scopus queries and executes cleanly on OpenAlex).*

### 2. Setting Date Cutoff

- `start_year`: Publication cutoff year (e.g., `2020` retrieves works published from 2020 onward).

### 3. Setting Geographic Filter Terms (`GEO_TERMS`)

`GEO_TERMS` filters search results geographically across database APIs.

- **Continental Review**: `GEO_TERMS <- c("Africa", "Sub-Saharan Africa", "North Africa")`
- **Regional Bloc Review**: `GEO_TERMS <- c("ECOWAS", "West Africa", "Nigeria", "Ghana")`
- **Single Country Review**: `GEO_TERMS <- c("Kenya", "Kenyan")`

### 4. Search Topics & Keywords (`SEARCH_TOPICS`)

Group your search terms into named thematic categories. Terms within each category are queried using boolean `OR` logic:

```R
SEARCH_TOPICS <- list(
  party_linkages = c(
    "political party", "party organization", "party linkage", 
    "party system", "candidate selection", "party decline"
  ),
  constituency_representation = c(
    "constituency service", "constituency focus", "constituency work", 
    "home style", "district focus", "local representation"
  ),
  responsiveness_patronage = c(
    "service responsiveness", "clientelism", "patronage", 
    "constituency development fund", "particularistic"
  )
)
```

---

## 🚀 Running the Script

Run the pipeline directly from your terminal or R console:

```bash
Rscript api_pipeline.R
```

---

## 🛠️ Pipeline Function Reference (`R/pipeline_functions.R`)

All heavy-lifting functional elements are encapsulated inside [`R/pipeline_functions.R`](file:///Users/jt17630/Documents/PPADEM/Code/Systematic_Review_Pipeline/R/pipeline_functions.R):

| Function | Description |
| :--- | :--- |
| `fetch_scopus_data()` | Queries Elsevier Scopus API across search topics and geographic terms. |
| `fetch_openalex_data()` | Queries OpenAlex API with rate-limit retry backoff (`oa_fetch_retry`). |
| `parse_openalex_authors()` | Parses semicolon-separated author names. |
| `deduplicate_records()` | **2-Stage Hybrid Deduplication**: Stage 1 exact Clean DOI collapse + Stage 2 Jaro-Winkler title fuzzy distance matching ($\le 0.12$, $\pm 1$ year). |
| `run_scoping_review()` | **Master Function**. Orchestrates ingestion, deduplication, and exports the clean dataset. |

---

## 📂 Output Files Reference

All generated outputs are exported to the `outputs/` directory:

| Output File | Description |
| :--- | :--- |
| `outputs/scoping_review_dataset.csv` | **Primary Clean Dataset**. Contains DOI, title, journal, year, citations, authors, abstract, query category, and database source. |

---

## 🗺️ Strategic Roadmap for Downstream Analysis

1. **Geographic Scale Tagging**: Distinguishes study focus location (*Continental*, *Regional (e.g. ECOWAS, SADC)*, or *Country-Specific*) using title and abstract gazetteer matching.
2. **Thematic Filtering**: Excludes non-political false positives using OpenAlex Concept Filtering, Structural Topic Modeling (`stm`), and negative vocabulary lists.
3. **PRISMA-ScR & Bibliometrics**: Integrates `PRISMA2020` flow diagrams and `bibliometrix` co-authorship & co-word network maps.
