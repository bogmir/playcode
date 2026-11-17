defmodule Playcode.Browser do
  @moduledoc """
  The static site as a reader's browser leaves it: headless Chrome opens a page from disk,
  runs its scripts, and prints the document they made. For the `:browser` tests, which
  are left out of the default run and of CI, which has no Chrome.
  """

  @doc "Chrome's path, or nil where none is installed."
  def chrome,
    do: Enum.find_value(~w(google-chrome chromium chromium-browser), &System.find_executable/1)

  @doc "The page at `address` (a path in `dir`, its `#…` included) after its scripts ran."
  def dom!(dir, address) do
    profile = Path.join(System.tmp_dir!(), "chrome-#{System.unique_integer([:positive])}")

    args = [
      "--headless=new",
      "--disable-gpu",
      "--allow-file-access-from-files",
      "--user-data-dir=#{profile}",
      "--virtual-time-budget=5000",
      "--dump-dom",
      "file://" <> Path.join(dir, address)
    ]

    # Chrome talks on stderr about its own start-up; only the document is read.
    {html, 0} = System.cmd("sh", ["-c", ~s(exec "$0" "$@" 2>/dev/null), chrome() | args])
    File.rm_rf(profile)
    LazyHTML.from_document(html)
  end
end
