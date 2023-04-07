defmodule O do
  @moduledoc "Very basic OCI client used to create instances"
  @app :o

  use GenServer
  require Logger

  def finch, do: __MODULE__.Finch
  def config(key), do: Application.fetch_env!(@app, key)

  @impl true
  def init(state) do
    {:ok, %Finch.Response{status: 200, body: instances}} = list_instances()
    names = state.names -- Enum.map(instances, & &1["displayName"])

    if names == [] do
      :ignore
    else
      rand_schedule_loop(:timer.seconds(10))
      {:ok, %{state | names: names}}
    end
  end

  @impl true
  def handle_info(:loop, state) do
    %{names: [name | names], shape: shape} = state

    result =
      case create_instance(instance_config(name, shape)) do
        {:ok, %Finch.Response{status: 200, body: body}} ->
          Logger.info(shape: shape, created: body)

          case names do
            [] -> {:stop, :normal, state}
            _ -> {:cont, %{state | names: names}}
          end

        {:ok, %Finch.Response{status: 429, body: body}} ->
          Logger.warn(shape: shape, message: Map.fetch!(body, "message"))
          {:sleep, state}

        {:ok, %Finch.Response{status: status, body: body}} ->
          Logger.error(shape: shape, status: status, message: Map.fetch!(body, "message"))
          {:cont, state}

        {:error, error} ->
          raise error
      end

    case result do
      {:stop, _reason, _state} = stop ->
        stop

      {:sleep, state} ->
        rand_schedule_loop(:timer.seconds(120))
        {:noreply, state}

      {:cont, state} ->
        rand_schedule_loop(:timer.seconds(60))
        {:noreply, state}
    end
  end

  defp rand_schedule_loop(time) do
    Process.send_after(self(), :loop, :rand.uniform(time))
  end

  def instance_config(name, shape) do
    Map.merge(default_instance_config(name), shape_config(shape))
  end

  defp shape_config("VM.Standard.A1.Flex" = shape) do
    %{
      "shape" => shape,
      "sourceDetails" => %{"imageId" => image(shape), "sourceType" => "image"},
      "shapeConfig" => %{"ocpus" => 1, "memoryInGBs" => 6}
    }
  end

  defp shape_config("VM.Standard.E2.1.Micro" = shape) do
    %{
      "shape" => shape,
      "sourceDetails" => %{"imageId" => image(shape), "sourceType" => "image"},
      "shapeConfig" => %{"ocpus" => 1, "memoryInGBs" => 1}
    }
  end

  def list_instances(query \\ %{}) do
    query = Map.put_new(query, "compartmentId", config(:tenancy))
    get("iaas", "/20160918/instances", query)
  end

  def create_instance(body \\ %{}) do
    post("iaas", "/20160918/instances", body)
  end

  defp availability_domain do
    query = %{"compartmentId" => config(:tenancy)}

    {:ok, %Finch.Response{status: 200, body: domains}} =
      get("identity", "/20160918/availabilityDomains", query)

    domains |> Enum.random() |> Map.fetch!("name")
  end

  defp image(shape) do
    query = %{
      "compartmentId" => config(:tenancy),
      "operatingSystem" => "Oracle Linux",
      "operatingSystemVersion" => 8,
      "shape" => shape
    }

    {:ok, %Finch.Response{status: 200, body: images}} = get("iaas", "/20160918/images", query)

    images
    |> Enum.sort_by(& &1["timeCreated"], :desc)
    |> List.first()
    |> Map.fetch!("id")
  end

  defp default_instance_config(name) do
    %{
      "displayName" => name,
      "metadata" => %{"ssh_authorized_keys" => config(:public_key)},
      "agentConfig" => %{
        "isManagementDisabled" => false,
        "isMonitoringDisabled" => false,
        "pluginsConfig" => [
          %{"name" => "Vulnerability Scanning", "desiredState" => "DISABLED"},
          %{"name" => "Oracle Java Management Service", "desiredState" => "DISABLED"},
          %{"name" => "OS Management Service Agent", "desiredState" => "ENABLED"},
          %{"name" => "Management Agent", "desiredState" => "DISABLED"},
          %{"name" => "Custom Logs Monitoring", "desiredState" => "ENABLED"},
          %{"name" => "Compute Instance Run Command", "desiredState" => "ENABLED"},
          %{"name" => "Compute Instance Monitoring", "desiredState" => "ENABLED"},
          %{"name" => "Block Volume Management", "desiredState" => "DISABLED"},
          %{"name" => "Bastion", "desiredState" => "DISABLED"}
        ]
      },
      "compartmentId" => config(:tenancy),
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
    with {:ok, %Finch.Response{body: body} = resp} <- Finch.request(req, O.finch()) do
      {:ok, %Finch.Response{resp | body: Jason.decode!(body)}}
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

  for {k, v} <- [rsa_private_key: :RSAPrivateKey] do
    Record.defrecord(k, v, Record.extract(v, from_lib: "public_key/include/OTP-PUB-KEY.hrl"))
  end

  defp pkey, do: pkey(config(:private_key))

  defp pkey(pkey) do
    [pem_entry] = :public_key.pem_decode(pkey)
    rsa_private_key() = :public_key.pem_entry_decode(pem_entry)
  end
end
