defmodule Desktop.Deployment.Package.MacOS do
  @moduledoc """
  macOS specific deployment functions.
  """
  import Desktop.Deployment.Tooling
  alias Desktop.Deployment.Package

  def import_extra_files(%Package{release: %Mix.Release{} = rel} = pkg) do
    # Importing dependend libraries
    libs = wildcard(rel, "**/*.dylib") ++ wildcard(rel, "**/*.so")
    for lib <- libs, do: strip_symbols(lib)
    deps = find_all_deps(MacOS, libs)
    for lib <- deps, do: priv_import!(pkg, lib)

    pkg
  end

  def release(%Package{release: %Mix.Release{path: path} = rel} = pkg) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    linux_tools = Path.absname("#{base}/rel/linux")
    mac_tools = Path.absname("#{base}/rel/macosx")

    build_root = Path.join([path, "..", ".."]) |> Path.expand()
    root = Path.join(build_root, "#{pkg.name}.app")
    # Remove crust
    File.rm_rf(root)
    contents = Path.join(root, "Contents")
    bindir = Path.join(contents, "MacOS")
    resources = Path.join(contents, "Resources")

    File.mkdir_p!(bindir)

    content = eval_eex(Path.join(mac_tools, "InfoPlist.strings.eex"), rel, pkg)
    utf8bom = <<0xEF, 0xBB, 0xBF>>

    for lang <- ["en", "Base"] do
      langdir = Path.join(resources, "#{lang}.lproj")
      File.mkdir_p!(langdir)
      File.write!(Path.join(langdir, "InfoPlist.strings"), utf8bom <> content)
    end

    content = eval_eex(Path.join(mac_tools, "Info.plist.eex"), rel, pkg)
    File.write!(Path.join(contents, "Info.plist"), content)
    File.write!(Path.join(contents, "PkgInfo"), "APPL????")
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
    maybe_import_webview(pkg, contents)

    for bin <- find_binaries(root) do
      rewrite_deps(bin, fn dep ->
        if should_rewrite?(bin, dep) do
          rewrite_to_approot(pkg, bin, dep, root)
        end
      end)
    end

    developer_id = Package.MacOS.find_developer_id()

    if developer_id != nil do
      codesign(developer_id, root)
    end

    dmg = make_dmg(pkg)

    if developer_id != nil do
      package_sign(developer_id, dmg)
    end

    :ok
  end

  def package_sign(developer_id, dmg) do
    System.cmd(
      "codesign",
      [
        "-s",
        developer_id,
        "--timestamp",
        dmg
      ]
    )
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

  defp maybe_import_webview(%Package{} = pkg, contents) do
    webview =
      :filelib.fold_files(contents, '^webview$', true, fn elem, acc -> [elem | acc] end, [])
      |> List.first()

    if webview != nil do
      import_webview(pkg, webview, contents)
    end
  end

  defp import_webview(%Package{} = pkg, webview, contents) do
    frameworks = Path.join(contents, "Frameworks")
    File.mkdir_p!(frameworks)
    cef = Path.join(Path.dirname(webview), "Chromium Embedded Framework.framework")
    File.rename!(cef, Path.join(frameworks, "Chromium Embedded Framework.framework"))

    # Collecting plist content
    base = Mix.Project.deps_paths()[:desktop_deployment]
    mac_tools = Path.absname("#{base}/rel/macosx")
    filename = Path.join(mac_tools, "Info.plist.helper.eex")
    app_name = pkg.priv.executable_name
    helper_name = "#{app_name} Helper"
    executable_name = "#{app_name} Helper"
    version = pkg.release.version

    helper_contents = Path.join([frameworks, "#{helper_name}.app", "Contents"])
    File.mkdir_p!(Path.join(helper_contents, "MacOS"))
    File.mkdir_p!(Path.join(helper_contents, "Resources"))

    plist =
      EEx.eval_file(filename,
        assigns: [
          name: helper_name,
          display_name: helper_name,
          executable: executable_name,
          identifier: pkg.identifier <> ".helper",
          version: version,
          short_version_string: version
        ]
      )

    File.write!(Path.join(helper_contents, "Info.plist"), plist)
    File.write!(Path.join(helper_contents, "PkgInfo"), "APPL????")

    rewrite_deps(webview, fn dep ->
      if Regex.match?(~r/Chromium ?Embedded ?Framework/, dep) do
        "@executable_path/../../../../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
      end
    end)

    File.rename!(webview, Path.join(helper_contents, "MacOS/#{executable_name}"))

    icon_path = Path.join(mac_tools, "icons.icns")
    File.cp!(icon_path, Path.join(helper_contents, "Resources/icons.icns"))

    for name <- ~w(Alerts GPU Plugin Renderer) do
      sub_helper_name = "#{app_name} Helper (#{name})"

      # File.ln_s!(
      #   "./#{helper_name}.app",
      #   Path.join(frameworks, "#{sub_helper_name}.app")
      # )

      sub_helper_contents = Path.join(frameworks, "#{sub_helper_name}.app/Contents")
      File.mkdir_p!(Path.join(sub_helper_contents, "MacOS"))
      # Conserving disk space
      File.ln_s!(
        "../../../#{helper_name}.app/Contents/MacOS/#{executable_name}",
        Path.join(sub_helper_contents, "MacOS/#{sub_helper_name}")
      )

      plist =
        EEx.eval_file(filename,
          assigns: [
            name: sub_helper_name,
            display_name: sub_helper_name,
            executable: sub_helper_name,
            identifier: pkg.identifier <> ".helper",
            version: version,
            short_version_string: version
          ]
        )

      File.write!(Path.join(sub_helper_contents, "Info.plist"), plist)
      File.write!(Path.join(sub_helper_contents, "PkgInfo"), "APPL????")
    end

    pkg
  end

  def find_deps(object) do
    # otool -L can't handle filenames such as "webview (Alerts)"
    if String.ends_with?(object, ")") do
      []
    else
      cmd!("otool", ["-L", object])
      |> String.split("\n")
      |> tl()
      |> Enum.map(fn row ->
        # There can be spaces in lib names so splitting on space is not good enough
        case String.split(row, "(compatibility") do
          [path | _] -> String.trim(path) |> String.trim(":")
          _other -> nil
        end
      end)
      |> Enum.filter(&is_binary/1)
    end
  end

  defp should_rewrite?(bin, dep) do
    String.starts_with?(dep, "/usr/local/opt/") or String.starts_with?(dep, "/Users/") or
      (String.starts_with?(dep, "@executable_path") and
         not File.exists?(
           Path.join(
             Path.dirname(bin),
             String.replace_leading(dep, "@executable_path", "")
           )
         ))
  end

  defp rewrite_to_approot(pkg, bin, dep, root) do
    location =
      if String.contains?(dep, ".framework/") do
        framework = Regex.replace(~r"^.+/([^/]+\.framework)", dep, fn _, match -> match end)
        Path.join("Contents/Frameworks", framework)
      else
        Path.join(["Contents/Resources", relative_priv(pkg), Path.basename(dep)])
      end

    depth =
      Path.relative_to(Path.dirname(bin), root)
      |> Path.split()
      |> Enum.count()

    escape = List.duplicate("..", depth) |> Path.join()

    Path.join([
      "@loader_path",
      escape,
      location
    ])
  end

  def rewrite_dep(object, old_name, new_name) do
    cmd!("install_name_tool", ["-change", old_name, new_name, object])
  end

  def rewrite_deps(object, fun) do
    find_deps(object)
    |> Enum.map(fn old_name ->
      with new_name when is_binary(new_name) <- fun.(old_name) do
        rewrite_dep(object, old_name, new_name)
        old_name
      end
    end)
    |> Enum.filter(&is_binary/1)
  end

  @uid_attribute {0, 9, 2342, 19_200_300, 100, 1, 1}
  def locate_uid(pem_filename) do
    cert = File.read!(pem_filename)
    cert_der = List.keyfind!(:public_key.pem_decode(cert), :Certificate, 0)

    :public_key.der_decode(:Certificate, elem(cert_der, 1))
    |> scan()
  end

  def find_developer_id() do
    cond do
      System.get_env("DEVELOPER_ID") != nil ->
        System.get_env("DEVELOPER_ID")

      System.get_env("MACOS_DEVELOPER_ID") != nil ->
        System.get_env("MACOS_DEVELOPER_ID")

      System.get_env("MACOS_PEM") != nil ->
        file = "tmp.pem"
        File.write!(file, System.get_env("MACOS_PEM"))
        uid = locate_uid(file) || raise "Could not parse PEM"
        maybe_import_pem(file, uid)

        # Caching for next call
        if uid != nil do
          System.put_env("DEVELOPER_ID", uid)
          uid
        end

      true ->
        nil
    end
  end

  defp maybe_import_pem(file, uid) do
    if not String.contains?(find_identity(), uid) do
      cmd("security", ["import", file, "-k", keychain()])

      if not String.contains?(find_identity(), uid) do
        raise "Failed to import PEM for uid #{uid}"
      end
    end
  end

  defp find_identity() do
    cmd("security", ["find-identity", "-v", keychain()])
  end

  @keychain_key {__MODULE__, :keychain}
  defp keychain() do
    keychain = :persistent_term.get(@keychain_key, nil)

    if keychain != nil do
      keychain
    else
      keychain =
        case System.get_env("MACOS_KEYCHAIN") do
          nil -> cmd("security", ["login-keychain"]) |> String.trim() |> String.trim("\"")
          keychain -> keychain
        end

      case cmd_raw("security", ["show-keychain-info", keychain]) do
        {_, 36} ->
          raise "Keychain #{keychain} is not unlocked run `security unlock-keychain #{keychain}` to unlock it and try again"

        {_, 0} ->
          :ok

        {ret, status} ->
          raise "Unknown error (#{status}) '#{ret}' when accessing keychain #{keychain}"
      end

      :persistent_term.put(@keychain_key, keychain)
      keychain
    end
  end

  defmodule NtzCreds do
    @moduledoc false
    defstruct [:username, :password, :team_uid]
  end

  def notarize(file) do
    notarize(Desktop.Deployment.package(), default_creds(), file)
  end

  def default_creds() do
    %NtzCreds{
      username: System.get_env("MACOS_NOTARIZATION_USER"),
      password: System.get_env("MACOS_NOTARIZATION_PASSWORD"),
      team_uid: find_developer_id()
    }
  end

  def notarize(
        %Package{identifier: identifier},
        %NtzCreds{username: username, password: password, team_uid: team_uid},
        file
      )
      when is_binary(username) and is_binary(password) and is_binary(team_uid) do
    cmd!("xcrun", [
      "altool",
      "--notarize-app",
      "--primary-bundle-id",
      identifier <> ".dmg",
      "--username",
      username,
      "--password",
      password,
      "--team",
      team_uid,
      "--file",
      file
    ])
  end

  defp scan({:AttributeTypeAndValue, @uid_attribute, uid}) do
    String.trim(uid)
  end

  defp scan([head | tail]), do: scan(head) || scan(tail)
  defp scan(tuple) when is_tuple(tuple), do: scan(Tuple.to_list(tuple))
  defp scan(_), do: nil

  def find_binaries(root) do
    libs = wildcard(root, "**/*.so") ++ wildcard(root, "**/*.dylib") ++ wildcard(root, "**/*.smp")

    bins =
      wildcard(root, "**")
      |> Enum.reject(fn file -> String.contains?(Path.basename(file), ".") end)
      |> Enum.filter(fn file -> Bitwise.band(0o100, File.lstat!(file).mode) != 0 end)

    frameworks = wildcard(root, "**/Contents/MacOS/*")

    (bins ++ libs)
    |> Enum.filter(fn file -> File.lstat!(file).type == :regular end)
    |> Enum.concat(frameworks)
    |> Enum.uniq()
  end

  def codesign(developer_id, root) do
    # Codesign all executable code in the package with timestamp and
    # hardened runtime. This is a prerequisite for notarization.
    to_sign = find_binaries(root)

    base = Mix.Project.deps_paths()[:desktop_deployment]
    mac_tools = Path.absname("#{base}/rel/macosx")
    entitlements = Path.join(mac_tools, "app.entitlements")

    File.write!("codesign.log", Enum.join(to_sign, "\n"))

    # If there are any Frameworks embedded we have to sign them first
    # otherwise codesign will give up with an error like: `MacOS/run: code object is not signed at all\nIn subcomponent .../Framework`
    {frameworks, rest} =
      Enum.split_with(to_sign, fn path -> String.contains?(path, "/Frameworks/") end)

    to_sign = frameworks ++ rest

    # Signing binaries in app directory
    Enum.chunk_every(to_sign, 10)
    |> Enum.each(fn chunk ->
      IO.puts("Signing #{inspect(chunk)}")

      cmd!(
        "codesign",
        [
          "--keychain",
          keychain(),
          "-f",
          "-s",
          developer_id,
          "--timestamp",
          "--options=runtime",
          "--entitlements",
          entitlements | chunk
        ]
      )
    end)

    # Signing app directory itself
    cmd!(
      "codesign",
      [
        "--keychain",
        keychain(),
        "-f",
        "-s",
        developer_id,
        "--timestamp",
        "--options=runtime",
        "--entitlements",
        entitlements,
        root
      ]
    )
  end

  # openssl genrsa -out mock.key 2048
  # openssl req -new -config ./Developer_ID_mock.conf -key mock.key -out mock.csr
  # openssl req -x509 -days 1825 -key mock.key -in mock.csr -out mock.crt -copy_extensions copy
  # cat mock.crt mock.key > mock.pem
  # openssl pkcs12 -inkey mock.key -in mock.crt -export -out mock.pfx
end
