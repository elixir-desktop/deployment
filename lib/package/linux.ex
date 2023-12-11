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
    import_libgstreamer_modules(pkg, deps)
    import_libgio_modules(pkg, deps)
    import_inotifywait(pkg)

    # Import dependencies of these loaders and modules
    deps = find_all_deps(Linux, wildcard(rel, "**/*.so"))

    for lib <- deps do
      priv_import!(pkg, lib)
    end

    import_nss(pkg, deps)
    pkg
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
        if File.dir?(file) do
          File.mkdir_p!(Path.join([priv(pkg), "libwebkit2gtk", Path.basename(file)]))

          for subfile <- wildcard(file, "*"),
              do: priv_import!(pkg, subfile, extra_path: ["libwebkit2gtk/#{Path.basename(file)}"])
        else
          priv_import!(pkg, file, extra_path: ["libwebkit2gtk"])
        end
      end

      redirection =
        "#{Path.dirname(libwebkit)}/#{basename}/=$RELEASE_ROOT/#{Path.join(relative_priv(pkg), "libwebkit2gtk")}/"

      %Package{pkg | env: Map.put(pkg.env, "REDIRECTIONS", redirection)}
    else
      pkg
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
        :filelib.wildcard('#{Path.dirname(libgdk)}/gdk-pixbuf-*/gdk-pixbuf-query-loaders')

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
