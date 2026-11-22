# Sourced by build scripts: loads .env from the repository root without overriding variables
# that are already set in the environment.
if [[ -f .env ]]; then
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    if [[ -z "${!key:-}" ]]; then export "$key=$value"; fi
  done < .env
fi
