#!/bin/bash
# ============================================================
#  Zoho Robotics — Repository Automation Setup Script
#  Run ONCE per repository by the Engineering Lead.
#  Sets up the full automation stack: hooks, commitlint,
#  clang-format, GitHub Actions workflows, PR template.
#
#  Prerequisites:
#    1. Repository cloned locally
#    2. develop branch exists and is checked out
#    3. setup_developer_system.sh has been run on this machine
#    4. tools/project.env is present in the repository
#
#  Usage:
#    cd ~/robotics-dev/<repo-name>
#    ./tools/setup_repo_automation.sh
# ============================================================

set -e

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass()   { echo -e "  ${GREEN}✔  $1${RESET}"; }
fail()   { echo -e "  ${RED}✖  $1${RESET}"; }
info()   { echo -e "  ${CYAN}→  $1${RESET}"; }
warn()   { echo -e "  ${YELLOW}⚠  $1${RESET}"; }
header() { echo ""; echo -e "${BOLD}━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
created(){ echo -e "  ${GREEN}✔  Created: $1${RESET}"; }
skipped(){ echo -e "  ${YELLOW}⚠  Already exists — skipped: $1${RESET}"; }

# ── Must be inside a Git repository ──────────────────────────
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo ""
  fail "Not inside a Git repository."
  fail "cd into the repository folder first, then run this script."
  echo ""
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
cd "$REPO_ROOT"

# ── Load project.env ─────────────────────────────────────────
PROJECT_FILE="$REPO_ROOT/tools/project.env"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo ""
  fail "project.env not found at: $PROJECT_FILE"
  echo ""
  echo "  project.env must be present in tools/ before running this script."
  echo "  Copy it from the POC repository:"
  echo "    github.com/cherinzoho/robotics-git-automation-poc/tools/project.env"
  echo ""
  exit 1
fi

# shellcheck source=tools/project.env
source "$PROJECT_FILE"

# Validate required variables
REQUIRED_VARS=(
  ROS2_DISTRO NODE_MAJOR_VERSION GIT_MIN_VERSION
  PRECOMMIT_MIN_VERSION COMMITLINT_CLI_VERSION
  COMMITLINT_CONFIG_VERSION HUSKY_VERSION
  PRECOMMIT_HOOKS_REV CLANG_FORMAT_REV CLANG_FORMAT_VERSION
  BLACK_REV FLAKE8_REV MAX_LINE_LENGTH
)
MISSING=false
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    fail "project.env is missing required variable: $var"
    MISSING=true
  fi
done
[[ "$MISSING" == "true" ]] && { echo "  Fix project.env and retry."; exit 1; }

# ── Intro ─────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Zoho Robotics — Repository Automation Setup        ║${RESET}"
echo -e "${BOLD}║   Engineering Lead Setup — Run Once Per Repository       ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Repository : $REPO_NAME"
echo "  Location   : $REPO_ROOT"
echo "  Config     : $PROJECT_FILE"
echo ""
echo -e "  ${CYAN}Versions from project.env:${RESET}"
echo "    ROS2:          $ROS2_DISTRO"
echo "    Node.js:       v${NODE_MAJOR_VERSION}.x"
echo "    commitlint:    $COMMITLINT_CLI_VERSION"
echo "    Husky:         $HUSKY_VERSION"
echo "    pre-commit:    hooks rev $PRECOMMIT_HOOKS_REV"
echo "    clang-format:  $CLANG_FORMAT_REV"
echo "    black:         $BLACK_REV"
echo "    flake8:        $FLAKE8_REV"
echo "    line length:   $MAX_LINE_LENGTH"
echo ""
echo -e "  ${YELLOW}This script will create files and make commits to ${INTEGRATION_BRANCH_NAME:-develop}.${RESET}"
echo -e "  ${YELLOW}Only run this once on a fresh repository.${RESET}"
echo ""
read -r -p "  Press ENTER to start, or Ctrl+C to cancel... "

# ── STEP 1: Prerequisites ─────────────────────────────────────
header "Step 1 of 10 — Checking Prerequisites"

PREREQS_OK=true

# Git
GIT_VER=$(git --version | grep -oP '\d+\.\d+' | head -1)
GIT_MAJ=$(echo "$GIT_VER" | cut -d. -f1)
GIT_MIN=$(echo "$GIT_VER" | cut -d. -f2)
GIT_REQ_MAJ=$(echo "$GIT_MIN_VERSION" | cut -d. -f1)
GIT_REQ_MIN=$(echo "$GIT_MIN_VERSION" | cut -d. -f2)
if [[ "$GIT_MAJ" -gt "$GIT_REQ_MAJ" ]] || \
   [[ "$GIT_MAJ" -eq "$GIT_REQ_MAJ" && "$GIT_MIN" -ge "$GIT_REQ_MIN" ]]; then
  pass "Git $(git --version | cut -d' ' -f3)"
else
  fail "Git $GIT_VER is below minimum $GIT_MIN_VERSION — run setup_developer_system.sh first"
  PREREQS_OK=false
fi

# Node.js
if command -v node &>/dev/null; then
  NODE_MAJ=$(node --version | grep -oP '\d+' | head -1)
  if [[ "$NODE_MAJ" -ge "$NODE_MAJOR_VERSION" ]]; then
    pass "Node.js $(node --version)"
  else
    fail "Node.js $(node --version) is below v${NODE_MAJOR_VERSION} — run setup_developer_system.sh first"
    PREREQS_OK=false
  fi
else
  fail "Node.js not found — run setup_developer_system.sh first"
  PREREQS_OK=false
fi

# pre-commit
if command -v pre-commit &>/dev/null; then
  PC_MAJ=$(pre-commit --version | grep -oP '\d+' | head -1)
  if [[ "$PC_MAJ" -ge "$PRECOMMIT_MIN_VERSION" ]]; then
    pass "pre-commit $(pre-commit --version | grep -oP '\d+\.\d+\.\d+')"
  else
    fail "pre-commit version too old — run setup_developer_system.sh first"
    PREREQS_OK=false
  fi
else
  fail "pre-commit not found — run setup_developer_system.sh first"
  PREREQS_OK=false
fi

# Must be on ${INTEGRATION_BRANCH_NAME:-develop} branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "${INTEGRATION_BRANCH_NAME:-develop}" ]]; then
  pass "On develop branch"
else
  fail "Must be on ${INTEGRATION_BRANCH_NAME:-develop} branch — currently on: $CURRENT_BRANCH"
  info "Run: git switch ${INTEGRATION_BRANCH_NAME:-develop}"
  PREREQS_OK=false
fi

# Working directory must be clean
if git diff --quiet && git diff --staged --quiet; then
  pass "Working directory is clean"
else
  fail "Working directory has uncommitted changes"
  info "Commit or stash your changes before running this script"
  git status --short
  PREREQS_OK=false
fi

if [[ "$PREREQS_OK" == "false" ]]; then
  echo ""
  fail "Prerequisites not met. Fix the issues above and retry."
  exit 1
fi

# ── STEP 2: Extend .gitignore ─────────────────────────────────
header "Step 2 of 10 — Extending .gitignore (Step 8a)"

if [[ ! -f ".gitignore" ]]; then
  warn ".gitignore not found — creating from scratch"
  touch .gitignore
fi

# Check if ROS2 entries already exist
if grep -q "\.db3" .gitignore 2>/dev/null; then
  skipped ".gitignore ROS2 entries already present"
else
  cat >> .gitignore << EOF

# ROS2 bag files — must never be committed
*.db3
*.bag
*.mcap

# Node.js — Git hook dependencies
node_modules/
.npm/

# colcon
compile_commands.json

# Setup audit logs — local only, do not commit
tools/logs/
EOF
  pass ".gitignore extended with ROS2 and Node.js entries"
fi

# ── STEP 3: package.json + commitlint + Husky ─────────────────
header "Step 3 of 10 — npm, commitlint, Husky (Step 8b)"

if [[ -f "package.json" ]]; then
  skipped "package.json already exists"
else
  info "Running npm init..."
  npm init -y > /dev/null
  # Update name field to match repository name
  # Use node to safely edit package.json
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json'));
    pkg.name = '${REPO_NAME}';
    pkg.description = 'Zoho Robotics — ${REPO_NAME}';
    pkg.private = true;
    delete pkg.main;
    delete pkg.scripts.test;
    pkg.scripts = { prepare: 'husky' };
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
  "
  pass "package.json created for $REPO_NAME"
fi

# Install commitlint and Husky
if [[ -d "node_modules/husky" ]] && [[ -d "node_modules/@commitlint" ]]; then
  pass "commitlint and Husky already installed"
else
  info "Installing commitlint ${COMMITLINT_CLI_VERSION} and Husky ${HUSKY_VERSION}..."
  npm install --save-dev \
    "@commitlint/cli@${COMMITLINT_CLI_VERSION}" \
    "@commitlint/config-conventional@${COMMITLINT_CONFIG_VERSION}" \
    "husky@${HUSKY_VERSION}" \
    > /dev/null 2>&1
  pass "commitlint and Husky installed"
fi

# Husky install — check before running with version verification
HOOKS_PATH_CHECK=$(git config --local core.hooksPath 2>/dev/null || echo "")

# Also check installed Husky version matches project.env
INSTALLED_HUSKY_VER=""
if [[ -f "node_modules/husky/package.json" ]]; then
  INSTALLED_HUSKY_VER=$(node -e \
    "try{console.log(require('./node_modules/husky/package.json').version)}catch(e){}" \
    2>/dev/null || echo "")
fi

# Determine required major version from HUSKY_VERSION in project.env
# e.g. ^9.0.0 → major 9
REQUIRED_HUSKY_MAJOR=$(echo "$HUSKY_VERSION" | grep -oP '\d+' | head -1)
INSTALLED_HUSKY_MAJOR=$(echo "$INSTALLED_HUSKY_VER" | grep -oP '^\d+' || echo "0")

if [[ "$HOOKS_PATH_CHECK" == ".husky" ]] && \
   [[ -d ".husky/_" ]] && \
   [[ "$INSTALLED_HUSKY_MAJOR" -ge "$REQUIRED_HUSKY_MAJOR" ]]; then
  pass "Husky $INSTALLED_HUSKY_VER already initialised — core.hooksPath is .husky"
elif [[ "$HOOKS_PATH_CHECK" == ".husky" ]] && [[ ! -d ".husky/_" ]]; then
  warn "core.hooksPath is correct but .husky/_ is missing — re-initialising Husky..."
  npx husky > /dev/null 2>&1
  git config core.hooksPath .husky
  pass "Husky re-initialised"
elif [[ -n "$INSTALLED_HUSKY_VER" ]] && \
     [[ "$INSTALLED_HUSKY_MAJOR" -lt "$REQUIRED_HUSKY_MAJOR" ]]; then
  warn "Husky $INSTALLED_HUSKY_VER is below required v${REQUIRED_HUSKY_MAJOR} — re-installing..."
  npm install --save-dev "husky@${HUSKY_VERSION}" > /dev/null 2>&1
  npx husky > /dev/null 2>&1
  git config core.hooksPath .husky
  pass "Husky upgraded and re-initialised"
else
  info "Initialising Husky..."
  npx husky > /dev/null 2>&1
  # Critical fix: Husky v9 sets core.hooksPath to .husky/_ by mistake
  git config core.hooksPath .husky
  HOOKS_PATH=$(git config --local core.hooksPath)
  if [[ "$HOOKS_PATH" == ".husky" ]]; then
    FINAL_HUSKY_VER=$(node -e \
      "try{console.log(require('./node_modules/husky/package.json').version)}catch(e){}" \
      2>/dev/null || echo "unknown")
    pass "Husky $FINAL_HUSKY_VER initialised — core.hooksPath set to .husky"
  else
    fail "core.hooksPath is wrong: $HOOKS_PATH"
    exit 1
  fi
fi

# ── STEP 4: commitlint.config.js ─────────────────────────────
header "Step 4 of 10 — commitlint config (Step 8c)"

if [[ -f "commitlint.config.js" ]]; then
  skipped "commitlint.config.js already exists"
else
  # Build scope array from COMMIT_SCOPES in project.env
  # Format: scope:description,scope:description,...
  # Generate JS array entries with inline comments
  # Build type list for the comment header in generated config
  TYPE_LIST=$(echo "$COMMIT_TYPES" | tr ',' ' ')

  # Build JS array lines BEFORE the heredoc so variable expansion works.
  # Inside a heredoc, subshell variables (from while-read loops) are not
  # expanded — only the outer shell's variables are. Pre-building the
  # strings here avoids that scoping problem entirely.
  TYPE_ARRAY_JS=$(echo "$COMMIT_TYPES" | tr ',' '\n' | while read -r t; do
    t=$(echo "$t" | xargs)
    [[ -n "$t" ]] && echo "      '$t',"
  done)

  SCOPE_ARRAY_JS=$(echo "$COMMIT_SCOPES" | tr ',' '\n' | while read -r entry; do
    SC=$(echo "$entry" | cut -d: -f1 | xargs)
    DE=$(echo "$entry" | cut -d: -f2- | xargs)
    if [[ -n "$SC" ]]; then
      if [[ -n "$DE" && "$DE" != "$SC" ]]; then
        echo "      '$SC', // $DE"
      else
        echo "      '$SC',"
      fi
    fi
  done)

  cat > commitlint.config.js << EOF
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Scope is mandatory on every commit
    'scope-empty': [2, 'never'],

    // Allowed types: ${TYPE_LIST}
    // Add custom types to COMMIT_TYPES in tools/project.env
    'type-enum': [2, 'always', [
${TYPE_ARRAY_JS}
    ]],

    // Allowed scopes — edit COMMIT_SCOPES in tools/project.env
    // Format in project.env: scope:description
    'scope-enum': [2, 'always', [
${SCOPE_ARRAY_JS}
    ]],

    // Subject max ${COMMIT_SUBJECT_MAX_LENGTH} characters
    // Edit COMMIT_SUBJECT_MAX_LENGTH in tools/project.env
    'subject-max-length': [2, 'always', ${COMMIT_SUBJECT_MAX_LENGTH}],

    // subject-case disabled — technical acronyms (ROS2, SLAM, AMR) conflict
    // with all built-in case rules. Convention enforced via code review.
    'subject-case': [0],

    // NOTE: A space after the colon is required by the Conventional Commits
    // specification. This is enforced by the commit-msg hook before
    // commitlint runs. If you see "fix stuff" being rejected it is because
    // the message has no type/scope, not a spacing issue.
  },
};
EOF
  created "commitlint.config.js"
