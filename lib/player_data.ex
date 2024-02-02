defmodule TS.PlayerData do
  @moduledoc """
  Module for manipulation of player's data.

  """
  defstruct name: nil, inventory: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          inventory: Map.t()
        }

  require Logger

  # Binds the player with the current process
  def create_player(name) do
    {:ok, registered_name, pid} = TS.Players.register(name)
    Logger.info("Created new player bound with PID #{inspect(pid)}")
    %__MODULE__{name: registered_name, inventory: %{"gold" => 500, "armor" => 1, "sword" => 1}}
  end

  def send_trade_change(name, name_other, inv_my, inv_other) do
    pid = TS.Players.get(name)
    send(pid, {:trade_change, name_other, inv_my, inv_other})
  end

  def send_invite(name, name_other) do
    pid = TS.Players.get(name)
    send(pid, {:invite, name_other})
  end

  def send_ready(name, name_other) do
    pid = TS.Players.get(name)
    send(pid, {:ready, name_other})
  end

  def send_finished(name, name_other) do
    pid = TS.Players.get(name)
    send(pid, {:finished, name_other})
  end

  def entered_negotiation(name, name_other) do
    pid = TS.Players.get(name)
    send(pid, {:negotiate, name, name_other})
  end

  @spec process(TS.PlayerData.t()) :: :ok
  def process(%__MODULE__{name: name} = player) do
    receive do
      {:invite, other_name} ->
        Logger.info(" #{name} invited by #{other_name}")
        process(player)

      {:negotiate, ^name, other_name} ->
        Logger.info(
          "#{name} POV: #{other_name} accepted the invitation and trade went to negotiation phase"
        )

        process(player)

      {:trade_change, other_name, p1_inv, p2_inv} ->
        Logger.info(
          "#{other_name} changed the trade contents, now for your #{inspect(p1_inv)} he offers #{
            inspect(p2_inv)
          }"
        )

        process(player)

      {:ready, other_name} ->
        Logger.info("#{other_name} is ready to finish the trade")
        process(player)

      {:finished, other_name} ->
        Logger.info(
          "#{other_name} is also ready, moving the trade to finished phase. You can claim your items back now."
        )

        process(player)
    after
      # Logger.info("No new messages")
      1_000 -> :ok
    end
  end
end
