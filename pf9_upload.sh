#!/usr/bin/env bash
#
# upload.sh
# Usage: ./upload.sh <TOKEN> <TICKET> <FILE>
#
# Behavior:
# - Calls GET /whoami on API to determine allowed_prefix and bucket for the token.
# - Builds S3 key as: <allowed_prefix><ticket>/<UTC-timestamp>_<basename>
# - Calls POST /presign to get a presigned PUT URL.
# - Uploads file with SSE header (required if presign expects it).
# - Fails loudly and prints helpful debug info on any error.
#
# Requirements: bash, curl, stat (standard on Linux/macOS). No jq or python required.

### --- CONFIGURE: set your API base (execute-api or custom domain) ----------
readonly API_BASE="https://uploads.platform9.com"   # <-- set to your API base
readonly WHOAMI_PATH="/whoami"
readonly PRESIGN_PATH="/presign"
readonly PRESIGN_EXPIRES=900   # seconds for presign URL
readonly MAX_FILE_BYTES=5368709120  # 5 GiB

### --- Colors for pretty output (optional) --------------------------------
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'

info()  { echo -e "${C_CYAN}${C_BOLD}>${C_RESET} ${C_CYAN}$1${C_RESET}"; }
step()  { echo -e "${C_YELLOW}• $1${C_RESET}"; }
success(){ echo -e "${C_GREEN}✓ $1${C_RESET}"; }
err()   { echo -e "${C_RED}✗ ERROR: $1${C_RESET}" >&2; }

# cross-platform file size
get_file_size() {
  local file="$1"
  if stat -c %s "$file" &>/dev/null; then
    stat -c %s "$file"
  elif stat -f %z "$file" &>/dev/null; then
    stat -f %z "$file"
  else
    echo ""
  fi
}

# extract a JSON string value for a key using grep/cut (zero-dep)
# usage: json_get_str "$json" "allowed_prefix"
json_get_str() {
  local json="$1" key="$2"
  echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | cut -d'"' -f4
}

# ensure prefix ends with single slash
normalize_prefix() {
  local p="$1"
  p="${p#/}"    # remove leading slash(es)
  p="${p%/}"    # remove trailing slash(es)
  if [ -z "$p" ]; then
    echo ""
  else
    echo "${p}/"
  fi
}