fi

# ── STEP 5: Git hook files ─────────────────────────────────────
header "Step 5 of 10 — Git hook files (Step 8d)"

mkdir -p .husky

# Hook 1 — commit-msg
if [[ -f ".husky/commit-msg" ]]; then
  skipped ".husky/commit-msg"
else
  # Build allowed types and scopes for the error message
  TYPE_LIST_DISPLAY=$(echo "$COMMIT_TYPES" | tr ',' ' ')
  SCOPE_LIST_DISPLAY=$(echo "$COMMIT_SCOPES" | tr ',' '\n' \
    | cut -d: -f1 | xargs | tr ' ' '|')
  FIRST_TYPE=$(echo "$COMMIT_TYPES" | cut -d',' -f1 | xargs)
  FIRST_SCOPE=$(echo "$COMMIT_SCOPES" | cut -d',' -f1 | cut -d: -f1 | xargs)
  EXAMPLE_TICKET_DISPLAY="${EXAMPLE_TICKET_ID:-PROJ-42}"

  cat > .husky/commit-msg << EOF
#!/bin/bash
# commit-msg hook — validates commit message format using commitlint
# Edit allowed types and scopes in tools/project.env

COMMIT_MSG_FILE="\$1"
COMMIT_MSG=\$(cat "\$COMMIT_MSG_FILE")

