---
name: ralph-search
description: Use when the user asks for an extensive, systematic search or research task across a domain (finding products, candidates, services, treatments, etc.). Sets up and runs iterative research using the Ralph Wiggum loop pattern.
---

# Ralph Search — Iterative Research Automation

## Description
Sets up and runs iterative research searches using the Ralph Wiggum loop pattern.
Use this when the user asks for an extensive, systematic search across a domain
(finding products, candidates, services, treatments, etc.).

## Usage
```
/ralph-search [topic]
```

## Overview

This is a two-component system:

1. **SKILL.md** (this file) — Handles the interactive setup, execution monitoring, and user communication. You (the agent reading this) follow these instructions to guide the user through defining their search, generating the right files, launching the automated loop, and reviewing results.

2. **ralph_search.sh** — A bash CLI that runs Claude Code in a headless loop. Each iteration spawns a fresh Claude session that reads `prompt.md`, picks one item from the backlog, researches it via web search, creates a dossier, and updates `notes.md`. The script handles timeouts, logging, dossier counting, and stall detection. You do NOT run inside that loop — you call it from the outside and monitor its output.

The key insight: the agent running inside the loop (spawned by `ralph_search.sh`) is a DIFFERENT agent. It only sees the files inside the search folder (`prompt.md`, `notes.md`, `dossiers/`, `DOSSIER_TEMPLATE.md`). All domain knowledge, instructions, scoring criteria, and research strategies must be written into those files. If it is not in `prompt.md`, the loop agent will not know about it.

## Configuration

All paths below are relative to the directory containing this SKILL.md file (the tool root). Resolve them at runtime using the skill's location.

- **TOOL_DIR**: `.` (the directory containing this SKILL.md)
- **RALPH_SCRIPT**: `./ralph_search.sh`
- **TEMPLATES_DIR**: `./templates`
- **EXAMPLES_DIR**: `./examples`
- **SEARCHES_DIR**: `${CWD}/searches` (relative to the current working directory when the skill is invoked)

---

## The 8-Phase Workflow

Execute these phases in order. Do not skip any phase. Each phase has specific deliverables that feed into the next.

---

### Phase 1: Context Discovery

**Goal:** Check for existing searches that might inform the new one.

**Steps:**

1. Check if a `searches/` directory exists in the current working directory.
2. If it exists, list all subdirectories matching the pattern `NN_*` (e.g., `01_suche_pizzaofen`, `02_suche_developer`).
3. For each folder found:
   - Read the first 5 lines of `prompt.md` (contains the title and domain description).
   - Read the "Search Criteria" section of `notes.md` (contains the requirements summary).
4. Identify which past searches are relevant to the user's new request. A search is relevant if:
   - It is in the same domain (e.g., both are product searches, both are hiring searches).
   - It has similar requirements or criteria structure.
   - Its dossier format could be reused or adapted.
5. Present findings to the user:
   - If related searches exist: "I found these related past searches: [list with brief descriptions]. I can adapt their prompt structure for your new search."
   - If no `searches/` directory or no related searches: "No related past searches found. I'll build the prompt from the generic template."

**Deliverable:** A list of related past searches (possibly empty) and a decision on whether to adapt from a past search or start from the template.

---

### Phase 2: Initial Research

**Goal:** Quickly map the landscape so you can have an informed conversation with the user in Phase 3.

**Steps:**

1. Based on the user's search request, perform 2-3 web searches to understand the domain. Example queries:
   - "best [item type] 2025 2026" or "[item type] test comparison"
   - "[item type] review [location]" or "[item type] buyer guide"
   - "[domain] forum recommendations"
2. From the results, identify:
   - **Key dimensions:** What are the major categories, brands, or providers? What segments exist (budget/mid/premium)?
   - **Price tiers:** What does the market look like? What is cheap, what is expensive, what is the sweet spot?
   - **Quality indicators:** What separates good from bad in this domain? What do experts look for?
   - **Best sources:** Which review sites, forums, databases, or professional resources are authoritative for this domain?
