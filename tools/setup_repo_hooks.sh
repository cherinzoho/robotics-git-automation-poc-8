#!/bin/bash
# ============================================================
#  Zoho Robotics — Repository Hook Setup Script
#  Run once inside each cloned repository.
#
#  Versions are read from tools/project.env in the repository.
#  To upgrade a tool, update project.env — not this script.
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass()  { echo -e "  ${GREEN}✔  $1${RESET}"; }
fail()  { echo -e "  ${RED}✖  $1${RESET}"; }
info()  { echo -e "  ${CYAN}→  $1${RESET}"; }
warn()  { echo -e "  ${YELLOW}⚠  $1${RESET}"; }
header(){ echo ""; echo -e "${BOLD}━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

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

# ── Load project.env from repository's tools/ directory ─────
PROJECT_FILE="$REPO_ROOT/tools/project.env"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo ""
  fail "project.env not found at: $PROJECT_FILE"
  echo ""
  echo "  This file should be committed in the repository under tools/"
  echo "  Ask your Engineering Lead — the repository may not have"
  echo "  the automation setup committed yet."
  echo ""
  exit 1
fi

# shellcheck source=tools/project.env
source "$PROJECT_FILE"

# Validate required variables
REQUIRED_VARS=(NODE_MAJOR_VERSION PRECOMMIT_MIN_VERSION)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    fail "project.env is missing required variable: $var"
    exit 1
  fi
done

clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Zoho Robotics — Repository Hook Setup             ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Repository : $REPO_NAME"
echo "  Location   : $REPO_ROOT"
echo "  Config     : $PROJECT_FILE"
echo ""
echo -e "  ${CYAN}Tool versions from project.env:${RESET}"
echo "    Node.js:    v${NODE_MAJOR_VERSION}.x"
echo "    pre-commit: v${PRECOMMIT_MIN_VERSION}.x minimum"
[[ -n "$ROS2_DISTRO" ]] && echo "    ROS2:       $ROS2_DISTRO"
echo ""
read -r -p "  Press ENTER to start, or Ctrl+C to cancel... "

# ── STEP 1: Prerequisite checks ──────────────────────────────
header "Step 1 of 5 — Checking prerequisites"

PREREQS_OK=true

# Node.js — check against NODE_MAJOR_VERSION from project.env
if ! command -v node &>/dev/null; then
  fail "Node.js is not installed"
  info "Run setup_developer_system.sh first"
  PREREQS_OK=false
else
  INSTALLED_MAJOR=$(node --version | grep -oP '\d+' | head -1)
  if [[ "$INSTALLED_MAJOR" -ge "$NODE_MAJOR_VERSION" ]]; then
    pass "Node.js $(node --version)  (need v${NODE_MAJOR_VERSION}+)"
  else
    fail "Node.js $(node --version) is below v${NODE_MAJOR_VERSION}"
    info "Run setup_developer_system.sh to upgrade"
    PREREQS_OK=false
  fi
fi

# pre-commit — check against PRECOMMIT_MIN_VERSION from project.env
if ! command -v pre-commit &>/dev/null; then
  fail "pre-commit is not installed"
  info "Run setup_developer_system.sh first"
  PREREQS_OK=false
else
  PC_MAJOR=$(pre-commit --version | grep -oP '\d+' | head -1)
  if [[ "$PC_MAJOR" -ge "$PRECOMMIT_MIN_VERSION" ]]; then
    pass "pre-commit $(pre-commit --version | grep -oP '\d+\.\d+\.\d+')  (need v${PRECOMMIT_MIN_VERSION}+)"
  else
    fail "pre-commit version is below v${PRECOMMIT_MIN_VERSION}"
    info "Run: pipx upgrade pre-commit"
    PREREQS_OK=false
  fi
fi

# package.json must exist
if [[ ! -f "$REPO_ROOT/package.json" ]]; then
  fail "package.json not found in repository root"
  info "Contact your Engineering Lead — automation files may not be committed yet"
  PREREQS_OK=false
else
  pass "package.json found"
fi

# .husky directory must exist
if [[ ! -d "$REPO_ROOT/.husky" ]]; then
  fail ".husky/ directory not found in repository"
  info "Contact your Engineering Lead — automation files may not be committed yet"
  PREREQS_OK=false
else
  pass ".husky/ directory found"
fi

# .pre-commit-config.yaml must exist
if [[ ! -f "$REPO_ROOT/.pre-commit-config.yaml" ]]; then
  warn ".pre-commit-config.yaml not found — pre-commit checks will not run"
else
  pass ".pre-commit-config.yaml found"
fi

if [[ "$PREREQS_OK" == "false" ]]; then
  echo ""
  fail "Prerequisites not met. Fix the issues above before continuing."
  echo ""
  exit 1
fi

# ── STEP 2: Switch to develop ─────────────────────────────────
header "Step 2 of 5 — Confirming branch"

cd "$REPO_ROOT"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "${INTEGRATION_BRANCH_NAME:-develop}" ]]; then
  pass "Already on ${INTEGRATION_BRANCH_NAME:-develop} branch"
