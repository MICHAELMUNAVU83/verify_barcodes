defmodule VerifyBarcodes.VerifyGtinTest do
  use ExUnit.Case, async: false

  @gs1_kenya_url "https://gs1kenya.org/activate/getbarcode_v2"
  @bearer_token "test-token"

  setup do
    previous_client = Application.get_env(:verify_barcodes, :gtin_http_client)
    previous_test_pid = Application.get_env(:verify_barcodes, :gtin_http_test_pid)
    previous_responses = Application.get_env(:verify_barcodes, :gtin_http_test_responses)
    previous_kenya_url = Application.get_env(:verify_barcodes, :gs1_kenya_getbarcode_url)
    previous_bearer_token = Application.get_env(:verify_barcodes, :gs1_kenya_bearer_token)

    Application.put_env(:verify_barcodes, :gtin_http_client, VerifyBarcodes.GtinHttpClientStub)
    Application.put_env(:verify_barcodes, :gtin_http_test_pid, self())
    Application.put_env(:verify_barcodes, :gs1_kenya_bearer_token, @bearer_token)

    on_exit(fn ->
      restore_env(:gtin_http_client, previous_client)
      restore_env(:gtin_http_test_pid, previous_test_pid)
      restore_env(:gtin_http_test_responses, previous_responses)
      restore_env(:gs1_kenya_getbarcode_url, previous_kenya_url)
      restore_env(:gs1_kenya_bearer_token, previous_bearer_token)
    end)

    :ok
  end

  test "posts directly to GS1 Kenya v2 and maps product plus GCP fields" do
    Application.put_env(
      :verify_barcodes,
      :gtin_http_test_responses,
      %{
        @gs1_kenya_url =>
          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "product" => %{
                 "weight" => "1",
                 "unit_of_measure" => "PIECE",
                 "target_market" => "KE",
                 "status" => "Inactive",
                 "image" => "https://gs1kenya.org/uploads/",
                 "global_product_classification" => "Baby/Infant Cutlery (Non Disposable)",
                 "description" => "TEEPEE WOODEN TOOTHPICKS TP6",
                 "brand_owner" => "BRUSH MANUFACTURERS",
                 "brand_name" => "TEEPEE"
               },
               "brand_owner" => %{
                 "website" => "https://N/A",
                 "licensing_member_organization" => "GS1 Kenya",
                 "license_type" => "GCP",
                 "license_key" => "616110226",
                 "brand_owner" => "BRUSH MANUFACTURERS",
                 "address" => "N/A"
               }
             }
           }}
      }
    )

    assert {:ok, product} = VerifyBarcodes.VerifyGtin.verify("6161102266160")

    assert product.source_label == "GS1 Kenya"
    assert product.gtin == "6161102266160"
    assert product.brand == "TEEPEE"
    assert product.description == "TEEPEE WOODEN TOOTHPICKS TP6"
    assert product.category == "Baby/Infant Cutlery (Non Disposable)"
    assert product.net_content == "1 Piece"
    assert product.target_market == "Kenya"
    assert product.status == "Inactive"
    assert product.unit_of_measure == "Piece"
    assert product.image_url == nil
    assert product.licensee == "BRUSH MANUFACTURERS"
    assert product.brand_owner == "BRUSH MANUFACTURERS"
    assert product.licensing_member_organization == "GS1 Kenya"
    assert product.license_type == "GCP"
    assert product.license_key == "616110226"
    assert product.brand_owner_website == nil

    assert_received {:gtin_http_called, @gs1_kenya_url, options}
    assert options[:json] == %{"barcode" => "6161102266160"}
    assert {"Authorization", "Bearer #{@bearer_token}"} in options[:headers]
  end

  test "strips a single leading zero before trying the 13 digit GS1 Kenya barcode" do
    Application.put_env(
      :verify_barcodes,
      :gtin_http_test_responses,
      fn
        @gs1_kenya_url, options ->
          assert options[:json] == %{"barcode" => "6161101890151"}

          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "product" => %{
                 "weight" => "1",
                 "unit_of_measure" => "H87",
                 "target_market" => "001",
                 "description" => "Cosy serviette 10 extra",
                 "global_product_classification" => "Beauty/Personal Care/Hygiene Variety Packs",
                 "brand_name" => "Cosy"
               },
               "brand_owner" => %{
                 "brand_owner" => "KIM-FAY EAST AFRICA LIMITED",
                 "license_type" => "GCP",
                 "license_key" => "616110189"
               }
             }
           }}
      end
    )

    assert {:ok, product} = VerifyBarcodes.VerifyGtin.verify("06161101890151")

    assert product.source_label == "GS1 Kenya"
    assert product.gtin == "06161101890151"
    assert product.brand == "Cosy"
    assert product.description == "Cosy serviette 10 extra"
    assert product.net_content == "1 Piece"
    assert product.target_market == "Global"
    assert product.unit_of_measure == "Piece"
    assert product.licensee == "KIM-FAY EAST AFRICA LIMITED"
    assert product.license_key == "616110189"
  end

  test "uses the configured local GS1 Kenya barcode endpoint" do
    local_url = "http://localhost:4001/activate/getbarcode_v2"

    Application.put_env(:verify_barcodes, :gs1_kenya_getbarcode_url, local_url)

    Application.put_env(
      :verify_barcodes,
      :gtin_http_test_responses,
      fn
        ^local_url, options ->
          assert options[:json] == %{"barcode" => "6161101890151"}

          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "product" => %{
                 "weight" => "1",
                 "unit_of_measure" => "PIECE",
                 "brand_name" => "Cosy"
               },
               "brand_owner" => %{"brand_owner" => "KIM-FAY EAST AFRICA LIMITED"}
             }
           }}
      end
    )

    assert {:ok, product} = VerifyBarcodes.VerifyGtin.verify("06161101890151")

    assert product.source_label == "GS1 Kenya"
    assert_received {:gtin_http_called, ^local_url, _options}
  end

  test "decodes string JSON bodies returned by GS1 Kenya" do
    Application.put_env(
      :verify_barcodes,
      :gtin_http_test_responses,
      fn
        @gs1_kenya_url, options ->
          assert options[:json] == %{"barcode" => "6161101890496"}

          {:ok,
           %Req.Response{
             status: 200,
             body:
               ~s({"product":{"weight":"30","unit_of_measure":"u2","target_market":"404","brand_name":"Pain Relief"},"brand_owner":{"brand_owner":"Example Pharma","license_type":"GCP","license_key":"616110189"}})
           }}
      end
    )

    assert {:ok, product} = VerifyBarcodes.VerifyGtin.verify("6161101890496")

    assert product.source_label == "GS1 Kenya"
    assert product.gtin == "6161101890496"
    assert product.brand == "Pain Relief"
    assert product.net_content == "30 Tablet"
    assert product.unit_of_measure == "Tablet"
    assert product.target_market == "404"
    assert product.licensee == "Example Pharma"
    assert product.license_key == "616110189"
  end

  defp restore_env(key, nil), do: Application.delete_env(:verify_barcodes, key)
  defp restore_env(key, value), do: Application.put_env(:verify_barcodes, key, value)
end