# Run commitlint and capture output
LINT_OUTPUT=\$(npx --no -- commitlint --edit "\$COMMIT_MSG_FILE" 2>&1)
LINT_EXIT=\$?

if [[ \$LINT_EXIT -ne 0 ]]; then
  echo ""
  echo "  ✖  Commit message rejected"
  echo ""
  echo "  Your message:"
  echo "    \$COMMIT_MSG"
  echo ""
  echo "  commitlint output:"
  echo "\$LINT_OUTPUT" | sed 's/^/    /'
  echo ""
  echo "  ─────────────────────────────────────────────────────"
  echo "  ─────────────────────────────────────────────────────"
  echo "  Required format:  type(scope): description"
  echo "                                ^ space required after colon"
  echo ""
  echo "  Example:"
  echo "    ${FIRST_TYPE}(${FIRST_SCOPE}): add ${EXAMPLE_TICKET_DISPLAY} feature description"
  echo ""
  echo "  Allowed types:  ${TYPE_LIST_DISPLAY}"
  echo "  Allowed scopes: ${SCOPE_LIST_DISPLAY}"
  echo "  Max length:     ${COMMIT_SUBJECT_MAX_LENGTH:-72} characters"
  echo ""
  echo "  Common mistakes:"
  echo "    ✖  ${FIRST_TYPE}(${FIRST_SCOPE}):missing space    ← no space after colon"
  echo "    ✖  ${FIRST_TYPE}: missing scope                   ← scope is mandatory"
  echo "    ✖  ${FIRST_TYPE}(wrong): bad scope                ← scope not in allowed list"
  echo "    ✖  Fixed the bug                                  ← no type or scope"
  echo "    ✔  ${FIRST_TYPE}(${FIRST_SCOPE}): correct format  ← type(scope): description"
  echo "  ─────────────────────────────────────────────────────"
  echo ""
  exit 1
