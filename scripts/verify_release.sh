#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mix_version=$(sed -n 's/^  @version "\(.*\)"/\1/p' "${project_root}/mix.exs" | head -n1)
cargo_version=$(sed -n '/^\[package\]/,/^\[/s/^version = "\(.*\)"/\1/p' \
  "${project_root}/native/fuzler/Cargo.toml" | head -n1)
checksum_file="${project_root}/checksum-Elixir.Fuzler.Native.exs"

test -n "${mix_version}"
test "${mix_version}" = "${cargo_version}"

if [[ "${mix_version}" == *-* ]]; then
  echo "Release version must not contain a prerelease suffix: ${mix_version}" >&2
  exit 1
fi

if ! grep -q 'sha256:' "${checksum_file}"; then
  echo "${checksum_file} does not contain release archive checksums" >&2
  exit 1
fi

echo "Release metadata is valid for v${mix_version}"
