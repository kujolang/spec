class KujoSpec < Formula
  desc "Structured task definition format for AI-native development"
  homepage "https://github.com/kujolang/spec"
  # NOTE: Head install is intentional until release artifacts are published with
  # checksum + provenance metadata (see docs/RELEASE_ARTIFACT_POLICY.md).
  head "https://github.com/kujolang/spec.git", branch: "main"
  license "MIT"
  version "0.1.0"

  depends_on "python@3.11"

  def install
    # Install the spec CLI script
    bin.install "scripts/spec" => "spec"

    # Install support scripts
    (libexec/"scripts").install "scripts/spec_helpers.py"
    (libexec/"scripts").install "scripts/spec_yaml_to_json.py"
    (libexec/"scripts").install "scripts/spec_toml_to_json.py"

    # Install Kujo modules
    (libexec/"src").install Dir["src/*.kujo"]

    # Install schema
    (libexec/"schema").install "schema/spec.schema.json"

    # Patch the spec script to find support files
    inreplace bin/"spec", 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"',
              "SCRIPT_DIR=\"#{libexec}/scripts\""
    inreplace bin/"spec", 'PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"',
              "PROJECT_DIR=\"#{libexec}\""
  end

  test do
    system "#{bin}/spec", "version"
    system "#{bin}/spec", "init", "--name", "test", "--output", testpath/"test.yml"
    assert_predicate testpath/"test.yml", :exist?
  end
end