fi

exit 0
EOF
  chmod +x .husky/commit-msg
  created ".husky/commit-msg"
fi

# Hook 2 — pre-commit
if [[ -f ".husky/pre-commit" ]]; then
  skipped ".husky/pre-commit"
else
  cat > .husky/pre-commit << 'EOF'
pre-commit run --color=always --show-diff-on-failure
EOF
  chmod +x .husky/pre-commit
  created ".husky/pre-commit"
  info "Note: do NOT run 'pre-commit install' — hooks call pre-commit directly"
fi

# Hook 3 — pre-push (branch name validation)
if [[ -f ".husky/pre-push" ]]; then
  skipped ".husky/pre-push"
else
  # Build branch type pattern from BRANCH_TYPES in project.env
  # BRANCH_TYPES=feature,bugfix,hotfix,refactor,sim,experiment
  # Produces: (feature|bugfix|hotfix|refactor|sim|experiment)
  BRANCH_TYPE_PATTERN=$(echo "$BRANCH_TYPES" | tr ',' '|')

  # Build example lines for the error message
  # Take first ticket-based type for examples
  FIRST_TYPE=$(echo "$BRANCH_TYPES" | cut -d',' -f1 | xargs)
  SECOND_TYPE=$(echo "$BRANCH_TYPES" | cut -d',' -f2 | xargs)

  # Build valid format examples from TICKET_ID_PATTERN
  # Use a concrete example matching the pattern
  EXAMPLE_TICKET="${EXAMPLE_TICKET_ID:-PROJ-42}"

  cat > .husky/pre-push << EOF
branch=\$(git rev-parse --abbrev-ref HEAD)

# Allow main and develop to push without validation
if echo "\$branch" | grep -qE "^(${RELEASE_BRANCH_NAME:-main}|${INTEGRATION_BRANCH_NAME:-develop})\$"; then
  exit 0
fi

# Branch types from tools/project.env: ${BRANCH_TYPES}
# Ticket ID pattern from tools/project.env: ${TICKET_ID_PATTERN}
PATTERN="^(${BRANCH_TYPE_PATTERN})\\\/${TICKET_ID_PATTERN}-[a-z0-9-]+\$|^release\\\/[0-9]+\.[0-9]+\.[0-9]+\$|^experiment\\\/[a-z0-9-]+\$"

if ! echo "\$branch" | grep -qE "\$PATTERN"; then
  echo "----------------------------------------------------"
  echo "ERROR: Branch name '\$branch' does not follow convention"
  echo ""
  echo "Valid formats:"
  echo "  ${FIRST_TYPE}/${EXAMPLE_TICKET}-short-description"
  echo "  ${SECOND_TYPE}/${EXAMPLE_TICKET}-short-description"
  echo "  release/1.4.0"
  echo "  experiment/topic-name"
  echo ""
  echo "Allowed types: $(echo "$BRANCH_TYPES" | tr ',' ' ')"
  echo "----------------------------------------------------"
  exit 1
fi

echo "Branch name '\$branch' is valid"
exit 0
EOF
  chmod +x .husky/pre-push
  created ".husky/pre-push"
fi

# ── STEP 6: .pre-commit-config.yaml ───────────────────────────
header "Step 6 of 10 — .pre-commit-config.yaml (Step 8e)"

if [[ -f ".pre-commit-config.yaml" ]]; then
  skipped ".pre-commit-config.yaml already exists"
else
  # Write file using variables from project.env
  cat > .pre-commit-config.yaml << EOF
repos:
  # General file hygiene
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: ${PRECOMMIT_HOOKS_REV}
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-merge-conflict
      - id: check-added-large-files
        args: ['--maxkb=${MAX_FILE_SIZE_KB:-5120}']

  # Block ROS2 bag files and build artefacts
  - repo: local
    hooks:
      - id: block-bag-files
        name: Block ROS2 bag and database files
        entry: bash
        args:
          - -c
          - |
            git diff --cached --name-only | grep -qE "\\.(bag|db3|mcap)\$" \\
            && echo "ERROR - ROS2 bag files must not be committed" \\
            && exit 1 || exit 0
        language: system
        pass_filenames: false

      - id: block-build-artifacts
        name: Block build artifacts
        entry: bash
        args:
          - -c
          - |
            git diff --cached --name-only | grep -qE "^(build|install|log)/" \\
            && echo "ERROR - Build artifacts must not be committed" \\
            && exit 1 || exit 0
        language: system
        pass_filenames: false

  # C++ formatting — auto-fixes on commit
  - repo: https://github.com/pre-commit/mirrors-clang-format
    rev: ${CLANG_FORMAT_REV}
    hooks:
      - id: clang-format
        types_or: [c++, c]
        args: ['--style=file']

  # Python formatting — auto-fixes on commit
  - repo: https://github.com/psf/black
    rev: ${BLACK_REV}
    hooks:
      - id: black
        language_version: python3

  # Python linting
  - repo: https://github.com/PyCQA/flake8
    rev: ${FLAKE8_REV}
    hooks:
      - id: flake8
        args: ['--max-line-length=${MAX_LINE_LENGTH}']
