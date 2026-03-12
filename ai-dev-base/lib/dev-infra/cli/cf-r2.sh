#!/usr/bin/env bash
# cf-r2 — Cloudflare R2 (S3-compatible) wrapper for AI agents.
# Uses a Python S3 signer helper to generate presigned requests.
# Requires R2 credentials (or fetches from Doppler).
#
# Usage: cf-r2 {ls} [args...]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd python3
_require_cmd curl
_load_registry

_resolve_r2_creds() {
  local project="${CF_PROJECT:-}"
  local config="${CF_CONFIG:-prd}"

  if [ -z "${R2_ACCESS_KEY_ID:-}" ]; then
    [ -z "$project" ] && _die "R2_ACCESS_KEY_ID not set and CF_PROJECT not configured"
    R2_ACCESS_KEY_ID=$(_dop_get "$project" "$config" "R2_ACCESS_KEY_ID") \
      || _die "Failed to fetch R2_ACCESS_KEY_ID from Doppler"
  fi
  if [ -z "${R2_SECRET_ACCESS_KEY:-}" ]; then
    [ -z "$project" ] && _die "R2_SECRET_ACCESS_KEY not set and CF_PROJECT not configured"
    R2_SECRET_ACCESS_KEY=$(_dop_get "$project" "$config" "R2_SECRET_ACCESS_KEY") \
      || _die "Failed to fetch R2_SECRET_ACCESS_KEY from Doppler"
  fi
  if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    [ -z "$project" ] && _die "CLOUDFLARE_ACCOUNT_ID not set and CF_PROJECT not configured"
    CLOUDFLARE_ACCOUNT_ID=$(_dop_get "$project" "$config" "CLOUDFLARE_ACCOUNT_ID" 2>/dev/null) || true
  fi
  [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] && _die "CLOUDFLARE_ACCOUNT_ID required for R2"

  export R2_ENDPOINT="https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com"
}

# Python helper to sign S3 ListBuckets request
_r2_list_buckets() {
  python3 -c "
import datetime, hashlib, hmac, urllib.request, os, xml.etree.ElementTree as ET

endpoint = os.environ['R2_ENDPOINT']
key_id = os.environ['R2_ACCESS_KEY_ID']
secret = os.environ['R2_SECRET_ACCESS_KEY']

now = datetime.datetime.utcnow()
datestamp = now.strftime('%Y%m%d')
amzdate = now.strftime('%Y%m%dT%H%M%SZ')
region = 'auto'
service = 's3'

def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

signing_key = sign(sign(sign(sign(
    ('AWS4' + secret).encode('utf-8'), datestamp), region), service), 'aws4_request')

host = endpoint.replace('https://', '')
canonical = f'GET\n/\n\nhost:{host}\nx-amz-content-sha256:UNSIGNED-PAYLOAD\nx-amz-date:{amzdate}\n\nhost;x-amz-content-sha256;x-amz-date\nUNSIGNED-PAYLOAD'
scope = f'{datestamp}/{region}/{service}/aws4_request'
to_sign = f'AWS4-HMAC-SHA256\n{amzdate}\n{scope}\n{hashlib.sha256(canonical.encode()).hexdigest()}'
sig = hmac.new(signing_key, to_sign.encode('utf-8'), hashlib.sha256).hexdigest()
auth = f'AWS4-HMAC-SHA256 Credential={key_id}/{scope}, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature={sig}'

req = urllib.request.Request(endpoint + '/', headers={
    'Authorization': auth, 'x-amz-date': amzdate,
    'x-amz-content-sha256': 'UNSIGNED-PAYLOAD', 'Host': host
})
resp = urllib.request.urlopen(req)
root = ET.fromstring(resp.read())
ns = {'s3': 'http://s3.amazonaws.com/doc/2006-03-01/'}
for b in root.findall('.//s3:Bucket', ns):
    name = b.find('s3:Name', ns)
    date = b.find('s3:CreationDate', ns)
    if name is not None:
        print(f\"{name.text}  created={date.text if date is not None else 'unknown'}\")
"
}

case "${1:-}" in
  ls)
    _resolve_r2_creds
    _r2_list_buckets
    ;;
  --help|-h)
    cat <<'EOF'
Usage: cf-r2 {ls} [args...]

Commands:
  ls    List R2 buckets

Environment:
  R2_ACCESS_KEY_ID       R2 access key (or fetched from Doppler)
  R2_SECRET_ACCESS_KEY   R2 secret key (or fetched from Doppler)
  CLOUDFLARE_ACCOUNT_ID  Account ID (or fetched from Doppler)
  CF_PROJECT             Doppler project for credential lookup
  CF_CONFIG              Doppler config (default: prd)
EOF
    ;;
  *)
    _usage "Usage: cf-r2 {ls} [args...]"
    ;;
esac
