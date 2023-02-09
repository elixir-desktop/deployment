defmodule Desktop.Deployment.Package do
  @moduledoc false
  alias Desktop.Deployment.Package
  import Desktop.Deployment.Tooling
  require Logger

  defstruct name: "ElixirApp",
            name_long: "The Elixir App",
            description: "An Elixir App for Dekstop",
            description_long: "An Elixir App for Desktop powered by Phoenix LiveView",
            icon: "priv/icon.png",
            # https://developer.gnome.org/menu-spec/#additional-category-registry
            category_gnome: "GNOME;GTK;Office;",
            category_macos: "public.app-category.productivity",
            identifier: "io.elixirdesktop.app",
            # additional ELIXIR_ERL_OPTIONS for boot
            elixir_erl_options: "",
            # import options
            import_inofitywait: false,
            # defined during the process
            app_name: nil,
            release: nil

  def copy_extra_files(%Package{} = pkg) do
    copy_extra_files(os(), pkg)
  end

  defp copy_extra_files(Windows, %Package{release: %Mix.Release{path: rel_path} = rel} = pkg) do
    # Windows renaming exectuable
    [erl] = wildcard(rel, "**/erl.exe")
    new_name = Path.join(Path.dirname(erl), pkg.name <> ".exe")
    File.rename!(erl, new_name)

    # Updating icon
    cmd!("convert", ["-resize", "64x64", pkg.icon, "icon.ico"])

    priv_import!(pkg, "icon.ico")

    :ok = Mix.Tasks.Pe.Update.run(["--set-icon", Path.join(priv(pkg), "icon.ico"), new_name])

    [elixir] = wildcard(rel, "**/elixir.bat")
    file_replace(elixir, "erl.exe", pkg.name <> ".exe")

    base = Mix.Project.deps_paths()[:desktop_deployment]
    windows_tools = Path.absname("#{base}/rel/win32")
    cp!(Path.join(windows_tools, "app.exe.manifest"), new_name <> ".manifest")

    for redist <- ~w(vcredist_x64.exe MicrosoftEdgeWebview2Setup.exe) do
      base_import!(
        rel,
        Path.join([System.get_env("USERPROFILE"), "DistributedDrives/first/build", redist])
      )
    end

    # Windows has wxwidgets & openssl statically linked
    dll_import!(rel, "C:\\msys64\\mingw64\\bin\\libgmp-10.dll")

    wildcard(rel, "**/*.so")
    |> Enum.each(fn name ->
      new_name = Path.join(Path.dirname(name), Path.basename(name, ".so") <> ".dll")
      File.rename!(name, new_name)
    end)

    cp!(Path.join(windows_tools, "run.vbs"), rel_path)
    content = eval_eex(Path.join(windows_tools, "run.bat.eex"), rel, pkg)
    File.write!(Path.join(rel_path, "run.bat"), content)

    pkg
  end

  defp copy_extra_files(os, %Package{release: %Mix.Release{} = rel} = pkg)
       when os == Linux or os == MacOS do
    [beam] = wildcard(rel, "**/beam.smp")
    # Chaning emulator name
    [erl] = wildcard(rel, "**/bin/erl")
    file_replace(erl, "EMU=beam", "EMU=#{pkg.name}")

    # Trying to remove .smp ending
    # unsafe binary editing (confirmed to work on 23.x)
    [erlexec] = wildcard(rel, "**/bin/erlexec")
    file_replace(erlexec, ".smp", <<0, 0, 0, 0>>)

    # Figuring out the result of our edits
    # and renaming beam
    System.put_env("EMU", pkg.name)
    name = cmd!(erlexec, ["-emu_name_exit"])

    # Unsafe binary removal of "Erlang", needs same length!
    file_replace(beam, "Erlang", binary_part(pkg.name <> <<0, 0, 0, 0, 0, 0>>, 0, 6))
    File.rename!(beam, Path.join(Path.dirname(beam), name))

    # Linux ->
    if os == MacOS do
      libs =
        :filelib.wildcard('/Users/administrator/projects/wxWidgets/lib/libwx_*')
        |> Enum.map(&List.to_string/1)

      # This copies links as links
      cmd!("cp", List.flatten(["-a", libs, priv(pkg)]))

      wildcard(rel, "**/*.dylib")
      |> Enum.map(fn lib -> macos_find_deps(lib) end)
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.to_list()
      |> Enum.each(fn lib -> priv_import!(pkg, lib) end)
    else
      if pkg.import_inofitywait do
        bin = System.find_executable("inotifywait")

        if bin == nil do
          IO.puts(
            "import_inoftifywait: true was speccified but the `inotifywait` binary could not be found"
          )

          System.halt(1)
        end

        erst_bin_import!(rel, bin)

        for lib <- linux_find_deps(bin) do
          priv_import!(pkg, lib)
        end
      end

      wildcard(rel, "**/*.so")
      |> Enum.map(fn lib -> linux_find_deps(lib) end)
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.to_list()
      |> Enum.each(fn lib -> priv_import!(pkg, lib) end)
    end

    pkg
  end

  def create_installer(%Package{} = pkg) do
    case os() do
      MacOS -> mac_release(pkg)
      Linux -> linux_release(pkg)
      Windows -> windows_release(pkg)
    end

    pkg
  end

  defp windows_release(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    out_file = Path.join(build_root, "#{pkg.name}-#{vsn}-win32.zip")
    base = Mix.Project.deps_paths()[:desktop_deployment]
    windows_tools = Path.absname("#{base}/rel/win32")

    File.rm(out_file)

    files =
      File.ls!(rel_path)
      |> Enum.map_join(",", fn file -> Path.join(rel_path, file) end)

    cmd!("powershell", ["Compress-Archive #{files} #{out_file}"])

    :file.set_cwd(String.to_charlist(rel_path))

    content = eval_eex(Path.join(windows_tools, "app.nsi.eex"), rel, pkg)
    File.write!(Path.join(build_root, "app.nsi"), content)
    cmd!("makensis", ["-NOCD", "-DVERSION=#{vsn}", Path.join(build_root, "app.nsi")])
    :ok
  end

  defp linux_release(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    linux_tools = Path.absname("#{base}/rel/linux")
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    arch = arch()
    out_file = Path.join(build_root, "#{pkg.name}-#{vsn}-linux-#{arch}.run")

    File.rm(out_file)

    content = eval_eex(Path.join(linux_tools, "install.eex"), rel, pkg)
    File.write!(Path.join(rel_path, "install"), content)
    File.chmod!(Path.join(rel_path, "install"), 0o755)

    run_content = eval_eex(Path.join(linux_tools, "run.eex"), rel, pkg)
    File.write!(Path.join(rel_path, pkg.name), run_content)
    File.chmod!(Path.join(rel_path, pkg.name), 0o755)

    # Remove the original release bin/ dir
    File.rm_rf!(Path.join(rel_path, "bin"))

    :file.set_cwd(String.to_charlist(rel_path))

    cmd!(Path.join(linux_tools, "makeself.sh"), [
      "--xz",
      rel_path,
      out_file,
      pkg.name,
      "./install"
    ])

    :ok
  end

  defp mac_release(%Package{release: %Mix.Release{path: path} = rel} = pkg) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    linux_tools = Path.absname("#{base}/rel/linux")
    mac_tools = Path.absname("#{base}/rel/macosx")

    build_root = Path.join([path, "..", ".."]) |> Path.expand()
    root = Path.join(build_root, "#{pkg.name}.app")
    contents = Path.join(root, "Contents")
    bindir = Path.join(contents, "MacOS")
    resources = Path.join(contents, "Resources")

    File.mkdir_p!(bindir)
    File.mkdir_p!(resources)

    content = eval_eex(Path.join(mac_tools, "Info.plist.eex"), rel, pkg)
    File.write!(Path.join(contents, "Info.plist"), content)
    content_run = eval_eex(Path.join(linux_tools, "run.eex"), rel, pkg)
    File.write!(Path.join(bindir, "run"), content_run)

    File.ls!(path)
    |> Enum.each(fn file ->
      File.cp_r!(Path.join(path, file), Path.join(resources, file), fn src, dst ->
        file_md5(src) != file_md5(dst)
      end)
    end)

    # Creating/copying the icon
    icon_path = Path.join(mac_tools, "icons.icns")

    if not File.exists?(icon_path) do
      iconset = Path.join(build_root, "icons.iconset")
      File.mkdir_p!(iconset)

      cmd!("convert", [
        "-resize",
        "1024x1024",
        pkg.icon,
        Path.join(iconset, "icon_512x512@2x.png")
      ])

      cmd!("convert", ["-resize", "512x512", pkg.icon, Path.join(iconset, "icon_512x512.png")])
      cmd!("iconutil", ["-c", "icns", iconset, "-o", Path.join(mac_tools, "icons.icns")])
    end

    cp!(icon_path, resources)

    developer_id = System.get_env("DEVELOPER_ID")

    if developer_id != nil do
      codesign(developer_id, root)
    end

    dmg = make_dmg(pkg)

    if developer_id != nil do
      package_sign(developer_id, dmg)
    end

    :ok
  end

  defp make_dmg(%Package{release: %Mix.Release{path: path, version: vsn}} = pkg) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    mac_tools = Path.absname("#{base}/rel/macosx")
    build_root = Path.join([path, "..", ".."]) |> Path.expand()
    app_root = Path.join(build_root, "#{pkg.name}.app")
    out_file = Path.join(build_root, "#{pkg.name}-#{vsn}.dmg")
    tmp_file = out_file <> ".tmp.#{:rand.uniform(1_000_000_000)}.dmg"
    File.rm(out_file)

    cmd!("hdiutil", [
      "create",
      "-srcfolder",
      app_root,
      "-volname",
      pkg.name,
      "-fs",
      "HFS+",
      "-layout",
      "NONE",
      "-format",
      "UDRW",
      tmp_file
    ])

    volume = Path.join("/Volumes", pkg.name)

    if File.exists?(volume) do
      cmd!("hdiutil", ["detach", volume])
    end

    cmd!("hdiutil", ["attach", tmp_file])
    # Adding application destination for dragging
    cmd!("ln", ["-s", "/Applications", Path.join(volume, "Applications")])
    # Adding styling
    background_dir = Path.join(volume, ".background")
    File.mkdir(background_dir)
    cp!(Path.join(mac_tools, "background.png"), background_dir)

    File.cp!(Path.join(mac_tools, "DS_Store"), Path.join(volume, ".DS_Store"))
    File.cp!(Path.join(mac_tools, "VolumeIcon.icns"), Path.join(volume, ".VolumeIcon.icns"))

    cmd!("hdiutil", ["detach", volume])

    # Creating final file
    cmd!("hdiutil", ["convert", tmp_file, "-format", "ULFO", "-o", out_file])

    File.rm!(tmp_file)
    out_file
  end

  def package_sign(developer_id, dmg) do
    System.cmd("codesign", [
      "-s",
      developer_id,
      "--timestamp",
      dmg
    ])
  end

  def codesign(developer_id, root) do
    # Codesign all executable code in the package with timestamp and
    # hardened runtime. This is a prerequisite for notarization.
    libs = wildcard(root, "**/*.so") ++ wildcard(root, "**/*.dylib")

    bins =
      wildcard(root, "**")
      |> Enum.filter(fn file -> Bitwise.band(0o100, File.lstat!(file).mode) != 0 end)

    to_sign =
      (bins ++ libs)
      |> Enum.filter(fn file -> File.lstat!(file).type == :regular end)

    base = Mix.Project.deps_paths()[:desktop_deployment]
    mac_tools = Path.absname("#{base}/rel/macosx")
    entitlements = Path.join(mac_tools, "app.entitlements")

    File.write!("codesign.log", Enum.join(to_sign, "\n"))

    # Signing binaries in app directory
    Enum.chunk_every(to_sign, 10)
    |> Enum.each(fn chunk ->
      IO.puts("Signing #{inspect(chunk)}")

      cmd!("codesign", [
        "-f",
        "-s",
        developer_id,
        "--timestamp",
        "--options=runtime",
        "--entitlements",
        entitlements | chunk
      ])
    end)

    # Signing app directory itself
    cmd!("codesign", [
      "-f",
      "-s",
      developer_id,
      "--timestamp",
      "--options=runtime",
      "--entitlements",
      entitlements,
      root
    ])
  end
end
