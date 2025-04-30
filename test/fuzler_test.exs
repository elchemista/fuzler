defmodule FuzlerTest do
  use ExUnit.Case
  doctest Fuzler

  test "greets the world" do
    assert Fuzler.hello() == :world
  end
end
