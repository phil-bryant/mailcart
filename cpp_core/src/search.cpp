#include "mailcartcore/search.hpp"

#include <algorithm>
#include <cctype>
#include <deque>
#include <regex>

#include "mailcartcore/api_error.hpp"

namespace mailcartcore
{
  namespace
  {
    // #R020: Mirror str(message.get(key, "")) semantics for JSON fields.
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

    std::string AsciiLower(std::string value)
    { std::transform(value.begin(), value.end(), value.begin(),
                     [](unsigned char symbol) { return static_cast<char>(std::tolower(symbol)); });
      return value;
    }

    bool IsSpace(char symbol)
    { return std::isspace(static_cast<unsigned char>(symbol)) != 0;
    }

    std::string Strip(const std::string &value)
    { size_t begin = 0;
      size_t end = value.size();
      while (begin < end && IsSpace(value[begin]))
      { ++begin;
      }
      while (end > begin && IsSpace(value[end - 1]))
      { --end;
      }
      return value.substr(begin, end - begin);
    }

    bool IsLeapYear(int year)
    { return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    }

    int DaysInMonth(int year, int month)
    { static constexpr int kDays[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
      if (month == 2 && IsLeapYear(year))
      { return 29;
      }
      return kDays[month - 1];
    }

    bool AllDigits(const std::string &value)
    { return !value.empty() &&
             std::all_of(value.begin(), value.end(),
                         [](unsigned char symbol) { return std::isdigit(symbol) != 0; });
    }

    // Validate calendar fields, mirroring datetime.date error messages.
    std::optional<CivilDate> MakeDate(int year, int month, int day, std::string *error)
    { if (month < 1 || month > 12)
      { if (error != nullptr)
        { *error = "month must be in 1..12";
        }
        return std::nullopt;
      }
      if (day < 1 || day > DaysInMonth(year, month))
      { if (error != nullptr)
        { *error = "day is out of range for month";
        }
        return std::nullopt;
      }
      return CivilDate{year, month, day};
    }

    // #R020: Replace HTML entities with their literal characters (common subset plus numeric forms).
    std::string UnescapeHtml(const std::string &value)
    { std::string output;
      output.reserve(value.size());
      size_t index = 0;
      while (index < value.size())
      { if (value[index] != '&')
        { output.push_back(value[index]);
          ++index;
          continue;
        }
        const size_t semicolon = value.find(';', index + 1);
        if (semicolon == std::string::npos || semicolon - index > 12)
        { output.push_back(value[index]);
          ++index;
          continue;
        }
        const std::string entity = value.substr(index + 1, semicolon - index - 1);
        std::string replacement;
        bool recognized = true;
        if (entity == "amp")
        { replacement = "&";
        }
        else if (entity == "lt")
        { replacement = "<";
        }
        else if (entity == "gt")
        { replacement = ">";
        }
        else if (entity == "quot")
        { replacement = "\"";
        }
        else if (entity == "apos" || entity == "#39")
        { replacement = "'";
        }
        else if (entity == "nbsp" || entity == "#160")
        { replacement = "\xC2\xA0";
        }
        else if (entity.size() >= 2 && entity[0] == '#')
        { long code = -1;
          try
          { if (entity[1] == 'x' || entity[1] == 'X')
            { code = std::stol(entity.substr(2), nullptr, 16);
            }
            else
            { code = std::stol(entity.substr(1), nullptr, 10);
            }
          }
          catch (const std::exception &)
          { code = -1;
          }
          if (code >= 0 && code <= 0x10FFFF)
          { // Encode the code point as UTF-8.
            if (code < 0x80)
            { replacement.push_back(static_cast<char>(code));
            }
            else if (code < 0x800)
            { replacement.push_back(static_cast<char>(0xC0 | (code >> 6)));
              replacement.push_back(static_cast<char>(0x80 | (code & 0x3F)));
            }
            else if (code < 0x10000)
            { replacement.push_back(static_cast<char>(0xE0 | (code >> 12)));
              replacement.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
              replacement.push_back(static_cast<char>(0x80 | (code & 0x3F)));
            }
            else
            { replacement.push_back(static_cast<char>(0xF0 | (code >> 18)));
              replacement.push_back(static_cast<char>(0x80 | ((code >> 12) & 0x3F)));
              replacement.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
              replacement.push_back(static_cast<char>(0x80 | (code & 0x3F)));
            }
          }
          else
          { recognized = false;
          }
        }
        else
        { recognized = false;
        }
        if (recognized)
        { output += replacement;
          index = semicolon + 1;
        }
        else
        { output.push_back(value[index]);
          ++index;
        }
      }
      return output;
    }

    // Case-insensitive comparison of a fragment at a position.
    bool MatchesIgnoreCase(const std::string &text, size_t position, const std::string &fragment)
    { if (position + fragment.size() > text.size())
      { return false;
      }
      for (size_t offset = 0; offset < fragment.size(); ++offset)
      { if (std::tolower(static_cast<unsigned char>(text[position + offset])) !=
            std::tolower(static_cast<unsigned char>(fragment[offset])))
        { return false;
        }
      }
      return true;
    }
  } // namespace

