defmodule Mix.Tasks.Desktop.Notarize do
  use Mix.Task
  @moduledoc false

  defmodule Credentials do
    defstruct apple_id: nil, password: nil, team_id: nil
  end

  @shortdoc "Notarizes a file on MacOS."
  def run(args) do
    case args do
      [apple_id, password, team_id, file] ->
        creds = %Credentials{apple_id: apple_id, password: password, team_id: team_id}
        do_notarize(creds, file)

      [apple_id, password, team_id, file, id] ->
        creds = %Credentials{apple_id: apple_id, password: password, team_id: team_id}
        File.exists?(file) || raise("File #{file} does not exist")
        await_notarization(creds, file, id)

      _ ->
        IO.puts("Usage: mix desktop.notarize <apple_id> <password> <team_id> (<file>|<id>)")
    end
  end

  @logfile "notarize.log"
  defp do_notarize(creds, file) do
    hash = :crypto.hash(:sha256, file) |> Base.encode16(case: :lower)

    {ret, status} =
      cmd("xcrun", [
        "notarytool",
        "submit",
        "--apple-id",
        creds.apple_id,
        "--password",
        creds.password,
        "--team-id",
        creds.team_id,
        file
      ])

    if status == 0 do
      [_, id] = Regex.run(~r/id: ([-0-9a-f]+)/s, ret)
      log("#{hash} uploaded id=#{id} file='#{file}'")
      await_notarization(creds, file, id)
    else
      log("#{hash} failed=#{status} file='#{file}'")
    end
  end

  defp await_notarization(creds, file, id) do
    {ret, status} =
      cmd("xcrun", [
        "notarytool",
        "info",
        "--apple-id",
        creds.apple_id,
        "--password",
        creds.password,
        "--team-id",
        creds.team_id,
        id
      ])

    if status != 0 do
      IO.puts("Notarization failed with status #{status}")
      System.halt(status)
    end

    [_, status] = Regex.run(~r/status: (.+)/s, ret)

    case String.trim(status) do
      "Accepted" ->
        log("#{id} status=accepted")
        {_ret, status} = cmd("xcrun", ["stapler", "staple", file])

        if status == 0 do
          log("#{id} status=stapled")
        else
          log("#{id} status=staple-failed")
        end

      "In Progress" ->
        log("#{id} status=in-progress")
        Process.sleep(10_000)
        await_notarization(creds, file, id)

      _ ->
        IO.puts("Notarization failed with status #{status}")
        System.halt(1)
    end
  end

  defp log(msg) do
    t = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    File.write!(@logfile, "#{t} #{msg}\n", [:append])
    IO.puts("LOG: #{msg}")
  end

  defp cmd(cmd, args) do
    IO.puts("CMD: #{cmd} #{Enum.join(Enum.take(args, 2), " ")}...")
    {out, status} = System.cmd(cmd, args, stderr_to_stdout: true)
    out = String.split(out, "\n") |> Enum.join("\n\t")
    IO.puts("\t#{out}")
    {out, status}
  end
end
