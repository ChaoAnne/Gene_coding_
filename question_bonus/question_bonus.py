"""
========================================================
Question 4: GenAI Clinical Data Assistant
Author: Chao Ma
Date:   April 2026
========================================================

Implements a ClinicalTrialDataAgent that translates natural language
questions into Pandas queries using an LLM (OpenAI via LangChain).
A mock LLM fallback is included for environments without an API key.
"""

import os
import json
import re
import pandas as pd
from typing import Optional

# ----------------------------------------------------------
# Optional: LangChain + OpenAI imports
# Comment these out if you do not have the packages installed
# ----------------------------------------------------------
try:
    from langchain_openai import ChatOpenAI
    from langchain.schema import HumanMessage, SystemMessage
    LANGCHAIN_AVAILABLE = True
except ImportError:
    LANGCHAIN_AVAILABLE = False

# ==========================================================
# 1. Schema Definition
#    Describes the AE dataset columns to the LLM so it can
#    map natural language questions to the correct variable.
# ==========================================================

AE_SCHEMA = """
You are a clinical data assistant. You help map natural language questions
to structured queries on an adverse event (AE) dataset.

The dataset has the following relevant columns:

  USUBJID  : Unique subject identifier
  AETERM   : Verbatim adverse event term reported by the subject
             (e.g. "HEADACHE", "NAUSEA", "FATIGUE")
  AEDECOD  : MedDRA preferred term — standardised AE term
             (e.g. "Headache", "Nausea", "Fatigue")
  AESEV    : Severity or intensity of the AE
             Values: "MILD", "MODERATE", "SEVERE"
  AESOC    : System Organ Class — body system affected
             (e.g. "Nervous system disorders", "Cardiac disorders",
              "Skin and subcutaneous tissue disorders")
  AESEVN   : Numeric severity (1=MILD, 2=MODERATE, 3=SEVERE)
  TRTEMFL  : Treatment-emergent flag ("Y" = treatment-emergent AE)
  AESER    : Serious AE flag ("Y" = serious)

Mapping rules:
  - Questions about "severity" or "intensity"   -> AESEV
  - Questions about a specific condition or term -> AETERM or AEDECOD
  - Questions about a body system or organ class -> AESOC
  - Questions about "serious" AEs               -> AESER
  - Questions about "treatment-emergent" AEs    -> TRTEMFL

You must respond ONLY with a valid JSON object in this exact format:
{
  "target_column": "<column name>",
  "filter_value": "<value to filter on, uppercased>",
  "description": "<one sentence explaining what you are doing>"
}

Do not include any text outside the JSON object.
"""


# ==========================================================
# 2. Mock LLM
#    Used when no API key is available. Applies simple keyword
#    matching to simulate the LLM's JSON output so the full
#    logic flow (Prompt -> Parse -> Execute) is preserved.
# ==========================================================

def mock_llm_response(question: str) -> str:
    """
    Simulates LLM output using keyword matching.
    Returns a JSON string in the same format the real LLM would produce.
    """
    q = question.lower()

    # Severity / intensity
    if any(word in q for word in ["severe", "severity", "intense", "intensity"]):
        if "mild" in q:
            return json.dumps({
                "target_column": "AESEV",
                "filter_value": "MILD",
                "description": "Filter AEs where severity is MILD."
            })
        elif "moderate" in q:
            return json.dumps({
                "target_column": "AESEV",
                "filter_value": "MODERATE",
                "description": "Filter AEs where severity is MODERATE."
            })
        elif "severe" in q:
            return json.dumps({
                "target_column": "AESEV",
                "filter_value": "SEVERE",
                "description": "Filter AEs where severity is SEVERE."
            })

    # Serious AEs
    if "serious" in q:
        return json.dumps({
            "target_column": "AESER",
            "filter_value": "Y",
            "description": "Filter AEs flagged as serious (AESER = Y)."
        })

    # Treatment-emergent AEs
    if any(word in q for word in ["treatment-emergent", "treatment emergent", "emergent"]):
        return json.dumps({
            "target_column": "TRTEMFL",
            "filter_value": "Y",
            "description": "Filter treatment-emergent AEs (TRTEMFL = Y)."
        })

    # Body system / SOC keywords
    soc_keywords = {
        "cardiac":          "Cardiac disorders",
        "heart":            "Cardiac disorders",
        "skin":             "Skin and subcutaneous tissue disorders",
        "nervous":          "Nervous system disorders",
        "neurolog":         "Nervous system disorders",
        "gastro":           "Gastrointestinal disorders",
        "stomach":          "Gastrointestinal disorders",
        "hepat":            "Hepatobiliary disorders",
        "liver":            "Hepatobiliary disorders",
        "muscul":           "Musculoskeletal and connective tissue disorders",
        "muscle":           "Musculoskeletal and connective tissue disorders",
        "infect":           "Infections and infestations",
        "respirat":         "Respiratory, thoracic and mediastinal disorders",
        "lung":             "Respiratory, thoracic and mediastinal disorders",
        "renal":            "Renal and urinary disorders",
        "kidney":           "Renal and urinary disorders",
        "eye":              "Eye disorders",
        "ocular":           "Eye disorders",
        "blood":            "Blood and lymphatic system disorders",
        "metabol":          "Metabolism and nutrition disorders",
        "psychiatric":      "Psychiatric disorders",
        "mental":           "Psychiatric disorders",
        "vascular":         "Vascular disorders",
        "general":          "General disorders and administration site conditions",
    }
    for keyword, soc_value in soc_keywords.items():
        if keyword in q:
            return json.dumps({
                "target_column": "AESOC",
                "filter_value": soc_value,
                "description": f"Filter AEs in the '{soc_value}' system organ class."
            })

    # Specific AE term — extract capitalised or quoted words as the term
    # Try to find a term in quotes first
    quoted = re.findall(r'"([^"]+)"|\'([^\']+)\'', question)
    if quoted:
        term = [t for pair in quoted for t in pair if t][0]
        return json.dumps({
            "target_column": "AETERM",
            "filter_value": term.upper(),
            "description": f"Filter AEs where the reported term matches '{term.upper()}'."
        })

    # Fall back to AETERM with the last significant word
    words = [w for w in q.split() if len(w) > 4 and w not in
             ("about", "subjects", "patients", "adverse", "events",
              "which", "where", "their", "those", "have", "with", "that")]
    term = words[-1].upper() if words else "UNKNOWN"
    return json.dumps({
        "target_column": "AETERM",
        "filter_value": term,
        "description": f"Filter AEs where the reported term matches '{term}'."
    })


