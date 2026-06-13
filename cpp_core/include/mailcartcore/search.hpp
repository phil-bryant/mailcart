#pragma once
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

// Port of the scoped-search subset of scripts/matchy_mailcart_api.py:
// query parsing, text normalization, HTML stripping, date filters, and the
// Aho-Corasick matcher used for one-pass multi-pattern substring search.
namespace mailcartcore
{
  // Calendar date used by from:/to: filters (no timezone semantics).
  struct CivilDate
  { int year = 0;
    int month = 0;
    int day = 0;

    [[nodiscard]] auto operator<=>(const CivilDate &) const = default;
    [[nodiscard]] std::string Iso() const;
  };

  // #R020: Enforce strict yyyy-mm-dd parsing for from:/to: scoped filters; nullopt on invalid input.
  [[nodiscard]] std::optional<CivilDate> ParseIsoDate(const std::string &value);

  // #R610: Leniently parse message receivedDateTime (ISO-8601, trailing Z) to a date; nullopt when absent/unparseable.
  [[nodiscard]] std::optional<CivilDate> ParseReceivedAtDate(const std::string &value);

  // #R020: Normalize scoped search text by trimming, collapsing whitespace, and case-folding (ASCII).
  [[nodiscard]] std::string NormalizeSearchText(const std::string &value);

  // #R020: Convert HTML body payloads to plain searchable text before normalization.
  [[nodiscard]] std::string StripHtml(const std::string &value);

  // #R020: Evaluate body: tokens against full body content when available.
  [[nodiscard]] std::string ExtractBodyText(const nlohmann::json &message);

  struct SearchCriteria
  { std::vector<std::string> subject;
    std::vector<std::string> sender;
    std::vector<std::string> body;
    std::optional<CivilDate> from_date;
    std::optional<CivilDate> to_date;
  };

  // #R020: Parse scoped search tokens and reject unsupported/unprefixed token text (throws ApiError 400).
  [[nodiscard]] SearchCriteria ParseScopedQuery(const std::string &query);

  // #R050: Aho-Corasick automaton: keyword trie with failure links so one linear
  // pass over a message field reports every scoped filter that occurs as a substring.
  class AhoCorasick
  { public:
    // #R050: Initialize matcher trie state and register all non-empty scoped patterns.
    explicit AhoCorasick(const std::vector<std::string> &patterns);

    // #R050: Return the set of patterns occurring as substrings of text in a single pass.
    [[nodiscard]] std::set<std::string> Search(const std::string &text) const;

    private:
    void AddPattern(const std::string &pattern);
    void BuildFailureLinks();

    std::vector<std::map<char, int>> goto_;
    std::vector<int> fail_;
    std::vector<std::set<std::string>> output_;
  };

  // #R050: Build one Aho-Corasick matcher over the union of scoped text filters.
  [[nodiscard]] AhoCorasick BuildCriteriaMatcher(const SearchCriteria &criteria);

  // #R020: Apply AND semantics across scoped text and inclusive date range filters.
  [[nodiscard]] bool MessageMatchesCriteria(const nlohmann::json &message, const SearchCriteria &criteria,
                                            const AhoCorasick *matcher = nullptr);
} // namespace mailcartcore
