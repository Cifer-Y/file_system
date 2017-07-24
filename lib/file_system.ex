defmodule FileSystem do
  @moduledoc File.read!("README.md")

  @doc """
  ## Options

    * `:dirs` ([string], requires), the dir list to monitor

    * `:backend` (atom, optional), default backends: `:fs_mac`
      for `macos`, `:fs_inotify` for `linux` and `freebsd`,
      `:fs_windows` for `windows`

    * `:listener_extra_args` (string, optional), extra args for
      port backend.

    * `:name` (atom, optional), `name` can be used to subscribe as
      the same as pid when the `name` is given. The `name` should
      be the name of worker process.

  ## Example

  Simple usage:

      iex> {:ok, pid} = FileSystem.start_link(dirs: ["/tmp/fs"])
      iex> FileSystem.subscribe(pid)

  Get nstant notifications on file changes for Mac OS X:

      iex> FileSystem.start_link(dirs: ["/path/to/some/files"], listener_extra_args: "--latency=0.0")

  Named monitir with specialty backend:

      iex> FileSystem.start_link(backend: :fs_mac, dirs: ["/tmp/fs"], name: :worker)
      iex> FileSystem.subscribe(:worker)
  """
  @spec start_link(Keyword.t) :: {:ok, pid}
  def start_link(options) do
    FileSystem.Worker.start_link(options)
  end

  @doc """
  Regester current process as a subscriber of file_system worker.
  The pid you subscribed from will now receive messages like

      {:file_event, worker_pid, {file_path, events}}
      {:file_event, worker_pid, :stop}
  """
  @spec subscribe(pid() | atom()) :: :ok
  def subscribe(pid) do
    GenServer.call(pid, :subscribe)
  end
end
