defmodule TS.TradingCenter do
  @moduledoc """
  Maps trades between players to the underlying FSM processes.
  Keys are of {player1, player2} and {player2, player1} form.
  """
  use GenServer
  require Logger

  @doc """
  Client: Add pid of a given player.
  Initiator and Recipent need to be comparable.
  """
  def start_trade(initiator, recipent) do
    GenServer.call(__MODULE__, {:trade, initiator, recipent})
  end

  @doc """
  Name is always the module name
  """
  def start_link(opts) do
    opts = Keyword.put(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    {:ok, {%{}, %{}}}
  end

  @doc """
  Server: Create new trade or return existing.
  """
  @impl true
  def handle_call({:trade, initiator, recipent}, {_pid, _ref}, {trades, monitors}) do
    trade_id = {min(initiator, recipent), max(initiator, recipent)}
    # Get trade if it already exists
    {trades_update, monitors_update} =
      case Map.has_key?(trades, trade_id) do
        false ->
          # Create new Trade FSM spawn, monitor
          {:ok, trade} = TS.Trade.start(elem(trade_id, 0), elem(trade_id, 1))
          ref = Process.monitor(trade)
          Logger.info("New trade: #{inspect(trade_id)}")
          TS.Trade.ready(trade, initiator)

          {Map.put(trades, trade_id, trade), Map.put(monitors, ref, trade_id)}

        true ->
          {trades, monitors}
      end

    {:reply, {:ok, trade_id, Map.get(trades_update, trade_id)}, {trades_update, monitors_update}}
  end

  # To test: Process.exit(self, :normal)
  # Player has to exist
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {trades, monitors}) do
    {trade_id, monitors_update} = Map.pop(monitors, ref)
    {pid, trades_update} = Map.pop(trades, trade_id)

    Logger.info("Process for trade #{inspect(trade_id)} with #{inspect(pid)} is down")

    {:noreply, {trades_update, monitors_update}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
