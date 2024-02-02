defmodule TS do
  @moduledoc """
  Documentation for TS.
  """

  @doc """

  p1 = TS.PlayerData.create_player("P1")
  p2 = TS.PlayerData.create_player("P2")
  {what, ever, trade} = TS.TradingCenter.start_trade("P1", "P2")
  TS.Trade.ready(trade, "P1")
  TS.Trade.ready(trade, "P2")
  p2 = %{p2 | inventory: TS.Trade.add_item(trade, "P2", p2.inventory, "sword", 1)}

  p1 = %{p1 | inventory: TS.Trade.add_item(trade, "P1", p1.inventory, "gold", 150)}
  TS.Trade.ready(trade, "P2")

  p1 = %{p1 | inventory: TS.Trade.remove_item(trade, "P1", p1.inventory, "gold", 5)}
  TS.Trade.ready(trade, "P1")

  TS.Trade.ready(trade, "P2")

  p1 = %{p1 | inventory: TS.Trade.collect(trade, "P1", p1.inventory)}
  p2 = %{p2 | inventory: TS.Trade.collect(trade, "P2", p2.inventory)}
  """

  alias TS.PlayerData, as: Player

  def test do
    p1 = TS.PlayerData.create_player("P1")
    IO.inspect(p1)

    p2 = TS.PlayerData.create_player("P2")
    {_what, _ever, trade} = TS.TradingCenter.start_trade("P1", "P2")
    IO.inspect(trade)
    IO.puts("P1 invites P2 to trade")
    Player.process(p2)

    TS.Trade.ready(trade, "P2")
    IO.puts("P2 accepts invitation")
    Player.process(p1)

    p2 = %{p2 | inventory: TS.Trade.add_item(trade, "P2", p2.inventory, "sword", 1)}
    Player.process(p1)

    p1 = %{p1 | inventory: TS.Trade.add_item(trade, "P1", p1.inventory, "gold", 150)}
    Player.process(p2)

    TS.Trade.ready(trade, "P2")
    IO.puts("P2 is ready")
    Player.process(p1)

    p1 = %{p1 | inventory: TS.Trade.remove_item(trade, "P1", p1.inventory, "gold", 5)}
    IO.inspect(p1)
    Player.process(p2)

    TS.Trade.ready(trade, "P1")
    IO.puts("P1 is ready")
    Player.process(p2)

    TS.Trade.ready(trade, "P2")
    IO.puts("P2 is ready")
    Player.process(p1)

    p1 = %{p1 | inventory: TS.Trade.collect(trade, "P1", p1.inventory)}
    IO.inspect(p1)
    p2 = %{p2 | inventory: TS.Trade.collect(trade, "P2", p2.inventory)}
    IO.inspect(p2)
  end
end
