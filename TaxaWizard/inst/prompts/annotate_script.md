# Script Annotation Prompt

You are analyzing an R script to identify **user-configurable parameters** and **execution steps** so it can be converted into a Shiny app.

## Script: {{SCRIPT_PATH}}

```r
{{SCRIPT_TEXT}}
```

## Task

Analyze the script above and return a JSON object with three fields:

1. **`libraries`**: Character vector of package names loaded via `library()`.

2. **`parameters`**: Array of objects for values that a user would reasonably want to change between runs. Each object has:
   - `name`: variable name
   - `type`: one of `"file_input"`, `"file_output"`, `"numeric"`, `"character"`, `"logical"`, `"named_numeric"`, `"numeric_range"`, `"function_ref"`, `"null_param"`, `"data_frame"`
   - `default`: the default value as it appears in the script
   - `line`: the line number in the script

   **What counts as a parameter:**
   - File paths (input and output)
   - Numeric thresholds, counts, or limits
   - Logical flags (TRUE/FALSE)
   - String labels or identifiers that vary between runs
   - Function references (e.g., `TaxaTools::call_anthropic_api`)
   - Named numeric vectors used as configuration (e.g., `c(high = 50, low = 3)`)

   **What is NOT a parameter:**
   - Intermediate computed results (e.g., `df <- read.csv(...)`)
   - Loop variables or temporary values
   - Infrastructure/plumbing (e.g., step counters, checkpoint directories)

3. **`steps`**: Array of objects grouping the remaining code into logical execution steps. Each object has:
   - `description`: short human-readable description of what this step does
   - `output_var`: the variable name assigned in the last line of the step (or a descriptive name if none)
   - `code_text`: the actual R code for this step (copy verbatim from the script)
   - `start_line`: first line number
   - `end_line`: last line number

   **Grouping rules:**
   - Group related operations together (e.g., read + clean = one step)
   - Use existing comment headers as step boundaries when present
   - Each step should be a coherent unit of work
   - Prefer 3-8 steps for a typical script

## Response Format

Return ONLY a JSON object (no markdown fences, no explanation):

```json
{
  "libraries": ["dplyr", "ggplot2"],
  "parameters": [
    {"name": "input_file", "type": "file_input", "default": "data.csv", "line": 3},
    {"name": "threshold", "type": "numeric", "default": 0.05, "line": 4}
  ],
  "steps": [
    {
      "description": "Load and clean data",
      "output_var": "clean_df",
      "code_text": "raw <- read.csv(input_file)\nclean_df <- raw[complete.cases(raw), ]",
      "start_line": 7,
      "end_line": 8
    }
  ]
}
```
