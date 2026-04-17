defmodule VerifyBarcodesWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use VerifyBarcodesWeb, :controller` and
  `use VerifyBarcodesWeb, :live_view`.
  """
  use VerifyBarcodesWeb, :html

  @default_page_title "Verify Barcodes"
  @default_page_description "Upload a barcode image and get an AI-assisted GS1-style verification summary with checks, warnings, and recommendations."
  @default_page_type "website"
  @site_name "Verify Barcodes"

  def default_page_title, do: @default_page_title

  def page_title(assigns), do: assigns[:page_title] || @default_page_title

  def page_description(assigns), do: assigns[:page_description] || @default_page_description

  def page_type(assigns), do: assigns[:page_type] || @default_page_type

  def page_url(assigns), do: assigns[:page_url] || url(~p"/")

  def page_image(assigns), do: assigns[:page_image] || url(~p"/images/gs1.png")

  def site_name, do: @site_name

  def structured_data(assigns) do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebApplication",
      "name" => page_title(assigns),
      "applicationCategory" => "BusinessApplication",
      "operatingSystem" => "Any",
      "description" => page_description(assigns),
      "url" => page_url(assigns),
      "image" => page_image(assigns),
      "publisher" => %{
        "@type" => "Organization",
        "name" => site_name(),
        "logo" => %{
          "@type" => "ImageObject",
          "url" => page_image(assigns)
        }
      }
    }
    |> Jason.encode!()
  end

  embed_templates "layouts/*"
end
