defmodule O do
  @moduledoc "Very basic OCI client used to create instances"
  @app :o

  def finch, do: __MODULE__.Finch
  def config(key), do: Application.fetch_env!(@app, key)

  # https://docs.oracle.com/en-us/iaas/api/#/en/iaas/20160918/Instance/ListInstances
  def list_instances(query \\ %{}) do
    query = Map.put_new(query, "compartmentId", config(:tenancy))
    get("iaas", "/20160918/instances", query)
  end

  def availability_domain do
  end

  def oracle_amd_image do
  end

  def oracle_arm_image do
  end

  # https://docs.oracle.com/en-us/iaas/api/#/en/iaas/20160918/Instance/LaunchInstance
  def create_instance(body \\ %{}) do
    body = Map.merge(default_instance_config(), body)
    post("iaas", "/20160918/instances", body)
  end

  def default_instance_config do
    %{
      "metadata" => %{"ssh_authorized_keys" => config(:public_key)},
      "compartmentId" => config(:tenancy),
      "displayName" => "instance-#{Date.utc_today()}",
      "availabilityDomain" => availability_domain(),
      "createVnicDetails" => %{
        "assignPublicIp" => true,
        "subnetId" => config(:subnet_id),
        "assignPrivateDnsRecord" => true
      },
      "availabilityConfig" => %{
        "recoveryAction" => "RESTORE_INSTANCE"
      },
      "instanceOptions" => %{
        "areLegacyImdsEndpointsDisabled" => true
      }
    }
  end

  def create_arm_instance do
    create_instance(%{
      "shape" => "VM.Standard.A1.Flex",
      "sourceDetails" => %{
        "sourceId" => oracle_arm_image(),
        "sourceType" => "image",
        "bootVolumeSizeInGbs" => 50
      },
      "shapeConfig" => %{
        "ocpus" => 1,
        "memoryInGBs" => 6
      }
    })
  end

  def create_amd_instance do
    create_instance(%{
      "shape" => "VM.Standard.E2.1.Micro",
      "sourceDetails" => %{
        "sourceId" => oracle_amd_image(),
        "sourceType" => "image",
        "bootVolumeSizeInGbs" => 50
      },
      "shapeConfig" => %{
        "ocpus" => 1,
        "memoryInGBs" => 1
      }
    })
  end

  defp get(service, path, query) do
    date = date()
    host = host(service)
    path = path <> "?" <> URI.encode_query(query)
    headers = [{"host", host}, {"date", date}]
    authorization = authorization([{"(request-target)", "get #{path}"} | headers])
    headers = [{"authorization", authorization} | headers]
    url = "https://" <> host <> path
    request(Finch.build("GET", url, headers))
  end

  defp post(service, path, body) do
    date = date()
    host = host(service)
    body = Jason.encode_to_iodata!(body)
    content_length = IO.iodata_length(body)
    content_hash = Base.encode64(:crypto.hash(:sha256, body))

    headers = [
      {"host", host},
      {"date", date},
      {"x-content-sha256", content_hash},
      {"content-length", to_string(content_length)},
      {"content-type", "application/json"}
    ]

    authorization = authorization([{"(request-target)", "post #{path}"} | headers])
    headers = [{"authorization", authorization} | headers]

    url = "https://" <> host <> path
    request(Finch.build("POST", url, headers, body))
  end

  defp request(req) do
    with {:ok, %{body: body} = resp} <- Finch.request(req, O.finch()) do
      {:ok, %{resp | body: Jason.decode!(body)}}
    end
  end

  defp date(now \\ NaiveDateTime.utc_now()) do
    Calendar.strftime(now, "%a, %d %b %Y %X GMT")
  end

  defp host(service) do
    "#{service}.#{config(:region)}.oraclecloud.com"
  end

  @doc false
  def authorization(fields) do
    headers = fields |> Enum.map(fn {k, _} -> k end) |> Enum.join(" ")

    ~s[Signature version="1",keyId="#{key_id()}",] <>
      ~s[algorithm="rsa-sha256",] <>
      ~s[headers="#{headers}",] <>
      ~s[signature="#{signature(fields)}"]
  end

  defp key_id do
    Application.get_env(@app, :key_id) ||
      "#{config(:tenancy)}/#{config(:user)}/#{config(:fingerprint)}"
  end

  defp signature(fields) do
    payload = for {k, v} <- fields, do: [k, ": ", v]
    payload = Enum.intersperse(payload, ?\n)
    Base.encode64(:public_key.sign(payload, :sha256, pkey()))
  end

  require Record

  for {k, v} <- [rsa_private_key: :RSAPrivateKey, rsa_public_key: :RSAPublicKey] do
    Record.defrecord(k, v, Record.extract(v, from_lib: "public_key/include/OTP-PUB-KEY.hrl"))
  end

  defp pkey, do: pkey(config(:private_key))

  defp pkey(pkey) do
    [pem_entry] = :public_key.pem_decode(pkey)
    rsa_private_key() = :public_key.pem_entry_decode(pem_entry)
  end
end
