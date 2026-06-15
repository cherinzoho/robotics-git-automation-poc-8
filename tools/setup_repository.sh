#!/bin/bash
# ============================================================
#  Robotics Division — Repository Setup Orchestrator
#  Master script that runs all setup scripts in the correct
#  order based on the target Git platform.
#
#  Usage:
#    bash tools/setup_repository.sh --platform github
#    bash tools/setup_repository.sh --platform zoho
#    bash tools/setup_repository.sh --platform gitlab
#
#  What it does:
#    1. Validates prerequisites (laptop setup already done)
#    2. Runs setup_repo_automation.sh  (all platforms)
#    3. Runs add_status_checks.sh      (GitHub only)
#    4. Prints manual steps            (Zoho / GitLab)
#
#  What it does NOT do:
#    - Does not run setup_developer_system.sh
#      (machine setup is separate, done once per machine)
#    - Does not run setup_repo_hooks.sh
#      (developer setup is separate, done per clone by each developer)
#
#  Prerequisites:
#    - setup_developer_system.sh must have been run on this machine
#    - Repository must be cloned and on develop branch
#    - tools/project.env must exist in the repository
# ============================================================

set -e

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Audit log ─────────────────────────────────────────────────
# All output mirrored to a temp log, then copied to tools/logs/ after repo detection
# The temp log is always available at /tmp/ even if script fails partway through
AUDIT_LOG="/tmp/setup_repository_$(date +%Y%m%d_%H%M%S).log"
FINAL_LOG=""  # set after repo detection

# Mirror all stdout and stderr to the log file
exec > >(tee -a "$AUDIT_LOG") 2>&1

echo "Setup started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Script: setup_repository.sh"
echo "PID: $$"
echo ""

# Trap to copy log to repository even if script exits early or fails
_copy_log_on_exit() {
  if [[ -n "$FINAL_LOG" ]]; then
#    cp "$AUDIT_LOG" "$FINAL_LOG" 2>/dev/null || true
    sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9]*[A-Za-z]//g' "$AUDIT_LOG" > "$FINAL_LOG" 2>/dev/null || true 
    echo ""
    echo "Audit log: $FINAL_LOG"
  else
    echo ""
    echo "Audit log (temp): $AUDIT_LOG"
  fi
}
trap _copy_log_on_exit EXIT

pass()    { echo -e "  ${GREEN}✔  $1${RESET}"; }
fail()    { echo -e "  ${RED}✖  $1${RESET}"; }
info()    { echo -e "  ${CYAN}→  $1${RESET}"; }
warn()    { echo -e "  ${YELLOW}⚠  $1${RESET}"; }
header()  { echo ""; echo -e "${BOLD}━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
section() { echo ""; echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${RESET}";
            echo -e "${BOLD}${BLUE}║  $1$(printf '%*s' $((54 - ${#1})) '')║${RESET}";
            echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${RESET}"; echo ""; }

# ── Parse arguments ──────────────────────────────────────────
PLATFORM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --platform=*)
      PLATFORM="${1#*=}"
      shift
      ;;
    -h|--help)
      echo ""
      echo "Usage: bash tools/setup_repository.sh --platform <platform>"
      echo ""
      echo "Platforms:"
      echo "  github  — GitHub (github.com or GitHub Enterprise)"
      echo "            Runs full automation including branch protection"
      echo "            and status checks via GitHub CLI"
      echo ""
      echo "  zoho    — Zoho Repository (repository.zoho.in)"
      echo "            Runs automation stack (local hooks, workflows committed)"
      echo "            Prints manual Zoho configuration steps"
      echo ""
      echo "  gitlab  — GitLab (gitlab.com or self-hosted)"
      echo "            Runs automation stack"
      echo "            Prints manual GitLab configuration steps"
      echo ""
      echo "Example:"
      echo "  cd ~/robotics-dev/robotic-arm-sdk"
      echo "  bash tools/setup_repository.sh --platform github"
      echo ""
      exit 0
      ;;
    *)
      echo ""
      echo -e "${RED}Unknown argument: $1${RESET}"
      echo "Run with --help for usage."
      echo ""
      exit 1
      ;;
  esac
done

