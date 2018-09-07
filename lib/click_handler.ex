defmodule Clicks do
  def start_link(args) do
    args
    |> Enum.reduce(%{}, fn x, acc ->
      case x do
        {name, _, click_event} ->
          Map.put(acc, name, click_event)

        _ ->
          acc
      end
    end)
    |> listen_for_clicks

    {:ok, self()}
  end

  defp listen_for_clicks(files) do
    :timer.sleep(100)

    IO.gets("")
    |> Poison.decode()
    |> handle_click(files)

    listen_for_clicks(files)
  end

  defp handle_click(json, files) do
    case json do
      {:ok, map} ->
        case script = files[String.to_atom(map["name"])] do
          nil ->
            nil

          _ ->
            spawn(fn -> System.cmd("bash", [Atom.to_string(script)]) end)
        end

      _ ->
        nil
    end

    files
  end
end