elif git show-ref --verify --quiet refs/remotes/origin/${INTEGRATION_BRANCH_NAME:-develop}; then
  info "Switching to ${INTEGRATION_BRANCH_NAME:-develop}..."
  git switch "${INTEGRATION_BRANCH_NAME:-develop}" 2>/dev/null || git checkout "${INTEGRATION_BRANCH_NAME:-develop}"
  pass "Switched to ${INTEGRATION_BRANCH_NAME:-develop}"
else
  warn "${INTEGRATION_BRANCH_NAME:-develop} branch not found — staying on $CURRENT_BRANCH"
  warn "Ask your Engineering Lead whether ${INTEGRATION_BRANCH_NAME:-develop} has been created"
fi

# ── STEP 3: Install npm dependencies ─────────────────────────
header "Step 3 of 5 — Installing npm dependencies (commitlint + Husky)"

# Check if dependencies from package.json are already installed
if [[ -d "node_modules/husky" ]] && [[ -d "node_modules/@commitlint" ]]; then
  # Verify installed commitlint version matches project.env if specified
  if [[ -n "$COMMITLINT_CLI_VERSION" ]]; then
    INSTALLED_CL=$(node -e "try{console.log(require('./node_modules/@commitlint/cli/package.json').version)}catch(e){console.log('unknown')}" 2>/dev/null)
    pass "commitlint $INSTALLED_CL already installed"
    pass "Husky already installed"
  else
    pass "npm dependencies already installed"
  fi
else
  info "Running npm install..."
  npm install
  pass "npm dependencies installed"
  # Show what was installed
  CL_VER=$(node -e "try{console.log(require('./node_modules/@commitlint/cli/package.json').version)}catch(e){console.log('unknown')}" 2>/dev/null)
  HK_VER=$(node -e "try{console.log(require('./node_modules/husky/package.json').version)}catch(e){console.log('unknown')}" 2>/dev/null)
  pass "  commitlint: $CL_VER"
  pass "  husky:      $HK_VER"
fi

# ── STEP 4: Initialise Husky and fix hooksPath ───────────────
header "Step 4 of 5 — Initialising Husky hooks"

info "Initialising Husky..."
# Husky v9 — use npm run prepare which calls 'husky install' via package.json
# This avoids the 'install command is DEPRECATED' warning from npx husky install
if npm run prepare > /dev/null 2>&1; then
  pass "Husky initialised via npm run prepare"
else
  # Fallback for repos where prepare script is not set
  npx husky > /dev/null 2>&1 || true
  pass "Husky initialised"
fi

# Critical fix: Husky v9 sets core.hooksPath to .husky/_ instead of .husky
CURRENT_HOOKS_PATH=$(git config --local core.hooksPath 2>/dev/null || echo "not set")

if [[ "$CURRENT_HOOKS_PATH" == ".husky" ]]; then
  pass "core.hooksPath correctly set to .husky"