# Validate platform argument
if [[ -z "$PLATFORM" ]]; then
  echo ""
  echo -e "${RED}✖  --platform is required${RESET}"
  echo ""
  echo "Usage: bash tools/setup_repository.sh --platform <github|zoho|gitlab>"
  echo "Run with --help for details."
  echo ""
  exit 1
fi

case "$PLATFORM" in
  github|zoho|gitlab) ;;
  *)
    echo ""
    echo -e "${RED}✖  Unknown platform: $PLATFORM${RESET}"
    echo ""
    echo "Supported platforms: github  zoho  gitlab"
    echo ""
    exit 1
    ;;
esac

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

# Set up log directory now that we know the repo location
LOG_DIR="$REPO_ROOT/tools/logs"
mkdir -p "$LOG_DIR"
# FINAL_LOG set at end of script so timestamp reflects completion time

# ── Locate tools directory ────────────────────────────────────
TOOLS_DIR="$REPO_ROOT/tools"

if [[ ! -d "$TOOLS_DIR" ]]; then
  echo ""
  fail "tools/ directory not found at: $TOOLS_DIR"
  fail "The setup scripts must be in tools/ before running this script."
  echo ""
  echo "  Copy the tools/ directory from the POC repository:"
  echo "    cp -r ~/robotics-dev/robotics-git-automation-poc/tools ."
  echo "    git add tools/"
  echo "    git commit -m \"chore(repo): add automation scripts and versions config\""
  echo "    git push origin develop"
  echo ""
  exit 1
fi

# Verify required scripts exist
MISSING_SCRIPTS=false
for script in setup_repo_automation.sh add_status_checks.sh setup_repo_hooks.sh; do
  if [[ ! -f "$TOOLS_DIR/$script" ]]; then
    fail "Missing: tools/$script"
    MISSING_SCRIPTS=true
  fi
done
if [[ "$MISSING_SCRIPTS" == "true" ]]; then
  echo ""
  fail "Required scripts missing from tools/ — copy them from the POC repository"
  exit 1
fi

# ── Load project.env ─────────────────────────────────────────
PROJECT_FILE="$TOOLS_DIR/project.env"
if [[ ! -f "$PROJECT_FILE" ]]; then
  fail "tools/project.env not found"
  exit 1
fi
# shellcheck source=tools/project.env
source "$PROJECT_FILE"

# ── Track timing ──────────────────────────────────────────────
START_TIME=$(date +%s)
elapsed() {
  local END
  END=$(date +%s)
  echo $(( END - START_TIME ))
}

# ── Intro ─────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Robotics Division — Repository Setup Orchestrator      ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Repository : $REPO_NAME"
echo "  Platform   : $PLATFORM"
echo "  Tools dir  : $TOOLS_DIR"
echo "  ROS2       : ${ROS2_DISTRO:-not set}"
echo "  Node.js    : v${NODE_MAJOR_VERSION:-?}.x"
echo ""

# ── Platform-specific intro ───────────────────────────────────
case "$PLATFORM" in
  github)
    echo -e "  ${CYAN}Scripts that will run:${RESET}"
    echo "    1. setup_repo_automation.sh  — creates all config files and commits"
    echo "    2. add_status_checks.sh --phase1  — configures branch protection"
    echo "       (includes automated PR trigger and Phase 2 status checks)"
    echo ""
    echo -e "  ${CYAN}Scripts that will NOT run (run separately):${RESET}"
    echo "    setup_developer_system.sh  — run once per machine before this"
    echo "    setup_repo_hooks.sh     — run by each developer after cloning"
    ;;
  zoho)
    echo -e "  ${CYAN}Scripts that will run:${RESET}"
    echo "    1. setup_repo_automation.sh  — creates all config files and commits"
    echo "       (GitHub Actions workflows committed but ignored by Zoho)"
    echo ""
    echo -e "  ${YELLOW}Manual steps printed at end:${RESET}"
    echo "    Zoho Protected Branches configuration"
    echo "    Zoho Merge Settings configuration"
    echo ""
    echo -e "  ${CYAN}Scripts that will NOT run:${RESET}"
    echo "    setup_developer_system.sh  — run once per machine before this"
    echo "    add_status_checks.sh    — GitHub-specific, not applicable"
    echo "    setup_repo_hooks.sh     — run by each developer after cloning"
    ;;
  gitlab)
    echo -e "  ${CYAN}Scripts that will run:${RESET}"
    echo "    1. setup_repo_automation.sh  — creates all config files and commits"
    echo "       (GitHub Actions workflows committed — replace with .gitlab-ci.yml)"
    echo ""
    echo -e "  ${YELLOW}Manual steps printed at end:${RESET}"
    echo "    GitLab Protected Branches configuration"
    echo "    GitLab CI/CD pipeline setup guidance"
    echo ""
    echo -e "  ${CYAN}Scripts that will NOT run:${RESET}"
    echo "    setup_developer_system.sh  — run once per machine before this"
    echo "    add_status_checks.sh    — GitHub-specific, not applicable"
    echo "    setup_repo_hooks.sh     — run by each developer after cloning"
    ;;
