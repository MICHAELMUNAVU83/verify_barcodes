defmodule VerifyBarcodes.Gtin do
  @moduledoc """
  GTIN (GS1 Global Trade Item Number) validation.

  Accepts GTIN-8, GTIN-12 (UPC-A), GTIN-13 (EAN-13) and GTIN-14 strings
  and validates the mod-10 check digit per GS1 specification.
  """

  @valid_lengths [8, 12, 13, 14]

  @spec validate(binary()) :: {:ok, binary()} | {:error, atom()}
  def validate(gtin) when is_binary(gtin) do
    trimmed = String.trim(gtin)

    cond do
      not Regex.match?(~r/^\d+$/, trimmed) ->
        {:error, :non_numeric}

      String.length(trimmed) not in @valid_lengths ->
        {:error, :invalid_length}

      not check_digit_valid?(trimmed) ->
        {:error, :invalid_check_digit}

      true ->
        {:ok, trimmed}
    end
  end

  def validate(_), do: {:error, :invalid_input}

  @doc "Pads a validated GTIN to 14 digits by prefixing zeros."
  @spec pad_to_14(binary()) :: binary()
  def pad_to_14(gtin) when is_binary(gtin) do
    String.pad_leading(gtin, 14, "0")
  end

  defp check_digit_valid?(digits) do
    {body, <<check::binary-size(1)>>} = String.split_at(digits, -1)

    expected =
      body
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce(0, fn {d, i}, acc ->
        weight = if rem(i, 2) == 0, do: 3, else: 1
        acc + d * weight
      end)
      |> then(&rem(10 - rem(&1, 10), 10))

    String.to_integer(check) == expected
  end
end