main() {
  if [ "$#" -ne 3 ]; then
    echo -e "Usage: ${C_BOLD}$0${C_RESET} ${C_YELLOW}<TOKEN>${C_RESET} ${C_YELLOW}<TICKET>${C_RESET} ${C_YELLOW}<FILE>${C_RESET}"
    exit 1
  fi

  local token="$1"
  local ticket="$2"
  local file_path="$3"

  if [ -z "$token" ]; then err "token is required"; exit 1; fi
  if [ ! -f "$file_path" ]; then err "file not found: $file_path"; exit 2; fi

  info "Checking file size..."
  local file_size
  file_size=$(get_file_size "$file_path")
  if [ -z "$file_size" ]; then err "could not determine file size (stat failed)"; exit 3; fi
  if [ "$file_size" -gt "$MAX_FILE_BYTES" ]; then err "file too large: ${file_size} bytes (max ${MAX_FILE_BYTES})"; exit 4; fi
  success "File size OK."

  # 1) WHOAMI — determine prefix and bucket from token
  info "Identifying customer for token..."
  local whoami_json
  whoami_json=$(curl -sS -X GET "${API_BASE}${WHOAMI_PATH}" -H "x-upload-token: ${token}" -H "Accept: application/json" || true)
  if [ -z "$whoami_json" ]; then
    err "whoami request failed (no response). Check network or API_BASE."
    exit 5
  fi

  # check for API-level errors (Not Found, etc.)
  local whoami_err
  whoami_err=$(json_get_str "$whoami_json" "message")
  if [ -n "$whoami_err" ] && [ "$whoami_err" = "Not Found" ]; then
    err "whoami endpoint returned Not Found (404). Ensure GET /whoami route exists on API gateway."
    echo "whoami response: $whoami_json"
    exit 6
  fi

  # parse allowed_prefix and bucket
  local allowed_prefix bucket customer_id
  allowed_prefix=$(json_get_str "$whoami_json" "allowed_prefix")
  bucket=$(json_get_str "$whoami_json" "bucket")
  customer_id=$(json_get_str "$whoami_json" "customer_id")

  if [ -z "$allowed_prefix" ]; then
    err "whoami did not return allowed_prefix. Response: $whoami_json"
    exit 7
  fi
  allowed_prefix=$(normalize_prefix "$allowed_prefix")
  if [ -z "$allowed_prefix" ]; then
    err "normalized allowed_prefix is empty; token may be misconfigured."
    echo "whoami response: $whoami_json"
    exit 8
  fi

  success "Customer prefix detected: ${C_YELLOW}${allowed_prefix}${C_RESET}"
  if [ -n "$bucket" ]; then
    step "Target bucket from token: ${bucket}"
  else
    step "No bucket returned in whoami (ensure DynamoDB token row contains bucket if you do not set DEFAULT_BUCKET)"
  fi

  # 2) build object key
  local file_name s3_key
  file_name=$(basename "$file_path")
  s3_key="${allowed_prefix}${ticket}/$(date -u +%Y%m%dT%H%M%SZ)_${file_name}"

  info "Requesting pre-signed URL for ${C_YELLOW}$s3_key${C_RESET}..."

  # 3) PRESIGN: request presigned URL
  local payload api_response
  payload="{\"key\":\"$s3_key\",\"expires\":${PRESIGN_EXPIRES}}"
  api_response=$(curl -sS -X POST "${API_BASE}${PRESIGN_PATH}" \
    -H "Content-Type: application/json" \
    -H "x-upload-token: ${token}" \
    -d "$payload" || true)

  if [ -z "$api_response" ]; then
    err "Presign request failed (no response). Check API_BASE and network."
    exit 9
  fi

  # 3a) detect presign error
  local presign_error
  presign_error=$(json_get_str "$api_response" "error")
  if [ -n "$presign_error" ]; then
    err "Presign API returned error: $presign_error"
    echo "Presign response: $api_response"
    exit 10
  fi

  # 3b) extract url
  local upload_url
  upload_url=$(json_get_str "$api_response" "url")
  if [ -z "$upload_url" ]; then
    err "Could not parse presigned URL from API response."
    echo "Presign response: $api_response"
    exit 11
  fi

  success "Got presigned URL (hidden)."

  # 4) UPLOAD — perform PUT and treat non-2xx as error (capture response body for debug)
  info "Uploading ${C_YELLOW}$file_name${C_RESET}..."
  local tmp_out
  tmp_out=$(mktemp /tmp/s3_upload_resp.XXXXXX) || tmp_out="/tmp/s3_upload_resp.$$"
  local http_code
  # note: keep SSE header if your bucket/presign requires it
  http_code=$(curl -w "%{http_code}" -X PUT --upload-file "$file_path" \
    -H "x-amz-server-side-encryption: AES256" \
    -o "$tmp_out" \
    "$upload_url" || true)

  if [ -z "$http_code" ]; then
    err "Upload failed: no HTTP response from PUT."
    [ -f "$tmp_out" ] && { echo "Response body:"; sed -n '1,200p' "$tmp_out"; }
    rm -f "$tmp_out"
    exit 12
  fi

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    err "Upload failed with HTTP ${http_code}."
    echo "Response body (first 200 lines):"
    sed -n '1,200p' "$tmp_out"
    rm -f "$tmp_out"
    exit 13
  fi

  rm -f "$tmp_out"
  success "Upload complete!"
  echo -e "File Path: ${C_YELLOW}${s3_key}${C_RESET}"
  if [ -n "$customer_id" ]; then
    echo -e "Customer: ${C_YELLOW}${customer_id}${C_RESET}"
  fi
}

main "$@"
