defmodule TS.Trade do
  @behaviour :gen_statem
  require Logger

  require Record
  Record.defrecord(:trade_state, name: "", inventory: %{}, ready: false)
  # STATE:
  # P1_name, inventory, ready
  # P2_name, inventory, ready
  # drop ready in collect state

  import TS.PlayerData

  # Client API
  def start(player1_name, player2_name) do
    Logger.info("Trade starting")
    :gen_statem.start(__MODULE__, [player1_name, player2_name], [])
  end

  def ready(pid, player_name) do
    :gen_statem.call(pid, {:ready, player_name})
  end

  def add_item(pid, player_name, inventory, item, quantity) do
    case Map.fetch(inventory, item) do
      {:ok, in_inv} when in_inv >= quantity ->
        :gen_statem.call(pid, {:add, player_name, item, quantity})
        Map.update(inventory, item, 0, &(&1 - quantity))

      _other ->
        Logger.debug("Cannot add item #{item} in quantity #{quantity} by #{player_name}")
        inventory
    end
  end

  def remove_item(pid, player_name, inventory, item, quantity) do
    case :gen_statem.call(pid, {:remove, player_name, item, quantity}) do
      :ok ->
        Map.update(inventory, item, 0, &(&1 + quantity))

      :error ->
        Logger.debug("Cannot remove item #{item} in quantity #{quantity} by #{player_name}")
        inventory
    end
  end

  def collect(pid, player_name, inventory) do
    loot = :gen_statem.call(pid, {:collect, player_name})
    Map.merge(inventory, loot, fn _k, v1, v2 -> v1 + v2 end)
  end

  def cancel(pid) do
    :gen_statem.call(pid, :cancel)
  end

  def stop(pid) do
    :gen_statem.stop(pid)
  end

  # API:
  # cancel -> handle_event, puts trade into complete state
  # check -> handle_event, returns current items on auction

  # collect -> get item back from trade, whether its succesful or not
  # add_item -> adds item to player list
  # remove_item -> remove item from the list
  # ready_up -> change player X state to ready, both ready is transition

  # Callbacks

  def callback_mode, do: :state_functions

  def init([player1_name, player2_name]),
    do: {:ok, :awaiting, {trade_state(name: player1_name), trade_state(name: player2_name)}}

  def terminate(_reason, _state, _data), do: :void

  def code_change(_vsn, state, data, _extra), do: {:ok, state, data}

  # State functions
  def awaiting(
        {:call, from},
        {:ready, name},
        {trade_state(name: name1) = ts1, trade_state(name: name2) = ts2}
      ) do
    reply =
      case name do
        ^name1 ->
          ts1_new = trade_state(ts1, ready: true)
          {:keep_state, {ts1_new, ts2}, [{:reply, from, :ok}]}

        ^name2 ->
          ts2_new = trade_state(ts2, ready: true)
          {:keep_state, {ts1, ts2_new}, [{:reply, from, :ok}]}

        _other ->
          Logger.debug("Trade: Unknown player #{name}")
          {:keep_state, {ts1, ts2}, [{:reply, from, :ok}]}
      end

    {trade_state(name: caller_name), trade_state(name: other_name)} =
      match_caller(name, {ts1, ts2})

    unless both_ready?(elem(reply, 1)) do
      send_invite(caller_name, other_name)
      reply
    else
      # negotiation start
      # inform other player

      entered_negotiation(caller_name, other_name)
      Logger.info("A trade is going to negotiation state")

      {:next_state, :negotiation,
       {trade_state(ts1, ready: false), trade_state(ts2, ready: false)},
       [{:reply, from, :negotiate}]}
    end
  end

  def awaiting({:call, from}, _, data) do
    {:keep_state, data, [{:reply, from, :not_supported}]}
  end

  defp both_ready?({trade_state(ready: true), trade_state(ready: true)}), do: true
  defp both_ready?({_ts1, _ts2}), do: false

  def negotiation({:call, from}, {:ready, name}, data) do
    {trade_state(name: caller_name, inventory: caller_inventory) = ts1,
     trade_state(name: other_name, inventory: other_inventory) = ts2} = match_caller(name, data)

    send_ready(other_name, caller_name)
    ts1 = trade_state(ts1, ready: true)

    unless both_ready?({ts1, ts2}) do
      {:keep_state, {ts1, ts2}, [{:reply, from, :ok}]}
    else
      # negotiation start
      # inform other player
      send_finished(other_name, caller_name)
      Logger.info("A trade is finished, you can collect now")

      {:next_state, :finished,
       {trade_state(ts1, ready: false, inventory: other_inventory),
        trade_state(ts2, ready: false, inventory: caller_inventory)}, [{:reply, from, :finished}]}
    end
  end

  def negotiation({:call, from}, {:add, player_name, item, quantity}, data) do
    {trade_state(name: caller_name, inventory: caller_inventory) = ts1,
     trade_state(name: other_name, inventory: other_inventory) = ts2} =
      match_caller(player_name, data)

    updated_inventory = Map.update(caller_inventory, item, quantity, &(&1 + quantity))
    send_trade_change(other_name, caller_name, other_inventory, updated_inventory)

    {:keep_state,
     {trade_state(ts1, inventory: updated_inventory, ready: false),
      trade_state(ts2, ready: false)}, [{:reply, from, :ok}]}
  end

  def negotiation({:call, from}, {:remove, player_name, item, quantity}, data) do
    {trade_state(name: caller_name, inventory: caller_inventory) = ts1,
     trade_state(name: other_name, inventory: other_inventory) = ts2} =
      match_caller(player_name, data)

    updated_inventory = Map.update(caller_inventory, item, -1, &(&1 - quantity))

    case Map.fetch(updated_inventory, item) do
      {:ok, i} when i < 0 ->
        {:keep_state, {ts1, ts2}, [{:reply, from, :error}]}

      {:ok, _} ->
        send_trade_change(other_name, caller_name, other_inventory, updated_inventory)

        {:keep_state,
         {trade_state(ts1, inventory: updated_inventory, ready: false),
          trade_state(ts2, ready: false)}, [{:reply, from, :ok}]}
    end
  end

  def negotiation({:call, from}, _, data) do
    {:keep_state, data, [{:reply, from, :not_supported}]}
  end

  # Returns trade state of {caller, other} form
  defp match_caller(caller_name, {trade_state(name: caller_name) = ts1, ts2}) do
    {ts1, ts2}
  end

  defp match_caller(caller_name, {ts1, trade_state(name: caller_name) = ts2}) do
    {ts2, ts1}
  end

  def finished({:call, from}, {:collect, player_name}, data) do
    {trade_state(inventory: caller_inventory) = cts, ots} = match_caller(player_name, data)
    cts = trade_state(cts, inventory: %{})

    if both_empty?(cts, ots) do
      {:stop_and_reply, :normal, [{:reply, from, caller_inventory}]}
    else
      {:keep_state, {cts, ots}, [{:reply, from, caller_inventory}]}
    end
  end

  def finished({:call, from}, _, data) do
    {:keep_state, data, [{:reply, from, :not_supported}]}
  end

  defp both_empty?(trade_state(inventory: inv1), trade_state(inventory: inv2))
       when inv1 == %{} and inv2 == %{},
       do: true

  defp both_empty?(_ts1, _ts2), do: false

  # Confirm current trade contents
  def handle_event({:call, from}, :check, data) do
    {:keep_state, data, [{:reply, from, data}]}
  end

  # Cancel trade
  def handle_event(
        {:call, from},
        {:cancel, name},
        {trade_state(name: name1), trade_state(name: name2)} = data
      ) do
    # inform other that its cancelled
    case name do
      ^name1 ->
        send_finished(name2, name1)

      ^name2 ->
        send_finished(name1, name2)

      _oth ->
        Logger.debug("Trade: Unknown player #{name}")
    end

    {:next_state, :finished, data, [{:reply, from, :cancelled}]}
  end

  def handle_event(_event, _content, data), do: {:keep_state, data}
end

# awaiting -> one player didnt accept trade, both can cancel
## add_item -> deny
## remove_item -> deny

# negotiate -> add item, inform other party (async)
## add_item -> add item to the trade, inform other party (async)
## remove_item -> remove item from the trade, inform other party (async)

# complete -> send items (sync), end process after both parties retrieved items
## cancel - ignored
## collect - give item back
## change_items - ignored
## accept - ignored

# Player API:
# {:trade_change, name_other, inv_my, inv_other} <- receive
# {:ready, name_other} <- other player is ready
# {:finished, name_other} <- other player cancelled
