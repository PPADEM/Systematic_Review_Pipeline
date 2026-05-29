# Automated Systematic Review Pipeline

This repository contains an end-to-end automated systematic review pipeline written in R. It leverages the global OpenAlex API to search academic literature, extract contextual keyword usage, build citation snowball networks, discover emerging terminology via n-grams, and visualize the research landscape.

## Features
1. Automated Metadata Retrieval: Bypasses manual database searches by querying OpenAlex directly, automatically sorting by the most impactful (highly cited) literature.

2. Contextual Keyword Extraction: Does not just find papers; it extracts the exact sentences where your target terms are used so you can immediately see how authors are defining concepts.

3. Citation Snowballing: Automatically maps the backward (foundational) and forward (emerging) citation networks of your top-cited papers.

4. N-Gram Discovery: Analyzes text to find related 2-word and 3-word phrases mathematically, helping you expand your search without guessing.


## Prerequisites
You will need R installed, along with the following packages:

```{r}
install.packages(c("openalexR", "dplyr", "stringr", "purrr", "tidyr", "visNetwork"))
```

## ⚙️ Configuration & Setup
Before running api_pipeline.R, you must configure the parameters at the top of the script.

### 1. The Polite Pool (Required)
OpenAlex provides a faster "polite pool" for users who identify themselves. Replace the placeholder with your actual email:
```R
options(openalexR.mailto = "your_email@example.com")
```

### 2. Setting Your Search Terms (Crucial)
The script separates your search logic into two distinct variables to give you maximum flexibility: `API_QUERIES` and `TARGET_PHRASES`.

- `API_QUERIES`: This is what is sent to the OpenAlex search engine. OpenAlex natively treats spaces as AND.

- `TARGET_PHRASES`: This is what the R script looks for inside the text to extract the surrounding sentence context.

#### Starting Simple (Broad Search)
If you are starting your scoping review and just want to find everything related to a single concept:

```R
API_QUERIES <- c(
  "\"party decline\""
)

TARGET_PHRASES <- c("party decline")
```

#### Expanding with Geographic Filters & Multiple Phrases
As your review progresses, you might want to narrow your search to specific regions or add alternative phrasing.
Notice how we add "Africa" to the `API_QUERIES` to filter the database, but we DO NOT add it to the `TARGET_PHRASES`, because we only want to extract sentences discussing the decline, not sentences that just mention Africa.
```R
API_QUERIES <- c(
  "\"party decline\" Africa",
  "\"political decline\" Africa"
)

TARGET_PHRASES <- c("party decline", "political decline")
```


#### Boolean Logic Guide for API_QUERIES
- Exact Phrases: Wrap in escaped quotes `("\"exact phrase\"")`
- AND logic: Separate with a space `("\"party decline\" Africa")`
- OR logic: Put them as separate items in the list `c("Term1", "Term2")`. The script automatically loops through them and combines the results.

### 3. Snowball Anchors
You can adjust how many of your top-cited papers are used to build the citation network. (Default is 5 to prevent the API from timing out or generating an unreadable hairball network).

```R
SNOWBALL_ANCHORS <- 5
```

## 📂 Output Files
Once the script finishes running, it will generate the following files in your working directory:

### Core Analysis
- `party_decline_africa_abstracts.csv`: The primary dataset. Contains the Title, DOI, Journal, Authors, Citation Count, and the exact `context_mentions` showing the ~300 characters surrounding your target phrases.

### Network & Snowballing
- `snowball_papers_full.rds`: The raw, deeply nested R data object containing all metadata for your citation network (useful for advanced R analysis).
- `snowball_papers_flat.csv`: A flattened, spreadsheet-friendly list of all foundational and forward-citing papers connected to your anchors.
- `snowball_connections.csv`: The edge list (From / To) showing exactly who cited whom.

### Discovery & Visualization
- `discovered_keywords.csv:` (If open-access text is available) A list of frequent bigrams and trigrams used in your top papers to help you discover new search terms.
