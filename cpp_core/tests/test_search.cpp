// Catch2 port of the matcher/parsing subset of tests/python/test_matchy_mailcart_api.py.
#include <catch2/catch_test_macros.hpp>

#include <string>
#include <vector>

#include "mailcartcore/api_error.hpp"
#include "mailcartcore/search.hpp"

using mailcartcore::AhoCorasick;
using mailcartcore::ApiError;
using mailcartcore::BuildCriteriaMatcher;
using mailcartcore::ExtractBodyText;
using mailcartcore::MessageMatchesCriteria;
using mailcartcore::NormalizeSearchText;
using mailcartcore::ParseIsoDate;
using mailcartcore::ParseReceivedAtDate;
using mailcartcore::ParseScopedQuery;
using mailcartcore::SearchCriteria;
using mailcartcore::StripHtml;

namespace
{
  nlohmann::json MakeMessage(const std::string &message_id, const std::string &subject,
                             const std::string &sender, const std::string &body_content,
                             const std::string &body_content_type = "text",
                             const std::string &received_at = "2026-04-15T12:00:00Z")
  { return nlohmann::json{
        {"id", message_id},
        {"subject", subject},
        {"bodyPreview", ""},
        {"body", {{"contentType", body_content_type}, {"content", body_content}}},
        {"from", {{"emailAddress", {{"address", sender}}}}},
        {"receivedDateTime", received_at},
    };
  }
} // namespace

// #R050-T01: Aho-Corasick reports all substring hits in one pass.
TEST_CASE("AhoCorasick single-pass substring search", "[search]")
{ const AhoCorasick matcher({"coffee", "order", "absent"});
  CHECK(matcher.Search("your coffee order is ready") == std::set<std::string>{"coffee", "order"});
}

// #R050-T01: Aho-Corasick handles overlapping suffix patterns.
TEST_CASE("AhoCorasick overlapping suffix patterns", "[search]")
{ const AhoCorasick matcher({"he", "she", "his", "hers"});
  CHECK(matcher.Search("ushers") == std::set<std::string>{"she", "he", "hers"});
}

// #R050-T01: empty patterns never match.
TEST_CASE("AhoCorasick ignores empty patterns", "[search]")
{ const AhoCorasick matcher({"", "x"});
  CHECK(matcher.Search("anything").empty());
}

// #R050-T01: Aho-Corasick matches a naive substring scan across a corpus.
TEST_CASE("AhoCorasick matches naive scan across corpus", "[search]")
{ const std::vector<std::vector<std::string>> pattern_sets{
      {"a", "ab", "bab", "bc", "bca", "c", "caa"},
      {"he", "she", "his", "hers"},
      {"aa", "aaa", "aaaa", "baaa"},
      {"abc", "bcd", "cde", "de"},
  };
  const std::string alphabet = "abcde";
  for (const auto &patterns : pattern_sets)
  { const AhoCorasick matcher(patterns);
    // Enumerate all strings over {a..e} up to length 4 (bounded for runtime).
    std::vector<std::string> texts{""};
    for (int length = 0; length < 4; ++length)
    { std::vector<std::string> next;
      for (const auto &text : texts)
      { for (char symbol : alphabet)
        { next.push_back(text + symbol);
        }
      }
      for (const auto &text : next)
      { std::set<std::string> expected;
        for (const auto &pattern : patterns)
        { if (!pattern.empty() && text.find(pattern) != std::string::npos)
          { expected.insert(pattern);
          }
        }
        CHECK(matcher.Search(text) == expected);
      }
      texts = next;
    }
  }
}

// #R020-T01: field-scoped tokens parse independently with AND semantics.
TEST_CASE("ParseScopedQuery parses scoped tokens", "[search]")
{ const SearchCriteria criteria = ParseScopedQuery("subject:doordash body:tacombi from:2026-04-09 to:2026-07-08");
  REQUIRE(criteria.subject.size() == 1);
  CHECK(criteria.subject[0] == "doordash");
  REQUIRE(criteria.body.size() == 1);
  CHECK(criteria.body[0] == "tacombi");
  REQUIRE(criteria.from_date.has_value());
  CHECK(criteria.from_date->Iso() == "2026-04-09");
  REQUIRE(criteria.to_date.has_value());
  CHECK(criteria.to_date->Iso() == "2026-07-08");
}

// #R020-T01: invalid or unscoped tokens raise 400.
TEST_CASE("ParseScopedQuery rejects unscoped and invalid tokens", "[search]")
{ CHECK_THROWS_AS(ParseScopedQuery("doordash"), ApiError);
  CHECK_THROWS_AS(ParseScopedQuery("foo:bar"), ApiError);
  CHECK_THROWS_AS(ParseScopedQuery("junk subject:receipt"), ApiError);
  CHECK_THROWS_AS(ParseScopedQuery("from:2026-04-01 from:2026-04-02"), ApiError);
  CHECK_THROWS_AS(ParseScopedQuery("from:2026-05-01 to:2026-04-01"), ApiError);
  CHECK_THROWS_AS(ParseScopedQuery("from:not-a-date"), ApiError);
  CHECK_THROWS_AS(ParseScopedQuery("subject:"), ApiError);
}

