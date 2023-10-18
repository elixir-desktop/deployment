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

  def copy_extra_files(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    vm_args = Path.absname("#{base}/rel/vm.args.eex")
    content = eval_eex(vm_args, rel, pkg)
    vm_args_out = Path.join([rel_path, "releases", vsn, "vm.args"])
    File.write!(vm_args_out, content)

    copy_extra_files(os(), pkg)
  end

  defp copy_extra_files(Windows, %Package{release: %Mix.Release{path: rel_path} = rel} = pkg) do
    # Windows renaming exectuable
    [erl] = wildcard(rel, "**/erl.exe")
    new_name = Path.join(Path.dirname(erl), pkg.name <> ".exe")
    File.rename!(erl, new_name)

    # Updating icon
    cmd!("convert", ["-resize", "64x64", pkg.icon, "icon.ico"])

    priv_import!(pkg, "icon.ico", false)

    icon = Path.join(priv(pkg), "icon.ico")
    base = Mix.Project.deps_paths()[:desktop_deployment]
    windows_tools = Path.absname("#{base}/rel/win32")
    content = eval_eex(Path.join(windows_tools, "app.exe.manifest.eex"), rel, pkg)
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    File.write!(Path.join(build_root, "app.exe.manifest"), content)

    :ok =
      Mix.Tasks.Pe.Update.run([
        "--set-icon",
        icon,
        "--set-manifest",
        Path.join(build_root, "app.exe.manifest"),
        new_name
      ])

    [elixir] = wildcard(rel, "**/elixir.bat")
    file_replace(elixir, "werl.exe", pkg.name <> ".exe")
    file_replace(elixir, "erl.exe", pkg.name <> ".exe")

    redistributables = %{
      "MicrosoftEdgeWebview2Setup.exe" => "https://go.microsoft.com/fwlink/p/?LinkId=2124703",
      "vcredist_x64.exe" => "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    }

    for {redist, url} <- redistributables do
      if not File.exists?(redist) do
        download_file(redist, url)
      end

      base_import!(rel, redist)
    end

    # Windows has wxwidgets & openssl statically linked
    # dll_import!(rel, "C:\\msys64\\mingw64\\bin\\libgmp-10.dll")

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
    strip_symbols(beam)
    File.rename!(beam, Path.join(Path.dirname(beam), name))

    libs = wildcard(rel, "**/*.dylib") ++ wildcard(rel, "**/*.so")
    for lib <- libs, do: strip_symbols(lib)
    for lib <- find_all_deps(os, libs), do: priv_import!(pkg, lib)

    if os == Linux and pkg.import_inofitywait do
      bin = System.find_executable("inotifywait")

      if bin == nil do
        Mix.Shell.IO.error(
          "import_inoftifywait: true was speccified but the `inotifywait` binary could not be found"
        )

        System.halt(1)
      end

      erts_bin_import!(rel, bin)

      for lib <- find_deps(os, bin) do
        priv_import!(pkg, lib)
      end
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
    base = Mix.Project.deps_paths()[:desktop_deployment]
    windows_tools = Path.absname("#{base}/rel/win32")

    signfun = win32_sign_function(pkg)

    if signfun == nil do
      Mix.Shell.IO.info("Not signing secret detected. Skipping signing")
    else
      win32_codesign(signfun, build_root)
    end

    {:ok, cur} = :file.get_cwd()
    :file.set_cwd(String.to_charlist(rel_path))
    content = eval_eex(Path.join(windows_tools, "app.nsi.eex"), rel, pkg)
    File.write!(Path.join(build_root, "app.nsi"), content)
    cmd!("makensis", ["-NOCD", "-DVERSION=#{vsn}", Path.join(build_root, "app.nsi")])
    :file.set_cwd(cur)

    if signfun != nil do
      outfile = "#{pkg.name}-#{vsn}-win32.exe"
      path = Path.join([build_root, outfile])
      signfun.(path)
    end

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
    File.chmod!(Path.join(bindir, "run"), 0o755)

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

      for size <- [16, 32, 128, 256, 512] do
        outfile = Path.join(iconset, "icon_#{size}x#{size}.png")
        cmd!("sips", ["-z", size, size, pkg.icon, "--out", outfile])
        outfile = Path.join(iconset, "icon_#{size}x#{size}@2.png")
        cmd!("sips", ["-z", 2 * size, 2 * size, pkg.icon, "--out", outfile])
      end

      outfile = Path.join(iconset, "icon_512x512@2x.png")
      cmd!("sips", ["-z", 1024, 1024, pkg.icon, "--out", outfile])
      cmd!("iconutil", ["-c", "icns", iconset, "-o", Path.join(mac_tools, "icons.icns")])
    end

    cp!(icon_path, resources)

    developer_id = Desktop.MacOS.find_developer_id()

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

    # Future: auto generate proper installer icon
    # https://0day.work/parsing-the-ds_store-file-format/
    # https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
    metadata = ["rel/macosx/DS_Store", "rel/macosx/VolumeIcon.icns"]

    for file <- metadata do
      if File.exists?(file) do
        basename = "." <> Path.basename(file)
        File.cp!(file, Path.join(volume, basename))
      end
    end

    # Creating final file
    cmd!("hdiutil", ["detach", volume])
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

  def win32_codesign(signfun, root) do
    exceptions = [
      "msvcr120.dll",
      "msvcp120.dll",
      "webview2loader.dll",
      "vcruntime140_clr0400.dll",
      "microsoftedgewebview2setup.exe",
      "vcredist_x64.exe"
    ]

    to_sign =
      (wildcard(root, "**/*.exe") ++ wildcard(root, "**/*.dll"))
      |> Enum.reject(fn filename -> String.downcase(Path.basename(filename)) in exceptions end)

    File.write!("codesign.log", Enum.join(to_sign, "\n"))

    for file <- to_sign do
      signfun.(file)
    end
  end

  def win32_sign_function(%Package{name: name, name_long: name_long}) do
    app_name = name_long || name
    cert_path = Path.absname(System.get_env("WIN32_CERTIFICATE_PATH", "rel/win32/app_cert.pem"))
    key_path = Path.absname(System.get_env("WIN32_KEY_PATH", "rel/win32/app_key.pem"))

    token = System.get_env("WIN32_SAFENET_TOKEN")
    pass = System.get_env("WIN32_KEY_PASS")

    signfun =
      cond do
        pass != nil -> &win32_certificate_sign(app_name, cert_path, key_path, pass, &1)
        token != nil -> &win32_keyfob_sign(app_name, cert_path, token, &1)
        true -> nil
      end

    if signfun != nil do
      fn filename ->
        IO.puts("Signing #{filename}")
        signfun.(filename)
        File.rename!("#{filename}.tmp", filename)
        # There is a funny comment about waiting between signing requests
        # on the official microsoft docs, so we're doing that here.
        Process.sleep(5_000)
      end
    end
  end

  def win32_certificate_sign(app_name, cert_path, key_path, pass, filename) do
    # app.pem from sectigo cert `openssl x509 -in app_cert.p12 -inform DER -out app_cert.pem`
    # app_key.pem from sectigo
    cmd!("osslsigncode", [
      "sign",
      "-certs",
      cert_path,
      "-key",
      key_path,
      "-pass",
      pass,
      "-n",
      app_name,
      "-t",
      "https://timestamp.sectigo.com",
      "-in",
      filename,
      "-out",
      "#{filename}.tmp"
    ])
  end

  def win32_keyfob_sign(app_name, cert_path, token, filename) do
    # pkcs11.so from  https://github.com/OpenSC/libp11.git @ b02940e7dcde8026a3e120fdf42921b06e8f9ee9
    # libeToken.so.10 from https://support.globalsign.com/ssl/ssl-certificates-installation/safenet-drivers
    # app.der from `pkcs11-tool --module /usr/lib/libeToken.so --id 0ff482e6569909c51ef69aabe88c659e89c32a27 --read-object --type cert --output-file app.der`
    # app.pem from `openssl x509 -in app.der -inform DER -out app.pem`
    cmd!(
      "osslsigncode",
      [
        "sign",
        "-verbose",
        "-pkcs11engine",
        "#{System.user_home!()}/projects/libp11/src/.libs/pkcs11.so",
        "-pkcs11module",
        "/usr/lib/libeToken.so.10",
        "-h",
        "sha256",
        "-n",
        app_name,
        "-t",
        "https://timestamp.sectigo.com",
        "-certs",
        cert_path,
        "-pass",
        token,
        "-in",
        filename,
        "-out",
        "#{filename}.tmp"
      ]
    )
  end
end
