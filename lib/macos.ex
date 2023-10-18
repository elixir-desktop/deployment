defmodule Desktop.MacOS do
  alias Desktop.Deployment.Package
  import Desktop.Deployment.Tooling

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
        cmd!("security", ["import", file])
        uid = locate_uid(file)
        # Caching for next call
        if uid != nil do
          System.put_env("DEVELOPER_ID", uid)
        end

      true ->
        nil
    end
  end

  defmodule NtzCreds do
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
    |> IO.inspect()
  end

  defp scan({:AttributeTypeAndValue, @uid_attribute, uid}) do
    String.trim(uid)
  end

  defp scan([head | tail]), do: scan(head) || scan(tail)
  defp scan(tuple) when is_tuple(tuple), do: scan(Tuple.to_list(tuple))
  defp scan(_), do: nil

  # openssl genrsa -out mock.key 2048
  # openssl req -new -config ./Developer_ID_mock.conf -key mock.key -out mock.csr
  # openssl req -x509 -days 1825 -key mock.key -in mock.csr -out mock.crt -copy_extensions copy
  # cat mock.crt mock.key > mock.pem
  # openssl pkcs12 -inkey mock.key -in mock.crt -export -out mock.pfx
end