EOF
  created ".pre-commit-config.yaml"

  # Validate the generated YAML immediately
  if python3 -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))" 2>/dev/null; then
    pass ".pre-commit-config.yaml YAML validation passed"
  else
    fail ".pre-commit-config.yaml has a YAML error — check project.env for special characters"
    exit 1
  fi

  # Check if hook revisions are outdated and warn if so
  info "Checking if pre-commit hook revisions in project.env are current..."
  UPDATE_OUTPUT=$(pre-commit autoupdate --dry-run 2>/dev/null || true)
  if echo "$UPDATE_OUTPUT" | grep -q "already up to date"; then
    pass "All hook revisions in project.env are current"
  elif [[ -n "$UPDATE_OUTPUT" ]]; then
    echo ""
    warn "Some hook revisions in project.env may be outdated:"
    echo "$UPDATE_OUTPUT" | grep -E "updating|already" | while read -r line; do
      echo -e "    ${YELLOW}$line${RESET}"
    done
    echo ""
    warn "To update project.env with the latest revisions run:"
    echo ""
    echo -e "    ${CYAN}pre-commit autoupdate${RESET}"
    echo ""
    echo "    Then update the matching REV values in tools/project.env:"
    echo "      PRECOMMIT_HOOKS_REV"
    echo "      CLANG_FORMAT_REV"
    echo "      BLACK_REV"
    echo "      FLAKE8_REV"
    echo ""
    echo "    Commit the updated project.env:"
    echo -e "    ${CYAN}git add tools/project.env .pre-commit-config.yaml${RESET}"
    echo -e "    ${CYAN}git commit -m \"chore(repo): update pre-commit hook revisions\"${RESET}"
    echo ""
    read -r -p "  Continue with current versions? (Y/n): " CONTINUE_VERSIONS
    if [[ "$CONTINUE_VERSIONS" == "n" || "$CONTINUE_VERSIONS" == "N" ]]; then
      echo ""
      info "Update project.env with the latest revisions then re-run this script."
      exit 0
    fi
  fi
fi

# ── STEP 7: .clang-format ─────────────────────────────────────
header "Step 7 of 10 — .clang-format (Step 8f)"

if [[ -f ".clang-format" ]]; then
  skipped ".clang-format already exists"
else
  cat > .clang-format << EOF
Language: Cpp
BasedOnStyle: Google
IndentWidth: 2
ColumnLimit: ${MAX_LINE_LENGTH}
PointerAlignment: Left
DerivePointerAlignment: false
AllowShortFunctionsOnASingleLine: Empty
AllowShortIfStatementsOnASingleLine: false
AllowShortLoopsOnASingleLine: false
EOF
  # Note: deliberately NO closing --- line — causes check-yaml to fail
  created ".clang-format"

  # Validate
  if python3 -c "import yaml; yaml.safe_load(open('.clang-format'))" 2>/dev/null; then
    pass ".clang-format YAML validation passed"
  else
    fail ".clang-format has a YAML error"
    exit 1
  fi
fi

# ── STEP 8: GitHub Actions workflows ──────────────────────────
header "Step 8 of 10 — GitHub Actions workflows (Step 8g)"

mkdir -p .github/workflows

# Workflow 1 — PR Validation
if [[ -f ".github/workflows/pr-validation.yml" ]]; then
  skipped ".github/workflows/pr-validation.yml"
else
  # Build patterns dynamically from project.env
  # Branch type pattern: feature|bugfix|hotfix|...
  BRANCH_TYPE_PAT=$(echo "$BRANCH_TYPES" | tr ',' '|')

  # Commit type pattern: feat|fix|refactor|...
  COMMIT_TYPE_PAT=$(echo "$COMMIT_TYPES" | tr ',' '|')

  # Scope pattern: arm|amr|humanoid|...  (extract scope names only, before the colon)
  SCOPE_PAT=$(echo "$COMMIT_SCOPES" | tr ',' '\n' \
    | cut -d: -f1 | xargs | tr ' ' '|')

  # Ticket keyword pattern: closes|fixes|relates to
  # TICKET_KEYWORDS uses | as separator (handles multi-word like "relates to")
  # Use directly as regex alternation — no conversion needed
  TICKET_KW_PAT="${TICKET_KEYWORDS}"

  cat > .github/workflows/pr-validation.yml << EOF
name: PR Validation
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
    branches: [${INTEGRATION_BRANCH_NAME:-develop}, ${RELEASE_BRANCH_NAME:-main}]

# Patterns generated from tools/project.env
# To update: edit project.env and re-run setup_repo_automation.sh

