#include "mailcartcore/api.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>

#include "mailcartcore/api_error.hpp"
#include "mailcartcore/search.hpp"

namespace mailcartcore
{
  namespace
  {
    constexpr const char *kWriteTokenEnvVars[] = {
        "MAILCART_API_WRITE_TOKEN", "TELLER_CLASSIFIER_WRITE_TOKEN", "CLASSY_WRITE_TOKEN"};

    std::string Strip(const std::string &value)
    { const auto begin = value.find_first_not_of(" \t\r\n\f\v");
      if (begin == std::string::npos)
      { return "";
      }
      const auto end = value.find_last_not_of(" \t\r\n\f\v");
      return value.substr(begin, end - begin + 1);
    }

    std::string AsciiLower(std::string value)
    { std::transform(value.begin(), value.end(), value.begin(),
                     [](unsigned char symbol) { return static_cast<char>(std::tolower(symbol)); });
      return value;
    }

    // #R620: hmac.compare_digest equivalent: constant-time equality over equal-length inputs.
    bool ConstantTimeEquals(const std::string &left, const std::string &right)
    { if (left.size() != right.size())
      { return false;
      }
      unsigned char accumulator = 0;
      for (size_t index = 0; index < left.size(); ++index)
      { accumulator = static_cast<unsigned char>(
            accumulator | (static_cast<unsigned char>(left[index]) ^ static_cast<unsigned char>(right[index])));
      }
      return accumulator == 0;
    }

    std::string JsonFieldAsString(const nlohmann::json &object, const char *key)
    { if (!object.is_object() || !object.contains(key))
      { return "";
      }
      const auto &value = object[key];
      if (value.is_string())
      { return value.get<std::string>();
      }
      if (value.is_null())
      { return "";
      }
      return value.dump();
    }

    std::string SenderAddress(const nlohmann::json &row)
    { if (!row.is_object() || !row.contains("from") || !row["from"].is_object())
      { return "";
      }
      const auto &from = row["from"];
      if (!from.contains("emailAddress") || !from["emailAddress"].is_object())
      { return "";
      }
      return JsonFieldAsString(from["emailAddress"], "address");
    }

    // Pydantic-v2-style validation error entry.
    nlohmann::json ValidationEntry(const std::string &type, const nlohmann::json &loc,
                                   const std::string &msg, const nlohmann::json &input,
                                   const nlohmann::json &ctx = nullptr)
    { nlohmann::json entry{{"type", type}, {"loc", loc}, {"msg", msg}, {"input", input}};
      if (!ctx.is_null())
      { entry["ctx"] = ctx;
      }
      return entry;
    }
  } // namespace

  // #R620: Resolve the caller-facing write-token header name (env-overridable).
  std::string WriteTokenHeaderName()
  { const char *raw = std::getenv("MAILCART_API_WRITE_TOKEN_HEADER");
    if (raw != nullptr && raw[0] != '\0')
    { return raw;
    }
    return "X-Teller-Write-Token";
  }

  // #R620: Normalize configured/caller write tokens by trimming and stripping optional Bearer prefixes.
  std::string NormalizedWriteToken(const std::optional<std::string> &token_value)
  { std::string normalized = Strip(token_value.value_or(""));
    if (AsciiLower(normalized).rfind("bearer ", 0) == 0)
    { return Strip(normalized.substr(7));
    }
    return normalized;
  }

  // #R620: Resolve the configured caller write-token from supported environment keys.
  std::string ConfiguredWriteToken()
  { for (const char *env_name : kWriteTokenEnvVars)
    { const char *raw = std::getenv(env_name);
      const std::string value = NormalizedWriteToken(raw == nullptr ? std::optional<std::string>() : std::optional<std::string>(raw));
      if (!value.empty())
      { return value;
      }
    }
    return "";
  }

  // #R620: Validate caller-provided write-token using constant-time comparison.
  bool IsValidWriteToken(const std::optional<std::string> &provided_token)
  { const std::string configured_token = ConfiguredWriteToken();
    if (configured_token.empty())
    { return false;
    }
    const std::string candidate = NormalizedWriteToken(provided_token);
    return !candidate.empty() && ConstantTimeEquals(candidate, configured_token);
  }

  MailcartApi::MailcartApi(GraphClient &graph)
    : graph_(graph)
  {
  }

