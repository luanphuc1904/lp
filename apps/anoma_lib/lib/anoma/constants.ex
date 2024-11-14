defmodule Anoma.Constants do
  def felt_zero, do: <<0::256>>

  def felt_one, do: <<1::256>>

  def prf_expand_personalization_felt,
    do:
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 67, 97, 105, 114, 111,
        95, 69, 120, 112, 97, 110, 100, 83, 101, 101, 100>>

  def cairo_compliance_program_hash,
    do:
      <<1, 187, 37, 213, 62, 82, 16, 216, 85, 16, 20, 9, 248, 138, 85, 191,
        92, 149, 228, 228, 215, 118, 57, 175, 251, 63, 166, 64, 144, 107, 240,
        61>>

  # cairo_trivial_resource_logic_hash is just for test
  @spec cairo_trivial_resource_logic_hash() :: binary()
  def cairo_trivial_resource_logic_hash,
    do:
      <<3, 115, 187, 29, 55, 65, 76, 46, 223, 17, 28, 242, 249, 240, 118, 81,
        125, 169, 157, 56, 228, 76, 221, 113, 108, 162, 173, 0, 160, 119, 49,
        229>>

  @doc """
  The default merkle root in cairo RM is used when the root set is empty and can
  also serve as the root of ephemeral resources.
  """
  @spec default_cairo_rm_root() :: binary()
  def default_cairo_rm_root,
    do:
      <<5, 101, 30, 21, 217, 125, 148, 196, 222, 166, 77, 121, 232, 165, 45,
        28, 38, 119, 178, 62, 102, 218, 45, 158, 185, 49, 107, 56, 99, 93,
        101, 44>>
end
