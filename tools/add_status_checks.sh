#!/bin/bash
# ============================================================
#  Robotics Division — GitHub Branch Protection + Status Checks
#  GitHub-SPECIFIC. Do NOT run on Zoho or other platforms.
#
#  PHASE 1 — Run immediately after setup_repo_automation.sh
#    Installs gh CLI if missing (with confirmation)
#    Configures branch protection for develop and main
#    Sets required approvals, force push block, deletion block
#    Status checks left empty — workflows not yet run
#
#  PHASE 2 — Run after a test PR triggers GitHub Actions
#    Verifies Phase 1 has been run (queries GitHub API)
#    Verifies workflows have run and check names are registered
#    Adds all 5 required status checks to develop and main
#    Verifies the complete final state via GitHub API
#
#  Usage:
#    bash tools/add_status_checks.sh --phase1   after setup_repo_automation.sh
#    bash tools/add_status_checks.sh --phase2   after first test PR workflows pass
# ============================================================

set -e

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

# ── Parse phase argument ──────────────────────────────────────
case "${1:-}" in
  --phase1) PHASE=1 ;;
  --phase1--auto) PHASE=1; AUTO=true ;;
  --phase2) PHASE=2 ;;
  --phase2--auto) PHASE=2; AUTO=true ;;
  *)
    echo ""
    echo "Usage:"
    echo "  bash tools/add_status_checks.sh --phase1"
    echo "    Run immediately after setup_repo_automation.sh"
    echo "    Configures branch protection rules"
    echo ""
    echo "  bash tools/add_status_checks.sh --phase2"
    echo "    Run after a test PR triggers GitHub Actions workflows"
    echo "    Adds status check names to branch protection"
    echo ""
    exit 1
    ;;
esac

# ── Must be inside a Git repository ──────────────────────────
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo ""
  fail "Not inside a Git repository. cd into the repo first."
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
cd "$REPO_ROOT"

# ── Load project.env if present ─────────────────────────────
PROJECT_FILE="$REPO_ROOT/tools/project.env"
[[ -f "$PROJECT_FILE" ]] && source "$PROJECT_FILE"

# ── Local audit log ─────────────────────────────────────────────
# Writes debug output to /tmp if AUDIT_LOG not set by parent script
AUDIT_LOG="${AUDIT_LOG:-/tmp/add_status_checks_$(date +%Y%m%d_%H%M%S).log}"
exec > >(tee -a "$AUDIT_LOG") 2>&1
echo "add_status_checks.sh started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$AUDIT_LOG"

# ── Status checks required by both phases ─────────────────────
# These must exactly match the name: fields in .github/workflows/
# Values read from tools/project.env
REQUIRED_CHECKS=(
  "${STATUS_CHECK_BRANCH_NAME:-Branch Name Check}"
  "${STATUS_CHECK_PR_TITLE:-PR Title Check}"
  "${STATUS_CHECK_PR_TICKET:-PR Ticket Reference Check}"
  "${STATUS_CHECK_CPP_FORMAT:-C++ Format Check}"
  "${STATUS_CHECK_PYTHON_STYLE:-Python Style Check}"
)

# ── Intro ─────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Robotics Division — GitHub Branch Protection Setup     ║${RESET}"
echo -e "${BOLD}║   GitHub-specific — do not run on Zoho or other platforms║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Repository : $REPO_NAME"
echo "  Phase      : $PHASE"
echo ""
if [[ $PHASE -eq 1 ]]; then
  echo "  What this does:"
  echo "    Configures branch protection for develop and main"
  echo "    Sets required approvals, force push block, deletion block"
  echo "    Status checks added in Phase 2 after workflows run"
else
  echo "  What this does:"
  echo "    Verifies Phase 1 has been run"
  echo "    Verifies GitHub Actions workflows have run at least once"
  echo "    Adds 5 required status checks to develop and main"
  echo "    Verifies complete branch protection state"
fi
echo ""
[[ "${AUTO:-false}" == "true" ]] || read -r -p "  Press ENTER to start or Ctrl+C to cancel... "

# ── Shared Step 1: Install and authenticate gh CLI ────────────
header "Step 1 — GitHub CLI"

