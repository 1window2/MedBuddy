#!/bin/sh
# File Name: docker-entrypoint.sh
# Role: Copies mounted credentials into a private medbuddy-owned runtime directory, then drops privileges for the API command.

set -eu

credential_source="${GOOGLE_APPLICATION_CREDENTIALS:-}"
runtime_directory="/run/medbuddy"
runtime_credential="${runtime_directory}/firebase-admin.json"

if [ -z "${credential_source}" ] || [ ! -r "${credential_source}" ]; then
  echo "Firebase Admin credentials are unavailable to the container bootstrap." >&2
  exit 1
fi

# The non-root process reads this restricted copy, not the original mounted secret.
install -d -m 0700 -o medbuddy -g medbuddy "${runtime_directory}"
install -m 0400 -o medbuddy -g medbuddy \
  "${credential_source}" "${runtime_credential}"
export GOOGLE_APPLICATION_CREDENTIALS="${runtime_credential}"

# Replace the bootstrap process so signals reach the API without retaining root capabilities.
exec setpriv \
  --reuid=medbuddy \
  --regid=medbuddy \
  --init-groups \
  --inh-caps=-all \
  --ambient-caps=-all \
  --bounding-set=-all \
  --no-new-privs \
  "$@"
