// Port of scripts/matchy_mailcart_api.py's server entrypoint (plus
// dast_app.py's env-based host/port/TLS resolution): serve the Matchy-
// compatible Mailcart API over HTTPS on loopback.
// CPPHTTPLIB_OPENSSL_SUPPORT is defined by the httplib::httplib CMake target.
#include <httplib.h>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <unistd.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "mailcartcore/api.hpp"
#include "mailcartcore/http_transport.hpp"

namespace
{
  // #R005: Resolve host/port/TLS settings from a prioritized list of env var names, falling back to a default.
  std::string ResolveEnv(const std::vector<const char *> &names, const std::string &fallback)
  { for (const char *name : names)
    { const char *raw = std::getenv(name);
      if (raw == nullptr)
      { continue;
      }
      std::string value = raw;
      const auto begin = value.find_first_not_of(" \t\r\n");
      if (begin == std::string::npos)
      { continue;
      }
      const auto end = value.find_last_not_of(" \t\r\n");
      value = value.substr(begin, end - begin + 1);
      if (!value.empty())
      { return value;
      }
    }
    return fallback;
  }

  std::string HomePath(const std::string &relative)
  { const char *home = std::getenv("HOME");
    return (home == nullptr ? std::string(".") : std::string(home)) + "/" + relative;
  }

  // #R615: Probe whether the API port is already bound via a short-timeout localhost TCP connect.
  bool IsPortInUse(const std::string &host, int port)
  { const int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0)
    { return false;
    }
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<uint16_t>(port));
    if (inet_pton(AF_INET, host.c_str(), &address.sin_addr) != 1)
    { close(sock);
      return false;
    }
    fcntl(sock, F_SETFL, O_NONBLOCK);
    const int rc = connect(sock, reinterpret_cast<sockaddr *>(&address), sizeof(address));
    bool in_use = false;
    if (rc == 0)
    { in_use = true;
    }
    else if (errno == EINPROGRESS)
    { fd_set write_set;
      FD_ZERO(&write_set);
      FD_SET(sock, &write_set);
      timeval timeout{0, 250000};
      if (select(sock + 1, nullptr, &write_set, nullptr, &timeout) > 0)
      { int error = 0;
        socklen_t length = sizeof(error);
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &length);
        in_use = error == 0;
      }
    }
    close(sock);
    return in_use;
  }

  // #R040: Detect whether an already-bound HTTPS API instance is healthy on localhost.
  bool ExistingServerIsHealthy(const std::string &host, int port, const std::string &cert_file)
  { const auto probe = mailcartcore::transport::ProbeHttpsHealth(host, port, cert_file, 1.5);
    return probe.transport_ok && probe.status == 200 &&
           probe.body.find("\"status\":\"ok\"") != std::string::npos;
  }

  // #R040: Detect whether a legacy HTTP API instance occupies the configured localhost port.
  bool ExistingHttpServerIsHealthy(const std::string &host, int port)
  { const auto probe = mailcartcore::transport::ProbeHttpHealth(host, port, 1.5);
    return probe.transport_ok && probe.status == 200 &&
           probe.body.find("\"status\":\"ok\"") != std::string::npos;
  }

  std::string LoadOpenApiSpec()
  { std::string spec_path;
    const char *env_path = std::getenv("MAILCART_OPENAPI_SPEC_FILE");
    if (env_path != nullptr && env_path[0] != '\0')
    { spec_path = env_path;
    }
#if defined(MAILCART_OPENAPI_SPEC_PATH)
    if (spec_path.empty())
    { spec_path = MAILCART_OPENAPI_SPEC_PATH;
    }
#endif
    if (spec_path.empty())
    { return "";
    }
    std::ifstream stream(spec_path);
    if (!stream.is_open())
    { return "";
    }
    std::stringstream buffer;
    buffer << stream.rdbuf();
    return buffer.str();
  }
} // namespace

