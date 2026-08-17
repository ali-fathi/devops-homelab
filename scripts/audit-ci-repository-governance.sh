#!/usr/bin/env bash
# Collect a read-only GitHub Actions and repository-governance baseline.
#
# This script never changes GitHub settings, repository contents, Actions
# secrets, workflows, branches, or Kubernetes resources. It deliberately
# writes only curated non-secret metadata and local workflow configuration.

set -Eeuo pipefail
umask 077

REPORT_ROOT="${PWD}/artifacts/ci-repository-governance"
repository=""
branch=""

usage() {
  cat <<'EOF'
Usage: audit-ci-repository-governance.sh [--repo <owner/repository>] [--branch <name>] [--report-dir <path>]

Collects a read-only CI/repository-governance baseline using the authenticated
GitHub CLI context and local checkout. No Secret values, tokens, workflow
variables, or GitHub Actions secrets are requested or written.

When --repo is omitted, the current repository is resolved with `gh repo view`.
When --branch is omitted, the repository default branch is inspected.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--repo needs owner/repository." >&2; exit 2; }
      repository="$2"
      shift
      ;;
    --branch)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--branch needs a branch name." >&2; exit 2; }
      branch="$2"
      shift
      ;;
    --report-dir)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--report-dir needs a path." >&2; exit 2; }
      REPORT_ROOT="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command in gh git jq rg; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 2; }
done

if [[ -z "$repository" ]]; then
  repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

if [[ -z "$branch" ]]; then
  branch="$(gh api "repos/${repository}" --jq '.default_branch')"
fi

run_id="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
report_dir="${REPORT_ROOT}/${run_id}"
mkdir -p "$report_dir"

printf 'run_id=%s\ncollected_at=%s\nrepository=%s\nbranch=%s\ngit_commit=%s\n' \
  "$run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$repository" "$branch" "$(git rev-parse HEAD)" \
  > "${report_dir}/metadata.txt"

# Curated API responses only. Do not write raw API responses because future
# endpoint additions could expose fields this audit does not need.
gh api "repos/${repository}" --jq '{visibility,default_branch,archived,delete_branch_on_merge,has_issues,allow_forking,security_and_analysis}' \
  > "${report_dir}/repository.json"
gh api "repos/${repository}/branches/${branch}" --jq '{name,protected,protection_url}' \
  > "${report_dir}/branch.json"
gh api "repos/${repository}/rulesets" --jq '[.[] | {id,name,target,enforcement}]' \
  > "${report_dir}/rulesets.json"

ruleset_details_file="${report_dir}/ruleset-details.ndjson"
: > "$ruleset_details_file"
while IFS= read -r ruleset_id; do
  gh api "repos/${repository}/rulesets/${ruleset_id}" \
    --jq '{id,name,target,enforcement,conditions,rules,bypass_actors}' \
    >> "$ruleset_details_file"
done < <(jq -r '.[].id' "${report_dir}/rulesets.json")
if [[ -s "$ruleset_details_file" ]]; then
  jq -s . "$ruleset_details_file" > "${report_dir}/ruleset-details.json"
else
  printf '[]\n' > "${report_dir}/ruleset-details.json"
fi
rm -f "$ruleset_details_file"

# Legacy branch protection is absent when rulesets own the branch. Preserve
# that distinction instead of misclassifying a 404 as proof of no protection.
if ! gh api "repos/${repository}/branches/${branch}/protection" \
  --jq '{required_status_checks,required_pull_request_reviews,required_linear_history,allow_force_pushes,allow_deletions,required_conversation_resolution,lock_branch}' \
  > "${report_dir}/legacy-branch-protection.json" 2>/dev/null; then
  jq -n '{available: false, reason: "Legacy branch-protection endpoint unavailable; inspect ruleset-details.json."}' \
    > "${report_dir}/legacy-branch-protection.json"
fi

gh api "repos/${repository}/actions/permissions" \
  --jq '{enabled,allowed_actions,sha_pinning_required}' \
  > "${report_dir}/actions-permissions.json"
