#include "mailcartcore/graph.hpp"

#include <algorithm>
#include <cctype>

#include "mailcartcore/api_error.hpp"
#if defined(MAILCARTCORE_ENABLE_HTTP)
#include "mailcartcore/http_transport.hpp"
#endif

namespace mailcartcore
{
  namespace
  {
    std::string AsciiLower(std::string value)
    { std::transform(value.begin(), value.end(), value.begin(),
                     [](unsigned char symbol) { return static_cast<char>(std::tolower(symbol)); });
      return value;
    }

    std::string Truncate200(const std::string &value)
    { return value.substr(0, 200);
    }

    int HexDigit(char symbol)
    { if (symbol >= '0' && symbol <= '9')
      { return symbol - '0';
      }
      if (symbol >= 'a' && symbol <= 'f')
      { return symbol - 'a' + 10;
      }
      if (symbol >= 'A' && symbol <= 'F')
      { return symbol - 'A' + 10;
      }
      return -1;
    }

    // #R027: Default live transport serializes (path, params) onto graph.microsoft.com/v1.0.
    HttpResponse DefaultTransport(const GraphRequestArgs &args,
                                  const std::vector<std::pair<std::string, std::string>> &headers)
    {
#if defined(MAILCARTCORE_ENABLE_HTTP)
      std::string path_and_query = "/v1.0" + args.path;
      if (!args.params.empty())
      { path_and_query.push_back('?');
        bool first = true;
        for (const auto &[key, value] : args.params)
        { if (!first)
          { path_and_query.push_back('&');
          }
          first = false;
          path_and_query += transport::UrlEncode(key) + "=" + transport::UrlEncode(value);
        }
      }
      const std::string body = args.payload.has_value() ? args.payload->dump() : "";
      return transport::GraphRequest(args.method, path_and_query, headers, body);
#else
      (void)args;
      (void)headers;
      HttpResponse response;
      response.transport_ok = false;
      response.transport_error = "HTTP transport disabled in this build";
      return response;
#endif
    }
  } // namespace

  // #R600: Classify Graph responses as auth failures (HTTP 401 or known invalid-token bodies).
  bool IsAuthFailure(int status_code, const std::string &body)
  { if (status_code == 401)
    { return true;
    }
    const std::string lowered = AsciiLower(body);
    return lowered.find("invalidauthenticationtoken") != std::string::npos ||
           lowered.find("authorization_identity_not_found") != std::string::npos ||
           lowered.find("graph auth failed") != std::string::npos ||
           lowered.find(": 401 ") != std::string::npos;
  }

  // Percent-decode (urllib.parse.unquote): leaves '+' untouched.
  std::string UrlUnquote(const std::string &value)
  { std::string output;
    output.reserve(value.size());
    size_t index = 0;
    while (index < value.size())
    { if (value[index] == '%' && index + 2 < value.size())
      { const int high = HexDigit(value[index + 1]);
        const int low = HexDigit(value[index + 2]);
        if (high >= 0 && low >= 0)
        { output.push_back(static_cast<char>((high << 4) | low));
          index += 3;
          continue;
        }
      }
      output.push_back(value[index]);
      ++index;
    }
    return output;
  }