  // #R620: Require caller-facing write-token auth for all message API routes.
  void MailcartApi::RequireApiWriteToken(const std::optional<std::string> &provided_token,
                                         const std::optional<std::string> &authorization_header) const
  { std::string candidate_token = Strip(provided_token.value_or(""));
    if (candidate_token.empty())
    { candidate_token = Strip(authorization_header.value_or(""));
    }
    if (ConfiguredWriteToken().empty())
    { throw ApiError(503,
                     "Mailcart API write token is not configured. Set MAILCART_API_WRITE_TOKEN "
                     "or TELLER_CLASSIFIER_WRITE_TOKEN (CLASSY_WRITE_TOKEN is also accepted).");
    }
    if (!IsValidWriteToken(candidate_token))
    { throw ApiError(401, "Unauthorized", {{"WWW-Authenticate", WriteTokenHeaderName()}});
    }
  }

  // #R029: Expose token metadata only to authenticated callers on the health endpoint.
  nlohmann::json MailcartApi::Health(const std::optional<std::string> &provided_token)
  { nlohmann::json status{{"status", "ok"}};
    if (IsValidWriteToken(provided_token))
    { for (const auto &[key, value] : graph_.tokenManager().TokenStatus())
      { status[key] = value;
      }
    }
    return status;
  }

  // #R020: Return recent messages for empty query; otherwise apply scoped filtering with caller limit.
  nlohmann::json MailcartApi::SearchMessages(const std::string &query, int limit)
  { SearchCriteria criteria;
    try
    { criteria = ParseScopedQuery(query);
    }
    catch (const ApiError &exc)
    { if (exc.status() == 400)
      { return nlohmann::json{{"messages", nlohmann::json::array()}};
      }
      throw;
    }
    const std::string normalized_query = Strip(query);
    QueryParams graph_params{
        {"$select", "id,subject,bodyPreview,body,receivedDateTime,from"},
        {"$orderby", "receivedDateTime DESC"},
        {"$top", std::to_string(normalized_query.empty() ? std::max(limit, 50) : std::max(limit * 8, 200))},
    };
    std::vector<std::string> graph_filters;
    if (criteria.from_date.has_value())
    { graph_filters.push_back("receivedDateTime ge " + criteria.from_date->Iso() + "T00:00:00Z");
    }
    if (criteria.to_date.has_value())
    { graph_filters.push_back("receivedDateTime le " + criteria.to_date->Iso() + "T23:59:59Z");
    }
    if (!graph_filters.empty())
    { std::string joined;
      for (const auto &filter : graph_filters)
      { if (!joined.empty())
        { joined += " and ";
        }
        joined += filter;
      }
      graph_params.emplace_back("$filter", joined);
    }
    //R030: Surface Graph auth failures explicitly instead of swallowing them as empty results.
    nlohmann::json payload = graph_.Get("/me/messages", graph_params);
    nlohmann::json messages = nlohmann::json::array();
    //R050: Construct the Aho-Corasick matcher once per request and reuse it for every scanned message.
    const AhoCorasick criteria_matcher = BuildCriteriaMatcher(criteria);
    const bool should_paginate = criteria.from_date.has_value() || criteria.to_date.has_value();
    const int max_scanned_rows = should_paginate ? std::max(limit * 100, 2000) : std::max(limit * 8, 200);
    int scanned_rows = 0;
    while (true)
    { nlohmann::json page_rows = nlohmann::json::array();
      if (payload.is_object() && payload.contains("value") && payload["value"].is_array())
      { page_rows = payload["value"];
      }
      std::optional<CivilDate> oldest_received_on_page;
      for (const auto &row : page_rows)
      { if (!row.is_object())
        { continue;
        }
        ++scanned_rows;
        const auto received_at_date = ParseReceivedAtDate(JsonFieldAsString(row, "receivedDateTime"));
        if (received_at_date.has_value())
        { if (!oldest_received_on_page.has_value() || *received_at_date < *oldest_received_on_page)
          { oldest_received_on_page = received_at_date;
          }
        }
        const std::string subject = JsonFieldAsString(row, "subject");
        const std::string preview = JsonFieldAsString(row, "bodyPreview");
        const std::string sender = SenderAddress(row);
        const std::string body_text = ExtractBodyText(row);
        if (!normalized_query.empty() && !MessageMatchesCriteria(row, criteria, &criteria_matcher))
        { continue;
        }
        messages.push_back(nlohmann::json{
            {"message_id", JsonFieldAsString(row, "id")},
            {"subject", subject},
            {"preview", preview},
            {"received_at", JsonFieldAsString(row, "receivedDateTime")},
            {"sender", sender},
            {"body_text", body_text},
        });
        if (static_cast<int>(messages.size()) >= limit)
        { break;
        }
      }
      if (static_cast<int>(messages.size()) >= limit || normalized_query.empty())
      { break;
      }
      if (!should_paginate)
      { break;
      }
      if (scanned_rows >= max_scanned_rows)
      { break;
      }
      if (criteria.from_date.has_value() && oldest_received_on_page.has_value() &&
          *oldest_received_on_page < *criteria.from_date)
      { break;
      }
      std::string next_link;
      if (payload.is_object() && payload.contains("@odata.nextLink") && payload["@odata.nextLink"].is_string())
      { next_link = payload["@odata.nextLink"].get<std::string>();
      }
      if (next_link.empty())
      { break;
      }
      payload = graph_.GetNextLink(next_link);
    }
    return nlohmann::json{{"messages", messages}};
  }

