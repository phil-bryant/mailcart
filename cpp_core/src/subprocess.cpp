#include "mailcartcore/subprocess.hpp"

#include <fcntl.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <sstream>

extern char **environ;

namespace mailcartcore::subprocess
{
  namespace
  {
    // #R032: Drain a pipe file descriptor fully into a string.
    std::string ReadAll(int fd)
    { std::string out;
      std::array<char, 4096> buffer{};
      for (;;)
      { ssize_t n = read(fd, buffer.data(), buffer.size());
        if (n > 0)
        { out.append(buffer.data(), static_cast<size_t>(n));
          continue;
        }
        if (n < 0 && errno == EINTR)
        { continue;
        }
        break;
      }
      return out;
    }
  } // namespace

  // #R032: Spawn the command with argv semantics (no shell) and capture stdout/stderr separately.
  CompletedProcess Run(const std::vector<std::string> &argv)
  { CompletedProcess result;
    if (argv.empty())
    { return result;
    }
    int out_pipe[2] = {-1, -1};
    int err_pipe[2] = {-1, -1};
    if (pipe(out_pipe) != 0)
    { return result;
    }
    if (pipe(err_pipe) != 0)
    { close(out_pipe[0]);
      close(out_pipe[1]);
      return result;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, out_pipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, err_pipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, out_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, out_pipe[1]);
    posix_spawn_file_actions_addclose(&actions, err_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, err_pipe[1]);

    std::vector<char *> argv_raw;
    argv_raw.reserve(argv.size() + 1);
    for (const auto &arg : argv)
    { argv_raw.push_back(const_cast<char *>(arg.c_str()));
    }
    argv_raw.push_back(nullptr);

    pid_t pid = 0;
    int spawn_status = posix_spawnp(&pid, argv[0].c_str(), &actions, nullptr, argv_raw.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    close(out_pipe[1]);
    close(err_pipe[1]);
    if (spawn_status != 0)
    { close(out_pipe[0]);
      close(err_pipe[0]);
      return result;
    }
    result.launched = true;
    result.stdout_text = ReadAll(out_pipe[0]);
    result.stderr_text = ReadAll(err_pipe[0]);
    close(out_pipe[0]);
    close(err_pipe[0]);

    int wait_status = 0;
    while (waitpid(pid, &wait_status, 0) < 0 && errno == EINTR)
    {
    }
    if (WIFEXITED(wait_status))
    { result.exit_code = WEXITSTATUS(wait_status);
    }
    return result;
  }

  // #R032: Resolve a command on PATH like shutil.which; empty string when absent.
  std::string Which(const std::string &command)
  { if (command.empty())
    { return "";
    }
    if (command.find('/') != std::string::npos)
    { return access(command.c_str(), X_OK) == 0 ? command : "";
    }
    const char *path_env = std::getenv("PATH");
    if (path_env == nullptr)
    { return "";
    }
    std::stringstream stream(path_env);
    std::string entry;
    while (std::getline(stream, entry, ':'))
    { if (entry.empty())
      { continue;
      }
      std::string candidate = entry + "/" + command;
      if (access(candidate.c_str(), X_OK) == 0)
      { struct stat status_buffer{};
        if (stat(candidate.c_str(), &status_buffer) == 0 && S_ISREG(status_buffer.st_mode))
        { return candidate;
        }
      }
    }
    return "";
  }
} // namespace mailcartcore::subprocess
