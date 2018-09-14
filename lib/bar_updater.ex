defmodule Updater do
  use GenServer

  @moduledoc """
  The module that handles everything
  """

  @doc """
  Starts a GenServer which will handle requests

  Returns `{:ok, pid}`
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: :Updater)
  end

  @doc """
  Sets up state

  Returns `{:ok, state}`
  """
  @impl true
  def init(files) do
    state =
      files
      |> Enum.map_reduce(%{}, fn x, acc ->
        %{:name => name} = x

        {name,
         Map.put(
           acc,
           name,
           Enum.into(x, %{
             :click => nil,
             :time => 999_999,
             :left => 0,
             :content => [],
             :status => 1
           })
         )}
      end)

    send(self(), :start)

    {:ok, state}
  end

  @doc """
  Handles a click

  Returns `:ok`
  """
  @impl true
  def handle_call({:click, clickmap}, _from, {order, files}) do
    files = handle_click(files, clickmap)
    send(self(), {:checkupdate, 0, false})

    {:reply, :ok, {order, files}}
  end

  @doc """
  Handles a custom even

  Returns `:ok`
  """
  @impl true
  def handle_call({:custom, %{"name" => key, "action" => action} = json}, _from, {order, files}) do
    %{^key => map} = files

    files =
      case action do
        "update" ->
          Map.put(files, key, Map.put(map, :left, 0))

        "enable" ->
          Map.put(files, key, Map.put(map, :status, 1))

        "disable" ->
          Map.put(files, key, Map.put(map, :status, 0))

        "set" ->
          Map.put(
            files,
            key,
            Map.put(map, String.to_atom(json["key"]), json["value"])
          )

        _ ->
          files
      end

    send(self(), {:checkupdate, 0, false})

    {:reply, :ok, {order, files}}
  end

  @doc """
  The start callback really. Starts a loop for timing updates
  """
  @impl true
  def handle_info(:start, state) do
    IO.puts("{\"version\":1,\"click_events\":true}")
    IO.puts("[")
    send(self(), {:checkupdate, 0, true})
    {:noreply, state}
  end

  @doc """
  Callback to update blocks
  """
  @impl true
  def handle_info({:checkupdate, time, loop}, {order, files}) do
    {tasks, files} =
      files
      |> Enum.reduce({[], %{}}, fn {name,
                                    %{:time => refresh, :left => left, :status => status} = map2},
                                   {list, map} ->
        newtime = left - time

        cond do
          newtime <= 0 && status == 1 ->
            {[update_contents(name) | list], Map.put(map, name, Map.put(map2, :left, refresh))}

          status == 1 ->
            {list,
             Map.put(
               map,
               name,
               Map.put(
                 map2,
                 :left,
                 newtime
               )
             )}

          status == 0 ->
            {list,
             Map.put(
               map,
               name,
               Map.put(
                 map2,
                 :left,
                 refresh
               )
             )}

          true ->
            {list, map}
        end
      end)

    files =
      tasks
      |> Enum.map(&Task.await/1)
      |> Enum.into(files, fn {file, content} ->
        %{^file => map} = files
        {file, Map.put(map, :content, content)}
      end)

    send_blocks(files, order)

    if loop do
      files
      |> get_minimum_time
      |> (&Process.send_after(self(), {:checkupdate, &1, true}, &1)).()
    end

    {:noreply, {order, files}}
  end

  defp handle_click(files, %{"name" => key} = clickmap) do
    %{^key => map} = files

    case map[:click] do
      nil ->
        files

      script ->
        {:ok, str} = Poison.encode(clickmap)
        System.cmd(Path.expand(script), [str])
    end

    Map.put(files, key, Map.put(map, :left, 0))
  end

  defp update_contents(file) do
    Task.async(fn -> {file, BlockWatcher.update(file)} end)
  end

  defp get_minimum_time(state) do
    state
    |> Enum.reduce(999_999, fn x, acc ->
      {_, %{:left => left, :status => status}} = x

      case status do
        1 ->
          min(left, acc)

        _ ->
          acc
      end
    end)
  end

  defp send_blocks(files, order) do
    order
    |> Enum.reduce([], fn x, acc ->
      %{^x => %{:content => content}} = files

      case content do
        nil ->
          acc

        _ ->
          [Enum.join(content, ",") | acc]
      end
    end)
    |> Enum.join(",")
    |> (&IO.puts("[" <> &1 <> "]")).()

    files
  end
end