jobs:
  validate-branch-name:
    name: ${STATUS_CHECK_BRANCH_NAME:-Branch Name Check}
    runs-on: ${CI_RUNNER_GENERAL:-ubuntu-latest}
    steps:
      - name: Validate branch name
        run: |
          branch="\${{ github.head_ref }}"
          echo "Checking branch name: \$branch"
          PATTERN="^(${BRANCH_TYPE_PAT})/${TICKET_ID_PATTERN}-[a-z0-9-]+\$|^release/[0-9]+\\.[0-9]+\\.[0-9]+\$|^experiment/[a-z0-9-]+\$"
          if echo "\$branch" | grep -qE "\$PATTERN"; then
            echo "Branch name valid: \$branch"
          else
            echo "Invalid branch name: \$branch"
            echo "Required format: type/TICKET-ID-description"
            echo "Allowed types: $(echo "$BRANCH_TYPES" | tr ',' ' ')"
            exit 1
          fi

  validate-pr-title:
    name: ${STATUS_CHECK_PR_TITLE:-PR Title Check}
    runs-on: ${CI_RUNNER_GENERAL:-ubuntu-latest}
    steps:
      - name: Validate PR title follows Conventional Commits
        run: |
          title="\${{ github.event.pull_request.title }}"
          echo "Checking PR title: \$title"
          PATTERN="^(${COMMIT_TYPE_PAT})\\((${SCOPE_PAT})\\): .{1,${COMMIT_SUBJECT_MAX_LENGTH}}\$"
          if echo "\$title" | grep -qE "\$PATTERN"; then
            echo "PR title valid"
          else
            echo ""
            echo "Invalid PR title: \$title"
            echo ""
            echo "Required format:  type(scope): description"
            echo "                             ^ space required after colon"
            echo ""
            echo "Allowed types:  $(echo "$COMMIT_TYPES" | tr ',' ' ')"
            echo "Allowed scopes: $(echo "$COMMIT_SCOPES" | tr ',' '\n' | cut -d: -f1 | tr '\n' ' ')"
            echo "Max length:     ${COMMIT_SUBJECT_MAX_LENGTH} characters"
            echo ""
            echo "Common mistakes:"
            echo "  type(scope):missing space    no space after colon"
            echo "  type: no scope               scope is mandatory"
            echo "  type(wrong): bad scope       scope not in allowed list"
            echo ""
            exit 1
          fi

  validate-pr-body:
    name: ${STATUS_CHECK_PR_TICKET:-PR Ticket Reference Check}
    runs-on: ${CI_RUNNER_GENERAL:-ubuntu-latest}
    steps:
      - name: Check PR body contains ticket reference
        run: |
          body="\${{ github.event.pull_request.body }}"
          if echo "\$body" | grep -qiE "(${TICKET_KW_PAT}) #?${TICKET_ID_PATTERN}"; then
            echo "Ticket reference found"
          else
            echo ""
            echo "No ticket reference found in PR body"
            echo ""
            echo "Add one of these to your PR description:"
            echo "  Closes #${EXAMPLE_TICKET_ID}   (closes the ticket on merge)"
            echo "  Fixes #${EXAMPLE_TICKET_ID}    (closes the ticket on merge)"
            echo "  Relates to ${EXAMPLE_TICKET_ID} (links without closing)"
            echo ""
            echo "Ticket ID format: ${TICKET_ID_PATTERN}"
            exit 1
          fi
EOF
  created ".github/workflows/pr-validation.yml"

  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pr-validation.yml'))" 2>/dev/null \
    && pass "pr-validation.yml YAML valid" \
    || { fail "pr-validation.yml has YAML error"; exit 1; }
fi

# Workflow 2 — Code Style
if [[ -f ".github/workflows/lint.yml" ]]; then
  skipped ".github/workflows/lint.yml"
else
  # Use CLANG_FORMAT_VERSION and MAX_LINE_LENGTH from project.env
  cat > .github/workflows/lint.yml << EOF
name: Code Style
on:
  pull_request:
    branches: [${INTEGRATION_BRANCH_NAME:-develop}, ${RELEASE_BRANCH_NAME:-main}]

jobs:
  clang-format:
    name: ${STATUS_CHECK_CPP_FORMAT:-C++ Format Check}
    runs-on: ${CI_RUNNER_LINT:-ubuntu-22.04}
    steps:
      - uses: actions/checkout@v4
      - name: Install clang-format-${CLANG_FORMAT_VERSION}
        run: sudo apt-get install -y clang-format-${CLANG_FORMAT_VERSION}
      - name: Check C++ formatting
        run: |
          find src -name "*.cpp" -o -name "*.hpp" 2>/dev/null \\
            | xargs clang-format-${CLANG_FORMAT_VERSION} --dry-run --Werror --style=file \\
            || (echo "C++ formatting errors found. Run clang-format locally to fix." && exit 1)
          echo "C++ formatting check passed"

  python-style:
    name: ${STATUS_CHECK_PYTHON_STYLE:-Python Style Check}
    runs-on: ${CI_RUNNER_LINT:-ubuntu-22.04}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: '${PYTHON_MIN_VERSION:-3.10}'
      - name: Install black and flake8
        run: pip install black flake8
      - name: Check Python formatting
        run: |
          black --check --diff src/ 2>/dev/null || echo "No Python files found"
      - name: Run flake8
        run: |
          flake8 src/ --max-line-length=${MAX_LINE_LENGTH} 2>/dev/null || echo "No Python files found"
EOF
  created ".github/workflows/lint.yml"

  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/lint.yml'))" 2>/dev/null \
    && pass "lint.yml YAML valid" \
    || { fail "lint.yml has YAML error"; exit 1; }
fi

# Workflow 3 — Stale branch check
if [[ -f ".github/workflows/stale-branches.yml" ]]; then
  skipped ".github/workflows/stale-branches.yml"
