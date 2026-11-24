defmodule Desktop.Deployment.Package.Linux do
  @moduledoc """
  Linux specific deployment + packaging functions
  """
  import Desktop.Deployment.Tooling
  alias Desktop.Deployment.Package

  def import_extra_files(%Package{release: %Mix.Release{} = rel} = pkg) do
    import_libse_mock(pkg)
    import_redirector(pkg)

    # Importing dependend libraries
    libs = wildcard(rel, "**/*.so")
    for lib <- libs, do: strip_symbols(lib)
    deps = find_all_deps(Linux, libs)
    for lib <- deps, do: priv_import!(pkg, lib)

    import_pixbuf_loaders(pkg, deps)
    pkg = import_webkit(pkg, deps)
    maybe_import_webview(pkg)
    import_libgstreamer_modules(pkg, deps)
    import_immodules(pkg, deps)
    import_libgio_modules(pkg, deps)
    import_inotifywait(pkg)

    # Import dependencies of these loaders and modules
    deps = find_all_deps(Linux, wildcard(rel, "**/*.so"))

    for lib <- deps do
      priv_import!(pkg, lib)
    end

    import_nss(pkg, deps)
    patch_erl_script(rel)
    patch_rpaths(pkg)
    pkg
  end

  @doc false
  def patch_erl_script(%Mix.Release{} = rel) do
    [erl] = wildcard(rel, "**/bin/erl")
    patch_erl_file(erl)
  end

  @doc false
  def patch_erl_file(erl) do
    content = File.read!(erl)

    if not String.contains?(content, "DESKTOP_LD_PRELOAD") do
      target = ~s(exec "$BINDIR/erlexec" ${1+"$@"})

      if not String.contains?(content, target) do
        raise "Could not find #{inspect(target)} in #{erl}"
      end

      replacement =
        """
        if [ -n "$DESKTOP_LD_PRELOAD" ]; then
          export LD_PRELOAD="$DESKTOP_LD_PRELOAD"
        fi
        #{target}
        """
        |> String.trim_trailing()

      file_replace(erl, target, replacement)
    end
  end

  @doc false
  def patch_rpaths(%Package{release: %Mix.Release{path: rel_path}} = pkg) do
    patch_rpaths(rel_path, priv(pkg))
  end

  @doc false
  def patch_rpaths(rel_path, priv_dir) do
    patchelf = ensure_patchelf!()
    priv_dir = Path.expand(priv_dir)

    rel_path
    |> find_dynamic_elfs()
    |> Enum.each(fn file ->
      rpath = rpath_for(file, priv_dir)
      File.chmod!(file, Bitwise.bor(File.lstat!(file).mode, 0o200))
      cmd!(patchelf, ["--set-rpath", rpath, file])
    end)
  end

  @doc false
  def rpath_for(file, priv_dir) do
    from_parts = file |> Path.dirname() |> Path.expand() |> Path.split()
    to_parts = priv_dir |> Path.expand() |> Path.split()
    {from_rest, to_rest} = drop_common_prefix(from_parts, to_parts)

    case List.duplicate("..", length(from_rest)) ++ to_rest do
      [] -> "$ORIGIN"
      rel_parts -> "$ORIGIN:$ORIGIN/#{Path.join(rel_parts)}"
    end
  end

  @doc false
  def find_dynamic_elfs(root) do
    root
    |> walk_regular_files()
    |> Enum.filter(&dynamic_elf?/1)
    |> Enum.sort()
  end

  @doc false
  def dynamic_elf?(path) do
    case File.open(path, [:read, :binary], &has_dynamic_segment?/1) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end

  defp ensure_patchelf! do
    System.find_executable("patchelf") ||
      raise "patchelf is required for Linux packaging (install it e.g. via `apt-get install patchelf`)"
  end

  defp drop_common_prefix([head | from_tail], [head | to_tail]),
    do: drop_common_prefix(from_tail, to_tail)

  defp drop_common_prefix(from_rest, to_rest), do: {from_rest, to_rest}

  defp walk_regular_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, &walk_entry(Path.join(dir, &1)))

      {:error, _} ->
        []
    end
  end

  defp walk_entry(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> walk_regular_files(path)
      {:ok, %File.Stat{type: :regular}} -> [path]
      _ -> []
    end
  end

  defp has_dynamic_segment?(io) do
    with {:ok, header} <- :file.pread(io, 0, 64),
         {:ok, endian, phoff, phentsize, phnum} <- parse_elf_header(header),
         {:ok, table} <- :file.pread(io, phoff, phentsize * phnum) do
      contains_pt_dynamic?(table, endian, phentsize, phnum)
    else
      _ -> false
    end
  end

  # ET_EXEC (2) or ET_DYN (3) ELF headers for 64-bit / 32-bit, little / big endian
  defp parse_elf_header(
         <<0x7F, "ELF", 2, 1, _::binary-size(10), type::little-16, _::binary-size(14),
           phoff::little-64, _::binary-size(14), phentsize::little-16, phnum::little-16,
           _::binary>>
       )
       when type in [2, 3] and phoff > 0 and phentsize >= 56 and phnum > 0 do
    {:ok, :little, phoff, phentsize, phnum}
  end

  defp parse_elf_header(
         <<0x7F, "ELF", 2, 2, _::binary-size(10), type::big-16, _::binary-size(14), phoff::big-64,
           _::binary-size(14), phentsize::big-16, phnum::big-16, _::binary>>
       )
       when type in [2, 3] and phoff > 0 and phentsize >= 56 and phnum > 0 do
    {:ok, :big, phoff, phentsize, phnum}
  end

  defp parse_elf_header(
         <<0x7F, "ELF", 1, 1, _::binary-size(10), type::little-16, _::binary-size(10),
           phoff::little-32, _::binary-size(10), phentsize::little-16, phnum::little-16,
           _::binary>>
       )
       when type in [2, 3] and phoff > 0 and phentsize >= 32 and phnum > 0 do
    {:ok, :little, phoff, phentsize, phnum}
  end

  defp parse_elf_header(
         <<0x7F, "ELF", 1, 2, _::binary-size(10), type::big-16, _::binary-size(10), phoff::big-32,
           _::binary-size(10), phentsize::big-16, phnum::big-16, _::binary>>
       )
       when type in [2, 3] and phoff > 0 and phentsize >= 32 and phnum > 0 do
    {:ok, :big, phoff, phentsize, phnum}
  end

  defp parse_elf_header(_), do: :error

  defp contains_pt_dynamic?(_table, _endian, _phentsize, 0), do: false

  defp contains_pt_dynamic?(table, endian, phentsize, count)
       when byte_size(table) >= phentsize do
    <<entry::binary-size(phentsize), rest::binary>> = table

    p_type =
      case {endian, entry} do
        {:little, <<t::little-32, _::binary>>} -> t
        {:big, <<t::big-32, _::binary>>} -> t
      end

    if p_type == 2 do
      true
    else
      contains_pt_dynamic?(rest, endian, phentsize, count - 1)
    end
  end

  defp contains_pt_dynamic?(_, _, _, _), do: false

  defp maybe_import_webview(%Package{} = pkg) do
    webview =
      priv(pkg)
      |> :filelib.fold_files(~c"^webview$", true, fn elem, acc -> [elem | acc] end, [])
      |> List.first()

    if webview != nil do
      [executable] = wildcard(pkg.release, "**/#{pkg.priv.executable_name}")
      base = Path.basename(executable) |> Path.rootname()
      ext = Path.extname(executable)
      helper = Path.join(Path.dirname(executable), "#{base}_cef_helper#{ext}")
      File.rename!(webview, helper)
    end
  end

  defp import_inotifywait(%Package{release: rel} = pkg) do
    if pkg.import_inofitywait do
      bin = System.find_executable("inotifywait")

      if bin == nil do
        Mix.Shell.IO.error(
          "import_inoftifywait: true was speccified but the `inotifywait` binary could not be found"
        )

        System.halt(1)
      end

      erts_bin_import!(rel, bin)

      for lib <- find_deps(os(), bin) do
        priv_import!(pkg, lib)
      end
    end
  end

  defp import_webkit(%Package{} = pkg, deps) do
    libwebkit =
      Enum.find(deps, fn lib -> String.starts_with?(Path.basename(lib), "libwebkit2gtk") end)

    if libwebkit != nil do
      File.mkdir_p!(Path.join(priv(pkg), "libwebkit2gtk"))
      # Turns /la/la/lulu/libwebkit2gtk-4.0.so.37 into "webkit2gtk-4.0"
      [_, basename] = Regex.run(~r"/lib([^/]+)\.so", libwebkit)
      files = wildcard(Path.dirname(libwebkit), "#{basename}/*")

      for file <- files do
        import_webkit_entry(pkg, file)
      end

      redirection =
        "#{Path.dirname(libwebkit)}/#{basename}/=$RELEASE_ROOT/#{Path.join(relative_priv(pkg), "libwebkit2gtk")}/"

      %Package{pkg | env: Map.put(pkg.env, "REDIRECTIONS", redirection)}
    else
      pkg
    end
  end

  defp import_webkit_entry(%Package{} = pkg, file) do
    if File.dir?(file) do
      File.mkdir_p!(Path.join([priv(pkg), "libwebkit2gtk", Path.basename(file)]))

      for subfile <- wildcard(file, "*"),
          do: priv_import!(pkg, subfile, extra_path: ["libwebkit2gtk/#{Path.basename(file)}"])
    else
      priv_import!(pkg, file, extra_path: ["libwebkit2gtk"])
    end
  end

  defp import_libgstreamer_modules(%Package{} = pkg, deps) do
    libgst =
      Enum.find(deps, fn lib -> String.starts_with?(Path.basename(lib), "libgstreamer") end)

    if libgst != nil do
      File.mkdir_p!(Path.join(priv(pkg), "gst/modules"))
      files = wildcard(Path.dirname(libgst), "gstreamer-1.0/*.so")
      for file <- files, do: priv_import!(pkg, file, extra_path: ["gst/modules"])
    end
  end

  defp import_immodules(%Package{} = pkg, deps) do
    libgtk = Enum.find(deps, fn lib -> String.starts_with?(Path.basename(lib), "libgtk-3") end)

    if libgtk != nil do
      [loader | _] =
        :filelib.wildcard(~c"#{Path.dirname(libgtk)}/libgtk-3-*/gtk-query-immodules-*")

      {loaders, 0} = System.cmd("#{loader}", [])

      libs =
        Regex.scan(~r/[^"]+\.so/, loaders)
        |> List.flatten()

      File.mkdir_p!(Path.join(priv(pkg), "immodules"))
      for lib <- libs, do: priv_import!(pkg, lib, extra_path: ["immodules"])

      loaders =
        Enum.reduce(libs, loaders, fn lib, loaders ->
          String.replace(
            loaders,
            lib,
            Path.join([relative_priv(pkg), "immodules", Path.basename(lib)])
          )
        end)

      File.write!(Path.join(priv(pkg), "immodules.cache"), loaders)
    end
  end

  defp import_nss(%Package{} = pkg, deps) do
    libnss = Enum.find(deps, fn lib -> String.starts_with?(Path.basename(lib), "libnss3") end)

    if libnss != nil do
      File.mkdir_p!(Path.join(priv(pkg), "nss"))
      files = wildcard(Path.dirname(libnss), "nss/*.so")
      for file <- files, do: priv_import!(pkg, file, extra_path: ["nss"])
    end
  end

  defp import_libgio_modules(%Package{} = pkg, deps) do
    libgio = Enum.find(deps, fn lib -> String.starts_with?(Path.basename(lib), "libgio") end)

    if libgio != nil do
      File.mkdir_p!(Path.join(priv(pkg), "gio/modules"))
      files = wildcard(Path.dirname(libgio), "gio/modules/*")
      for file <- files, do: priv_import!(pkg, file, extra_path: ["gio/modules"])
    end
  end

  defp import_pixbuf_loaders(%Package{} = pkg, deps) do
    # libgdk = "/usr/lib/x86_64-linux-gnu/libgdk_pixbuf-2.0.so.0.4200.8"
    libgdk =
      Enum.find(deps, fn lib -> String.starts_with?(Path.basename(lib), "libgdk_pixbuf") end)

    if libgdk != nil do
      [loader | _] =
        :filelib.wildcard(~c"#{Path.dirname(libgdk)}/gdk-pixbuf-*/gdk-pixbuf-query-loaders")

      {loaders, 0} = System.cmd("#{loader}", [])

      libs =
        String.split(loaders, "\n")
        |> Enum.map(fn str -> String.trim(str, "\"") end)
        |> Enum.filter(fn str -> String.ends_with?(str, ".so") end)

      File.mkdir_p!(Path.join(priv(pkg), "pixbuf"))
      for lib <- libs, do: priv_import!(pkg, lib, extra_path: ["pixbuf"])

      loaders =
        Enum.reduce(libs, loaders, fn lib, loaders ->
          String.replace(
            loaders,
            lib,
            Path.join([relative_priv(pkg), "pixbuf", Path.basename(lib)])
          )
        end)

      File.write!(Path.join(priv(pkg), "pixbuf.cache"), loaders)
    end
  end

  defp import_libse_mock(%Package{release: %Mix.Release{path: rel_path}} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()

    libselinux_dummy =
      Path.join(Mix.Project.deps_paths()[:desktop_deployment], "priv/libselinux-dummy")

    for lib <- ["selinux", "semanage", "sepol"] do
      soname = "lib#{lib}.so.1"

      if not File.exists?(Path.join(build_root, soname)) do
        cmd!("gcc", [
          "-Os",
          "-s",
          "-shared",
          "-o",
          Path.join(build_root, soname),
          "-Wl,-soname,#{soname}",
          "-Wl,--version-script,#{libselinux_dummy}/src/lib/lib#{lib}.map",
          "-I#{libselinux_dummy}/src/lib/",
          "#{libselinux_dummy}/src/dummy/dummy.c"
          | wildcard("#{libselinux_dummy}/src/lib/#{lib}/", "*.c")
        ])
      end

      priv_import!(pkg, Path.join(build_root, soname))
    end
  end

  defp import_redirector(%Package{release: %Mix.Release{path: rel_path}} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    redirector = Path.join(Mix.Project.deps_paths()[:desktop_deployment], "priv/redirector")
    soname = "libredirector.so"

    if not File.exists?(Path.join(build_root, soname)) do
      glib = cmd!("pkg-config", ["--cflags", "glib-2.0"]) |> String.split()

      cmd!("gcc", [
        "-D_GNU_SOURCE",
        "-O",
        "-Wall",
        "-fPIC",
        "-shared",
        "-o",
        Path.join(build_root, soname),
        "#{redirector}/redirector.c",
        "-ldl" | glib
      ])
    end

    priv_import!(pkg, Path.join(build_root, soname))
  end
end
