// Port of scripts/refresh_graph_token.py: refresh the shared Microsoft Graph
// OAuth token cache. `--force` refreshes even when the cached token is valid.
#include <cstring>
#include <iostream>

#include "mailcartcore/token.hpp"

// #R001: CLI refreshes/validates the shared Graph OAuth cache; --force forces a refresh.
int main(int argc, char **argv)
{ bool force = false;
  for (int index = 1; index < argc; ++index)
  { if (std::strcmp(argv[index], "--force") == 0)
    { force = true;
    }
    else if (std::strcmp(argv[index], "--help") == 0 || std::strcmp(argv[index], "-h") == 0)
    { std::cout << "usage: mailcart_token [--force]\n"
                << "Refresh Mailcart Graph OAuth token cache.\n"
                << "  --force  Refresh even when the cached token is still valid.\n";
      return 0;
    }
    else
    { std::cerr << "mailcart_token: unrecognized argument: " << argv[index] << "\n";
      return 2;
    }
  }

  mailcartcore::GraphTokenManager manager;
  try
  { if (force)
    { manager.Invalidate();
      const mailcartcore::TokenSession session = manager.Load();
      manager.Refresh(true, session);
    }
    else
    { (void)manager.GetAccessToken();
    }
  }
  // #R005: Surface token errors to stderr and exit non-zero so callers can detect refresh failures.
  catch (const mailcartcore::GraphTokenError &exc)
  { std::cerr << exc.what() << "\n";
    return 1;
  }
  return 0;
}