3. Note 5-10 initial candidates/items that look promising for the backlog.
4. Keep this phase quick — spend 3-5 minutes maximum. The goal is to frame the search, not to do deep research.

**Deliverable:** A mental model of the domain landscape, key dimensions, and an initial list of 5-10 candidates.

---

### Phase 3: User Check-in

**Goal:** Clarify and confirm the user's requirements before generating the search files.

**Steps:**

1. Present the landscape findings from Phase 2 concisely. For example:
   - "I've done some initial research on [domain]. The market has X categories, price ranges from Y to Z, and the key quality factors are A, B, C."
   - "The top sources for reviews appear to be [list]."
   - "I've identified [N] initial candidates worth investigating."

2. Ask the user to clarify the following (adapt questions to the domain):
   - **Mandatory requirements:** What are the hard filters? What must every candidate have? (e.g., "must be electric", "must have certification X", "must be available in Germany")
   - **Important preferences:** What is nice to have but not a dealbreaker? (e.g., "lighter is better", "would prefer stainless steel")
   - **Optimization priority:** What matters most? If two items are close, what tips the scale? (e.g., "performance over price", "reliability over features")
   - **Budget/scope constraints:** What is the budget range? Is there a hard maximum? Or is value-for-money the concern rather than absolute price?
   - **Location:** Where is the user? This affects availability, shipping, language of sources, currency, and regulatory requirements.
   - **Language preference:** Should the search be conducted primarily in German, English, or another language? This affects search queries and source selection.
   - **Known items:** Does the user already know about specific items they want included? Any items to explicitly exclude?
   - **Use case details:** Who is this for? What is their experience level? What is the timeline?

3. Summarize the confirmed requirements back to the user before proceeding. Format them as:
   - Mandatory requirements (numbered list)
   - Important preferences (bullet list)
   - Key background (bullet list with labeled fields)
4. Get explicit confirmation: "Does this capture your requirements correctly? Anything to add or change?"

**Deliverable:** A confirmed, structured list of requirements, preferences, and context that will feed directly into the prompt.

---

### Phase 4: Folder Setup

**Goal:** Create the search folder with the correct naming convention and directory structure.

**Steps:**

1. Create the `searches/` directory if it does not exist:
   ```bash
   mkdir -p searches
   ```

2. Determine the next available number:
   - List all directories in `searches/` matching the `NN_*` pattern.
   - Find the highest number NN currently in use.
   - Increment by 1 to get the next number.
   - If no existing folders, start at `01`.
   - Always zero-pad to 2 digits (01, 02, ..., 09, 10, 11, ...).

3. Construct the folder name:
   - Pattern: `NN_suche_<topic>`
   - `<topic>` should be lowercase, words separated by underscores, 2-3 words maximum.
   - Examples: `01_suche_pizzaofen`, `02_suche_frontend_dev`, `03_suche_laufschuhe`

4. Create the folder and its subdirectories:
   ```bash
   mkdir -p searches/NN_suche_<topic>/dossiers
   mkdir -p searches/NN_suche_<topic>/logs
   ```

5. Tell the user: "Created search folder: `searches/NN_suche_<topic>/`"

**Deliverable:** An empty search folder with `dossiers/` and `logs/` subdirectories, ready for file generation.

---

### Phase 5: Prompt Generation

**Goal:** Create `prompt.md`, `DOSSIER_TEMPLATE.md`, and `notes.md` inside the search folder. This is the most critical phase — the quality of these files directly determines the quality of the automated search.

**Decision tree for prompt.md:**

1. **If a related past search was found in Phase 1 AND it is in a similar domain:**
   - Read that search's `prompt.md` in full.
   - Copy it as the starting point for the new `prompt.md`.
   - Replace ALL domain-specific content (item types, criteria, search queries, brands, sources) with content appropriate to the new domain.
   - Keep the structural patterns that worked (section organization, rating criteria format, research strategies layout).
   - Also copy and adapt that search's `DOSSIER_TEMPLATE.md`.

