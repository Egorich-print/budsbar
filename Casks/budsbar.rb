cask "budsbar" do
  version "0.1.2"
  sha256 "331844c1fd93b4713c7037c669d10a78a63d9d28e2739bde8d73d7b2e942ae2f"

  url "https://github.com/Egorich-print/budsbar/releases/download/v#{version}/BudsBar-macOS.tar.gz"
  name "BudsBar"
  desc "Native macOS menu-bar control panel for HUAWEI FreeBuds earbuds"
  homepage "https://github.com/Egorich-print/budsbar"

  app "BudsBar.app"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  caveats <<~EOS
    BudsBar needs Bluetooth permission on first launch.
    The earbuds must be paired with this Mac in System Settings › Bluetooth.
  EOS
end
