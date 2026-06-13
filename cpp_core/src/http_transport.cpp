#include "mailcartcore/http_transport.hpp"

// CPPHTTPLIB_OPENSSL_SUPPORT is defined by the httplib::httplib CMake target.
#include <httplib.h>

namespace mailcartcore::transport
{
  namespace
  {
    constexpr double kGraphTimeoutSeconds = 25.0;

    // #R027: Split an absolute https URL into origin ("https://host[:port]") and path-with-query.
    bool SplitUrl(const std::string &url, std::string &origin, std::string &path_and_query)
    { const std::string prefix = "https://";
      if (url.rfind(prefix, 0) != 0)
      { return false;
      }
      const auto path_start = url.find('/', prefix.size());
      if (path_start == std::string::npos)
      { origin = url;
        path_and_query = "/";
        return true;
      }
      origin = url.substr(0, path_start);
      path_and_query = url.substr(path_start);
      return true;
    }

    void ApplyTimeout(httplib::SSLClient &client, double seconds)
    { const auto whole = static_cast<time_t>(seconds);
      const auto usec = static_cast<time_t>((seconds - static_cast<double>(whole)) * 1000000.0);
      client.set_connection_timeout(whole, usec);
      client.set_read_timeout(whole, usec);
      client.set_write_timeout(whole, usec);
    }

    HttpResponse FromResult(const httplib::Result &result)
    { HttpResponse response;
      if (!result)
      { response.transport_ok = false;
        response.transport_error = httplib::to_string(result.error());
        return response;
      }
      response.transport_ok = true;
      response.status = result->status;
      response.body = result->body;
      return response;
    }
  } // namespace

  // Percent-encode a string for use in a query component (quote(value, safe="")).
  std::string UrlEncode(const std::string &value, const std::string &safe)
  { static constexpr const char *kHex = "0123456789ABCDEF";
    std::string encoded;
    encoded.reserve(value.size() * 3);
    for (unsigned char symbol : value)
    { const bool unreserved = (symbol >= 'A' && symbol <= 'Z') || (symbol >= 'a' && symbol <= 'z') ||
                              (symbol >= '0' && symbol <= '9') || symbol == '-' || symbol == '_' ||
                              symbol == '.' || symbol == '~';
      if (unreserved || safe.find(static_cast<char>(symbol)) != std::string::npos)
      { encoded.push_back(static_cast<char>(symbol));
      }
      else
      { encoded.push_back('%');
        encoded.push_back(kHex[symbol >> 4]);
        encoded.push_back(kHex[symbol & 0x0F]);
      }
    }
    return encoded;
  }

  // #R026: POST a form-encoded body to an absolute https:// URL (token endpoint).
  HttpResponse PostForm(const std::string &url,
                        const std::vector<std::pair<std::string, std::string>> &form)
  { std::string origin;
    std::string path_and_query;
    if (!SplitUrl(url, origin, path_and_query))
    { HttpResponse response;
      response.transport_error = "unsupported URL: " + url;
      return response;
    }
    httplib::SSLClient client(origin.substr(std::string("https://").size()));
    client.enable_server_certificate_verification(true);
    ApplyTimeout(client, kGraphTimeoutSeconds);
    std::string body;
    for (const auto &[key, value] : form)
    { if (!body.empty())
      { body.push_back('&');
      }
      body += UrlEncode(key) + "=" + UrlEncode(value);
    }
    return FromResult(client.Post(path_and_query, body, "application/x-www-form-urlencoded"));
  }

  // #R027: Issue a Graph API request against https://graph.microsoft.com.
  HttpResponse GraphRequest(const std::string &method,
                            const std::string &path_and_query,
                            const std::vector<std::pair<std::string, std::string>> &headers,
                            const std::string &json_body)
  { httplib::SSLClient client("graph.microsoft.com");
    client.enable_server_certificate_verification(true);
    ApplyTimeout(client, kGraphTimeoutSeconds);
    httplib::Headers request_headers;
    for (const auto &[key, value] : headers)
    { request_headers.emplace(key, value);
    }
    if (method == "GET")
    { return FromResult(client.Get(path_and_query, request_headers));
    }
    if (method == "POST")
    { return FromResult(client.Post(path_and_query, request_headers, json_body, "application/json"));
    }
    HttpResponse response;
    response.transport_error = "unsupported Graph method: " + method;
    return response;
  }

  // #R040: Probe a local HTTPS endpoint, verifying against the given CA file.
  HttpResponse ProbeHttpsHealth(const std::string &host, int port,
                                const std::string &ca_cert_file, double timeout_seconds)
  { httplib::SSLClient client(host, port);
    if (!ca_cert_file.empty())
    { client.set_ca_cert_path(ca_cert_file);
    }
    client.enable_server_certificate_verification(true);
    ApplyTimeout(client, timeout_seconds);
    return FromResult(client.Get("/health"));
  }

  // #R040: Probe a local plain-HTTP endpoint (legacy server detection).
  HttpResponse ProbeHttpHealth(const std::string &host, int port, double timeout_seconds)
  { httplib::Client client(host, port);
    const auto whole = static_cast<time_t>(timeout_seconds);
    const auto usec = static_cast<time_t>((timeout_seconds - static_cast<double>(whole)) * 1000000.0);
    client.set_connection_timeout(whole, usec);
    client.set_read_timeout(whole, usec);
    return FromResult(client.Get("/health"));
  }
} // namespace mailcartcore::transport
