defmodule Desktop.Installer.Cache do
  import Desktop.Deployment.Tooling
  @moduledoc false

  def cache_dir() do
    Path.join([System.user_home!(), ".elixir-desktop", "cache"])
  end

  def fetch(filename, url) do
    fullname = Path.join(cache_dir(), filename)

    if File.exists?(fullname) do
      :ok
    else
      File.mkdir_p!(cache_dir())
      cmd!("wget", [url, "-O", fullname])
    end

    fullname
  end
end
