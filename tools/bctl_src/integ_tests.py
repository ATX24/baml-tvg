"""Module for running integration tests and build commands for different project directories."""

import subprocess


def get_repo_root() -> str:
    """Get the git repository root directory."""
    result = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()


def run_all_integ_tests() -> None:
    """Run all integration tests."""
    run_python_integ_tests()
    run_typescript_integ_tests()
    run_ruby_integ_tests()
    run_java_integ_tests()


def run_python_integ_tests() -> None:
    """Run commands for the Python integration tests directory."""
    repo_root = get_repo_root()
    base_cmd = f"""
      cd {repo_root}/integ-tests/python
      uv run maturin develop --uv --manifest-path {repo_root}/engine/language_client_python/Cargo.toml
      uv run baml-cli generate --from {repo_root}/integ-tests/baml_src
      uv run pytest --capture=no
    """
    subprocess.run(base_cmd, shell=True, check=True)


def run_typescript_integ_tests() -> None:
    """Run commands for the TypeScript integration tests directory."""
    repo_root = get_repo_root()
    base_cmd = f"""
      cd {repo_root}/engine/language_client_typescript
      pnpm build:debug
      pnpm baml-cli generate --from {repo_root}/integ-tests/baml_src
      cd {repo_root}/integ-tests/typescript
      pnpm test -- --silent false --testTimeout 30000
    """
    subprocess.run(base_cmd, shell=True, check=True)


def run_ruby_integ_tests() -> None:
    """Run commands for the Ruby integration tests directory."""
    repo_root = get_repo_root()
    base_cmd = f"""
      cd {repo_root}/integ-tests/ruby
      rake compile
      rake generate
      rake test
    """
    subprocess.run(base_cmd, shell=True, check=True)


def run_java_integ_tests(skip_install: bool = False) -> None:
    """Run commands for the Java integration tests directory.

    Steps:
      1. Build and install baml-runtime-java to the local Maven repo (~/.m2).
         (Skipped when skip_install=True, useful when the JAR is already installed.)
      2. Generate the baml_client from the integration-test BAML sources.
      3. Run the Maven integration tests (WorkflowTest).

    Args:
      skip_install: When True, skip the `mvn install` step. Pass this flag if
                    you have already installed the runtime JAR and only want to
                    re-run the tests without rebuilding (saves ~30 s per run).

    Prerequisites:
      - Java 11+ and Maven on PATH.
      - BAML CLI binary at engine/target/release/baml-cli (cargo build --release).
      - BAML_LIBRARY_PATH pointing to engine/target/release/libbaml_cffi.so|dylib|dll.
      - OPENAI_API_KEY (or whichever key the integ-test BAML schema requires).
    """
    repo_root = get_repo_root()
    install_step = "" if skip_install else f"""
      echo "=== Installing baml-runtime-java to local Maven repo ==="
      cd {repo_root}/engine/language_client_java
      mvn install -DskipTests -q
"""
    base_cmd = f"""
      set -e
      {install_step}
      echo "=== Generating baml_client from integ-test BAML sources ==="
      {repo_root}/engine/target/release/baml-cli generate --from {repo_root}/integ-tests/java/baml_src

      echo "=== Running Java integration tests ==="
      cd {repo_root}/integ-tests/java
      mvn test
    """
    subprocess.run(base_cmd, shell=True, check=True)