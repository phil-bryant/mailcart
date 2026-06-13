#pragma once
#include <string>
#include <utility>
#include <vector>

#include "mailcartcore/token.hpp"

// Live HTTPS transports (cpp-httplib + OpenSSL). Only available when the core
// is built with MAILCARTCORE_ENABLE_HTTP; fuzz builds exclude this surface.
namespace mailcartcore::transport
{
  // #R026: POST a form-encoded body to an absolute https:// URL (token endpoint).
  [[nodiscard]] HttpResponse PostForm(const std::string &url,
                                      const std::vector<std::pair<std::string, std::string>> &form);

  // #R027: Issue a Graph API request against https://graph.microsoft.com with a
  // relative versioned path (e.g. "/v1.0/me/messages?...") and optional JSON body.
  [[nodiscard]] HttpResponse GraphRequest(const std::string &method,
                                          const std::string &path_and_query,
                                          const std::vector<std::pair<std::string, std::string>> &headers,
                                          const std::string &json_body);

  // #R040: Probe a local HTTPS endpoint, verifying against the given CA file.
  [[nodiscard]] HttpResponse ProbeHttpsHealth(const std::string &host, int port,
                                              const std::string &ca_cert_file, double timeout_seconds);

  // #R040: Probe a local plain-HTTP endpoint (legacy server detection).
  [[nodiscard]] HttpResponse ProbeHttpHealth(const std::string &host, int port, double timeout_seconds);

  // Percent-encode a string for use in a query component (quote(value, safe="")).
  [[nodiscard]] std::string UrlEncode(const std::string &value, const std::string &safe = "");
} // namespace mailcartcore::transport