// #R020: empty query yields empty criteria.
TEST_CASE("ParseScopedQuery accepts empty queries", "[search]")
{ const SearchCriteria criteria = ParseScopedQuery("   ");
  CHECK(criteria.subject.empty());
  CHECK(criteria.sender.empty());
  CHECK(criteria.body.empty());
  CHECK_FALSE(criteria.from_date.has_value());
  CHECK_FALSE(criteria.to_date.has_value());
}

// #R020-T01: whitespace normalization and case folding before matching.
TEST_CASE("NormalizeSearchText collapses whitespace and lowercases", "[search]")
{ CHECK(NormalizeSearchText("  DoorDash   order    total ") == "doordash order total");
}

// #R020: HTML bodies are stripped to searchable text.
TEST_CASE("StripHtml removes tags, scripts, and entities", "[search]")
{ CHECK(StripHtml("<p>Hello <b>world</b></p>") == " Hello  world  ");
  CHECK(StripHtml("a<script type=\"x\">ignored</script>b") == "a b");
  CHECK(StripHtml("<style>p{}</style>text") == " text");
  CHECK(StripHtml("Tom &amp; Jerry &lt;3") == "Tom & Jerry <3");
}

// #R020: body extraction prefers full content with preview fallback.
TEST_CASE("ExtractBodyText prefers typed content", "[search]")
{ nlohmann::json html_message = MakeMessage("m1", "s", "x@example.com", "<p>DoorDash</p>", "html");
  CHECK(ExtractBodyText(html_message).find("DoorDash") != std::string::npos);
  nlohmann::json text_message = MakeMessage("m2", "s", "x@example.com", "plain body", "text");
  CHECK(ExtractBodyText(text_message) == "plain body");
  nlohmann::json unknown{{"bodyPreview", "preview text"}, {"body", {{"contentType", "weird"}, {"content", "zzz"}}}};
  CHECK(ExtractBodyText(unknown) == "preview text");
}

// #R610-T01: receivedDateTime parser returns nullopt for blank/invalid inputs.
TEST_CASE("ParseReceivedAtDate handles blank and invalid values", "[search]")
{ CHECK_FALSE(ParseReceivedAtDate("").has_value());
  CHECK_FALSE(ParseReceivedAtDate("not-a-date").has_value());
  CHECK(ParseReceivedAtDate("2026-05-01T01:02:03Z").has_value());
  CHECK(ParseReceivedAtDate("2026-05-01").has_value());
}

// #R020-T01: strict yyyy-mm-dd parsing for from:/to: filters.
TEST_CASE("ParseIsoDate enforces strict format and real dates", "[search]")
{ CHECK(ParseIsoDate("2026-02-28").has_value());
  CHECK_FALSE(ParseIsoDate("2026-02-30").has_value());
  CHECK_FALSE(ParseIsoDate("2026-13-01").has_value());
  CHECK_FALSE(ParseIsoDate("26-01-01").has_value());
  CHECK_FALSE(ParseIsoDate("2026/01/01").has_value());
  CHECK(ParseIsoDate("2024-02-29").has_value()); // leap year
  CHECK_FALSE(ParseIsoDate("2023-02-29").has_value());
}

// #R050-T01: prebuilt matcher preserves AND semantics.
TEST_CASE("MessageMatchesCriteria applies AND semantics", "[search]")
{ SearchCriteria criteria;
  criteria.subject = {"receipt"};
  criteria.body = {"doordash"};
  const AhoCorasick matcher = BuildCriteriaMatcher(criteria);
  const nlohmann::json match =
      MakeMessage("m1", "Your Receipt", "noreply@store.com", "DoorDash order total");
  const nlohmann::json miss = MakeMessage("m2", "Your Receipt", "noreply@store.com", "unrelated body");
  CHECK(MessageMatchesCriteria(match, criteria, &matcher));
  CHECK_FALSE(MessageMatchesCriteria(miss, criteria, &matcher));
}

// #R050-T01: matcher is built on demand when absent.
TEST_CASE("MessageMatchesCriteria builds matcher when absent", "[search]")
{ SearchCriteria criteria;
  criteria.sender = {"doordash"};
  const nlohmann::json match = MakeMessage("m1", "x", "orders@doordash.com", "");
  CHECK(MessageMatchesCriteria(match, criteria));
}

// #R020-T01: from:/to: date bounds are inclusive.
TEST_CASE("Date bounds are inclusive", "[search]")
{ SearchCriteria criteria = ParseScopedQuery("from:2026-04-01 to:2026-04-30");
  CHECK(MessageMatchesCriteria(MakeMessage("start", "", "", "", "text", "2026-04-01T00:00:00Z"), criteria));
  CHECK(MessageMatchesCriteria(MakeMessage("end", "", "", "", "text", "2026-04-30T23:59:59Z"), criteria));
  CHECK_FALSE(MessageMatchesCriteria(MakeMessage("before", "", "", "", "text", "2026-03-31T23:59:59Z"), criteria));
  CHECK_FALSE(MessageMatchesCriteria(MakeMessage("after", "", "", "", "text", "2026-05-01T00:00:00Z"), criteria));
}
