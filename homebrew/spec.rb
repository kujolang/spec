class KujoSpec < Formula
  desc "Structured task definition format for AI-native development"
  homepage "https://github.com/kujolang/spec"
  # NOTE: Head install is intentional until release artifacts are published with
  # checksum + provenance metadata (see docs/RELEASE_ARTIFACT_POLICY.md).
  head "https://github.com/kujolang/spec.git", branch: "main"
  license "MIT"
  version "1.0.2"

  depends_on "python@3.11"

  def install
    (libexec/"scripts").install "scripts/spec", "scripts/spec_helpers.py",
                               "scripts/spec_yaml_to_json.py", "scripts/spec_toml_to_json.py"
    (libexec/"scripts/commands").install "scripts/commands/maintenance.sh"
    (libexec/"src").install Dir["src/*.kujo"]
    (libexec/"schema").install "schema/spec.schema.json"
    bin.write_exec_script libexec/"scripts/spec"
  end

  test do
    system "#{bin}/spec", "version"
    system "#{bin}/spec", "init", "--name", "test", "--output", testpath/"test.yml"
    assert_predicate testpath/"test.yml", :exist?
  end
end
