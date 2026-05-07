class TokenGate < Formula
  desc "Local proxy gateway for managing multiple Claude API keys"
  homepage "https://github.com/simpossible/token_gate"
  version "0.1.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/simpossible/token_gate/releases/download/v#{version}/token_gate_darwin_arm64.tar.gz"
      sha256 "4fb2ad6f65a6067a13a6728060cfe195a14c64b633a8d2187ffedd9802649e73"
    end
    on_intel do
      url "https://github.com/simpossible/token_gate/releases/download/v#{version}/token_gate_darwin_amd64.tar.gz"
      sha256 "66cfbe3fc7a0f59301f2b860e9c383091072b5b60b43be60edd151cb986a167b"
    end
  end

  def install
    on_arm do
      bin.install "token_gate_darwin_arm64" => "token_gate"
    end
    on_intel do
      bin.install "token_gate_darwin_amd64" => "token_gate"
    end
  end

  service do
    run [opt_bin/"token_gate", "server"]
    keep_alive true
  end

  def caveats
    <<~EOS
      Run Token Gate:
        token_gate start    # start in background and open browser
        token_gate stop     # stop the background process
        token_gate show     # open the web interface
        token_gate status   # check if running

      Or start automatically on login:
        brew services start token_gate

      Web interface: http://127.0.0.1:12123
      Logs: ~/.token_gate/logs/token_gate.log
    EOS
  end
end
