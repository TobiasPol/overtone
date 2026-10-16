#!/usr/bin/env bash
# One-time setup for notarized releases and automatic Homebrew cask updates.
# Run it yourself: it stores secrets in GitHub and your keychain without printing them.
#
#   scripts/setup-release-signing.sh csr
#       Creates a private key and a certificate signing request (CSR) in ~/.overtone-signing.
#       Upload the CSR at developer.apple.com → Certificates → + → Developer ID Application.
#
#   scripts/setup-release-signing.sh secrets <developerID_application.cer> <AuthKey_XXXX.p8> <issuer-id>
#       1. Packs the certificate and key into a .p12 with a random password and imports it into
#          your login keychain (so you can also sign locally).
#       2. Saves a notarytool keychain profile "overtone-notary" (validates the API key with Apple).
#       3. Stores the GitHub secrets the Release workflow needs.
#       4. Creates a write deploy key on the Homebrew tap and stores its private half as a secret.
#       5. Deletes the loose key files.
set -euo pipefail

REPO="TobiasPol/overtone"
TAP_REPO="TobiasPol/homebrew-tap"
DIR="$HOME/.overtone-signing"
KEY="$DIR/developer-id.key"
OPENSSL=/usr/bin/openssl # LibreSSL writes .p12 files that `security import` accepts on every macOS

die() { echo "error: $*" >&2; exit 1; }

make_csr() {
  mkdir -p "$DIR" && chmod 700 "$DIR"
  if [[ -f "$KEY" ]]; then
    echo "Reusing existing key $KEY"
  else
    (umask 077 && "$OPENSSL" genrsa -out "$KEY" 2048 2> /dev/null)
  fi
  "$OPENSSL" req -new -key "$KEY" -subj "/CN=Overtone Developer ID" -out "$DIR/developer-id.csr"
  echo "✓ CSR written to $DIR/developer-id.csr"
}

pack_identity() { # <cer> <password> → $DIR/developer-id.p12
  local cer="$1" password="$2" cert_key key_key
  "$OPENSSL" x509 -inform DER -in "$cer" -out "$DIR/developer-id.pem" 2> /dev/null ||
    "$OPENSSL" x509 -in "$cer" -out "$DIR/developer-id.pem"
  cert_key="$("$OPENSSL" x509 -in "$DIR/developer-id.pem" -noout -pubkey)"
  key_key="$("$OPENSSL" rsa -in "$KEY" -pubout 2> /dev/null)"
  [[ "$cert_key" == "$key_key" ]] || die "the certificate does not belong to $KEY (upload the CSR from 'csr')"
  "$OPENSSL" x509 -in "$DIR/developer-id.pem" -noout -subject | grep -q "Developer ID Application" ||
    die "that is not a Developer ID Application certificate"
  (umask 077 && P12_PASSWORD="$password" "$OPENSSL" pkcs12 -export -inkey "$KEY" -in "$DIR/developer-id.pem" \
    -name "Developer ID Application" -passout env:P12_PASSWORD -out "$DIR/developer-id.p12")
  security import "$DIR/developer-id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$password" -T /usr/bin/codesign > /dev/null
  echo "✓ Developer ID identity imported into your login keychain"
}

store_secrets() { # <password> <p8> <key-id> <issuer>
  base64 -i "$DIR/developer-id.p12" | gh secret set DEVELOPER_ID_P12_BASE64 --repo "$REPO"
  printf '%s' "$1" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"
  base64 -i "$2" | gh secret set NOTARY_KEY_BASE64 --repo "$REPO"
  printf '%s' "$3" | gh secret set NOTARY_KEY_ID --repo "$REPO"
  printf '%s' "$4" | gh secret set NOTARY_ISSUER_ID --repo "$REPO"
  echo "✓ Signing and notarization secrets stored in $REPO"
}

setup_tap_deploy_key() {
  rm -f "$DIR/tap-deploy" "$DIR/tap-deploy.pub"
  ssh-keygen -q -t ed25519 -N "" -C "overtone-release-workflow" -f "$DIR/tap-deploy"
  gh repo deploy-key add "$DIR/tap-deploy.pub" --repo "$TAP_REPO" --allow-write \
    --title "Overtone release workflow" > /dev/null
  gh secret set TAP_DEPLOY_KEY --repo "$REPO" < "$DIR/tap-deploy"
  echo "✓ Deploy key added to $TAP_REPO; private half stored as TAP_DEPLOY_KEY"
}

cleanup() { # <p8>
  rm -P -f "$KEY" "$DIR/developer-id.pem" "$DIR/developer-id.p12" "$DIR/developer-id.csr" \
    "$DIR/tap-deploy" "$DIR/tap-deploy.pub"
  read -r -p "Delete the downloaded API key $1 too? It now lives in your keychain and GitHub. [Y/n] " answer
  if [[ ! "$answer" =~ ^[Nn] ]]; then rm -P -f "$1" && echo "✓ Deleted $1"; fi
}

run_secrets() {
  local cer="${1:-}" p8="${2:-}" issuer="${3:-}" key_id password
  [[ -f "$cer" && -f "$p8" && -n "$issuer" ]] ||
    die "usage: $0 secrets <developerID_application.cer> <AuthKey_XXXX.p8> <issuer-id>"
  [[ -f "$KEY" ]] || die "no private key in $DIR; run '$0 csr' first"
  gh auth status > /dev/null 2>&1 || die "run 'gh auth login' first"
  key_id="$(basename "$p8" | sed -nE 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/p')"
  [[ -n "$key_id" ]] || die "expected the API key file to be named AuthKey_<KEYID>.p8"
  password="$("$OPENSSL" rand -base64 24)"

  pack_identity "$cer" "$password"
  xcrun notarytool store-credentials overtone-notary --key "$p8" --key-id "$key_id" --issuer "$issuer" > /dev/null
  echo "✓ API key validated with Apple and saved as notarytool profile 'overtone-notary'"
  store_secrets "$password" "$p8" "$key_id" "$issuer"
  setup_tap_deploy_key
  cleanup "$p8"
  echo
  echo "All set. Tag a release (git tag v1.0.1 && git push origin v1.0.1) to publish a notarized build."
}

case "${1:-}" in
  csr) make_csr ;;
  secrets) shift && run_secrets "$@" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' && exit 1 ;;
esac