install_gh() {
  info "Installing GitHub CLI..."

  # Verify apt is healthy before installing — GPG key issues must be
  # fixed by setup_developer_system.sh before running this script
  APT_CHECK=$(sudo apt-get update 2>&1 || true)
  if echo "$APT_CHECK" | grep -qiE "NO_PUBKEY|couldn't be verified|EXPKEYSIG"; then
    echo ""
    fail "apt has broken GPG keys — gh cannot be installed safely"
    fail "Fix this first by running setup_developer_system.sh:"
    echo ""
    echo -e "    ${CYAN}bash tools/setup_developer_system.sh${RESET}"
    echo ""
    echo "  setup_developer_system.sh fixes all broken apt GPG keys"
    echo "  (Chrome, NodeSource, and others) before any installation."
    echo ""
    exit 1
  fi

  # Add the GitHub CLI apt repository using the official signed-by method
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    > /dev/null 2>&1
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update -q
  sudo apt-get install -y gh
  pass "GitHub CLI installed: $(gh --version | head -1 | grep -oP '\d+\.\d+\.\d+')"
}

if ! command -v gh &>/dev/null; then
  warn "GitHub CLI (gh) is not installed"
  echo ""
  echo "  gh is needed to configure branch protection via the GitHub API."
  echo "  It will be installed from the official GitHub CLI apt repository."
  echo ""
  read -r -p "  Install GitHub CLI now? (Y/n): " INSTALL_GH
  if [[ "$INSTALL_GH" == "n" || "$INSTALL_GH" == "N" ]]; then
    echo ""
    echo "  Install manually and re-run:"
    echo -e "    ${CYAN}sudo apt-get install gh${RESET}"
    echo -e "    ${CYAN}gh auth login${RESET}"
    echo ""
    exit 1
  fi
  install_gh
else
  pass "gh $(gh --version | head -1 | grep -oP '\d+\.\d+\.\d+') installed"
fi

# Authentication
if ! gh auth status &>/dev/null; then
  warn "GitHub CLI is not authenticated"
  echo ""
  echo "  You need to authenticate with your GitHub account."
  echo "  A browser window will open to complete login."
  echo ""
  read -r -p "  Authenticate now? (Y/n): " DO_AUTH
  if [[ "$DO_AUTH" == "n" || "$DO_AUTH" == "N" ]]; then
    echo ""
    echo "  Authenticate manually and re-run:"
    echo -e "    ${CYAN}gh auth login${RESET}"
    echo ""
    exit 1
  fi
  gh auth login
fi

GH_USER=$(gh api /user --jq '.login' 2>/dev/null || echo "unknown")
pass "Authenticated as: $GH_USER"

# ── Shared Step 2: Detect repository slug ─────────────────────
header "Step 2 — Repository Detection"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

if ! echo "$REMOTE_URL" | grep -q "github.com"; then
  fail "Remote origin is not a GitHub URL"
  echo ""
  echo "  Current remote: $REMOTE_URL"
  echo ""
  echo "  This script only works with GitHub repositories."
  echo "  For Zoho, use the manual steps printed by setup_repo_automation.sh"
  echo ""
  exit 1
fi

# Handle both SSH and HTTPS remote URL formats
REPO_SLUG=$(echo "$REMOTE_URL" \
  | sed 's|.*github\.com[:/]||' \
  | sed 's|\.git$||')
pass "GitHub repository: $REPO_SLUG"

# Verify access and admin permission
REPO_INFO=$(gh api "/repos/${REPO_SLUG}" 2>/dev/null || echo "")
if [[ -z "$REPO_INFO" ]]; then
  fail "Cannot access repository: $REPO_SLUG"
  echo "  Ensure $GH_USER has Admin access to this repository."
  exit 1
fi

PERMISSIONS=$(echo "$REPO_INFO" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); \
  print(d.get('permissions',{}).get('admin',False))" \
  2>/dev/null || echo "False")
if [[ "$PERMISSIONS" != "True" ]]; then
  warn "You may not have Admin permission on $REPO_SLUG"
  warn "Branch protection requires Admin access"
  read -r -p "  Continue anyway? (y/N): " CONTINUE_NO_ADMIN
  [[ "$CONTINUE_NO_ADMIN" != "y" && "$CONTINUE_NO_ADMIN" != "Y" ]] && exit 1
else
  pass "Admin access confirmed for $GH_USER"
fi

# Check repository visibility — branch protection requires GitHub Team or Enterprise
# for private repos. Free plan private repos will get a 403 on the protection API.
REPO_PRIVATE=$(echo "$REPO_INFO" | python3 -c   "import sys,json; d=json.load(sys.stdin); print(d.get('private', False))"   2>/dev/null || echo "False")

