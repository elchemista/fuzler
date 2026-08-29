#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(sed -n 's/^  @version "\(.*\)"/\1/p' "${project_root}/mix.exs" | head -n1)
package_path="${project_root}/fuzler-${version}.tar"
smoke_root=$(mktemp -d)

cleanup() {
  rm -rf "${smoke_root}"
}
trap cleanup EXIT

cd "${project_root}"
mix hex.build

mkdir -p "${smoke_root}/outer" "${smoke_root}/package" "${smoke_root}/consumer/test"
tar -xf "${package_path}" -C "${smoke_root}/outer"
tar -xzf "${smoke_root}/outer/contents.tar.gz" -C "${smoke_root}/package"

test -f "${smoke_root}/package/checksum-Elixir.Fuzler.Native.exs"
test -f "${smoke_root}/package/native/fuzler/Cargo.lock"
test ! -e "${smoke_root}/package/priv/native/libfuzler.so"

cat > "${smoke_root}/consumer/mix.exs" <<EOF
defmodule FuzlerSmoke.MixProject do
  use Mix.Project

  def project do
    [
      app: :fuzler_smoke,
      version: "0.0.0",
      elixir: "~> 1.18",
      deps: [
        {:rustler, "~> 0.36.2"},
        {:fuzler, path: "../package"}
      ]
    ]
  end
end
EOF

cat > "${smoke_root}/consumer/test/test_helper.exs" <<'EOF'
ExUnit.start()
EOF

cat > "${smoke_root}/consumer/test/fuzler_smoke_test.exs" <<'EOF'
defmodule FuzlerSmokeTest do
  use ExUnit.Case

  test "the packaged source compiles, loads its NIF, and serves the public API" do
    assert Fuzler.similarity_score("café", "cafe\u0301") == 1.0
    assert [%Fuzler.Match{value: "Milano"}] =
             Fuzler.top_matches("milano", ["Roma", "Milano"], 1)
  end
end
EOF

cd "${smoke_root}/consumer"
RUSTLER_PRECOMPILATION_EXAMPLE_BUILD=1 MIX_ENV=test mix deps.get
RUSTLER_PRECOMPILATION_EXAMPLE_BUILD=1 MIX_ENV=test mix test
