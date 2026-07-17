defmodule LocateUidTest do
  use ExUnit.Case

  alias Desktop.Deployment.Package.MacOS

  # Regression for:
  #   UndefinedFunctionError: function :public_key.pem_decode/1 is undefined
  #   (module :public_key is not available)
  #
  # That failure happened in Mix task context when only Application.ensure_all_started/1
  # was used (and its error ignored). locate_uid/1 must load :public_key via
  # Mix.ensure_application!/1 and then start it before calling pem_decode/1.
  test "locate_uid/1 can decode a PEM after ensuring :public_key is available" do
    dir = System.tmp_dir!()
    key = Path.join(dir, "desktop-deployment-test-key.pem")
    cert = Path.join(dir, "desktop-deployment-test-cert.pem")

    try do
      {_, 0} =
        System.cmd("openssl", [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-keyout",
          key,
          "-out",
          cert,
          "-days",
          "1",
          "-nodes",
          "-subj",
          "/CN=Desktop Deployment Test (TESTUID)"
        ])

      # Force ensure_public_key!/0 to re-start :public_key the way a Mix task would
      # after the app is not already up.
      _ = Application.stop(:public_key)

      # Must not raise UndefinedFunctionError for :public_key.pem_decode/1
      uids = MacOS.locate_uid(cert)
      assert is_list(uids)
      assert "TESTUID" in uids
    after
      File.rm(key)
      File.rm(cert)
    end
  end
end
