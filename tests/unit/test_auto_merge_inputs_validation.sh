#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SCRIPT_PATH="${SCRIPT_DIR}/../../entrypoint.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_contains() {
  local file_path="$1"
  local expected="$2"
  if ! grep -Fq -- "${expected}" "${file_path}"; then
    echo "Assertion failed. Expected to find: ${expected}" >&2
    echo "----- FILE CONTENT -----" >&2
    cat "${file_path}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${file_path}"; then
    echo "Assertion failed. Did NOT expect to find: ${unexpected}" >&2
    echo "----- FILE CONTENT -----" >&2
    cat "${file_path}" >&2
    exit 1
  fi
}

mkdir -p "${TMP_DIR}/bin"
mkdir -p "${TMP_DIR}/repo"

cat > "${TMP_DIR}/bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

args=("$@")
if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "-C" ]]; then
  args=("${args[@]:2}")
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "config" && "${args[1]}" == "--global" ]]; then
  exit 0
fi

if [[ "${#args[@]}" -ge 1 && "${args[0]}" == "config" ]]; then
  exit 0
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "remote" && "${args[1]}" == "set-url" ]]; then
  exit 0
fi

if [[ "${#args[@]}" -ge 1 && "${args[0]}" == "fetch" ]]; then
  exit 0
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "rev-parse" && "${args[1]}" == "--is-inside-work-tree" ]]; then
  echo "true"
  exit 0
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "show-ref" ]]; then
  last_arg="${args[$((${#args[@]} - 1))]}"
  if [[ "${last_arg}" == "refs/remotes/origin/main" || "${last_arg}" == "refs/remotes/origin/develop" ]]; then
    exit 0
  fi
  exit 1
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "rev-parse" ]]; then
  last_arg="${args[$((${#args[@]} - 1))]}"
  if [[ "${last_arg}" == "origin/main" ]]; then
    echo "aaa111"
    exit 0
  fi
  if [[ "${last_arg}" == "origin/develop" ]]; then
    echo "bbb222"
    exit 0
  fi
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "diff" && "${args[1]}" == "--quiet" ]]; then
  exit 1
fi

if [[ "${#args[@]}" -ge 1 && "${args[0]}" == "diff" ]]; then
  echo "M README.md"
  exit 0
fi

if [[ "${#args[@]}" -ge 1 && "${args[0]}" == "log" ]]; then
  echo "stub log"
  exit 0
fi

if [[ "${#args[@]}" -ge 2 && "${args[0]}" == "symbolic-ref" ]]; then
  echo "develop"
  exit 0
fi

echo "Unsupported git call: $*" >&2
exit 1
EOF

cat > "${TMP_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -ge 3 && "$1" == "api" && "$2" == "--method" && "$3" == "GET" && "$4" == "repos/owner/repo/pulls?state=open&base=main" ]]; then
  echo "[]"
  exit 0
fi

if [[ "$#" -ge 2 && "$1" == "pr" && "$2" == "create" ]]; then
  echo "https://example.test/pr/1"
  exit 0
fi

if [[ "$#" -ge 2 && "$1" == "pr" && "$2" == "view" ]]; then
  echo "1"
  exit 0
fi

if [[ "$#" -ge 2 && "$1" == "pr" && "$2" == "merge" ]]; then
  exit 0
fi

echo "Unsupported gh call: $*" >&2
exit 1
EOF

# jq mock: for empty arrays returns empty
cat > "${TMP_DIR}/bin/jq" <<'JQEOF'
#!/usr/bin/env bash
# Minimal jq mock for tests
# For the pattern: jq -r ... '... [] .number // empty' <<< "[]"
# just output nothing for empty array input
input=""
if [[ "$#" -ge 1 && "$1" == "--arg" ]]; then
  shift 3
fi
if [[ "$#" -ge 1 && "$1" == "--json" ]]; then
  shift 1
fi
# Read from stdin or file
if [[ "$#" -ge 1 ]]; then
  # Last arg might be a file or expression
  :
fi
# Simple approach: if stdin is "[]", output nothing
stdin_data=$(cat)
if [[ "${stdin_data}" == "[]" || "${stdin_data}" == "" ]]; then
  exit 0
fi
# For review count queries
if echo "${stdin_data}" | grep -q '"APPROVED"'; then
  echo "1"
  exit 0
fi
# Default: output nothing
exit 0
JQEOF

chmod +x "${TMP_DIR}/bin/git" "${TMP_DIR}/bin/gh" "${TMP_DIR}/bin/jq"

# Test 1: Invalid auto_merge_method should fail
echo "Test 1: Invalid auto_merge_method..."
LOG_FILE="${TMP_DIR}/run1.log"
set +e
PATH="${TMP_DIR}/bin:${PATH}" \
GITHUB_ACTOR="ci-user" \
GITHUB_TOKEN="token" \
GITHUB_REPOSITORY="owner/repo" \
GITHUB_WORKSPACE="${TMP_DIR}" \
GITHUB_OUTPUT="${TMP_DIR}/output1.txt" \
INPUT_GITHUB_TOKEN="token" \
INPUT_REPOSITORY_PATH="repo" \
INPUT_SOURCE_BRANCH="develop" \
INPUT_TARGET_BRANCH="main" \
INPUT_TITLE="Test PR" \
INPUT_TEMPLATE="" \
INPUT_BODY="" \
INPUT_REVIEWER="" \
INPUT_ASSIGNEE="" \
INPUT_LABEL="" \
INPUT_MILESTONE="" \
INPUT_PROJECT="" \
INPUT_DRAFT="false" \
INPUT_GET_DIFF="false" \
INPUT_OLD_STRING="" \
INPUT_NEW_STRING="" \
INPUT_IGNORE_USERS="dependabot" \
INPUT_ALLOW_NO_DIFF="false" \
INPUT_MAX_BODY_BYTES="65000" \
INPUT_MAX_DIFF_LINES="0" \
INPUT_CREATE_MISSING_LABELS="false" \
INPUT_AUTO_MERGE="true" \
INPUT_AUTO_MERGE_METHOD="invalid_method" \
INPUT_AUTO_MERGE_REQUIRE_APPROVAL="true" \
INPUT_AUTO_MERGE_WAIT_CHECKS="true" \
bash "${SCRIPT_PATH}" >"${LOG_FILE}" 2>&1
STATUS="$?"
set -e

