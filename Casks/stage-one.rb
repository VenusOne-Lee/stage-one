# Homebrew cask for Stage One. This repo doubles as the tap:
#   brew tap VenusOne-Lee/stage-one https://github.com/VenusOne-Lee/stage-one
#   brew install --cask stage-one
# The release workflow prints the new version and sha256 and attaches a bumped copy
# of this file to each release (docs/RELEASING.md).
cask "stage-one" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/VenusOne-Lee/stage-one/releases/download/v#{version}/StageOne-#{version}.dmg"
  name "Stage One"
  desc "Free, open source window manager: groups, a strip and saved scenes"
  homepage "https://github.com/VenusOne-Lee/stage-one"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Stage One.app"
  binary "#{appdir}/Stage One.app/Contents/Helpers/stage"

  uninstall quit: "africa.venusone.StageOne"

  zap trash: [
    "~/Library/Application Support/StageOne",
    "~/Library/Caches/africa.venusone.StageOne",
    "~/Library/HTTPStorages/africa.venusone.StageOne",
    "~/Library/Preferences/africa.venusone.StageOne.plist",
  ]
end