  std::string CivilDate::Iso() const
  { char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d", year, month, day);
    return buffer;
  }

  // #R020: Enforce strict yyyy-mm-dd parsing for from:/to: scoped filters.
  std::optional<CivilDate> ParseIsoDate(const std::string &value)
  { if (value.size() != 10 || value[4] != '-' || value[7] != '-')
    { return std::nullopt;
    }
    const std::string year_text = value.substr(0, 4);
    const std::string month_text = value.substr(5, 2);
    const std::string day_text = value.substr(8, 2);
    if (!AllDigits(year_text) || !AllDigits(month_text) || !AllDigits(day_text))
    { return std::nullopt;
    }
    return MakeDate(std::stoi(year_text), std::stoi(month_text), std::stoi(day_text), nullptr);
  }

  // #R610: Leniently parse message receivedDateTime (ISO-8601, trailing Z) to a date.
  std::optional<CivilDate> ParseReceivedAtDate(const std::string &value)
  { if (value.empty())
    { return std::nullopt;
    }
    if (value.size() < 10 || value[4] != '-' || value[7] != '-')
    { return std::nullopt;
    }
    const std::string year_text = value.substr(0, 4);
    const std::string month_text = value.substr(5, 2);
    const std::string day_text = value.substr(8, 2);
    if (!AllDigits(year_text) || !AllDigits(month_text) || !AllDigits(day_text))
    { return std::nullopt;
    }
    if (value.size() > 10)
    { // Require a date/time separator and a minimally plausible time component,
      // mirroring datetime.fromisoformat's acceptance after Z-normalization.
      const char separator = value[10];
      if (separator != 'T' && separator != ' ')
      { return std::nullopt;
      }
      const std::string remainder = value.substr(11);
      if (remainder.size() < 5 || !std::isdigit(static_cast<unsigned char>(remainder[0])))
      { return std::nullopt;
      }
    }
    return MakeDate(std::stoi(year_text), std::stoi(month_text), std::stoi(day_text), nullptr);
  }

  // #R020: Normalize scoped search text by trimming, collapsing whitespace, and case-folding.
  std::string NormalizeSearchText(const std::string &value)
  { const std::string stripped = Strip(value);
    std::string collapsed;
    collapsed.reserve(stripped.size());
    bool in_whitespace = false;
    for (char symbol : stripped)
    { if (IsSpace(symbol))
      { in_whitespace = true;
        continue;
      }
      if (in_whitespace)
      { collapsed.push_back(' ');
        in_whitespace = false;
      }
      collapsed.push_back(symbol);
    }
    return AsciiLower(collapsed);
  }

  // #R020: Convert HTML body payloads to plain searchable text before normalization.
  std::string StripHtml(const std::string &value)
  { // Pass 1: drop <script>/<style> blocks including their content.
    std::string without_blocks;
    without_blocks.reserve(value.size());
    size_t index = 0;
    while (index < value.size())
    { bool replaced = false;
      if (value[index] == '<')
      { for (const std::string &tag : {std::string("script"), std::string("style")})
        { if (MatchesIgnoreCase(value, index + 1, tag))
          { const size_t after_name = index + 1 + tag.size();
            // Mirror `\b`: the tag name must end at a non-word character.
            if (after_name < value.size() &&
                (std::isalnum(static_cast<unsigned char>(value[after_name])) != 0 || value[after_name] == '_'))
            { continue;
            }
            // Opening tag must close with '>' without an intervening '>': [^>]*>
            const size_t open_close = value.find('>', after_name);
            if (open_close == std::string::npos)
            { continue;
            }
            const std::string closing = "</" + tag + ">";
            size_t close_at = std::string::npos;
            for (size_t probe = open_close + 1; probe + closing.size() <= value.size(); ++probe)
            { if (MatchesIgnoreCase(value, probe, closing))
              { close_at = probe;
                break;
              }
            }
            if (close_at == std::string::npos)
            { continue;
            }
            without_blocks.push_back(' ');
            index = close_at + closing.size();
            replaced = true;
            break;
          }
        }
      }
      if (!replaced)
      { without_blocks.push_back(value[index]);
        ++index;
      }
    }

    // Pass 2: replace remaining tags `<[^>]+>` with spaces.
    std::string without_tags;
    without_tags.reserve(without_blocks.size());
    index = 0;
    while (index < without_blocks.size())
    { if (without_blocks[index] == '<')
      { const size_t close = without_blocks.find('>', index + 1);
        if (close != std::string::npos && close > index + 1)
        { without_tags.push_back(' ');
          index = close + 1;
          continue;
        }
      }
      without_tags.push_back(without_blocks[index]);
      ++index;
    }

    return UnescapeHtml(without_tags);
  }