if [[ "${STATUS}" == "0" ]]; then
  echo "Expected failure for invalid auto_merge_method" >&2
  cat "${LOG_FILE}" >&2
  exit 1
fi

assert_contains "${LOG_FILE}" "Input 'auto_merge_method' must be 'merge', 'squash', or 'rebase'"
echo "  PASSED"

# Test 2: Valid auto_merge_method should not produce validation error
echo "Test 2: Valid auto_merge_method (squash)..."
LOG_FILE="${TMP_DIR}/run2.log"
set +e
PATH="${TMP_DIR}/bin:${PATH}" \
GITHUB_ACTOR="ci-user" \
GITHUB_TOKEN="token" \
GITHUB_REPOSITORY="owner/repo" \
GITHUB_WORKSPACE="${TMP_DIR}" \
GITHUB_OUTPUT="${TMP_DIR}/output2.txt" \
INPUT_GITHUB_TOKEN="token" \
INPUT_REPOSITORY_PATH="repo" \
INPUT_SOURCE_BRANCH="develop" \
INPUT_TARGET_BRANCH="main" \
INPUT_TITLE="Test PR" \
INPUT_TEMPLATE="" \
INPUT_BODY="" \
INPUT_REVIEWER="" \
INPUT_ASSIGNEE="" \
INPUT_LABEL="" \
INPUT_MILESTONE="" \
INPUT_PROJECT="" \
INPUT_DRAFT="false" \
INPUT_GET_DIFF="false" \
INPUT_OLD_STRING="" \
INPUT_NEW_STRING="" \
INPUT_IGNORE_USERS="dependabot" \
INPUT_ALLOW_NO_DIFF="false" \
INPUT_MAX_BODY_BYTES="65000" \
INPUT_MAX_DIFF_LINES="0" \
INPUT_CREATE_MISSING_LABELS="false" \
INPUT_AUTO_MERGE="true" \
INPUT_AUTO_MERGE_METHOD="squash" \
INPUT_AUTO_MERGE_REQUIRE_APPROVAL="false" \
INPUT_AUTO_MERGE_WAIT_CHECKS="true" \
bash "${SCRIPT_PATH}" >"${LOG_FILE}" 2>&1
STATUS="$?"
set -e

if [[ "${STATUS}" != "0" ]]; then
  echo "Expected success for valid auto_merge_method" >&2
  cat "${LOG_FILE}" >&2
  exit 1
fi

assert_contains "${LOG_FILE}" "Auto-merge is enabled for PR"
echo "  PASSED"

# Test 3: auto_merge=false should not trigger merge
echo "Test 3: auto_merge=false should not trigger merge..."
LOG_FILE="${TMP_DIR}/run3.log"
set +e
PATH="${TMP_DIR}/bin:${PATH}" \
GITHUB_ACTOR="ci-user" \
GITHUB_TOKEN="token" \
GITHUB_REPOSITORY="owner/repo" \
GITHUB_WORKSPACE="${TMP_DIR}" \
GITHUB_OUTPUT="${TMP_DIR}/output3.txt" \
INPUT_GITHUB_TOKEN="token" \
INPUT_REPOSITORY_PATH="repo" \
INPUT_SOURCE_BRANCH="develop" \
INPUT_TARGET_BRANCH="main" \
INPUT_TITLE="Test PR" \
INPUT_TEMPLATE="" \
INPUT_BODY="" \
INPUT_REVIEWER="" \
INPUT_ASSIGNEE="" \
INPUT_LABEL="" \
INPUT_MILESTONE="" \
INPUT_PROJECT="" \
INPUT_DRAFT="false" \
INPUT_GET_DIFF="false" \
INPUT_OLD_STRING="" \
INPUT_NEW_STRING="" \
INPUT_IGNORE_USERS="dependabot" \
INPUT_ALLOW_NO_DIFF="false" \
INPUT_MAX_BODY_BYTES="65000" \
INPUT_MAX_DIFF_LINES="0" \
INPUT_CREATE_MISSING_LABELS="false" \
INPUT_AUTO_MERGE="false" \
INPUT_AUTO_MERGE_METHOD="squash" \
INPUT_AUTO_MERGE_REQUIRE_APPROVAL="true" \
INPUT_AUTO_MERGE_WAIT_CHECKS="true" \
bash "${SCRIPT_PATH}" >"${LOG_FILE}" 2>&1
STATUS="$?"
set -e

if [[ "${STATUS}" != "0" ]]; then
  echo "Expected success for auto_merge=false" >&2
  cat "${LOG_FILE}" >&2
  exit 1
fi

assert_not_contains "${LOG_FILE}" "Auto-merge is enabled"
echo "  PASSED"

echo ""
echo "All auto-merge input validation tests passed."