elif [[ "$CURRENT_HOOKS_PATH" == ".husky/_" ]]; then
  warn "Husky v9 set core.hooksPath to .husky/_ — fixing automatically..."
  git config core.hooksPath .husky
  pass "core.hooksPath fixed: now .husky"
else
  info "Setting core.hooksPath to .husky..."
  git config core.hooksPath .husky
  pass "core.hooksPath set to .husky"
fi

# Verify and fix hook file permissions
HOOKS_OK=true
for hook in commit-msg pre-commit pre-push; do
  if [[ -f ".husky/$hook" ]]; then
    chmod +x ".husky/$hook"
    pass ".husky/$hook  ✔ executable"
  else
    fail ".husky/$hook  ✖ MISSING"
    HOOKS_OK=false
  fi
done

if [[ "$HOOKS_OK" == "false" ]]; then
  echo ""
  warn "Some hook files are missing — contact your Engineering Lead"
fi

# ── STEP 5: Test the hooks ────────────────────────────────────
header "Step 5 of 5 — Testing hooks"

echo ""
info "Test 1: Bad commit message must be REJECTED..."
TEST1_OUTPUT=$(git commit --allow-empty -m "${TEST_COMMIT_BAD:-fix stuff}" 2>&1 || true)
if echo "$TEST1_OUTPUT" | grep -qiE "problems|error|rejected|subject|scope|type"; then
  pass "Test 1 PASSED — bad commit message correctly rejected"
else
  fail "Test 1 FAILED — bad commit message was NOT rejected"
  warn "Hooks are not running. Trying automatic fix..."
  git config core.hooksPath .husky
  # Retry test
  TEST1_RETRY=$(git commit --allow-empty -m "${TEST_COMMIT_BAD:-fix stuff}" 2>&1 || true)
  if echo "$TEST1_RETRY" | grep -qiE "problems|error|rejected|subject|scope|type"; then
    pass "Test 1 PASSED after fix"
  else
    fail "Test 1 still failing after fix — ask your mentor"
    HOOKS_OK=false
  fi
fi

echo ""
info "Test 2: Valid commit message must PASS..."
TEST2_OUTPUT=$(git commit --allow-empty -m "${TEST_COMMIT_GOOD:-chore(repo): verify automation hooks are active}" 2>&1) || true
if echo "$TEST2_OUTPUT" | grep -qE "\[develop|develop\]|\[.*\].*feat"; then
  pass "Test 2 PASSED — valid commit accepted"
  # Clean up the test commit
  git reset HEAD~1 --soft 2>/dev/null || true
else
  # pre-commit might have run and printed output without the branch in the same line
  if ! echo "$TEST2_OUTPUT" | grep -qi "error\|failed\|problems"; then
    pass "Test 2 PASSED — valid commit accepted"
    git reset HEAD~1 --soft 2>/dev/null || true
  else
    fail "Test 2 FAILED — valid commit was rejected unexpectedly"
    echo "  Output: $TEST2_OUTPUT"
    HOOKS_OK=false
  fi
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

HOOKS_PATH_FINAL=$(git config --local core.hooksPath 2>/dev/null || echo "not set")

if [[ "$HOOKS_PATH_FINAL" == ".husky" && "$HOOKS_OK" == "true" ]]; then
  echo -e "${GREEN}${BOLD}  ✔  Repository hooks are active for: $REPO_NAME${RESET}"
  echo ""
  echo "  Active hooks:"
  echo "    commit-msg  — validates Conventional Commits format"
  echo "    pre-commit  — clang-format, black, flake8, bag file check"
  echo "    pre-push    — validates branch naming convention"
  echo ""
  echo "  project.env: $PROJECT_FILE"
  echo ""
  echo -e "${CYAN}  You are ready to start working. Create your first branch:${RESET}"
  echo ""
  echo -e "  ${BOLD}git switch -c feature/TICKET-ID-short-description${RESET}"
  echo ""
else
  echo -e "${YELLOW}${BOLD}  ⚠  Setup completed with warnings${RESET}"
  echo ""
  echo "  Check the items marked with ✖ above and ask your mentor."
  echo ""
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