# ==========================================================
# 3. ClinicalTrialDataAgent
# ==========================================================

class ClinicalTrialDataAgent:
    """
    Translates natural language questions into Pandas queries
    on an adverse event dataset.

    Parameters
    ----------
    df : pd.DataFrame
        The AE dataset (e.g. pharmaversesdtm::ae exported as CSV).
    api_key : str, optional
        OpenAI API key. If not provided, the mock LLM is used.
    model : str
        OpenAI model name. Defaults to "gpt-3.5-turbo".
    """

    def __init__(
        self,
        df: pd.DataFrame,
        api_key: Optional[str] = None,
        model: str = "gpt-3.5-turbo"
    ):
        self.df = df.copy()
        self.use_mock = True

        if api_key and LANGCHAIN_AVAILABLE:
            try:
                self.llm = ChatOpenAI(
                    model=model,
                    temperature=0,
                    api_key=api_key
                )
                self.use_mock = False
                print("Using OpenAI LLM via LangChain.")
            except Exception as e:
                print(f"LLM initialisation failed: {e}. Falling back to mock LLM.")
        else:
            print("No API key provided or LangChain not installed. Using mock LLM.")

    # ----------------------------------------------------------
    # Step 1: Call LLM (real or mock) to parse the question
    # ----------------------------------------------------------
    def _call_llm(self, question: str) -> str:
        """Send the question to the LLM and return the raw response string."""
        if self.use_mock:
            return mock_llm_response(question)

        messages = [
            SystemMessage(content=AE_SCHEMA),
            HumanMessage(content=question)
        ]
        response = self.llm.invoke(messages)
        return response.content

    # ----------------------------------------------------------
    # Step 2: Parse the LLM response into a structured dict
    # ----------------------------------------------------------
    def _parse_response(self, raw: str) -> dict:
        """
        Extract the JSON object from the LLM response.
        Handles cases where the LLM wraps output in markdown code fences.
        """
        # Strip markdown code fences if present
        cleaned = re.sub(r"```(?:json)?", "", raw).strip()

        try:
            parsed = json.loads(cleaned)
        except json.JSONDecodeError as e:
            raise ValueError(
                f"LLM response could not be parsed as JSON.\n"
                f"Raw response: {raw}\n"
                f"Error: {e}"
            )

        required_keys = {"target_column", "filter_value"}
        missing = required_keys - parsed.keys()
        if missing:
            raise ValueError(
                f"LLM response missing required keys: {missing}\n"
                f"Parsed response: {parsed}"
            )

        return parsed

    # ----------------------------------------------------------
    # Step 3: Execute the Pandas filter
    # ----------------------------------------------------------
    def _execute_query(self, parsed: dict) -> dict:
        """
        Apply the filter to the dataframe and return results.
        Returns subject count and list of unique USUBJIDs.
        """
        col   = parsed["target_column"]
        value = parsed["filter_value"]

        if col not in self.df.columns:
            raise ValueError(
                f"Column '{col}' not found in dataset.\n"
                f"Available columns: {list(self.df.columns)}"
            )

        # Case-insensitive string match
        mask = self.df[col].astype(str).str.upper() == value.upper()
        filtered = self.df[mask]

        unique_subjects = filtered["USUBJID"].dropna().unique().tolist()

        return {
            "question":        parsed.get("description", ""),
            "target_column":   col,
            "filter_value":    value,
            "n_subjects":      len(unique_subjects),
            "subject_ids":     sorted(unique_subjects),
            "n_ae_records":    len(filtered)
        }

    # ----------------------------------------------------------
    # Public method: run the full pipeline
    # ----------------------------------------------------------
    def ask(self, question: str) -> dict:
        """
        Full pipeline: Prompt -> Parse -> Execute.

        Parameters
        ----------
        question : str
            A natural language question about the AE dataset.

        Returns
        -------
        dict with keys: question, target_column, filter_value,
                        n_subjects, subject_ids, n_ae_records
        """
        print(f"\n{'='*60}")
        print(f"Question : {question}")
        print(f"{'='*60}")

        # Step 1: call LLM
        raw_response = self._call_llm(question)
        print(f"LLM output: {raw_response}")

        # Step 2: parse JSON
        parsed = self._parse_response(raw_response)

        # Step 3: execute filter
        result = self._execute_query(parsed)

        # Print summary
        print(f"Mapped to : {result['target_column']} = '{result['filter_value']}'")
        print(f"Subjects  : {result['n_subjects']} unique subject(s)")
        print(f"AE records: {result['n_ae_records']}")
        print(f"IDs       : {result['subject_ids']}")

        return result


