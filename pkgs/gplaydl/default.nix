{
  lib,
  buildPythonApplication,
  fetchPypi,
  setuptools,
  typer,
  rich,
  httpx,
}:

buildPythonApplication rec {
  pname = "gplaydl";
  version = "2.1.5";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-nAl1yMazd2mH16g5GPvAEYFsMIekcS1Jg4SRKkP2jFw=";
  };

  build-system = [ setuptools ];

  dependencies = [
    typer
    rich
    httpx
  ];

  # No test suite is shipped, and downloading requires network access anyway.
  doCheck = false;

  meta = {
    description = "Download APKs from Google Play Store using anonymous authentication (base APK, splits, OBB, asset packs)";
    homepage = "https://github.com/rehmatworks/gplaydl";
    changelog = "https://github.com/rehmatworks/gplaydl/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "gplaydl";
  };
}
