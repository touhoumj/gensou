{ lib
, buildPythonPackage
, fetchFromGitHub
, cargo
, rustPlatform
, rustc
, typing-extensions
, pytestCheckHook
, hypothesis
, pytest-timeout
, pytest-mock
, dirty-equals
}:

buildPythonPackage rec {
  pname = "pydantic-core";
  version = "2.10.1";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "pydantic";
    repo = "pydantic-core";
    rev = "v${version}";
    hash = "sha256-D7FOnSYMkle+Kl+ORDXpAGtSYyDzR8FnkZxjEY1BIqs=";
  };

  patches = [
    ./01-remove-benchmark-flags.patch
  ];

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    cargo
    rustPlatform.cargoSetupHook
    rustPlatform.maturinBuildHook
    rustc
    typing-extensions
  ];

  propagatedBuildInputs = [
    typing-extensions
  ];

  pythonImportsCheck = [ "pydantic_core" ];

  nativeCheckInputs = [
    pytestCheckHook
    hypothesis
    pytest-timeout
    dirty-equals
    pytest-mock
  ];
  disabledTests = [
    # RecursionError: maximum recursion depth exceeded while calling a Python object
    "test_recursive"
  ];
  disabledTestPaths = [
    # no point in benchmarking in nixpkgs build farm
    "tests/benchmarks"
  ];

  meta = with lib; {
    description = "Core validation logic for pydantic written in rust";
    homepage = "https://github.com/pydantic/pydantic-core";
    license = licenses.mit;
    maintainers = with maintainers; [ blaggacao ];
  };
}