// #R040: Start the Matchy Mailcart API with HTTPS-only TLS settings.
int main()
{ const std::string host = ResolveEnv(
      {"CLASSIFICATION_API_HOST", "CLASSY_API_HOST", "TELLER_CLASSIFIER_API_HOST", "MATCHY_API_HOST"},
      mailcartcore::kApiHost);
  const std::string port_text = ResolveEnv(
      {"CLASSIFICATION_API_PORT", "CLASSY_API_PORT", "TELLER_CLASSIFIER_API_PORT", "MATCHY_API_PORT"},
      std::to_string(mailcartcore::kApiPort));
  int port = mailcartcore::kApiPort;
  try
  { port = std::stoi(port_text);
  }
  catch (const std::exception &)
  { std::cerr << "Invalid API port: " << port_text << "\n";
    return 1;
  }

  mailcartcore::GraphTokenManager token_manager;

  // Eager token validation mirrors run_server(): fail fast when a client id is configured.
  const std::string client_id = ResolveEnv({"OUTLOOK_GRAPH_CLIENT_ID"}, "");
  if (!client_id.empty())
  { try
    { (void)token_manager.GetAccessToken();
    }
    catch (const mailcartcore::GraphTokenError &exc)
    { std::cerr << exc.what() << "\n";
      return 1;
    }
  }

  // #R040: Resolve TLS cert/key paths and require HTTPS startup materials.
  // #R045: Fail fast with explicit guidance when TLS cert/key files are missing.
  const std::string cert_file = ResolveEnv(
      {"MAILCART_MATCHY_TLS_CERT_FILE", "MATCHY_API_TLS_CERT_FILE", "TELLER_CLASSIFIER_TLS_CERT_FILE"},
      HomePath(".mailcart/matchy-localhost-cert.pem"));
  const std::string key_file = ResolveEnv(
      {"MAILCART_MATCHY_TLS_KEY_FILE", "MATCHY_API_TLS_KEY_FILE", "TELLER_CLASSIFIER_TLS_KEY_FILE"},
      HomePath(".mailcart/matchy-localhost-key.pem"));
  if (!std::filesystem::is_regular_file(cert_file))
  { std::cerr << "MAILCART_MATCHY_TLS_CERT_FILE is required and must point to an existing certificate file: "
              << cert_file << ". Run ./05_install_matchy_api_tls.sh to install local TLS materials.\n";
    return 1;
  }
  if (!std::filesystem::is_regular_file(key_file))
  { std::cerr << "MAILCART_MATCHY_TLS_KEY_FILE is required and must point to an existing key file: "
              << key_file << ". Run ./05_install_matchy_api_tls.sh to install local TLS materials.\n";
    return 1;
  }

  const std::string https_base = "https://" + host + ":" + std::to_string(port);
  if (IsPortInUse(host, port))
  { if (ExistingServerIsHealthy(host, port, cert_file))
    { std::cout << "Mailcart API already running at " << https_base << "; reusing existing process.\n";
      return 0;
    }
    if (ExistingHttpServerIsHealthy(host, port))
    { std::cerr << "Port " << port << " is occupied by a legacy HTTP Mailcart API process. "
                << "Stop the existing process and rerun make run-api to launch HTTPS.\n";
      return 1;
    }
    std::cerr << "Port " << port << " is already in use by another process.\n";
    return 1;
  }

  mailcartcore::GraphClient graph(token_manager);
  mailcartcore::MailcartApi api(graph);
  const std::string openapi_spec = LoadOpenApiSpec();

  httplib::SSLServer server(cert_file.c_str(), key_file.c_str());
  if (!server.is_valid())
  { std::cerr << "Unable to initialize TLS server with cert " << cert_file << " and key " << key_file << "\n";
    return 1;
  }

  auto dispatch = [&api, &openapi_spec](const httplib::Request &req, httplib::Response &res)
  { if (req.method == "GET" && req.path == "/openapi.json" && !openapi_spec.empty())
    { res.status = 200;
      res.set_content(openapi_spec, "application/json");
      return;
    }
    mailcartcore::ApiRequest request;
    request.method = req.method;
    request.path = req.path;
    for (const auto &[key, value] : req.params)
    { request.query_params.emplace_back(key, value);
    }
    for (const auto &[key, value] : req.headers)
    { std::string lowered = key;
      for (auto &symbol : lowered)
      { symbol = static_cast<char>(std::tolower(static_cast<unsigned char>(symbol)));
      }
      request.headers[lowered] = value;
    }
    request.body = req.body;
    request.has_body = !req.body.empty();
    const mailcartcore::ApiResult result = mailcartcore::HandleApiRequest(api, request);
    res.status = result.status;
    for (const auto &[key, value] : result.headers)
    { res.set_header(key, value);
    }
    res.set_content(result.body.dump(), "application/json");
  };

  // Route every method/path through the shared FastAPI-equivalent dispatcher.
  const char *match_all = R"(/.*)";
  server.Get(match_all, dispatch);
  server.Post(match_all, dispatch);
  server.Put(match_all, dispatch);
  server.Delete(match_all, dispatch);
  server.Patch(match_all, dispatch);
  server.Options(match_all, dispatch);

  std::cout << "Mailcart API listening at " << https_base << "\n";
  if (!server.listen(host, port))
  { std::cerr << "Mailcart API failed to bind " << https_base << "\n";
    return 1;
  }
  return 0;
}