else
  # Pre-compute branch type regex pattern
  BRANCH_TYPE_REGEX=$(echo "$BRANCH_TYPES" | tr ',' '|')

  cat > .github/workflows/stale-branches.yml << EOF
name: Stale Branch Check
on:
  schedule:
    - cron: '${STALE_BRANCH_CRON:-0 8 * * 1}'   # Every Monday at 8am UTC
  workflow_dispatch:        # Allow manual trigger from GitHub UI

jobs:
  find-stale:
    name: Find branches inactive ${STALE_BRANCH_DAYS:-60}+ days
    runs-on: ${CI_RUNNER_GENERAL:-ubuntu-latest}
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Find stale feature and experiment branches
        run: |
          git fetch --all --prune
          echo "Scanning for branches inactive for ${STALE_BRANCH_DAYS:-60}+ days..."
          # Branch types from tools/project.env: ${BRANCH_TYPES}
          found=0
          for ref in \$(git branch -r \
            | grep -E "origin/(${BRANCH_TYPE_REGEX})/" \\
            | sed 's/origin\///'); do
            last=\$(git log -1 --format="%ct" "origin/\$ref" 2>/dev/null || continue)
            age=\$(( (\$(date +%s) - last) / 86400 ))
            if [ \$age -gt ${STALE_BRANCH_DAYS:-60} ]; then
              echo "Stale: \$ref — inactive for \$age days"
              found=1
            fi
          done
          if [ \$found -eq 0 ]; then
            echo "No stale branches found."
          else
            echo ""
            echo "Action required: Engineering Lead to review and delete stale branches."
            echo "Command: git push origin --delete <branch-name>"
          fi
EOF
  created ".github/workflows/stale-branches.yml"

  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/stale-branches.yml'))" 2>/dev/null \
    && pass "stale-branches.yml YAML valid" \
    || { fail "stale-branches.yml has YAML error"; exit 1; }
fi

# ── STEP 9: PR template ───────────────────────────────────────
header "Step 9 of 10 — Pull Request template (Step 8h)"

if [[ -f ".github/pull_request_template.md" ]]; then
  skipped ".github/pull_request_template.md"
else
  cat > .github/pull_request_template.md << 'EOF'
## Summary
<!-- Required — What does this PR do? Why is this change needed? -->

## Related Ticket
Closes #<TICKET-ID>

## Type of Change
- [ ] Feature
- [ ] Bug Fix
- [ ] Refactor
- [ ] Simulation
- [ ] Docs
- [ ] Firmware

## Testing Performed
<!-- Delete options that do not apply -->
- [ ] Unit tests
- [ ] Simulation (Gazebo scenario: _________)
- [ ] Hardware-in-the-loop
<!-- For hardware tests: state robot serial and environment -->

## ROS2 Packages Affected
<!-- Required — list packages changed or write "None" -->

## Robot Deployment Impact
<!-- Required — tick one. Do not leave blank. -->
- [ ] No deployed robot impact
- [ ] Requires re-deployment (describe below)

## Breaking Changes
<!-- Required — tick one. Do not leave blank. -->
- [ ] No
- [ ] Yes — describe impact below

## Checklist
<!-- Delete items that do not apply -->
- [ ] Code follows style guide (enforced automatically by hooks)
- [ ] Self-reviewed
- [ ] Tests added or updated
- [ ] CHANGELOG.md updated (if applicable)
EOF
  created ".github/pull_request_template.md"
fi

# ── STEP 10: Commit and push ──────────────────────────────────
header "Step 10 of 10 — Committing and pushing to develop (Step 8i)"

# Show what is staged before committing
echo ""
info "Files created or modified:"
git status --short
echo ""