  // #R035: Return a single message with subject, sender, recipients, body, and preview metadata.
  nlohmann::json MailcartApi::GetMessage(const std::string &message_id)
  { const std::string normalized_message_id = ValidatedGraphMessageId(message_id);
    nlohmann::json payload;
    try
    { payload = graph_.Get(
          GraphMessagePath(normalized_message_id),
          {{"$select", "id,subject,bodyPreview,body,from,toRecipients,receivedDateTime"}});
    }
    catch (const ApiError &exc)
    { if (exc.status() == 502 && exc.detail().find("ErrorInvalidIdMalformed") != std::string::npos)
      { throw ApiError(404, "message not found");
      }
      throw;
    }
    const std::string sender = SenderAddress(payload);
    std::string recipients;
    if (payload.is_object() && payload.contains("toRecipients") && payload["toRecipients"].is_array())
    { for (const auto &row : payload["toRecipients"])
      { if (!row.is_object())
        { continue;
        }
        std::string address;
        if (row.contains("emailAddress") && row["emailAddress"].is_object())
        { address = JsonFieldAsString(row["emailAddress"], "address");
        }
        if (!address.empty())
        { if (!recipients.empty())
          { recipients.push_back(',');
          }
          recipients += address;
        }
      }
    }
    std::string body_content_type;
    std::string body_content;
    if (payload.is_object() && payload.contains("body") && payload["body"].is_object())
    { body_content_type = AsciiLower(JsonFieldAsString(payload["body"], "contentType"));
      body_content = JsonFieldAsString(payload["body"], "content");
    }
    const std::string html_body = body_content_type == "html" ? body_content : "";
    const std::string text_body = body_content_type == "text" ? body_content : "";
    const std::string resolved_id =
        payload.is_object() && payload.contains("id") ? JsonFieldAsString(payload, "id") : message_id;
    return nlohmann::json{
        {"message_id", resolved_id},
        {"subject", JsonFieldAsString(payload, "subject")},
        {"preview", JsonFieldAsString(payload, "bodyPreview")},
        {"received_at", JsonFieldAsString(payload, "receivedDateTime")},
        {"sender", sender},
        {"recipients", recipients},
        {"html_body", html_body},
        {"text_body", text_body},
        {"body_text", text_body.empty() ? html_body : text_body},
    };
  }

  // #R025: Move selected message into requested destination folder.
  nlohmann::json MailcartApi::MoveMessage(const std::string &message_id, const std::string &folder_name)
  { const std::string normalized_message_id = ValidatedGraphMessageId(message_id);
    const std::string folder_id = graph_.GetOrCreateFolderId(folder_name);
    nlohmann::json response;
    try
    { response = graph_.Post(GraphMessagePath(normalized_message_id) + "/move",
                             nlohmann::json{{"destinationId", folder_id}});
    }
    catch (const ApiError &exc)
    { if (exc.status() == 502 && exc.detail().find("ErrorInvalidIdMalformed") != std::string::npos)
      { throw ApiError(404, "message not found");
      }
      throw;
    }
    std::string result_id;
    if (response.is_object() && response.contains("id"))
    { result_id = JsonFieldAsString(response, "id");
    }
    return nlohmann::json{{"moved", true}, {"folder_id", folder_id}, {"result_id", result_id}};
  }

