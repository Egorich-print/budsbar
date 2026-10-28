cask "budsbar" do
  version "0.1.4"
  sha256 "fb4d4b8ffaef3a4165854a2b3ead99b954f8daa415f094a567f6f594b7183bda"

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
