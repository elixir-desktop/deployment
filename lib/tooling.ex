defmodule Desktop.Deployment.Tooling do
  alias Desktop.Deployment.Package
  require Logger
  @moduledoc false

  def file_replace(file, from, to) do
    orig = File.read!(file)
    content = String.replace(orig, from, to)

    if orig != content do
      File.chmod!(file, Bitwise.bor(File.lstat!(file).mode, 0o200))
      File.write!(file, content)
    end
  end

  def wildcard(%Mix.Release{path: rel_path}, path) do
    wildcard(rel_path, path)
  end

  def wildcard(rel_path, path) do
    :filelib.wildcard(Path.join(rel_path, path) |> String.to_charlist())
    |> Enum.map(&List.to_string/1)
  end

  def machine() do
    cmd!("dpkg-architecture", ["-q", "DEB_BUILD_GNU_TYPE"])
  end

  def arch() do
    cmd!("uname", ["-m"])
  end

  def priv(%{app_name: app, release: %Mix.Release{path: path, version: vsn}}) do
    Path.join([path, "lib", "#{app}-#{vsn}", "priv"])
  end

  def relative_priv(%{app_name: app, release: %Mix.Release{version: vsn}}) do
    Path.join(["lib", "#{app}-#{vsn}", "priv"])
  end

  def priv_import!(pkg, src, opts \\ []) do
    # Copying libraries to app_name-vsn/priv and adding that to (DY)LD_LIBRARY_PATH
    strip = Keyword.get(opts, :strip, true)
    extra_path = Keyword.get(opts, :extra_path, [])

    dst = Path.join([priv(pkg)] ++ extra_path ++ [Path.basename(src)])
    File.mkdir_p(priv(pkg))

    if not File.exists?(dst) do
      File.cp!(src, dst)
      File.chmod!(dst, 0o755)
      if strip, do: strip_symbols(dst)
    end

    src
  end

  def dll_import!(%Mix.Release{} = rel, src) do
    # In windows the primary .exe directory is searched for missing dlls
    # (and there is no LD_LIBRARY_PATH)
    erts_bin_import!(rel, src)
  end

  def erts_bin_import!(%Mix.Release{path: path}, src) do
    erts = Application.app_dir(:erts) |> Path.basename()
    bindir = Path.join([path, erts, "bin"])
    dst = Path.join(bindir, Path.basename(src))

    if not File.exists?(dst) do
      File.cp!(src, dst)
      strip_symbols(dst)
    end
  end

  def strip_symbols(file) do
    extname = Path.extname(file)
    is_binary = extname == ""
    is_library = Regex.match?(~r/\.(so|dylib|smp)($|\.)/, extname)

    strip_args =
      cond do
        os() == MacOS and is_library -> ["-x", "-S"]
        os() == MacOS and is_binary -> ["-u", "-r"]
        is_binary || is_library -> ["-s"]
        true -> nil
      end

    if strip_args do
      File.chmod!(file, Bitwise.bor(File.lstat!(file).mode, 0o200))
      cmd!("strip", strip_args ++ [file])
    end

    file
  end

  def base_import!(%Mix.Release{path: path}, src) do
    # Copying redesitributables to app_name-vsn
    dst = Path.join(path, Path.basename(src))
    if not File.exists?(dst), do: File.cp!(src, dst)
  end

  # Same as File.cp! but uses directory as second argument.
  def cp!(src, destination) do
    dst = Path.join(destination, Path.basename(src))
    File.cp!(src, dst)
  end

  def eval_eex(filename, rel, pkg) do
    EEx.eval_file(filename, assigns: [release: rel, package: pkg])
  end

  def file_md5(name) do
    File.stream!(name, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
  end

  def os() do
    case :os.type() do
      {:unix, :darwin} -> MacOS
      {:unix, :linux} -> Linux
      {:win32, _} -> Windows
    end
  end

  def cmd!(cmd, args) when is_list(cmd) do
    cmd!(List.to_string(cmd), args)
  end

  def cmd!(cmd, args) do
    {ret, 0} = cmd_raw(cmd, args)
    ret
  end

  def cmd(cmd, args) do
    {ret, _} = cmd_raw(cmd, args)
    ret
  end

  def cmd_raw(cmd, args) do
    args = Enum.map(List.wrap(args), fn arg -> "#{arg}" end)
    IO.puts("Running: #{cmd} #{Enum.join(args, " ")}")
    {ret, status} = System.cmd(cmd, args)
    {String.trim_trailing(ret), status}
  end

  def cmd_status(cmd, args) do
    {_, status} = cmd_raw(cmd, args)
    status
  end

  def find_all_deps(os, new_objects, old_objects \\ MapSet.new())

  def find_all_deps(_os, [], _old_objects) do
    []
  end

  def find_all_deps(os, new_objects, old_objects) do
    new_objects = MapSet.new(new_objects)
    old_objects = MapSet.union(new_objects, old_objects)

    result =
      new_objects
      |> Enum.map(fn lib -> find_deps(os, lib) end)
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.difference(old_objects)
      |> MapSet.to_list()

    result ++ find_all_deps(os, result, old_objects)
  end

  def find_deps(MacOS, object) do
    cwd = File.cwd!()

    Package.MacOS.find_deps(object)
    |> Enum.filter(fn lib ->
      Enum.any?(Package.MacOS.import_prefixes(), &String.starts_with?(lib, &1)) and
        not String.starts_with?(lib, cwd) and
        existing_dep?(lib, object)
    end)
  end

  def find_deps(Linux, object) do
    cmd!("ldd", [object])
    |> String.split("\n")
    |> Enum.map(fn row ->
      case String.split(row, " ") do
        [name, "=>", "not" | _] ->
          raise "Error locating required library #{String.trim(name)} for #{object}"

        [_, "=>", path | _] ->
          path

        _other ->
          nil
      end
    end)
    |> Enum.filter(fn lib ->
      is_binary(lib) and Path.basename(lib) not in linux_builtin()
    end)
  end

  # A dependency's recorded install path can point at a location that only ever
  # existed on the machine that built the binary. Precompiled NIFs are the common
  # case: e.g. exqlite's prebuilt artifact bakes in the CI runner path
  # `/Users/runner/work/exqlite/...`, which matches our `/Users/` import prefix
  # but does not exist here. Such a path can neither be inspected with `otool -L`
  # (it fails hard and crashes the build) nor copied into the bundle, so we skip
  # it. Anything genuinely required is resolvable next to the binary or via the
  # linker's search paths.
  defp existing_dep?(lib, object) do
    if File.exists?(lib) do
      true
    else
      Logger.warning(
        "desktop_deployment: skipping dependency #{lib} of #{object} — no such file " <>
          "on this machine (stale path baked into a precompiled binary?)"
      )

      false
    end
  end

  # https://raw.githubusercontent.com/probonopd/AppImages/master/excludelist
  @excludelist File.read!("priv/AppImages/excludelist")
               |> String.split("\n")
               |> Enum.map(fn row ->
                 case String.split(row, " ") do
                   [] -> nil
                   ["#" <> _ | _] -> nil
                   [lib | _] -> lib
                 end
               end)
               |> Enum.filter(fn lib -> lib != nil and lib != "" end)
  def linux_builtin() do
    @excludelist
  end

  def download_file(filename, url, attempts \\ 3) do
    Mix.Shell.IO.info("Downloading #{filename} from #{url}")
    {:ok, _} = Application.ensure_all_started(:httpoison)

    # These downloads (e.g. the Windows WebView2/vcredist redistributables) are
    # large and the endpoints occasionally stall on CI. Use a generous receive
    # timeout and retry on any failure so a transient network hiccup doesn't
    # fail an otherwise-good installer build.
    opts = [follow_redirect: true, timeout: 30_000, recv_timeout: 180_000]

    case HTTPoison.get(url, [], opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        File.write!(filename, body)

      other when attempts > 1 ->
        Mix.Shell.IO.info(
          "Download of #{filename} failed (#{inspect(elem_or(other))}); retrying (#{attempts - 1} left)"
        )

        Process.sleep(3_000)
        download_file(filename, url, attempts - 1)

      {:ok, %HTTPoison.Response{status_code: code}} ->
        raise "Failed to download #{filename} from #{url}: HTTP #{code}"

      {:error, %{reason: reason}} ->
        raise "Failed to download #{filename} from #{url}: #{inspect(reason)}"
    end
  end

  defp elem_or({:ok, %HTTPoison.Response{status_code: code}}), do: {:http, code}
  defp elem_or({:error, %{reason: reason}}), do: reason
  defp elem_or(other), do: other
end