  namespace
  {
    std::optional<std::string> HeaderValue(const ApiRequest &request, const std::string &name)
    { const auto found = request.headers.find(AsciiLower(name));
      if (found == request.headers.end())
      { return std::nullopt;
      }
      return found->second;
    }

    std::optional<std::string> QueryValue(const ApiRequest &request, const std::string &name)
    { for (const auto &[key, value] : request.query_params)
      { if (key == name)
        { return value;
        }
      }
      return std::nullopt;
    }

    // #R020: Validate search query/limit params, mirroring FastAPI's 422 envelopes.
    void ValidateSearchParams(const ApiRequest &request, std::string &query, int &limit)
    { nlohmann::json errors = nlohmann::json::array();
      const auto query_value = QueryValue(request, "query");
      query = query_value.value_or("");
      if (query.size() > 400)
      { errors.push_back(ValidationEntry("string_too_long", nlohmann::json::array({"query", "query"}),
                                         "String should have at most 400 characters", query,
                                         nlohmann::json{{"max_length", 400}}));
      }
      limit = 50;
      const auto limit_value = QueryValue(request, "limit");
      if (limit_value.has_value())
      { const std::string trimmed = Strip(*limit_value);
        bool numeric = !trimmed.empty();
        size_t start = trimmed.size() > 0 && (trimmed[0] == '-' || trimmed[0] == '+') ? 1 : 0;
        if (start >= trimmed.size())
        { numeric = false;
        }
        for (size_t index = start; numeric && index < trimmed.size(); ++index)
        { if (std::isdigit(static_cast<unsigned char>(trimmed[index])) == 0)
          { numeric = false;
          }
        }
        if (!numeric)
        { errors.push_back(ValidationEntry(
              "int_parsing", nlohmann::json::array({"query", "limit"}),
              "Input should be a valid integer, unable to parse string as an integer", *limit_value));
        }
        else
        { long long parsed = 0;
          try
          { parsed = std::stoll(trimmed);
          }
          catch (const std::exception &)
          { parsed = trimmed[0] == '-' ? -1000000000LL : 1000000000LL;
          }
          if (parsed < 1)
          { errors.push_back(ValidationEntry("greater_than_equal", nlohmann::json::array({"query", "limit"}),
                                             "Input should be greater than or equal to 1", *limit_value,
                                             nlohmann::json{{"ge", 1}}));
          }
          else if (parsed > 100)
          { errors.push_back(ValidationEntry("less_than_equal", nlohmann::json::array({"query", "limit"}),
                                             "Input should be less than or equal to 100", *limit_value,
                                             nlohmann::json{{"le", 100}}));
          }
          else
          { limit = static_cast<int>(parsed);
          }
        }
      }
      if (!errors.empty())
      { throw ApiValidationError(errors);
      }
    }

    // #R025: Validate the move request body, mirroring FastAPI/pydantic 422 envelopes.
    std::string ValidateMoveBody(const ApiRequest &request)
    { nlohmann::json errors = nlohmann::json::array();
      if (!request.has_body || Strip(request.body).empty())
      { errors.push_back(ValidationEntry("missing", nlohmann::json::array({"body"}), "Field required", nullptr));
        throw ApiValidationError(errors);
      }
      nlohmann::json body = nlohmann::json::parse(request.body, nullptr, false);
      if (body.is_discarded())
      { errors.push_back(ValidationEntry("json_invalid", nlohmann::json::array({"body", 0}),
                                         "JSON decode error", nlohmann::json::object(),
                                         nlohmann::json{{"error", "Invalid JSON"}}));
        throw ApiValidationError(errors);
      }
      if (!body.is_object())
      { errors.push_back(ValidationEntry("model_attributes_type", nlohmann::json::array({"body"}),
                                         "Input should be a valid dictionary or object to extract fields from",
                                         body));
        throw ApiValidationError(errors);
      }
      std::string folder_name = "matchy";
      if (body.contains("folder_name"))
      { const auto &value = body["folder_name"];
        if (!value.is_string())
        { errors.push_back(ValidationEntry("string_type", nlohmann::json::array({"body", "folder_name"}),
                                           "Input should be a valid string", value));
          throw ApiValidationError(errors);
        }
        folder_name = value.get<std::string>();
        if (folder_name.empty())
        { errors.push_back(ValidationEntry("string_too_short", nlohmann::json::array({"body", "folder_name"}),
                                           "String should have at least 1 character", folder_name,
                                           nlohmann::json{{"min_length", 1}}));
          throw ApiValidationError(errors);
        }
        if (folder_name.size() > 120)
        { errors.push_back(ValidationEntry("string_too_long", nlohmann::json::array({"body", "folder_name"}),
                                           "String should have at most 120 characters", folder_name,
                                           nlohmann::json{{"max_length", 120}}));
          throw ApiValidationError(errors);
        }
      }
      return folder_name;
    }