# ==========================================================
# 4. Test Script — three example queries
# ==========================================================

if __name__ == "__main__":

    # -------------------------------------------------------
    # Load data
    # Option A: load from local CSV (export from R with
    #           write.csv(pharmaversesdtm::ae, "adae.csv"))
    # Option B: load from pharmaverseadam via pyreadr if available
    # -------------------------------------------------------
    try:
        ae = pd.read_csv("adae.csv")
        print(f"Loaded adae.csv — {len(ae)} rows, {ae['USUBJID'].nunique()} subjects.\n")
    except FileNotFoundError:
        # Generate a small synthetic dataset for demonstration
        print("adae.csv not found. Using synthetic demo data.\n")
        ae = pd.DataFrame({
            "USUBJID": [
                "CDISCPILOT01-01-701-1015", "CDISCPILOT01-01-701-1015",
                "CDISCPILOT01-01-701-1023", "CDISCPILOT01-01-701-1028",
                "CDISCPILOT01-01-701-1033", "CDISCPILOT01-01-701-1033",
                "CDISCPILOT01-01-701-1042", "CDISCPILOT01-01-701-1057",
                "CDISCPILOT01-01-701-1057", "CDISCPILOT01-01-701-1097"
            ],
            "AETERM": [
                "HEADACHE", "NAUSEA", "HEADACHE", "FATIGUE",
                "DIZZINESS", "HEADACHE", "NAUSEA", "FATIGUE",
                "HEADACHE", "DIZZINESS"
            ],
            "AEDECOD": [
                "Headache", "Nausea", "Headache", "Fatigue",
                "Dizziness", "Headache", "Nausea", "Fatigue",
                "Headache", "Dizziness"
            ],
            "AESEV": [
                "MILD", "MODERATE", "SEVERE", "MILD",
                "MODERATE", "MILD", "SEVERE", "MODERATE",
                "MILD", "SEVERE"
            ],
            "AESOC": [
                "Nervous system disorders", "Gastrointestinal disorders",
                "Nervous system disorders", "General disorders and administration site conditions",
                "Nervous system disorders", "Nervous system disorders",
                "Gastrointestinal disorders", "General disorders and administration site conditions",
                "Nervous system disorders", "Nervous system disorders"
            ],
            "AESER":   ["N","N","N","N","N","N","N","N","N","Y"],
            "TRTEMFL": ["Y","Y","Y","Y","Y","Y","Y","Y","Y","Y"]
        })

    # -------------------------------------------------------
    # Initialise agent
    # To use OpenAI, set your key here or via environment variable:
    #   api_key = os.getenv("OPENAI_API_KEY")
    # -------------------------------------------------------
    api_key = os.getenv("OPENAI_API_KEY", None)
    agent = ClinicalTrialDataAgent(df=ae, api_key=api_key)

    # -------------------------------------------------------
    # Run three example queries
    # -------------------------------------------------------

    # Query 1: severity-based
    result1 = agent.ask(
        "Give me the subjects who had adverse events of moderate severity."
    )

    # Query 2: specific AE term
    result2 = agent.ask(
        "Which patients experienced headache?"
    )

    # Query 3: body system / SOC
    result3 = agent.ask(
        "Show me subjects with adverse events related to the nervous system."
    )

    # -------------------------------------------------------
    # Summary printout
    # -------------------------------------------------------
    print("\n" + "="*60)
    print("RESULTS SUMMARY")
    print("="*60)
    for i, result in enumerate([result1, result2, result3], 1):
        print(f"\nQuery {i}: {result['target_column']} = '{result['filter_value']}'")
        print(f"  Unique subjects : {result['n_subjects']}")
        print(f"  Subject IDs     : {result['subject_ids']}")