2. **If no related past search exists (or the past search is too different):**
   - Read the generic template: `./templates/prompt_template.md`
   - Use it as the starting point.
   - Replace ALL `[PLACEHOLDER]` markers with domain-specific content derived from Phase 3.
   - Read the generic dossier template: `./templates/dossier_template.md`
   - Adapt it with domain-specific sections.

**In BOTH cases, the final `prompt.md` must contain:**

- **Title line:** A clear, descriptive title (e.g., "Electric Pizza Oven Search: Indoor, High-Temperature, Compact").
- **Search Context:** 2-4 sentences describing what we are looking for, why, and the general constraints. Directly from Phase 3.
- **Mandatory Requirements:** Numbered list, each with a bold label and specific description. These are hard filters — items that fail any mandatory requirement should be noted but deprioritized.
- **Important Preferences:** Bullet list of nice-to-have criteria. Not dealbreakers, but they influence scoring.
- **Key Background:** Labeled bullet list with use case, location, budget, experience level, timeline, and any additional context.
- **Step 3 (Thorough Research):** Customize subsections for the domain. Replace generic placeholders with domain-specific research areas. For example:
  - Products: "Build Quality & Materials", "Usability & Cleaning", "Power & Performance"
  - Hiring: "Publications & Research", "GitHub & Open Source", "Interview Signals"
  - Services: "Onboarding Process", "SLA & Support", "Integration Capabilities"
- **Step 4 (Rating):** Define 4-6 domain-specific rating criteria with clear names. Each criterion is scored 0-10. Examples:
  - Products: "Temperature Performance", "Build Quality", "Ease of Use", "Value for Money", "Availability"
  - Hiring: "Technical Skills", "Research Fit", "Communication", "Cultural Fit", "Availability"
- **Research Strategies:** Fill in specific search queries, websites, forums, and key brands/names relevant to this domain. Be concrete — the loop agent will use these as starting points.

**Generate `DOSSIER_TEMPLATE.md`:**

- If adapting from a past search: copy and modify that search's dossier template.
- If starting from scratch: read `./templates/dossier_template.md` and replace all `[PLACEHOLDER]` and `[DOMAIN-SPECIFIC ...]` markers with concrete, domain-appropriate fields and sections.
- The template MUST include YAML frontmatter at the top (between `---` delimiters) containing: name, date, priority_score, recommendation, scores (list of criterion/score/comment objects), and summary. This frontmatter powers the live dashboard. Fill in the criterion names in the frontmatter to match the domain-specific scoring criteria.
- The template must have: Summary, Basic Information table, 2-4 domain-specific deep-dive sections, Reviews & Reputation, Pricing & Availability, Assessment scoring table, Comparison Notes, Research Sources.
- Save as `searches/NN_suche_<topic>/DOSSIER_TEMPLATE.md`.

**Generate `notes.md`:**

- Read the template: `./templates/notes_template.md`
- Fill in the Search Criteria section with the confirmed requirements from Phase 3.
- Populate the "To Research -- HIGH Priority" section with 3-5 of the most promising candidates from Phase 2.
- Populate the "To Research -- MEDIUM Priority" section with the remaining candidates from Phase 2.
- Leave the "Researched Items" table empty (the loop agent will fill it).
- Leave the "Key Learnings" section empty (the loop agent will fill it).
- Save as `searches/NN_suche_<topic>/notes.md`.

**Decide on model:**

- Use `sonnet` for: product searches, service comparisons, general consumer research, straightforward evaluations.
- Use `opus` for: complex research requiring deep analysis (medical/scientific literature, technical evaluations, hiring/candidate assessment, legal or regulatory research).
- Default to `sonnet` if unclear — it is faster and cheaper.
- Tell the user which model you chose and why.

**Deliverable:** Three files in the search folder: `prompt.md`, `DOSSIER_TEMPLATE.md`, `notes.md`. All fully populated with domain-specific content, no remaining placeholders.

---

### Phase 6: Execute First Batch

**Goal:** Run the first 3 iterations to get initial dossiers and validate the setup.

**Steps:**