  // Percent-encode one path segment (urllib.parse.quote with safe="").
  std::string QuotePathSegment(const std::string &value)
  { static constexpr const char *kHex = "0123456789ABCDEF";
    std::string encoded;
    encoded.reserve(value.size() * 3);
    for (unsigned char symbol : value)
    { const bool unreserved = (symbol >= 'A' && symbol <= 'Z') || (symbol >= 'a' && symbol <= 'z') ||
                              (symbol >= '0' && symbol <= '9') || symbol == '-' || symbol == '_' ||
                              symbol == '.' || symbol == '~';
      if (unreserved)
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

  // parse_qsl(query, keep_blank_values=True) equivalent ('+' decodes to space).
  QueryParams ParseQueryString(const std::string &query)
  { QueryParams params;
    size_t start = 0;
    while (start <= query.size())
    { size_t end = query.find('&', start);
      if (end == std::string::npos)
      { end = query.size();
      }
      const std::string pair_text = query.substr(start, end - start);
      if (!pair_text.empty())
      { const size_t equals = pair_text.find('=');
        std::string key = equals == std::string::npos ? pair_text : pair_text.substr(0, equals);
        std::string value = equals == std::string::npos ? "" : pair_text.substr(equals + 1);
        std::replace(key.begin(), key.end(), '+', ' ');
        std::replace(value.begin(), value.end(), '+', ' ');
        if (!key.empty())
        { params.emplace_back(UrlUnquote(key), UrlUnquote(value));
        }
      }
      if (end == query.size())
      { break;
      }
      start = end + 1;
    }
    return params;
  }

  // #R035: Normalize message ids and encode them as safe single Graph path segments.
  std::string GraphMessagePath(const std::string &message_id)
  { const std::string normalized_id = UrlUnquote(message_id);
    return "/me/messages/" + QuotePathSegment(normalized_id);
  }

  // #R035: Validate message ids before Graph calls to fail closed on malformed inputs.
  std::string ValidatedGraphMessageId(const std::string &message_id)
  { std::string normalized = message_id;
    const auto begin = normalized.find_first_not_of(" \t\r\n\f\v");
    if (begin == std::string::npos)
    { normalized.clear();
    }
    else
    { const auto end = normalized.find_last_not_of(" \t\r\n\f\v");
      normalized = normalized.substr(begin, end - begin + 1);
    }
    if (normalized.size() < 8)
    { throw ApiError(404, "message not found");
    }
    const bool all_allowed = std::all_of(normalized.begin(), normalized.end(), [](unsigned char symbol)
    { return std::isalnum(symbol) != 0 || symbol == '.' || symbol == '_' || symbol == ':' ||
             symbol == '/' || symbol == '+' || symbol == '=' || symbol == '-';
    });
    if (!all_allowed)
    { throw ApiError(404, "message not found");
    }
    return normalized;
  }

  GraphClient::GraphClient(GraphTokenManager &token_manager, GraphTransport transport)
    : token_manager_(token_manager),
      transport_(transport ? std::move(transport) : GraphTransport(DefaultTransport))
  {
  }

  GraphTokenManager &GraphClient::tokenManager()
  { return token_manager_;
  }

  // #R010: Build Graph request headers with auth and JSON content negotiation.
  // #R015: Fail request processing with explicit error when token is missing.
  std::vector<std::pair<std::string, std::string>> GraphClient::Headers()
  { std::string token;
    try
    { token = token_manager_.GetAccessToken();
    }
    catch (const GraphTokenError &)
    { throw ApiError(500, "Graph access token is unavailable.");
    }
    return {
        {"Authorization", "Bearer " + token},
        {"Accept", "application/json"},
        {"Content-Type", "application/json"},
    };
  }

  // #R027: Retry the Graph request once after a 401 by invalidating + force-refreshing the cached token.
  nlohmann::json GraphClient::Request(const std::string &method, const std::string &path,
                                      const QueryParams &params,
                                      const std::optional<nlohmann::json> &payload)
  { for (int attempt = 0; attempt < 2; ++attempt)
    { const auto headers = Headers();
      GraphRequestArgs args{method, path, params, payload};
      const HttpResponse response = transport_(args, headers);
      if (!response.transport_ok)
      { throw ApiError(502, "Graph " + method + " failed: " + response.transport_error);
      }
      if (response.status < 400)
      { if (response.body.empty())
        { return nlohmann::json::object();
        }
        nlohmann::json parsed = nlohmann::json::parse(response.body, nullptr, false);
        if (parsed.is_discarded())
        { throw ApiError(502, "Graph " + method + " returned invalid JSON");
        }
        return parsed;
      }
      if (attempt == 0 && IsAuthFailure(response.status, response.body))
      { token_manager_.Invalidate();
        try
        { token_manager_.Refresh(true);
        }
        catch (const GraphTokenError &)
        { throw ApiError(502, "Graph authentication failed: token refresh failed.");
        }
        continue;
      }
      const std::string truncated = Truncate200(response.body);
      if (IsAuthFailure(response.status, response.body))
      { throw ApiError(502, "Graph auth failed: " + std::to_string(response.status) + " " + truncated);
      }
      // Pass through Graph's 404 (and ItemNotFound errors) as a real 404 so downstream
      // callers can render "no longer in inbox" instead of a generic 502. Graph also
      // occasionally serves ResourceNotFound as 400 with that text in the body.
      const std::string lowered = AsciiLower(response.body);
      if (response.status == 404 || lowered.find("itemnotfound") != std::string::npos ||
          lowered.find("resourcenotfound") != std::string::npos)
      { throw ApiError(404, "Graph reports message not found: " + truncated);
      }
      throw ApiError(502, "Graph " + method + " failed: " + std::to_string(response.status) + " " + truncated);
    }
    throw ApiError(502, "Graph request failed after token refresh retry");
  }

  // #R027: Issue Graph GET requests through the shared authenticated request/retry pipeline.
  nlohmann::json GraphClient::Get(const std::string &path, const QueryParams &params)
  { return Request("GET", path, params, std::nullopt);
  }

  // #R605: Issue authenticated Graph POST requests via the shared retry-aware pipeline.
  nlohmann::json GraphClient::Post(const std::string &path, const nlohmann::json &payload)
  { return Request("POST", path, {}, payload);
  }

  // #R020: Follow Graph @odata.nextLink pagination only when host and base path are trusted.
  nlohmann::json GraphClient::GetNextLink(const std::string &next_link)
  { // urlsplit equivalents: scheme://netloc/path?query
    const std::string scheme_separator = "://";
    const auto scheme_end = next_link.find(scheme_separator);
    std::string scheme;
    std::string remainder;
    if (scheme_end != std::string::npos)
    { scheme = AsciiLower(next_link.substr(0, scheme_end));
      remainder = next_link.substr(scheme_end + scheme_separator.size());
    }
    const auto path_start = remainder.find('/');
    const std::string netloc = path_start == std::string::npos ? remainder : remainder.substr(0, path_start);
    std::string path_and_query = path_start == std::string::npos ? "" : remainder.substr(path_start);
    if (scheme != "https" || netloc != "graph.microsoft.com")
    { throw ApiError(502, "Graph pagination returned an unexpected host");
    }
    std::string query;
    const auto query_start = path_and_query.find('?');
    std::string path = path_and_query;
    if (query_start != std::string::npos)
    { query = path_and_query.substr(query_start + 1);
      path = path_and_query.substr(0, query_start);
    }
    const std::string base_path = "/v1.0";
    if (path.rfind(base_path, 0) == 0)
    { path = path.substr(base_path.size());
      if (path.empty())
      { path = "/";
      }
    }
    return Get(path, ParseQueryString(query));
  }

  // #R025: Resolve destination mail folder by name, creating it when absent.
  std::string GraphClient::GetOrCreateFolderId(const std::string &folder_name)
  { const nlohmann::json folders = Get("/me/mailFolders", {{"$select", "id,displayName"}, {"$top", "200"}});
    const std::string wanted = AsciiLower(folder_name);
    if (folders.is_object() && folders.contains("value") && folders["value"].is_array())
    { for (const auto &row : folders["value"])
      { if (!row.is_object())
        { continue;
        }
        std::string display_name;
        if (row.contains("displayName") && row["displayName"].is_string())
        { display_name = row["displayName"].get<std::string>();
        }
        if (AsciiLower(display_name) == wanted)
        { if (row.contains("id") && row["id"].is_string())
          { return row["id"].get<std::string>();
          }
          return "";
        }
      }
    }
    const nlohmann::json created = Post("/me/mailFolders", nlohmann::json{{"displayName", folder_name}});
    std::string folder_id;
    if (created.is_object() && created.contains("id") && created["id"].is_string())
    { folder_id = created["id"].get<std::string>();
    }
    if (folder_id.empty())
    { throw ApiError(502, "Unable to create folder: " + folder_name);
    }
    return folder_id;
  }
} // namespace mailcartcore
