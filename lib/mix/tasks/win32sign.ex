defmodule Mix.Tasks.Win32Sign do
  use Mix.Task
  import Desktop.Deployment.Tooling
  @moduledoc false

  @shortdoc "Repackages a windows zip and signs it."
  def run([zip_path], config \\ Mix.Project.config()) do
    app_name = config[:name]
    vsn = config[:version]

    zip_path = Path.expand(zip_path)
    IO.puts("Extracting #{zip_path}")

    nsi_path =
      Path.join(__DIR__, "../../../rel/win32/app.nsi")
      |> Path.expand()

    cert_path =
      Path.join(__DIR__, "../../../rel/win32/app.pem")
      |> Path.expand()

    dst =
      Path.join(__DIR__, "../../../_build/win32sign/rel/app")
      |> Path.expand()

    installer_path =
      Path.join(__DIR__, "../../../_build/win32sign/#{app_name}-#{vsn}-win32.exe")
      |> Path.expand()

    IO.puts("Using dst: #{dst}")
    File.mkdir_p(dst)
    cmd!("chmod", ["-R", "+xw", dst])
    File.rm_rf!(dst)
    File.mkdir!(dst)

    case System.cmd("unzip", [zip_path, "-d", dst]) do
      {_ret, 0} -> :ok
      {_ret, 1} -> :ok
    end

    cmd!("chmod", ["-R", "+xw", dst])

    :ok = :file.set_cwd(String.to_charlist(dst))

    exceptions = [
      "msvcr120.dll",
      "msvcp120.dll",
      "webview2loader.dll",
      "vcruntime140_clr0400.dll",
      "microsoftedgewebview2setup.exe",
      "vcredist_x64.exe"
    ]

    token =
      System.get_env("SAFENET_TOKEN") ||
        raise "Require pin in SAFENET_TOKEN environment variable!"

    sign = fn filename ->
      tmp = "#{filename}.out"

      # pkcs11.so from  https://github.com/OpenSC/libp11.git @ b02940e7dcde8026a3e120fdf42921b06e8f9ee9
      # libeToken.so.10 from https://support.globalsign.com/ssl/ssl-certificates-installation/safenet-drivers
      # app.der from `pkcs11-tool --module /usr/lib/libeToken.so --id 0ff482e6569909c51ef69aabe88c659e89c32a27 --read-object --type cert --output-file app.der`
      # app.pem from `openssl x509 -in app.der -inform DER -out app.pem`
      cmd!(
        "osslsigncode",
        ~w(sign -verbose -pkcs11engine /home/dominicletz/projects/libp11/src/.libs/pkcs11.so
        -pkcs11module /usr/lib/libeToken.so.10 -h sha256 -n #{app_name} -t https://timestamp.sectigo.com
        -certs #{cert_path} -pass #{token} -in #{filename} -out #{tmp})
      )

      IO.puts("Signing #{filename}")
      File.rename!(tmp, filename)
      # There is a funny comments about waiting between signing requests
      # on the official microsoft docs, so we're doing that here.
      Process.sleep(15_000)
    end

    cmd!("find", ~w(-iname *.exe -or -iname *.dll))
    |> String.split("\n")
    |> Enum.reject(fn filename ->
      String.downcase(Path.basename(filename)) in exceptions
    end)
    |> Enum.each(sign)

    cmd!("makensis", ["-NOCD", "-DVERSION=#{vsn}", nsi_path])
    sign.(installer_path)
  end
end