1. Start the live dashboard so the user can monitor progress on any device:
   ```bash
   ./ralph_search.sh dashboard searches/NN_suche_<topic> &
   ```
   Get the Tailscale IP via `tailscale ip -4` and share the full URL `http://<tailscale-ip>:8420` with the user so they can access the dashboard from any device on their Tailscale network (e.g. smartphone).

2. Run the first batch:
   ```bash
   ./ralph_search.sh run searches/NN_suche_<topic> 3 --model <model>
   ```
   Replace `<model>` with either `sonnet` or `opus` based on the decision in Phase 5.

3. Wait for the script to complete. This will take approximately 10-20 minutes depending on the model and domain complexity.

4. Verify the first dossiers have valid YAML frontmatter by checking the dashboard overview table. If scores are missing, check whether the loop agent is writing frontmatter correctly and fix the `DOSSIER_TEMPLATE.md` or `prompt.md` if needed.

5. If the script exits with a STALL warning (2 consecutive sessions with 0 new dossiers):
   - Read the last 2-3 log files in `searches/NN_suche_<topic>/logs/`.
   - Read `notes.md` to see if the loop agent encountered issues.
   - Common stall causes:
     - `prompt.md` instructions are too vague or contradictory.
     - The loop agent cannot find the dossier template.
     - Web search is returning irrelevant results (bad search queries in prompt.md).
     - The backlog is empty and the agent cannot discover new items.
   - Fix the identified issue in the relevant file and re-run.

**Deliverable:** 1-3 completed dossiers in `dossiers/`, updated `notes.md`, session logs in `logs/`, and live dashboard accessible via Tailscale.

---

### Phase 7: Early Review (CRITICAL — do not skip)

**Goal:** Validate the search direction with the user before investing more iterations. This is the most important quality gate.

**Steps:**

1. Read ALL dossiers in `searches/NN_suche_<topic>/dossiers/`. The dashboard overview table (accessible via Tailscale) provides a quick visual summary of all scores and recommendations.
2. Read the current `notes.md` (check the Researched Items table, backlog state, and Key Learnings).
3. Present to the user:
   - **Progress:** "The search has researched [N] items so far."
   - **Current top choice:** Name, score, and a 1-2 sentence justification from the dossier.
   - **Surprising findings:** Anything unexpected — an item that scored much higher or lower than anticipated, a dimension the user had not considered, a market gap.
   - **Coverage assessment:** Are the key dimensions from Phase 2 being well covered? Are there blind spots (e.g., only one price tier explored, only one brand family)?
   - **Backlog state:** How many HIGH and MEDIUM priority items remain?

4. Ask the user (these are mandatory questions, do not skip):
   - "Does this match what you're looking for? Are the dossiers at the right level of detail?"
   - "Any changes to requirements or priorities based on what you've seen?"
   - "Should I adjust the search direction? (e.g., focus more on budget options, explore a different category, add a new mandatory requirement)"

5. If requirements change:
   - Update `prompt.md` with the new or changed requirements. Edit the relevant sections — do not rewrite the entire file.
   - Update `notes.md` with adjusted criteria in the Search Criteria section.
   - If existing dossiers need re-scoring based on changed criteria, read each dossier and update its Assessment table and Priority Score.
   - Add a note to the Key Learnings section in `notes.md` explaining the requirement change (so the loop agent understands the shift).

6. If everything looks good: confirm with the user and proceed to Phase 8.

**Deliverable:** User-validated search direction. Any necessary updates to `prompt.md`, `notes.md`, and existing dossiers.

---

### Phase 8: Continue & Exhaustion Check

**Goal:** Run additional batches until the search space is exhausted or the user is satisfied.

**Loop:**

1. **Run a batch:**
   ```bash
   ./ralph_search.sh run searches/NN_suche_<topic> 5 --model <model>
   ```