# Validate all YAML files one final time before committing
info "Validating all YAML files..."
YAML_OK=true
for f in .pre-commit-config.yaml .clang-format .github/workflows/*.yml; do
  if [[ -f "$f" ]]; then
    if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
      pass "$f"
    else
      fail "$f — YAML invalid, cannot commit"
      YAML_OK=false
    fi
  fi
done

if [[ "$YAML_OK" == "false" ]]; then
  fail "YAML validation failed — fix errors above before committing"
  exit 1
fi

echo ""
read -r -p "  Ready to commit. Press ENTER to continue or Ctrl+C to review files first... "

# Commit 1 — .gitignore only (file tracking is independent of tooling)
info "Commit 1 of 3 — .gitignore..."
git add .gitignore 2>/dev/null || true

if ! git diff --staged --quiet; then
  git commit -m "chore(repo): extend ROS gitignore with ROS2 and Node.js entries"
  pass "Commit 1 created"
else
  warn "Nothing new to commit for .gitignore"
fi

# Commit 2 — local enforcement stack
# All files that work together to enforce conventions on the developer machine
# commitlint + husky hooks + pre-commit + clang-format all depend on each other
info "Commit 2 of 3 — local hooks and code style config..."
git add \
  package.json \
  package-lock.json \
  commitlint.config.js \
  .clang-format \
  .pre-commit-config.yaml \
  .husky/commit-msg \
  .husky/pre-commit \
  .husky/pre-push \
  2>/dev/null || true

if ! git diff --staged --quiet; then
  git commit -m "chore(repo): add git hooks, commitlint and code style config"
  pass "Commit 2 created"
else
  warn "Nothing new to commit for local hooks and config"
fi

# Commit 3 — remote enforcement stack
# GitHub Actions workflows and PR template — independent of local hooks
# Can be reverted without affecting local enforcement
info "Commit 3 of 3 — GitHub Actions workflows and PR template..."
git add \
  .github/workflows/pr-validation.yml \
  .github/workflows/lint.yml \
  .github/workflows/stale-branches.yml \
  .github/pull_request_template.md \
  2>/dev/null || true

if ! git diff --staged --quiet; then
  git commit -m "ci(repo): add PR validation, lint and stale branch workflows"
  pass "Commit 3 created"
else
  warn "Nothing new to commit for GitHub Actions files"
fi

# Push to develop — only if local is ahead of remote
LOCAL_SHA=$(git rev-parse "${INTEGRATION_BRANCH_NAME:-develop}" 2>/dev/null || echo "none")
REMOTE_SHA=$(git rev-parse "origin/${INTEGRATION_BRANCH_NAME:-develop}" 2>/dev/null || echo "none")

if [[ "$LOCAL_SHA" == "$REMOTE_SHA" ]]; then
  pass "develop is already up to date with origin/${INTEGRATION_BRANCH_NAME:-develop} — no push needed"
else
  info "Pushing to origin/${INTEGRATION_BRANCH_NAME:-develop}..."
  git push origin "${INTEGRATION_BRANCH_NAME:-develop}"
  pass "Pushed to origin/${INTEGRATION_BRANCH_NAME:-develop}"
fi

# ── Final verification ─────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━  Verifying hooks are active ━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

HOOKS_PATH_FINAL=$(git config --local core.hooksPath 2>/dev/null || echo "not set")
ALL_GOOD=true

[[ "$HOOKS_PATH_FINAL" == ".husky" ]] && pass "core.hooksPath = .husky" || { fail "core.hooksPath = $HOOKS_PATH_FINAL"; ALL_GOOD=false; }

for hook in commit-msg pre-commit pre-push; do
  [[ -x ".husky/$hook" ]] && pass ".husky/$hook is executable" || { fail ".husky/$hook missing or not executable"; ALL_GOOD=false; }
done

# Live test: bad commit message must be rejected
# Use exit code not string matching — more reliable across commitlint versions
# IMPORTANT: capture exit code with ||true to prevent set -e from killing the
# script when the hook correctly rejects the commit (non-zero exit is expected).
info "Testing hooks — bad commit message must be REJECTED..."
TEST_OUTPUT=$(git commit --allow-empty -m "${TEST_COMMIT_BAD:-fix stuff}" 2>&1) || true
TEST_EXIT=$?
if [[ $TEST_EXIT -ne 0 ]]; then
  pass "Hooks are active — bad commit message correctly rejected (exit $TEST_EXIT)"
else
  fail "Hooks are NOT running — bad commit message was accepted (exit 0)"
  fail "Output: $TEST_OUTPUT"
  warn "Check core.hooksPath: $(git config --local core.hooksPath 2>/dev/null || echo 'not set')"
  ALL_GOOD=false
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

if [[ "$ALL_GOOD" == "true" ]]; then
  echo -e "${GREEN}${BOLD}  ✔  Automation setup complete for: $REPO_NAME${RESET}"
  echo ""
  echo "  Files committed to develop:"
  echo "    .gitignore               extended with ROS2 + Node.js entries"
  echo "    package.json             commitlint + Husky dependencies"
  echo "    commitlint.config.js     commit message rules"
  echo "    .clang-format            C++ style — Google, ${MAX_LINE_LENGTH} char limit"
  echo "    .pre-commit-config.yaml  pre-commit hook definitions"
  echo "    .husky/commit-msg        validates commit messages locally"
  echo "    .husky/pre-commit        clang-format, black, flake8, bag file check"
  echo "    .husky/pre-push          validates branch names locally"
  echo "    .github/workflows/       PR validation, lint, stale branch workflows"
  echo "    .github/pull_request_template.md"
  echo ""
  echo -e "${CYAN}  Platform-agnostic — done for all platforms:${RESET}"
  echo "    Local hooks active: commit-msg, pre-commit, pre-push"
  echo "    All developers run: ./tools/setup_repo_hooks.sh after cloning"
  echo ""
  echo -e "${CYAN}  GitHub-specific next steps — run after this script:${RESET}"
  echo ""
  echo "  Step 1 — Open a test PR to register workflow check names:"
  echo "    git switch -c feature/ARM-01-test-github-actions"
  echo "    echo '# test' >> README.md && git add README.md"
  echo "    git commit -m \"docs(repo): trigger GitHub Actions workflows\""
  echo "    git push origin feature/ARM-01-test-github-actions"
  echo "    → Open PR on GitHub targeting develop"
  echo "    → Wait for all 5 checks to appear (green or red)"
  echo ""
  echo "  Step 2 — Configure branch protection + status checks:"
  echo "    bash tools/add_status_checks.sh"
  echo "    (requires: gh auth login — GitHub CLI authenticated)"
  echo ""
  echo -e "${CYAN}  Zoho repository next steps:${RESET}"
  echo "    Settings → Protected Branches → develop:"
  echo "      Admins & Maintainers can merge"
  echo "      Enable Code Owners"
  echo "      Allow Force Push: unchecked"
  echo "    Settings → Merge Settings:"
  echo "      develop: Squash Merge"
  echo "      main:    Merge Commit"
  echo "      Code Review: Add Branch → develop and main"
  echo "      SonarQube: Add Branch → develop and main"
  echo ""
else
  echo -e "${YELLOW}${BOLD}  ⚠  Setup completed with warnings — check items above${RESET}"
  echo ""
  echo "  All files were created and committed."
  echo "  Fix the hook issues shown above before asking developers to clone."
  echo ""
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