esac

echo ""
read -r -p "  Press ENTER to start or Ctrl+C to cancel... "

# ── Prerequisite check — laptop setup ────────────────────────
header "Prerequisite Check — Laptop Setup"

echo ""
info "Verifying setup_developer_system.sh has been run on this machine..."
echo ""

PREREQS_OK=true

# Git
GIT_VER=$(git --version | grep -oP '\d+\.\d+' | head -1)
GIT_MAJ=$(echo "$GIT_VER" | cut -d. -f1)
GIT_MIN=$(echo "$GIT_VER" | cut -d. -f2)
REQ_MAJ=$(echo "${GIT_MIN_VERSION:-2.23}" | cut -d. -f1)
REQ_MIN=$(echo "${GIT_MIN_VERSION:-2.23}" | cut -d. -f2)
if [[ "$GIT_MAJ" -gt "$REQ_MAJ" ]] || \
   [[ "$GIT_MAJ" -eq "$REQ_MAJ" && "$GIT_MIN" -ge "$REQ_MIN" ]]; then
  pass "Git $(git --version | cut -d' ' -f3)"
else
  fail "Git $GIT_VER is below minimum ${GIT_MIN_VERSION}"
  info "Run: bash tools/setup_developer_system.sh"
  PREREQS_OK=false
fi

# Node.js
if command -v node &>/dev/null; then
  NODE_MAJ=$(node --version | grep -oP '\d+' | head -1)
  if [[ "$NODE_MAJ" -ge "${NODE_MAJOR_VERSION:-22}" ]]; then
    pass "Node.js $(node --version)"
  else
    fail "Node.js $(node --version) below v${NODE_MAJOR_VERSION}"
    info "Run: bash tools/setup_developer_system.sh"
    PREREQS_OK=false
  fi
else
  fail "Node.js not found"
  info "Run: bash tools/setup_developer_system.sh"
  PREREQS_OK=false
fi

# pre-commit
if command -v pre-commit &>/dev/null; then
  PC_MAJ=$(pre-commit --version | grep -oP '\d+' | head -1)
  if [[ "$PC_MAJ" -ge "${PRECOMMIT_MIN_VERSION:-3}" ]]; then
    pass "pre-commit $(pre-commit --version | grep -oP '\d+\.\d+\.\d+')"
  else
    fail "pre-commit version too old"
    info "Run: bash tools/setup_developer_system.sh"
    PREREQS_OK=false
  fi
else
  fail "pre-commit not found"
  info "Run: bash tools/setup_developer_system.sh"
  PREREQS_OK=false
fi

# ROS2
if [[ -n "${ROS2_DISTRO:-}" ]] && [[ -d "/opt/ros/$ROS2_DISTRO" ]]; then
  pass "ROS2 $ROS2_DISTRO found"
else
  warn "ROS2 ${ROS2_DISTRO:-?} not found at /opt/ros/${ROS2_DISTRO:-?}"
  warn "Some pre-commit hooks may not work without ROS2"
fi

# Git identity
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  pass "Git identity: $GIT_NAME <$GIT_EMAIL>"
else
  fail "Git identity not configured (name or email missing)"
  info "Run: bash tools/setup_developer_system.sh"
  PREREQS_OK=false
fi

# Branch check
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "${INTEGRATION_BRANCH_NAME:-develop}" ]]; then
  pass "On develop branch"
else
  fail "Must be on develop branch — currently on: $CURRENT_BRANCH"
  info "Run: git switch ${INTEGRATION_BRANCH_NAME:-develop}"
  PREREQS_OK=false
fi

# Working directory clean
if git diff --quiet && git diff --staged --quiet; then
  pass "Working directory is clean"