2. **After each batch, check for exhaustion:**
   - Read `notes.md`.
   - Count items listed under "To Research -- HIGH Priority" (items not yet researched).
   - Count items listed under "To Research -- MEDIUM Priority" (items not yet researched).
   - Count how many new dossiers were created in this batch: compare the number of files in `dossiers/` before and after the batch. You can use `ls dossiers/ | wc -l` or the `ralph_search.sh status` command.
   - **EXHAUSTED if ALL THREE conditions are true:**
     1. Backlog has 0 HIGH priority items remaining, AND
     2. Backlog has 0 MEDIUM priority items remaining, AND
     3. The last batch produced 1 or fewer new dossiers.
   - **NOT EXHAUSTED:** Run another batch. Go back to step 1.

3. **Safety limit:** Never run more than 10 iterations (2 batches of 5) without checking in with the user. After every 2 batches (10 iterations total), pause and give the user a brief progress update:
   - How many total dossiers exist.
   - Current top choice and score.
   - Remaining backlog size.
   - Ask: "Should I continue or would you like to review now?"

4. **When exhausted or user says stop:**
   - Read ALL dossiers in `dossiers/`.
   - Sort them by priority score (highest first).
   - Present a final ranked summary:

     **Top 3 Recommendations:**
     For each of the top 3, provide:
     - Name and score
     - 2-3 sentence summary of why it ranks here
     - Key differentiators vs. the other top choices
     - Any caveats or concerns

     **Full Ranked Table:**
     | Rank | Name | Score | Recommendation | Key Strength | Key Weakness |
     |------|------|-------|---------------|--------------|--------------|

     **Key Learnings:**
     - Summarize the most important insights from the search.
     - Note any patterns (e.g., "all items above [price] scored well on [criterion]").
     - Flag any remaining uncertainties.

   - Ask: "Are you satisfied with these results, or would you like me to continue searching in a specific direction?"

**Deliverable:** Either a final ranked summary (search complete) or a progress update with continued execution.

---

## Important Notes

1. **Script path.** Call `ralph_search.sh` using the resolved absolute path of the tool directory (derived from the location of this SKILL.md file). For example, if SKILL.md is at `/path/to/tool/SKILL.md`, use `/path/to/tool/ralph_search.sh`.

2. **The loop agent is separate.** The agent spawned by `ralph_search.sh` is a completely independent Claude session. It has no memory of your conversation with the user. It only sees the files in the search folder. Every instruction, criterion, and strategy must be written into `prompt.md`. If you tell the user something but do not write it into `prompt.md`, the loop agent will not know about it.

3. **Confirm the folder path.** After creating the search folder in Phase 4, always confirm the full path with the user. This avoids confusion if the user is running from an unexpected working directory.

4. **Stall debugging.** If the search stalls (script exits with STALL warning), check these in order:
   - Are there items in the backlog? If the backlog is empty and the agent cannot discover new items, it will stall.
   - Is `prompt.md` clear and unambiguous? Vague instructions cause the loop agent to waste time or produce incomplete dossiers.
   - Are the search queries in the Research Strategies section producing relevant results? Try running them yourself via web search to verify.
   - Does `DOSSIER_TEMPLATE.md` exist and is it readable? The loop agent needs it to create dossiers.
   - Check the last 2-3 log files for error messages or signs of confusion.

5. **Iteration limits.** Never run more than 10 iterations without checking in with the user. The user should always have the opportunity to redirect the search.

6. **Search language.** The search language (queries, sources, dossier content) should match the user's preferred language and location. If the user is in Germany and searching for local products, use German search queries and prioritize German-language sources. Write this explicitly into the Research Strategies section of `prompt.md`.

7. **Model selection rationale.** When choosing between `sonnet` and `opus`, err on the side of `sonnet`. It is significantly faster and cheaper. Only use `opus` when the domain genuinely requires deeper reasoning (e.g., evaluating scientific papers, complex multi-factor trade-offs, nuanced hiring decisions).

8. **File encoding.** All generated files should be UTF-8. This is especially important for searches in non-English languages (German umlauts, accented characters, etc.).

9. **Status command.** You can check the current state of a search at any time without running new iterations:
   ```bash
   ./ralph_search.sh status searches/NN_suche_<topic>
   ```
   This shows dossier count, recent sessions, backlog analysis, and stall risk.
