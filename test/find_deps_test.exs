defmodule FindDepsTest do
  use ExUnit.Case

  alias Desktop.Deployment.Package
  alias Desktop.Deployment.Tooling

  @moduletag :macos

  setup_all do
    unless match?({:unix, :darwin}, :os.type()) do
      # These tests exercise the macOS otool-based dependency walk.
      raise "find_deps macOS tests must run on macOS"
    end

    :ok
  end

  # Regression for the crash where a dependency install-name baked into a
  # precompiled NIF (e.g. exqlite's `/Users/runner/work/exqlite/...`) points at a
  # path that does not exist on the build machine. It matches the `/Users/` import
  # prefix, so the old code recursed into it and ran `otool -L` on the missing
  # file, which failed and raised a MatchError in `cmd!/2`.
  test "find_all_deps skips dependency paths that do not exist on this machine" do
    dir = tmp_dir("find_deps_missing")
    dep = Path.join(dir, "dep.c")
    main = Path.join(dir, "main.c")
    missing_install_name = "/Users/runner/work/exqlite/exqlite/priv/libfakedep.dylib"
    fake_dep = Path.join(dir, "libfakedep.dylib")
    lib = Path.join(dir, "libmain.dylib")

    File.write!(dep, "int dep_fn(void){return 42;}\n")
    File.write!(main, "extern int dep_fn(void); int main_fn(void){return dep_fn();}\n")

    # Build a dep dylib whose install-name is a path that will not exist at load
    # time, then link main against it so main records that missing path.
    {_, 0} =
      System.cmd("clang", [
        "-dynamiclib",
        "-install_name",
        missing_install_name,
        "-o",
        fake_dep,
        dep
      ])

    {_, 0} = System.cmd("clang", ["-dynamiclib", "-o", lib, main, fake_dep])
    File.rm!(fake_dep)

    # Sanity check: otool records the now-missing path.
    assert Package.MacOS.find_deps(lib) |> Enum.member?(missing_install_name)
    refute File.exists?(missing_install_name)

    # The walk must not crash and must not surface the missing path.
    deps = Tooling.find_all_deps(MacOS, [lib])
    refute Enum.member?(deps, missing_install_name)

    File.rm_rf!(dir)
  end

  test "find_deps returns [] for an object that does not exist" do
    assert Package.MacOS.find_deps("/does/not/exist/whatsoever.dylib") == []
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