gh api "repos/${repository}/actions/permissions/workflow" \
  --jq '{default_workflow_permissions,can_approve_pull_request_reviews}' \
  > "${report_dir}/workflow-token-defaults.json"

codeowners_present=false
for candidate in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
  if [[ -f "$candidate" ]]; then
    codeowners_present=true
    break
  fi
done

dependabot_present=false
for candidate in .github/dependabot.yml .github/dependabot.yaml; do
  if [[ -f "$candidate" ]]; then
    dependabot_present=true
    break
  fi
done

jq -n \
  --argjson codeowners_present "$codeowners_present" \
  --argjson dependabot_present "$dependabot_present" \
  --argjson renovate_present "$(test -f renovate.json || test -f renovate.json5 && echo true || echo false)" \
  '{codeownersPresent: $codeowners_present, dependabotConfigPresent: $dependabot_present, renovateConfigPresent: $renovate_present}' \
  > "${report_dir}/governance-files.json"

refs_file="${report_dir}/workflow-action-references.tsv"
permissions_file="${report_dir}/workflow-permissions.txt"
: > "$refs_file"
: > "$permissions_file"

while IFS= read -r workflow; do
  while IFS= read -r reference; do
    printf '%s\t%s\n' "$workflow" "$reference" >> "$refs_file"
  done < <(rg --no-filename '^\s*uses:\s*' "$workflow" | sed -E 's/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//')

  printf '===== %s =====\n' "$workflow" >> "$permissions_file"
  rg -n '^(permissions:|[[:space:]]{2,}(actions|attestations|checks|contents|deployments|id-token|issues|packages|pull-requests|security-events|statuses):)' "$workflow" \
    >> "$permissions_file" || true
done < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort)

jq -Rn '[inputs | select(length > 0) | split("\t") | {path: .[0], reference: .[1], immutableCommitSha: (.[1] | test("@[0-9a-fA-F]{40}$"))}]' \
  < "$refs_file" > "${report_dir}/workflow-action-references.json"

jq -n \
  --slurpfile branch_data "${report_dir}/branch.json" \
  --slurpfile rulesets "${report_dir}/ruleset-details.json" \
  --slurpfile actions "${report_dir}/actions-permissions.json" \
  --slurpfile token_defaults "${report_dir}/workflow-token-defaults.json" \
  --slurpfile governance "${report_dir}/governance-files.json" \
  --slurpfile refs "${report_dir}/workflow-action-references.json" \
  '{
    branchProtected: $branch_data[0].protected,
    activeRulesets: [$rulesets[0][] | select(.enforcement == "active") | {name, target, ruleTypes: [.rules[]?.type]}],
    actions: $actions[0],
    workflowTokenDefaults: $token_defaults[0],
    governanceFiles: $governance[0],
    workflowActionReferences: ($refs[0] | length),
    actionReferencesNotPinnedToCommitSha: ([$refs[0][] | select(.immutableCommitSha | not)] | length)
  }' > "${report_dir}/summary.json"

cat > "${report_dir}/README.txt" <<EOF
CI and repository governance audit
==================================

This report is read-only and contains curated repository metadata, branch
ruleset metadata, Actions policy metadata, and local workflow configuration.
It does not contain GitHub tokens, Actions secrets, workflow variables, or
Secret values.

Review order:
1. summary.json
2. ruleset-details.json and legacy-branch-protection.json
3. actions-permissions.json and workflow-token-defaults.json
4. governance-files.json
5. workflow-action-references.json and workflow-permissions.txt

A finding is evidence for a reviewed change; this audit never changes a
GitHub repository setting or workflow.
EOF

echo "[PASS] Read-only CI and repository-governance audit collected."
echo "[INFO] Repository: ${repository}; branch: ${branch}"
echo "[INFO] Report directory: ${report_dir}"
echo "[INFO] Review ${report_dir}/summary.json first."
