# Automated Scoping Literature Review Pipeline: Political Science Research in Africa

This repository contains an automated, end-to-end literature review pipeline written in R for conducting systematic and scoping literature reviews. It queries, merges, harmonizes, and deduplicates bibliographic records across **Elsevier Scopus** and **OpenAlex** APIs, with a specific focus on **Political Science research in Africa** (continental, regional, and country-specific scales).

---

## 🌟 Key Features

1. **Dual-API Ingestion (Scopus + OpenAlex)**:
   - Integrates both Elsevier Scopus (`rscopus`) and OpenAlex (`openalexR`) databases simultaneously to ensure maximum bibliographic coverage.
   - Built-in rate-limit resilience with automated exponential backoff retries (`oa_fetch_with_retry`) to handle HTTP 429 throttling.

2. **2-Stage Hybrid Deduplication Algorithm**:
   - **Stage 1 (Clean DOI Matching)**: Standardizes DOIs (stripping protocol prefixes, `doi:` tags, and trailing slashes) and merges records present in both databases while tracking provenance (`database = "Scopus; OpenAlex"`).
   - **Stage 2 (Normalized Fuzzy Title Matching)**: Normalizes titles (lowercasing, stripping punctuation/whitespace) and applies Jaro-Winkler string distance matching (`threshold <= 0.12`) constrained within $\pm 1$ publication year to merge records missing DOIs or suffering from minor spelling/punctuation variations.

3. **Author Geographic Metadata Extraction**:
   - Captures author institutional country codes (`author_countries`, e.g., `ZA; GB; US`) and institutional affiliations directly from OpenAlex and Scopus schemas, enabling downstream analysis of Global South vs. Global North co-authorship.

4. **Contextual Sentence Extraction**:
   - Extracts the exact $\sim 300$-character text windows surrounding target terms within abstracts to immediately analyze conceptual definitions across authors.

5. **Citation Snowballing & Resolution**:
   - Resolves OpenAlex IDs for top-impact papers (even those originating from Scopus via DOI lookup) and automatically maps backward (foundational) and forward (emerging) citation networks (`oa_snowball`).

6. **N-Gram Terminology Discovery**:
   - Mathematically analyzes top-cited works to discover high-frequency bigrams and trigrams, helping expand search strategies dynamically.

---

## 📋 Prerequisites & Installation

Ensure you have R installed (version 4.1 or higher recommended). Install the required dependencies:

```R
install.packages(c(
  "rscopus",
  "openalexR",
  "dplyr",
  "purrr",
  "stringr",
  "tidyr",
  "tibble",
  "stringdist",
  "synthesisr"
))
```

---

## ⚙️ Configuration & Setup

Prior to running `PRISMA.R`, set your API credentials and parameters:

### 1. API Credentials & Environment Setup

- **Scopus API Key**: Obtain a key from the Elsevier Developer Portal and set it as an environment variable in your `.Renviron` or shell:
  ```R
  Sys.setenv(ELSEVIER_SCOPUS_KEY = "your_scopus_api_key_here")
  ```
  *(Note: If no Scopus key is provided, the pipeline gracefully skips Scopus calls and executes on OpenAlex).*

- **OpenAlex Polite Pool (Required)**: Identify yourself to access the OpenAlex polite pool for elevated rate limits:
  ```R
  options(openalexR.mailto = "your_email@example.com")
  ```

### 2. Search Logic Configuration (`PRISMA.R`)

The script structures search parameters into modular blocks:

- `START_YEAR`: Cutoff year for literature search (default: `2020`).
- `AFRICA_GEO`: Regional geographic search filter string covering continental and sub-regional descriptors.
- `QUERY_BLOCKS`: A named list of concept categories and associated keyword phrases sent to database APIs:
  ```R
  QUERY_BLOCKS <- list(
    party_linkages = c('"political party"', '"party decline"', ...),
    constituency_representation = c('"constituency service"', '"home style"', ...),
    responsiveness_patronage = c('"clientelism"', '"patronage"', ...)
  )
  ```
- `TARGET_PHRASES`: Precise phrases used for sentence-level context extraction within abstracts:
  ```R
  TARGET_PHRASES <- c("party decline", "clientelism", "patronage", "constituency service")
  ```
- `SNOWBALL_ANCHORS`: Number of top-cited papers to select for citation network snowballing (default: `5`).

---

## 🚀 Running the Pipeline

Execute the main pipeline script from R or your terminal:

```bash
Rscript PRISMA.R
```

---

## 📂 Output Files & Directory Structure

All generated outputs are saved to the `outputs/` directory:

| Output File | Description |
| :--- | :--- |
| `outputs/context_mentions.csv` | **Primary Analysis Dataset**. Contains DOI, title, journal, year, citations, authors, `author_countries`, matched term, and extracted context sentences. |
| `outputs/snowball_papers_full.rds` | Deeply nested R data object containing full metadata for all papers in the citation snowball network. |
| `outputs/snowball_papers_flat.csv` | Flattened CSV of all forward and backward citing papers connected to your anchor papers. |
| `outputs/snowball_connections.csv` | Directed edge list (`From` / `To`) representing citation relationships. |
| `outputs/discovered_keywords.csv` | High-frequency 2-gram and 3-gram key phrases discovered across top anchor works. |

---

## 🗺️ Downstream Analysis Strategy

For advanced downstream workflows, refer to the strategic roadmap in `systematic_review_analysis_plan.md`:

1. **Geographic Scale Tagging**: Distinguishes **Author Institutional Location** (`author_countries`) from **Study Focus Location** (*Continental*, *Regional (e.g. ECOWAS, SADC)*, or *Country-Specific*) using `countrycode` gazetteer matching.
2. **Thematic Filtering**: Filters out false positives (e.g. clinical health studies mentioning political terms) using OpenAlex Concept Filtering, Structural Topic Modeling (`stm`), and negative vocabulary lists.
3. **PRISMA-ScR & Bibliometrics**: Uses `PRISMA2020` for PRISMA flow diagrams and `bibliometrix` for co-authorship networks, country collaboration maps, and keyword co-occurrence analysis.
