defmodule TSTest do
  use ExUnit.Case
  doctest TS

  test "greets the world" do
    assert TS.hello() == :world
  end
end
