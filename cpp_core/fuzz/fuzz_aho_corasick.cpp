// libFuzzer target for the Aho-Corasick multi-pattern matcher (port of the
// AhoCorasick class in scripts/matchy_mailcart_api.py). The input is split on
// NUL bytes into [pattern, pattern, ..., text]; the final segment is the text
// scanned for every preceding pattern.
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "mailcartcore/search.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{ std::vector<std::string> segments;
  std::string current;
  for (size_t index = 0; index < size; ++index)
  { if (data[index] == 0)
    { segments.push_back(current);
      current.clear();
    }
    else
    { current.push_back(static_cast<char>(data[index]));
    }
  }
  segments.push_back(current);

  std::string text = segments.back();
  segments.pop_back();

  const mailcartcore::AhoCorasick matcher(segments);
  const std::set<std::string> hits = matcher.Search(text);

  // Every reported hit must actually occur as a substring of the scanned text.
  for (const std::string &hit : hits)
  { if (!hit.empty() && text.find(hit) == std::string::npos)
    { __builtin_trap();
    }
  }
  return 0;
}
