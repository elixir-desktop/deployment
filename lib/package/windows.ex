defmodule Desktop.Deployment.Package.Windows do
  @moduledoc """
  Windows specific deployment functions.
  """
  import Desktop.Deployment.Tooling
  alias Desktop.Deployment.Package

  @redistributables [
    "MicrosoftEdgeWebview2Setup.exe",
    "vcredist_x64.exe"
  ]

  def release(%Package{} = pkg) do
    case pkg.windows_layout do
      :host_first ->
        release_host_first(pkg)

      :release_first ->
        release_release_first(pkg)

      other ->
        raise "Unknown windows_layout #{inspect(other)}. Use :host_first or :release_first."
    end
  end

  defp release_host_first(%Package{release: %Mix.Release{path: path, version: vsn} = rel} = pkg) do
    build_root = Path.join([path, "..", ".."]) |> Path.expand()
    package_root = Path.join(build_root, pkg.name)
    File.rm_rf(package_root)
    File.mkdir_p!(package_root)

    release_subdir = pkg.release_subdir || "beam"
    beam_root = Path.join(package_root, release_subdir)
    File.mkdir_p!(beam_root)

    host_bin = resolve_host_binary!(pkg)

    # Destination name in $INSTDIR. Prefer an explicit host_executable, then the
    # package name (so taskbar pins / shortcuts to dDrive.exe keep working), then
    # the source basename (e.g. DesktopWebView.exe).
    host_name =
      cond do
        is_binary(pkg.host_executable) and pkg.host_executable != "" ->
          pkg.host_executable

        is_binary(pkg.name) and to_string(pkg.name) != "" ->
          to_string(pkg.name) <> ".exe"

        true ->
          Path.basename(host_bin)
      end

    dest = Path.join(package_root, host_name)
    File.cp!(host_bin, dest)
    IO.puts("Host-first Windows/#{host_name} <- #{host_bin}")

    beam_app = pkg.beam_app_name || to_string(pkg.app_name || Mix.Project.config()[:app])

    # Windows Mix releases ship `bin/<app>.bat` alongside the Unix `bin/<app>`
    # shell script. Prefer the batch name in the ini so hosts without the
    # ".bat preference" fix still spawn correctly.
    beam_app =
      if match?({:win32, _}, :os.type()) and not String.ends_with?(beam_app, ".bat") and
           not String.ends_with?(beam_app, ".cmd") do
        beam_app <> ".bat"
      else
        beam_app
      end

    ini = """
    [beam]
    path = #{release_subdir}
    app_name = #{beam_app}
    args = start
    working_dir = #{release_subdir}

    [network]
    host = 127.0.0.1
    port = 0

    [lifetime]
    mode = reconnect
    # Host-driven BEAM restart (replaces the heart watchdog). The native
    # host watches its child BEAM process and respawns it on any exit;
    # `system.prepare_quit` from Elixir suppresses respawn during a
    # user-initiated quit. The Erlang release does not need -heart here.
    restart_beam = true
    restart_max_attempts = 0
    restart_backoff_ms = 500
    """

    File.write!(Path.join(package_root, "#{Path.rootname(host_name)}.ini"), ini)

    File.ls!(path)
    |> Enum.each(fn file ->
      File.cp_r!(Path.join(path, file), Path.join(beam_root, file), fn src, dst ->
        file_md5(src) != file_md5(dst)
      end)
    end)

    # Redistributables live at package root (next to the host), not only in beam/
    for redist <- @redistributables do
      src = Path.join(beam_root, redist)

      if File.exists?(src) do
        File.rename!(src, Path.join(package_root, redist))
      end
    end

    icon_rel = Path.join(["lib", "#{pkg.app_name}-#{vsn}", "priv", "icon.ico"])

    pkg =
      pkg
      |> put_priv(:windows_layout, :host_first)
      |> put_priv(:host_executable, host_name)
      |> put_priv(:release_subdir, release_subdir)
      |> put_priv(:icon_rel, Path.join(release_subdir, icon_rel))
      |> put_priv(:package_root, package_root)
      |> put_priv(:nsi_outfile, "../#{pkg.name}-#{vsn}.exe")
      |> put_priv(:scheme_launcher, "\"${TARGET}\" \"%1\"")

    finalize_windows_installer(pkg, rel, package_root)
  end

  defp release_release_first(
         %Package{release: %Mix.Release{path: path, version: vsn} = rel} = pkg
       ) do
    icon_rel = Path.join(["lib", "#{pkg.app_name}-#{vsn}", "priv", "icon.ico"])

    pkg =
      pkg
      |> put_priv(:windows_layout, :release_first)
      |> put_priv(:icon_rel, icon_rel)
      |> put_priv(:package_root, path)
      |> put_priv(:nsi_outfile, "../../#{pkg.name}-#{vsn}.exe")
      |> put_priv(
        :scheme_launcher,
        "\"$WINDIR\\system32\\wscript.exe\" \"${TARGET}\" \"%1\""
      )

    finalize_windows_installer(pkg, rel, path)
  end

  defp finalize_windows_installer(%Package{release: %Mix.Release{version: vsn}} = pkg, rel, cwd) do
    build_root = Path.join([rel.path, "..", ".."]) |> Path.expand()
    signfun = Package.win32_sign_function(pkg)

    if signfun == nil do
      Mix.Shell.IO.info("Not signing secret detected. Skipping signing")
    else
      Package.win32_codesign(signfun, build_root)
    end

    nsi_file = Package.toolpath("rel/win32/app.nsi.eex")
    {:ok, cur} = :file.get_cwd()
    :file.set_cwd(String.to_charlist(cwd))

    content = eval_eex(nsi_file, rel, pkg)
    File.write!(Path.join(build_root, "app.nsi"), content)
    cmd!("makensis", ["-NOCD", "-DVERSION=#{vsn}", Path.join(build_root, "app.nsi")])
    :file.set_cwd(cur)

    outfile = "#{pkg.name}-#{vsn}.exe"

    if signfun != nil do
      path = Path.join([build_root, outfile])
      signfun.(path)
    end

    %{pkg | priv: Map.put(pkg.priv, :installer_name, outfile)}
  end

  defp resolve_host_binary!(%Package{} = pkg) do
    explicit =
      [
        pkg.host_binary,
        System.get_env("DESKTOP_HOST_BINARY"),
        # Back-compat alias used by existing build scripts
        System.get_env("DESKTOP_WEBVIEW_BINARY")
      ]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.map(&Path.expand/1)
      |> Enum.filter(&File.exists?/1)

    case explicit do
      [path | _] ->
        path

      [] ->
        case discover_host_binaries(pkg) do
          [path] ->
            path

          [] ->
            raise """
            Native host binary not found for Windows :host_first packaging.

            Set package.host_binary, DESKTOP_HOST_BINARY, or ship a binary under a
            Mix dependency at priv/native/windows/<executable>.exe (discovered by convention).
            """

          paths ->
            raise """
            Multiple host binaries found for Windows :host_first packaging:

            #{Enum.map_join(paths, "\n", &"  #{&1}")}

            Set package.host_binary to select one. package.host_executable only
            controls the installed filename (defaults to package.name.exe).
            """
        end
    end
  end

  # Convention only: any Mix dep that ships priv/native/windows/<exe>.exe.
  # Deployment never names a particular OTP application (e.g. desktop_webview).
  # `package.host_executable` is the *installed* name (may differ from the source
  # basename, e.g. DesktopWebView.exe → dDrive.exe) and is not used to filter
  # discovery here.
  defp discover_host_binaries(%Package{} = _pkg) do
    dep_bins =
      for {_app, path} <- Mix.Project.deps_paths(),
          file <- Path.wildcard(Path.join(path, "priv/native/windows/*.exe")),
          File.regular?(file),
          do: Path.expand(file)

    preferred = Enum.filter(dep_bins, &(Path.basename(&1) == "DesktopWebView.exe"))
    bins = if preferred != [], do: preferred, else: dep_bins
    Enum.uniq(bins)
  end

  defp put_priv(pkg, key, value) do
    %{pkg | priv: Map.put(pkg.priv, key, value)}
  end
end
