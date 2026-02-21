# Ralph Search

Automated iterative research tool powered by [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It runs Claude in a headless loop to systematically investigate items — products, candidates, services, or anything else — and produces scored dossiers with a live web dashboard.

## How It Works

1. You define a search by writing a `prompt.md` with your requirements, scoring criteria, and research strategies.
2. `ralph_search.sh` spawns independent Claude Code sessions in a loop. Each session picks one item from the backlog, researches it via web search, writes a structured dossier, and updates shared notes.
3. A live dashboard lets you monitor progress, compare scores, and read dossiers from any device.

## Quick Start

```bash
# Prerequisites: Claude Code CLI, gtimeout (brew install coreutils), Python 3
# Set up a search folder with prompt.md, notes.md, and DOSSIER_TEMPLATE.md
# (see templates/ for starting points, examples/ for real-world prompts)

# Run 5 research iterations
./ralph_search.sh run ./my_search 5 --model sonnet

# Check status
./ralph_search.sh status ./my_search

# Start the live dashboard
./ralph_search.sh dashboard ./my_search --port 8420
```

## Project Structure

```
ralph_search.sh      # CLI: run loops, check status, start dashboard
dashboard/           # Flask web dashboard (auto-refresh, mobile-friendly)
templates/           # Generic templates for prompt.md, notes.md, dossiers
examples/            # Example prompts for different domains
SKILL.md             # Claude Code skill definition for guided setup
```

## Claude Code Skill

If you use Claude Code, install `SKILL.md` as a skill and run `/ralph-search [topic]`. It walks you through an 8-phase workflow: landscape research, requirement gathering, prompt generation, execution, review, and iteration.

## License

MIT