else
  # Check if the uncommitted changes are automation files
  # from a previous failed run of this script
  UNCLEAN_FILES=$(git status --short | awk '{print $2}')
  AUTOMATION_FILES="commitlint.config.js package.json package-lock.json \
    .clang-format .pre-commit-config.yaml .gitignore"
  ALL_AUTOMATION=true
  while IFS= read -r f; do
    IS_AUTO=false
    for af in $AUTOMATION_FILES; do
      [[ "$f" == "$af" || "$f" == .husky/* || "$f" == .github/* ]] \
        && IS_AUTO=true && break
    done
    [[ "$IS_AUTO" == "false" ]] && ALL_AUTOMATION=false && break
  done <<< "$UNCLEAN_FILES"

  if [[ "$ALL_AUTOMATION" == "true" ]]; then
    echo ""
    warn "Uncommitted automation files detected from a previous run:"
    git status --short
    echo ""
    echo "  This looks like a previous run of setup_repository.sh"
    echo "  was interrupted before completing the commits."
    echo ""
    echo "  Options:"
    echo "  Y — stage and commit these files now then continue"
    echo "  N — exit so you can review and handle manually"
    echo ""
    read -r -p "  Commit existing automation files and continue? (Y/n): " RECOVER
    if [[ "$RECOVER" == "n" || "$RECOVER" == "N" ]]; then
      echo ""
      echo "  To commit manually:"
      echo -e "    ${CYAN}git add .${RESET}"
      echo -e "    ${CYAN}git commit -m \"chore(repo): add automation files (recovered)\"${RESET}"
      echo -e "    ${CYAN}git push origin develop${RESET}"
      echo "  Then re-run this script."
      echo ""
      exit 1
    fi
    # Stage all automation files and commit
    git add .gitignore package.json package-lock.json \
      commitlint.config.js .clang-format \
      .pre-commit-config.yaml 2>/dev/null || true
    git add .husky/ 2>/dev/null || true
    git add .github/ 2>/dev/null || true
    if ! git diff --staged --quiet; then
      git commit -m "chore(repo): add automation files (recovered from interrupted run)"
      git push origin develop
      pass "Recovered files committed and pushed"
    else
      pass "No changes to commit after staging"
    fi
  else
    fail "Working directory has uncommitted changes"
    info "Commit or stash changes before running this script:"
    git status --short
    echo ""
    echo -e "  Stash:  ${CYAN}git stash push -m \"wip before setup\"${RESET}"
    echo -e "  Commit: ${CYAN}git add . && git commit -m \"chore: save work in progress\"${RESET}"
    echo ""
    PREREQS_OK=false
  fi
fi

if [[ "$PREREQS_OK" == "false" ]]; then
  echo ""
  fail "Prerequisite check failed. Fix the issues above and retry."
  echo ""
  echo "  If machine setup has not been done:"
  echo -e "    ${CYAN}bash tools/setup_developer_system.sh${RESET}"
  echo ""
  exit 1
fi

echo ""
pass "All prerequisites satisfied — proceeding with $PLATFORM setup"

# ══════════════════════════════════════════════════════════════
# STAGE 1 — Repository Automation (all platforms)
# ══════════════════════════════════════════════════════════════
section "Stage 1 of 3 — Repository Automation Setup"

echo "  Running setup_repo_automation.sh..."
echo "  This creates and commits all automation files."
echo ""

bash "$TOOLS_DIR/setup_repo_automation.sh"

echo ""
pass "Stage 1 complete — automation files committed to develop"

# ══════════════════════════════════════════════════════════════
# STAGE 2 — Platform-specific remote configuration
# ══════════════════════════════════════════════════════════════
section "Stage 2 of 3 — Remote Platform Configuration"

case "$PLATFORM" in

  # ── GitHub ───────────────────────────────────────────────
  github)
    echo "  Running add_status_checks.sh --phase1..."
    echo "  This configures branch protection and triggers"
    echo "  the test PR automatically if you choose Y."
    echo ""

    bash "$TOOLS_DIR/add_status_checks.sh" --phase1

    echo ""
    pass "Stage 2 complete — GitHub branch protection configured"
    ;;

  # ── Zoho ─────────────────────────────────────────────────
  zoho)
    echo -e "  ${YELLOW}Zoho repository requires manual configuration.${RESET}"
    echo "  The automation files have been committed to your repository."
    echo "  Complete the following steps on repository.zoho.in:"
    echo ""
    echo -e "  ${BOLD}Protected Branches — Settings → Protected Branches → Protect Branch${RESET}"
    echo ""
    echo "  Branch: develop"
    echo "    Members who can process merge request: Admins & Maintainers"
    echo "    Members who can push:                 Admins, Maintainers & All Developers"
    echo "    ☑ Enable Code Owners"
    echo "    ☐ Allow Force Push"
    echo "    → Click Protect Branch"
    echo ""
    echo "  Branch: main"
    echo "    Members who can process merge request: Admins only"
    echo "    Members who can push:                 Admins only"
    echo "    ☑ Enable Code Owners"
    echo "    ☐ Allow Force Push"
    echo "    → Click Protect Branch"
    echo ""
    echo -e "  ${BOLD}Merge Settings — Settings → Merge Settings${RESET}"
    echo ""
    echo "  Merge Method:     Squash Merge (default for all branches)"
    echo "  Merge Rule:       ☑ Require all comments resolved before merging"
    echo ""
    echo "  SonarQube Code Validation → Add Branch:"
    echo "    Add develop"
    echo "    Add main"
    echo ""
    echo "  Code Review → Add Branch:"
    echo "    Add develop  (minimum ${REQUIRED_APPROVALS_DEVELOP:-1} reviewer(s))"
    echo "    Add main     (minimum ${REQUIRED_APPROVALS_MAIN:-2} reviewers)"
    echo ""
    echo -e "  ${BOLD}CODEOWNERS — create in root directory (not .github/)${RESET}"
    echo ""
    echo "  The .github/CODEOWNERS file should be moved to root:"
    echo -e "    ${CYAN}mv .github/CODEOWNERS CODEOWNERS 2>/dev/null || true${RESET}"
    echo -e "    ${CYAN}git add CODEOWNERS .github/CODEOWNERS${RESET}"
    echo -e "    ${CYAN}git commit -m \"chore(repo): move CODEOWNERS to root for Zoho\"${RESET}"
    echo -e "    ${CYAN}git push origin develop${RESET}"
    echo ""
    echo -e "  ${BOLD}Developer instructions for Merge Requests:${RESET}"
    echo "    Title:                    Must follow type(scope): description"
    echo "    Merger:                   Assign Engineering Lead"
    echo "    ☑ Require review approval (always tick this)"
    echo "    Optional Reviewers:       Assign at least one reviewer"
    echo "    Development Status:       In Progress until ready, then Completed"
    echo "    ☑ Remove source branch after request is completed"
    echo ""
    pass "Stage 2 complete — manual Zoho configuration steps printed above"
    ;;

  # ── GitLab ───────────────────────────────────────────────
  gitlab)
    echo -e "  ${YELLOW}GitLab repository requires manual configuration.${RESET}"
    echo "  The automation files have been committed to your repository."
    echo "  Complete the following steps on your GitLab instance:"
    echo ""
    echo -e "  ${BOLD}Protected Branches — Settings → Repository → Protected Branches${RESET}"
    echo ""
    echo "  Branch: develop"
    echo "    Allowed to merge:  Maintainers"
    echo "    Allowed to push:   Developers + Maintainers"
    echo "    ☑ Require code owner approval"
    echo "    → Protect"
    echo ""
    echo "  Branch: main"
    echo "    Allowed to merge:  Maintainers"
    echo "    Allowed to push:   No one (merge only via MR)"
    echo "    ☑ Require code owner approval"
    echo "    → Protect"
    echo ""
    echo -e "  ${BOLD}Merge Request settings — Settings → General → Merge Requests${RESET}"
    echo ""
    echo "    Merge method:               Squash commits"
    echo "    ☑ Squash commits when merging"
    echo "    ☑ Require all threads resolved before merge"
    echo "    ☑ Delete source branch by default"
    echo "    Approvals required:         1 (develop)  2 (main)"
    echo ""
    echo -e "  ${BOLD}CI/CD Pipeline — replace GitHub Actions workflows${RESET}"
    echo ""
    echo "  The .github/workflows/*.yml files will not run on GitLab."
    echo "  Create .gitlab-ci.yml in the repository root with equivalent"
    echo "  pipeline stages. Variable mappings:"
    echo ""
    echo "    GitHub Actions                GitLab CI"
    echo "    ─────────────────────────     ──────────────────────────────"
    echo "    github.head_ref               CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"
    echo "    github.event.pull_request     CI_MERGE_REQUEST_TITLE"
    echo "      .title"
    echo "    github.event.pull_request     CI_MERGE_REQUEST_DESCRIPTION"
    echo "      .body"
    echo "    runs-on: ubuntu-latest        image: ubuntu:22.04"
    echo "    on: pull_request              rules: if CI_PIPELINE_SOURCE"
    echo "                                         == merge_request_event"
    echo ""
    echo "  The validation logic in scripts/ci/*.sh is platform-agnostic"
    echo "  and can be called from .gitlab-ci.yml directly."
    echo ""
    echo -e "  ${BOLD}CODEOWNERS — move to root directory for GitLab${RESET}"
    echo ""
    echo -e "    ${CYAN}mv .github/CODEOWNERS CODEOWNERS 2>/dev/null || true${RESET}"
    echo -e "    ${CYAN}git add CODEOWNERS .github/CODEOWNERS${RESET}"
    echo -e "    ${CYAN}git commit -m \"chore(repo): move CODEOWNERS to root for GitLab\"${RESET}"
    echo -e "    ${CYAN}git push origin develop${RESET}"
    echo ""
    pass "Stage 2 complete — manual GitLab configuration steps printed above"
    ;;
esac

# ══════════════════════════════════════════════════════════════
# STAGE 3 — Developer onboarding instructions
# ══════════════════════════════════════════════════════════════
section "Stage 3 of 3 — Developer Onboarding"

echo "  The repository is now configured. Every developer who clones"
echo "  this repository must activate the local hooks on their machine."
echo ""
echo -e "  ${BOLD}One-time machine setup (if not already done):${RESET}"
echo -e "    ${CYAN}bash tools/setup_developer_system.sh${RESET}"
echo ""
echo -e "  ${BOLD}After cloning the repository:${RESET}"
echo -e "    ${CYAN}git clone <repository-url>${RESET}"
echo -e "    ${CYAN}cd $REPO_NAME${RESET}"
echo -e "    ${CYAN}bash tools/setup_repo_hooks.sh${RESET}"
echo ""
echo "  setup_repo_hooks.sh will:"
echo "    → Install npm dependencies (commitlint, Husky)"
echo "    → Initialise Husky and fix core.hooksPath"
echo "    → Verify all three hooks are active"
echo "    → Run two live tests to confirm everything works"
echo ""

# ── Final summary ─────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
MINUTES=$(( DURATION / 60 ))
SECONDS=$(( DURATION % 60 ))

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "${GREEN}${BOLD}  ✔  Repository setup complete${RESET}"
echo ""
echo "  Repository : $REPO_NAME"
echo "  Platform   : $PLATFORM"
echo "  Duration   : ${MINUTES}m ${SECONDS}s"

# Set FINAL_LOG so the EXIT trap copies to the right place
FINAL_LOG="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S)_${PLATFORM}.log"
echo ""

case "$PLATFORM" in
  github)
    echo "  What is active:"
    echo "    Local hooks     — commitlint, clang-format, branch name check"
    echo "    GitHub Actions  — PR title, ticket ref, C++ format, Python style"
    echo "    Branch protection — ${REQUIRED_APPROVALS_DEVELOP:-1} approval (${INTEGRATION_BRANCH_NAME:-develop}), ${REQUIRED_APPROVALS_MAIN:-2} approvals (${RELEASE_BRANCH_NAME:-main})"
    echo "    Status checks   — all 5 required before merge"
    ;;
  zoho)
    echo "  What is active:"
    echo "    Local hooks     — commitlint, clang-format, branch name check"
    echo "    Zoho workflows  — committed (ignored until CI runner configured)"
    echo "  What needs manual completion:"
    echo "    Protected Branches, Merge Settings, Code Review, SonarQube"
    echo "    (steps printed above in Stage 2)"
    ;;
  gitlab)
    echo "  What is active:"
    echo "    Local hooks     — commitlint, clang-format, branch name check"
    echo "  What needs manual completion:"
    echo "    Protected Branches, MR settings, .gitlab-ci.yml pipeline"
    echo "    (steps printed above in Stage 2)"
    ;;
esac

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