if [[ "$REPO_PRIVATE" == "True" ]]; then
  REPO_PLAN=$(gh api "/repos/${REPO_SLUG}" --jq '.owner.plan.name' 2>/dev/null || echo "unknown")
  warn "Repository is PRIVATE"
  echo ""
  echo "  Branch protection rules on private repositories require:"
  echo "    GitHub Team plan (\$4/user/month) or higher"
  echo "    GitHub Free plan does NOT support branch protection on private repos"
  echo ""
  if [[ "$REPO_PLAN" == "free" || "$REPO_PLAN" == "unknown" ]]; then
    echo "  Detected plan: ${REPO_PLAN}"
    echo ""
    echo "  Options:"
    echo "    1. Make the repository public (Settings → Danger Zone → Change visibility)"
    echo "    2. Upgrade to GitHub Team plan"
    echo "    3. Continue anyway — the API call will likely fail with HTTP 403"
    echo ""
    read -r -p "  Continue anyway? (y/N): " CONTINUE_PRIVATE
    [[ "$CONTINUE_PRIVATE" != "y" && "$CONTINUE_PRIVATE" != "Y" ]] && exit 1
  else
    pass "Plan: $REPO_PLAN — branch protection supported on private repos"
  fi
fi

# ══════════════════════════════════════════════════════════════
# PHASE 1 — Configure Branch Protection Rules
# ══════════════════════════════════════════════════════════════
if [[ $PHASE -eq 1 ]]; then

  # Parse PROTECTED_BRANCHES from project.env
  # First branch = integration branch (develop) — fewer approvals
  # Second branch = release branch (main) — more approvals, enforce admins
  INTEGRATION_BRANCH=$(echo "${PROTECTED_BRANCHES:-develop,main}" \
    | cut -d',' -f1 | xargs)
  RELEASE_BRANCH=$(echo "${PROTECTED_BRANCHES:-develop,main}" \
    | cut -d',' -f2 | xargs)
  DEV_APPROVALS="${REQUIRED_APPROVALS_DEVELOP:-1}"
  MAIN_APPROVALS="${REQUIRED_APPROVALS_MAIN:-2}"

  header "Phase 1 — Configuring Branch Protection Rules"
  echo ""
  info "Integration branch: $INTEGRATION_BRANCH (${DEV_APPROVALS} approval)"
  info "Release branch:     $RELEASE_BRANCH (${MAIN_APPROVALS} approvals)"
  echo "  Status checks added in Phase 2 after workflows run."
  echo ""

  # ── integration branch (develop) ──────────────────────────
  if ! gh api "/repos/${REPO_SLUG}/branches/${INTEGRATION_BRANCH}" &>/dev/null; then
    fail "$INTEGRATION_BRANCH branch not found on remote"
    echo "  Push it first:"
    echo -e "    ${CYAN}git switch -c ${INTEGRATION_BRANCH} && git push origin ${INTEGRATION_BRANCH}${RESET}"
    exit 1
  fi

  info "Configuring ${INTEGRATION_BRANCH} (${DEV_APPROVALS} approval required)..."
  BP_OUTPUT=$(gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/${REPO_SLUG}/branches/${INTEGRATION_BRANCH}/protection" \
    --input - 2>&1 << JSON
{
  "required_status_checks": { "strict": true, "contexts": [] },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": ${DEV_APPROVALS},
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
) || true
  if echo "$BP_OUTPUT" | grep -q "Must have admin rights\|403\|not allowed\|Resource not accessible"; then
    fail "${INTEGRATION_BRANCH}: branch protection failed — HTTP 403"
    echo ""
    echo "  Private repositories require GitHub Team plan or higher for branch protection."
    echo "  Options:"
    echo "    1. Make the repository public (Settings → Danger Zone → Change visibility)"
    echo "    2. Upgrade to GitHub Team plan"
    echo ""
    exit 1
  fi
  pass "${INTEGRATION_BRANCH}: ${DEV_APPROVALS} approval(s), stale reviews dismissed, force push blocked"

  # ── release branch (main) ─────────────────────────────────
  if gh api "/repos/${REPO_SLUG}/branches/${RELEASE_BRANCH}" &>/dev/null; then
    info "Configuring ${RELEASE_BRANCH} (${MAIN_APPROVALS} approvals required)..."
    BP_OUTPUT=$(gh api \
      --method PUT \
      -H "Accept: application/vnd.github+json" \
      "/repos/${REPO_SLUG}/branches/${RELEASE_BRANCH}/protection" \
      --input - 2>&1 << JSON
{
  "required_status_checks": { "strict": true, "contexts": [] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": ${MAIN_APPROVALS},
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
) || true
    if echo "$BP_OUTPUT" | grep -q "Must have admin rights\|403\|not allowed\|Resource not accessible"; then
      fail "${RELEASE_BRANCH}: branch protection failed — HTTP 403"
      echo ""
      echo "  Private repositories require GitHub Team plan or higher for branch protection."
      echo "  Options:"
      echo "    1. Make the repository public (Settings → Danger Zone → Change visibility)"
      echo "    2. Upgrade to GitHub Team plan"
      echo ""
      exit 1
    fi
    pass "${RELEASE_BRANCH}: ${MAIN_APPROVALS} approvals, enforce admins, force push blocked"
  else
    warn "${RELEASE_BRANCH} branch not found — skipping ${RELEASE_BRANCH} branch protection"
  fi

  # ── Trigger test PR to register workflow check names ──────
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo -e "${GREEN}${BOLD}  ✔  Phase 1 complete — branch protection configured${RESET}"
  echo ""
  echo "  Status checks need to be registered before Phase 2 can add them."
  echo "  GitHub registers check names the first time a workflow runs."
  echo "  This requires a Pull Request to be opened against develop."
  echo ""
  echo -e "${CYAN}  This can be done automatically right now.${RESET}"
  echo "  The script will:"
  echo "    1. Create a temporary branch (devops/register-workflow-checks)"
  echo "    2. Make a small README change"
  echo "    3. Open a PR targeting develop"
  echo "    4. Wait for all 5 workflows to complete (up to 5 minutes)"
  echo "    5. Run Phase 2 automatically"
  echo "    6. Close and delete the temporary branch"
  echo ""
  if [[ "${AUTO:-false}" == "true" ]]; then
    AUTO_TRIGGER="y"
    info "Auto mode — triggering test PR automatically..."
  else
    read -r -p "  Trigger test PR automatically now? (Y/n): " AUTO_TRIGGER
  fi

  if [[ "$AUTO_TRIGGER" == "n" || "$AUTO_TRIGGER" == "N" ]]; then
    echo ""
    echo "  Manual steps to trigger workflows:"
    echo ""
    echo "  1. Create a test branch and open a PR:"
    echo -e "     ${CYAN}git switch -c feature/${EXAMPLE_TICKET_ID:-PROJ-01}-test-workflows${RESET}"
    echo -e "     ${CYAN}echo '# test' >> README.md${RESET}"
    echo -e "     ${CYAN}git add README.md${RESET}"
    echo -e "     ${CYAN}git commit -m \"docs(repo): trigger GitHub Actions workflows\"${RESET}"
    echo -e "     ${CYAN}git push origin feature/${EXAMPLE_TICKET_ID:-PROJ-01}-test-workflows${RESET}"
    echo ""
    echo "  2. Open a Pull Request targeting develop on GitHub"
    echo "  3. Wait for all 5 workflow checks to appear (1-2 minutes)"
    echo "  4. Run Phase 2:"
    echo -e "     ${CYAN}bash tools/add_status_checks.sh --phase2${RESET}"
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    exit 0
  fi

  # ── Automated PR trigger ───────────────────────────────────
  TRIGGER_BRANCH="${WORKFLOW_TRIGGER_BRANCH:-devops/register-workflow-checks}"
  TRIGGER_PR_NUMBER=""
  ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

  # Ensure we leave the repo in its original state even if something fails
  cleanup_trigger_branch() {
    echo ""
    info "Cleaning up trigger branch..."
    # Close the PR if it was opened
    if [[ -n "$TRIGGER_PR_NUMBER" ]]; then
      gh pr close "$TRIGGER_PR_NUMBER" \
        --repo "$REPO_SLUG" \
        --comment "Automated cleanup — branch protection and status checks configured" \
        > /dev/null 2>&1 || true
      pass "Test PR #${TRIGGER_PR_NUMBER} closed"
    fi
    # Delete remote branch
    git push origin --delete "$TRIGGER_BRANCH" > /dev/null 2>&1 || true
    # Delete local branch and return to original branch
    git switch "$ORIGINAL_BRANCH" > /dev/null 2>&1 || true
    git branch -D "$TRIGGER_BRANCH" > /dev/null 2>&1 || true
    pass "Trigger branch deleted"
  }
  trap cleanup_trigger_branch EXIT

  echo ""
  header "Triggering test PR to register workflow checks"

  # Check trigger branch does not already exist
  if git show-ref --verify --quiet "refs/remotes/origin/${TRIGGER_BRANCH}" 2>/dev/null; then
    info "Trigger branch already exists on remote — deleting first..."
    git push origin --delete "$TRIGGER_BRANCH" > /dev/null 2>&1 || true
  fi

  # Create trigger branch from develop
  info "Creating trigger branch: $TRIGGER_BRANCH..."
  git fetch origin "${INTEGRATION_BRANCH_NAME:-develop}" > /dev/null 2>&1
  git switch -c "$TRIGGER_BRANCH" "origin/${INTEGRATION_BRANCH}" > /dev/null 2>&1
  pass "Trigger branch created from develop"

  # Make a minimal traceable change
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  cat >> README.md << EOF

<!-- automation: workflow registration trigger ${TIMESTAMP} -->
EOF
  git add README.md
  git commit -m "ci(repo): trigger workflow registration for branch protection" \
    > /dev/null 2>&1
  pass "Trigger commit created"

  # Push the branch — capture output for debugging
  info "Pushing trigger branch to GitHub..."
  # || true prevents set -e from killing the script before PUSH_EXIT is captured.
  PUSH_OUTPUT=$(git push origin "$TRIGGER_BRANCH" 2>&1) || true
  PUSH_EXIT=$?
  if [[ $PUSH_EXIT -ne 0 ]]; then
    fail "Failed to push trigger branch: $PUSH_OUTPUT"
    fail "Cannot create trigger PR — push was rejected"
    echo ""
    echo "  Common causes:"
    echo "  • Repository is private and free plan blocks push to protected branch"
    echo "  • Network connectivity issue"
    echo "  • Authentication expired (run: gh auth login)"
    echo ""
    echo "  Manual alternative:"
    echo "  1. Push a branch manually and open a PR on GitHub"
    echo "  2. Wait for workflows to complete"
    echo "  3. Run: bash tools/add_status_checks.sh --phase2"
    echo ""
    trap - EXIT
    cleanup_trigger_branch
    exit 1
  fi
  pass "Trigger branch pushed"

  # Open a PR using gh CLI
  info "Opening Pull Request..."
  PR_OUTPUT=$(gh pr create \
    --repo "$REPO_SLUG" \
    --base "$(echo "${PROTECTED_BRANCHES:-develop,main}" | cut -d',' -f1 | xargs)" \
    --head "$TRIGGER_BRANCH" \
    --title "ci(repo): trigger workflow registration for branch protection" \
    --body "$(cat << 'EOF'
## Summary
Automated PR to register GitHub Actions workflow check names with branch protection.
This PR is created by tools/add_status_checks.sh and will be closed automatically.

## Related Ticket
Relates to #DEVOPS-01

## Type of Change
- [x] Docs

## Robot Deployment Impact
- [x] No deployed robot impact

## Breaking Changes
- [x] No

## Checklist
- [x] Self-reviewed
EOF
)" 2>&1)
  PR_EXIT=$?

  # Log full output for debugging
  echo "  [DEBUG] gh pr create output: $PR_OUTPUT" >> "${AUDIT_LOG:-/dev/null}"

  TRIGGER_PR_NUMBER=$(echo "$PR_OUTPUT" | grep -oP '(?<=pull/)\d+' | head -1)

  if [[ $PR_EXIT -ne 0 ]] || [[ -z "$TRIGGER_PR_NUMBER" ]]; then
    echo ""
    fail "Failed to create Pull Request"
    echo "  Error output: $PR_OUTPUT"
    echo ""
    echo "  Common causes:"
    echo "  • Repository is private — gh pr create may fail on private repos"
    echo "    with branch protection requiring review"
    echo "  • Branch already has an open PR"
    echo "  • Authentication issue (run: gh auth status)"
    echo ""
    echo "  Manual alternative:"
    echo "  1. Open a PR manually on GitHub from devops/register-workflow-checks → develop"
    echo "     OR create any PR targeting develop"
    echo "  2. Wait for all 5 workflow checks to appear (1-2 minutes)"
    echo "  3. Run: bash tools/add_status_checks.sh --phase2"
    echo ""
    trap - EXIT
    cleanup_trigger_branch
    exit 1
  fi

  PR_URL=$(echo "$PR_OUTPUT" | grep "https://github.com" | tail -1)
  pass "Pull Request #${TRIGGER_PR_NUMBER} opened"
  info "PR URL: $PR_URL"

  # ── Wait for workflows to complete ────────────────────────
  echo ""
  header "Waiting for GitHub Actions workflows to complete"
  echo ""

  # Get the SHA of the trigger branch commit
  TRIGGER_SHA=$(gh api \
    "/repos/${REPO_SLUG}/pulls/${TRIGGER_PR_NUMBER}" \
    --jq '.head.sha' 2>/dev/null || echo "")

  if [[ -z "$TRIGGER_SHA" ]]; then
    fail "Could not get commit SHA for PR #${TRIGGER_PR_NUMBER}"
    exit 1
  fi
  info "Watching commit: ${TRIGGER_SHA:0:8}..."

  MAX_WAIT=300   # 5 minutes maximum
  POLL_INTERVAL=15
  ELAPSED=0
  ALL_DONE=false

  echo ""
  while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    # Get all check runs for this commit
    CHECK_DATA=$(gh api \
      "/repos/${REPO_SLUG}/commits/${TRIGGER_SHA}/check-runs" \
      --jq '.check_runs[] | {name: .name, status: .status, conclusion: .conclusion}' \
      2>/dev/null || echo "")

    TOTAL=$(gh api \
      "/repos/${REPO_SLUG}/commits/${TRIGGER_SHA}/check-runs" \
      --jq '.total_count' 2>/dev/null || echo "0")

    COMPLETED=$(gh api \
      "/repos/${REPO_SLUG}/commits/${TRIGGER_SHA}/check-runs" \
      --jq '[.check_runs[] | select(.status == "completed")] | length' \
      2>/dev/null || echo "0")

    # Print progress on same line
    printf "\r  ⏳  Checks: %s/%s completed — elapsed: %ss / %ss   " \
      "$COMPLETED" "$TOTAL" "$ELAPSED" "$MAX_WAIT"

    # Check if all REQUIRED_CHECKS have completed
    REGISTERED_NOW=$(gh api \
      "/repos/${REPO_SLUG}/commits/${TRIGGER_SHA}/check-runs" \
      --jq '.check_runs[].name' 2>/dev/null || echo "")

    ALL_FOUND=true
    for check in "${REQUIRED_CHECKS[@]}"; do
      if ! echo "$REGISTERED_NOW" | grep -qF "$check"; then
        ALL_FOUND=false
        break
      fi
    done

    if [[ "$ALL_FOUND" == "true" && "$COMPLETED" -ge "${#REQUIRED_CHECKS[@]}" ]]; then
      ALL_DONE=true
      break
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
  done

  echo ""  # newline after progress line

  if [[ "$ALL_DONE" == "false" ]]; then
    echo ""
    warn "Workflows did not complete within ${MAX_WAIT}s"
    warn "They may still be running. Wait for them to complete then run:"
    echo -e "    ${CYAN}bash tools/add_status_checks.sh --phase2${RESET}"
    echo ""
    exit 0
  fi

  echo ""
  info "Workflow results:"
  for check in "${REQUIRED_CHECKS[@]}"; do
    CONCLUSION=$(gh api \
      "/repos/${REPO_SLUG}/commits/${TRIGGER_SHA}/check-runs" \
      --jq ".check_runs[] | select(.name == \"${check}\") | .conclusion" \
      2>/dev/null || echo "unknown")
    if [[ "$CONCLUSION" == "success" ]]; then
      pass "$check → $CONCLUSION"
    else
      warn "$check → $CONCLUSION  (result does not affect registration)"
    fi
  done

  echo ""
  info "All 5 checks are now registered with GitHub."
  info "Running Phase 2 automatically..."
  echo ""

  # ── Run Phase 2 inline ────────────────────────────────────
  # Disable the EXIT trap before Phase 2 runs so cleanup
  # does not interfere with Phase 2 verification
  trap - EXIT

  # Clean up trigger branch before Phase 2
  cleanup_trigger_branch

  # Switch back to develop for Phase 2
  git switch "$ORIGINAL_BRANCH" > /dev/null 2>&1 || true

  # Now fall through to Phase 2 by setting PHASE=2
  PHASE=2
  # Reload develop protection state since we need PHASE1_APPROVALS
  DEVELOP_PROTECTION=$(gh api \
    "/repos/${REPO_SLUG}/branches/${INTEGRATION_BRANCH_NAME:-develop}/protection" \
    2>/dev/null || echo "")
  PHASE1_APPROVALS=$(echo "$DEVELOP_PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
reviews=d.get('required_pull_request_reviews',{})
print(reviews.get('required_approving_review_count','0'))" \
    2>/dev/null || echo "1")

  # Jump directly to Step 5 — skip Steps 3 and 4 since we
  # just verified Phase 1 and workflows above
  echo ""
  header "Phase 2 — Adding Status Checks (auto-triggered)"
  SKIP_PHASE2_PREREQS=true
fi

# ══════════════════════════════════════════════════════════════
# PHASE 2 — Add Status Checks
# ══════════════════════════════════════════════════════════════

# ── Step 3: Verify Phase 1 was run ───────────────────────────
if [[ "${SKIP_PHASE2_PREREQS:-false}" == "true" ]]; then
  pass "Phase 1 verified — already confirmed in auto-trigger flow"
  pass "Workflow registration verified — already confirmed in auto-trigger flow"
else
  header "Step 3 — Verifying Phase 1 was run"

  DEVELOP_PROTECTION=$(gh api \
    "/repos/${REPO_SLUG}/branches/${INTEGRATION_BRANCH_NAME:-develop}/protection" \
    2>/dev/null || echo "")

  if [[ -z "$DEVELOP_PROTECTION" ]]; then
    echo ""
    fail "develop branch has no protection configured"
    fail "Phase 1 has not been run yet"
    echo ""
    echo "  Run Phase 1 first:"
    echo -e "    ${CYAN}bash tools/add_status_checks.sh --phase1${RESET}"
    echo ""
    exit 1
  fi

  PHASE1_APPROVALS=$(echo "$DEVELOP_PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
reviews=d.get('required_pull_request_reviews',{})
print(reviews.get('required_approving_review_count','0'))" \
    2>/dev/null || echo "0")

  if [[ "$PHASE1_APPROVALS" -gt 0 ]]; then
    pass "Phase 1 confirmed — develop requires $PHASE1_APPROVALS approval(s)"
  else
    warn "develop has protection but required approvals = 0"
    warn "Phase 1 may not have completed correctly"
    read -r -p "  Continue anyway? (y/N): " CONTINUE_P1
    [[ "$CONTINUE_P1" != "y" && "$CONTINUE_P1" != "Y" ]] && {
      echo "  Run: bash tools/add_status_checks.sh --phase1"
      exit 1
    }
  fi

  # ── Step 4: Verify workflows have run ────────────────────────
  header "Step 4 — Verifying GitHub Actions workflows have run"

  DEVELOP_SHA=$(git rev-parse origin/${INTEGRATION_BRANCH_NAME:-develop} 2>/dev/null \
    || gh api "/repos/${REPO_SLUG}/branches/${INTEGRATION_BRANCH_NAME:-develop}" \
       --jq '.commit.sha' 2>/dev/null \
    || echo "")

  REGISTERED_CHECKS=""
  if [[ -n "$DEVELOP_SHA" ]]; then
    REGISTERED_CHECKS=$(gh api \
      "/repos/${REPO_SLUG}/commits/${DEVELOP_SHA}/check-runs" \
      --jq '.check_runs[].name' 2>/dev/null || echo "")
  fi

  ALL_REGISTERED=true
  for check in "${REQUIRED_CHECKS[@]}"; do
    if echo "$REGISTERED_CHECKS" | grep -qF "$check"; then
      pass "Registered: $check"
    else
      warn "Not yet registered: $check"
      ALL_REGISTERED=false
    fi
  done

  if [[ "$ALL_REGISTERED" == "false" ]]; then
    echo ""
    warn "Some status checks are not yet registered with GitHub."
    echo ""
    echo "  GitHub only registers check names after a workflow has run."
    echo "  To register all 5 checks open a PR against develop and wait,"
    echo "  or use --phase1 which can do this automatically."
    echo ""
    read -r -p "  Add only registered checks and continue anyway? (y/N): " FORCE
    if [[ "$FORCE" != "y" && "$FORCE" != "Y" ]]; then
      echo ""
      info "Exiting. Re-run after workflows complete."
      exit 0
    fi
  fi
fi

# ── Step 5: Add status checks to branch protection ───────────
header "Step 5 — Adding Status Checks"

# Build JSON array of check names
CONTEXTS_JSON="["
FIRST=true
for check in "${REQUIRED_CHECKS[@]}"; do
  if [[ "$FIRST" == "true" ]]; then
    CONTEXTS_JSON="${CONTEXTS_JSON}\"${check}\""
    FIRST=false
  else
    CONTEXTS_JSON="${CONTEXTS_JSON},\"${check}\""
  fi
done
CONTEXTS_JSON="${CONTEXTS_JSON}]"

# develop
info "Adding status checks to develop..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${REPO_SLUG}/branches/${INTEGRATION_BRANCH_NAME:-develop}/protection" \
  --input - << JSON > /dev/null
{
  "required_status_checks": {
    "strict": true,
    "contexts": ${CONTEXTS_JSON}
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": ${PHASE1_APPROVALS},
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
pass "develop: all 5 status checks added"

# main
if gh api "/repos/${REPO_SLUG}/branches/${RELEASE_BRANCH_NAME:-main}" &>/dev/null; then
  MAIN_APPROVALS=$(gh api \
    "/repos/${REPO_SLUG}/branches/${RELEASE_BRANCH_NAME:-main}/protection" \
    --jq \
    '.required_pull_request_reviews.required_approving_review_count' \
    2>/dev/null || echo "2")
  info "Adding status checks to main..."
  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/${REPO_SLUG}/branches/${RELEASE_BRANCH_NAME:-main}/protection" \
    --input - << JSON > /dev/null
{
  "required_status_checks": {
    "strict": true,
    "contexts": ${CONTEXTS_JSON}
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": ${MAIN_APPROVALS},
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
  pass "main: all 5 status checks added"
fi

# ── Step 6: Verify complete state ─────────────────────────────
header "Step 6 — Final Verification"

verify_branch() {
  local branch=$1
  local expected_approvals=$2

  if ! gh api "/repos/${REPO_SLUG}/branches/${branch}" &>/dev/null; then
    return
  fi

  echo ""
  info "Verifying $branch..."

  PROTECTION=$(gh api \
    "/repos/${REPO_SLUG}/branches/${branch}/protection" \
    2>/dev/null || echo "")

  if [[ -z "$PROTECTION" ]]; then
    warn "$branch: cannot read protection — check Admin permission"
    return
  fi

  # Approvals
  ACTUAL_APPROVALS=$(echo "$PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
print(d.get('required_pull_request_reviews',{}) \
       .get('required_approving_review_count','0'))" \
    2>/dev/null || echo "0")
  [[ "$ACTUAL_APPROVALS" -ge "$expected_approvals" ]] \
    && pass "$branch: required approvals = $ACTUAL_APPROVALS" \
    || warn "$branch: approvals = $ACTUAL_APPROVALS (expected $expected_approvals)"

  # Dismiss stale reviews
  STALE=$(echo "$PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
print(d.get('required_pull_request_reviews',{}) \
       .get('dismiss_stale_reviews',False))" \
    2>/dev/null || echo "False")
  [[ "$STALE" == "True" ]] \
    && pass "$branch: stale reviews dismissed on new commits" \
    || warn "$branch: stale review dismissal not configured"

  # Status checks
  CHECKS=$(echo "$PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
checks=d.get('required_status_checks',{}).get('contexts',[])
print('\n'.join(checks) if checks else '')" \
    2>/dev/null || echo "")

  if [[ -z "$CHECKS" ]]; then
    warn "$branch: no status checks configured"
  else
    while IFS= read -r c; do
      [[ -n "$c" ]] && pass "$branch: required — $c"
    done <<< "$CHECKS"
  fi

  # Strict (branches must be up to date)
  STRICT=$(echo "$PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
print(d.get('required_status_checks',{}).get('strict',False))" \
    2>/dev/null || echo "False")
  [[ "$STRICT" == "True" ]] \
    && pass "$branch: branch must be up to date before merging" \
    || warn "$branch: strict status checks not enabled"

  # Force push
  FORCE=$(echo "$PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
print(d.get('allow_force_pushes',{}).get('enabled',True))" \
    2>/dev/null || echo "True")
  [[ "$FORCE" == "False" ]] \
    && pass "$branch: force push blocked" \
    || warn "$branch: force push is NOT blocked"

  # Deletion
  DELETE=$(echo "$PROTECTION" | python3 -c \
    "import sys,json
d=json.load(sys.stdin)
print(d.get('allow_deletions',{}).get('enabled',True))" \
    2>/dev/null || echo "True")
  [[ "$DELETE" == "False" ]] \
    && pass "$branch: branch deletion blocked" \
    || warn "$branch: branch deletion is NOT blocked"
}

verify_branch "${INTEGRATION_BRANCH_NAME:-develop}" "${REQUIRED_APPROVALS_DEVELOP:-1}"
verify_branch "${RELEASE_BRANCH_NAME:-main}" "${REQUIRED_APPROVALS_MAIN:-2}"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "${GREEN}${BOLD}  ✔  Phase 2 complete for: $REPO_NAME${RESET}"
echo ""
echo "  develop: ${REQUIRED_APPROVALS_DEVELOP:-1} approval(s) + 5 status checks + no force push"
echo "  main: ${REQUIRED_APPROVALS_MAIN:-2} approvals + 5 status checks + no force push + enforce admins"
echo ""
echo -e "${CYAN}  Full automation stack is now active:${RESET}"
echo "    Local  → commitlint, clang-format, branch name check"
echo "    Remote → PR title, ticket ref, C++ format, Python style"
echo "    Merge  → required approvals + all 5 checks must pass"
echo ""
echo -e "${CYAN}  Every developer who clones this repository runs:${RESET}"
echo "    bash tools/setup_repo_hooks.sh"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
