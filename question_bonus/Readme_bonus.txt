# GenAI Clinical Data Assistant

**Author:** Chao Ma  
**Date:** April 2026  

---

## Overview

---- Before starting ----------------------------------------
- I do not have prior experience with Python as my primary programming language is mainly in SAS and R
- I used AI-assisted tools to help with Python syntax and structuring the implementation.
- I carefully reviewed, understood, and validated the logic of the code, run it with Google Colab, specifically including:
   - Data flow (LLM → parsing → execution)
   - JSON handling and error checking
   - Pandas-based filtering logic
--------------------------------------------------------------


This project implements a prototype **Clinical Trial Data Assistant** that translates natural language questions into structured queries on an adverse event (AE) dataset.

The system allows users to ask questions such as:
- “Which patients experienced headache?”
- “Show me subjects with moderate severity adverse events”
- “Which subjects had nervous system disorders?”

and returns filtered results using a Pandas-based backend.

---

## Approach

The solution follows a three-step pipeline:

1. **Natural Language Parsing**
   - A large language model (LLM) is used to map user questions to structured query components.
   - The mapping is guided by a predefined AE dataset schema.

2. **Structured Interpretation**
   - The LLM output is constrained to a JSON format:
     - `target_column`
     - `filter_value`
     - `description`

3. **Execution**
   - The parsed output is applied to the dataset using Pandas filtering.
   - Results include:
     - Number of subjects
     - Subject IDs
     - Number of AE records

---

## LLM Design

- The implementation supports:
  - OpenAI models via LangChain (if API key is available)
  - A **mock LLM fallback** using rule-based keyword matching

The mock LLM ensures the full pipeline remains functional without external dependencies.

---

## Data

The expected dataset structure follows a standard AE domain, including:

- `USUBJID` — Subject ID  
- `AETERM` — Reported adverse event term  
- `AEDECOD` — Standardized MedDRA term  
- `AESEV` — Severity (MILD, MODERATE, SEVERE)  
- `AESOC` — System Organ Class  
- `AESER` — Serious event flag  
- `TRTEMFL` — Treatment-emergent flag  

If no dataset is provided, a small synthetic dataset is used for demonstration.

---

## How to Run

1. Save the AE dataset as `adae.csv` in the working directory  
2. Run the script:

```bash
python question_bonus.py