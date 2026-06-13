#pragma once
#include <string>
#include <vector>

// #R032: Declare the argv-based subprocess runner used to resolve 1psa credential fields without a shell.
namespace mailcartcore::subprocess
{
  struct CompletedProcess
  { int exit_code = -1;
    std::string stdout_text;
    std::string stderr_text;
    bool launched = false;
  };

  // Run argv[0] (resolved via PATH) with the given arguments and capture both
  // output streams. Never throws; failure to launch is reported via `launched`.
  [[nodiscard]] CompletedProcess Run(const std::vector<std::string> &argv);

  // PATH lookup mirroring shutil.which: returns "" when not found.
  [[nodiscard]] std::string Which(const std::string &command);
} // namespace mailcartcore::subprocess
