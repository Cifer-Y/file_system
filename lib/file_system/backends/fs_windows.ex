require Logger

defmodule FileSystem.Backends.FSWindows do
  @moduledoc """
  This file is a fork from https://github.com/synrc/fs.
  FileSysetm backend for windows, a GenServer receive data from Port, parse event
  and send it to the worker process.
  Need binary executable file packaged in to use this backend.

  ## Backend Options

    * `:recursive` (bool, default: true), monitor directories and their contents recursively
  """

  use GenServer
  @behaviour FileSystem.Backend
  @sep_char <<1>>

  def bootstrap do
    exec_file = find_executable()
    if File.exists?(exec_file) do
      :ok
    else
      Logger.error "Can't find executable `inotifywait.exe`, make sure the file is in your priv dir."
      {:error, :fs_windows_bootstrap_error}
    end
  end

  def supported_systems do
    [{:win32, :nt}]
  end

  def known_events do
    [:created, :modified, :removed, :renamed, :undefined]
  end

  defp find_executable do
    (:code.priv_dir(:file_system) ++ '/inotifywait.exe') |> to_string
  end

  def parse_options(options) do
    case Keyword.pop(options, :dirs) do
      {nil, _} ->
        Logger.error "required argument `dirs` is missing"
        {:error, :missing_dirs_argument}
      {dirs, rest} ->
        format = ["%w", "%e", "%f"] |> Enum.join(@sep_char) |> to_charlist
        args = [
          '--format', format, '--quiet', '-m', '-r'
          | dirs |> Enum.map(&Path.absname/1) |> Enum.map(&to_charlist/1)
        ]
        parse_options(rest, args)
    end
  end

  defp parse_options([], result), do: {:ok, result}
  defp parse_options([{:recursive, true} | t], result) do
    parse_options(t, result)
  end
  defp parse_options([{:recursive, false} | t], result) do
    parse_options(t, result -- ['-r'])
  end
  defp parse_options([{:recursive, value} | t], result) do
    Logger.error "unknown value `#{inspect value}` for recursive, ignore"
    parse_options(t, result)
  end
  defp parse_options([h | t], result) do
    Logger.error "unknown option `#{inspect h}`, ignore"
    parse_options(t, result)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    {worker_pid, rest} = Keyword.pop(args, :worker_pid)
    case parse_options(rest) do
      {:ok, port_args} ->
        port = Port.open(
          {:spawn_executable, to_charlist(find_executable())},
          [:stream, :exit_status, {:line, 16384}, {:args, port_args}, {:cd, System.tmp_dir!()}]
        )
        Process.link(port)
        Process.flag(:trap_exit, true)
        {:ok, %{port: port, worker_pid: worker_pid}}
      {:error, _} ->
        :ignore
    end
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port}=state) do
    {file_path, events} = line |> parse_line
    send(state.worker_pid, {:backend_file_event, self(), {file_path, events}})
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _}}, %{port: port}=state) do
    send(state.worker_pid, {:backend_file_event, self(), :stop})
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, port, _reason}, %{port: port}=state) do
    send(state.worker_pid, {:backend_file_event, self(), :stop})
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def parse_line(line) do
    {path, flags} =
      case line |> to_string |> String.split(@sep_char, trim: true) do
        [dir, flags, file] -> {Enum.join([dir, file], "\\"), flags}
        [path, flags]      -> {path, flags}
      end
    {path, flags |> String.split(",") |> Enum.map(&convert_flag/1)}
  end

  defp convert_flag("CREATE"),   do: :created
  defp convert_flag("MODIFY"),   do: :modified
  defp convert_flag("DELETE"),   do: :removed
  defp convert_flag("MOVED_TO"), do: :renamed
  defp convert_flag(_),          do: :undefined
end
