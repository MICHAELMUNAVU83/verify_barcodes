defmodule VerifyBarcodes.VerifyGtin do
  require Logger

  @default_gs1_kenya_url "https://gs1kenya.org/activate/getbarcode_v2"
  @default_gs1_kenya_bearer_token "XP2hhQuJ4Uk_ksAhICQq1QXOZX_neqDrP13BYRmPQ3M"

  defmodule ReqClient do
    def post(url, options), do: Req.post(url, options)
  end

  def verify(gtin) when is_binary(gtin) do
    Logger.info("Starting GS1 Kenya GTIN lookup for #{gtin}")
    lookup_gs1_kenya(gtin)
  rescue
    error ->
      Logger.error("GTIN lookup crashed for #{gtin}: #{Exception.message(error)}")
      {:ok, :not_verified}
  catch
    kind, reason ->
      Logger.error("GTIN lookup threw #{inspect(kind)} for #{gtin}: #{inspect(reason)}")
      {:ok, :not_verified}
  end

  defp lookup_gs1_kenya(gtin) do
    candidates = gs1_kenya_candidates(gtin)

    Logger.info(
      "Trying GS1 Kenya lookup for #{gtin} with candidate(s): #{Enum.join(candidates, ", ")}"
    )

    gtin
    |> gs1_kenya_candidates()
    |> Enum.reduce_while({:ok, :not_verified}, fn candidate, _acc ->
      case lookup_gs1_kenya_candidate(candidate, gtin) do
        {:ok, :not_verified} -> {:cont, {:ok, :not_verified}}
        result -> {:halt, result}
      end
    end)
  end

  defp lookup_gs1_kenya_candidate(candidate, original_gtin) do
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{gs1_kenya_bearer_token()}"}
    ]

    req_options = [
      headers: headers,
      json: %{"barcode" => candidate},
      retry: :transient,
      max_retries: 5,
      receive_timeout: 60_000
    ]

    Logger.debug(
      "Posting barcode candidate #{candidate} to GS1 Kenya for original GTIN #{original_gtin}"
    )

    case http_client().post(gs1_kenya_url(), req_options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.debug("GS1 Kenya returned 200 for candidate #{candidate}")

        case decode_gs1_kenya_body(body) do
          {:ok, decoded_body} ->
            Logger.debug(
              "GS1 Kenya decoded response keys for candidate #{candidate}: #{inspect(Map.keys(decoded_body))}"
            )

            case normalize_gs1_kenya_product(decoded_body, original_gtin) do
              nil ->
                Logger.info(
                  "GS1 Kenya returned no usable product data for candidate #{candidate}"
                )

                {:ok, :not_verified}

              product ->
                Logger.info(
                  "GS1 Kenya returned product data for original GTIN #{original_gtin} using candidate #{candidate}"
                )

                {:ok, product}
            end

          {:error, reason} ->
            Logger.warning(
              "GS1 Kenya returned a 200 response but the body could not be decoded for candidate #{candidate}: #{inspect(reason)}"
            )

            {:ok, :not_verified}
        end

      {:ok, %Req.Response{status: status}} when status in 400..599 ->
        Logger.warning("GS1 Kenya returned HTTP #{status} for candidate #{candidate}")
        {:ok, :not_verified}

      {:error, _reason} ->
        Logger.warning("GS1 Kenya request errored for candidate #{candidate}")
        {:ok, :not_verified}

      _ ->
        Logger.warning("GS1 Kenya returned an unexpected response for candidate #{candidate}")
        {:ok, :not_verified}
    end
  end

  defp gs1_kenya_candidates(gtin) do
    [strip_single_leading_zero(gtin), gtin]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp strip_single_leading_zero("0" <> rest) when byte_size(rest) == 13, do: rest
  defp strip_single_leading_zero(_gtin), do: nil

  defp normalize_gs1_kenya_product(response, gtin) do
    product =
      response
      |> Map.get("product", response)
      |> map_value()

    brand_owner = map_value(response["brand_owner"])

    normalized = %{
      gtin: gtin,
      brand: extract_string(product["brand_name"]) || extract_string(product["brand"]),
      name: extract_string(product["name"]),
      description: extract_string(product["description"]),
      category:
        extract_string(product["global_product_classification"]) ||
          extract_string(product["classify"]),
      net_content:
        extract_gs1_kenya_net_content(
          product["weight"],
          product["unit_of_measure"] || product["uom"],
          product["package"]
        ),
      country_of_sale: nil,
      target_market: target_market_label(product["target_market"] || product["target"]),
      status: extract_string(product["status"]),
      unit_of_measure: uom_label(product["unit_of_measure"] || product["uom"]),
      image_url: extract_image_url(product["image"]),
      licensee:
        extract_string(brand_owner["brand_owner"]) ||
          extract_string(product["brand_owner"]) ||
          extract_string(product["company"]),
      brand_owner: extract_string(product["brand_owner"]),
      brand_owner_address: extract_string(brand_owner["address"]),
      brand_owner_website: extract_website(brand_owner["website"]),
      licensing_member_organization: extract_string(brand_owner["licensing_member_organization"]),
      license_type: extract_string(brand_owner["license_type"]),
      license_key: extract_string(brand_owner["license_key"]),
      source_label: "GS1 Kenya"
    }

    if normalized
       |> Map.drop([:gtin, :source_label])
       |> Enum.any?(fn {_key, value} -> present?(value) end) do
      normalized
    end
  end

  defp decode_gs1_kenya_body(body) when is_map(body), do: {:ok, body}

  defp decode_gs1_kenya_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, decoded} -> {:error, {:unexpected_json_shape, decoded}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_gs1_kenya_body(body), do: {:error, {:unexpected_body_type, body}}

  defp extract_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp extract_string(_), do: nil

  defp extract_gs1_kenya_net_content(weight, uom, package) do
    [extract_string(weight), uom_label(uom), extract_string(package)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> extract_string()
  end

  defp extract_image_url(value) do
    value
    |> extract_string()
    |> case do
      "https://gs1kenya.org/uploads/" -> nil
      other -> other
    end
  end

  defp target_market_label(value) do
    case extract_string(value) do
      "001" -> "Global"
      "KE" -> "Kenya"
      other -> other
    end
  end

  defp uom_label(value) do
    case value |> extract_string() |> maybe_upcase() do
      "H87" -> "Piece"
      "PIECE" -> "Piece"
      "U2" -> "Tablet"
      other -> other
    end
  end

  defp maybe_upcase(nil), do: nil
  defp maybe_upcase(value), do: String.upcase(value)

  defp present?(value), do: value not in [nil, "", []]

  defp map_value(value) when is_map(value), do: value
  defp map_value(_), do: %{}

  defp extract_website(value) do
    case extract_string(value) do
      nil -> nil
      "https://N/A" -> nil
      "http://N/A" -> nil
      "N/A" -> nil
      website -> website
    end
  end

  defp http_client do
    Application.get_env(:verify_barcodes, :gtin_http_client, ReqClient)
  end

  defp gs1_kenya_url do
    Application.get_env(:verify_barcodes, :gs1_kenya_getbarcode_url, @default_gs1_kenya_url)
  end

  defp gs1_kenya_bearer_token do
    Application.get_env(
      :verify_barcodes,
      :gs1_kenya_bearer_token,
      @default_gs1_kenya_bearer_token
    )
  end
end