  // #R020: Evaluate body: tokens against full body content when available.
  std::string ExtractBodyText(const nlohmann::json &message)
  { if (!message.is_object())
    { return "";
    }
    const auto body_iterator = message.find("body");
    if (body_iterator == message.end() || !body_iterator->is_object())
    { return JsonFieldAsString(message, "bodyPreview");
    }
    const std::string content = JsonFieldAsString(*body_iterator, "content");
    const std::string content_type = AsciiLower(JsonFieldAsString(*body_iterator, "contentType"));
    if (content_type == "html")
    { return StripHtml(content);
    }
    if (content_type == "text")
    { return content;
    }
    return JsonFieldAsString(message, "bodyPreview");
  }

  // #R020: Parse scoped search tokens and reject unsupported/unprefixed token text.
  SearchCriteria ParseScopedQuery(const std::string &query)
  { SearchCriteria criteria;
    const std::string normalized_query = Strip(query);
    if (normalized_query.empty())
    { return criteria;
    }
    static const std::regex kTokenPattern(R"(\b(subject|sender|body|from|to)\s*:)",
                                          std::regex::icase);
    std::vector<std::pair<size_t, std::pair<size_t, std::string>>> matches; // start -> (end, token)
    for (auto iterator = std::sregex_iterator(normalized_query.begin(), normalized_query.end(), kTokenPattern);
         iterator != std::sregex_iterator(); ++iterator)
    { const auto &match = *iterator;
      matches.emplace_back(static_cast<size_t>(match.position(0)),
                           std::make_pair(static_cast<size_t>(match.position(0) + match.length(0)),
                                          AsciiLower(match.str(1))));
    }
    if (matches.empty())
    { throw ApiError(400, "Invalid query: use scoped tokens subject:, sender:, body:, from:, or to:.");
    }
    size_t cursor = 0;
    for (size_t index = 0; index < matches.size(); ++index)
    { const size_t match_start = matches[index].first;
      const size_t match_end = matches[index].second.first;
      const std::string &token = matches[index].second.second;
      const std::string prefix_region = normalized_query.substr(cursor, match_start - cursor);
      if (!Strip(prefix_region).empty())
      { throw ApiError(400, "Invalid query: unsupported or unscoped token content detected.");
      }
      const size_t value_end =
          index + 1 < matches.size() ? matches[index + 1].first : normalized_query.size();
      const std::string raw_value = Strip(normalized_query.substr(match_end, value_end - match_end));
      if (raw_value.empty())
      { throw ApiError(400, "Invalid query: " + token + ": requires a value.");
      }
      if (token == "subject" || token == "sender" || token == "body")
      { const std::string normalized_value = NormalizeSearchText(raw_value);
        if (normalized_value.empty())
        { throw ApiError(400, "Invalid query: " + token + ": requires text.");
        }
        if (token == "subject")
        { criteria.subject.push_back(normalized_value);
        }
        else if (token == "sender")
        { criteria.sender.push_back(normalized_value);
        }
        else
        { criteria.body.push_back(normalized_value);
        }
      }
      else if (token == "from")
      { if (criteria.from_date.has_value())
        { throw ApiError(400, "Invalid query: duplicate from: token.");
        }
        const auto parsed = ParseIsoDate(raw_value);
        if (!parsed.has_value())
        { throw ApiError(400, "Invalid query: from: date must use yyyy-mm-dd");
        }
        criteria.from_date = parsed;
      }
      else
      { // token == "to"
        if (criteria.to_date.has_value())
        { throw ApiError(400, "Invalid query: duplicate to: token.");
        }
        const auto parsed = ParseIsoDate(raw_value);
        if (!parsed.has_value())
        { throw ApiError(400, "Invalid query: to: date must use yyyy-mm-dd");
        }
        criteria.to_date = parsed;
      }
      cursor = value_end;
    }
    if (!Strip(normalized_query.substr(cursor)).empty())
    { throw ApiError(400, "Invalid query: unsupported or unscoped token content detected.");
    }
    if (criteria.from_date.has_value() && criteria.to_date.has_value() &&
        *criteria.from_date > *criteria.to_date)
    { throw ApiError(400, "Invalid query: from: date cannot be after to: date.");
    }
    return criteria;
  }

  // #R050: Initialize matcher trie state and register all non-empty scoped patterns.
  AhoCorasick::AhoCorasick(const std::vector<std::string> &patterns)
  { goto_.emplace_back();
    fail_.push_back(0);
    output_.emplace_back();
    for (const auto &pattern : patterns)
    { if (!pattern.empty())
      { AddPattern(pattern);
      }
    }
    BuildFailureLinks();
  }

