defmodule Desktop.Deployment.LinuxRpathTest do
  use ExUnit.Case, async: false

  alias Desktop.Deployment.Package
  alias Desktop.Deployment.Package.Linux, as: LinuxPkg
  alias Desktop.Deployment.Tooling

  @erl_script """
  #!/bin/sh
  SELF=$(readlink "$0" || true)
  if [ -z "$SELF" ]; then SELF="$0"; fi
  BINDIR="$(cd "$(dirname "$SELF")" && pwd -P)"
  ROOTDIR="${ERL_ROOTDIR:-"$(dirname "$(dirname "$BINDIR")")"}"
  EMU=MyApp
  PROGNAME=$(echo "$0" | sed 's/.*\\///')
  export EMU
  export ROOTDIR
  export BINDIR
  export PROGNAME
  exec "$BINDIR/erlexec" ${1+"$@"}
  """

  test "rpath_for computes $ORIGIN-relative paths to priv across release directories" do
    root = "/tmp/rel"
    priv = Path.join(root, "lib/ddrive-1.22.18/priv")

    assert LinuxPkg.rpath_for(Path.join(priv, "libwebkit2gtk-4.0.so.37"), priv) == "$ORIGIN"

    assert LinuxPkg.rpath_for(Path.join(priv, "libwebkit2gtk/WebKitWebProcess"), priv) ==
             "$ORIGIN:$ORIGIN/.."

    assert LinuxPkg.rpath_for(
             Path.join(priv, "libwebkit2gtk/injected-bundle/libwebkit2gtkinjectedbundle.so"),
             priv
           ) == "$ORIGIN:$ORIGIN/../.."

    assert LinuxPkg.rpath_for(Path.join(priv, "gst/modules/libgstlibav.so"), priv) ==
             "$ORIGIN:$ORIGIN/../.."

    assert LinuxPkg.rpath_for(Path.join(root, "lib/wx-2.4.1/priv/wxe_driver.so"), priv) ==
             "$ORIGIN:$ORIGIN/../../ddrive-1.22.18/priv"

    assert LinuxPkg.rpath_for(Path.join(root, "lib/crypto-5.4.2.3/priv/lib/crypto.so"), priv) ==
             "$ORIGIN:$ORIGIN/../../../ddrive-1.22.18/priv"

    assert LinuxPkg.rpath_for(Path.join(root, "erts-14.2.5.10/bin/dDrive.smp"), priv) ==
             "$ORIGIN:$ORIGIN/../../lib/ddrive-1.22.18/priv"
  end

  test "dynamic_elf? distinguishes dynamic ELFs from static ELFs, objects, and scripts" do
    dir = tmp_dir("dynamic_elf")
    on_exit(fn -> File.rm_rf!(dir) end)

    elf64_le_dyn = Path.join(dir, "elf64_le_dyn")
    elf64_be_dyn = Path.join(dir, "elf64_be_dyn")
    elf32_le_dyn = Path.join(dir, "elf32_le_dyn")
    elf64_static = Path.join(dir, "elf64_static")
    elf64_rel = Path.join(dir, "elf64_rel.o")
    script = Path.join(dir, "script.sh")

    File.write!(elf64_le_dyn, fake_elf64(:little, 3, [1, 2]))
    File.write!(elf64_be_dyn, fake_elf64(:big, 2, [1, 2]))
    File.write!(elf32_le_dyn, fake_elf32(:little, 3, [1, 2]))
    File.write!(elf64_static, fake_elf64(:little, 2, [1, 1]))
    File.write!(elf64_rel, fake_elf64(:little, 1, [2]))
    File.write!(script, "#!/bin/sh\necho hi\n")

    assert LinuxPkg.dynamic_elf?(elf64_le_dyn)
    assert LinuxPkg.dynamic_elf?(elf64_be_dyn)
    assert LinuxPkg.dynamic_elf?(elf32_le_dyn)
    refute LinuxPkg.dynamic_elf?(elf64_static)
    refute LinuxPkg.dynamic_elf?(elf64_rel)
    refute LinuxPkg.dynamic_elf?(script)
    refute LinuxPkg.dynamic_elf?(Path.join(dir, "missing"))

    link = Path.join(dir, "symlink_to_dyn")
    File.ln_s!(elf64_le_dyn, link)

    assert LinuxPkg.find_dynamic_elfs(dir) ==
             Enum.sort([elf32_le_dyn, elf64_be_dyn, elf64_le_dyn])
  end

  test "dynamic_elf? classifies real gcc-compiled Linux ELF artifacts" do
    if Tooling.os() == Linux and System.find_executable("gcc") != nil do
      dir = tmp_dir("real_elf")
      on_exit(fn -> File.rm_rf!(dir) end)

      src = Path.join(dir, "sample.c")
      obj = Path.join(dir, "sample.o")
      so = Path.join(dir, "libsample.so")
      bin = Path.join(dir, "sample")

      File.write!(src, "int main(void) { return 0; }\n")

      {_, 0} = System.cmd("gcc", ["-c", "-fPIC", "-o", obj, src])
      {_, 0} = System.cmd("gcc", ["-shared", "-o", so, obj])
      {_, 0} = System.cmd("gcc", ["-o", bin, src])

      refute LinuxPkg.dynamic_elf?(obj)
      assert LinuxPkg.dynamic_elf?(so)
      assert LinuxPkg.dynamic_elf?(bin)
    end
  end

  test "patch_erl_file scopes LD_PRELOAD to erlexec and is idempotent" do
    dir = tmp_dir("patch_erl")
    on_exit(fn -> File.rm_rf!(dir) end)

    erl = Path.join(dir, "erl")
    erlexec = Path.join(dir, "erlexec")
    File.write!(erl, @erl_script)
    File.chmod!(erl, 0o555)

    LinuxPkg.patch_erl_file(erl)
    patched = File.read!(erl)
    assert patched =~ ~s(if [ -n "$DESKTOP_LD_PRELOAD" ]; then)
    assert patched =~ ~s(export LD_PRELOAD="$DESKTOP_LD_PRELOAD")

    # Idempotent when run a second time
    LinuxPkg.patch_erl_file(erl)
    assert File.read!(erl) == patched

    # Verify runtime behavior with a fake erlexec script
    File.write!(erlexec, "#!/bin/sh\nprintf 'PRELOAD=%s' \"$LD_PRELOAD\"\n")
    File.chmod!(erlexec, 0o755)

    {out, 0} =
      System.cmd(erl, [],
        env: [{"DESKTOP_LD_PRELOAD", "/opt/app/libredirector.so"}, {"LD_PRELOAD", nil}]
      )

    assert out == "PRELOAD=/opt/app/libredirector.so"

    {out_unset, 0} = System.cmd(erl, [], env: [{"DESKTOP_LD_PRELOAD", nil}, {"LD_PRELOAD", nil}])
    assert out_unset == "PRELOAD="
  end

  test "patch_erl_file raises when exec erlexec line is missing" do
    dir = tmp_dir("patch_erl_missing")
    on_exit(fn -> File.rm_rf!(dir) end)

    erl = Path.join(dir, "erl")
    File.write!(erl, "#!/bin/sh\necho unexpected\n")

    assert_raise RuntimeError, ~r/erlexec/, fn ->
      LinuxPkg.patch_erl_file(erl)
    end
  end

  test "patch_rpaths invokes patchelf with $ORIGIN paths and chmods read-only ELFs" do
    dir = tmp_dir("patch_rpaths")
    on_exit(fn -> File.rm_rf!(dir) end)

    rel_root = Path.join(dir, "rel")
    priv_dir = Path.join(rel_root, "lib/myapp-1.0.0/priv")
    erts_bin = Path.join(rel_root, "erts-14.2/bin")
    wx_priv = Path.join(rel_root, "lib/wx-2.4/priv")
    webkit_dir = Path.join(priv_dir, "libwebkit2gtk")

    for d <- [priv_dir, erts_bin, wx_priv, webkit_dir], do: File.mkdir_p!(d)

    lib_so = Path.join(priv_dir, "libfoo.so.1")
    beam = Path.join(erts_bin, "MyApp.smp")
    wx_nif = Path.join(wx_priv, "wxe_driver.so")
    webkit_proc = Path.join(webkit_dir, "WebKitWebProcess")
    static_bin = Path.join(erts_bin, "static_tool")
    shell_script = Path.join(erts_bin, "erl")

    for f <- [lib_so, beam, wx_nif, webkit_proc] do
      File.write!(f, fake_elf64(:little, 3, [1, 2]))
    end

    # Ensure read-only ELF is made writable before patchelf runs
    File.chmod!(wx_nif, 0o555)
    File.write!(static_bin, fake_elf64(:little, 2, [1]))
    File.write!(shell_script, @erl_script)

    fake_bin = Path.join(dir, "bin")
    File.mkdir_p!(fake_bin)
    log_file = Path.join(dir, "patchelf.log")
    fake_patchelf = Path.join(fake_bin, "patchelf")

    File.write!(fake_patchelf, """
    #!/bin/sh
    echo "$@" >> "#{log_file}"
    """)

    File.chmod!(fake_patchelf, 0o755)

    orig_path = System.get_env("PATH")

    try do
      System.put_env("PATH", "#{fake_bin}:#{orig_path}")
      LinuxPkg.patch_rpaths(rel_root, priv_dir)
    after
      System.put_env("PATH", orig_path)
    end

    calls =
      File.read!(log_file)
      |> String.split("\n", trim: true)
      |> MapSet.new()

    assert calls ==
             MapSet.new([
               "--set-rpath $ORIGIN #{lib_so}",
               "--set-rpath $ORIGIN:$ORIGIN/.. #{webkit_proc}",
               "--set-rpath $ORIGIN:$ORIGIN/../../myapp-1.0.0/priv #{wx_nif}",
               "--set-rpath $ORIGIN:$ORIGIN/../../lib/myapp-1.0.0/priv #{beam}"
             ])

    # Read-only ELF received owner write bit
    assert Bitwise.band(File.lstat!(wx_nif).mode, 0o200) == 0o200
  end

  test "run.eex on Linux does not export LD_LIBRARY_PATH or LD_PRELOAD directly" do
    if Tooling.os() == Linux do
      rel = %Mix.Release{name: :myapp, version: "1.2.3", path: "/tmp/myapp"}
      pkg = %Package{name: "MyApp", app_name: :myapp, release: rel}

      rendered = Tooling.eval_eex("rel/linux/run.eex", rel, pkg)

      assert rendered =~ "unset LD_LIBRARY_PATH LD_PRELOAD"
      refute rendered =~ "export LD_LIBRARY_PATH="
      refute rendered =~ "export LD_PRELOAD="

      assert rendered =~
               ~s(export DESKTOP_LD_PRELOAD="$RELEASE_ROOT/lib/myapp-1.2.3/priv/libredirector.so")

      # Unset must occur before `dirname $0` so inherited LD_* vars cannot break coreutils
      {unset_pos, _} = :binary.match(rendered, "unset LD_LIBRARY_PATH LD_PRELOAD")
      {dirname_pos, _} = :binary.match(rendered, "dirname $0")
      assert unset_pos < dirname_pos
    end
  end

  test "install.eex removes stale lib, erts, and versioned release before extracting" do
    if Tooling.os() == Linux do
      rel = %Mix.Release{name: :myapp, version: "1.2.3", path: "/tmp/myapp"}
      pkg = %Package{name: "MyApp", app_name: :myapp, release: rel}

      rendered = Tooling.eval_eex("rel/linux/install.eex", rel, pkg)

      cleanup_cmd =
        ~s(rm -rf "$INSTALL_DIR/lib" "$INSTALL_DIR"/erts-* "$INSTALL_DIR/releases/1.2.3")

      assert rendered =~ cleanup_cmd

      {cleanup_pos, _} = :binary.match(rendered, cleanup_cmd)
      {extract_pos, _} = :binary.match(rendered, "tar xf -")
      assert cleanup_pos < extract_pos

      install_dir = tmp_dir("install_clean")
      on_exit(fn -> File.rm_rf!(install_dir) end)

      stale_plugin =
        Path.join(install_dir, "lib/myapp-1.2.3/priv/gst/modules/libgstvideoscale.so")

      stale_erts = Path.join(install_dir, "erts-12.0/bin/beam.smp")
      stale_rel = Path.join(install_dir, "releases/1.2.3/start.boot")
      cookie = Path.join(install_dir, "releases/COOKIE")
      tmp_file = Path.join(install_dir, "tmp/keep")

      for file <- [stale_plugin, stale_erts, stale_rel, cookie, tmp_file] do
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, "data")
      end

      {_, 0} =
        System.cmd(
          "sh",
          ["-c", cleanup_cmd],
          env: [{"INSTALL_DIR", install_dir}]
        )

      refute File.exists?(stale_plugin)
      refute File.exists?(stale_erts)
      refute File.exists?(stale_rel)
      assert File.exists?(cookie)
      assert File.exists?(tmp_file)
    end
  end

  test "end-to-end patchelf resolves bundled transitive shared libraries without LD_LIBRARY_PATH" do
    if Tooling.os() == Linux and System.find_executable("patchelf") != nil and
         System.find_executable("gcc") != nil do
      dir = tmp_dir("e2e_rpath")
      on_exit(fn -> File.rm_rf!(dir) end)

      rel_root = Path.join(dir, "rel")
      priv_dir = Path.join(rel_root, "lib/myapp-1.0.0/priv")
      erts_bin = Path.join(rel_root, "erts-14.2/bin")
      src_dir = Path.join(dir, "src")

      for d <- [priv_dir, erts_bin, src_dir], do: File.mkdir_p!(d)

      File.write!(Path.join(src_dir, "leaf.c"), "int leaf_val(void) { return 40; }\n")

      File.write!(
        Path.join(src_dir, "mid.c"),
        "extern int leaf_val(void); int mid_val(void) { return leaf_val() + 2; }\n"
      )

      File.write!(
        Path.join(src_dir, "main.c"),
        "#include <stdio.h>\nextern int mid_val(void); int main(void) { printf(\"%d\", mid_val()); return 0; }\n"
      )

      leaf_so = Path.join(priv_dir, "libleaf_test.so.1")
      mid_so = Path.join(priv_dir, "libmid_test.so.1")
      main_bin = Path.join(erts_bin, "app_bin")

      {_, 0} =
        System.cmd("gcc", [
          "-shared",
          "-fPIC",
          "-Wl,-soname,libleaf_test.so.1",
          "-o",
          leaf_so,
          Path.join(src_dir, "leaf.c")
        ])

      {_, 0} =
        System.cmd("gcc", [
          "-shared",
          "-fPIC",
          "-Wl,-soname,libmid_test.so.1",
          "-o",
          mid_so,
          Path.join(src_dir, "mid.c"),
          leaf_so
        ])

      {_, 0} =
        System.cmd("gcc", [
          "-o",
          main_bin,
          Path.join(src_dir, "main.c"),
          mid_so
        ])

      LinuxPkg.patch_rpaths(rel_root, priv_dir)

      # Must execute and resolve both libmid_test.so.1 and transitive libleaf_test.so.1
      # with LD_LIBRARY_PATH unset.
      {output, 0} = System.cmd(main_bin, [], env: [{"LD_LIBRARY_PATH", nil}])
      assert output == "42"
    end
  end

  defp fake_elf64(endian, type, p_types) do
    phoff = 64
    phentsize = 56
    phnum = length(p_types)

    header =
      case endian do
        :little ->
          <<0x7F, "ELF", 2, 1, 1, 0::size(72), type::little-16, 62::little-16, 1::little-32,
            0::little-64, phoff::little-64, 0::little-64, 0::little-32, 64::little-16,
            phentsize::little-16, phnum::little-16, 0::little-16, 0::little-16, 0::little-16>>

        :big ->
          <<0x7F, "ELF", 2, 2, 1, 0::size(72), type::big-16, 62::big-16, 1::big-32, 0::big-64,
            phoff::big-64, 0::big-64, 0::big-32, 64::big-16, phentsize::big-16, phnum::big-16,
            0::big-16, 0::big-16, 0::big-16>>
      end

    phdrs =
      Enum.map_join(p_types, fn pt ->
        case endian do
          :little -> <<pt::little-32, 0::size(416)>>
          :big -> <<pt::big-32, 0::size(416)>>
        end
      end)

    header <> phdrs
  end

  defp fake_elf32(endian, type, p_types) do
    phoff = 52
    phentsize = 32
    phnum = length(p_types)

    header =
      case endian do
        :little ->
          <<0x7F, "ELF", 1, 1, 1, 0::size(72), type::little-16, 40::little-16, 1::little-32,
            0::little-32, phoff::little-32, 0::little-32, 0::little-32, 52::little-16,
            phentsize::little-16, phnum::little-16, 0::little-16, 0::little-16, 0::little-16>>

        :big ->
          <<0x7F, "ELF", 1, 2, 1, 0::size(72), type::big-16, 40::big-16, 1::big-32, 0::big-32,
            phoff::big-32, 0::big-32, 0::big-32, 52::big-16, phentsize::big-16, phnum::big-16,
            0::big-16, 0::big-16, 0::big-16>>
      end

    phdrs =
      Enum.map_join(p_types, fn pt ->
        case endian do
          :little -> <<pt::little-32, 0::size(224)>>
          :big -> <<pt::big-32, 0::size(224)>>
        end
      end)

    header <> phdrs
  end

  defp tmp_dir(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "desktop_deployment_test_#{name}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