    ApiResult JsonResult(int status, nlohmann::json body, std::map<std::string, std::string> headers = {})
    { ApiResult result;
      result.status = status;
      result.body = std::move(body);
      result.headers = std::move(headers);
      return result;
    }
  } // namespace

  // FastAPI-equivalent request dispatch: routing, auth, validation, endpoint invocation, error mapping.
  ApiResult HandleApiRequest(MailcartApi &api, const ApiRequest &request)
  { try
    { const std::string write_token_header = AsciiLower(WriteTokenHeaderName());
      const auto provided_token = HeaderValue(request, write_token_header);
      const auto authorization = HeaderValue(request, "authorization");

      if (request.path == "/health")
      { if (request.method != "GET")
        { return JsonResult(405, nlohmann::json{{"detail", "Method Not Allowed"}}, {{"Allow", "GET"}});
        }
        return JsonResult(200, api.Health(provided_token));
      }

      if (request.path == "/v1/messages/search")
      { if (request.method != "GET")
        { return JsonResult(405, nlohmann::json{{"detail", "Method Not Allowed"}}, {{"Allow", "GET"}});
        }
        api.RequireApiWriteToken(provided_token, authorization);
        std::string query;
        int limit = 50;
        ValidateSearchParams(request, query, limit);
        return JsonResult(200, api.SearchMessages(query, limit));
      }

      const std::string messages_prefix = "/v1/messages/";
      if (request.path.rfind(messages_prefix, 0) == 0)
      { std::string remainder = request.path.substr(messages_prefix.size());
        const std::string move_suffix = "/move";
        const bool is_move = remainder.size() > move_suffix.size() &&
                             remainder.compare(remainder.size() - move_suffix.size(),
                                               move_suffix.size(), move_suffix) == 0;
        if (is_move)
        { remainder = remainder.substr(0, remainder.size() - move_suffix.size());
        }
        // FastAPI path params do not span path separators; nested paths are 404.
        if (remainder.empty() || remainder.find('/') != std::string::npos)
        { return JsonResult(404, nlohmann::json{{"detail", "Not Found"}});
        }
        if (is_move)
        { if (request.method != "POST")
          { return JsonResult(405, nlohmann::json{{"detail", "Method Not Allowed"}}, {{"Allow", "POST"}});
          }
          api.RequireApiWriteToken(provided_token, authorization);
          const std::string folder_name = ValidateMoveBody(request);
          return JsonResult(200, api.MoveMessage(remainder, folder_name));
        }
        if (request.method != "GET")
        { return JsonResult(405, nlohmann::json{{"detail", "Method Not Allowed"}}, {{"Allow", "GET"}});
        }
        api.RequireApiWriteToken(provided_token, authorization);
        return JsonResult(200, api.GetMessage(remainder));
      }

      return JsonResult(404, nlohmann::json{{"detail", "Not Found"}});
    }
    catch (const ApiValidationError &exc)
    { return JsonResult(422, nlohmann::json{{"detail", exc.errors()}});
    }
    catch (const ApiError &exc)
    { return JsonResult(exc.status(), nlohmann::json{{"detail", exc.detail()}}, exc.headers());
    }
    catch (const std::exception &)
    { return JsonResult(500, nlohmann::json{{"detail", "Internal Server Error"}});
    }
  }
} // namespace mailcartcore