  // #R050: Add one pattern to the trie, allocating transition nodes as needed.
  void AhoCorasick::AddPattern(const std::string &pattern)
  { int node = 0;
    for (char symbol : pattern)
    { auto found = goto_[node].find(symbol);
      int next_node;
      if (found == goto_[node].end())
      { next_node = static_cast<int>(goto_.size());
        goto_.emplace_back();
        fail_.push_back(0);
        output_.emplace_back();
        goto_[node][symbol] = next_node;
      }
      else
      { next_node = found->second;
      }
      node = next_node;
    }
    output_[node].insert(pattern);
  }

  // #R050: Build failure transitions so one-pass matching supports overlap/fallback.
  void AhoCorasick::BuildFailureLinks()
  { std::deque<int> queue;
    for (const auto &[symbol, next_node] : goto_[0])
    { (void)symbol;
      queue.push_back(next_node);
    }
    while (!queue.empty())
    { const int node = queue.front();
      queue.pop_front();
      for (const auto &[symbol, next_node] : goto_[node])
      { queue.push_back(next_node);
        int fail_node = fail_[node];
        while (fail_node != 0 && goto_[fail_node].find(symbol) == goto_[fail_node].end())
        { fail_node = fail_[fail_node];
        }
        const auto target_iterator = goto_[fail_node].find(symbol);
        const int target = target_iterator == goto_[fail_node].end() ? 0 : target_iterator->second;
        fail_[next_node] = target;
        output_[next_node].insert(output_[target].begin(), output_[target].end());
      }
    }
  }

  // #R050: Return the set of patterns occurring as substrings of text in a single pass.
  std::set<std::string> AhoCorasick::Search(const std::string &text) const
  { std::set<std::string> found;
    int node = 0;
    for (char symbol : text)
    { while (node != 0 && goto_[node].find(symbol) == goto_[node].end())
      { node = fail_[node];
      }
      const auto next_iterator = goto_[node].find(symbol);
      node = next_iterator == goto_[node].end() ? 0 : next_iterator->second;
      found.insert(output_[node].begin(), output_[node].end());
    }
    return found;
  }

  // #R050: Build one Aho-Corasick matcher over the union of scoped text filters.
  AhoCorasick BuildCriteriaMatcher(const SearchCriteria &criteria)
  { std::set<std::string> patterns;
    for (const auto *field : {&criteria.subject, &criteria.sender, &criteria.body})
    { for (const auto &value : *field)
      { if (!value.empty())
        { patterns.insert(value);
        }
      }
    }
    return AhoCorasick(std::vector<std::string>(patterns.begin(), patterns.end()));
  }

  // #R020: Apply AND semantics across scoped text and inclusive date range filters.
  bool MessageMatchesCriteria(const nlohmann::json &message, const SearchCriteria &criteria,
                              const AhoCorasick *matcher)
  { std::optional<AhoCorasick> local_matcher;
    if (matcher == nullptr)
    { local_matcher.emplace(BuildCriteriaMatcher(criteria));
      matcher = &*local_matcher;
    }
    const std::string subject = NormalizeSearchText(JsonFieldAsString(message, "subject"));
    std::string sender_address;
    if (message.is_object() && message.contains("from") && message["from"].is_object())
    { const auto &from = message["from"];
      if (from.contains("emailAddress") && from["emailAddress"].is_object())
      { sender_address = JsonFieldAsString(from["emailAddress"], "address");
      }
    }
    const std::string sender = NormalizeSearchText(sender_address);
    const std::string body_text = NormalizeSearchText(ExtractBodyText(message));

    const auto subject_hits = matcher->Search(subject);
    const auto sender_hits = matcher->Search(sender);
    const auto body_hits = matcher->Search(body_text);

    bool matches = true;
    for (const auto &token : criteria.subject)
    { if (subject_hits.find(token) == subject_hits.end())
      { matches = false;
      }
    }
    for (const auto &token : criteria.sender)
    { if (sender_hits.find(token) == sender_hits.end())
      { matches = false;
      }
    }
    for (const auto &token : criteria.body)
    { if (body_hits.find(token) == body_hits.end())
      { matches = false;
      }
    }
    const auto received_at = ParseReceivedAtDate(JsonFieldAsString(message, "receivedDateTime"));
    if (criteria.from_date.has_value())
    { if (!received_at.has_value() || *received_at < *criteria.from_date)
      { matches = false;
      }
    }
    if (criteria.to_date.has_value())
    { if (!received_at.has_value() || *received_at > *criteria.to_date)
      { matches = false;
      }
    }
    return matches;
  }
} // namespace mailcartcore
