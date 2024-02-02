defmodule TS.Players do
  use GenServer
  require Logger

  @doc """
  Client: Gets pid for a given player.
  """
  def get(player) do
    GenServer.call(__MODULE__, {:get, player})
  end

  @doc """
  Client: Add pid of a given player.
  """
  def register(name) do
    GenServer.call(__MODULE__, {:register, name})
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

  # Server: Gets pid for a given player.
  @impl true
  def handle_call({:get, player}, _from, {players, _monitors} = state) do
    {:reply, Map.get(players, player), state}
  end

  @doc """
  Server: Add pid of a given player.
  Doesn't check if player already exists!
  """
  @impl true
  def handle_call({:register, player}, {pid, _ref}, {players, monitors}) do
    players_update = Map.put(players, player, pid)
    ref = Process.monitor(pid)
    monitors_update = Map.put(monitors, ref, player)
    {:reply, {:ok, player, pid}, {players_update, monitors_update}}
  end

  # To test: Process.exit(self, :normal)
  # Player has to exist
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {players, monitors}) do
    {player, monitors_update} = Map.pop(monitors, ref)
    {pid, players_update} = Map.pop(players, player)

    Logger.info("Process for player #{player} with #{inspect(pid)} is down")

    {:noreply, {players_update, monitors_update}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
