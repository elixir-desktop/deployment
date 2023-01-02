defmodule Desktop.Deployment.Tooling do
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

  def priv_import!(pkg, src) do
    # Copying libraries to app_name-vsn/priv and adding that to (DY)LD_LIBRARY_PATH
    dst = Path.join(priv(pkg), Path.basename(src))
    if not File.exists?(dst), do: File.cp!(src, dst)
  end

  def dll_import!(%Mix.Release{} = rel, src) do
    # In windows the primary .exe directory is searched for missing dlls
    # (and there is no LD_LIBRARY_PATH)
    erst_bin_import!(rel, src)
  end

  def erst_bin_import!(%Mix.Release{path: path}, src) do
    erts = Application.app_dir(:erts) |> Path.basename()
    bindir = Path.join([path, erts, "bin"])
    dst = Path.join(bindir, Path.basename(src))
    if not File.exists?(dst), do: File.cp!(src, dst)
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
    IO.puts("Running: #{cmd} #{Enum.join(args, " ")}")
    {ret, 0} = System.cmd(cmd, args)
    String.trim_trailing(ret)
  end

  def linux_find_deps(object) do
    cmd!("ldd", [object])
    |> String.split("\n")
    |> Enum.map(fn row ->
      case String.split(row, " ") do
        [_, "=>", "not" | _] -> nil
        [_, "=>", path | _] -> path
        _other -> nil
      end
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.filter(fn lib ->
      name = hd(String.split(Path.basename(lib), "."))
      name not in linux_builtin()
    end)
  end

  @lsb_builtins [
    "libc",
    "libdbus-1",
    "libdl",
    "libexpat",
    "libffi",
    "libgcc_s",
    "libharfbuzz-icu",
    "libharfbuzz",
    "libICE",
    "libm",
    "libmount",
    "libpcre",
    "libpthread",
    "libresolv",
    "librt",
    "libselinux",
    "libstdc++",
    "libsystemd",
    "libudev",
    "libuuid",
    "libz"
  ]
  @xorg_builtins [
    "libatk-1",
    "libatk-bridge-2",
    "libatspi",
    "libblkid",
    "libbrotlicommon",
    "libbrotlidec",
    "libbsd",
    "libcairo-gobject",
    "libcairo",
    "libcom_err",
    "libdatrie",
    "libdrm",
    "libEGL",
    "libenchant",
    "libepoxy",
    "libfontconfig",
    "libfreetype",
    "libgbm",
    "libgcrypt",
    "libgdk_pixbuf-2",
    "libgdk-3",
    "libgio-2",
    "libGL",
    "libGLdispatch",
    "libglib-2",
    "libGLX",
    "libgmodule-2",
    "libgobject-2",
    "libgpg-error",
    "libgraphite2",
    "libgssapi_krb5",
    "libgstallocators-1",
    "libgstapp-1",
    "libgstaudio-1",
    "libgstbase-1",
    "libgstfft-1",
    "libgstgl-1",
    "libgstpbutils-1",
    "libgstreamer-1",
    "libgsttag-1",
    "libgstvideo-1",
    "libgtk-3",
    "libgudev-1",
    "libhyphen",
    "libicudata",
    "libicui18n",
    "libicuuc",
    "libjavascriptcoregtk-4",
    "libk5crypto",
    "libkeyutils",
    "libkrb5",
    "libkrb5support",
    "liblz4",
    "liblzma",
    "liborc-0",
    "libpango-1",
    "libpangocairo-1",
    "libpangoft2-1",
    "libpixman-1",
    "librotlidec",
    "libsecret-1",
    "libSM",
    "libsoup-2",
    "libtasn1",
    "libthai",
    "libwayland-client",
    "libwayland-cursor",
    "libwayland-egl",
    "libwayland-server",
    "libwebkit2gtk-4",
    "libwebp",
    "libwebpdemux",
    "libwoff2common",
    "libwoff2dec",
    "libX11-xcb",
    "libX11",
    "libXau",
    "libxcb-render",
    "libxcb-shm",
    "libxcb",
    "libXcomposite",
    "libXcursor",
    "libXdamage",
    "libXdmcp",
    "libXext",
    "libXfixes",
    "libXi",
    "libXinerama",
    "libxkbcommon",
    "libxml2",
    "libXrandr",
    "libXrender",
    "libxslt",
    "libXtst",
    "libXxf86vm"
    # "libsqlite3",
  ]
  def linux_builtin() do
    @lsb_builtins ++ @xorg_builtins
  end
end
